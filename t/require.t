#!perl -T

use strict;
use warnings;
use utf8;

use Test::More tests => 1;

# Check we can require the module
ok(eval { require Funtoo::Report }, 'require module');
