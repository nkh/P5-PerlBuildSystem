

=head1 Plugin GraphGeneration

This plugin handles the following PBS defined switches:

=over 2

=item  --gtg

=item --gtg_p

=back

=cut

use PBS::PBSConfigSwitches ;
use PBS::Information ;
use Data::TreeDumper ;

#-------------------------------------------------------------------------------

sub PostDependAndCheck
{
my ($pbs_config, $dependency_tree, $inserted_nodes, $build_sequence, $build_node) = @_ ;

# find the inserted roots
my @trigger_inserted_roots ;
for my $node_name (keys %$inserted_nodes)
	{
	if(exists $inserted_nodes->{$node_name}{__TRIGGER_INSERTED})
		{
		push @trigger_inserted_roots, $inserted_nodes->{$node_name} ;
		}
	}
	
my $start_node = $build_node ;

if(defined $pbs_config->{GENERATE_TREE_GRAPH_START_NODE})
	{
	if(exists $inserted_nodes->{$pbs_config->{GENERATE_TREE_GRAPH_START_NODE}})
		{
		$start_node = $inserted_nodes->{$pbs_config->{GENERATE_TREE_GRAPH_START_NODE}} ;
		PrintInfo("Graph: using root: '$pbs_config->{GENERATE_TREE_GRAPH_START_NODE}'\n") ;
		}
	else
		{
		PrintWarning("Graph: Error: No such element '$pbs_config->{GENERATE_TREE_GRAPH_START_NODE}' in graph\n") ;

		DisplayCloseMatches($pbs_config->{GENERATE_TREE_GRAPH_START_NODE}, $inserted_nodes) ;

		PrintWarning("Graph: using root: '$start_node->{__NAME}'\n") ;
		}
	}


my $graph_title = '' ;
$graph_title .= "Partial Tree!\n" if($build_node != $dependency_tree) ;
$graph_title .= "Pbsfile: '$pbs_config->{PBSFILE}'" ;
	
if
	(
	   defined $pbs_config->{GENERATE_TREE_GRAPH} 
	|| defined $pbs_config->{GENERATE_TREE_GRAPH_HTML}
	|| defined $pbs_config->{GENERATE_TREE_GRAPH_SNAPSHOTS}
	)
	{
	eval "use PBS::Graph"; die $@ if $@ ;
	
	PBS::Graph::GenerateTreeGraphFile
		(
		  [$start_node, @trigger_inserted_roots], $inserted_nodes
		, $graph_title
		, $pbs_config
		) ;
	}
}

#-------------------------------------------------------------------------------

1 ;
