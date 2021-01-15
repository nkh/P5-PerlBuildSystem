
traverse_graph($dependency_tree, \&ComputeDeliveryTime, $inserted_nodes) ;

sub traverse_graph
{
my ($node, $callback, @args) = @_ ;

my $enter = $callback->($node, 'entering', @args) ;

#PrintDebug "traversing $node->{__NAME} $enter\n" ; 

return unless $enter ;

for my $dependency (grep {! /^__/} keys %$node)
	{
	traverse_graph->($node->{$dependency}, $callback, @args) ;
	}

$callback->($node, 'leaving', @args) ;
}

use List::Util qw(max) ;

sub ComputeDeliveryTime
{
my ($node, $phase, $inserted_nodes) = @_ ;
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
					#PrintDebug "dependency $_: delivery_time: $inserted_nodes->{$_}{__CONFIG}{_DELIVERY_TIME}\n" ;
					$inserted_nodes->{$_}{__CONFIG}{_DELIVERY_TIME} // 0
					} grep { ! /^__/ } keys %$node
				) ;

	$config->{_MIN_START_TIME} = $min_start_time ;
	$config->{_DELIVERY_TIME} = $min_start_time + ($config->{_BUILD_TIME} // 0) ;

	PrintWarning "'$name': start_time: $start_time,  min_start_time: $min_start_time, build_time: $config->{_BUILD_TIME}, delivery time: $config->{_DELIVERY_TIME}\n" ;
	}
}

# ----------------------------------------------------------------------
1;

