package App::Prover::Sink;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    my $fh = delete $opts{fh} || \*STDOUT;
    return bless { fh => $fh, %opts }, $class;
}

sub fh { $_[0]->{fh} }

sub emit      { }
sub flush_job { }
sub summary   { }

sub load {
    my ($class, $name) = @_;
    my $pkg = $name =~ /::/ ? $name : 'App::Prover::Sink::' . _camel($name);
    (my $path = $pkg) =~ s{::}{/}g;
    require "$path.pm";
    return $pkg;
}

sub _camel {
    my ($s) = @_;
    return join '', map { ucfirst lc $_ } split /[-_]/, $s;
}

1;

__END__

=head1 NAME

App::Prover::Sink - output sink interface

=head1 INTERFACE

    $sink->emit($event)                   # called per event in arrival order
    $sink->flush_job($job_id, $verdict)   # 'pass'|'fail'|'skip'|'todo'
    $sink->summary($aggregator)           # called once at end of run

=cut
