package Funtoo::Report;

### Author : Joshua S. Day (haxmeister)
### purpose : functions for retrieving data on funtoo linux

use strict;
use warnings;
use Exporter;           #core
use JSON;               #cpan
use POSIX qw(ceil);     #core
use Term::ANSIColor;    #core
use HTTP::Tiny;         #core

our $VERSION = '1.4';

our @EXPORT_OK = qw(
    user_config
    get_kernel_info
    get_boot_dir_info
    get_version_info
    get_world_info
    get_profile_info
    get_kit_info
    add_uuid
    version
    get_all_installed_pkg
    report_time
    config_update
    get_hardware_info
    send_report);

### getting some initialization done:
my $config_file = '/etc/funtoo-report.conf';
my %lspci = ( 'PCI-Device' => get_lspci() );

##
## generates report, creates user agent, and sends to elastic search
##
sub send_report {
    my $rep     = shift;
    my $es_conf = shift;

    # constructing the url we will report too
    my $url = "$es_conf->{'node'}/$es_conf->{'index'}/$es_conf->{'type'}";

    # generate a json object that we can use to convert to json
    my $json = JSON->new->allow_nonref;

    # load the report options for the http post
    my %header = ( "Content-Type" => "application/json" );
    my %options = (
        'content' => $json->pretty->encode($rep),
        'headers' => \%header
    );

    # create a new HTTP object
    my $http = HTTP::Tiny->new();

    # send report and capture the response from ES
    my $response = $http->request( 'POST', $url, \%options );

}

##
## finds the config file in /etc/funtoo-report.conf and loads it's contents
## into a hash and returns it
#
sub user_config {
    my $args = shift;
    my %hash;

    if ( open( my $fh, '<:encoding(UTF-8)', $config_file ) ) {
        my @lines = <$fh>;
        close $fh;
        foreach my $line (@lines) {
            chomp $line;

            # skip lines that start with '#'
            if ( $line =~ /^\#/msx ) {
                next;
            }

            # split the line on the colon
            # left side becomes a key, right side a value
            elsif ($line) {
                my ( $key, $value ) = split /\s*:\s*/msx, $line;
                $hash{$key} = $value;
            }

            # skip the empty lines also
            else {
                next;
            }
        }
    }
    elsif ( $args and ( $args eq 'new' ) ) {

        # if we arrived here due to config-update() and there isn't
        # a config file then we return a UUID without editing the file
        $hash{'UUID'} = 'none';
        return;
    }
    else {
        # if we arrived here from the command line and there is no
        # config file then tell the user what to do
        print color( 'red', 'bold' );
        print "\nWarning!";
        print color('reset');
        print "\nCould not open the configuration file at $config_file \n";
        print
            "To generate a new configuration file use 'funtoo-report config-update' \n\n";
        exit;
    }

    return %hash;
}

## retrieves UUID from the config file if present and then
## prompts user as it generates settings for a new config file
## insures all new possibilities are in the config file from previous
## versions, etc.
#
sub config_update {

    # check for existing config
    my %old_config = user_config('new');
    my %new_config;

    # see if we picked up a current UUID from the old config
    if ( $old_config{'UUID'} ) {

        #since it's there we will add it to the new config file
        $new_config{'UUID'} = $old_config{'UUID'};
    }
    else {

        # since there is no previous UUID we will go get a new one
        $new_config{'UUID'} = add_uuid('new');
    }

    # let's ask the user about each report setting

    $new_config{'kernel-info'}
        = get_y_or_n('Report information about your active kernel?');

    $new_config{'boot-dir-info'}
        = get_y_or_n('Report available kernels in /boot ?');

    $new_config{'version-info'}
        = get_y_or_n('Report versions of key system softwares?');

    $new_config{'installed-pkgs'}
        = get_y_or_n('Report all packages installed on the system?');

    $new_config{'world-info'}
        = get_y_or_n('Report the contents of your world file?');

    $new_config{'profile-info'}
        = get_y_or_n('Report the output of "epro show-json"?');

    $new_config{'kit-info'}
        = get_y_or_n('Report the output of "ego kit show"?');

    $new_config{'hardware-info'}
        = get_y_or_n('Report information about your hardware and drivers?');


    # let's create or replace /etc/funtoo-report.conf
    print "Creating or replacing /etc/funtoo-report.conf\n";
    open( my $fh, '>:encoding(UTF-8)', $config_file )
        or die "could not open $config_file", $!;
    foreach my $key ( keys %new_config ) {
        print $fh "$key" . ":" . "$new_config{$key}\n";
    }
    close $fh;

}

