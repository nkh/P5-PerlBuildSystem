
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
use String::Truncate ;
use Term::Size::Any qw(chars) ;

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
	$pbsfile_chain,
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

my $indent = $PBS::Output::indentation ;

my $build_directory    = $pbs_config->{BUILD_DIRECTORY} ;
my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;

my ($package, $file_name, $line) = caller() ;

my $t0_depend = [gettimeofday];

my $config           = { PBS::Config::ExtractConfig($config_snapshot, $config_namespaces)	} ;
my $dependency_rules = [PBS::Rules::ExtractRules($pbs_config, $Pbsfile, $rules, @$rules_namespaces)];

RunPluginSubs($pbs_config, 'PreDepend', $pbs_config, $package_alias, $config_snapshot, $config, $source_directories, $dependency_rules) ;

my $start_nodes = $PBS::Depend::BuildDependencyTree_calls // 0 ;

my $available = (chars() // 10_000) - (length($indent x ($PBS::Output::indentation_depth + 2)) + 35 + length($PBS::Output::output_info_label)) ;
my $em = String::Truncate::elide_with_defaults({ length => $available, truncate => 'middle' });

my $target_string = '' ; 
$target_string .= $em->($_) for (@$targets) ; 

my $pbs_runs = PBS::PBS::GetPbsRuns() ;
PrintInfo("Depend: " . INFO3($target_string, 0) . INFO2(", run: $pbs_runs, level: $PBS::Output::indentation_depth, nodes: $start_nodes\n", 0))
	unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;

if($pbs_config->{DISPLAY_COMPACT_DEPEND_INFORMATION})
	{
	my $number_of_nodes = scalar(keys %$inserted_nodes) ;
	PrintInfo("\r\e[K" . $PBS::Output::output_info_label . INFO("Depend: run: $pbs_runs, level: $PBS::Output::indentation_depth, nodes: $number_of_nodes", 0)) ;
	}
		
PBS::Depend::CreateDependencyTree
	(
	$pbsfile_chain,
	$Pbsfile,
	$package_alias,
	$load_package,
	$pbs_config,
	$dependency_tree,
	$config,
	$inserted_nodes,
	$dependency_rules,
	) ;

if ($pbs_config->{DISPLAY_DEPEND_END})
	{
	my $end_nodes = $PBS::Depend::BuildDependencyTree_calls // 0 ;
	my $added_nodes = $end_nodes - $start_nodes ;

	my $template = "Depend: done %s, level:$PBS::Output::indentation_depth, nodes:$end_nodes(+$added_nodes)\n" ;
	my $available = PBS::Output::GetScreenWidth() - length($template) ;
	my $em = String::Truncate::elide_with_defaults({ length => $available, truncate => 'middle' }) ;

	PrintWarning sprintf($template, $em->($Pbsfile)) ;
	}

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

return(BUILD_SUCCESS, 'Dependended successfuly', []) if(DEPEND_ONLY == $build_type || $pbs_config->{DEPEND_ONLY}) ;

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

if($pbs_config->{DISPLAY_COMPACT_DEPEND_INFORMATION})
	{
	my $number_of_nodes = scalar(keys %$inserted_nodes) ;
	PrintInfo("\r\e[K") ;
	}

$pbs_runs = PBS::PBS::GetPbsRuns() ;
my $plural = $pbs_runs > 1 ? 's' : '' ;

my $nodes = scalar(keys %$inserted_nodes) ;
my $non_warp_nodes = scalar(grep{! exists $inserted_nodes->{$_}{__WARP_NODE}} keys %$inserted_nodes) ;
my $warp_nodes = $nodes - $non_warp_nodes ;

if($pbs_config->{DISPLAY_TOTAL_DEPENDENCY_TIME})
	{
	PrintInfo(sprintf("Depend: pbsfile$plural: $pbs_runs, time: %0.2f s, nodes: $nodes,  warp: $warp_nodes, other: $non_warp_nodes\n", tv_interval ($t0_depend, [gettimeofday]))) ;
	}
else
	{
	PrintInfo "Depend: pbsfile$plural: $pbs_runs, nodes: $nodes,  warp: $warp_nodes, other: $non_warp_nodes\n" unless defined $pbs_config->{QUIET};
	}

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
			PrintError("Build: no such build point: '$build_point'\n") ;
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
	
	# check if any triggered top node has been left outside the build
	for my $node_name (keys %$inserted_nodes)
		{
		next if (! defined $inserted_nodes->{$node_name}{__NAME}) || $inserted_nodes->{$node_name}{__NAME} =~ /^__/ ;
		
		unless(exists $inserted_nodes->{$node_name}{__CHECKED})
			{
			#~PrintWarning("Node '$inserted_nodes->{$node_name}{__NAME}' wasn't checked!\n") ;
			
			if(exists $inserted_nodes->{$node_name}{__TRIGGER_INSERTED})
				{
				PrintInfo("Check: trigger inserted '$inserted_nodes->{$node_name}{__NAME}'\n") unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;
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

	PrintInfo $stat_message unless $stat_message eq ''  ;
	} ;

PrintInfo(sprintf("Check: time: %0.2f s.\n", tv_interval ($t0_check, [gettimeofday]))) if $pbs_config->{DISPLAY_CHECK_TIME} ;

if($pbs_config->{DISPLAY_FILE_LOCATION_ALL})
	{
	for my $name (keys %$inserted_nodes)
		{
		my $node = $inserted_nodes->{$name} ;
		my $full_name = $node->{__BUILD_NAME} ;

		my $is_alternative_source++ if exists $node->{__ALTERNATE_SOURCE_DIRECTORY} ;
		my $is_virtual = exists $node->{__VIRTUAL} ;
		
		PrintInfo "Node: " . INFO3($name) 
				. INFO2($is_alternative_source ? ' -> [R]' : '')
				. INFO2($is_virtual ? ' -> [V]' : $full_name ne $name ? " -> $full_name" : '')
				. "\n" ;
		} 
	}

# die later if check failed (ex: cyclic tree), run visualisation plugins first
my $check_failed = $@ ;

# ie: -tt options
RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $dependency_tree, $inserted_nodes, \@build_sequence, $build_node) ;

if($check_failed !~ /^DEPENDENCY_CYCLE_DETECTED/ && defined $pbs_config->{INTERMEDIATE_WARP_WRITE} && 'CODE' eq ref $pbs_config->{INTERMEDIATE_WARP_WRITE})
	{
	$pbs_config->{INTERMEDIATE_WARP_WRITE}->($dependency_tree, $inserted_nodes) ;
	}

if ($check_failed)
	{
	PrintError "PBS: error: $check_failed" ;
	die "\n" ;
	}

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

$dependency_tree->{__BUILD_SEQUENCE} = \@build_sequence ;

return(BUILD_SUCCESS, 'Generated build sequence', \@build_sequence) if(DEPEND_AND_CHECK == $build_type || $pbs_config->{DEPEND_AND_CHECK}) ;

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

my ($build_result, $build_message) ;

if($pbs_config->{DO_BUILD})
	{
	($build_result, $build_message) 
		= PBS::Build::BuildSequence($pbs_config, \@build_sequence, $inserted_nodes) ;

	PrintError("Build: failed\n") unless $build_result == BUILD_SUCCESS ;
	
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
			&&
			(exists $node->{__PBS_POST_BUILD} && 'CODE' eq ref $node->{__PBS_POST_BUILD})
			)
			{
			$post_build_commands++ ;

			if ($pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS})
				{
				PrintInfo("Build: running post build command for node:" . USER(" '$node->{__NAME}'\n", 0)) ;
				}

			my @r = $node->{__PBS_POST_BUILD}($node, $inserted_nodes) ;
			PrintInfo2("${indent}node sub returned: @r\n") if @r && $pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS} ;
			}
		}

	PrintInfo(sprintf("Build: ran $post_build_commands post build commands in: %0.2f s.\n", tv_interval($t0_pbs_post_build, [gettimeofday])))
		 if ($post_build_commands && $pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS}) ;

	}
else
	{
	($build_result, $build_message) = (BUILD_SUCCESS, 'DO_BUILD not set') ;
	
	while(my ($debug_flag, $value) = each %$pbs_config) 
		{
		if(! defined $pbs_config->{NO_BUILD} && $debug_flag =~ /^DEBUG/ && defined $value)
			{
			PrintWarning("Build: $debug_flag\n") ;
			}
		}

	($build_result, $build_message) = (0, 'No build flags') ;
	}

RunPluginSubs($pbs_config, 'CreateDump', $pbs_config, $dependency_tree, $inserted_nodes, \@build_sequence, $build_node) ;
RunPluginSubs($pbs_config, 'CreateLog', $pbs_config, $dependency_tree, $inserted_nodes, \@build_sequence, $build_node) ;

return($build_result, $build_message, \@build_sequence) ;
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
