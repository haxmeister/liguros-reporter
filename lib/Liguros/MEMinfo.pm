package Liguros::MEMinfo;

use Moose;                         #CPAN
use JSON;                          #core
use Carp;                          #core
use English qw(-no_match_vars);    #core

has all_data => (
    is  => 'ro',
    isa => 'HashRef',
);

has mem_file => (
    is      => 'ro',
    default => '/proc/meminfo',
);

has errors => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has MemTotal => (
    is  => 'ro',
    isa => 'Int',
);
has MemFree => (
    is  => 'ro',
    isa => 'Int',
);
has MemAvailable => (
    is  => 'ro',
    isa => 'Int',
);
has SwapTotal => (
    is  => 'ro',
    isa => 'Int',
);
has SwapFree => (
    is  => 'ro',
    isa => 'Int',
);

my %data = (
    MemTotal     => undef,
    MemFree      => undef,
    MemAvailable => undef,
    SwapTotal    => undef,
    SwapFree     => undef,
);

sub BUILD {
    my $self = shift;
    my @mem_file_contents;

    if ( open( my $fh, '<:encoding(UTF-8)', $self->mem_file ) ) {
        @mem_file_contents = <$fh>;
        close $fh;
    }
    else {
        push(
            @{ $self->errors },
            "Could not open file" . $self->cpu_file . ": $ERRNO"
        );
        return;
    }

    foreach my $row (@mem_file_contents) {
        my ( $key, $value ) = $row =~ m/ (\S+) : \s* (\d+) /msx or next;
        exists $data{$key} or next;

        # Convert the size from KB to GB
        $data{$key} = sprintf '%.2f', ($value) / ( 1024**2 );
        $data{$key} += 0;
    }
    $self->{MemTotal}     = $data{MemTotal};
    $self->{MemFree}      = $data{MemFree};
    $self->{MemAvailable} = $data{MemAvailable};
    $self->{SwapTotal}    = $data{SwapTotal};
    $self->{SwapFree}     = $data{SwapFree};
    $self->{all_data}     = \%data;
}

1;
