use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'App::Prover',
    AUTHOR           => 'Andy Baugh <andy@troglodyne.net>',
    VERSION_FROM     => 'lib/App/Prover.pm',
    ABSTRACT         => 'A simple, fast, MCE-driven Perl test runner script',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.020',
    EXE_FILES        => ['bin/prover'],

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
    },
    TEST_REQUIRES => {
        'Test::More'  => '0.98',
        'File::Temp'  => '0',
        'File::Spec'  => '0',
    },
    PREREQ_PM => {
        'MCE'                    => '1.870',
        'MCE::Flow'              => '1.870',
        'TAP::Parser'            => '3.30',
        'TAP::Parser::Aggregator'=> '3.30',
        'Time::HiRes'            => '0',
        'IPC::Open3'             => '0',
        'Getopt::Long'           => '2.49',
        'File::Find'             => '0',
        'List::Util'             => '1.45',
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        prereqs => {
            runtime => {
                recommends => {
                    'Test2::Harness'   => 0,
                    'Log::Dispatch'    => 0,
                    'JSON::PP'         => 0,
                },
            },
        },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/teodesian/perl-app-prover.git',
                web  => 'https://github.com/teodesian/perl-app-prover',
            },
            bugtracker => {
                web => 'https://github.com/teodesian/perl-app-prover/issues',
            },
        },
    },

    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES => 'App-Prover-*' },
);
