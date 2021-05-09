# http options (I)

my ($n, $m) ;
{
local $/ = "R" ;
print STDERR "\033[6n" ;
($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
print STDERR "\n" ;
}

my $l = length $ARGV[1] ;

Say EC  <<EOC ;

HTTP options are used during parallel Pbs

some documentation
	...

more documentation
	...
EOC

if(0 == system 'fzf --version > /dev/null' and 0 == system 'tmux -V > /dev/null')
	{
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
	
	print $fzf_in join "\n",
			map
				{
				my ($long, $short, $type, $help) = @{$_} ;
				
				EC sprintf "<I3>--%-${max_long}s <W3>%--${max_short}s<I3>%2s: <I>$help", $long, ($short eq '' ? '' : "--$short"), $type ;
				} @options ;
	
	my $size = qx'stty size' ;
	my ($screen_lines) = $size =~ /^(\d+)/ ;
	my $height = @options > $screen_lines / 2 ? '50%' : @options ; 
	
	my @fzf = qx"cat pbs_fzf_x3 | fzf --height=$height --info=inline --ansi --reverse -m" ;
	
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	$n -= 1 + 8 ; # we added an extra lines
	}
	print STDERR "\e[$n;${m}H" ;
	qx"tput ed 1>&2" ;

	my $options = join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf ;
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[2])) . "'$options '" unless $options eq '' ;
	qx "$command" ;
	
	return ;
	}

