# man,page

my $page = $ARGV[3] // '' ;

if($page ne '' and 0 == system "man -w $page 2>/dev/null 1>&2")
	{
	qx"man $page | vipe | cat > /dev/null" ;
	
	my $command = "tmux send-keys -- " . ('C-H ' x length(join ',', @ARGV[2, $#ARGV])) ;
	qx"$command" ;
	}


