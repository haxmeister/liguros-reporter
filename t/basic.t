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

# Check the module has all the methods we expect
can_ok(
    'Funtoo::Report', qw(
      send_report
      user_config
      config_update
      add_uuid
      version
      errors
      report_time
      get_hardware_info
      get_net_info
      get_filesystem_info
      get_cpu_info
      get_mem_info
      get_chassis_info
      get_profile_info
      get_kit_info
      get_kernel_info
      get_boot_dir_info
      get_world_info
      get_all_installed_pkg
      get_version_info
      get_lspci
      get_y_or_n
      push_error
      )
);

# Check that its configuration is set to the default
ok( $Funtoo::Report::config_file eq '/etc/funtoo-report.conf',
    'default config set' );
