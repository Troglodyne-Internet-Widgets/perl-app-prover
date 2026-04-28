use strict;
use warnings;
use Test::More;

# Asserts the test process inherited App::Prover::TestPreloadProbe that the
# manager preloaded — no `use` directive in this file. Used by t/11-preload.t.

ok exists $INC{'App/Prover/TestPreloadProbe.pm'},
    'TestPreloadProbe.pm in %INC inherited from preload';
ok defined &App::Prover::TestPreloadProbe::ping,
    'ping() reachable without an explicit use';
is App::Prover::TestPreloadProbe::ping(), 'pong',
    'ping() returns the expected value';

done_testing;
