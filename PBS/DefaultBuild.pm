
package PBS::DefaultBuild ;
use PBS::Debug ;

use Data::Dumper ;
use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(DefaultBuild) ;
our $VERSION = '0.04' ;

use Data::TreeDumper;
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Depend ;
use PBS::Check ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Information ;
use PBS::Plugin ;

#-------------------------------------------------------------------------------

sub DefaultBuild
{
my
	(
	$Pbsfile,
	$package_alias,
	$load_package,
	$pbs_config,
	$rules_namespaces,
	$rules,
	$config_namespaces,
	$config_snapshot,
	$targets,
	$inserted_nodes,
	$dependency_tree,
	$build_point,
	$build_type,
	) = @_ ;

my $build_directory    = $pbs_config->{BUILD_DIRECTORY} ;
my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;

my ($package, $file_name, $line) = caller() ;

my $t0_depend = [gettimeofday];

my $config           = { PBS::Config::ExtractConfig($config_snapshot, $config_namespaces)	} ;
my $dependency_rules = [PBS::Rules::ExtractRules($rules, @$rules_namespaces)];

RunPluginSubs($pbs_config, 'PreDepend', $pbs_config, $package_alias, $config_snapshot, $config, $source_directories, $dependency_rules) ;

my $start_nodes = $PBS::Depend::BuildDependencyTree_calls // 0 ;

PrintInfo("Depend: $package_alias\[$PBS::Output::indentation_depth], nodes:$start_nodes              \n") unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;

PBS::Depend::CreateDependencyTree
	(
	$Pbsfile,
	$package_alias,
	$load_package,
	$pbs_config,
	$dependency_tree,
	$config,
	$inserted_nodes,
	$dependency_rules,
	) ;

my $end_nodes = $PBS::Depend::BuildDependencyTree_calls // 0 ;
my $added_nodes = $end_nodes - $start_nodes ;

PrintInfo2("Depended: $package_alias\[$PBS::Output::indentation_depth], nodes:$end_nodes(+$added_nodes)\n") if $pbs_config->{DISPLAY_DEPEND_END} ;

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

return(BUILD_SUCCESS, 'Dependended successfuly') if(DEPEND_ONLY == $build_type) ;

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

my $pbs_runs = PBS::PBS::GetPbsRuns() ;
my $plural = $pbs_runs > 1 ? 's' : '' ;
PrintInfo "\e[KDepend: $pbs_runs pbsfile$plural.\n" ;

if($pbs_config->{DISPLAY_TOTAL_DEPENDENCY_TIME})
	{
	PrintInfo(sprintf("Depend: time: %0.2f s.\n", tv_interval ($t0_depend, [gettimeofday]))) ;
	}

PrintInfo("\nChecking:\n") unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;
my ($build_node, @build_sequence, %trigged_nodes) ;

if($build_point eq '')
	{
	$build_node = $dependency_tree ;
	}
else
	{
	# composite node
	if(exists $inserted_nodes->{$build_point})
		{
		$build_node = $inserted_nodes->{$build_point} ;
		}
	else
		{
		my $local_name = './' . $build_point ;
		if(exists $inserted_nodes->{$local_name})
			{
			$build_node = $inserted_nodes->{$local_name} ;
			$build_point = $local_name ;
			}
		else
			{
			PrintError("Build: no such build point: '$build_point'.\n") ;
			DisplayCloseMatches($build_point, $inserted_nodes) ;
			die "\n" ;
			}
		}
	}
	
my $t0_check = [gettimeofday];

eval
	{
	my $nodes_checker = RunUniquePluginSub($pbs_config, 'GetNodeChecker') ;
	PBS::Check::CheckDependencyTree
		(
		$build_node, # start of the tree
		0, # node level, used for some parallelizing optimization
		$inserted_nodes,
		$pbs_config,
		$config,
		$nodes_checker,
		undef, # single node checker
		\@build_sequence,
		\%trigged_nodes,
		) ;
	
	print ' ' x 30 . "\r" ;
	
	# check if any triggered top node has been left outside the build
	for my $node_name (keys %$inserted_nodes)
		{
		next if $inserted_nodes->{$node_name}{__NAME} =~ /^__/ ;
		
		unless(exists $inserted_nodes->{$node_name}{__CHECKED})
			{
			#~PrintWarning("Node '$inserted_nodes->{$node_name}{__NAME}' wasn't checked!\n") ;
			
			if(exists $inserted_nodes->{$node_name}{__TRIGGER_INSERTED})
				{
				PrintInfo("\nChecking Trigger Inserted '$inserted_nodes->{$node_name}{__NAME}'\n") unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;
				my @triggered_build_sequence ;
				
				PBS::Check::CheckDependencyTree
					(
					$inserted_nodes->{$node_name},
					0, #node level
					$inserted_nodes,
					$pbs_config,
					$config,
					$nodes_checker,
					undef, # single node checker
					\@triggered_build_sequence,
					\%trigged_nodes,
					) ;
				
				push @build_sequence, @triggered_build_sequence ;
				}
			}
		}

	my ($fn, $fp, $stat_message) = RunUniquePluginSub($pbs_config, 'GetWatchedFilesCheckerStats') ;
	RunUniquePluginSub($pbs_config, 'ResetWatchedFilesCheckerStats') ;

	PrintInfo $stat_message ;
	} ;

if($pbs_config->{DISPLAY_CHECK_TIME})
	{
	PrintInfo(sprintf("Check: total time: %0.2f s.\n", tv_interval ($t0_check, [gettimeofday]))) ;
	}

# die later if check failed (ex: cyclic tree), run visualisation plugins first
my $check_failed = $@ ;

# ie: -tt options
RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $dependency_tree, $inserted_nodes, \@build_sequence, $build_node) ;

