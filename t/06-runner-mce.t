use strict;
use warnings;

use FindBin::libs;
use Test::More;
use File::Spec ();

BEGIN {
    eval { require MCE; require MCE::Flow; 1 }
        or plan skip_all => "MCE not available: $@";
}

use App::Prover::Runner ();

my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');

sub captured_runner {
    my (%opts) = @_;
    require Log::Dispatch;
    require App::Prover::Sink::Log;
    my $buf = '';
    my $log = Log::Dispatch->new(
        outputs => [
            [
                'Code',
                min_level => 'notice',
                code      => sub { my %p = @_; $buf .= $p{message} . "\n" },
            ],
        ],
    );
    my $sink = App::Prover::Sink::Log->new( log => $log, live => 0 );
    my $runner = App::Prover::Runner->new(
        jobs    => $opts{jobs} || 4,
        verbose => 0,
        sinks   => [ $sink ],
    );
    return ($runner, \$buf);
}

subtest 'parallel: all-pass batch' => sub {
    my ($runner, $bufref) = captured_runner(jobs => 4);
    my $exit = $runner->run(
        File::Spec->catfile($fixtures, 'pass.t'),
        File::Spec->catfile($fixtures, 'noisy.t'),
        File::Spec->catfile($fixtures, 'plan-at-end.t'),
        File::Spec->catfile($fixtures, 'todo.t'),
    );
    is $exit, 0, 'all passed -> exit 0';
    like $$bufref, qr/Result:\s+PASS/, 'summary PASS';
    is $runner->stats->failed_files, 0, 'no failed files';
    ok $runner->stats->total >= 8, "saw at least 8 tests (got @{[ $runner->stats->total ]})";
};

subtest 'parallel: mixed pass/fail' => sub {
    my ($runner, $bufref) = captured_runner(jobs => 4);
    my $exit = $runner->run(
        File::Spec->catfile($fixtures, 'pass.t'),
        File::Spec->catfile($fixtures, 'fail.t'),
        File::Spec->catfile($fixtures, 'pass.t'),
    );
    is $exit, 1, 'fail -> exit 1';
    like $$bufref, qr/FAIL: .*fail\.t/, 'fail file dumped';
    like $$bufref, qr/Result:\s+FAIL/, 'summary FAIL';
};

subtest 'parallel: stress 50 files' => sub {
    my ($runner, $bufref) = captured_runner(jobs => 8);
    my @files = ( File::Spec->catfile($fixtures, 'pass.t') ) x 50;
    my $exit = $runner->run(@files);
    is $exit, 0, '50 passes succeed';
    is scalar( $runner->stats->descriptions ), 50, 'aggregated 50 results';
};

done_testing;
