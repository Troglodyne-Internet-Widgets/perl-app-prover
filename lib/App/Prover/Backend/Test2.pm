package App::Prover::Backend::Test2;

use strict;
use warnings;

use parent 'App::Prover::Backend';

use App::Prover::Event qw(:types new_event);

sub new {
    my ($class, %opts) = @_;
    eval { require Test2::Harness2::Collector::Parser::TapParser; 1 }
        or die "App::Prover::Backend::Test2 requires Test2::Harness installed\n";
    return $class->SUPER::new(%opts);
}

sub parse {
    my ($self, $emit, $stdout_fh, $stderr_fh, $ctx) = @_;

    my $stats = _new_stats();
    my $bailout;

    while ( defined( my $raw = readline $stdout_fh ) ) {
        chomp $raw;
        my $facet = Test2::Harness2::Collector::Parser::TapParser::parse_stdout_tap($raw);
        if ($facet) {
            my $ev = _facet_to_event($facet, $raw, $ctx);
            _accumulate($stats, $ev, $facet);
            $bailout = $ev->{bailout} if $ev->{type} eq EV_BAILOUT;
            $emit->($ev);
        }
        else {
            $emit->( new_event(
                type => EV_UNKNOWN,
                raw  => $raw,
                file => $ctx->{file},
            ) );
        }
    }

    if ($stderr_fh) {
        while ( defined( my $line = readline $stderr_fh ) ) {
            chomp $line;
            $emit->( new_event(
                type => EV_COMMENT,
                raw  => $line,
                file => $ctx->{file},
                from => 'stderr',
            ) );
        }
    }

    $stats->{has_problems} = 1 if $stats->{failed} || $stats->{parse_errors} || defined $bailout;
    return App::Prover::Backend::Test2::_FakeParser->new($stats);
}

sub _facet_to_event {
    my ($facet, $raw, $ctx) = @_;

    if ( my $assert = $facet->{assert} ) {
        my $is_pass = $assert->{pass} ? 1 : 0;
        my ($directive, $explanation);
        for my $am ( @{ $facet->{amnesty} || [] } ) {
            if ( $am->{tag} eq 'SKIP' ) {
                $directive   = 'SKIP';
                $explanation = $am->{details};
                last;
            }
            if ( $am->{tag} eq 'TODO' ) {
                $directive   = 'TODO';
                $explanation = $am->{details};
            }
        }
        return new_event(
            type        => EV_TEST,
            raw         => $raw,
            ok          => $is_pass,
            test_num    => $assert->{number},
            description => $assert->{details},
            directive   => $directive,
            explanation => $explanation,
            file        => $ctx->{file},
            facet_data  => $facet,
        );
    }

    if ( my $plan = $facet->{plan} ) {
        return new_event(
            type => EV_PLAN,
            raw  => $raw,
            plan => {
                count    => $plan->{count} // 0,
                skip_all => $plan->{skip}  ? 1 : 0,
                reason   => $plan->{details},
            },
            file       => $ctx->{file},
            facet_data => $facet,
        );
    }

    if ( my $control = $facet->{control} ) {
        if ( $control->{halt} || $control->{terminate} ) {
            return new_event(
                type    => EV_BAILOUT,
                raw     => $raw,
                bailout => $control->{details},
                file    => $ctx->{file},
                facet_data => $facet,
            );
        }
    }

    if ( $facet->{info} && @{ $facet->{info} } ) {
        return new_event(
            type       => EV_COMMENT,
            raw        => $raw,
            file       => $ctx->{file},
            facet_data => $facet,
        );
    }

    if ( $facet->{about} && $facet->{about}{details} && $facet->{about}{details} =~ /^TAP\s+version/i ) {
        return new_event(
            type       => EV_VERSION,
            raw        => $raw,
            file       => $ctx->{file},
            facet_data => $facet,
        );
    }

    return new_event(
        type       => EV_UNKNOWN,
        raw        => $raw,
        file       => $ctx->{file},
        facet_data => $facet,
    );
}

sub _new_stats {
    return {
        tests_run     => 0,
        passed        => 0,
        failed        => 0,
        skipped       => 0,
        todo          => 0,
        todo_passed   => 0,
        actual_passed => 0,
        actual_failed => 0,
        parse_errors  => 0,
        has_problems  => 0,
        skip_all      => 0,
        is_good_plan  => 1,
        plan          => 0,
    };
}

sub _accumulate {
    my ($stats, $ev, $facet) = @_;
    my $type = $ev->{type};
    if ($type eq EV_TEST) {
        $stats->{tests_run}++;
        if ($ev->{ok}) {
            $stats->{passed}++;
            $stats->{actual_passed}++;
        }
        else {
            if ($ev->{directive} && $ev->{directive} eq 'TODO') {
                $stats->{passed}++;   # TAP: not ok # TODO is a "pass"
            }
            else {
                $stats->{failed}++;
                $stats->{actual_failed}++;
            }
        }
        if ($ev->{directive} && $ev->{directive} eq 'SKIP') {
            $stats->{skipped}++;
        }
        if ($ev->{directive} && $ev->{directive} eq 'TODO') {
            $stats->{todo}++;
            $stats->{todo_passed}++ if $ev->{ok};
        }
    }
    elsif ($type eq EV_PLAN) {
        $stats->{plan}     = $ev->{plan}{count};
        $stats->{skip_all} = $ev->{plan}{skip_all} ? 1 : 0;
    }
    elsif ($facet && @{ $facet->{info} || [] }) {
        for my $i ( @{ $facet->{info} } ) {
            $stats->{parse_errors}++ if ($i->{tag} || '') eq 'PARSER';
        }
    }
}

# --- Fake parser duck-type for App::Prover::Stats::extract -----------------

package App::Prover::Backend::Test2::_FakeParser;

sub new {
    my ($class, $stats) = @_;
    return bless { stats => $stats }, $class;
}

sub _f { $_[0]->{stats}{$_[1]} }

sub tests_run     { $_[0]->_f('tests_run') }
sub passed        { $_[0]->_f('passed') }
sub failed        { $_[0]->_f('failed') }
sub skipped       { $_[0]->_f('skipped') }
sub todo          { $_[0]->_f('todo') }
sub todo_passed   { $_[0]->_f('todo_passed') }
sub parse_errors  { $_[0]->_f('parse_errors') }
sub actual_passed { $_[0]->_f('actual_passed') }
sub actual_failed { $_[0]->_f('actual_failed') }
sub has_problems  { $_[0]->_f('has_problems') }
sub skip_all      { $_[0]->_f('skip_all') }
sub is_good_plan  { $_[0]->_f('is_good_plan') }
sub plan          { $_[0]->_f('plan') }

1;

__END__

=head1 NAME

App::Prover::Backend::Test2 - parser backend driven by Test2::Harness2

=head1 DESCRIPTION

Wraps L<Test2::Harness2::Collector::Parser::TapParser> to emit normalized
App::Prover events with raw Test2 facet data attached under C<facet_data>.

The Test2::Harness distribution is an optional runtime dependency; if it is
not installed, instantiating this backend dies with a clear error.

=cut
