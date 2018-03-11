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
        'autodie'         => 0,
        'Carp'            => 0,
        'English'         => 0,
        'Exporter'        => 0,
        'Getopt::Long'    => 0,
        'HTTP::Tiny'      => 0,
        'JSON'            => 0,
        'List::Util'      => '1.33',
        'POSIX'           => 0,
        'Term::ANSIColor' => 0,
    },
);
