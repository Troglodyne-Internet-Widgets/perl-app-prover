#!/usr/bin/env perl
package App::Prover::CLI;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case bundling);
use File::Find  ();
use File::Spec  ();
use List::Util  qw(shuffle);

use App::Prover::Runner ();

our $VERSION = $App::Prover::Runner::VERSION;

exit run(@ARGV) unless caller;

sub run {
    my ($class, @argv) = @_;

    my %opt = (
        jobs    => $ENV{HARNESS_JOBS} || 1,
        backend => 'tap',
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
        'jsonl=s'         => \$opt{jsonl},
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

    my @perl_args;
    push @perl_args, map { "-I$_" } @inc;
    push @perl_args, map { "-M$_" } @{ $opt{M} };

    my @files = _discover_tests(\@argv, $opt{ext}, $opt{recurse});
    @files = shuffle @files          if $opt{shuffle};
    @files = reverse @files          if $opt{reverse};

    unless (@files) {
        print STDERR "no test files found\n";
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

    if ($opt->{jsonl}) {
        require App::Prover::Sink::JSONL;
        push @sinks, App::Prover::Sink::JSONL->new(path => $opt->{jsonl});
    }

    if ($opt->{log_dispatch}) {
        require App::Prover::Sink::LogDispatch;
        push @sinks, App::Prover::Sink::LogDispatch->new(config => $opt->{log_dispatch});
    }

    return \@sinks;
}

sub _discover_tests {
    my ($argv, $exts, $recurse) = @_;

    my @args = @$argv ? @$argv : (-d 't' ? ('t') : (), -d 'xt' ? ('xt') : ());
    return () unless @args;

    my @files;
    for my $arg (@args) {
        if (-f $arg) {
            push @files, $arg;
            next;
        }
        if (-d $arg) {
            push @files, _files_under($arg, $exts, $recurse);
            next;
        }
        warn "no such file or directory: $arg\n";
    }
    return @files;
}

sub _files_under {
    my ($dir, $exts, $recurse) = @_;
    my %ext_set = map { $_ => 1 } map { /^\./ ? $_ : ".$_" } @$exts;
    my @found;
    if ($recurse) {
        File::Find::find(
            {
                wanted => sub {
                    return unless -f $_;
                    my ($e) = $_ =~ /(\.[^.]+)$/;
                    return unless $e && $ext_set{$e};
                    push @found, $File::Find::name;
                },
                no_chdir => 1,
            },
            $dir,
        );
    }
    else {
        opendir my $dh, $dir or do {
            warn "cannot open directory $dir: $!\n";
            return ();
        };
        while ( defined( my $entry = readdir $dh ) ) {
            next if $entry =~ /^\.\.?$/;
            my $path = File::Spec->catfile($dir, $entry);
            next unless -f $path;
            my ($e) = $entry =~ /(\.[^.]+)$/;
            next unless $e && $ext_set{$e};
            push @found, $path;
        }
        closedir $dh;
    }
    return sort @found;
}

sub _print_version {
    print "app-prover $App::Prover::Runner::VERSION\n";
    return 0;
}

sub _usage {
    my ($fh, $exit) = @_;
    print {$fh} <<'USAGE';
Usage: app-prover [options] [tests-or-dirs...]

  -j N, --jobs N        Concurrency (default: $HARNESS_JOBS || 1)
  -l, --lib             Add ./lib to @INC
  -b, --blib            Add ./blib/lib and ./blib/arch to @INC
  -I PATH               Add PATH to @INC (repeatable)
  -M MODULE             -mMODULE for tests (repeatable)
  -r, --recurse         Recurse into directories
  -v, --verbose         Verbose output (live-stream when -j 1)
  --ext EXT             Filename extension to discover (default: .t, repeatable)
  --shuffle             Shuffle test order
  --reverse             Reverse test order
  --timer               Show per-test elapsed time
  --backend NAME        tap (default) | test2
  --jsonl FILE          Emit JSONL events to FILE
  --log-dispatch CFG    Optional Log::Dispatch wiring
  --version             Print version and exit
  -h, --help            Show this help

If no test paths are given, discovers tests under t/ then xt/.
USAGE
    return $exit;
}

1;

__END__

=head1 NAME

App::Prover::CLI - command-line entry point for app-prover

=cut
