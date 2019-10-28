package Liguros::Report_Config;

use Moose;                         #CPAN
use JSON;                          #core
use Carp;                          #core
use English qw(-no_match_vars);    #core
use 5.20.0;

has 'config_location' => (
    is      => 'ro',
    default => '/etc/liguros-report.conf',
);
has 'config_exists' => (
    is      => 'ro',
    default => 0,
);

has 'CONFIG_VERSION' => (
	is 	   => 'ro',
	default => 0,
);

has 'UUID' => (
    is      => 'ro',
    default => 0,
);

has 'kernel_info' => (
    is      => 'ro',
    default => 'n',
);

has 'boot_dir_info' => (
    is      => 'ro',
    default => 'n',
);

has 'installed_pkgs' => (
    is      => 'ro',
    default => 'n',
);

has 'profile_info' => (
    is      => 'ro',
    default => 'n',
);

has 'kit_info' => (
    is      => 'ro',
    default => 'n',
);

has 'cpu_info' => (
    is      => 'ro',
    default => 'n',
);
has 'file_systems_info' => (
    is      => 'ro',
    default => 'n',
);
has 'networking_devices' => (
    is      => 'ro',
    default => 'n',
);
has 'memory_info' => (
    is      => 'ro',
    default => 'n',
);
has 'chassis_info' => (
    is      => 'ro',
    default => 'n',
);

has 'audio_devices' => (
	is      => 'ro',
	default => 'n',
);
has 'video_devices' => (
	is      => 'ro',
	default => 'n',
);
has 'errors' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

my $CURRENT_CONFIG_VERSION = 2;

my @options = (
	'kernel_info', 
	'boot_dir_info', 
	'installed_pkgs',
	'profile_info', 
	'kit_info', 
	'cpu_info', 
	'file_systems_info',
	'networking_devices', 
	'memory_info',
	'chassis_info',
	'audio_devices',
	'video_devices',
	'CONFIG_VERSION',
	'UUID',
);


sub generate_new_UUID {
    my $self = shift;
    open( my $ufh, '<', '/proc/sys/kernel/random/uuid' )
      or croak
      "Cannot open /proc/sys/kernel/random/uuid to generate a UUID: $ERRNO\n";
    my $UUID = <$ufh>;
    chomp $UUID;
    close $ufh;
    return $UUID;
}

sub save_config {
    my $self = shift;
    
    open( my $fh, '>', $self->config_location )
      or croak "Cannot open Config file at " . $self->config_location . "\n";
	
    foreach my $item (@options){
		print $fh "$item:".$self->{$item}."\n";
	}
	close $fh;	
}

sub load_config {
    my $self = shift;
    
    open( my $fh, '<', $self->config_location )
      or croak "Cannot open Config file at " . $self->config_location . "\n";
    my @lines = <$fh>;
    close $fh;

    foreach my $line (@lines) {
        chomp $line;

        # skip lines that start with '#'
        if ( $line =~ /^\#/msx ) { next; }

        if ($line) {
            my ( $key, $value ) = split /\s*:\s*/msx, $line;
            if ( exists $self->{$key} ) {
                $self->{$key} = $value;
            }
        }
    }
	unless ($self->{UUID}){
		$self->{UUID} = $self->generate_new_UUID();
		$self->append_to_file ("UUID:".$self->{UUID}."\n");
	}
}

sub list_options {
    my $self = shift;
    my %hash;
    foreach my $key (@options){
		unless (($key eq 'UUID') or ($key eq 'CONFIG_VERSION')){
			$hash{$key} = $self->{key};
		}
	}

    return \%hash;
}
sub update_config{
	my $self = shift;
	my %questions = (
		'kernel_info'       => "Include info about your kernel", 
		'boot_dir_info'     => "Include info in your /boot directory", 
		'installed_pkgs'    => "Include a list of all installed packages",
		'profile_info'      => "Include profile info", 
		'kit_info'          => "Include info about your kits", 
		'cpu_info'          => "Include info about your CPU", 
		'file_systems_info' => "Include info about your file system types",
		'networking_devices'=> "Include info about your networking devices", 
		'memory_info'       =>"Include info about your system's RAM",
		'chassis_info'      =>"Include info about your system chassis",
		'audio_devices'     =>"Include info about audio devices",
		'video_devices'     =>"Include info about video devices",
	);
	foreach my $key (keys %questions){
		$self->{$key} = get_y_or_n($questions{$key});
	}
	
	
	unless ($self->{UUID}){
		print"generating new\n";
		$self->{UUID} = $self->generate_new_UUID();
	}
	
	$self->{CONFIG_VERSION} = $CURRENT_CONFIG_VERSION;
	$self->save_config();

	
	
}
sub BUILD {
    my $self = shift;
    if (-e $self->config_location){
		$self->{config_exists} = 1;
		$self->load_config();
	}else{
		die "Missing config file at ".$self->config_location."\n";
	}

}
sub append_to_file{
	my $self = shift;
	my $append_line = shift;
    open( my $fh, '>>', $self->config_location )
      or croak "Cannot open Config file at " . $self->config_location . "\n";
	print $fh "$append_line\n";
    close $fh;
}

## accepts a string that is the question
## returns y or n or continues to prompt user
## until they answer correctly
sub get_y_or_n {
    my $arg = shift;

    my $answer = q( );
    while ( $answer !~ /^y(?:es)?$|^no?$|^$/ixms ) {

        # ask the question, with "yes" as the implied default
        print "$arg yes or no? [y]\n";
        $answer = readline *STDIN;
    }

    if ( $answer =~ /^y(?:es)?$|^$/ixms ) {
        return 'y';
    }
    elsif ( $answer =~ /^no?$/ixms ) {
        return 'n';
    }
}
1;
