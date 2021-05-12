#!/bin/env perl
# smenu example

use strict ; use warnings ;

my ($n, $m) = get_cursor_position() ;

print STDERR "\n" ;

qx'printf  "prf\nprf_no_anonymous\nprf_none" | smenu -1 "none" -middle -column -tag -restore  2> pbs_smenu 1>&2' ;

restore_position($m, 1, 1) ; # we added one extra line, clear screen below

open my $in, '<', 'pbs_smenu' ;
my $options = <$in> ;

if('' ne $options)
	{
	my $options =  '--' . join(' --', split(/\s/, $options)) ;
	chomp $options ;
	
	my $command = (chr(8) x length($ARGV[2])) . "$options " ;
	ioctl STDERR, 0x5412, $_ for split //, $command ;
	}

#-------------------------------------------------------------------------------

sub get_cursor_position
{
local $/ = "R" ;
print STDERR "\033[6n" ;
<STDIN> =~ m/(\d+)\;(\d+)/ ;
}

sub restore_position
{
my ($m, $extra_lines, $clear_screen_below) = @_ ;

local $/ = "R" ;
print STDERR "\033[6n" ;
($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
$n -= $extra_lines ;

print STDERR "\e[$n;${m}H" ;

qx"tput ed 1>&2" if $clear_screen_below  ;
}


