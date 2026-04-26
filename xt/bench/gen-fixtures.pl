#!perl
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Spec;

my $dir   = $ARGV[0] || '/tmp/app-prover-bench';
my $count = $ARGV[1] || 1000;

# Avoid "cannot remove cwd" surprises if the user runs this script from inside
# the target directory.
chdir File::Spec->tmpdir or die "chdir tmpdir: $!";

remove_tree($dir) if -d $dir;
make_path("$dir/t");

for my $i (1 .. $count) {
    my $path = File::Spec->catfile($dir, 't', sprintf('%04d.t', $i));
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} <<'EOT';
use strict;
use warnings;
use Test::More;

ok 1, 'a';
ok 1, 'b';
ok 1, 'c';

done_testing;
EOT
    close $fh;
}

print "wrote $count tests under $dir/t\n";
