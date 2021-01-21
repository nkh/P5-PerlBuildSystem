# implement a gant timeline
# nodes are given start time, duration, and dependencies
# start time and duration are saved in the node's config
#	one of the problems encountered is that source nodes have no rules run on them
#	and can't get start time and duration set
#
# postpbs doesn't work in warp mode, nodes are not depended if not changed, if no node is
# modified there are no nodes at all in the graph

# run with: pbs all -w 0 

# post pbs is called after the build, maybe we should call post "depend" instead

AddRule 'all',	['all' => 'a', 'b'],	["touch %TARGET"],			SetTime(5, 3) ;
AddRule 'a',	['a' => 'c'],		["touch %TARGET"],			SetTime(1, 2) ;
AddRule 'b',	['b' => 'c'],		["touch %TARGET"],			SetTime(3, 1) ;
AddRule 'c',	['c'],			["touch %TARGET", "touch %TARGET"],	SetTime(4, 3) ;

sub SetTime 
{
my ($start_time, $build_time) = @_ ;
return sub 
	{
	PrintInfo4 "GANT: setting $_[2]->{__NAME}, start_time: $start_time, build_time: $build_time\n" ;
	$_[2]->{__CONFIG} = { _START_TIME => $start_time, _BUILD_TIME => $build_time } ;
	}
}

