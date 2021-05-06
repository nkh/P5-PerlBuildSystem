# man,page

my $page = $ARGV[2] // '' ;

if($page ne '' and 0 == system "man -w $page 2>/dev/null 1>&2")
	{
	qx"man $page | vipe | cat > /dev/null" ;
	
	my $command = "tmux send-keys -- " . ('C-H ' x length(join ',', @ARGV[1, $#ARGV])) ;
	qx"$command" ;
	}


