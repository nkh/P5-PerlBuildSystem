
traverse_graph($dependency_tree, \&ComputeDeliveryTime) ;

sub traverse_graph
{
my ($node, $callback, @args) = @_ ;

return unless $callback->($node, 'entering', @args) ;

traverse_graph->($node->{$_}, $callback, @args) for (grep {! /^__/} keys %$node) ;

$callback->($node, 'leaving', @args) ;
}

use List::Util qw(max) ;

sub ComputeDeliveryTime
{
my ($node, $phase) = @_ ;
my ($config, $name) = ($node->{__CONFIG}, $node->{__NAME}) ;

return 1 if $name =~ /^__/ ; # enter root node

if ('entering' eq $phase)
	{
	return ! defined $config->{_DELIVERY_TIME} ; # do not traverse a sub graph twice
	}
else
	{
	my $start_time = $config->{_START_TIME} // 0 ;
	my $min_start_time = max
				(
				$start_time,
				map 
					{
					#PrintDebug "dependency $_: delivery_time: $node->{$_}{__CONFIG}{_DELIVERY_TIME}\n" ;
					$node->{$_}{__CONFIG}{_DELIVERY_TIME} // 0
					} grep { ! /^__/ } keys %$node
				) ;

	$config->{_MIN_START_TIME} = $min_start_time ;
	$config->{_DELIVERY_TIME} = $min_start_time + ($config->{_BUILD_TIME} // 0) ;

	PrintInfo4 "GANT: '$name': start_time: $start_time,  min_start_time: $min_start_time, build_time: $config->{_BUILD_TIME}, delivery time: $config->{_DELIVERY_TIME}\n" ;
	}
}

# ----------------------------------------------------------------------

1 ;

