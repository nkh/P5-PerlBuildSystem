# smenu example

my ($n, $m) ;
{
local $/ = "R" ;
print STDERR "\033[6n" ;
($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
print STDERR "\n" ;
}

qx'printf  "prf\nprf_no_anonymous\nprf_none" | smenu -1 "none" -middle -column -tag -restore  2> pbs_smenu 1>&2' ;

{
local $/ = "R" ;
print STDERR "\033[6n" ;
($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
$n -= 1 ; # we added an extra lines
}
print STDERR "\e[$n;${m}H" ;
qx"tput ed 1>&2" ;


if(0 == system 'tmux -V > /dev/null' )
	{
	open my $in, '<', 'pbs_smenu' ;
	
	my $options = <$in> ;
	
	if('' ne $options)
		{
		my $options =  '--' . join(' --', split(/\s/, $options)) ;
		chomp $options ;
		#my $command = "tmux send-keys -- " . ('C-H ' x length($ARGV[2])) . " '$options '" ;
		#my $command = "xdotool key " . ('Backspace ' x length($ARGV[2])) . " ; xdotool type -- '$options '" ;
		#qx"$command" ;
		
		my $command = (chr(8) x length($ARGV[2])) . $options ;
		ioctl STDERR, 0x5412, $_ for split //, $command . ' ' ;
		}
	}

