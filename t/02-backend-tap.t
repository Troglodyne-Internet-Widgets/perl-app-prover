use strict;
use warnings;
use Test::More;

use App::Prover::Backend::TAP;
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
my $backend = App::Prover::Backend::TAP->new;
my $parser  = $backend->parse(
    sub { push @events, $_[0] },
    $fh,
    undef,
    { file => 'inline.t' },
);

ok $parser, 'parse returned a TAP::Parser';
isa_ok $parser, 'TAP::Parser';

my @types = map { $_->{type} } @events;
ok scalar(@events) >= 5, "got at least 5 events (got @{[ scalar @events ]})";

my @tests = grep { $_->{type} eq EV_TEST } @events;
is scalar(@tests), 3, 'three test events';
is $tests[0]->{ok}, 1, 'first test passed';
is $tests[1]->{ok}, 0, 'second test failed';
is $tests[2]->{ok}, 1, 'third test passed (SKIP)';
is $tests[2]->{directive}, 'SKIP', 'SKIP directive preserved';
like $tests[0]->{description}, qr/first/, 'description preserved';
is $tests[0]->{file}, 'inline.t', 'file context propagated';

my @plans = grep { $_->{type} eq EV_PLAN } @events;
is scalar(@plans), 1, 'one plan event';
is $plans[0]->{plan}{count}, 3, 'plan count is 3';

my @comments = grep { $_->{type} eq EV_COMMENT } @events;
ok scalar(@comments) >= 1, 'got at least one comment event';

done_testing;
