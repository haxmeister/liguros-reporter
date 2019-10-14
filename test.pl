#!/usr/bin/env perl

use strict;
use warnings;
use Liguros::CPUinfo;

my $cpu = Liguros::CPUinfo->new();
print $cpu->model;
