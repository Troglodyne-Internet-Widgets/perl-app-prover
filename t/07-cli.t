use strict;
use warnings;

use FindBin::libs;
use Test::More;
use File::Spec ();

use App::Prover ();

my $fixtures = File::Spec->catdir($FindBin::Bin, 'fixtures');

sub capture {
    my (@argv) = @_;
    my ($out, $err) = ('', '');
    my $exit;
    {
        local *STDOUT;
        local *STDERR;
        open STDOUT, '>', \$out or die $!;
        open STDERR, '>', \$err or die $!;
        $exit = App::Prover->run(@argv);
    }
    return ($exit, $out, $err);
}

subtest 'CLI: --version' => sub {
    my ($exit, $out) = capture('--version');
    is $exit, 0, 'exit 0';
    like $out, qr/prover\s+\d+/, 'version printed';
};

subtest 'CLI: --help' => sub {
    my ($exit, $out) = capture('--help');
    is $exit, 0, 'exit 0';
    like $out, qr/Usage:.*prover/s, 'usage printed';
};

subtest 'CLI: pass file with -j 1' => sub {
    my ($exit, $out) = capture('-j1', File::Spec->catfile($fixtures, 'pass.t'));
    is $exit, 0, 'exit 0';
    like $out, qr/Result:\s+PASS/, 'pass result';
};

subtest 'CLI: fail file with -j 1' => sub {
    my ($exit, $out) = capture('-j1', File::Spec->catfile($fixtures, 'fail.t'));
    is $exit, 1, 'exit 1';
    like $out, qr/Result:\s+FAIL/, 'fail result';
};

subtest 'CLI: directory discovery (non-recursive)' => sub {
    my ($exit, $out) = capture('-j1', $fixtures);
    isnt $exit, 0, 'fixtures contain failing tests, so non-zero';
    like $out, qr/pass\.t/, 'pass.t was discovered';
};

subtest 'CLI: --reverse and --shuffle parse' => sub {
    my ($exit, $out) = capture('-j1', '--reverse', File::Spec->catfile($fixtures, 'pass.t'));
    is $exit, 0, '--reverse single file ok';
};

done_testing;
