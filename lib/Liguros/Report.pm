package Liguros::Report;

### Authors : Joshua S. Day (haxmeister), Tom Ryder, ShadowM00n
### purpose : functions for retrieving and sending data on liguros linux

use 5.20.0;
use Moose;
use Carp;                          #core
use English qw(-no_match_vars);    #core
use HTTP::Tiny;                    #core
use JSON;                          #cpan
use List::Util qw(any);            #core
use Term::ANSIColor;               #core
use Time::Piece;                   #core
use Liguros::MEMinfo;
use Liguros::CHASSISinfo;
use Liguros::Report_Config;
use Liguros::CPUinfo;
use Liguros::Lspci;
use Liguros::KernelInfo;

my $VERSION = 1.0;
has 'VERBOSE' => (
    is      => 'rw',
    default => 0,
);
has 'errors' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);
has 'CPU' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_cpu',
);

has 'Memory' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_memory',
);
has 'Chassis' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_chassis',
);
has 'Net_devices' => (
    is      => 'ro',
    isa     => 'ArrayRef',
);
has 'Kernel' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_kernel',
);
has 'Profiles' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_profiles',
);
has 'Block_dev' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_block_dev',
);
has 'Kits' => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => '1',
    builder => '_kits',
);

has 'Audio' => (
    is      => 'ro',
    isa     => 'ArrayRef',

);

has 'Video' => (
    is      => 'ro',
    isa     => 'ArrayRef',
);

my $cpu     = Liguros::CPUinfo->new;
my $memory  = Liguros::MEMinfo->new;
my $chassis = Liguros::CHASSISinfo->new;
my $json    = JSON->new->allow_nonref;
my $lspci   = Liguros::Lspci->new;
my $kernel  = Liguros::KernelInfo->new;
my $config  = Liguros::Report_Config->new;

sub BUILD{
	my $self = shift;
	$self->{Audio}       = _load_audio();
	$self->{Video}       = _load_video();
	$self->{Net_devices} = _load_net_devices();
}
sub update_config{
	$config->update_config();
}

##
## generates report, creates user agent, and sends to elastic search
##
sub send_report {
    my ( $self, $rep, $es_conf, $debug ) = @_;
    my $url;
    my $settings_url;

    # if we weren't told whether to show debugging output, don't
    $debug //= 0;

    # refuse to send a report with an unset, undefined, or empty UUID
    length $rep->{'liguros-report'}{UUID}
      or do {
        push(
            @{ $self->{errors} },
            'Refusing to submit report with blank UUID; check your config'
        );
        croak;
      };

    # if this is a development version we send to the fundev index
    # otherwise to the liguros index
    if ( $self->{VERSION} =~ /-/msx ) {
        $url =
"$es_conf->{'node'}/fundev-$self->{VERSION}-$es_conf->{'index'}/$es_conf->{'type'}";
        $settings_url =
"$es_conf->{'node'}/fundev-$self->{VERSION}-$es_conf->{'index'}/_settings";
    }
    else {
        $url =
"$es_conf->{'node'}/liguros-$self->{VERSION}-$es_conf->{'index'}/$es_conf->{'type'}";
        $settings_url =
"$es_conf->{'node'}/liguros-$self->{VERSION}-$es_conf->{'index'}/_settings";
    }

    # load the report options for the http post
    my %header  = ( "Content-Type" => "application/json" );
    my %options = (
        'content' => $json->pretty->encode($rep),
        'headers' => \%header
    );

    # create a new HTTP object
    my $agent = sprintf '%s/%s', __PACKAGE__, $self->{VERSION};
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

                send_report( $rep, $es_conf, $debug );
                exit;
            }
        }

        croak "Failed submission: $response->{status} $response->{reason}";
      };

    # warn if the response code wasn't 201 (Created)
    $response->{status} == 201
      or push(
        @{ $self->{errors} },
        'Successful submission, but status was not the expected \'201 Created\''
      );

    # print location redirection if there was one, warn if not
    if ( defined $response->{headers}{location} ) {
        if ( $self->{VERBOSE} ) {
            print "your report can be seen at: "
              . $es_conf->{'node'}
              . $response->{'headers'}{'location'} . "\n";
        }
    }
    else {
        push( @{ $self->{errors} }, 'Expected location for created resource' );
    }
}

## returns a long date string for the report body or
## returns a string that is like 'liguros-year.week' that is
## suitable for elasticsearch historical data management
##
## with special date formatting by request
sub report_time {
    my $self      = shift;
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
      or do {
        push( @{ $self->{errors} }, 'Unable to determine the time' );
        return;
      };
    return $formats{$format};
}

