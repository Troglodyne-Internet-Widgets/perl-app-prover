package App::Prover::Backend;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    return bless { %opts }, $class;
}

sub parse {
    my ($self) = @_;
    my $class = ref($self) || $self;
    die "$class did not implement parse(\$emit, \$stdout_fh, \$stderr_fh, \\%ctx)\n";
}

sub load {
    my ($class, $name) = @_;
    my $pkg = $name =~ /::/ ? $name : 'App::Prover::Backend::' . ucfirst lc $name;
    $pkg = 'App::Prover::Backend::TAP'   if lc $name eq 'tap';
    $pkg = 'App::Prover::Backend::Test2' if lc $name eq 'test2';
    (my $path = $pkg) =~ s{::}{/}g;
    require "$path.pm";
    return $pkg;
}

1;

__END__

=head1 NAME

App::Prover::Backend - backend (parser) base class

=head1 SYNOPSIS

    my $pkg     = App::Prover::Backend->load('tap');
    my $backend = $pkg->new();
    my $parser  = $backend->parse($emit, $stdout_fh, $stderr_fh, \%ctx);

=head1 CONTRACT

A backend takes one test's stdout/stderr handles, drains them, and converts the
output to normalized L<App::Prover::Event> hashrefs which it dispatches via the
caller-supplied C<$emit> coderef. After draining it returns a parser-shaped
object that can be passed to C<TAP::Parser::Aggregator::add($desc, $parser)> to
contribute to the run summary.

=cut
