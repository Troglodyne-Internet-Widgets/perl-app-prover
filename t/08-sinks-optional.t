use strict;
use warnings;
use Test::More;
use File::Temp ();
use File::Spec ();
use FindBin ();

use App::Prover::Sink::JSONL ();
use App::Prover::Event       qw(:types new_event);

subtest 'JSONL: writes one JSON object per line' => sub {
    my $tmp = File::Temp->new( SUFFIX => '.jsonl' );
    my $sink = App::Prover::Sink::JSONL->new( path => $tmp->filename );
    $sink->emit( new_event(type => EV_STARTED, file => 'a.t', job_id => 'j1') );
    $sink->emit( new_event(type => EV_TEST, ok => 1, test_num => 1, file => 'a.t', job_id => 'j1') );
    $sink->emit( new_event(type => EV_ENDED, exit => 0, file => 'a.t', job_id => 'j1') );
    $sink->{fh}->flush;

    open my $fh, '<', $tmp->filename or die $!;
    my @lines = <$fh>;
    is scalar(@lines), 3, '3 JSON lines';
    for my $line (@lines) {
        like $line, qr/^\{.*\}\n$/, "line is a JSON object";
        like $line, qr/"job_id":"j1"/, "job_id present";
    }
};

SKIP: {
    eval { require Log::Dispatch; require Log::Dispatch::File; 1 }
        or skip 'Log::Dispatch not installed', 1;

    require App::Prover::Sink::LogDispatch;

    subtest 'LogDispatch: writes formatted lines' => sub {
        my $tmp = File::Temp->new( SUFFIX => '.log' );
        my $sink = App::Prover::Sink::LogDispatch->new( config => $tmp->filename );
        $sink->emit( new_event(type => EV_TEST, ok => 1, test_num => 1, description => 'first', file => 'a.t') );
        $sink->emit( new_event(type => EV_TEST, ok => 0, test_num => 2, description => 'second', file => 'a.t') );
        $sink->emit( new_event(type => EV_BAILOUT, bailout => 'broken', file => 'a.t') );

        open my $fh, '<', $tmp->filename or die $!;
        my $contents = do { local $/; <$fh> };
        like $contents, qr/\[a\.t\] ok 1 - first/,     'pass logged';
        like $contents, qr/\[a\.t\] not ok 2 - second/, 'fail logged';
        like $contents, qr/\[a\.t\] BAIL_OUT: broken/,  'bailout logged';
    };
}

done_testing;
