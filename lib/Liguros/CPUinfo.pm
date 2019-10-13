package Liguros::CPUinfo;

use Moose;                         #CPAN
use JSON;                          #core
use Carp;                          #core
use English qw(-no_match_vars);    #core

has 'all_data' => (
    is  => 'ro',
    isa => 'HashRef',
);

has 'cpu_file' => (
    is      => 'ro',
    default => '/proc/cpuinfo',
);

has 'errors' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] }
);

has 'model'      => ( is => 'ro', );
has 'MHz'        => ( is => 'ro', );
has 'processors' => ( is => 'ro', );
has 'flags'      => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

my %data;

sub BUILD {
    my $self = shift;
    my @cpu_file_contents;
    my $proc_count = 0;

    if ( open( my $fh, '<:encoding(UTF-8)', $self->cpu_file ) ) {
        @cpu_file_contents = <$fh>;
        close $fh;
        push( @{ $self->errors }, 0 );
    }
    else {
        push(
            @{ $self->errors },
            "Could not open file" . $self->cpu_file . ": $ERRNO"
        );
        return;
    }

    foreach my $row (@cpu_file_contents) {
        chomp $row;
        if ($row) {

            my ( $key, $value ) = split /\s*:\s*/msx, $row;

            if ( $key eq 'model name' ) {
                $data{model} = $value;
            }
            elsif ( $key eq 'flags' ) {
                my @cpu_flags = split / /, $value;
                $data{flags} = \@cpu_flags;
            }
            elsif ( $key eq 'cpu MHz' ) {
                $data{MHz} = $value * 1;
            }
            elsif ( $key eq 'processor' ) {
                $proc_count = $proc_count + 1;
            }
        }
    }

    $data{processors} = $proc_count;

    $self->{processors} = $data{processors};
    $self->{MHz}        = $data{MHz};
    $self->{flags}      = $data{flags};
    $self->{model}      = $data{model};
    $self->{all_data}   = \%data;
}

1;
