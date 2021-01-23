
# set gant data in the node's config, give the node it's own config as it may be shared
sub GantTime 
{
my ($start_time, $build_time, $verbose) = @_ ;
sub 
	{
	my ($dependent_to_check, $config, $node, $inserted_nodes) = @_ ;

	PrintInfo4 "GANT: setting $node->{__NAME}, start_time: $start_time, build_time: $build_time\n" if $verbose;
	$node->{__CONFIG} = { %{$node->{__CONFIG}}, _GANT_START_TIME => $start_time, _GANT_BUILD_TIME => $build_time } ;
	}
}

# insert gant nodes in the graph

PbsUse('Dependers/Matchers') ;

# all nodes get a gant node dependency, except PBS internal nodes
Rule ['first_plus 10'], 'gant_dependency', [AndMatch(qr<.>, NoMatch(qr/__PBS/), NoMatch(qr/\.gant$/)) => '$path/$basename.gant'] ;
#Rule 'gant_dependency', [AndMatch(qr<.>, NoMatch(qr/__PBS/), NoMatch(qr/\.gant$/)) => '$path/$basename.gant'] ;

# gant node rule
#	depender adds the original node's dependencies
#	builder compute delivery time
Rule ['first_plus 9'], 'gant_node', ['*.gant' => \&GANTDepender], \&ComputeGANTTime ;
#Rule 'gant_node', ['*.gant' => \&GANTDepender], \&ComputeGANTTime ;

sub GANTDepender
{
my ($dependent_to_check, undef, undef, $inserted_nodes, $dependencies, $builder_override) = @_ ;
my ($source_node_name) = $dependent_to_check =~ /(.*)\.gant$/ ;

return([1, grep { ! /^__/ and ! /\.gant$/ } keys %{$inserted_nodes->{$source_node_name}}]) ;
}

use List::Util qw(max) ;
use PBS::Rules::Builders ;

sub ComputeGANTTime
{
my ($config, $file_to_build, $dependencies, $triggering_dependencies, $node, $inserted_nodes) = @_ ;
my ($name) = ($node->{__NAME}) ;

# node we shadow
my ($source_node_name) = $name =~ /(.*)\.gant$/ ;

my $start_time = $inserted_nodes->{$source_node_name}{__CONFIG}{_GANT_START_TIME} // 0 ;
my $build_time = $inserted_nodes->{$source_node_name}{__CONFIG}{_GANT_BUILD_TIME} // 0 ;

my $min_start_time = max
			(
			$start_time,
			map 
				{
				my $file = $inserted_nodes->{$source_node_name}{$_}{__BUILD_NAME} . '.gant' ;
				my $data ;

				# use serialized nodes delivery time, so warp, parallel build, ... works
				unless ($data = do $file)
					{
					warn "couldn't parse $file: $@" if $@ ;
					warn "couldn't do $file: $!"    unless defined $data ;
					warn "couldn't run $file"       unless $data ;

					$data = {} ;
					}

				$data->{delivery_time} // 0 ;
				}
				grep { ! /^__/ && ! /\.gant$/ } keys %{$inserted_nodes->{$source_node_name}}
			) ;

# update node
$inserted_nodes->{$source_node_name}{__CONFIG}{_GANT_MIN_START_TIME} = $min_start_time ;

my $delivery_time = $min_start_time + $build_time ;
$inserted_nodes->{$source_node_name}{__CONFIG}{_GANT_DELIVERY_TIME} = $delivery_time ; 

my $gant = "{node => \"$name\", start_time => $start_time,  min_start_time => $min_start_time, build_time => $build_time, delivery_time => $delivery_time}" ;

use Data::TreeDumper ;
PrintInfo4 DumpTree eval($gant), "GANT: '$name'" ;

# serialize the data
# having artefacts makes it makes it possible to run with warp and parallel builds

RunShellCommands
	(
	PBS::Rules::Builders::EvaluateShellCommandForNode
		(
		"echo '$gant' > %FILE_TO_BUILD",
		"gant builder",
		$node,
		$dependencies,
		$triggering_dependencies,
		)
	) ;

return (1, "OK Builder") ;
}

#--------------------------------------------------
1 ;

