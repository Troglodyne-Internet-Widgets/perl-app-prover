package App::Prover::Sink::Log;

use strict;
use warnings;

use parent 'App::Prover::Sink';

use App::Prover::Event qw(:types);

sub new {
    my ($class, %opts) = @_;

    my $log = delete $opts{log};
    unless ($log) {
        require Log::Dispatch;
        my $outputs = delete $opts{outputs};
        unless ($outputs) {
            require Log::Dispatch::Screen;
            $outputs = [
                [
                    'Screen',
                    min_level => delete $opts{min_level} // 'notice',
                    newline   => 1,
                ],
            ];
        }
        $log = Log::Dispatch->new( outputs => $outputs );
    }

    my $self = $class->SUPER::new(%opts);
    $self->{log}     = $log;
    $self->{live}    = $opts{live} ? 1 : 0;
    $self->{buffers} = {};
    $self->{failed}  = {};
    return $self;
}

sub log { $_[0]->{log} }

sub emit {
    my ($self, $ev) = @_;
    my $type = $ev->{type};

    if ($self->{live}) {
        $self->_emit_live($ev);
        return;
    }

    my $job = $ev->{job_id} // '';
    if ($type eq EV_STARTED) {
        $self->{buffers}{$job} = [];
        $self->{failed}{$job}  = 0;
        return;
    }
    push @{ $self->{buffers}{$job} ||= [] }, $ev;

    if ($type eq EV_TEST && !$ev->{ok} && !$ev->{directive}) {
        $self->{failed}{$job} = 1;
    }
    elsif ($type eq EV_BAILOUT) {
        $self->{failed}{$job} = 1;
    }
    elsif ($type eq EV_ENDED && ($ev->{exit} // 0) != 0) {
        $self->{failed}{$job} = 1;
    }
}

sub flush_job {
    my ($self, $job_id, $verdict) = @_;
    return if $self->{live};

    my $buf  = delete $self->{buffers}{$job_id} || [];
    my $fail = delete $self->{failed}{$job_id}  || 0;
    $fail ||= ($verdict && $verdict eq 'fail');

    my ($started, $ended);
    for my $ev (@$buf) {
        $started = $ev if $ev->{type} eq EV_STARTED;
        $ended   = $ev if $ev->{type} eq EV_ENDED;
    }
    my $any  = $started || $buf->[0] || {};
    my $file = $any->{file} || '?';
    my $secs = sprintf '%.3fs', ($ended && $ended->{elapsed_ms} ? $ended->{elapsed_ms} : 0) / 1000;

    if ($fail) {
        $self->{log}->log( level => 'error', message => "# === FAIL: $file ($secs) ===" );
        for my $ev (@$buf) {
            next if $ev->{type} eq EV_STARTED || $ev->{type} eq EV_ENDED;
            my $msg = _format_buffered($ev);
            next unless defined $msg;
            $self->{log}->log( level => _level_for($ev), message => $msg );
        }
        $self->{log}->log( level => 'error', message => "# --- end $file ---" );
    }
    else {
        my $marker = $verdict && $verdict eq 'skip' ? 'skip' : 'ok';
        $self->{log}->log( level => 'notice', message => "$marker $file ($secs)" );
    }
}

sub summary {
    my ($self, $stats) = @_;
    return unless $stats;
    my $verdict = $stats->all_passed ? 'PASS' : 'FAIL';
    my @failed  = $stats->failed_files;

    $self->{log}->log( level => 'notice', message => '' );
    if (@failed) {
        $self->{log}->log( level => 'error', message => 'Test Summary Report' );
        $self->{log}->log( level => 'error', message => '-------------------' );
        $self->{log}->log( level => 'error', message => "  $_" ) for @failed;
    }
    $self->{log}->log(
        level   => 'notice',
        message => sprintf(
            'Result: %s  (Tests=%d Passed=%d Failed=%d Skipped=%d TODO=%d)  [%.2fs]',
            $verdict,
            $stats->total, $stats->passed, $stats->failed,
            $stats->skipped, $stats->todo, $stats->elapsed,
        ),
    );
}

# --- live emit (verbose, jobs<=1) ------------------------------------------
# Mirrors the old Sink::Verbose so prove-style watchers see start/end banners
# and raw TAP lines as they happen.

sub _emit_live {
    my ($self, $ev) = @_;
    my $type = $ev->{type};
    my $file = $ev->{file} // '?';

    if ($type eq EV_STARTED) {
        $self->{log}->log( level => 'notice', message => "# === $file ===" );
        return;
    }
    if ($type eq EV_ENDED) {
        my $exit    = $ev->{exit} // 0;
        my $verdict = $exit == 0 ? 'ok' : 'NOT OK';
        my $secs    = sprintf '%.3fs', ($ev->{elapsed_ms} || 0) / 1000;
        $self->{log}->log(
            level   => $exit == 0 ? 'notice' : 'error',
            message => "# --- $file $verdict ($secs) ---",
        );
        return;
    }

    if (defined $ev->{raw}) {
        $self->{log}->log( level => _level_for($ev), message => $ev->{raw} );
    }
}

# --- buffered fail-replay format -------------------------------------------
# At -j > 1 we don't have the raw stream context anymore; the per-file FAIL
# block reproduces a prove-style dump from each event's raw line.

sub _format_buffered {
    my ($ev) = @_;
    return $ev->{raw} if defined $ev->{raw};
    my $type = $ev->{type};
    if ($type eq EV_BAILOUT) {
        return 'Bail out!  ' . ($ev->{bailout} // '');
    }
    return undef;
}

sub _level_for {
    my ($ev) = @_;
    my $type = $ev->{type};
    return 'critical' if $type eq EV_BAILOUT;
    return 'error'    if $type eq EV_TEST && !$ev->{ok} && !$ev->{directive};
    return 'notice'   if $type eq EV_COMMENT;
    return 'info';
}

1;

__END__

=head1 NAME

App::Prover::Sink::Log - Log::Dispatch-driven output sink for App::Prover

=head1 SYNOPSIS

    use App::Prover::Sink::Log;

    # default: a Screen output at min_level => 'notice' (≈ classic QVF)
    my $sink = App::Prover::Sink::Log->new;

    # verbose: live-stream every event as it arrives
    my $sink = App::Prover::Sink::Log->new( live => 1, min_level => 'info' );

    # bring your own Log::Dispatch
    my $log  = Log::Dispatch->new( outputs => [ ... ] );
    my $sink = App::Prover::Sink::Log->new( log => $log );

=head1 DESCRIPTION

A single sink that maps App::Prover events to L<Log::Dispatch> log levels;
the C<min_level> on each output decides what the user actually sees. This
replaces the older Verbose / QVF / LogDispatch sink trio — those three
were really just three preset C<min_level> + buffering combinations.

=head2 Level mapping

    EV_BAILOUT                          critical
    EV_TEST failing (no directive)      error
    EV_COMMENT                          notice
    EV_TEST passing or skip/todo        info
    EV_PLAN, EV_VERSION, EV_UNKNOWN     info
    EV_STARTED, EV_ENDED                info (verbose mode only)
    Per-file pass/skip summary          notice (synthesized)
    Per-file FAIL banner + replay       error / mixed (synthesized)
    Run-end summary                     notice

A user choosing C<min_level =E<gt> 'error'> sees only failures; C<'notice'>
adds per-file summaries and diagnostics (the historical QVF behavior);
C<'info'> shows every event (the historical Verbose behavior).

=head2 Live vs. buffered

C<live =E<gt> 1>: events are logged as they arrive. Suitable for C<-j 1>
verbose mode where the user wants prove-like real-time output.

C<live =E<gt> 0> (default): events are buffered per-job. On
C<flush_job($job_id, $verdict)>, the sink synthesizes either a one-line
C<ok/skip> verdict (passing files) or a multi-line FAIL banner with the
buffered events replayed at their natural levels (failing files). This
prevents cross-job interleaving at C<-j E<gt> 1> and matches the historical
QVF behavior.

=cut