sub _load_video{
	my $self = shift;
	my @list;

    for my $device ( keys %{ $lspci->{lspci_data}} ) {
        if ( $lspci->{lspci_data}{$device}{'Class'} =~  /VGA|vga/msx ){
            push @list, \%{ $lspci->{lspci_data}{$device} };
        }
    }
    return \@list;	
}

sub _load_audio{
	my $self = shift;
	my @list;
	
	for my $device ( keys %{ $lspci->{lspci_data}} ) {

        # fetching sound info from data structure
        if ( $lspci->{lspci_data}{$device}{'Class'} =~ /Audio|audio/msx ){
			push @list , \%{ $lspci->{lspci_data}{$device} };
        }
    }
    return \@list;
}


sub _cpu {
    my $self = shift;
    my %data;

    $data{processors} = $cpu->processors;
    $data{flags}      = $cpu->flags;
    $data{MHz}        = $cpu->MHz;
    $data{model}      = $cpu->model;

    return \%data;

}
sub _memory { }

sub _chassis {
    return $chassis->all_data;
}

sub _load_net_devices {
    my $self  = shift;
	my @list;
	
	for my $device ( keys %{ $lspci->{lspci_data}} ) {

        # fetching sound info from data structure
        if ( $lspci->{lspci_data}{$device}{'Class'} =~ /Network|network|Ethernet|ethernet/msx ){
			push @list , \%{ $lspci->{lspci_data}{$device} };
        }
    }
    return \@list;
}

sub _kernel {
    my $self = shift;
    my %info;

    $info{'osrelease'}     = $kernel->osrelease;
    $info{'ostype'}        = $kernel->ostype;
    $info{'version'}       = $kernel->version;
    $info{'kernels_found'} = $kernel->Kernels_found;

    return \%info;
}
sub _profiles { }

sub _block_dev {
    my $self = shift;
    my %hash;
    my $lsblk =
      `lsblk --bytes --json -o NAME,FSTYPE,SIZE,PARTTYPE,TRAN,HOTPLUG`;
    my $lsblk_decoded = decode_json($lsblk);

    fs_recurse( \@{ $lsblk_decoded->{blockdevices} }, \%hash );
    return \%hash;
}
sub _kits { return (kits => 'builder', needs => 'written'); }

sub get_final_report {
	my $self = shift;
    my %final_report;


    if ( $config->{'kernel_info'} eq 'y' ) {
        $final_report{'kernel_info'} = $self->Kernel;
    }
    if ( $config->{'profile_info'} eq 'y' ) {
        $final_report{'profile_info'} = $self->get_profile_info;
    }
    if ( $config->{'installed_pkgs'} eq 'y' ) {
        $final_report{'installed_pkgs'} = $self->get_all_installed_pkg;
    }
    if ( $config->{'chassis_info'} eq 'y' ) {
        $final_report{'chassis'} = $self->Chassis;
    }
    if ( $config->{'networking_devices'} eq 'y' ) {
        $final_report{'networking'} = $self->Net_devices;
    }
    if ( $config->{'file_systems_info'} eq 'y' ) {
        $final_report{'filesystems'} = $self->Block_dev;
    }

    if ( $config->{'kit_info'} eq 'y' ) {
        $final_report{'kit_info'} = $self->get_kit_info;
    }
    if ( $config->{'cpu_info'} eq 'y') {
		$final_report{'cpu'} = $self->CPU;
	}
	if ( $config->{'video_devices'} eq 'y'){
		$final_report {'Video'} = $self->{Video};
	}
	if ( $config->{'audio_devices'} eq 'y'){
		$final_report {'Audio'} = $self->{Audio};
	}

    $final_report{'liguros-report'}{'UUID'} = $config->UUID;
    $final_report{'timestamp'} = $self->report_time('long');
    $final_report{'liguros-report'}{'version'} = $VERSION;
    $final_report{'liguros-report'}{'errors'}  = $self->errors;

    return %final_report;
}

