use strict;
use warnings;
use Test::More;

use App::Prover::Event qw(:all);

ok defined(EV_TEST),  'EV_TEST defined';
is EV_TEST, 'test',   'EV_TEST value';
is EV_PLAN, 'plan',   'EV_PLAN value';

my $ev = new_event( type => EV_TEST, ok => 1, test_num => 1 );
is $ev->{type}, 'test', 'event has type';
ok defined $ev->{timestamp}, 'event has auto timestamp';
is $ev->{ok}, 1, 'event ok preserved';

done_testing;
