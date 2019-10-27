package Liguros::Lspci;

use Moose;                         #CPAN
use JSON;                          #core
use Carp;                          #core
use English qw(-no_match_vars);    #core
use 5.20.0;

has 'lspci_data' => (
    is  => 'ro',
    isa => 'HashRef',
);

has 'errors' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

sub BUILD {
    my $self  = shift;
    my $lspci = 'lspci -mmvvv';
    my %hash;
    if ( my $lspci_output = `$lspci` ) {
        my @hw_item_section = split( /^\n/msx, $lspci_output );

        my %item;
        for (@hw_item_section) {
            chomp;    # $hw_item;
            my @hw_item_lines = split(/\n/msx);

            for (@hw_item_lines) {
                chomp;
                s/\[\]|\{\}/[ ]/msx;
                my ( $key, $value ) = split(':\s');
                chomp $key;
                chomp $value;
                $item{$key} = $value;
               
            }

            foreach my $key_item ( keys %item ) {
                unless ( $key_item eq 'Slot' ) {
                    $self->{lspci_data}{ $item{'Slot'} }{$key_item} = $item{$key_item};
                }
            }
        }
    }
    else {
        push @{ $self->{errors} },
          "Could not retrieve output from $lspci: $ERRNO";
        return;
    }
}
1;
