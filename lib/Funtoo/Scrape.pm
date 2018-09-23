package Funtoo::Scrape;

### Authors : Joshua S. Day (haxmeister)
### purpose : Class for slurping files

use 5.014;
use strict;
use warnings;

our $VERSION = '1.0.0';


sub new{
    my ($class,$args) = @_;
    my $self = bless { 'paths' => $args->{'paths'},


                     }, $class;
    #print @{ $self->{paths} } ,"---> from new()\n";
    return $self;
}

# Interface:

sub add_paths{
    my $self = shift;
    my @new_files = @_;

    push @{$self->{paths}}, @new_files;
    clean_list();

    }

sub get_path_list{
    my $self = shift;
    clean_list();
    return \@{ $self->{paths} };
    }

sub get_all_files{
    my $self = shift;
    my $hash = $self->clean_list();

    for my $file (keys(%{$hash})){

        open( my $fh, '<:encoding(UTF-8)', $file );
        my @file_contents = <$fh>;
        close $fh;

        $hash->{$file} = join '', @file_contents;
    }

    return $hash;
    }

# Private functions:

sub clean_list{
    my $self = shift;

    my %files;
    my @stack; ;

    for my $item  (@{$self->{paths}}){

        if (-e -l $item){
            next;               #skip symlinks
        }
        else{
            push @stack, $item;
        }
    }

    while (my $element = pop(@stack)){

        if ($element eq ".." || $element eq ".") {
            next;
        }
        if (-e -l $element){
            next;               #skip symlinks
        }
        if (-e -f $element){
            $files{$element}='f';
        }
        if (-e -d $element){

            opendir (my $dh, $element) or die "unable to open the directory $element\n$!";
            my @dir_list = readdir($dh);
            closedir $dh;

            for my $dir_item (@dir_list){

                if ($dir_item eq ".." || $dir_item eq "."){
                    next;
                }
                else{
                    push @stack, "$element/$dir_item";
                }
            }
        }
        next;
    }
    return \%files;
}


1;

