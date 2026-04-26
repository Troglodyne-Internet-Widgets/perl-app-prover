package App::Prover;

use strict;
use warnings;

our $VERSION = '0.001';

use App::Prover::Runner ();

sub new {
    my ($class, %opts) = @_;
    return bless { opts => \%opts }, $class;
}

sub run {
    my ($self, @files) = @_;
    return App::Prover::Runner->new(%{ $self->{opts} })->run(@files);
}

1;

__END__

=head1 NAME

App::Prover - simple, fast, MCE-driven Perl test runner script

=head1 SYNOPSIS

    use App::Prover;
    my $exit = App::Prover->new(
        jobs    => 8,
        verbose => 0,
        backend => 'tap',
    )->run(@test_files);
    exit $exit;

=head1 DESCRIPTION

A test runner script designed to be as simple as possible while still providing
parallel execution, pluggable parser backends (TAP and Test2 facets), and
multiple output sinks. See L<bin/app-prover> for the command-line interface.

=head1 SEE ALSO

L<App::Prover::Runner>, L<App::Prover::CLI>, L<prove>.

=cut
