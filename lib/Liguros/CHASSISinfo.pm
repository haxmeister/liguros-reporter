package Liguros::CHASSISinfo;

use Moose;                         #CPAN
use JSON;                          #core
use Carp;                          #core
use English qw(-no_match_vars);    #core

has errors => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);
has chassis_type   => ( is => 'ro', );
has product_name   => ( is => 'ro', );
has chassis_vendor => ( is => 'ro', );
has all_data       => (
    is  => 'ro',
    isa => 'HashRef',
);

my %data;
my $content;
my $folder      = "/sys/class/dmi/id/";
my @id_files    = ( 'chassis_type', 'chassis_vendor', 'product_name' );
my @possible_id = (
    'N/A',
    'Other',
    'Unknown',
    'Desktop',
    'Low Profile Desktop',
    'Pizza Box',
    'Mini Tower',
    'Tower',
    'Portable',
    'Laptop',
    'Notebook',
    'Hand Held',
    'Docking Station',
    'All in One',
    'Sub Notebook',
    'Space-Saving',
    'Lunch Box',
    'Main Server Chassis',
    'Expansion Chassis',
    'SubChassis',
    'Bus Expansion Chassis',
    'Peripheral Chassis',
    'RAID Chassis',
    'Rack Mount Chassis',
    'Sealed-Case PC',
    'Multi-system Chassis',
    'Compact PCI',
    'Advanced TCA',
    'Blade',
    'Blade Enclosure',
    'Tablet',
    'Convertible',
    'Detachable',
    'IoT Gateway',
    'Embedded PC',
    'Mini PC',
    'Stick PC'
);

sub BUILD {
    my $self = shift;
    for my $file (@id_files) {
        if ( open( my $fh, '<', "$folder$file" ) ) {
            $content = <$fh>;
            chomp $content;
            close $fh;
            @{ $self->errors->[0] } = 0;
        }
        else {
            push(
                @{ $self->errors },
                "Could not open file" . $folder$file . ": $ERRNO"
            );
            next;
        }

        if ( $file eq "chassis_type" ) {
            $data{$file} = $possible_id[$content];
        }
        else {
            $data{$file} = $content;
        }
    }
    $self->{chassis_type}   = $data{chassis_type};
    $self->{chassis_vendor} = $data{chassis_vendor};
    $self->{product_name}   = $data{product_name};
    $self->{all_data}       = \%data;
}

1;
