package Funtoo::Report;

### Authors : Joshua S. Day (haxmeister), Tom Ryder, ShadowM00n
### purpose : functions for retrieving and sending data on funtoo linux

use 5.014;
use strict;
use warnings;
use Carp;                            #core
use English qw(-no_match_vars);      #core
use HTTP::Tiny;                      #core
use JSON;                            #cpan
use List::Util qw(any);              #core
use Term::ANSIColor;                 #core
use Time::Piece;                     #core
use Time::HiRes qw(gettimeofday);    #core

our $VERSION = '4.0.0-beta';

### getting some initialization done:
our $config_file = '/etc/funtoo-report.conf';
our $VERBOSE;
my @errors;                          # for any errors that don't cause a die
my %timers;

##
## generates report, creates user agent, and sends to elastic search
##
sub send_report {
    my ( $rep, $es_conf, $debug ) = @_;
    my $url;
    my $settings_url;
    my $start_time = gettimeofday;

    # if we weren't told whether to show debugging output, don't
    $debug //= 0;

    # refuse to send a report with an unset, undefined, or empty UUID
    length $rep->{'funtoo-report'}{UUID}
      or do {
        push_error(
            'Refusing to submit report with blank UUID; check your config');
        croak;
      };

    # lets set where the data is sent, could be development version
    # or not.. or possibly a bug report, depending on the es_conf hash
    # that we were sent
    ( $url, $settings_url ) =
      @{ set_es_index( $es_conf, $url, $settings_url ) };

    # generate a json object that we can use to convert to json
    my $json = JSON->new->allow_nonref;

    # load the report options for the http post
    my %header = ( "Content-Type" => "application/json" );
    my %options = (
        'content' => $json->pretty->encode($rep),
        'headers' => \%header
    );

    # create a new HTTP object
    my $agent = sprintf '%s/%s', __PACKAGE__, $VERSION;
    my $http = HTTP::Tiny->new( agent => $agent );

    # send report and capture the response from ES
    my $response = $http->request( 'POST', $url, \%options );

    # if debugging, dump the entire response content
    if ($debug) {
        print {*STDERR} "$response->{content}\n";
    }

    # error out or retry helpfully on failed submission
    $response->{success}
      or do {

        # decode response contents
        my $response_decoded = decode_json( $response->{content} );
        my $current_limit    = 0;

        # check the root cause of each error for field limit error
        foreach my $error_reason ( @{ $response_decoded->{error}{root_cause} } )
        {

            # capture the field limit number from any field limit error
            if ( $error_reason->{reason} =~
                /Limit[ ]of[ ]total[ ]fields[ ]\[ (\d*) \]/msx )
            {
                $current_limit = $1;
            }
        }

        # if we have found a field limit error
        # we will call a function to attempt to raise it by 1000
        # unless the limit is already at 5000 or more
        if ($current_limit) {

            # check current field limit
            if ( $current_limit >= 10000 ) {
                croak
"field limit error but field limit is already at max 5000 or more";
            }

            # if we successfully increased the field limit
            # then we can call send_report again and start over
            if ( fix_es_limit( $current_limit, $settings_url, $debug ) ) {
                $timers{'total'} += $timers{'fix_es_limit'};
                send_report( $rep, $es_conf, $debug );
                exit;
            }
        }

        croak "Failed submission: $response->{status} $response->{reason}";
      };

    # warn if the response code wasn't 201 (Created)
    $response->{status} == 201
      or push_error(
        'Successful submission, but status was not the expected \'201 Created\''
      );

    # print location redirection if there was one, warn if not
    if ( defined $response->{headers}{location} ) {
        if ($VERBOSE) {
            print "your report can be seen at: "
              . $es_conf->{'node'}
              . $response->{'headers'}{'location'} . "\n";
        }
    }
    else {
        push_error('Expected location for created resource');
    }
}

