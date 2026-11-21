use strict;
use warnings;
use Test::More;

ok 1, 'before bail';
BAIL_OUT('fixture bail');
ok 1, 'unreached';
