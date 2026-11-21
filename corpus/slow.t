use strict;
use warnings;
use Test::More;

select( ( select(STDOUT), $| = 1 )[0] );
ok 1, 'before sleep';
sleep 1;
ok 1, 'after sleep';

done_testing;
