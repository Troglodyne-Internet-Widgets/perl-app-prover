use strict;
use warnings;

use FindBin::libs;
use Test::More;

use Log::Dispatch ();
use App::Prover::Sink::Log ();
use App::Prover::Event qw(:types new_event);

# Build a Log::Dispatch instance backed by an in-memory string at min_level.
sub mk_log {
    my ($min_level) = @_;
    my $buf = '';
    my $log = Log::Dispatch->new(
        outputs => [
            [
                'Code',
                min_level => $min_level,
                code      => sub {
                    my %p = @_;
                    $buf .= $p{message} . "\n";
                },
            ],
        ],
    );
    return ($log, \$buf);
}

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

subtest 'live: streams every event at info+' => sub {
    my ($log, $out) = mk_log('info');
    my $sink = App::Prover::Sink::Log->new(log => $log, live => 1);
    $sink->emit($_) for events_pass('j1', 't/p.t');

    like $$out, qr/=== t\/p.t ===/,    'started banner';
    like $$out, qr/^ok 1 - first$/m,   'first test line';
    like $$out, qr/^ok 2 - second$/m,  'second test line';
    like $$out, qr/--- t\/p.t ok/,     'ended banner';
};

subtest 'buffered pass: one notice line, no per-test detail at notice' => sub {
    my ($log, $out) = mk_log('notice');
    my $sink = App::Prover::Sink::Log->new(log => $log);  # live=0 default
    $sink->emit($_) for events_pass('j2', 't/q.t');
    $sink->flush_job('j2', 'pass');

    like   $$out, qr/^ok t\/q.t \(/m,  'one ok summary line';
    unlike $$out, qr/ok 1 - first/,    'no per-test detail at notice';
};

subtest 'buffered fail at notice: FAIL banner + the failing line, but not passing details' => sub {
    my ($log, $out) = mk_log('notice');
    my $sink = App::Prover::Sink::Log->new(log => $log);
    $sink->emit($_) for events_fail('j3', 't/f.t');
    $sink->flush_job('j3', 'fail');

    like $$out, qr/FAIL: t\/f.t/,        'fail banner';
    like $$out, qr/not ok 1 - boom/,     'failing line dumped (error level passes notice filter)';
    like $$out, qr/end t\/f.t/,          'end banner';
};

subtest 'buffered fail at info: FAIL banner replays passing TAP too' => sub {
    my ($log, $out) = mk_log('info');
    my $sink = App::Prover::Sink::Log->new(log => $log);
    my $job = 'j4';
    $sink->emit($_) for (
        new_event(job_id => $job, file => 't/m.t', type => EV_STARTED),
        new_event(job_id => $job, file => 't/m.t', type => EV_PLAN, raw => '1..2', plan => { count => 2 }),
        new_event(job_id => $job, file => 't/m.t', type => EV_TEST, raw => 'ok 1 - one',     ok => 1, test_num => 1),
        new_event(job_id => $job, file => 't/m.t', type => EV_TEST, raw => 'not ok 2 - two', ok => 0, test_num => 2),
        new_event(job_id => $job, file => 't/m.t', type => EV_ENDED, exit => 1, elapsed_ms => 10),
    );
    $sink->flush_job($job, 'fail');

    like $$out, qr/FAIL: t\/m.t/,    'fail banner';
    like $$out, qr/^ok 1 - one$/m,   'passing TAP replayed at info';
    like $$out, qr/not ok 2 - two/,  'failing TAP replayed';
};

subtest 'buffered: error min_level shows only failures' => sub {
    my ($log, $out) = mk_log('error');
    my $sink = App::Prover::Sink::Log->new(log => $log);
    $sink->emit($_) for events_fail('j5', 't/e.t');
    $sink->flush_job('j5', 'fail');

    like   $$out, qr/FAIL: t\/e.t/,       'fail banner present at error';
    like   $$out, qr/not ok 1 - boom/,    'failing line shown';
    unlike $$out, qr/^1\.\.1$/m,          'plan filtered out at error level';
};

subtest 'buffered: passing file under error min_level emits nothing' => sub {
    my ($log, $out) = mk_log('error');
    my $sink = App::Prover::Sink::Log->new(log => $log);
    $sink->emit($_) for events_pass('j6', 't/silent.t');
    $sink->flush_job('j6', 'pass');

    is $$out, '', 'no output for passing file at error min_level';
};

done_testing;
