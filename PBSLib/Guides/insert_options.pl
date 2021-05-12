#!/bin/env perl
# insert options 

use strict ; use warnings ;

my @options = qw. --abc --def  . ;

my $options = join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @options ;

my $command = (chr(8) x length($ARGV[2])) . "$options " unless $options eq '' ;
ioctl STDERR, 0x5412, $_ for split //, $command  ;
