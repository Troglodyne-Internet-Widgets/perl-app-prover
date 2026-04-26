package App::Prover::Stats;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {
        descriptions => [],
        files        => {},
        files_failed => [],
        total        => 0,
        passed       => 0,
        failed       => 0,
        skipped      => 0,
        todo         => 0,
        todo_passed  => 0,
        parse_errors => 0,
        elapsed      => 0,
    }, $class;
}

sub extract {
    my ($class, $parser) = @_;
    return {
        tests_run     => $parser->tests_run,
        passed        => scalar( $parser->passed ),
        failed        => scalar( $parser->failed ),
        skipped       => scalar( $parser->skipped ),
        todo          => scalar( $parser->todo ),
        todo_passed   => scalar( $parser->todo_passed ),
        parse_errors  => scalar( $parser->parse_errors ),
        actual_passed => scalar( $parser->actual_passed ),
        actual_failed => scalar( $parser->actual_failed ),
        has_problems  => $parser->has_problems ? 1 : 0,
        skip_all      => $parser->skip_all     ? 1 : 0,
        is_good_plan  => $parser->is_good_plan ? 1 : 0,
        plan          => scalar( $parser->plan ),
    };
}

sub add {
    my ($self, $description, $stats, $verdict) = @_;
    push @{ $self->{descriptions} }, $description;
    $self->{files}{$description} = { %$stats, verdict => $verdict };
    push @{ $self->{files_failed} }, $description if $verdict eq 'fail';

    $self->{total}        += $stats->{tests_run}     || 0;
    $self->{passed}       += $stats->{passed}        || 0;
    $self->{failed}       += $stats->{failed}        || 0;
    $self->{skipped}      += $stats->{skipped}       || 0;
    $self->{todo}         += $stats->{todo}          || 0;
    $self->{todo_passed}  += $stats->{todo_passed}   || 0;
    $self->{parse_errors} += $stats->{parse_errors}  || 0;
}

sub all_passed     { $_[0]->{failed} == 0 && @{ $_[0]->{files_failed} } == 0 }
sub total          { $_[0]->{total} }
sub passed         { $_[0]->{passed} }
sub failed         { $_[0]->{failed} }
sub skipped        { $_[0]->{skipped} }
sub todo           { $_[0]->{todo} }
sub todo_passed    { $_[0]->{todo_passed} }
sub parse_errors   { $_[0]->{parse_errors} }
sub failed_files   { @{ $_[0]->{files_failed} } }
sub descriptions   { @{ $_[0]->{descriptions} } }
sub elapsed        { $_[0]->{elapsed} }
sub set_elapsed    { $_[0]->{elapsed} = $_[1] }

1;

__END__

=head1 NAME

App::Prover::Stats - lightweight test-run aggregator (MCE-friendly)

=head1 WHY NOT TAP::Parser::Aggregator

C<TAP::Parser> instances hold C<CODE> references and cannot be serialized
through Storable / MCE's IPC. This minimal aggregator collects only plain
scalars (counts plus per-file verdict) and is identical for the serial and
parallel paths.

=cut
