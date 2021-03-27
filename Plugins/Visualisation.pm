

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

use Time::HiRes qw(gettimeofday tv_interval) ;
use Data::TreeDumper ;
use File::Slurp ;

use PBS::Digest ;
use PBS::PBSConfigSwitches ;
use PBS::Information ;
use PBS::Build::ForkedNodeBuilder ; # for log file name
use PBS::Log::ForkedLNI ;

#-------------------------------------------------------------------------------

sub PostDependAndCheck
{
my ($pbs_config, $node, $inserted_nodes, $build_sequence) = @_ ;

if($pbs_config->{DISPLAY_PBSUSE_STATISTIC})
	{
	Print Info2 PBS::PBS::GetPbsUseStatistic() ;
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
		SIT $inserted_nodes->{$local_child}{__DEPENDENCY_TO}, "$local_child ancestors:",
			FILTER => $DependenciesOnly, DISPLAY_ADDRESS => 0,
		}
	else
		{
		Say Error "PBS: ancestor query, no such node $pbs_config->{DEBUG_DISPLAY_PARENT}" ;
		DisplayCloseMatches($pbs_config->{DEBUG_DISPLAY_PARENT}, $inserted_nodes) ;
		}
	}

if(@{$pbs_config->{DISPLAY_NODE_INFO}})
	{
	for my $node_name (sort keys %$inserted_nodes)
		{
		for my $node_info_regex (@{$pbs_config->{DISPLAY_NODE_INFO}})
			{
			if($inserted_nodes->{$node_name}{__NAME} =~ /$node_info_regex/)
				{
				do
					{
					PBS::Information::DisplayNodeInformation($inserted_nodes->{$node_name}, $pbs_config, 1, $inserted_nodes) 
					}
					unless $inserted_nodes->{$node_name}{__WARP_NODE} ;
				
				last ;
				}
			}
		}
	}
	
if (@{$pbs_config->{LOG_NODE_INFO}})
	{
	my $t0 = [gettimeofday];
	Print Info "Log: creating pre-build node dependency info ..." ;

	my @lnis ;

	for my $node_name 
		(
		grep { 
			(! $inserted_nodes->{$_}{__WARP_NODE})
			&& NodeIsGenerated($inserted_nodes->{$_}) 
			}
			keys %$inserted_nodes
		)
		{
		for my $node_info_regex (@{$pbs_config->{LOG_NODE_INFO}})
			{
			if($node_name =~ /$node_info_regex/ && (! $inserted_nodes->{$node_name}{__WARP_NODE} ))
				{
				push @lnis, $inserted_nodes->{$node_name} ;
				last ;
				}
			}
		}

	PBS::Log::ForkedLNI::ParallelLNI($pbs_config, $inserted_nodes, \@lnis) ;
	Say Info sprintf(" (nodes: %d, time: %0.2f s.)", scalar(@lnis),  tv_interval($t0, [gettimeofday])) ;
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
	my $nodes_in_build_sequence = @$build_sequence ;

	my $GetBuildNames = 
		sub
		{
		my $tree = shift ;
		
		return ('HASH', undef, sort grep { /^(__NAME|__BUILD_NAME)/} keys %$tree) if('HASH' eq ref $tree) ;
		return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
		} ;
	
	SIT $build_sequence, "Sequence: nodes:$nodes_in_build_sequence", FILTER => $GetBuildNames ;
	}

if($pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE})
	{
	my $parallel_nodes = grep { $_->{__NAME} !~ /^__/ && $_->{__PARALLEL_DEPEND}} @$build_sequence ;
	my $nodes = @$build_sequence ;
	my $ratio = $nodes ? sprintf('ratio: %.02f', $parallel_nodes / $nodes) : 'up to date' ;

	Say Info "Sequence: $node->{__NAME}, nodes: " . $nodes . ($pbs_config->{PBS_JOBS} ? ", parallel: $parallel_nodes, $ratio" : '');
	
	unless ($pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE_STATS_ONLY})
		{
		Say Info $_ for map { $_->{__NAME} . ($_->{__PARALLEL_DEPEND} ? '∥ ' : '') } grep { $_->{__NAME} !~ /^__/ } @$build_sequence ;
		}
	}

if($pbs_config->{SAVE_BUILD_SEQUENCE_SIMPLE})
	{
	write_file($pbs_config->{SAVE_BUILD_SEQUENCE_SIMPLE}, (map { $_->{__NAME} . "\n" } grep { $_->{__NAME} !~ /^__/ } @$build_sequence)) ;
	}
}

#-------------------------------------------------------------------------------

1 ;
