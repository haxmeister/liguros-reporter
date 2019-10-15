use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME             => 'Liguros::Report',
    VERSION_FROM     => 'lib/Liguros/Report.pm',
    EXE_FILES        => ['liguros-report'],
    MIN_PERL_VERSION => '5.014',
    PREREQ_PM        => {
        'Carp'            => 0,
        'English'         => 0,
        'Exporter'        => 0,
        'Getopt::Long'    => 0,
        'HTTP::Tiny'      => 0,
        'IO::Socket::SSL' => '1.56',
        'JSON'            => 0,
        'List::Util'      => '1.33',
        'Net::SSLeay'     => '1.49',
        'Pod::Usage'      => 0,
        'Term::ANSIColor' => 0,
        'Time::Piece'     => 0,
        'Moose'           => '2.2011',
    },
);
