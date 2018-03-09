use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME             => 'Funtoo::Report',
    VERSION_FROM     => 'lib/Funtoo/Report.pm',
    EXE_FILES        => ['funtoo-report'],
    MIN_PERL_VERSION => '5.014',
    PREREQ_PM        => {
        'Exporter'        => 0,
        'HTTP::Tiny'      => 0,
        'JSON'            => 0,
        'POSIX'           => 0,
        'Term::ANSIColor' => 0,
    },
);
