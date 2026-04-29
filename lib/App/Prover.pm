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
        backend => 'tap',
        ext     => [],
        I       => [],
        M       => [],
        preload => [],
    );

    GetOptionsFromArray(
        \@argv,
        'jobs|j=i'   => \$opt{jobs},
        'lib|l!'     => \$opt{lib},
        'blib|b!'    => \$opt{blib},
        'I=s@'       => $opt{I},
        'M=s@'       => $opt{M},
        'preload=s@' => $opt{preload},
        'recurse|r!' => \$opt{recurse},
        'verbose|v!' => \$opt{verbose},
        'ext=s@'     => $opt{ext},
        'shuffle!'   => \$opt{shuffle},
        'reverse!'   => \$opt{reverse},
        'timer!'     => \$opt{timer},
        'backend=s'  => \$opt{backend},
        'log=s'      => \$opt{log},
        'version'    => \$opt{show_version},
        'help|h'     => \$opt{show_help},
    ) or return _usage(\*STDERR, 2);

    return _print_version() if $opt{show_version};
    return _usage(\*STDOUT, 0) if $opt{show_help};

    @{ $opt{ext} } = ('.t') unless @{ $opt{ext} };

    my @inc;
    push @inc, 'lib'                    if $opt{lib};
    push @inc, 'blib/lib', 'blib/arch'  if $opt{blib};
    push @inc, @{ $opt{I} }             if @{ $opt{I} };

    my $preload_active = @{ $opt{preload} } ? 1 : 0;

    if ($preload_active) {
        unshift @INC, @inc;
        _do_preload($_) for @{ $opt{preload} };
        if (@{ $opt{M} }) {
            warn "warning: -M is ignored when --preload is in use; preload modules with --preload instead\n";
        }
    }

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
        preload   => $preload_active,
        sinks     => $sinks,
    );

    return $runner->run(@files);
}

sub _do_preload {
    my ($spec) = @_;
    my ($mod, $args) = split /=/, $spec, 2;
    (my $path = $mod) =~ s{::}{/}g;
    $path .= '.pm';
    my $ok = eval { require $path; 1 };
    unless ($ok) {
        warn "preload: require $mod failed: $@";
        return;
    }
    my @import_args = defined $args ? split /,/, $args : ();
    eval { $mod->import(@import_args); 1 }
        or warn "preload: $mod->import failed: $@";
}

sub _build_sinks {
    my ($opt) = @_;

    require Log::Dispatch;
    require Log::Dispatch::Screen;
    require App::Prover::Sink::Log;

    my @outputs = (
        [
            'Screen',
            min_level => $opt->{verbose} ? 'info' : 'notice',
            newline   => 1,
            stderr    => 0,
        ],
    );

    if (length $opt->{log}) {
        require Log::Dispatch::File;
        push @outputs, [
            'File',
            min_level => 'debug',
            filename  => $opt->{log},
            newline   => 1,
            mode      => '>>',
        ];
    }

    my $log = Log::Dispatch->new( outputs => \@outputs );

    return [
        App::Prover::Sink::Log->new(
            log  => $log,
            live => ($opt->{verbose} && $opt->{jobs} <= 1) ? 1 : 0,
        ),
    ];
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

Pass C<-MMODULE> to test workers. Repeatable. Ignored when B<--preload> is
in use; preload modules with B<--preload> instead.

=item B<--preload MODULE[=ARGS]>

Load (and import) MODULE in the manager process before any tests run. Test
workers fork from the preloaded manager and execute the test in-process via
C<do $file>, inheriting the preloaded modules through copy-on-write. Avoids
paying perl-bootstrap + module-compile cost per test, at the price of: (a)
losing C<exec>-based isolation (state from the manager is visible to the
test); (b) tests that depend on stack-frame depth (e.g. C<caller(0)> equal
to a particular value) may behave differently than under prove. Repeatable.

Module args follow the C<-MMODULE=arg1,arg2> convention:

    --preload Moose
    --preload Mojo::Base=-strict
    --preload List::Util=shuffle,sum

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

=item B<--log CFG>

Optional log file to emit to.

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