##
## adds a uuid to /etc/funtoo-report.conf and/or returns it as a string
##
sub add_uuid {

    my $arg = shift;

    # lets just get a random identifier from the system
    open( my $fh, '<', '/proc/sys/kernel/random/uuid' ) or die $!;
    my $UUID = <$fh>;
    chomp $UUID;
    close $fh;

    # if we recieved the 'new' argument then we just want to return
    # the UUID without modifying the file. i.e. we came here from the
    # config-update function
    if ( $arg and ( $arg eq 'new' ) ) {
        return $UUID;
    }
    else {

        # since we got here because a UUID isn't present in the config
        # open the config file and append the UUID properly into the file
        open( $fh, '>>', $config_file ) or die $!;
        print $fh "\n# A unique identifier for this reporting machine \n";
        print $fh "UUID:$UUID\n";
        close $fh;
    }
    return $UUID;
}

##
## reporting version number
##
sub version {
    return $VERSION;
}

## returns a long date string for the report body or
## returns a string that is like 'funtoo-year-week' that is
## suitable for elasticsearch historical data management
##
## with special date formatting by request
sub report_time {
    my $format = shift;
    my %formats = (
        long => sub {
            my @t = @_;
            my $year = $t[5] + 1900;
            my $mon  = $t[4] + 1;
            my $day  = $t[3];
            my $hour = $t[2];
            my $min  = $t[1];
            my $sec  = $t[0];
            return sprintf '%04u-%02u-%02uT%02u:%02u:%02uZ',
                $year, $mon, $day, $hour, $min, $sec;
        },
        short => sub {
            my @t = @_;
            my $year = $t[5] + 1900;
            my $week = ceil(($t[7] + 1) / 7);
            return sprintf 'funtoo-%04u.%02u',
                $year, $week;
        },
    );
    exists $formats{$format}
        or return 'no time';
    return $formats{$format}->(gmtime);
}

##
## returns a hash ref with various hardware info that was
## derived from lspci -kmv and other functions
##
sub get_hardware_info {
    my %hash;

    for my $device( keys %{$lspci{'PCI-Device'}}  ) {
                    
        # fetching sound info from data structure
        if ( $lspci{'PCI-Device'}{$device}{'Class'} =~ /Audio|audio/msx ) {
            $hash{'audio'}{$device} = \%{$lspci{'PCI-Device'}{$device}};
        
        }

        # fetching video cards
        if ( $lspci{'PCI-Device'}{$device}{'Class'} =~ /VGA|vga/msx ) {
            $hash{'video'}{$device} = \%{$lspci{'PCI-Device'}{$device}};
        }
    }
    
    # fetching networking devices
    $hash{'networking'} = get_net_info();
    
    # fetching block devices
    $hash{'filesystem'} = get_filesystem_info();
    
    # fetching cpu info
    $hash{'cpu'} = get_cpu_info();
    
    # fetching memory info
    $hash{'memory'} = get_mem_info();
    
    # fetching chassis info
    $hash{'chassis'} = get_chassis_info();
    
    return \%hash;
}

