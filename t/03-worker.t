use strict;
use warnings;
use Test::More;
use FindBin ();
use File::Spec ();

use App::Prover::Worker ();
use App::Prover::Backend::TAP ();
use App::Prover::Event qw(:types);

my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');

sub run_fixture {
    my ($name) = @_;
    my $file = File::Spec->catfile($fixtures, $name);
    my @events;
    my $result = App::Prover::Worker::run(
        file    => $file,
        backend => App::Prover::Backend::TAP->new,
        emit    => sub { push @events, $_[0] },
    );
    return ($result, \@events);
}

subtest 'pass.t' => sub {
    my ($r, $events) = run_fixture('pass.t');
    is $r->{exit}, 0, 'exit code 0';
    my @started = grep { $_->{type} eq EV_STARTED } @$events;
    my @ended   = grep { $_->{type} eq EV_ENDED   } @$events;
    is scalar(@started), 1, 'one started event';
    is scalar(@ended),   1, 'one ended event';
    is $started[0]->{type}, 'started', 'started event is first';
    is $ended[0]->{exit}, 0, 'ended event carries exit';
    my @tests = grep { $_->{type} eq EV_TEST } @$events;
    is scalar(@tests), 3, 'three test results';
    ok $_->{ok}, "test $_->{test_num} ok" for @tests;
};

subtest 'fail.t' => sub {
    my ($r, $events) = run_fixture('fail.t');
    isnt $r->{exit}, 0, 'non-zero exit';
    my @tests = grep { $_->{type} eq EV_TEST } @$events;
    is scalar(@tests), 3, 'three tests';
    is $tests[1]->{ok}, 0, 'second test failed';
};

subtest 'bail.t' => sub {
    my ($r, $events) = run_fixture('bail.t');
    my @bails = grep { $_->{type} eq EV_BAILOUT } @$events;
    is scalar(@bails), 1, 'one bailout event';
    like $bails[0]->{bailout}, qr/fixture bail/, 'bailout reason captured';
};

subtest 'plan-at-end.t' => sub {
    my ($r, $events) = run_fixture('plan-at-end.t');
    is $r->{exit}, 0, 'exit ok';
    my @plans = grep { $_->{type} eq EV_PLAN } @$events;
    is scalar(@plans), 1, 'one plan event';
    is $plans[0]->{plan}{count}, 2, 'plan count 2';
    my @tests = grep { $_->{type} eq EV_TEST } @$events;
    is scalar(@tests), 2, 'two tests';
};

subtest 'noisy.t' => sub {
    my ($r, $events) = run_fixture('noisy.t');
    is $r->{exit}, 0, 'exit ok';
    my @comments = grep { $_->{type} eq EV_COMMENT } @$events;
    ok scalar(@comments) >= 5, 'got several comment events';
};

done_testing;
