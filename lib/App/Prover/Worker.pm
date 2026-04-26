package App::Prover::Worker;

use strict;
use warnings;

use Time::HiRes ();
use Config       ();
use POSIX        ();

use App::Prover::Event qw(:types new_event);

our $JOB_SEQ = 0;

sub run {
    my (%args) = @_;
    my $file    = $args{file}    or die "Worker::run requires file\n";
    my $backend = $args{backend} or die "Worker::run requires backend\n";
    my $emit    = $args{emit}    or die "Worker::run requires emit coderef\n";
    my $job_id  = defined $args{job_id} ? $args{job_id} : ($$ . ':' . ++$JOB_SEQ);
    my $env     = $args{env}     || {};
    my $perl    = $args{perl}    || $Config::Config{perlpath} || $^X;
    my $perl_args = $args{perl_args} || [];

    my $emit_with_ctx = sub {
        my %ev = %{ $_[0] };
        $ev{job_id} //= $job_id;
        $ev{file}   //= $file;
        $emit->(\%ev);
    };

    $emit_with_ctx->(new_event(type => EV_STARTED));

    my $start = Time::HiRes::time();

    pipe(my $reader, my $writer) or die "pipe failed: $!";

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        # child
        close $reader;
        my $wfd = fileno($writer);
        # Force the pipe writer onto fd 1/2 explicitly. open(STDOUT, '>&', ...)
        # is unreliable when STDOUT was a Perl in-memory filehandle (fileno -1)
        # because '>&' picks whatever free fd it can — frequently not fd 1 —
        # and then _close_inherited_fds() ends up closing the redirect.
        POSIX::dup2($wfd, 1) or do { print STDERR "dup2 STDOUT failed: $!\n"; exit 127 };
        POSIX::dup2($wfd, 2) or do { print STDERR "dup2 STDERR failed: $!\n"; exit 127 };
        POSIX::close($wfd) if $wfd > 2;

        open STDOUT, '>&=1' or do { print STDERR "rebind STDOUT failed: $!\n"; exit 127 };
        open STDERR, '>&=2' or do { print STDERR "rebind STDERR failed: $!\n"; exit 127 };

        _close_inherited_fds();

        $ENV{$_} = $env->{$_} for keys %$env;

        exec $perl, @$perl_args, $file
            or do { print STDERR "exec $perl $file failed: $!\n"; exit 127 };
    }

    close $writer;

    my $parser = $backend->parse(
        $emit_with_ctx,
        $reader,
        undef,
        { file => $file, job_id => $job_id },
    );

    close $reader;

    waitpid $pid, 0;
    my $status     = $?;
    my $exit_code  = $status >> 8;
    my $signal     = $status & 0x7f;
    my $elapsed_ms = int( ( Time::HiRes::time() - $start ) * 1000 );

    $emit_with_ctx->(new_event(
        type       => EV_ENDED,
        exit       => $exit_code,
        signal     => $signal,
        elapsed_ms => $elapsed_ms,
    ));

    return {
        job_id     => $job_id,
        file       => $file,
        parser     => $parser,
        exit       => $exit_code,
        signal     => $signal,
        elapsed_ms => $elapsed_ms,
    };
}

# Close inherited file descriptors above STDIN/STDOUT/STDERR so the exec'd test
# does not keep open the parent's IPC sockets (e.g. MCE's manager channels).
# Without this, the test's eventual exit closes those sockets and confuses
# whatever is listening on the parent side.
sub _close_inherited_fds {
    if (-d '/proc/self/fd') {
        opendir my $dh, '/proc/self/fd' or return;
        my @fds = sort { $a <=> $b } grep { /^\d+$/ && $_ > 2 } readdir $dh;
        closedir $dh;
        for my $fd (@fds) {
            POSIX::close($fd);
        }
        return;
    }
    # Portable fallback: brute-force close 3..1023.
    for my $fd (3 .. 1023) {
        POSIX::close($fd);
    }
}

1;

__END__

=head1 NAME

App::Prover::Worker - per-test executor

=head1 SYNOPSIS

    my $result = App::Prover::Worker::run(
        file    => 't/01-foo.t',
        backend => $backend_obj,
        emit    => sub { my ($event) = @_; ... },
        env     => { HARNESS_ACTIVE => 1 },
    );

=head1 DESCRIPTION

Forks a child, redirects child STDERR onto STDOUT, execs C<perl> on the test
file, hands the merged pipe to the backend, then reaps the child. Emits
synthetic C<started> and C<ended> events around the backend's per-line events.

=cut
