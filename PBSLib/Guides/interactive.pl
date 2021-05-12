#!/bin/env perl
# option and optional option (I)

use strict ; use warnings ;

use PBS::Output ;
setup_colors() ;

my ($n, $m) = get_cursor_position() ;

print STDERR "\n" ;

Say EC  <<EOC ;

interactive guide inserting options

Adding:   <I>--super_xxx<R>
Optional: <W>--optional<R> (press return to add, any other key to skip)
EOC

my $r = getc ;

restore_position($m, 6, 1) ;

if($r eq "\e")
	{
	}
elsif($r eq "\r")
	{
	my $command = (chr(8) x length($ARGV[2])) . "--super_xxx --optional ";
	ioctl STDERR, 0x5412, $_ for split //, $command  ;
	}
else
	{
	my $command = (chr(8) x length($ARGV[2])) . "--super_xxx ";
	ioctl STDERR, 0x5412, $_ for split //, $command  ;
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

#-------------------------------------------------------------------------------

use Term::ANSIColor qw(:constants color) ;
sub setup_colors
{
my $cc =
	{
	256 =>
		[
		debug    => color('rgb314'),
		debug2   => color('rgb304'),
		debug3   => color('rgb102'),
		debug4   => color('rgb203'),
		error    => color('rgb300'),
		error2   => color('rgb200'),
		error3   => color('rgb400'),
		on_error => color('grey11 on_rgb100'),
		info     => color('rgb020'),
		info2    => color('rgb013'),
		info3    => color('rgb023'),
		info4    => color('rgb030'),
		info5    => color('rgb015'),
		info6    => color('rgb010'),
		shell    => color('grey7'),
		shell2   => color('grey11'),
		user     => color('rgb034'),
		warning  => color('rgb320'),
		warning2 => color('bright_yellow'),
		warning3 => color('rgb210'),
		warning4 => color('rgb310'),
		
		box_11   => color('on_grey4'),
		box_12   => color('on_grey4'),
		box_21   => color(''),
		box_22   => color(''),
		
		test_bg  => color('rgb220 on_rgb101'),
		test_bg2 => color('rgb220 on_rgb003'),
		
		ttcl1    => color('rgb010'),
		ttcl2    => color('rgb012'),
		ttcl3    => color('grey8'),
		ttcl4    => color('rgb101'),
		
		reset    => color('reset'),
		
		dark     => color('rgb000'),
		no_match => color('rgb200'),
		ignoring_local_rule => color('rgb220 on_rgb101'),
		],
	} ;

PBS::Output::SetDefaultColors($cc) ;
}


