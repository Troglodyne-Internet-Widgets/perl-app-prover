package App::Prover::Backend::TAP;

use strict;
use warnings;

use parent 'App::Prover::Backend';

use TAP::Parser            ();
use TAP::Parser::Aggregator();

use App::Prover::Event qw(:types new_event);

sub parse {
    my ($self, $emit, $stdout_fh, $stderr_fh, $ctx) = @_;

    my $parser = TAP::Parser->new( {
        source     => $stdout_fh,
        merge      => 0,
    } );

    while ( defined( my $r = $parser->next ) ) {
        $emit->( _result_to_event($r, $ctx) );
    }

    if ($stderr_fh) {
        while ( defined( my $line = <$stderr_fh> ) ) {
            chomp $line;
            $emit->( new_event(
                type => EV_COMMENT,
                raw  => $line,
                file => $ctx->{file},
                from => 'stderr',
            ) );
        }
    }

    return $parser;
}

sub _result_to_event {
    my ($r, $ctx) = @_;
    my $type = $r->type;

    if ($type eq 'test') {
        return new_event(
            type        => EV_TEST,
            raw         => $r->raw,
            ok          => $r->is_ok ? 1 : 0,
            test_num    => $r->number,
            description => $r->description,
            directive   => $r->directive   || undef,
            explanation => $r->explanation || undef,
            file        => $ctx->{file},
        );
    }
    if ($type eq 'plan') {
        return new_event(
            type => EV_PLAN,
            raw  => $r->raw,
            plan => {
                count    => $r->tests_planned,
                skip_all => ($r->directive && uc $r->directive eq 'SKIP') ? 1 : 0,
                reason   => $r->explanation,
            },
            file => $ctx->{file},
        );
    }
    if ($type eq 'comment') {
        return new_event(
            type => EV_COMMENT,
            raw  => $r->raw,
            file => $ctx->{file},
        );
    }
    if ($type eq 'bailout') {
        return new_event(
            type    => EV_BAILOUT,
            raw     => $r->raw,
            bailout => $r->explanation,
            file    => $ctx->{file},
        );
    }
    if ($type eq 'version') {
        return new_event(
            type => EV_VERSION,
            raw  => $r->raw,
            file => $ctx->{file},
        );
    }
    return new_event(
        type => EV_UNKNOWN,
        raw  => $r->raw,
        file => $ctx->{file},
    );
}

1;

__END__

=head1 NAME

App::Prover::Backend::TAP - default TAP::Parser-based backend

=cut
