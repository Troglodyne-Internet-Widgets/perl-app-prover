use strict;
use warnings;

use FindBin::libs;
use Test::More;
use File::Spec ();

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
                min_level => $opts{verbose} ? 'info' : 'notice',
                code      => sub { my %p = @_; $buf .= $p{message} . "\n" },
            ],
        ],
    );
    my $sink = App::Prover::Sink::Log->new(
        log  => $log,
        live => $opts{verbose} ? 1 : 0,
    );
    my $runner = App::Prover::Runner->new(
        jobs    => 1,
        verbose => $opts{verbose} || 0,
        sinks   => [ $sink ],
    );
    return ($runner, \$buf);
}

subtest 'serial: pass and fail' => sub {
    my ($runner, $bufref) = captured_runner();
    my $exit = $runner->run(
        File::Spec->catfile($fixtures, 'pass.t'),
        File::Spec->catfile($fixtures, 'fail.t'),
    );
    is $exit, 1, 'overall exit 1 (one fail)';
    like $$bufref, qr/FAIL:.*fail\.t/, 'failing file shown';
    like $$bufref, qr/ok .*pass\.t/, 'passing file shown';
    like $$bufref, qr/Result:\s+FAIL/, 'summary FAIL';
};

subtest 'serial: all pass' => sub {
    my ($runner, $bufref) = captured_runner();
    my $exit = $runner->run(
        File::Spec->catfile($fixtures, 'pass.t'),
        File::Spec->catfile($fixtures, 'plan-at-end.t'),
    );
    is $exit, 0, 'overall exit 0';
    like $$bufref, qr/Result:\s+PASS/, 'summary PASS';
};

subtest 'serial: verbose streams raw lines' => sub {
    my ($runner, $bufref) = captured_runner(verbose => 1);
    $runner->run( File::Spec->catfile($fixtures, 'pass.t') );
    like $$bufref, qr/^ok 1/m, 'verbose printed first ok';
    like $$bufref, qr/^ok 2/m, 'verbose printed second ok';
};

subtest 'serial: skip_all' => sub {
    my ($runner, $bufref) = captured_runner();
    my $exit = $runner->run( File::Spec->catfile($fixtures, 'skip.t') );
    is $exit, 0, 'skip_all is not a failure';
};

done_testing;
