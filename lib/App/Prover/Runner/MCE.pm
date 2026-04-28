package App::Prover::Runner::MCE;

use strict;
use warnings;

use MCE::Flow;

use App::Prover::Worker ();
use App::Prover::Stats  ();

our $CURRENT;

sub on_event {
    my ($event) = @_;
    return unless $CURRENT;
    $_->emit($event) for @{ $CURRENT->{sinks} };
}

sub on_result {
    my ($result) = @_;
    return unless $CURRENT;
    $CURRENT->_finish_test($result);
}

sub run_parallel {
    my ($runner, $files, $env) = @_;

    local $CURRENT = $runner;

    my $backend   = $runner->{backend};
    my $perl      = $runner->{opts}{perl};
    my $perl_args = $runner->{opts}{perl_args};
    my $jobs      = $runner->{opts}{jobs};
    my $preload   = $runner->{opts}{preload} ? 1 : 0;

    my $worker_func = sub {
        my ($mce, $chunk_ref) = @_;
        for my $file (@$chunk_ref) {
            my $emit = sub {
                MCE->do('App::Prover::Runner::MCE::on_event', $_[0]);
            };
            local $@;
            my $result = eval {
                App::Prover::Worker::run(
                    file      => $file,
                    backend   => $backend,
                    emit      => $emit,
                    env       => $env,
                    perl      => $perl,
                    perl_args => $perl_args,
                    preload   => $preload,
                );
            };
            if ($@) {
                $result = {
                    file       => $file,
                    job_id     => "$$:?",
                    exit       => 255,
                    signal     => 0,
                    elapsed_ms => 0,
                    error      => "$@",
                };
            }
            $result->{parser_stats} = $result->{parser}
                ? App::Prover::Stats->extract($result->{parser})
                : { has_problems => 1, tests_run => 0, passed => 0, failed => 0 };
            delete $result->{parser};
            MCE->gather($result);
        }
    };

    MCE::Flow->init(
        max_workers => $jobs,
        chunk_size  => 1,
        gather      => \&on_result,
    );

    MCE::Flow->run( $worker_func, $files );

    MCE::Flow->finish;
}

1;

__END__

=head1 NAME

App::Prover::Runner::MCE - parallel test dispatch via MCE::Flow

=head1 DESCRIPTION

Spawns C<jobs> MCE workers, each consuming one test file at a time, draining
events through the configured backend, streaming events to the manager via
C<MCE-E<gt>do('App::Prover::Runner::MCE::on_event', $event)>, and gathering
the per-test result on completion.

The L<TAP::Parser> instance held by the worker cannot be serialized across
the MCE boundary, so the worker extracts a primitive stats hash via
L<App::Prover::Stats/extract> before gathering.

=head1 NOTE

Use C<use MCE::Flow;> rather than C<use MCE::Flow ();>. MCE::Flow's C<import>
populates per-caller-package default options (C<MAX_WORKERS>, C<CHUNK_SIZE>);
without the import, those defaults are undef and run() is unable to chunk the
input data correctly.

=cut
