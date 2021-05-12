#!/bin/env perl
# http options (I)

use strict ; use warnings ;

use PBS::Output ;
setup_colors() ;

use PBS::PBSConfigSwitches ;
use List::Util qw(max any);
use Sort::Naturally ;

my ($n, $m) = get_cursor_position() ;

print STDERR "\n" ;
Say EC  <<EOC ;

HTTP options are used during parallel Pbs

some documentation
	...

more documentation
	...
EOC

my @matches = PBS::PBSConfigSwitches::GetOptionsElements() ;

my (@short, @long, @options) ;

for (grep { $_->[0] =~ /http/ } @matches)
	{
	my ($option_type, $help) = @{$_}[0..2] ;
	
	my ($option, $type) = $option_type  =~ m/^([^=]+)(=.*)?$/ ;
	$type //= '' ;
	
	my ($long, $short) = split(/\|/, $option, 2) ;
	$short //= '' ;
	
	push @short, length($short) ;
	push @long , length($long) ;
	
	push @options, [$long, $short, $type, $help] ; 
	}

my $max_short = max(@short) + 2 ;
my $max_long  = max(@long);

open my $fzf_in, '>', 'pbs_fzf_x3' ;
binmode $fzf_in ;

print $fzf_in 
	join "\n",
		map
			{
			my ($long, $short, $type, $help) = @{$_} ;
			
			EC sprintf "<I3>--%-${max_long}s <W3>%--${max_short}s<I3>%2s: <I>$help", $long, ($short eq '' ? '' : "--$short"), $type ;
			} @options ;

my $size = qx'stty size' ;
my ($screen_lines) = $size =~ /^(\d+)/ ;
my $height = @options > $screen_lines / 2 ? '50%' : @options ; 

my @fzf = qx"cat pbs_fzf_x3 | fzf --height=$height --info=inline --ansi --reverse -m" ;

restore_position($m, 9, 1) ;

my $options = join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf ;

SDT $options, 'options';
SDT \@ARGV ;

my $command = (chr(8) x length($ARGV[2])) . "$options " unless $options eq '' ;
ioctl STDERR, 0x5412, $_ for split //, $command  ;

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

