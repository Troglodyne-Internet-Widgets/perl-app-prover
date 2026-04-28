use strict;
use warnings;

use FindBin::libs;
use Test::More;
use File::Temp ();
use File::Spec ();

use App::Prover::Discovery ();

# Build a small fixture tree:
#   $root/t/a.t
#   $root/t/b.t
#   $root/t/sub/c.t
#   $root/t/sub/d.test
#   $root/t/skip.txt
#   $root/xt/e.t
my $root = File::Temp->newdir;
my $rdir = $root->dirname;
mkdir File::Spec->catdir($rdir, $_) or die "mkdir: $!"
    for ('t', File::Spec->catdir('t', 'sub'), 'xt');

sub touch {
    my ($path) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    close $fh;
}
touch(File::Spec->catfile($rdir, 't', 'a.t'));
touch(File::Spec->catfile($rdir, 't', 'b.t'));
touch(File::Spec->catfile($rdir, 't', 'sub', 'c.t'));
touch(File::Spec->catfile($rdir, 't', 'sub', 'd.test'));
touch(File::Spec->catfile($rdir, 't', 'skip.txt'));
touch(File::Spec->catfile($rdir, 'xt', 'e.t'));

my $cwd = File::Spec->rel2abs(File::Spec->curdir);
chdir $rdir or die "chdir $rdir: $!";

subtest 'explicit file' => sub {
    my @got = App::Prover::Discovery::discover(['t/a.t'], ['.t'], 0);
    is_deeply \@got, ['t/a.t'], 'single file passed through';
};

subtest 'directory non-recursive: only direct children, sorted' => sub {
    my @got = App::Prover::Discovery::discover(['t'], ['.t'], 0);
    is_deeply \@got, ['t/a.t', 't/b.t'], 't/a.t and t/b.t, no recursion';
};

subtest 'directory recursive: walks subtree' => sub {
    my @got = App::Prover::Discovery::discover(['t'], ['.t'], 1);
    is_deeply [sort @got], ['t/a.t', 't/b.t', 't/sub/c.t'],
        'recursive discovery picks up t/sub/c.t';
};

subtest 'extension filter: dot-prefixed and bare both work' => sub {
    my @got = App::Prover::Discovery::discover(['t/sub'], ['test'], 1);
    is_deeply \@got, ['t/sub/d.test'], 'bare ext "test" matches .test';
};

subtest 'extension filter: skip.txt is not picked up' => sub {
    my @got = App::Prover::Discovery::discover(['t'], ['.t'], 1);
    ok !( grep { /skip\.txt/ } @got ), 'skip.txt excluded by ext filter';
};

subtest 'default: empty argv → t/ then xt/' => sub {
    my @got = App::Prover::Discovery::discover([], ['.t'], 1);
    is_deeply [sort @got], ['t/a.t', 't/b.t', 't/sub/c.t', 'xt/e.t'],
        'walks both t/ and xt/ when nothing is given';
};

subtest 'missing path: warns but does not abort' => sub {
    my $warn = '';
    local $SIG{__WARN__} = sub { $warn .= $_[0] };
    my @got = App::Prover::Discovery::discover(['t/a.t', 'nope-doesnt-exist'], ['.t'], 0);
    is_deeply \@got, ['t/a.t'], 'good arg still returned';
    like $warn, qr/nope-doesnt-exist/, 'missing arg warned';
};

chdir $cwd or die "chdir back: $!";

done_testing;