##
## fetching active profiles
## reconstruct output of epro show-json command
##
sub get_profile_info {
    my $self = shift;

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
        return \%sorted;
    }
    else {
        push(
            @{ $self->{errors} },
            "Unable to retrieve output from $epro: $ERRNO"
        );
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
    my $self = shift;

    my $meta_file = "/var/git/meta-repo/metadata/kit-info.json";
    my $ego_conf  = "/etc/ego.conf";
    my %ego_conf_hash;
    my $meta_data;
    my %hash;

    # decode and store meta file datastructure into $meta_data
    if ( open( my $fh, '<:encoding(UTF-8)', $meta_file ) ) {
        my @lines = <$fh>;
        close $fh;
        my $data = join( '', @lines );
        $meta_data = decode_json($data);
    }
    else {
        push( @{ $self->{errors} }, "Cannot open file $meta_file: $ERRNO" );
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
        push( @{ $self->{errors} }, "Cannot open file $ego_conf: $ERRNO" );
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
    return \%hash;
}

##
## getting the full list of installed packages
##
sub get_all_installed_pkg {
    my $self = shift;
    my %hash;
    my @all;
    my @world;
    my $db_dir     = '/var/db/pkg';
    my $world_file = '/var/lib/portage/world';

    # Get a list of the world packages
    if ( open( my $fh, '<', $world_file ) ) {
        @world = <$fh>;
        close $fh;
    }
    else {
        push( @{ $self->{errors} }, "Unable to open dir $world_file: $ERRNO" );
    }

    # Get a list of all the packages, skipping those half-merged
    opendir my $dh, $db_dir
      or do {
        push( @{ $self->{errors} }, "Unable to open dir $db_dir: $ERRNO" );
        return;
      };
    while ( my $cat = readdir $dh ) {
        if ( -d "$db_dir/$cat" && $cat !~ /^[.]{1,2}$/xms ) {
            opendir my $dh2, "$db_dir/$cat"
              or do {
                push( @{ $self->{errors} }, "Unable to open dir $cat: $ERRNO" );
                next;
              };
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
    return \%hash;
}

sub user_config{
	return $config->list_options();
}
###########################################
############ misc functions ###############

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
    my $self      = shift;
    my $old_limit = shift;
    my $es_url    = shift;
    my $debug     = shift;

    # create a new HTTP object
    my $new_agent = sprintf '%s/%s', __PACKAGE__, $self->{VERSION};
    my $new_http = HTTP::Tiny->new( agent => $new_agent );

    # determine the new field limit
    my $new_limit = $old_limit + 1000;

    if ($debug) {
        print "\nAttempting to raise limit from $old_limit to $new_limit \n";
    }

    # creating new http options
    my %new_header  = ( "Content-Type" => "application/json" );
    my %new_options = (
        'content' => "{\"index.mapping.total_fields.limit\" : $new_limit}",
        'headers' => \%new_header
    );

    # sending command to ES to raise limit
    my $new_response = $new_http->request( 'PUT', $es_url, \%new_options );

    if ($debug) {
        print $new_response->{content} . "\n";
    }

    if ( $new_response->{success} ) {
        return 1;
    }
    else {
        return 0;
    }
}
1;

__END__

=pod

=head1 NAME

Liguros::Report - Functions for retrieving and sending data on Liguros Linux

=head1 VERSION

Version 3.2.2

=head1 DESCRIPTION

This module contains functions to generate the sections of a report for Liguros
Linux, build the whole report, and send it to an ElasticSearch server.

You almost certainly want to drive this using the C<liguros-report> script,
rather than importing it yourself.

=head1 SYNOPSIS

    use Liguros::Report;
    ...
    my %report = Liguros::Report::report_from_config;
    ...
    my %es_config = (
        node  => 'https://es.host.liguros.org:9200',
        index => Liguros::Report::report_time('short'),
        type  => 'report'
    );
    Liguros::Report::send_report(\%report, \%es_config, $debug);

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
"liguros-year.week" that is suitable for ElasticSearch historical data
management. Accepts "long" or "short" as input, which determines the output.

=item C<send_report>

Generates the report, creates a user agent, and sends it to the ElasticSearch
server. Uses L</push_errors> for error reporting.

=item C<update_config>

Retrieves the UUID from the config file if present, and then prompts the user
as it generates settings for a new config file via L</get_y_or_n>. Inserts a
comment containing a timestamp and the version of liguros-report used to create
the configuration. Can exit with failure if unable to read the config file.

=item C<user_config>

Parses the config file, returning the results as a hash. Can exit if unable to
read the config file, if the detected options are not in the list of known-good
options, or if known-good options are misisng.

=item C<version>

Returns $VERSION.

=item C<timer>

Returns a hash containing the results of all timers and the total time.

=back

=head1 DIAGNOSTICS

This section to be completed. The module emits very many error messages that
should hopefully be at least partly self-explanatory.

=head1 CONFIGURATION AND ENVIRONMENT

The configuration file is required and can be generated with C<liguros-report>'s
C<--update-config> option (recommended). Its default location is
C</etc/liguros-report.conf>.

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

This module is almost certainly only useful on a Liguros computer.

=head1 BUGS AND LIMITATIONS

Definitely. To report bugs or make feature requests, please raise an issue on
GitHub at L<https://github.com/haxmeister/liguros-reporter>.

=head1 AUTHOR

The Liguros::Report development team:

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
