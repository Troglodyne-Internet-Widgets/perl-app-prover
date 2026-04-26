package App::Prover::Sink::JSONL;

use strict;
use warnings;

use parent 'App::Prover::Sink';

use JSON::PP ();

sub new {
    my ($class, %opts) = @_;
    my $path = delete $opts{path}
        or die "App::Prover::Sink::JSONL requires path => FILE\n";
    open my $fh, '>>', $path or die "open $path: $!";
    $fh->autoflush(1);
    my $self = $class->SUPER::new(%opts, fh => $fh);
    $self->{json} = JSON::PP->new->utf8->canonical;
    return $self;
}

sub emit {
    my ($self, $event) = @_;
    print { $self->{fh} } $self->{json}->encode($event), "\n";
}

sub flush_job { }
sub summary   { }

1;

__END__

=head1 NAME

App::Prover::Sink::JSONL - one normalized event per JSON line

=head1 USAGE

    $ app-prover --jsonl events.log -j8 t/

Combine with a default human sink (QVF or Verbose) for normal terminal output;
JSONL is purely additive.

=cut