##
## finds the config file in and loads its contents into a hash and returns it
##
sub user_config {
    my $args = shift;
    my %hash;
    my $start_time = gettimeofday;
    if ( open( my $fh, '<:encoding(UTF-8)', $config_file ) ) {
        my @lines = <$fh>;
        close $fh;

        my @known_options =
          qw(UUID boot-dir-info hardware-info installed-pkgs kernel-info kit-info profile-info bug-report);

        foreach my $line (@lines) {
            chomp $line;

            # skip lines that start with '#'
            if ( $line =~ /^\#/msx ) {
                next;
            }

            # split the line on the colon
            # left side becomes a key, right side a value
            # then, unless it's a new config, check that it's a known option...
            elsif ($line) {
                my ( $key, $value ) = split /\s*:\s*/msx, $line;
                if ( !$args ) {
                    if ( any { $_ eq $key } @known_options ) {
                        $hash{$key} = $value;
                    }
                    else {
                        die
"Invalid configuration detected in '$config_file': key '$key' is not a valid option. Consider running '$PROGRAM_NAME --update-config'.\n";
                    }
                }
            }
        }

        # ...and that all the options are present
        if ( !$args ) {
            for my $option (@known_options) {
                if ( !exists $hash{$option} ) {
                    die
"Missing essential configuration option ($option) in '$config_file'. Consider running '$PROGRAM_NAME --update-config.\n";
                }
            }
        }
    }
    elsif ( $args and ( $args eq 'new' ) ) {

        # if we arrived here due to update-config() and there isn't
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
"To generate a new configuration file use 'funtoo-report --update-config' \n\n";
        exit;
    }

    return %hash;
}

## retrieves UUID from the config file if present and then
## prompts user as it generates settings for a new config file
## ensures all new possibilities are in the config file from previous
## versions, etc.
sub update_config {

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

    $new_config{'kernel-info'} =
      get_y_or_n('Report information about your active kernel?');

    $new_config{'boot-dir-info'} =
      get_y_or_n('Report available kernels in /boot ?');

    $new_config{'installed-pkgs'} =
      get_y_or_n('Report all packages installed on the system?');

    $new_config{'profile-info'} =
      get_y_or_n('Report the output of "epro show-json"?');

    $new_config{'kit-info'} =
      get_y_or_n('Report the output of "ego kit show"?');

    $new_config{'hardware-info'} =
      get_y_or_n('Report information about your hardware and drivers?');
      
    $new_config{'bug-report'} =
	  get_y_or_n('Report build failure bug reports? Contains emerge --info, build.log, the ENV and such'); 

    # let's create or replace the configuration file
    my $timestamp = localtime;
    print "Creating or replacing $config_file\n";
    open( my $fh, '>:encoding(UTF-8)', $config_file )
      or croak "Could not open $config_file: $ERRNO\n";
    printf {$fh} "# Generated on %s for v%s of funtoo-report\n", $timestamp,
      $VERSION;
    foreach my $key ( sort keys %new_config ) {
        print {$fh} "$key:$new_config{$key}\n";
    }
    close $fh;

}