##
## returns a hash ref containing networking device info
## by ShadowM00n this function goes directly to the source instead
## of making calls to external tools
##
sub get_net_info {
    use Carp;                          # Core
    use English qw(-no_match_vars);    # Core
    use autodie qw< :io >;

    my $interface_dir = '/sys/class/net';
    my $pci_ids       = '/usr/share/misc/pci.ids';
    my $usb_ids       = '/usr/share/misc/usb.ids';
    my %hash;
    my @interfaces;
    opendir my $dh, $interface_dir
        or croak "Unable to open dir $interface_dir: $ERRNO\n";
    while ( my $file = readdir $dh ) {
        if ( $file !~ /^[.]{1,2}$|^lo$/xms ) {
            push @interfaces, $file;
        }
    }
    closedir $dh;

### @interfaces

    for my $device (@interfaces) {
        my ( $vendor_id, $device_id, $id_file );

        # Create dummy entries for virtual devices and move on
        if ( !-d "$interface_dir/$device/device/driver/module" ) {
            $hash{$device}{'vendor'} = 'Virtual';
            $hash{$device}{'device'} = 'Virtual device';
            $hash{$device}{'driver'} = 'Virtual driver';
            next;
        }

        # Othewise, determine the driver via the path name
        my $driver = (
            split /[\/]/xms,
            readlink "$interface_dir/$device/device/driver/module"
        )[-1];
        ### $driver

        # Get the vendor ID (PCI)
        my $vendor_id_file = "/sys/class/net/$device/device/vendor";
        if ( -e $vendor_id_file ) {
            $id_file = $pci_ids;
            open my $fh, '<', $vendor_id_file
                or carp "Unable to open file $vendor_id_file: $ERRNO";
            $vendor_id = <$fh>;
            close $fh;
            chomp $vendor_id;
            $vendor_id =~ s/^0x//xms;

            # Get the device ID (PCI)
            my $device_id_file = "/sys/class/net/$device/device/device";
            open $fh, '<', $device_id_file
                or carp "Unable to open file $device_id_file: $ERRNO";
            $device_id = <$fh>;
            close $fh;
            chomp $device_id;
            $device_id =~ s/^0x//xms;

        }

        # Or get the vendor and device ID (USB)
        else {
            $vendor_id_file = "/sys/class/net/$device/device/uevent";
            $id_file        = $usb_ids;
            ## no critic [RequireBriefOpen]
            open my $fh, '<', $vendor_id_file
                or do {
                carp "Unable to open file $vendor_id_file: $ERRNO";
                next;
                };
            while (<$fh>) {
                if (/^PRODUCT=(.*)[\/](.*)[\/].*/xms) {
                    $vendor_id = sprintf '%04s', $1;
                    $device_id = sprintf '%04s', $2;
                    last;
                }
            }
            close $fh;
        }
        ### $vendor_id
        ### $device_id

        # Look up the proper device name from the id file
        my ( $vendor_name, $device_name );

        ## no critic [RequireBriefOpen]
        open my $fh, '<', $id_file
            or carp "Unable to open file $id_file $ERRNO\n";

     # Devices can share device IDs but not "underneath" a vendor ID, so we'll
     # want to get the first result under the vendor
        my $seen = 0;

        while (<$fh>) {

            if (/^$vendor_id[ ]{2}(.*)/xms) {
                $vendor_name = $1;
                chomp $vendor_name;
                $seen = 1;
            }
            if ( $seen == 1 && /^[\t]{1}$device_id[ ]{2}(.*)/xms ) {
                $device_name = $1;
                chomp $device_name;
                last;
            }
        }
        close $fh;
        ### $vendor_name
        ### $device_name
        $hash{$device}{'vendor'} = $vendor_name;
        $hash{$device}{'device'} = $device_name;
        $hash{$device}{'driver'} = $driver;
    }
    ### %hash
    return \%hash;
}

