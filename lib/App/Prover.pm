#!/usr/bin/env perl
package App::Prover;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case bundling);
use List::Util  qw(shuffle);

use App::Prover::Discovery ();
use App::Prover::Runner    ();

our $VERSION = $App::Prover::Runner::VERSION;

exit __PACKAGE__->run(@ARGV) unless caller;

sub run {
    my ($class, @argv) = @_;

    my %opt = (
        jobs    => $ENV{HARNESS_JOBS} || 1,
        backend => 'tap', # XXX TODO support more backends
        ext     => [],
        I       => [],
        M       => [],
    );

    GetOptionsFromArray(
        \@argv,
        'jobs|j=i'        => \$opt{jobs},
        'lib|l!'          => \$opt{lib},
        'blib|b!'         => \$opt{blib},
        'I=s@'            => $opt{I},
        'M=s@'            => $opt{M},
        'recurse|r!'      => \$opt{recurse},
        'verbose|v!'      => \$opt{verbose},
        'ext=s@'          => $opt{ext},
        'shuffle!'        => \$opt{shuffle},
        'reverse!'        => \$opt{reverse},
        'timer!'          => \$opt{timer},
        'backend=s'       => \$opt{backend},
        'log-dispatch=s'  => \$opt{log_dispatch},
        'version'         => \$opt{show_version},
        'help|h'          => \$opt{show_help},
    ) or return _usage(\*STDERR, 2);

    return _print_version() if $opt{show_version};
    return _usage(\*STDOUT, 0) if $opt{show_help};

    @{ $opt{ext} } = ('.t') unless @{ $opt{ext} };

    my @inc;
    push @inc, 'lib'                    if $opt{lib};
    push @inc, 'blib/lib', 'blib/arch'  if $opt{blib};
    push @inc, @{ $opt{I} }             if @{ $opt{I} };

    # Slam together perlopts mostly for lib/module loads
    # XXX TODO Ideally preloads are actually mindread from -M arg.
    # To be honest, we probably can preload them in the main process
    # as ultimately the children all would share whatever's loaded even if
    # we use something like goto::file.
    # In order not to pollute memory state in the shared workers, we may
    # have to get clever about scrubbing whatever the test had loaded perhaps.
    # It would be interesting if we could mmap the state right of the process
    # worker right before it executes then just brainwash the worker,
    # only replacing the test to run. Not sure if that's even possible in perl.
    my @perl_args = ( ( map { "-I$_" } @inc ), ( map { "-M$_" } @{ $opt{M} } ) );

    my @files = App::Prover::Discovery::discover(\@argv, $opt{ext}, $opt{recurse});
    @files = shuffle @files          if $opt{shuffle};
    @files = reverse @files          if $opt{reverse};

    unless (@files) {
        print STDERR "No test files found, nothing to do.";
        return 2;
    }

    my $sinks = _build_sinks(\%opt);

    my $runner = App::Prover::Runner->new(
        jobs      => $opt{jobs},
        verbose   => $opt{verbose} ? 1 : 0,
        backend   => $opt{backend},
        perl_args => \@perl_args,
        sinks     => $sinks,
    );

    return $runner->run(@files);
}

sub _build_sinks {
    my ($opt) = @_;
    my @sinks;

    if ($opt->{verbose} && $opt->{jobs} <= 1) {
        require App::Prover::Sink::Verbose;
        push @sinks, App::Prover::Sink::Verbose->new;
    }
    else {
        require App::Prover::Sink::QVF;
        push @sinks, App::Prover::Sink::QVF->new;
    }

    # XXX TODO I think Log::Dispatch is being used improperly here.
    # Ideally we just past a list of output (dispatch) sources to it
    # Whether that be a log, STD*, what have you
    # The -v is just a loglevel. Instead the opt should basically just add another logfile
    # If we want other dispatch like a DB then this should be handled by a config file I think.
    # Failure events via a logger pattern match "error" output which would be an earlier
    # loglevel than verbose, so you basically get qvf for free just by having your minimum
    # loglevel be that style of output where not_ok is considered error output.
    # Levels: error, summary (default), verbose.
    if ($opt->{log_dispatch}) {
        require App::Prover::Sink::LogDispatch;
        push @sinks, App::Prover::Sink::LogDispatch->new(config => $opt->{log_dispatch});
    }

    return \@sinks;
}

sub _print_version {
    print "prover $App::Prover::Runner::VERSION\n";
    return 0;
}

sub _usage {
    my ($fh, $exit) = @_;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        -input   => __FILE__,
        -output  => $fh,
        -verbose => $exit ? 0 : 1,
        -exitval => 'NOEXIT',
    );
    return $exit;
}

1;

__END__

=head1 NAME

App::Prover - simple, fast, MCE-driven Perl test runner script

=head1 SYNOPSIS

    prover [options] [tests-or-dirs...]

Or programmatically:

    use App::Prover;
    exit App::Prover->run(@ARGV);

=head1 OPTIONS

=over 4

=item B<-j N>, B<--jobs N>

Concurrency. Defaults to C<$ENV{HARNESS_JOBS}> or 1.

=item B<-l>, B<--lib>

Add F<./lib> to C<@INC>.

=item B<-b>, B<--blib>

Add F<./blib/lib> and F<./blib/arch> to C<@INC>.

=item B<-I PATH>

Add C<PATH> to C<@INC>. Repeatable.

=item B<-M MODULE>

Pass C<-MMODULE> to test workers. Repeatable.

=item B<-r>, B<--recurse>

Recurse into directories during test discovery.

=item B<-v>, B<--verbose>

Verbose output. Live-streams when C<-j 1>.

=item B<--ext EXT>

Filename extension to discover. Defaults to F<.t>. Repeatable.

=item B<--shuffle>

Shuffle test order.

=item B<--reverse>

Reverse test order.

=item B<--timer>

Show per-test elapsed time.

=item B<--backend NAME>

Backend parser: C<tap> (default) or C<test2>.

=item B<--log-dispatch CFG>

Optional L<Log::Dispatch> wiring (path or hashref module).

=item B<--version>

Print version and exit.

=item B<-h>, B<--help>

Show this help.

=back

If no test paths are given, discovers tests under F<t/> then F<xt/>.

=head1 DESCRIPTION

A test runner script designed to be as simple as possible while still providing
parallel execution, pluggable parser backends (TAP and Test2 facets), and
multiple output sinks. See L<bin/prover> for the command-line interface.

=head2 What's in a name???

Since prove is a somewhat scientific term, I thought that the appropriate "upgrayedd"
to this also needed a highly scientific name. Thus 'prover'.
You may be curious about what the extra 'r' means as well; this part in particular
is extremely sciency:

=over 4

=item r

The first word in 'red' which is what you paint your trukk to make it go fasta'

=item r

The 'type' of Honda Civic you drive to go faster. Ideally in red.

=item r

Recursive, which is even an option. Highly useful in benchmarking this when running versus other testsuites.

=back

=head1 SEE ALSO

L<App::Prover::Runner>, L<App::Prove>, L<App::Yath::Script>.

=cut
