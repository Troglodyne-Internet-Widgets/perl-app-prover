use strict;
use warnings;

use FindBin ();
use FindBin::libs;
use Test::More;
use File::Spec ();

# This test exercises the --preload (do-in-fork) Worker path. We don't drive
# the Worker directly from this Test::More process: a Test::Builder singleton
# already in flight in the parent confuses the child's output dup, and the
# real CLI never does that anyway. Instead we exec `bin/prover --preload`
# in a subprocess, capture its output, and assert the probe fixture passed.

my $bin     = File::Spec->catfile($FindBin::Bin, '..', 'bin', 'prover');
my $fixture = File::Spec->catfile($FindBin::Bin, '..', 'corpus', 'preload-probe.t');
my $tlib    = File::Spec->catdir($FindBin::Bin, 'lib');

sub run_prover {
    my (@argv) = @_;
    my $cmd = join ' ',
        $^X,
        "-Ilib",
        "-I$tlib",
        $bin,
        @argv;
    my $out = `$cmd 2>&1`;
    my $exit = $? >> 8;
    return ($exit, $out);
}

subtest 'baseline: no --preload, fixture cannot find probe module' => sub {
    my ($exit, $out) = run_prover('-j1', $fixture);
    isnt $exit, 0, 'non-zero exit (probe assertions failed)';
    like   $out, qr/FAIL/i, 'fail banner present';
};

subtest 'preload: --preload makes the probe module visible inside the test' => sub {
    my ($exit, $out) = run_prover('-j1', '--preload', 'App::Prover::TestPreloadProbe', $fixture);
    is   $exit, 0, 'exit 0';
    like $out, qr/Result:\s+PASS/, 'PASS summary';
    like $out, qr/Tests=3 Passed=3/, 'all 3 probe assertions passed';
};

subtest 'preload: -M warning when both -M and --preload are given' => sub {
    my ($exit, $out) = run_prover(
        '-j1',
        '--preload', 'App::Prover::TestPreloadProbe',
        '-M', 'List::Util',
        $fixture,
    );
    is   $exit, 0, 'still passes';
    like $out, qr/-M is ignored when --preload/, 'warning emitted';
};

subtest 'preload: parallel mode (jobs > 1) inherits preloads in MCE workers' => sub {
    my ($exit, $out) = run_prover('-j2', '--preload', 'App::Prover::TestPreloadProbe', $fixture, $fixture);
    is   $exit, 0, 'exit 0';
    like $out, qr/Result:\s+PASS/, 'PASS summary';
};

done_testing;
