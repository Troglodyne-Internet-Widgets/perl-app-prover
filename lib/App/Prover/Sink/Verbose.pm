package App::Prover::Sink::Verbose;

use strict;
use warnings;

use parent 'App::Prover::Sink';

use App::Prover::Event qw(:types);

sub emit {
    my ($self, $ev) = @_;
    my $fh   = $self->fh;
    my $type = $ev->{type};

    if ($type eq EV_STARTED) {
        print {$fh} "# === $ev->{file} ===\n";
        return;
    }
    if ($type eq EV_ENDED) {
        my $verdict = $ev->{exit} == 0 ? 'ok' : 'NOT OK';
        my $secs    = sprintf '%.3fs', ($ev->{elapsed_ms} || 0) / 1000;
        print {$fh} "# --- $ev->{file} $verdict ($secs) ---\n";
        return;
    }
    if (defined $ev->{raw}) {
        print {$fh} $ev->{raw}, "\n";
        return;
    }
}

sub flush_job { }

sub summary {
    my ($self, $agg) = @_;
    _print_summary($self->fh, $agg);
}

sub _print_summary {
    my ($fh, $stats) = @_;
    return unless $stats;
    my $total   = $stats->total;
    my $passed  = $stats->passed;
    my $failed  = $stats->failed;
    my $skipped = $stats->skipped;
    my $todo    = $stats->todo;
    my $verdict = $stats->all_passed ? 'PASS' : 'FAIL';
    my @failed_files = $stats->failed_files;
    my $elapsed = $stats->elapsed;
    print {$fh} "\n";
    if (@failed_files) {
        print {$fh} "Test Summary Report\n";
        print {$fh} "-------------------\n";
        for my $f (@failed_files) {
            print {$fh} "  $f\n";
        }
    }
    printf {$fh} "Result: %s  (Tests=%d Passed=%d Failed=%d Skipped=%d TODO=%d)  [%.2fs]\n",
        $verdict, $total, $passed, $failed, $skipped, $todo, $elapsed;
}

# expose for QVF reuse
sub _summary_print { _print_summary(@_) }

1;
