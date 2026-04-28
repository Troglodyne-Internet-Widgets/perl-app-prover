use strict;
use warnings;

use FindBin::libs;
use Test::More;

BEGIN {
    eval { require Test2::Harness2::Collector::Parser::TapParser; 1 }
        or plan skip_all => 'Test2::Harness not installed';
}

use App::Prover::Backend::Test2 ();
use App::Prover::Event qw(:types);

my $tap = <<'TAP';
TAP version 13
1..3
ok 1 - first
not ok 2 - second
ok 3 - third # SKIP not ready
# diagnostic
TAP

open my $fh, '<', \$tap or die $!;

my @events;
my $backend = App::Prover::Backend::Test2->new;
my $parser  = $backend->parse(
    sub { push @events, $_[0] },
    $fh,
    undef,
    { file => 'inline.t' },
);

isa_ok $parser, 'App::Prover::Backend::Test2::_FakeParser';

is $parser->tests_run, 3, 'tests_run = 3';
is $parser->passed, 2, 'passed = 2 (ok 1 + ok 3 SKIP)';
is $parser->failed, 1, 'failed = 1';
is $parser->skipped, 1, 'skipped = 1';

my @tests = grep { $_->{type} eq EV_TEST } @events;
is scalar(@tests), 3, '3 test events';
is $tests[0]->{ok}, 1, 'first ok';
is $tests[1]->{ok}, 0, 'second not ok';
is $tests[2]->{directive}, 'SKIP', 'third SKIP directive';
ok exists $tests[0]->{facet_data}, 'facet_data passed through';

my @plans = grep { $_->{type} eq EV_PLAN } @events;
is scalar(@plans), 1, 'one plan event';
is $plans[0]->{plan}{count}, 3, 'plan count 3';

done_testing;
