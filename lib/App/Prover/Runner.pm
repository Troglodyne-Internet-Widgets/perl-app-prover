package App::Prover::Runner;

use strict;
use warnings;

use Time::HiRes ();
use Config      ();

use App::Prover::Backend ();
use App::Prover::Worker  ();
use App::Prover::Sink    ();
use App::Prover::Stats   ();
use App::Prover::Event   qw(:types);

our $VERSION = '0.001';

sub new {
    my ($class, %opts) = @_;
    $opts{jobs}    //= 1;
    $opts{verbose} //= 0;
    $opts{backend} //= 'tap';
    $opts{perl}    //= $Config::Config{perlpath} || $^X;
    $opts{perl_args} //= [];
    $opts{env}     //= {};

    my $backend_pkg = App::Prover::Backend->load($opts{backend});
    my $backend     = $backend_pkg->new(%{ $opts{backend_args} || {} });

    my $sinks = $opts{sinks} || _default_sinks(\%opts);

    return bless {
        opts    => \%opts,
        backend => $backend,
        sinks   => $sinks,
        stats   => App::Prover::Stats->new,
        failed  => 0,
    }, $class;
}

sub _default_sinks {
    my ($opts) = @_;
    require App::Prover::Sink::Log;
    return [
        App::Prover::Sink::Log->new(
            min_level => $opts->{verbose} ? 'info' : 'notice',
            live      => ($opts->{verbose} && ($opts->{jobs} // 1) <= 1) ? 1 : 0,
        ),
    ];
}

sub stats   { $_[0]->{stats} }
sub sinks   { $_[0]->{sinks} }
sub backend { $_[0]->{backend} }

sub run {
    my ($self, @files) = @_;

    my $opts = $self->{opts};
    my $env  = {
        HARNESS_ACTIVE     => 1,
        HARNESS_VERSION    => $VERSION,
        HARNESS_IS_VERBOSE => $opts->{verbose} ? 1 : 0,
        HARNESS_JOBS       => $opts->{jobs},
        %{ $opts->{env} || {} },
    };

    my $start = Time::HiRes::time();

    if ($opts->{jobs} <= 1) {
        $self->_run_serial(\@files, $env);
    }
    else {
        $self->_run_parallel(\@files, $env);
    }

    $self->{stats}->set_elapsed( Time::HiRes::time() - $start );

    $_->summary($self->{stats}) for @{ $self->{sinks} };

    return $self->{failed} ? 1 : 0;
}

sub _run_serial {
    my ($self, $files, $env) = @_;
    for my $file (@$files) {
        my $emit = sub {
            my ($ev) = @_;
            $_->emit($ev) for @{ $self->{sinks} };
        };
        my $result = App::Prover::Worker::run(
            file      => $file,
            backend   => $self->{backend},
            emit      => $emit,
            env       => $env,
            perl      => $self->{opts}{perl},
            perl_args => $self->{opts}{perl_args},
        );
        $result->{parser_stats} = App::Prover::Stats->extract($result->{parser});
        $self->_finish_test($result);
    }
}

sub _run_parallel {
    my ($self, $files, $env) = @_;
    require App::Prover::Runner::MCE;
    App::Prover::Runner::MCE::run_parallel($self, $files, $env);
}

sub _finish_test {
    my ($self, $result) = @_;
    my $verdict = $self->_verdict($result);
    $self->{failed}++ if $verdict eq 'fail';
    $_->flush_job($result->{job_id}, $verdict) for @{ $self->{sinks} };
    $self->{stats}->add($result->{file}, $result->{parser_stats}, $verdict);
}

sub _verdict {
    my ($self, $result) = @_;
    my $stats = $result->{parser_stats} || {};
    return 'fail' if $result->{exit} != 0;
    return 'fail' if $stats->{has_problems};
    return 'skip' if $stats->{skip_all};
    return 'pass';
}

1;

__END__

=head1 NAME

App::Prover::Runner - test discovery + orchestration

=cut
