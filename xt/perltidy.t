#!perl -T

use strict;
use warnings;

use Perl::Critic;
use Test::More tests => 2;

my $critic = Perl::Critic->new('-single-policy' => 'tidy', '-profile' => 'xt/perlcriticrc');
my $funtoo_report = $critic->critique('funtoo-report');
my $report_pm = $critic->critique('lib/Funtoo/Report.pm');

# Check tidiness
ok($funtoo_report == 0, 'perltidy funtoo-report');
ok($report_pm == 0, 'perltidy Report.pm');
