

=head1 Plugin Visualisation

This plugin handles the following PBS defined switches:

=over 2

=item --a

=item --ni

=item --dar

=item --dac

=item --files

=item --files_extra

=item --dbs

=back

=cut

use PBS::PBSConfigSwitches ;
use PBS::Information ;
use Data::TreeDumper ;

#-------------------------------------------------------------------------------

sub PostDependAndCheck
{
my ($pbs_config, $dependency_tree, $inserted_nodes, $build_sequence) = @_ ;

if($pbs_config->{DISPLAY_PBSUSE_STATISTIC})
	{
	PrintInfo2(PBS::PBS::GetPbsUseStatistic()) ;
	}
	
if(defined $pbs_config->{DEBUG_DISPLAY_PARENT})
	{
	my $local_child = $pbs_config->{DEBUG_DISPLAY_PARENT} ;
	$local_child = "./$local_child" unless $local_child =~ /^[.\/]/ ;
	
	my $DependenciesOnly = sub
				{
				my $tree = shift ;
				
				if('HASH' eq ref $tree)
					{
					return( 'HASH', undef, sort grep {! /^__/} keys %$tree) ;
					}
				
				return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
				} ;
							
	if(exists $inserted_nodes->{$local_child})
		{
		PrintInfo
			(
			DumpTree
				(
				$inserted_nodes->{$local_child}{__DEPENDENCY_TO},
				"\n$local_child ancestors:",
				FILTER => $DependenciesOnly, DISPLAY_ADDRESS => 0,
				)
			) ;
		}
	else
		{
		PrintError("PBS: ancestor query, no such node '$pbs_config->{DEBUG_DISPLAY_PARENT}'\n") ;
		DisplayCloseMatches($pbs_config->{DEBUG_DISPLAY_PARENT}, $inserted_nodes) ;
		}
	}

if(exists $pbs_config->{DISPLAY_NODE_INFO} && @{$pbs_config->{DISPLAY_NODE_INFO}})
	{
	my @ni_regex_matched = (0) x @{$pbs_config->{DISPLAY_NODE_INFO}} ;

	for my $node_name (sort keys %$inserted_nodes)
		{
		my $ni_regex_index = 0 ;

		for my $node_info_regex (@{$pbs_config->{DISPLAY_NODE_INFO}})
			{
			if($inserted_nodes->{$node_name}{__NAME} =~ /$node_info_regex/)
				{
				$ni_regex_matched[$ni_regex_index] = 1 ;

				PBS::Information::DisplayNodeInformation($inserted_nodes->{$node_name}, $pbs_config) 
					unless $inserted_nodes->{$node_name}{__WARP_NODE} ;
				last ;
				}
			$ni_regex_index++ ;
			}
		}

	my $no_ni_regex_matched = 1 ;
	for (my $ni_regex_index = 0 ; $ni_regex_index < @ni_regex_matched ; $ni_regex_index++)
		{
		if($ni_regex_matched[$ni_regex_index])
			{
			$no_ni_regex_matched = 0 ;
			}
		else
			{
			PrintWarning("Info: --ni $pbs_config->{DISPLAY_NODE_INFO}[$ni_regex_index] doesn't match any node in the graph.\n") ;
			}
		}
		
	PrintWarning("Info: no --ni switch matched.\n") if $no_ni_regex_matched ;
	}
	
if(defined $pbs_config->{DEBUG_DISPLAY_ALL_CONFIGURATIONS})
	{
	PBS::Config::DisplayAllConfigs() ;
	}

if(defined $pbs_config->{DISPLAY_ALL_RULES})
	{
	PBS::Rules::DisplayAllRules() ;
	}
   
if($pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE})
	{
	my $GetBuildNames = 
		sub
		{
		my $tree = shift ;
		return ('HASH', undef, sort grep { /^(__NAME|__BUILD_NAME)/} keys %$tree) if('HASH' eq ref $tree) ;	
		return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
		} ;
	
	PrintInfo(DumpTree($build_sequence, "\nBuildSequence:", FILTER => $GetBuildNames)) ;
	}

if($pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE})
	{
	PrintInfo "\nBuildSequence:\n" ;
	for (map { $_->{__NAME} } grep { $_->{__NAME} !~ /^__/ } @$build_sequence)
		{	
		PrintInfo "$_\n" ;
		}
	print "\n" ;
	}
}

#-------------------------------------------------------------------------------

1 ;
