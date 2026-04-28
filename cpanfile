requires 'perl', '5.020';

requires 'MCE',                      '1.870';
requires 'MCE::Flow',                '1.870';
requires 'TAP::Parser',              '3.30';
requires 'TAP::Parser::Aggregator',  '3.30';
requires 'Time::HiRes',              '0';
requires 'IPC::Open3',               '0';
requires 'Getopt::Long',             '2.49';
requires 'File::Find',               '0';
requires 'List::Util',               '1.45';

recommends 'Test2::Harness', '0';
recommends 'Log::Dispatch',  '0';
recommends 'JSON::PP',       '0';

on 'configure' => sub {
    requires 'ExtUtils::MakeMaker', '6.64';
};

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'File::Temp', '0';
    requires 'File::Spec', '0';
    requires 'FindBin',    '0';
};

on 'develop' => sub {
    requires 'File::Path', '0';
};
