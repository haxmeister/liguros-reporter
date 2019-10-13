package Liguros::KernelInfo;

use Moose;                         #CPAN
use JSON;                          #core
use Carp;                          #core
use English qw(-no_match_vars);    #core
use 5.20.0;

has 'osrelease' =>(
	is     => 'ro',
    lazy    => 1,
    builder => '_build_osrelease',
);
 
has 'ostype'    => (
    is     => 'ro',
    lazy    => 1,
    builder => '_build_ostype',
);

has 'version'   => (
	is     => 'ro',
    lazy    => 1,
    builder => '_build_version',	
);

has 'errors'    =>(
	is 		=> 'ro',
	isa		=> 'ArrayRef',
	default => sub{[]},
);
has 'Kernels_found' => (
	is => 'ro',
	isa => 'ArrayRef',
	lazy => 1,
	builder => '_kernels_in_boot',
);


sub _build_osrelease{
	my $self = shift;
	return $self->load_from_file('osrelease');
}
sub _build_ostype{
	my $self = shift;
	return $self->load_from_file('ostype');
}
sub _build_version{
	my $self = shift;
	return $self->load_from_file('version');
}

sub _kernels_in_boot {
	my $self = shift;
    my $boot_dir = "/boot";
    my @kernels;

    # pulling list of kernels in /boot
    if ( opendir( my $dh, $boot_dir ) ) {
        foreach my $file_name ( readdir($dh) ) {
            next unless ( -f "$boot_dir/$file_name" );    #only want files
            chomp $file_name;

            # let's grab the names of any files that start with
            # kernel, vmlinuz or bzImage
            if ( $file_name =~ m/^kernel|^vmlinuz|^bzImage/msx ) {
                push @kernels, $file_name;
            }
        }
        closedir($dh);
    }
    else {
        push( @{$self->{errors}}, "Cannot open directory $boot_dir, $ERRNO");
    }
	return \@kernels;
}

sub  load_from_file {
	my $self = shift;
	my $file = shift;
	my $contents;
	
	if ( open my $fh, '<', "/proc/sys/kernel/$file" ) {
		chomp( $contents = <$fh> );
        close $fh;
    }else {
        push @{$self->{errors}}, "Could not open file $file: $ERRNO";
    }
    return $contents;	
}



1;
