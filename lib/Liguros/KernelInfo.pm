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
);


sub _build_osrelease{
	load_from_file('osrelease');
}
sub _build_ostype{
	load_from_file('ostype');
}
sub _build_version{
	load_from_file('version');
}

sub  load_from_file {
	my $self = shift;
	my $file = shift;
	
	if ( open my $fh, '<', "/proc/sys/kernel/$file" ) {
		chomp( $self->$file = <$fh> );
        close $fh;
    }else {
        push @{$self->{errors}}, "Could not open file $file: $ERRNO";
    }	
}



1;
