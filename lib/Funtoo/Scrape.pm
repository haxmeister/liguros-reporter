package Funtoo::Scrape;

### Authors : Joshua S. Day (haxmeister), Tom Ryder, ShadowM00n
### purpose : functions for retrieving and sending data on funtoo linux

use 5.014;
use strict;
use warnings;

our $VERSION = '1.0.0';


sub new{
    my ($class,$args) = @_;
    my $self = bless { 'files' => $args->{'files'}

                     }, $class;

    print @{ $self->{files} } ,"---> from new()\n";
    return $self;
}

# Interface:

sub add_files{
    my $self = shift;
    my @new_files = @_;

    push @{$self->{files}}, @new_files;
    # print @{$self->{files}},"\n";
    }

sub get_file_list{
    my $self = shift;
    return \@{ $self->{files} };
    }

sub get_file_contents{
    my $self = shift;
    }

# Private functions:


1;

