package App::Prover::Sink::QVF;

use strict;
use warnings;

use parent 'App::Prover::Sink';

use App::Prover::Event qw(:types);
use App::Prover::Sink::Verbose ();

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->{buffers}     = {};
    $self->{has_failure} = {};
    return $self;
}

sub emit {
    my ($self, $ev) = @_;
    my $job = $ev->{job_id} // '';
    my $type = $ev->{type};

    if ($type eq EV_STARTED) {
        $self->{buffers}{$job}     = [];
        $self->{has_failure}{$job} = 0;
        return;
    }

    my $buf = $self->{buffers}{$job} ||= [];
    push @$buf, $ev;

    if ($type eq EV_TEST && !$ev->{ok} && !$ev->{directive}) {
        $self->{has_failure}{$job} = 1;
    }
    if ($type eq EV_BAILOUT) {
        $self->{has_failure}{$job} = 1;
    }
    if ($type eq EV_ENDED && $ev->{exit} != 0) {
        $self->{has_failure}{$job} = 1;
    }
}

sub flush_job {
    my ($self, $job_id, $verdict) = @_;
    my $fh    = $self->fh;
    my $buf   = delete $self->{buffers}{$job_id}     || [];
    my $fail  = delete $self->{has_failure}{$job_id} || 0;

    my ($started, $ended);
    for my $ev (@$buf) {
        $started = $ev if $ev->{type} eq EV_STARTED;
        $ended   = $ev if $ev->{type} eq EV_ENDED;
    }
    my $any = $started || $buf->[0] || {};
    my $file = $any->{file} || '?';
    my $secs = sprintf '%.3fs', ($ended && $ended->{elapsed_ms} ? $ended->{elapsed_ms} : 0) / 1000;

    if ($fail || $verdict && $verdict eq 'fail') {
        print {$fh} "# === FAIL: $file ($secs) ===\n";
        for my $ev (@$buf) {
            next if $ev->{type} eq EV_STARTED || $ev->{type} eq EV_ENDED;
            print {$fh} $ev->{raw}, "\n" if defined $ev->{raw};
        }
        print {$fh} "# --- end $file ---\n";
    }
    else {
        my $marker = $verdict && $verdict eq 'skip' ? 'skip' : 'ok';
        printf {$fh} "%s %s (%s)\n", $marker, $file, $secs;
    }
}

sub summary {
    my ($self, $agg) = @_;
    App::Prover::Sink::Verbose::_summary_print($self->fh, $agg);
}

1;
