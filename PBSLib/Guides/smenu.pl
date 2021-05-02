# smenu example

# tmux display-message -p '#{pane_id}'
# tmux list-panes -F "#{pane_id} #{history_size}" -t %126

local $/ = "R" ;
print STDERR "\033[6n" ;
my ($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;

qx'printf  "prf\nprf_no_anonymous\nprf_none" | smenu -1 "none" -middle -column -tag -restore  2> pbs_smenu 1>&2' ;

print STDERR "\e[$n;${m}H" ;

if(0 == system 'tmux -V > /dev/null' )
	{
	open my $in, '<', 'pbs_smenu' ;
	
	my $options = <$in> ;
	
	if('' ne $options)
		{
		my $options =  '--' . join(' --', split(/\s/, $options)) ;
		chomp $options ;
		#my $command = "tmux send-keys -- " . ('C-H ' x length($ARGV[0])) . " '$options '" ;
		#my $command = "xdotool key " . ('Backspace ' x length($ARGV[0])) . " ; xdotool type -- '$options '" ;
		#qx"$command" ;
		
		my $command = (chr(8) x length($ARGV[0])) . $options ;
		ioctl STDERR, 0x5412, $_ for split //, $command;
		}
	}

