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
has 'errors' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
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
}

sub load_config {
    my $self = shift;

    $self->config_exists
      or die "No configuration file has been detected at "
      . $self->config_location . "\n";

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
            else {
                die "Invalid configuration detected in "
                  . $self->config_location
                  . "': key '$key' is not a valid option. Consider running '$PROGRAM_NAME --update-config'.\n";
            }
        }
    }

    $self->{UUID} or $self->{UUID} = $self->generate_new_UUID();
}

sub prompt_user {
    my $self = shift;
}

sub list_options {
    my $self = shift;
    my %options;

    $options{kernel_info}    = $self->{kernel_info};
    $options{boot_dir_info}  = $self->{boot_dir_info};
    $options{installed_pkgs} = $self->{installed_pkgs};
    $options{profile_info}   = $self->{profile_info};
    $options{kit_info}       = $self->{kit_info};
    $options{hardware_info}  = $self->{hardware_info};

    return \%options;
}

sub BUILD {
    my $self = shift;
    $self->{config_exists} = -e $self->config_location;

}

1;
