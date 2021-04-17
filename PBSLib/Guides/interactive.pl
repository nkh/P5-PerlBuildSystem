# option and optional option (I)

Say EC  <<EOC ;

interactive guide inserting options

Adding:   <I>--super_xxx<R>
Optional: <W>--optional<R> (press return to add, any other key to skip)
EOC

my $r = getc ;

my $command = '' ;

if($r eq "\r")
	{
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[0])) . " '--super_xxx --optional '" ;
	}
else
	{
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[0])) . " '--super_xxx '" ;
	}

qx"$command" ;

()


#run fzf to choose
