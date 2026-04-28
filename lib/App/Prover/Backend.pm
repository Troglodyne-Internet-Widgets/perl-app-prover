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

    my $base_parse = __PACKAGE__->can('parse');
    my $impl_parse = $pkg->can('parse');
    if (!$impl_parse || $impl_parse == $base_parse) {
        die "App::Prover::Backend->load('$name'): $pkg does not implement parse()\n";
    }
    return $pkg;
}

1;

__END__

=head1 NAME

App::Prover::Backend - parser backend role for App::Prover

=head1 SYNOPSIS

    my $pkg     = App::Prover::Backend->load('tap');   # or 'test2', or a FQ class
    my $backend = $pkg->new();
    my $parser  = $backend->parse($emit, $stdout_fh, $stderr_fh, \%ctx);

=head1 DESCRIPTION

A B<backend> drains a single test's output and converts it into normalized
L<App::Prover::Event> hashrefs. App::Prover ships with two:
L<App::Prover::Backend::TAP> (default, wraps L<TAP::Parser>) and
L<App::Prover::Backend::Test2> (wraps L<Test2::Harness2>'s facet parser).

You can write your own — see L</WRITING YOUR OWN BACKEND>.

=head1 CONTRACT

A backend class:

=over 4

=item *

May inherit from C<App::Prover::Backend> (gives you C<new>) or any other base.

=item *

B<Must> implement C<parse($emit, $stdout_fh, $stderr_fh, \%ctx)>:

=over 4

=item *

C<$emit> is a coderef. Call it once per normalized event hashref. Use
L<App::Prover::Event/new_event> to construct events with auto-timestamps.

=item *

C<$stdout_fh> is a readable filehandle — typically the merged stdout+stderr
of the test process. Drain it to EOF.

=item *

C<$stderr_fh> is either C<undef> (already merged into stdout) or a separate
filehandle. If defined, drain it the same way.

=item *

C<\%ctx> contains C<{ file => $path, job_id => $id }> for context that
should appear on emitted events.

=item *

The return value B<must> implement the parser duck-type below — a single
object that exposes per-test totals via accessor methods. The TAP backend
returns the L<TAP::Parser> directly (it already implements the duck-type);
the Test2 backend returns an internal C<_FakeParser> shim.

=back

=back

=head2 Parser duck-type

C<App::Prover::Stats::extract> calls these methods on the returned parser:

    tests_run         passed         failed         skipped
    todo              todo_passed    parse_errors
    actual_passed     actual_failed
    has_problems      skip_all       is_good_plan   plan

All return scalar counts or booleans. Mirroring L<TAP::Parser::Aggregator>'s
shape is the easiest path; if the underlying parser doesn't expose these
directly, write a tiny shim like
L<App::Prover::Backend::Test2::_FakeParser>.

=head1 WRITING YOUR OWN BACKEND

Two short reference implementations:

=over 4

=item *

L<App::Prover::Backend::TAP> — the simplest case. C<TAP::Parser> already
matches the duck-type, so the backend is mostly the result-to-event
mapping.

=item *

L<App::Prover::Backend::Test2> — the harder case: the underlying parser
doesn't match the duck-type, so the backend accumulates its own stats and
returns a C<_FakeParser> over them.

=back

Sketch of a third backend (e.g. JUnit XML):

    package My::Backend::JUnit;
    use parent 'App::Prover::Backend';
    use App::Prover::Event qw(:types new_event);

    sub parse {
        my ($self, $emit, $stdout_fh, $stderr_fh, $ctx) = @_;
        my $stats = { tests_run => 0, passed => 0, failed => 0, ... };
        # ... drain $stdout_fh, parse JUnit XML, $emit->(...) per testcase ...
        return My::Backend::JUnit::Parser->new($stats);  # implement duck-type
    }

Pass it to the runner via C<--backend My::Backend::JUnit> (any name with
C<::> in it is treated as a fully-qualified class name; bare names are
prefixed with C<App::Prover::Backend::>).

=head1 EXECUTORS (FUTURE)

Today every test is run by C<perl $file> via L<App::Prover::Worker>. A
JUnit-emitting backend doesn't help on its own — you also need an
B<executor> that knows to invoke C<playwright test --reporter=junit> (or
whatever) instead of C<perl>.

The intended future shape is a config-driven binding from filename
extension or path pattern to an C<(executor, backend)> pair. Adding new
backends now is forward-compatible with that model: the C<parse()> contract
is independent of how the test was launched. Expect a future release to add
the executor abstraction without changing the backend role.

=cut
