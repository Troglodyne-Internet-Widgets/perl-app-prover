package App::Prover::Event;

use strict;
use warnings;

use Time::HiRes ();
use Exporter 'import';

our @EXPORT_OK = qw(
    EV_STARTED EV_ENDED
    EV_TEST EV_PLAN EV_COMMENT EV_BAILOUT EV_UNKNOWN EV_VERSION
    new_event
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK, types => [qw(
    EV_STARTED EV_ENDED EV_TEST EV_PLAN EV_COMMENT EV_BAILOUT EV_UNKNOWN EV_VERSION
)]);

use constant {
    EV_STARTED => 'started',
    EV_ENDED   => 'ended',
    EV_TEST    => 'test',
    EV_PLAN    => 'plan',
    EV_COMMENT => 'comment',
    EV_BAILOUT => 'bailout',
    EV_UNKNOWN => 'unknown',
    EV_VERSION => 'version',
};

sub new_event {
    my (%fields) = @_;
    $fields{timestamp} //= Time::HiRes::time();
    return \%fields;
}

1;

__END__

=head1 NAME

App::Prover::Event - normalized event shape for the runner

=head1 EVENT FIELDS

A normalized event is a plain hash reference with these keys:

    job_id      uint, monotonically assigned by Runner
    file        path of the test file
    type        one of the EV_* constants
    timestamp   Time::HiRes::time() captured at event creation

Per-type extra fields:

    type=test       ok, test_num, description, directive, explanation, raw
    type=plan       plan => { count, skip_all, reason }, raw
    type=comment    raw
    type=bailout    bailout, raw
    type=version    raw
    type=unknown    raw
    type=started    (no extras)
    type=ended      exit, elapsed_ms

The Test2 backend additionally passes through C<facet_data> verbatim.

=cut
