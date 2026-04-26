App::Prover
================

Goal
----
A test *runner* script (NOT a TAP harness like Test2-Harness or Test::Builder) that is
as simple as possible, but which has *most* of the "power" of advanced tools like
App::Prove or App::Yath::Script/Test2::Harness2.

Ideally this also is *faster* to execute large paralellized test loads than both
App::Prove or App::Yath::Script (benchmarked against using the 2.0 branch Test harness).

Architecture
------------
In this case I actually like the idea exodist had in App::Yath::Script where it
actually could load different versions of the harness, but would like to extend
the concept further. I should be able to use whatever harness backend I like,
partially because that means if someone has extensions to say Tap::Parser they
like and want to keep, they can yet reap the benefits of a simple and fast
test runner script without worrying about having to refactor all the things.
We also should not support plugins, as I want this to be simple. To be fair,
the better spot to integrate anyways *is* at the harness level anyways, and that
is something we ultimately want to be agnostic about.

As to concurrency, I see no benefit to using anything other than MCE for this,
partially because we can have our *collector* process which is running the test
and collecting the data to do whatever with it. Given how we're running over a
bucket of tests, this will likely be best implemented either via the MCE::Flow
or MCE::Hobo model (depending on just how integrated we need to be with MCE::Shared
to simplify IPC.

As for logging results from the collectors, this should be fairly easy to be
extensible beyond just printing to STD* via usage of Log::Dispatch, whether
this means we send to a log, a database or whatever (and makes implementing
--verbose style flages rather trivial as it already supports loglevels.

Presentationally, there is a rather tough problem to solve -- how exactly to
present data from tests that are executing *simultaneously* whilst being able
to stream the data in a manner which doesn't make you want to shoot yourself
or force -j1 to ensure test output ordering when --verbose is passed in.
The best compromise is to disregard the user's preference for -verbose when
-j value is > 1 and instead favor an output more like yath's "QVF" mode in
that case.

We could do a calculation based on the term height and setup several
"slots" to view test output as it streams on by, but that would be "extra credit"
and possibly useful to release as a module in and of itself (basically a logstream
dashboard on the CLI).
Anyways, should look something like the following FOR EACH test output:
```
#########################################################################################
path/to/test/I/am/running.t ($NUM_ASSERTIONS_RAN/$NUM_ASSERTIONS_PLANNED) [$ELAPSED_TIME]
... # Some number of test output lines, min 4, max depends on calculation
#########################################################################################
```
Esssentially, we see how many of these "slots" we can fit in your terminal, IF the -j
argument is low enough to fit in all the jobs, then split em up into the slots so you
can watch the test data roll on by beautifully.
If we're using something like -j16 or something even that breaks down, so then I would
consider forcing an output mode similar to yath's 'QVF' in that case as well.

In the meantime we're keeping track of overall run status, so that at the end we can
emit the "usual" run summary either by signaling that to the harness (if it does that)
or constructing it ourselves.

Really shouldn't be more complicated than that.