##
## fetching lsblk output
##
sub get_filesystem_info {
    my $json_from_lsblk
        = `lsblk --bytes --json -o NAME,FSTYPE,SIZE,MOUNTPOINT,PARTTYPE,RM,HOTPLUG,TRAN`;
    my $data = decode_json($json_from_lsblk);

   # we need to recursively transform the arrayref-of-hashref structures in
   # this output into hashrefs-of-hashrefs, indexed by the 'name' of each item

    # start a stack of references to objects to transform
    my @stack;

    # dispatch table of reference type to transformation method
    my %disp = (

        # pass hashes through unscathed, enqueuing all their values
        HASH => sub {
            my $obj = shift;
            for my $value ( values %{$obj} ) {
                push @stack, \$value;
            }
            return $obj;
        },

       # convert an arrayref of hashrefs in-place into a hashref by the "name"
       # member of each hashref, and enqueue all the original items
        ARRAY => sub {
            my $obj = shift;

            # start replacement hash
            my %rep;

            # iterate over the list items
            for my $item ( @{$obj} ) {

                # ensure we can actually translate this item, warn and skip it
                # if we can't
                eval {
                    my $type = ref $item
                        or die;
                    $type eq 'HASH'
                        or die;
                    exists $item->{name}
                        or die;
                    not exists $rep{ $item->{name} }
                        or die;

                    # item passes muster, put it into the replacement hash
                    $rep{ $item->{name} } = $item;
                    push @stack, \$item;

                } or warn "Failed arrayref item conversion\n";
            }

            # return a reference to the replacement hash, not the original
            # arrayref; we discard that
            return \%rep;
        },
    );

    # start with the root node on the stack
    push @stack, \$data;

    # iterative walk through the tree
    while (@stack) {

        # pop a reference off the stack
        my $ref = pop @stack;

        # get the object it points to
        my $obj = ${$ref};

        # skip any object that is not itself a reference
        my $type = ref $obj
            or next;

        # skip any object for which we don't have a handler defined
        exists $disp{$type}
            or next;

        # repoint the reference to the outcome of this type's dispatch method
        ${$ref} = $disp{$type}->($obj);
    }

    return $data;
}

##
## fetching lines from /proc/cpuinfo
##
sub get_cpu_info {

    my $cpu_file = '/proc/cpuinfo';
    my %hash;
    my @cpu_file_contents;
    my $proc_count = 0;
    if ( open( my $fh, '<:encoding(UTF-8)', $cpu_file ) ) {
        @cpu_file_contents = <$fh>;
        close $fh;

        foreach my $row (@cpu_file_contents) {
            chomp $row;
            if ($row) {

                # lets split each line on the colon, left is the key
                # right is the value
                my ( $key, $value ) = split /\s*:\s*/msx, $row;

                # now we will just look for the values we want and
                # add them to the hash
                if ( $key eq 'model name' ) {
                    $hash{$key} = $value;
                }
                elsif ( $key eq 'flags' ) {
                    my @cpu_flags = split / /, $value;
                    $hash{$key} = \@cpu_flags;
                }
                elsif ( $key eq 'cpu MHz' ) {
                    $hash{$key} = $value * 1;
                }
                elsif ( $key eq 'processor' ) {

                    # counting lines that are labeled 'processor' which
                    # should give us a number that users expect to see
                    # including logical and physical cores
                    $proc_count = $proc_count + 1;
                }
                else {next}
            }
        }
    }

    else { warn "Could not open file ' $cpu_file' $!"; }
    $hash{"processors"} = $proc_count;
    return \%hash;
}

##
## fetching a few lines from /proc/meminfo
##
sub get_mem_info {

    # pulling relevent info from /proc/meminfo
    my %hash = (
        MemTotal     => undef,
        MemFree      => undef,
        MemAvailable => undef,
        SwapTotal    => undef,
        SwapFree     => undef,
    );
    my $mem_file = '/proc/meminfo';
    my @mem_file_contents;
    if ( open( my $fh, '<:encoding(UTF-8)', $mem_file ) ) {
        @mem_file_contents = <$fh>;
        close $fh;

        foreach my $row (@mem_file_contents) {

            # get the key and the first numeric value
            my ( $key, $value ) = $row =~ m/ (\S+) : \s* (\d+) /msx
                or next;

            # if there's a hash bucket waiting for this value, add it
            exists $hash{$key} or next;
            $hash{$key} = int $value;
        }
    }
    else { warn "Could not open file ' $mem_file' $!"; }
    return \%hash;
}