if(defined $pbs_config->{INTERMEDIATE_WARP_WRITE} && 'CODE' eq ref $pbs_config->{INTERMEDIATE_WARP_WRITE})
	{
	$pbs_config->{INTERMEDIATE_WARP_WRITE}->($dependency_tree, $inserted_nodes) ;
	}

#~ return(BUILD_FAILED, $check_failed) if $check_failed ;
die $check_failed if $check_failed ;

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

$dependency_tree->{__BUILD_SEQUENCE} = \@build_sequence ;

return(BUILD_SUCCESS, 'Generated build sequence', \@build_sequence) if(DEPEND_AND_CHECK == $build_type) ;

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

unless($pbs_config->{DISPLAY_NO_STEP_HEADER})
	{
	PrintInfo("\nBuild: start") ;
	PrintInfo(" @ '$build_point'") if $build_point ne '' ;
	print "\n" ;
	}

# we must get the number of nodes in the tree from the tree itself as we might have multiple %inserted_nodes if
# subpbses are run in LOCALE_NODES mode
my $number_of_nodes_in_the_dependency_tree = 0 ;
my $node_counter = sub 
			{
			my $tree = shift ;
			if('HASH' eq ref $tree && exists $tree->{__NAME})
				{
				$number_of_nodes_in_the_dependency_tree++ if($tree->{__NAME} !~ /^__/) ;
				
				return('HASH', $tree, grep {! /^__/} keys %$tree) ; # tweak to run faster
				}
			else
				{
				return(undef) ; # prune
				}
			} ;
		
DumpTree($dependency_tree, '', NO_OUTPUT => 1, FILTER => $node_counter) ;
		
PrintInfo("Build: nodes in the dependency tree: $number_of_nodes_in_the_dependency_tree nodes\n") ;

my ($build_result, $build_message) ;

if($pbs_config->{DO_BUILD})
	{
	($build_result, $build_message) 
		= PBS::Build::BuildSequence($pbs_config, \@build_sequence, $inserted_nodes) ;

	if($build_result == BUILD_SUCCESS)
		{
		PrintInfo("Build: done\n") ;
		}
	else
		{
		PrintError("Build: failed\n") ;
		}
		
	# run a global post build
	# this allows nodes to modify the dependency tree before warp
	# it was added to support c dependency scanning done by the compiler, in parallel
	# it's a test feature
	# it works because the dependency step is sequential and will break if dependency is done in parallel
	my $t0_pbs_post_build = [gettimeofday];
	my $post_build_commands = 0 ;

	for my $node (values %$inserted_nodes)
		{
		if
			(
			(exists $node->{__BUILD_FAILED} || exists $node->{__TRIGGERED})

			&& (exists $node->{__PBS_POST_BUILD} && 'CODE' eq ref $node->{__PBS_POST_BUILD})
			)
			{
			PrintInfo "Build: running post build commands.\n" unless $post_build_commands ;
			$post_build_commands++ ;

			PrintInfo2 $PBS::Output::indentation . "$node->{__NAME}\n" if ($pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS}) ;
			$node->{__PBS_POST_BUILD}($node, $inserted_nodes) ;
			}
		}

	PrintInfo
		(
		$PBS::Output::indentation
		. sprintf("$post_build_commands commands in: %0.2f s.\n", tv_interval ($t0_pbs_post_build, [gettimeofday]))
		) if ($pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS}) ;

	}
else
	{
	($build_result, $build_message) = (BUILD_SUCCESS, 'DO_BUILD not set') ;
	PrintWarning("Build: NOT BULDING.\n") ;
	
	while(my ($debug_flag, $value) = each %$pbs_config) 
		{
		if($debug_flag =~ /^DEBUG/ && defined $value)
			{
			PrintWarning("Build: $debug_flag set.\n") ;
			}
		}

	($build_result, $build_message) = (0, 'No build flags') ;
	}

RunPluginSubs($pbs_config, 'CreateDump', $pbs_config, $dependency_tree, $inserted_nodes, \@build_sequence, $build_node) ;
RunPluginSubs($pbs_config, 'CreateLog', $pbs_config, $dependency_tree, $inserted_nodes, \@build_sequence, $build_node) ;

return($build_result, $build_message) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::DefaultBuild  -

=head1 SYNOPSIS

  use PBS::DefaultBuild ;
  DefaultBuild(....) ;
  
=head1 DESCRIPTION

The B<DefaultBuild> sub drives the build process by calling the B<depend>, B<check> and B<build> steps defined by B<PBS>,
it also displays information requested by the user (through the commmand line and via plugins). 

B<DefaultBuild> can be overridden by a user defined sub within a B<Pbsfile>.

=head2 EXPORT

None by default.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual

=cut
