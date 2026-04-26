package App::Prover::Sink::LogDispatch;

use strict;
use warnings;

use parent 'App::Prover::Sink';

use App::Prover::Event qw(:types);

sub new {
    my ($class, %opts) = @_;
    my $config = delete $opts{config};

    require Log::Dispatch;
    require Log::Dispatch::File;

    my $log;
    if ($opts{log}) {
        $log = delete $opts{log};
    }
    else {
        defined $config or die "App::Prover::Sink::LogDispatch requires config => FILE_OR_HASHREF\n";
        if (ref $config eq 'HASH') {
            $log = Log::Dispatch->new(%$config);
        }
        else {
            $log = Log::Dispatch->new(
                outputs => [
                    [ 'File',
                      min_level => 'debug',
                      filename  => $config,
                      newline   => 1,
                      mode      => '>>',
                    ],
                ],
            );
        }
    }

    my $self = $class->SUPER::new(%opts);
    $self->{log} = $log;
    return $self;
}

sub emit {
    my ($self, $event) = @_;
    my $level = _level_for($event);
    my $msg   = _format($event);
    $self->{log}->log( level => $level, message => $msg );
}

sub flush_job { }
sub summary   { }

sub _level_for {
    my ($ev) = @_;
    my $type = $ev->{type};
    return 'error'   if $type eq EV_BAILOUT;
    return 'error'   if $type eq EV_TEST && !$ev->{ok} && !$ev->{directive};
    return 'notice'  if $type eq EV_COMMENT;
    return 'info';
}

sub _format {
    my ($ev) = @_;
    my $type = $ev->{type};
    my $file = $ev->{file} // '?';
    if ($type eq EV_TEST) {
        my $verdict = $ev->{ok} ? 'ok' : 'not ok';
        my $extra   = $ev->{directive} ? " # $ev->{directive}" : '';
        return sprintf '[%s] %s %s - %s%s',
            $file, $verdict, ($ev->{test_num} // '?'),
            ($ev->{description} // ''), $extra;
    }
    if ($type eq EV_PLAN) {
        my $count = $ev->{plan}{count} // 0;
        return "[$file] 1..$count";
    }
    if ($type eq EV_BAILOUT) {
        return "[$file] BAIL_OUT: " . ($ev->{bailout} // '');
    }
    if ($type eq EV_COMMENT) {
        return "[$file] " . ($ev->{raw} // '');
    }
    if ($type eq EV_STARTED) {
        return "[$file] start";
    }
    if ($type eq EV_ENDED) {
        return sprintf '[%s] end exit=%d (%dms)', $file, $ev->{exit} // 0, $ev->{elapsed_ms} // 0;
    }
    return "[$file] $type " . ($ev->{raw} // '');
}

1;

__END__

=head1 NAME

App::Prover::Sink::LogDispatch - route events through L<Log::Dispatch>

=head1 USAGE

    $ app-prover --log-dispatch /var/log/run.log -j8 t/

Or programmatically:

    my $log = Log::Dispatch->new( outputs => [ ... ] );
    my $sink = App::Prover::Sink::LogDispatch->new(log => $log);

=cut
