# attempt to implement a gant timeline
# nodes are given start time, duration, and dependencies
# start time and duration are saved in the node's config
#	one of the problems encountered is that source nodes have no rules run on them
#	and can't get start time and duration set
#
# we must also run this with -j 0 so all the nodes are in the same build process otherwise
# delivery time is set in different processes and when a parent node reads it's dependencies
# delivery time, it may be defined in another process and not available 

# run with: pbs all -w 0 -ndpb -j 0


#NoDigest 'a$', 'c$' ;

AddRule 'all', ['all' => 'a', 'b'], BuildOk(), [SetTime(10, 3)] ;
AddRule 'a', ['a'], BuildOk(), [SetTime(1, 2)] ;
AddRule 'b', ['b' => 'c'], BuildOk(), [SetTime(3, 1)] ;
AddRule 'c', ['c'], BuildOk(), [SetTime(4, 3)] ;

AddPostBuildCommand 'post build', ['all', 'a', 'b', 'c'], \&ComputeDeliveryTime, 'hi' ;

sub SetTime 
{
my ($start_time, $build_time) = @_ ;
sub 
	{
	PrintDebug "node: $_[2]->{__NAME}, start_time: $start_time, build_time: $build_time\n" ;
	$_[2]->{__CONFIG} = { _START_TIME => $start_time, _BUILD_TIME => $build_time } ;
	}
}

sub ComputeDeliveryTime
{
my ($config, $name, $dependencies, $triggered_dependencies, $argument, $node, $inserted_nodes) = @_ ;

use List::Util qw(max) ;

my $start_time = max
			(
			($config->{_START_TIME} // 0),
			map 
				{
				PrintDebug "dependency $_: delivery_time: $inserted_nodes->{$_}{__CONFIG}{_DELIVERY_TIME}\n" ;
				$inserted_nodes->{$_}{__CONFIG}{_DELIVERY_TIME} // 0
				} grep { ! /__/ } keys %$node
			) ;

$config->{_DELIVERY_TIME} = $start_time + ($config->{_BUILD_TIME} // 0) ;

PrintDebug "'$name->[0]': start_time: $start_time,  delivery time: $config->{_DELIVERY_TIME}\n" ;

return(1, "OK Builder") ;
}


