# option and optional option (I)

my ($n, $m) ;
{
local $/ = "R" ;
print STDERR "\033[6n" ;
($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
print STDERR "\n" ;
}

Say EC  <<EOC ;

interactive guide inserting options

Adding:   <I>--super_xxx<R>
Optional: <W>--optional<R> (press return to add, any other key to skip)
EOC

my $r = getc ;

{
local $/ = "R" ;
print STDERR "\033[6n" ;
($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
$n -= 1 + 5 ; # we added an extra lines
}
print STDERR "\e[$n;${m}H" ;
qx"tput ed 1>&2" ;
	
my $command = '' ;

if($r eq "\r")
	{
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[2])) . " '--super_xxx --optional '" ;
	qx"$command" ;
	}
elsif($r eq "\e")
	{
	
	}
else
	{
	$command = "tmux send-keys -- " . ('C-H ' x length($ARGV[2])) . " '--super_xxx '" ;
	qx"$command" ;
	}


()

