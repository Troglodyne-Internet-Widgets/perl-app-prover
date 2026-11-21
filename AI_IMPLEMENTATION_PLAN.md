# App::Prover — V1 Implementation Plan

## Context

`perl-app-prover` is a fresh repo (only the README is committed) for a new test runner script aimed at "as simple as possible, but with most of the power of `App::Prove` / `App::Yath::Script`," and ideally faster than both on large parallel test loads.

The README sketches: MCE-driven concurrency, Log::Dispatch-driven output, no plugins, an "agnostic" harness backend, and a future per-test slot dashboard ("extra credit"). Research into the local sources of Test2-Harness 2.0, TAP::Harness, and MCE clarified that several of those ideas need tightening before code can be written:

- `Test2::Harness2` is a service, not a library; "pluggable harness backend" only makes sense at the **parser** level (TAP vs Test2 facets), not the orchestrator level — both compete for scheduling.
- `MCE::Flow` already provides real-time worker→manager streaming via `user_output`/`MCE->do(...)`; `MCE::Hobo + MCE::Shared` is overkill for one-way event streams.
- Yath2's main speed feature (preload) is currently disabled in its v2 branch, so the speed bar is lower than the README implies — but a no-preload App::Prover will still not beat a preload-enabled Yath on big codebases. Preload is explicitly **out of scope for V1** per locked decisions below.
- `TAP::Parser::Aggregator` is the right shape for the run summary; reuse it instead of reinventing.

## Locked decisions (from Q&A)

| # | Decision |
|---|----------|
| Backend scope | **Parser-level only.** MCE always orchestrates. The "backend" is which parser turns a single test's stdout into normalized events. V1 ships `TAP` (built on `TAP::Parser`) plus an optional `Test2` backend (built on `Test2::Harness2::Collector::Parser::TapParser`) gated on the dep being installed. |
| Preload | **Out of scope for V1.** Defer to V2. The plan does not introduce a long-lived parent or fork-server. |
| Prove compat | **Common subset.** Ship `-l -b -I -M -r -v --ext --shuffle --reverse -j --timer` + the `HARNESS_*` env vars. Skip `.proverc`, `--state`, archives, plugins. |

## Architecture

```
                          ┌─────────────────────┐
                          │  bin/prover     │   CLI entry, parses argv,
                          │  (or bin/prover)    │   builds run config
                          └──────────┬──────────┘
                                     │
                          ┌──────────▼──────────┐
                          │  App::Prover        │   Orchestration façade
                          │  ::Runner           │   (test discovery, ordering,
                          │                     │    starts MCE::Flow,
                          │  - holds aggregator │    receives per-event
                          │  - holds sinks      │    callbacks, drives sinks,
                          │  - holds buffers    │    prints summary)
                          └──────────┬──────────┘
                                     │ MCE::Flow over @test_files
            ┌────────────────────────┼────────────────────────┐
            │                        │                        │
   ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
   │ MCE worker      │      │ MCE worker      │      │ MCE worker      │
   │ App::Prover::   │      │ ...             │      │ ...             │
   │ ::Worker::run   │      │                 │      │                 │
   │  - fork+exec    │      │                 │      │                 │
   │    test under   │      │                 │      │                 │
   │    perl         │      │                 │      │                 │
   │  - feed stdout  │      │                 │      │                 │
   │    to Backend   │      │                 │      │                 │
   │  - per event:   │      │                 │      │                 │
   │    MCE->do(     │      │                 │      │                 │
   │     'on_event', │      │                 │      │                 │
   │     $event)     │      │                 │      │                 │
   └─────────────────┘      └─────────────────┘      └─────────────────┘
```

### Concurrency primitive

**MCE::Flow** with `max_workers => $jobs`, chunking by single test (`chunk_size => 1`), workers stream events to manager via **`MCE->do('on_event', $event_hashref)`**. The manager-side `on_event` is registered when MCE is spawned (`user_tasks => [{ ... }]` and a top-level sub).

- Pros: structured payload (no JSON tax), in-order delivery per worker, real-time invocation in manager.
- Alternative considered: `MCE->print(JSON-encoded line)` + `user_output` callback. Rejected because (a) JSON encode/decode tax per event, (b) muddies stdout if anything else needs to print.
- Alternative considered: `MCE::Hobo + MCE::Channel`. Rejected for V1 simplicity — MCE::Flow already covers the case.