##
## adds a uuid to the config file and/or returns it as a string
##
sub add_uuid {

    my $arg        = shift;
    my $start_time = gettimeofday;

    # lets just get a random identifier from the system or die trying
    open( my $ufh, '<', '/proc/sys/kernel/random/uuid' )
      or croak
      "Cannot open /proc/sys/kernel/random/uuid to generate a UUID: $ERRNO\n";
    my $UUID = <$ufh>;
    chomp $UUID;
    close $ufh;

    # if we recieved the 'new' argument then we just want to return
    # the UUID without modifying the file. i.e. we came here from the
    # update-config function
    if ( $arg and ( $arg eq 'new' ) ) {
        return $UUID;
    }
    else {

        # since we got here because a UUID isn't present in the config
        # open the config file and append the UUID properly into the file
        open( my $cfh, '>>', $config_file )
          or croak "Unable to append to $config_file: $ERRNO\n";
        print {$cfh} "UUID:$UUID\n";
        close $cfh;
    }
    $timers{'add_uuid'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return $UUID;
}

##
## reporting version number
##
sub version {
    return $VERSION;
}

##
## returns hash of times and also a total of them all
##
sub timer {
    my $total;
    foreach my $key ( keys %timers ) {
        $total += $timers{$key};
    }
    $timers{'total'} = $total;
    return \%timers;
}

##
## reporting errors
##
sub errors {
    return \@errors;
}

## returns a long date string for the report body or
## returns a string that is like 'funtoo-year.week' that is
## suitable for elasticsearch historical data management
##
## with special date formatting by request
sub report_time {
    my $format    = shift;
    my $t         = gmtime;
    my $short_fmt = $t->date;
    $short_fmt =~ s/-/\./g;
    my %formats = (

        # ISO8601 date and time with UTC timezone suffix "Z"
        # e.g. 2018-03-09T22:37:09Z
        long => $t->datetime . 'Z',

        # date with dots for elastic search
        # e.g. 2018.03.18
        short => $short_fmt,

    );
    exists $formats{$format}
      or do { push_error('Unable to determine the time'); return };
    return $formats{$format};
}

##
## returns a hash ref with various hardware info that was
## derived from lspci -kmmvvv and other functions
##
sub get_hardware_info {
    my %hash;
    my $start_time = gettimeofday;
    my %lspci = ( 'PCI-Device' => get_lspci() );

    for my $device ( keys %{ $lspci{'PCI-Device'} } ) {

        # fetching sound info from data structure
        if ( $lspci{'PCI-Device'}{$device}{'Class'} =~ /Audio|audio/msx ) {
            $hash{'audio'}{$device} = \%{ $lspci{'PCI-Device'}{$device} };

        }

        # fetching video cards
        if ( $lspci{'PCI-Device'}{$device}{'Class'} =~ /VGA|vga/msx ) {
            $hash{'video'}{$device} = \%{ $lspci{'PCI-Device'}{$device} };
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

    $timers{'get_hardware_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## returns a hash ref containing networking device info
## by ShadowM00n
## this function goes directly to the source instead
## of making calls to external tools
##
sub get_net_info {
    my $start_time    = gettimeofday;
    my $interface_dir = '/sys/class/net';
    my $pci_ids       = '/usr/share/misc/pci.ids';
    my $usb_ids       = '/usr/share/misc/usb.ids';
    my %hash;
    my @interfaces;
    opendir my $dh, $interface_dir
      or do { push_error("Unable to open dir $interface_dir: $ERRNO"); return };
    while ( my $file = readdir $dh ) {

        if ( $file !~ /^[.]{1,2}$|^lo$/xms ) {
            push @interfaces, $file;
        }
    }
    closedir $dh;

### @interfaces

    for my $device (@interfaces) {
        my ( $vendor_id, $device_id, $id_file );

        # Ignore virtual devices
        if ( !-d "$interface_dir/$device/device/driver/module" ) {
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
              or do {
                push_error("Unable to open file $vendor_id_file: $ERRNO");
                next;
              };
            $vendor_id = <$fh>;
            close $fh;
            chomp $vendor_id;
            $vendor_id =~ s/^0x//xms;

            # Get the device ID (PCI)
            my $device_id_file = "/sys/class/net/$device/device/device";
            open $fh, '<', $device_id_file
              or do {
                push_error("Unable to open file $device_id_file: $ERRNO");
                next;
              };
            $device_id = <$fh>;
            close $fh;
            chomp $device_id;
            $device_id =~ s/^0x//xms;

        }

        # Or get the vendor and device ID (USB)
        else {
            $vendor_id_file = "/sys/class/net/$device/device/uevent";
            $id_file        = $usb_ids;
            open my $fh, '<', $vendor_id_file
              or do {
                push_error("Unable to open file $vendor_id_file: $ERRNO");
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

        # Look up the proper device name from the id file
        my ( $vendor_name, $device_name );

        ## no critic [RequireBriefOpen]
        open my $fh, '<', $id_file
          or do { push_error("Unable to open file $id_file $ERRNO"); next };

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
        $hash{$device} = {
            vendor => $vendor_name,
            device => $device_name,
            driver => $driver,
        };
    }
    $timers{'get_net_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## fetching lsblk output
## reconstructing the output to show a more flattened list
## with only info that actually has value as a statistic
##
sub get_filesystem_info {
    my %hash;
    my $start_time = gettimeofday;
    my $lsblk =
      `lsblk --bytes --json -o NAME,FSTYPE,SIZE,PARTTYPE,TRAN,HOTPLUG`;
    my $lsblk_decoded = decode_json($lsblk);

    fs_recurse( \@{ $lsblk_decoded->{blockdevices} }, \%hash );
    $timers{'get_filesystem_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## fetching lines from /proc/cpuinfo
##
sub get_cpu_info {

    my $cpu_file = '/proc/cpuinfo';
    my %hash;
    my @cpu_file_contents;
    my $proc_count = 0;
    my $start_time = gettimeofday;

    if ( open( my $fh, '<:encoding(UTF-8)', $cpu_file ) ) {
        @cpu_file_contents = <$fh>;
        close $fh;

        foreach my $row (@cpu_file_contents) {
            chomp $row;
            if ($row) {

                # let's split each line on the colon, left is the key
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
            }
        }
    }

    else {
        push_error("Could not open file $cpu_file: $ERRNO");
        return;
    }
    $hash{"processors"} = $proc_count;
    $timers{'get_cpu_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## fetching a few lines from /proc/meminfo
##
sub get_mem_info {
    my $start_time = gettimeofday;

    # pulling relevant info from /proc/meminfo
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

            # Convert the size from KB to GB
            $hash{$key} = sprintf '%.2f', ($value) / ( 1024**2 );
            $hash{$key} += 0;
        }
    }
    else {
        push_error("Could not open file $mem_file: $ERRNO");
        return;
    }
    $timers{'get_mem_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## fetch information about the system chassis
##
sub get_chassis_info {
    my %hash;
    my $folder     = "/sys/class/dmi/id/";
    my @id_files   = ( 'chassis_type', 'chassis_vendor', 'product_name' );
    my $start_time = gettimeofday;

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
            push_error("Unable to open $folder$file: $ERRNO");
            $hash{$file} = $possible_id[0];
        }
    }
    $timers{'get_boot_dir_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;

}

##
## fetching active profiles
## reconstruct output of epro show-json command
##
sub get_profile_info {
    my $start_time = gettimeofday;

    # execute 'epro show-json' and capture its output
    my $epro = 'epro show-json';
    if ( my $json_from_epro = `$epro` ) {
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
        $timers{'get_profile_info'} =
          sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
        return \%sorted;
    }
    else {
        push_error("Unable to retrieve output from $epro: $ERRNO");
        return;
    }
}

##
## fetching active kits
## applies /etc/ego.conf contents to the data structure
## at /var/git/meta-repo/metadata/kit-info.json and returns a structure
## that shows only the "active" kit
##
sub get_kit_info {

    my $meta_file = "/var/git/meta-repo/metadata/kit-info.json";
    my $ego_conf  = "/etc/ego.conf";
    my %ego_conf_hash;
    my $meta_data;
    my %hash;
    my $start_time = gettimeofday;

    # decode and store meta file datastructure into $meta_data
    if ( open( my $fh, '<:encoding(UTF-8)', $meta_file ) ) {
        my @lines = <$fh>;
        close $fh;
        my $data = join( '', @lines );
        $meta_data = decode_json($data);
    }
    else {
        push_error("Cannot open file $meta_file: $ERRNO");
        return;
    }

    # extract valid lines from ego.conf
    if ( open( my $fh, '<:encoding(UTF-8)', $ego_conf ) ) {
        my @lines = <$fh>;
        close $fh;
        my $last_section
          ;    # contains the last ini style section marker during iteration

        foreach my $line (@lines) {
            chomp $line;

            # skip comments and empty lines
            if ( $line =~ /^\#/msx )   { next; }
            if ( $line =~ /^\s*$/msx ) { next; }

            # looking for section tag
            if ( $line =~ /\[(\w*)\]/msx ) {
                $last_section = $1;
            }

            # looking for key = value pair
            if ( $line =~ /^\w/msx ) {
                my ( $kit, $value ) = split( /\s*=\s*/msx, $line );
                chomp $kit;
                chomp $value;

                if ($last_section) {
                    $ego_conf_hash{$last_section}{$kit} = $value;
                }
            }
        }
    }
    else {
        push_error("Cannot open file $ego_conf: $ERRNO");
        return;
    }

    # where a version is specified in the world section of ego.conf
    # we will first fill out the hash table with the specified defs
    # found in the meta.json file's release_defs section
    if ( exists $ego_conf_hash{'global'}{'release'} ) {

        # checking that the version found in ego.conf is defined in
        # the metadata.json file under release_defs
        if (
            exists $meta_data->{'release_defs'}
            { $ego_conf_hash{'global'}{'release'} } )
        {
            my $version = $ego_conf_hash{'global'}{'release'};

            # since it exists, lets load the hash first with the values given in
            # the release_defs section of the meta file
            foreach my $kit ( keys %{ $meta_data->{'release_defs'}{$version} } )
            {
                $hash{$kit} = $meta_data->{'release_defs'}{$version}{$kit}[0];
            }
        }
    }

    # if a version is not specified in ego.conf [world] section
    # we load the hash with the defaults
    else {
        foreach my $key ( keys %hash ) {
            if ( !defined $hash{$key} ) {
                $hash{$key} = $meta_data->{kit_settings}{$key}{default};
            }
        }
    }

    # lastly we will look at the [kits] section of ego.conf and if
    # anything has been defined here, we will override the current
    # value in the hash with this value.
    if ( exists $ego_conf_hash{'kits'} ) {
        for my $key ( keys %{ $ego_conf_hash{'kits'} } ) {
            $hash{$key} = $ego_conf_hash{'kits'}{$key};
        }
    }

    $timers{'get_kit_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## fetching kernel information from /proc/sys/kernel
##
sub get_kernel_info {

    my @keys = qw( osrelease ostype version );
    my %hash;
    my $start_time = gettimeofday;
    for my $fn (@keys) {
        if ( open my $fh, '<:encoding(UTF-8)', "/proc/sys/kernel/$fn" ) {
            chomp( $hash{$fn} = <$fh> );
            close $fh;
        }
        else {
            push_error("Could not open file $fn: $ERRNO");
            return;
        }
    }
    $timers{'get_kernel_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## finding kernel files in boot
##
sub get_boot_dir_info {
    my %hash;
    my $boot_dir = "/boot";
    my @kernel_list;
    my $start_time = gettimeofday;

    # pulling list of kernels in /boot
    if ( opendir( my $dh, $boot_dir ) ) {
        foreach my $file ( readdir($dh) ) {
            next unless ( -f "$boot_dir/$file" );    #only want files
            chomp $file;

            # let's grab the names of any files that start with
            # kernel, vmlinuz or bzImage
            if ( $file =~ m/^kernel|^vmlinuz|^bzImage/msx ) {
                push @kernel_list, $file;
            }
        }
        closedir($dh);
    }
    else {
        push_error("Cannot open directory $boot_dir, $ERRNO");
        return \%hash;
    }
    $hash{'available kernels'} = \@kernel_list;
    $timers{'get_boot_dir_info'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## getting the full list of installed packages
##
sub get_all_installed_pkg {
    my %hash;
    my @all;
    my @world;
    my $db_dir     = '/var/db/pkg';
    my $world_file = '/var/lib/portage/world';
    my $start_time = gettimeofday;

    # Get a list of the world packages
    open my $fh, '<', $world_file
      or do { push_error("Unable to open dir $world_file: $ERRNO"); };
    @world = <$fh>;
    close $fh;

    # Get a list of all the packages, skipping those half-merged
    opendir my $dh, $db_dir
      or do { push_error("Unable to open dir $db_dir: $ERRNO"); return };
    while ( my $cat = readdir $dh ) {
        if ( -d "$db_dir/$cat" && $cat !~ /^[.]{1,2}$/xms ) {
            opendir my $dh2, "$db_dir/$cat"
              or do { push_error("Unable to open dir $cat: $ERRNO"); next };
            while ( my $pkg = readdir $dh2 ) {
                next if $pkg =~ m/ \A -MERGING- /msx;
                if ( -d "$db_dir/$cat/$pkg" && $pkg !~ /^[.]{1,2}$/xms ) {
                    push @all, "$cat/$pkg";
                }
            }
        }
    }

    # Create the world and miscellaneous hashes. Do so using List::Util's "any"
    # since grep doesn't short-circuit after a successful match.
    for my $line (@all) {
        my ( $pkg, $version ) = $line =~ /(.*?)-(\d.*)/xms;
        if ( any { /\Q$pkg\E/xms } @world ) {
            push @{ $hash{pkgs}{world}{$pkg} }, $version;

            # Add a separate world-info section to make it easier to handle
            # stats in ES.
            push @{ $hash{'world-info'} }, "$pkg-$version";
        }
        else {
            push @{ $hash{pkgs}{other}{$pkg} }, $version;
        }
    }
    $hash{'pkg-count-world'} = scalar @world;
    $hash{'pkg-count-total'} = scalar @all;
    $timers{'get_all_installed_pkg'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}

##
## parsing output from lspci -kmmvvv and putting it in a useable data
## structure for use elswhere
##
sub get_lspci {
    my %hash;
    my $start_time = gettimeofday;
    my $lspci      = 'lspci -kmmvvv';
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
                    $hash{ $item{'Slot'} }{$key_item} = $item{$key_item};
                }
            }
        }
    }
    else {
        push_error("Could not retrieve output from $lspci: $ERRNO");
        return;
    }
    $timers{'get_lspci'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 ) + 0;
    return \%hash;
}
##
## gathers data and sends a bug report to the bug report ES
##
sub bug_report {
    my $debug = shift;
    my %bug_report;
    my %config = user_config;

	# if the user's config is set to not send bug reports
	# we can jump out here and let emerge move on
	$config{'bug-report'} eq 'y' or die "Skipping bug report because /etc/funtoo-report.conf bug-report=n\nYou can change this with: 'funtoo-report --update-config' and selecting 'y' for reporting build failures\n";
	

    # we make a special config to send to the send_report function
    # so that it is sent to the correct place
    my %es_config_bugreport = (
        node  => 'https://es.host.funtoo.org:9200',
        type  => 'bug',
        index => Funtoo::Report::report_time('short'),
    );

    # lets capture the UUID
    $bug_report{'funtoo-report'}{UUID} = $config{UUID};
    print "\nPreparing a bug report...\n";

    ## fetch env vars that are inherited from emerge
    my $bug_env = '';
    foreach my $key_var (%ENV) {
        if ( defined $ENV{$key_var} ) {
            $bug_env = $bug_env . "$key_var = $ENV{$key_var}\n";

        }
    }

    # Store CATEGORY and PACKAGE into a variable
    my $catpkg = "$ENV{CATEGORY}/$ENV{PN}";

    # Extract release info from /etc/ego.conf (FIXME)
    my $release_version = `grep release /etc/ego.conf |cut -f2 -d"="`;

    print "Fetching ego kit...";
    my $ego_kit = `ego kit`;
    print "Done\n";

    print "Fetching ego profile...";
    my $ego_profile = `ego profile`;
    print "Done\n";

    print "Fetching emerge info...";
    my $emerge_info = `emerge --info`;
    print "Done\n";

    print "Fetching build.log...";
    my $build_log = ${ slurp_file("$ENV{TEMP}/build.log") };
    print "Done\n";
    
    print "Fetching /var/cache/edb/mtimedb for dep state";
    my $mtimedb = ${ slurp_file('/var/cache/edb/mtimedb') };

    $bug_report{'catpkg'}           = $catpkg;
    $bug_report{'Environment_vars'} = $bug_env;
    $bug_report{'Ego Kit'}          = $ego_kit;
    $bug_report{'Ego Profile'}      = $ego_profile;
    $bug_report{'timestamp'}        = report_time('long');
    $bug_report{'build.log'}        = $build_log;
    $bug_report{'release'}          = $release_version;
	$bug_report{'mtimedb'}          = $mtimedb;
    send_report( \%bug_report, \%es_config_bugreport, $debug );
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

## Accepts a string that is a file path
## retrieves the contents of the file and returns
## it as a reference to scalar
sub slurp_file {
    my $file_path = shift;
    my $file_contents;

    if ( open( my $fh, '<', $file_path ) ) {
        my @lines = <$fh>;
        $file_contents = join( '', @lines );
    }
    else {
        $file_contents = "Unable to retrieve $file_path\n";
    }
    return \$file_contents;
}
## Accepts reportable errors, puts them
## into an array, and prints the error to
## *STDERR
sub push_error {
    my $error_message = shift;
    my $parent        = ( caller 1 )[3];
    my $line          = ( caller 0 )[2];
    print {*STDERR} "$parent: $error_message at line $line\n";
    push @errors, "$parent: $error_message at line $line";
    return;
}

## recursively crawls lsblk json output tree and modifies
## the hash in-place whose reference is sent by the caller
sub fs_recurse {
    my $data_ref = shift;
    my $hash_ref = shift;

    foreach my $item ( @{$data_ref} ) {
        if ( defined $item->{tran} ) {
            $hash_ref->{"tran-types"}{ $item->{tran} } += 1;
        }

        # follow children recursively
        if ( defined $item->{children} ) {
            fs_recurse( \@{ $item->{children} }, $hash_ref );
            next;
        }

        else {

            # capture fstype as key and size as value, renaming nulls
            if ( defined $item->{fstype} ) {

                $hash_ref->{fstypes}{ $item->{fstype} }{'size'} +=
                  sprintf( "%.2f", ( $item->{size} / 1024**3 ) );
                $hash_ref->{fstypes}{ $item->{fstype} }{'count'} += 1;
            }
            else {
                $hash_ref->{fstypes}{'unreported'}{'size'} +=
                  sprintf( "%.2f", ( $item->{size} / 1024**3 ) );
                $hash_ref->{fstypes}{'unreported'}{'count'} += 1;
            }
        }
    }
}

# This gets called by send-report()
# when a submission error is about the field limit
# it will attempt to tell ES to increase the field limit by 1000
sub fix_es_limit {
    my $old_limit  = shift;
    my $es_url     = shift;
    my $debug      = shift;
    my $start_time = gettimeofday;

    # create a json object to encode the message
    my $new_json = JSON->new->allow_nonref;

    # create a new HTTP object
    my $new_agent = sprintf '%s/%s', __PACKAGE__, $VERSION;
    my $new_http = HTTP::Tiny->new( agent => $new_agent );

    # determine the new field limit
    my $new_limit = $old_limit + 1000;

    if ($debug) {
        print "\nAttempting to raise limit from $old_limit to $new_limit \n";
    }

    # creating new http options
    my %new_header = ( "Content-Type" => "application/json" );
    my %new_options = (
        'content' => "{\"index.mapping.total_fields.limit\" : $new_limit}",
        'headers' => \%new_header
    );

    # sending command to ES to raise limit
    my $new_response = $new_http->request( 'PUT', $es_url, \%new_options );

    if ($debug) {
        print $new_response->{content} . "\n";
    }
    $timers{'fix_es_limit'} =
      sprintf( "%.4f", ( gettimeofday - $start_time ) * 1000 );

    if ( $new_response->{success} ) {
        return 1;
    }
    else {
        return 0;
    }
}

#
# This function will set the index that a report is sent to
# it can be a dev report or a regular report
# also could be a statistical report or a bug report
#
sub set_es_index {
    my ( $es_hashref, $url_ref, $settings_url_ref ) = @_;

    if ( $es_hashref->{type} eq 'report' ) {

        # if this is a development version we send to the fundev index
        # otherwise to the funtoo index
        if ( $VERSION =~ /-/msx ) {
            $url_ref =
"$es_hashref->{'node'}/fundev-$VERSION-$es_hashref->{'index'}/$es_hashref->{'type'}";
            $settings_url_ref =
"$es_hashref->{'node'}/fundev-$VERSION-$es_hashref->{'index'}/_settings";
        }
        else {
            $url_ref =
"$es_hashref->{'node'}/funtoo-$VERSION-$es_hashref->{'index'}/$es_hashref->{'type'}";
            $settings_url_ref =
"$es_hashref->{'node'}/funtoo-$VERSION-$es_hashref->{'index'}/_settings";
        }

    }

    # must be a bug report!
    else {
        # if this is a development version we send to the fundev index
        # otherwise to the funtoo index
        if ( $VERSION =~ /-/msx ) {
            $url_ref =
"$es_hashref->{'node'}/bugdev-$VERSION-$es_hashref->{'index'}/$es_hashref->{'type'}";
            $settings_url_ref =
"$es_hashref->{'node'}/bugdev-$VERSION-$es_hashref->{'index'}/_settings";
        }
        else {
            $url_ref =
"$es_hashref->{'node'}/bugtoo-$VERSION-$es_hashref->{'index'}/$es_hashref->{'type'}";
            $settings_url_ref =
"$es_hashref->{'node'}/bugtoo-$VERSION-$es_hashref->{'index'}/_settings";
        }
    }

    #print "url: $url_ref,\nsettings url: $settings_url_ref,\n";
    my @settings = ( $url_ref, $settings_url_ref );
    return \@settings;
}
1;

__END__

=pod

=head1 NAME

Funtoo::Report - Functions for retrieving and sending data on Funtoo Linux

=head1 VERSION

Version 4.0.0-beta

=head1 DESCRIPTION

This module contains functions to generate the sections of a report for Funtoo
Linux, build the whole report, and send it to an ElasticSearch server.

You almost certainly want to drive this using the C<funtoo-report> script,
rather than importing it yourself.

=head1 SYNOPSIS

    use Funtoo::Report;
    ...
    my %report = Funtoo::Report::report_from_config;
    ...
    my %es_config = (
        node  => 'https://es.host.funtoo.org:9200',
        index => Funtoo::Report::report_time('short'),
        type  => 'report'
    );
    Funtoo::Report::send_report(\%report, \%es_config, $debug);

=head1 SUBROUTINES/METHODS

=over 4

=item C<add_uuid>

Adds a UUID to the config file and/or returns it as a string. Can exit with
failure if unable to read C</proc/sys/kernel/random/uuid> or the config file.

=item C<errors>

Returns a reference to the @errors array. See also L</push_errors>, which is
used to manipulate this array.

=item C<fix_es_limit>

Used by L</send_report> when a submission error is received about the field
limit. Calling it will make an attempt to tell the ElasticSearch server to
increase the field limit by 1,000. Returns 1 if successful, 0 otherwise.

=item C<fs_recurse>

Recursively crawls supplied C<lsblk> JSON output, modifying the main hash
in-place with whose reference is sent by the caller. No return value. Used by
L</get_filesystem_info>.

=item C<get_all_installed_pkg>

Returns the full list of installed packages as a hash, separated into "world"
and "misc" sections containing the packages as well as their count.
Additionally, reports the contents of the "world" file as a separate, redundant
section for ease of parsing in ElasticSearch. Uses L</push_errors> for error
reporting.

=item C<get_boot_dir_info>

Finds kernel files in /boot. Returns the list of files found as part of the
main hash. Uses L</push_errors> for error reporting. Valid file names are
expected to begin with "kernel", "vmlinuz", or "bzImage".

=item C<get_chassis_info>

Returns information about the system chassis as a hash. Uses L</push_errors>
for error reporting. Used by L</get_hardware_info>.

=item C<get_cpu_info>

Returns information about the CPU as a hash. Uses L</push_errors> for error
reporting. Used by L</get_hardware_info>.

=item C<get_filesystem_info>

Returns C<lsblk> output as a hash. Reconstructs the output to show a more
flattened list containing only information deemed statistically valuable. Uses
L</push_error> for error reporting. Makes use of L</fs_recurse> and is used by
L</get_hardware_info>.

=item C<get_hardware_info>

Returns information about the hardware using several other subs (L</get_lspci>,
L</get_net_info>, L</get_filesystem_info>, L</get_cpu_info>, L</get_mem_info>,
L</get_chassis_info>) as a hash. Uses L</push_errors> for error reporting.

=item C<get_kernel_info>

Returns information about the currently running kernel as part of the main
hash. Uses L</push_errors> for error reporting.

=item C<get_kit_info>

Returns active kits as a hash. Uses L</push_errors> for error reporting.

=item C<get_lspci>

Returns massaged hardware information via C<lspci> as a hash. Used by
L</get_hardware_info>. Uses L</push_errors> for error reporting.

=item C<get_mem_info>

Returns information about system memory as a hash. Uses L</push_errors> for
error reporting.

=item C<get_net_info>

Returns information about network devices as a hash. Uses L</push_errors> for
error reporting. Used by L</get_hardware_info>.

=item C<get_profile_info>

Returns active profiles as reported by C<epro> as a hash. Uses L</push_errors>
for error reporting.

=item C<get_y_or_n>

Accepts a string as a question. Returns "y" or "n" based on the answer,
defaulting to "y" if nothing is provided. Repeats the question until valid
input is received. Used by L</update_config>.

=item C<push_error>

Accepts reportable errors, puts them into an array (@errors), and prints the
error to STDERR. See also L</errors>.

=item C<report_time>

Returns a long date string for the report body or a string that is like
"funtoo-year.week" that is suitable for ElasticSearch historical data
management. Accepts "long" or "short" as input, which determines the output.

=item C<send_report>

Generates the report, creates a user agent, and sends it to the ElasticSearch
server. Uses L</push_errors> for error reporting.

=item C<update_config>

Retrieves the UUID from the config file if present, and then prompts the user
as it generates settings for a new config file via L</get_y_or_n>. Inserts a
comment containing a timestamp and the version of funtoo-report used to create
the configuration. Can exit with failure if unable to read the config file.

=item C<user_config>

Parses the config file, returning the results as a hash. Can exit if unable to
read the config file, if the detected options are not in the list of known-good
options, or if known-good options are misisng.

=item C<version>

Returns $VERSION.

=item C<timer>

Returns a hash containing the results of all timers and the total time.

=item C<set_es_index>

Determines what elasticsearch index and url to send a bug or statistical
report too. Returns a list containing 2 fully formed URLs for this purpose

=item C<bug_report>

Intended to be executed by an emerge hook on build failures. Gathers
information to be added to a bug report and passes it to the send_report function

=back

=head1 DIAGNOSTICS

This section to be completed. The module emits very many error messages that
should hopefully be at least partly self-explanatory.

=head1 CONFIGURATION AND ENVIRONMENT

The configuration file is required and can be generated with C<funtoo-report>'s
C<--update-config> option (recommended). Its default location is
C</etc/funtoo-report.conf>.

=head1 DEPENDENCIES

=over 4

=item *

Perl v5.14.0 or newer

=item *

L<Carp>

=item *

L<English>

=item *

L<HTTP::Tiny>

=item *

L<IO::Socket::SSL> v1.56 or newer

=item *

L<JSON>

=item *

L<List::Util> v1.33 or newer

=item *

L<Net::SSLeay> v1.49 or newer

=item *

L<Term::ANSIColor>

=item *

L<Time::Piece>

=back

=head1 INCOMPATIBILITIES

This module is almost certainly only useful on a Funtoo computer.

=head1 BUGS AND LIMITATIONS

Definitely. To report bugs or make feature requests, please raise an issue on
GitHub at L<https://github.com/haxmeister/funtoo-reporter>.

=head1 AUTHOR

The Funtoo::Report development team:

=over 4

=item *

Joshua Day C<< <haxmeister@hotmail.com> >>

=item *

Palica C<< <palica@cupka.name> >>

=item *

ShadowM00n C<< <shadowm00n@airmail.cc> >>

=item *

Tom Ryder C<< <tom@sanctum.geek.nz> >>

=back

=head1 LICENSE AND COPYRIGHT

MIT License

Copyright (c) 2018 Haxmeister

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut
