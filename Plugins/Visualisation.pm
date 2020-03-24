

=head1 Plugin Visualisation

This plugin handles the following PBS defined switches:

=over 2

=item --a

=item --ni

=item --lni

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
use PBS::Build::ForkedNodeBuilder ; # for log file name

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

				do
					{
					PBS::Information::DisplayNodeInformation($inserted_nodes->{$node_name}, $pbs_config) 
					}
					unless $inserted_nodes->{$node_name}{__WARP_NODE} ;

				last ;
				}
			$ni_regex_index++ ;
			}
		}
	}
	
if(exists $pbs_config->{LOG_NODE_INFO} && @{$pbs_config->{LOG_NODE_INFO}})
	{
	PrintInfo "Log: creating pre-buil node info ..." ;
	my $generated_node_info_log = 0 ;

	my @ni_regex_matched = (0) x @{$pbs_config->{LOG_NODE_INFO}} ;

	for my $node_name (sort keys %$inserted_nodes)
		{
		my $ni_regex_index = 0 ;

		for my $node_info_regex (@{$pbs_config->{LOG_NODE_INFO}})
			{
			if($inserted_nodes->{$node_name}{__NAME} =~ /$node_info_regex/)
				{
				$ni_regex_matched[$ni_regex_index] = 1 ;
					
				my (undef, $node_info_file) =
					PBS::Build::ForkedNodeBuilder::GetLogFileNames($inserted_nodes->{$node_name}) ;

				$node_info_file =~ s/\.log$/.node_info/ ;

				do
					{
					$generated_node_info_log++ ;
					my ($node_info, $log_node_info) = 
						PBS::Information::GetNodeInformation($inserted_nodes->{$node_name}, $pbs_config, 1) ;

					open(my $fh, '>', $node_info_file) or die ERROR "Error: --lni can't create '$node_info_file'.\n" ;
					print $fh $log_node_info ;
					}
					if (! $inserted_nodes->{$node_name}{__WARP_NODE} && $inserted_nodes->{$node_name}{__TRIGGERED})
						|| ! -e $node_info_file  ;

				last ;
				}
			$ni_regex_index++ ;
			}
		}
	PrintInfo " ($generated_node_info_log nodes)\n" ;
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
