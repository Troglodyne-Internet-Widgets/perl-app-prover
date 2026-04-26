use strict;
use warnings;
use Test::More;

ok 1, 'normal';
TODO: {
    local $TODO = 'fixture todo';
    ok 0, 'pending implementation';
}

done_testing;
