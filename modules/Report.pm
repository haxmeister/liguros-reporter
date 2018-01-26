package Report;

### Author : Joshua S. Day (haxmeister)
### purpose : functions for retrieving data on funtoo linux

use strict;
use warnings;
use Exporter;
use JSON;
our $VERSION = '1.1';

our @EXPORT_OK = qw(user_config
                    get_cpu_info
                    get_mem_info
                    get_kernel_info
                    get_boot_dir_info
                    get_version_info
                    get_world_info
                    get_profile_info
                    get_kit_info
                    add_uuid);

my $config_file = '/etc/report.conf';

###
### finds the config file in /etc/report.conf and loads it's contents
### into a hash and returns it
###
sub user_config {

    my %hash;

    if ( open( my $fh, '<:encoding(UTF-8)', $config_file ) ) {
        my @lines = <$fh>;
        close $fh;
        foreach my $line (@lines) {
            chomp $line;
            if ( $line =~ /^\#/msx ) {
                next;
            }
            elsif ($line) {
                my ( $key, $value ) = split /\s*:\s*/msx, $line;
                $hash{$key} = $value;
            }
            else {
                next;
            }
        }
    }
    else {
        warn "Could not open file ' $config_file' \n$!";
        exit;
    }
    return %hash;
}

###
### adds a uuid to /etc/report.conf and returns it as a string
###
sub add_uuid{

    open(my $fh, '<', '/proc/sys/kernel/random/uuid') or die $!;
    my $UUID = <$fh>;
    close $fh;
    
    open( $fh, '>>', $config_file ) or die $!;
    print $fh "\n# A unique identifier for this reporting machine \n";
    print $fh "UUID:$UUID\n";
    close $fh;
    
    return $UUID;
}
