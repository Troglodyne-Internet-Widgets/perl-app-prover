package App::Prover::Discovery;

use strict;
use warnings;

use File::Find ();
use File::Spec ();

sub discover {
    my ($argv, $exts, $recurse) = @_;

    my @args = @$argv ? @$argv : (-d 't' ? ('t') : (), -d 'xt' ? ('xt') : ());
    return () unless @args;

    my @files;
    for my $arg (@args) {
        if (-f $arg) {
            push @files, $arg;
            next;
        }
        if (-d _) {
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

1;

__END__

=head1 NAME

App::Prover::Discovery - locate test files for App::Prover

=head1 SYNOPSIS

    use App::Prover::Discovery ();
    my @files = App::Prover::Discovery::discover(
        \@argv,           # paths from CLI; empty falls back to t/ then xt/
        ['.t'],           # extensions to match
        $recurse,         # walk directories recursively?
    );

=head1 FUNCTIONS

=head2 discover(\@paths, \@exts, $recurse)

Returns the list of test files implied by C<\@paths>. Behavior:

=over 4

=item *

If C<\@paths> is empty, falls back to F<t/> if it exists, then F<xt/> if it
exists. If neither exists, returns an empty list.

=item *

Each path that is a file is taken verbatim.

=item *

Each path that is a directory is walked. With C<$recurse> false, only
direct children are considered; with C<$recurse> true, the full subtree.
Files whose extension is in C<\@exts> are kept; others are skipped.

=item *

Per-directory results are sorted for deterministic ordering. Across paths,
order follows C<\@paths>.

=item *

Each path that doesn't exist produces a warning to STDERR but doesn't abort
discovery — the caller decides whether the resulting (possibly empty) list
is fatal.

=back

C<\@exts> entries may be given with or without a leading dot
(C<'.t'> or C<'t'>).

=head1 EXTENDING

Discovery is intentionally a free function rather than a class so callers
that need a different strategy can swap it out without subclassing. Future
strategies (C<git ls-files>-based discovery, C<.testrc>-driven filters,
glob-matching, etc.) belong in their own modules with the same return
contract: a list of paths, deterministically ordered.

=cut
