# Benchmark — V1

Hardware: x86_64-linux-gnu, Perl 5.38.2.
Workload: 200 generated `.t` files, each running 3 trivial `Test::More` ok-asserts (600 assertions total).
Generator: `xt/bench/gen-fixtures.pl /tmp/app-prover-bench 200`.

| jobs | app-prover     | prove          | notes                            |
|------|----------------|----------------|----------------------------------|
| -j1  | 10.87s @ 102%  | 11.68s @ 101%  | app-prover ~7% faster            |
| -j8  | 5.02s          | 4.89s          | tied                             |
| -j16 | 4.98s @ 335%   | 4.89s @ 332%   | tied; both bottlenecked          |

Yath was not available on the bench host (`yath: No Test2::Harness (App::Yath)
versions appear to be installed`), so a yath comparison is pending.

## Reading the numbers

At `-j16` neither runner saturates 16 cores — both top out around ~335% CPU
utilization. The bottleneck is **per-test perl startup**, not parallelism: each
trivial test forks a fresh `perl`, loads `Test::More`, runs three asserts, and
exits. Parallelism only helps until the system runs out of disk/IO bandwidth
for fork+exec; beyond that we wait.

This matches the V1 plan's stated tradeoff: without preload, App::Prover
matches `prove` on real-world suites; it does not beat preload-enabled Yath
(where modules are loaded once and forked for each test).

## To beat the bottleneck (V2)

The headline speedup is **preload** — a long-lived parent perl with the test
environment pre-loaded that fork-per-tests skip the `perl` startup cost. This
is out of scope for V1 (see `AI_IMPLEMENTATION_PLAN.md` "Risks / things
explicitly deferred").

Other future levers:

- Reduce per-event MCE round-trip overhead. Today each parser event becomes a
  synchronous `MCE->do(...)` round-trip; on a verbose suite with many diags,
  this dominates. Batching events (one `MCE->do` per N events, or per test)
  is straightforward.
- Disable the per-test `_close_inherited_fds` scan if we can guarantee no
  inherited fds (via `O_CLOEXEC` discipline at MCE init).
