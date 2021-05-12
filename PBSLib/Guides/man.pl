#!/bin/env perl
# man,page

use strict ; use warnings ;

my $page = $ARGV[3] // '' ;

if($page ne '' and 0 == system "man -w $page 2>/dev/null 1>&2")
	{
	qx"man $page | vipe | cat > /dev/null" ;
	
	my $command = (chr(8) x length(join ',', @ARGV[2, $#ARGV])) ;
	ioctl STDERR, 0x5412, $_ for split //, $command  ;
	}