### Output ordering ("the verbose-with-j>1 problem")

The manager keeps a **per-`job_id` buffer**. On `test_started` it opens a buffer; on each event it appends; on `test_ended` it decides what to do based on flush policy:

- `-j 1` + `-v`: flush every event live (verbose). No buffering needed at manager.
- `-j > 1`: **QVF behavior is the default.** Buffer per job; flush full output only if FAIL/error/timeout; otherwise emit one summary line.
- `-j 1` + no `-v`: dot-style progress, summary at end.
- Slot dashboard mode: deferred (this is the README "extra credit" — left out per user instruction).

### End-of-run summary

Reuse `TAP::Parser::Aggregator` (`/usr/share/perl/5.38/TAP/Parser/Aggregator.pm`). Each Worker, after the test exits, returns its drained `TAP::Parser` instance (or for the Test2 backend, a synthesized parser-shaped object) via the MCE return value. Runner calls `$aggregator->add($desc, $parser)` for each. Then renders the standard prove-style summary.

## Module layout (lib/)

| Path | Role |
|------|------|
| `App/Prover.pm` | Thin façade. `App::Prover->new(\%opts)->run(@files)`. Mostly delegates to Runner. |
| `App/Prover/CLI.pm` | argv → `\%opts`. `Getopt::Long`. Implements the prove subset. |
| `App/Prover/Runner.pm` | Test discovery, ordering, MCE::Flow setup, per-job buffer, manager-side `on_event` callback, aggregator, summary. |
| `App/Prover/Worker.pm` | Per-test executor. fork+exec under perl; pipes stdout/stderr; feeds Backend; emits events via `MCE->do`. |
| `App/Prover/Backend.pm` | Backend role/parent. Single contract: `parse(\&emit, $stdout_fh, $stderr_fh, \%ctx)` runs to EOF. |
| `App/Prover/Backend/TAP.pm` | Wraps `TAP::Parser`. Default. |
| `App/Prover/Backend/Test2.pm` | Wraps `Test2::Harness2::Collector::Parser::TapParser`. Optional dep; lazy-loaded. |
| `App/Prover/Event.pm` | Normalized event hashref helpers + constants. |
| `App/Prover/Sink.pm` | Sink role: `emit($event)`, `flush_job($job_id, $verdict)`, `summary($aggregator)`. |
| `App/Prover/Sink/QVF.pm` | Default for `-j > 1`. Buffers, flushes on fail. |
| `App/Prover/Sink/Verbose.pm` | Streams every event. Default for `-v -j 1`. |
| `App/Prover/Sink/JSONL.pm` | Optional. One JSON event per line. |
| `App/Prover/Sink/LogDispatch.pm` | Optional. Wraps a `Log::Dispatch` instance; severity = `info` for results, `notice` for diags, `error` for FAIL. |
| `bin/prover` (or `bin/prover`) | `#!perl` shim → `App::Prover::CLI`. |

Naming: avoiding "Collector" because Test2::Harness2 already owns that name with a specific shape; `Worker` is unambiguous.

Sink interface as a tiny role rather than forcing everything through `Log::Dispatch` (which is a log-*levels* abstraction; using it as the only event bus would be square-peg work). Log::Dispatch is one available sink.

## Data shapes

### Normalized Event

```perl
{
    job_id      => $job_id,                    # uint, monotonically assigned by Runner
    type        => 'test'|'plan'|'comment'|'bailout'|'unknown'|'started'|'ended',
    raw         => $original_line,             # for type=test/plan/comment/etc, undef for synthetic
    ok          => 0|1,                        # type=test only
    test_num    => $n,                         # type=test only
    description => $str,                       # type=test only
    directive   => 'TODO'|'SKIP'|undef,        # type=test only
    explanation => $str,                       # type=test only, reason for TODO/SKIP
    plan        => { count => $n, skip_all => 0|1, reason => $str },  # type=plan only
    bailout     => $str,                       # type=bailout only
    elapsed_ms  => $n,                         # type=ended only
    exit        => $code,                      # type=ended only
    file        => $path,                      # all types, set by Worker
    timestamp   => $hires,                     # all types
}
```

