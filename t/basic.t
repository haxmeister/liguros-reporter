#!perl -T

use strict;
use warnings;
use utf8;

use Test::More tests => 3;

# Check we can use the module
BEGIN {
    use_ok('Funtoo::Report')
      or BAIL_OUT 'Can\'t load module';
}

# Check the module has all the methods that funtoo-report expects
can_ok(
    'Funtoo::Report', qw(
      add_uuid
      config_update
      errors
      get_all_installed_pkg,
      get_boot_dir_info,
      get_hardware_info,
      get_kernel_info,
      get_kit_info,
      get_profile_info,
      get_version_info,
      get_world_info,
      report_time
      send_report
      user_config
      version
      )
);

# Check that its configuration is set to the default
ok( $Funtoo::Report::config_file eq '/etc/funtoo-report.conf',
    'default config set' );
