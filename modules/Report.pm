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
                    get_kit_info);

sub user_config {

    my $config_file = '/etc/report.conf';
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
        warn "Could not open file ' $config_file' $!";
        exit;
    }
    return %hash;
}

###
### fetching active profiles
### reconst output of epro show-json command
###
sub get_profile_info {
    my $json_from_epro = `epro show-json`;
    my %profiles;
    my $data = decode_json($json_from_epro);
    %profiles = %$data;
    return %profiles;
}

###
### fetching active kits
### resorting to parsing output of ego
###
sub get_kit_info {
    my @status_info = `ego kit status`;
    my %hash;
    
    for my $line (@status_info){
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        if ( $line =~ /NOTE/){
            return %hash;
        }
        if ( $line =~ /^\w/msx){
            my ($key, $value) = split(' ',$line);
            $value =~ s/^\W\[\d.m//;
            $hash{$key} = $value;
        }
    }
    return %hash;
}

###
### fetching lines from /proc/cpuinfo
###
sub get_cpu_info {

    my $cpu_file = '/proc/cpuinfo';
    my %hash;
    my @cpu_file_contents;
    if ( open( my $fh, '<:encoding(UTF-8)', $cpu_file ) ) {
        @cpu_file_contents = <$fh>;
        close $fh;
        foreach my $row (@cpu_file_contents) {
            chomp $row;
            if ($row) {
                my ( $key, $value ) = split /\s*:\s*/msx, $row;
                if (   ( $key eq 'cpu MHz' )
                    or ( $key eq 'model name' )
                    or ( $key eq 'cpu cores' ) )
                {
                    $hash{$key} = $value;
                }
                elsif ( $key eq 'flags' ) {
                    my @cpu_flags = split / /, $value;
                    $hash{$key} = \@cpu_flags;
                }
                else {next}
            }    #end if
        }    #end while
    }    #end if
    else { warn "Could not open file ' $cpu_file' $!"; }
    return %hash;
}    # end sub

###
### fetching a few lines from /proc/meminfo
###
sub get_mem_info {
    # pulling relevent info from /proc/meminfo
    my %hash;
    my $mem_file = '/proc/meminfo';
    my @mem_file_contents;
    if ( open( my $fh, '<:encoding(UTF-8)', $mem_file ) ) {
        @mem_file_contents = <$fh>;
        close $fh;
        foreach my $row (@mem_file_contents) {
            chomp $row;
            if ($row) {
                my ( $key, $value ) = split /\s*:\s*/msx, $row;
                if (   ( $key eq 'MemTotal' )
                    or ( $key eq 'MemFree' )
                    or ( $key eq 'MemAvailable' )
                    or ( $key eq 'SwapTotal' )
                    or ( $key eq 'SwapFree' ) ){
                    $hash{$key} = $value;
                }
            }
        }
    }
    else { warn "Could not open file ' $mem_file' $!"; }
    return %hash;
}    # end sub

###
### fetching kernel information from /proc/sys/kernel
###
sub get_kernel_info {

    my $directory = '/proc/sys/kernel';
    my %hash;
    my @dir_contents;

    # pulling relevant info from /proc/sys/kernel
    opendir( DIR, $directory ) or die $!;
    @dir_contents = readdir(DIR);
    closedir(DIR);
    foreach my $file (@dir_contents) {
        next unless ( -f "$directory/$file" );    #only want files
        if (   ( $file eq 'ostype' )
            or ( $file eq 'osrelease' )
            or ( $file eq 'version' ) )
        {
            if ( open( my $fh, '<:encoding(UTF-8)', "$directory/$file" ) ) {
                my $row = <$fh>;
                close $fh;
                chomp $row;
                $hash{$file} = $row;
            }
            else { warn "could not open file '$file' $!"; }
        }
    }
    return %hash;
}    #end sub

###
### fetching files in /boot that start with "kernel" or "vmlinuz"
###
sub get_boot_dir_info {
    my %hash;
    my $boot_dir = "/boot";
    my @kernel_list;

    # pulling list of kernels in /boot
    opendir( DIR, $boot_dir ) or die "cannot access $boot_dir ", $!;
    foreach my $file ( readdir(DIR) ) {
        next unless ( -f "$boot_dir/$file" );    #only want files
        chomp $file;
        if ( $file =~ m/^kernel|^vmlinuz/msx ) {
            push @kernel_list, $file;
        }
    }
    $hash{'available kernels'} = \@kernel_list;
    closedir(DIR);
    return %hash;
}    #end sub

###
### fetching contents of /var/lib/portage/world
###
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

###
### fetching versions of key softwares
###
sub get_version_info {

    my %hash;
    my %ebuild_dirs = (
        'portage' => '/var/db/pkg/sys-apps',
        'ego'     => '/var/db/pkg/app-admin',
        'python'  => '/var/db/pkg/dev-lang',
        'gcc'     => '/var/db/pkg/sys-devel',
        'glibc'   => '/var/db/pkg/sys-libs'
    );

    ## retrieving portage version
    opendir( DIR, ( $ebuild_dirs{'portage'} ) )
        or die "could not open $ebuild_dirs{'portage'} ", $!;
    my @portage_dir = readdir(DIR);
    closedir(DIR);
    foreach my $folder (@portage_dir) {
        chomp $folder;
        if ( $folder =~ /^portage/msx ) {
            $folder =~ /^portage-(.*)/msx;
            $hash{'portage version'} = $1;
        }
    }

    ## retrieving ego version
    opendir( DIR, ( $ebuild_dirs{'ego'} ) )
        or die "could not open $ebuild_dirs{'ego'} ", $!;
    my @ego_dir = readdir(DIR);
    closedir(DIR);
    foreach my $folder (@ego_dir) {
        chomp $folder;
        if ( $folder =~ /^ego/msx ) {
            $folder =~ /^ego-(.*)/msx;
            $hash{'ego version'} = $1;
        }
    }

    # retrieving python versions
    my @python_versions;
    opendir( DIR, ( $ebuild_dirs{'python'} ) )
        or die "could not open $ebuild_dirs{'python'} ", $!;
    my @python_dir = readdir(DIR);
    closedir(DIR);
    foreach my $folder (@python_dir) {
        chomp $folder;
        if ( $folder =~ /^python.[^exec]/msx ) {
            $folder =~ /^python-(.*)/msx;
            push @python_versions, $1;
            $hash{'python versions'} = \@python_versions;
        }
    }

    # retrieving gcc versions
    my @gcc_versions;
    opendir( DIR, ( $ebuild_dirs{'gcc'} ) )
        or die "could not open $ebuild_dirs{'gcc'} ", $!;
    my @gcc_dir = readdir(DIR);
    closedir(DIR);
    foreach my $folder (@gcc_dir) {
        chomp $folder;
        if ( $folder =~ /^gcc.[^config]/msx ) {
            $folder =~ /^gcc-(.*)/msx;
            push @gcc_versions, $1;
            $hash{'gcc versions'} = \@gcc_versions;
        }
    }

    # retrieving glibc versions
    my @glibc_versions;
    opendir( DIR, ( $ebuild_dirs{'gcc'} ) )
        or die "could not open $ebuild_dirs{'gcc'} ", $!;
    my @glibc_dir = readdir(DIR);
    closedir(DIR);
    foreach my $folder (@glibc_dir) {
        chomp $folder;
        if ( $folder =~ /^glibc.[^config]/msx ) {
            $folder =~ /^glibc-(.*)/msx;
            push @glibc_versions, $1;
            $hash{'glibc versions'} = \@glibc_versions;
        }
    }
    return %hash;
}

1;
