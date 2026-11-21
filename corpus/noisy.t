use strict;
use warnings;
use Test::More;

for my $i (1..5) {
    diag "noise line $i";
    ok 1, "noisy $i";
}

done_testing;
