# insert options 

my @options = qw. --abc --def  . ;

if(0 == system 'tmux -V > /dev/null')
	{
	my $options = join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @options ;
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[0])) . "'$options '" unless $options eq '' ;
	qx "$command" ;
	}

return () ;