This is intentionally TAP-shaped (it's what V1 actually emits). The Test2 backend will project relevant facets onto these fields and pass through facet data verbatim under an optional `facet_data` key.

### Backend contract

```perl
package App::Prover::Backend::TAP;
sub new { ... }
# Drains stdout/stderr to EOF; calls $emit->($event) per normalized event;
# returns the (post-drain) parser/aggregator-feedable object.
sub parse {
    my ($self, $emit, $stdout, $stderr, $ctx) = @_;
    ...;
    return $parser;   # opaque to caller; Runner only uses it for aggregator->add()
}
```

### Worker contract

```perl
sub App::Prover::Worker::run {
    my ($mce, $chunk_ref) = @_;          # MCE::Flow signature
    my $file = $chunk_ref->[0];
    my $job_id = $mce->wid . ':' . $$ . ':' . ++$JOB_SEQ;
    my $emit = sub { $mce->do('on_event', { %{$_[0]}, job_id => $job_id, file => $file }) };

    $emit->({ type => 'started', file => $file });
    my ($stdout, $stderr, $pid) = _spawn_test($file, \%env);   # IPC::Open3 style
    my $parser = $BACKEND->parse($emit, $stdout, $stderr, { file => $file });
    waitpid $pid, 0;
    $emit->({ type => 'ended', exit => $?, elapsed_ms => ... });
    return { job_id => $job_id, file => $file, parser => $parser, exit => $? };
}
```

### Sink contract

```perl
package App::Prover::Sink;
sub emit       { my ($self, $event) = @_; ... }       # called per event in arrival order
sub flush_job  { my ($self, $job_id, $verdict) = @_; ... }  # 'pass'|'fail'|'skip'|'todo'
sub summary    { my ($self, $aggregator) = @_; ... }
```

## CLI surface (V1)

```
prover [options] [TEST_FILES_OR_DIRS]

  -j N, --jobs N         Concurrency (default: $ENV{HARNESS_JOBS} || 1)
  -l, --lib              Add ./lib to @INC
  -b, --blib             Add ./blib/lib and ./blib/arch to @INC
  -I PATH                Add PATH to @INC (repeatable)
  -M MODULE              -mMODULE for tests (repeatable)
  -r, --recurse          Recurse into directories
  -v, --verbose          Verbose: with -j 1 streams; with -j>1 still QVF (warn user)
  --ext EXT              File extension to discover (default: .t, repeatable)
  --shuffle              Shuffle test order
  --reverse              Reverse test order
  --timer                Show per-test elapsed time
  --backend NAME         tap (default) | test2
  --log-dispatch CONFIG  Optional Log::Dispatch wiring (path or module)
  --version, --help
```

Env vars set in worker before exec (mimicking prove): `HARNESS_ACTIVE=1`, `HARNESS_VERSION=$VERSION`, `HARNESS_IS_VERBOSE=0|1`, `HARNESS_JOBS=$jobs`. Discovery: no args → `t/` then `xt/` if present. `--ext` filtering. With `-r`, recurse; without, top-level only.

## Implementation steps

1. **Repo scaffolding.** `dist.ini` (Dist::Zilla) or plain `Makefile.PL`. Pick `Makefile.PL` — fewer deps, matches App::Prove/Yath. Add `lib/` and `bin/` skeletons. Declare deps: `MCE >= 1.9`, `TAP::Parser` (core), `Time::HiRes` (core). Optional: `Test2::Harness`, `Log::Dispatch`. Pin `MCE` to a known-good version range.
2. **Event + Backend role + TAP backend.** `App::Prover::Event`, `App::Prover::Backend::TAP`. Unit test: feed in-memory TAP, assert normalized events.
3. **Worker (no MCE yet).** Synchronous `App::Prover::Worker::run` that fork+execs perl on a `.t` file, drains via Backend, calls a passed-in `$emit`. Unit test against fixture `.t` files in `corpus/`.
4. **Sinks.** `Sink` role + `Sink::Verbose` + `Sink::QVF`. Unit test against pre-recorded event streams.
5. **Runner without MCE.** Wire Worker → Sink directly (`-j 1` mode) feeding `TAP::Parser::Aggregator`. Verify summary line matches prove's format closely enough.
6. **Add MCE::Flow.** Replace direct call with `MCE::Flow::run`. Manager registers `on_event` and per-job buffer logic. Verify event-arrival ordering inside a job; cross-job ordering may interleave at the buffer flush boundary, which is fine for QVF.
7. **CLI.** `App::Prover::CLI` with `Getopt::Long`. Wire to Runner. Implement test discovery, `-l/-b/-I/-M`, `--ext`, `--shuffle`, `--reverse`, `--timer`. Set HARNESS_* env. Add `bin/prover`.
8. **Optional sinks.** `Sink::JSONL`, `Sink::LogDispatch` (deferred load).
9. **Optional Test2 backend.** `App::Prover::Backend::Test2` wrapping `Test2::Harness2::Collector::Parser::TapParser`. Lazy-require; if missing, `--backend test2` errors clearly.
10. **End-to-end smoke + benchmark.** Run against (a) own test suite, (b) a checkout of `Test2-Suite` or `Mojolicious` test dir, (c) a synthetic 1000-tiny-tests fixture. Benchmark against `prove -j 16` and `yath test -j 16`.

## Critical existing files / functions to reuse

- `TAP::Parser` (`/usr/share/perl/5.38/TAP/Parser.pm`) — the per-test event source for the TAP backend. Use `->new({source => $fh})` then loop on `->next`.
- `TAP::Parser::Aggregator` (`/usr/share/perl/5.38/TAP/Parser/Aggregator.pm`) — end-of-run summary. `->add($desc, $parser)` per test, then read counts.
- `Test2::Harness2::Collector::Parser::TapParser` (`/home/teo/git/Test2-Harness/lib/Test2/Harness2/Collector/Parser/TapParser.pm`) — only needed for the optional `Test2` backend; emits Test2 facets from TAP. Treat as optional dep.
- `MCE::Flow` (`/home/teo/git/local/lib/perl5/MCE/Flow.pm`) — orchestration. Use `MCE->do(...)` for streaming events to manager; `gather` or task return values for per-test parser handoff.

What we are explicitly **not** reusing:
- `App::Prove` — too entangled with `.proverc`, state file, plugin system. We re-do CLI parsing minimally.
- `Test2::Harness2` (the service, not the parser class) — would compete with MCE for scheduling.
- `App::Prove::Yath` — not a harness abstraction, just a CLI translator.

## Verification

End-to-end checks (Runner + Worker + Sink + Backend + MCE):

1. **Fixture directory** (`corpus/`): `pass.t`, `fail.t`, `skip.t`, `todo.t`, `bail.t`, `plan-at-end.t`, `slow.t` (sleeps 1s), `noisy.t` (lots of `diag`).
2. **Single-job runs:** `prover -j1 -v corpus/` — assert verbose stream matches expected fixture transcript.
3. **Parallel runs:** `prover -j8 corpus/` — assert exit code; assert QVF behavior (no verbose output for passing files, full output for `fail.t` and `bail.t`); assert summary matches.
4. **Determinism:** Run with `--reverse` and verify results identical except order.
5. **Backend swap:** `--backend test2` against same fixtures; assert same pass/fail verdicts.
6. **Discovery:** Run with no args inside a fixture project that has `t/` and `xt/`; verify only `t/` is picked up by default.
7. **Compare summary line** against `prove` output on the same fixtures (test count, pass/fail/skip totals).
8. **Benchmark** (manual, after V1): `time prover -j16` vs `time prove -j16` vs `time yath test -j16` on a fixture of 1000 trivial `.t` files. Document numbers in the README.
9. **Real-world sanity:** Run against `cpan -g Mojolicious` test dir; compare exit code with `prove`.

## Risks / things explicitly deferred

- **Slot-based dashboard renderer.** README "extra credit" — out of V1.
- **Preload.** Out of V1. Will require a separate persistent-parent design and probably a different CLI mode.
- **`.proverc`, `--state=failed,save`, archives, plugins.** Out of V1 scope.
- **Test2 native event stream (non-TAP)** beyond what `Collector::Parser::TapParser` produces. Out of V1.
- **Speed claim vs Yath2 on real codebases.** Without preload, App::Prover will likely be roughly equivalent to a preload-disabled Yath, faster than `prove -j` on suites where TAP::Harness's IO::Select multiplexer is the bottleneck, and slower than a preload-enabled Yath on big codebases. The README's "faster than both" claim should be softened in our README to "faster than `prove`; comparable to `yath test` without preload; slower than `yath test` with preload" until V2 lands preload.
- **Windows.** `IPC::Open3` and MCE::Flow both work on Windows; we don't try to be clever. Untested in V1.
