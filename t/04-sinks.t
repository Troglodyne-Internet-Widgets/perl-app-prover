use strict;
use warnings;
use Test::More;

use App::Prover::Sink::Verbose ();
use App::Prover::Sink::QVF     ();
use App::Prover::Event         qw(:types new_event);

sub events_pass {
    my ($job, $file) = @_;
    return (
        new_event(job_id => $job, file => $file, type => EV_STARTED),
        new_event(job_id => $job, file => $file, type => EV_PLAN, raw => '1..2', plan => { count => 2 }),
        new_event(job_id => $job, file => $file, type => EV_TEST, raw => 'ok 1 - first',  ok => 1, test_num => 1),
        new_event(job_id => $job, file => $file, type => EV_TEST, raw => 'ok 2 - second', ok => 1, test_num => 2),
        new_event(job_id => $job, file => $file, type => EV_ENDED, exit => 0, elapsed_ms => 50),
    );
}

sub events_fail {
    my ($job, $file) = @_;
    return (
        new_event(job_id => $job, file => $file, type => EV_STARTED),
        new_event(job_id => $job, file => $file, type => EV_PLAN, raw => '1..1', plan => { count => 1 }),
        new_event(job_id => $job, file => $file, type => EV_TEST, raw => 'not ok 1 - boom', ok => 0, test_num => 1),
        new_event(job_id => $job, file => $file, type => EV_ENDED, exit => 1, elapsed_ms => 10),
    );
}

subtest 'Verbose: prints every raw line' => sub {
    open my $fh, '>', \my $out or die $!;
    my $sink = App::Prover::Sink::Verbose->new(fh => $fh);
    $sink->emit($_) for events_pass('j1', 't/p.t');
    close $fh;
    like $out, qr/=== t\/p.t ===/, 'started banner';
    like $out, qr/^ok 1 - first$/m, 'first test line';
    like $out, qr/^ok 2 - second$/m, 'second test line';
    like $out, qr/--- t\/p.t ok/, 'ended banner';
};

subtest 'QVF: passing test prints one summary line' => sub {
    open my $fh, '>', \my $out or die $!;
    my $sink = App::Prover::Sink::QVF->new(fh => $fh);
    my @events = events_pass('j2', 't/q.t');
    $sink->emit($_) for @events;
    $sink->flush_job('j2', 'pass');
    close $fh;
    like $out, qr/^ok t\/q.t/m, 'one ok summary line';
    unlike $out, qr/ok 1 - first/, 'no per-test detail';
};

subtest 'QVF: failing test dumps full output' => sub {
    open my $fh, '>', \my $out or die $!;
    my $sink = App::Prover::Sink::QVF->new(fh => $fh);
    my @events = events_fail('j3', 't/f.t');
    $sink->emit($_) for @events;
    $sink->flush_job('j3', 'fail');
    close $fh;
    like $out, qr/FAIL: t\/f.t/, 'fail banner';
    like $out, qr/not ok 1 - boom/, 'failing line dumped';
    like $out, qr/end t\/f.t/, 'end banner';
};

done_testing;
