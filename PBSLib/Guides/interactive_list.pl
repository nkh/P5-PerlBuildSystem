# http options (I)

my $l = length $ARGV[0] ;

Say EC  <<EOC ;

HTTP options are used during parallel Pbs

some documentation
	...

more documentation
	...
EOC

#if(0 == system 'fzf --version > /dev/null' and 0 == system 'tmux -V > /dev/null')
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
	
	for (@options)
		{
		my ($long, $short, $type, $help) = @{$_} ;
		
		print $fzf_in 
			EC(sprintf( "<I3>--%-${max_long}s <W3>%--${max_short}s<I3>%2s: ", $long, ($short eq '' ? '' : "--$short"), $type)
				."<I>$help\n") ;
		}
	
	my @fzf = qx"cat pbs_fzf_x3 | fzf --height=50% --ansi --reverse -m" ;
	
	my $options = join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf ;
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[0])) . "'$options '" unless $options eq '' ;
	qx "$command" ;
	
	return ;
	}