##
## fetch information about the system chassi
##
sub get_chassis_info {
    my %hash;
    my $folder = "/sys/class/dmi/id/";
    my @id_files = ( 'chassis_type', 'chassis_vendor', 'product_name' );

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

    for my $file (@id_files) {
        if ( open( my $fh, '<', "$folder$file" ) ) {
            my $content = <$fh>;
            chomp $content;
            if ( $file eq "chassis_type" ) {
                $hash{$file} = $possible_id[$content];
            }
            else {
                $hash{$file} = $content;
            }
            close $fh;
        }
        else {
            $hash{$file} = $possible_id[0];
        }
    }
    return \%hash;

}


##
## fetching active profiles
## reconst output of epro show-json command
##
sub get_profile_info {

    # execute 'epro show-json' and capture it's output
    my $json_from_epro = `epro show-json`;
    my %profiles;
    my %sorted;

    # convert the output from json to a perl data structure
    my $data = decode_json($json_from_epro);
    %profiles = %$data;

    # we are going to reconstruct the epro output without the extra
    # 'shortname' keys, so that it is more easily used in elasticsearch
    foreach my $item ( keys(%profiles) ) {
        foreach my $final ( $profiles{$item} ) {
            foreach my $array_item ( @{$final} ) {
                push @{ $sorted{$item} }, $array_item->{'shortname'};
            }
        }
    }
    return \%sorted;
}

##
## fetching active kits
## applies /etc/ego.conf contents to the data structure
## at /var/git/meta-repo/metadata/kit-info.json and returns a structure
## that shows only the "active" kit
##
sub get_kit_info {

    my $meta_file = "/var/git/meta-repo/metadata/kit-info.json";
    my $meta_data;
    my $ego_conf = "/etc/ego.conf";
    my %hash;

    # decode and store meta file datastructure into $meta_data
    if ( open( my $fh, '<:encoding(UTF-8)', $meta_file ) ) {
        my @lines = <$fh>;
        close $fh;
        my $data = join( '', @lines );
        $meta_data = decode_json($data);

        # let's define our hash keys from the array found in this file
        foreach my $key ( @{ $meta_data->{"kit_order"} } ) {
            $hash{$key} = "undef";
        }
    }
    else {
        print "cannot open meta file";
    }

    # extract valid lines from ego.conf
    if ( open( my $fh, '<:encoding(UTF-8)', $ego_conf ) ) {
        my @lines = <$fh>;
        close $fh;
        foreach my $line (@lines) {
            chomp $line;
            if ( $line =~ /^\w/msx ) {
                my ( $kit, $value ) = split( /\s*=\s*/msx, $line );
                chomp $kit;
                chomp $value;

                # if the kit has been named in the meta data structure
                # we will plug that value into it
                if ( exists $hash{$kit} ) {
                    $hash{$kit} = $value;
                }
            }
        }
    }
    else {
        print "cannot open ego.conf";
    }

    # now lets finish filling out our hash with default settings
    # anywhere it is undef
    foreach my $key ( keys %hash ) {
        if ( $hash{$key} eq "undef" ) {
            $hash{$key} = $meta_data->{kit_settings}{$key}{default};
        }
    }
    return \%hash;
}


##
## fetching kernel information from /proc/sys/kernel
##
sub get_kernel_info {

    my $directory = '/proc/sys/kernel';
    my %hash;
    my @dir_contents;

    # pulling relevant info from /proc/sys/kernel
    opendir( DIR, $directory ) or die $!;
    @dir_contents = readdir(DIR);
    closedir(DIR);

    # let's search the directory tree and find the files we want
    foreach my $file (@dir_contents) {
        next unless ( -f "$directory/$file" );    #only want files

        # could be easy to add another file here
        if (   ( $file eq 'ostype' )
            or ( $file eq 'osrelease' )
            or ( $file eq 'version' ) )
        {
            # lets open the file we found and get it's contents
            if ( open( my $fh, '<:encoding(UTF-8)', "$directory/$file" ) ) {

                # just want the first line (there shouldn't be anything else)
                my $row = <$fh>;
                close $fh;
                chomp $row;
                $hash{$file} = $row;
            }
            else { warn "could not open file '$file' $!"; }
        }
    }
    return \%hash;
}    #end sub

