use strict;
use warnings;
use Test::More;

ok 1, 'first';
ok 0, 'second (intentional fail)';
diag "this test is supposed to fail";
ok 1, 'third';

done_testing;