##
## finding kernel files in boot
##
sub get_boot_dir_info {
    my %hash;
    my $boot_dir = "/boot";
    my @kernel_list;

    # pulling list of kernels in /boot
    opendir( DIR, $boot_dir ) or die "cannot access $boot_dir ", $!;
    foreach my $file ( readdir(DIR) ) {
        next unless ( -f "$boot_dir/$file" );    #only want files
        chomp $file;

        # lets grab the names of any files that start with
        # kernel, vmlinuz or bzImage
        if ( $file =~ m/^kernel|^vmlinuz|^bzImage/msx ) {
            push @kernel_list, $file;
        }
    }
    $hash{'available kernels'} = \@kernel_list;
    closedir(DIR);
    return \%hash;
}    #end sub

##
## fetching contents of /var/lib/portage/world
##
sub get_world_info {

    # reading in world file
    my @world_array;
    my %hash;
    my $world_file = '/var/lib/portage/world';
    if ( open( my $fh, '<:encoding(UTF-8)', $world_file ) ) {
        while ( my $row = <$fh> ) {
            chomp $row;
            if ($row) {
                push( @world_array, $row );
            }
        }
        close $fh;
    }
    else { warn "Could not open file $world_file $!"; }

    $hash{'world file'} = \@world_array;
    return \@world_array;
}    #end sub

##
## getting the full list of installed packages
##
sub get_all_installed_pkg {
    my %hash;
    my @results = `equery list -F'\$cpv' "*"`;
    for my $line (@results) {
        chomp $line;
        push @{ $hash{'pkgs'} }, $line;
    }
    $hash{'pkg-count'} = scalar @results;
    return \%hash;
}

##
## fetching versions of key softwares
##
sub get_version_info {

    my %hash;

   # specify which ebuilds to look at; use a "version" of "undef" for a single
   # version value, and a hashref "[]" for a list of version values
    my %ebuilds = (
        portage => {
            kit     => 'sys-apps',
            version => undef,
            section => 'portage version',
        },
        ego => {
            kit     => 'app-admin',
            version => undef,
            section => 'ego version',
        },
        python => {
            kit     => 'dev-lang',
            version => [],
            section => 'python versions',
        },
        gcc => {
            kit     => 'sys-devel',
            version => [],
            section => 'gcc versions',
        },
        glibc => {
            kit     => 'sys-libs',
            version => [],
            section => 'glibc versions',
        },
    );

    # iterate through the ebuilds hash to fill out the result hash

    for my $name ( keys %ebuilds ) {
        my $ebuild = $ebuilds{$name};

        # define a pattern for getting the version number of the ebuild from
        # its directory name
        my $pat = qr{
            \A         # start of string
            \Q$name\E  # quoted ebuild name
            -          # hyphen
            (\d.*)     # string beginning with digit
        }msx;

        # open the ebuild's directory, die horribly if we can't find it
        my $dn = "/var/db/pkg/$ebuild->{kit}";
        opendir my $dh, $dn
            or die "could not open $dn: $!\n";

        # iterate through directory entries
        while ( defined( my $entry = readdir $dh ) ) {

            # skip anything that doesn't match the version pattern
            my ($version) = $entry =~ $pat or next;

            # if the hash wants an array, push the version onto it and keep
            # iterating
            if ( ref $ebuild->{version} eq 'ARRAY' ) {
                push @{ $ebuild->{version} }, $version;
            }

            # otherwise, just set the value to the version and end the loop
            else {
                $ebuild->{version} = $version;
                last;
            }
        }

        # close the directory
        closedir $dh;

        # tie in this section of the final report
        $hash{ $ebuild->{section} } = $ebuild->{version};
    }
    return \%hash;
}

##
## parsing output from lspci -kmv and putting it in a useable data
## structure for use elswhere
##
sub get_lspci {

    my $lspci_output = `lspci -kmmvvv`;
    my @hardware_list;
    my @hw_item_section = split( /^\n/msx, $lspci_output );
    my %hash;
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
        
        
        foreach my $key_item (keys %item){
            unless ($key_item eq 'Slot'){
                $hash{$item{'Slot'}}{$key_item} = $item{$key_item};
            }
        }
    }
    return \%hash;
}

###########################################
############ misc functions ###############

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
