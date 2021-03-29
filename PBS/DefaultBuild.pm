
package PBS::DefaultBuild ;
use PBS::Debug ;

use Data::Dumper ;
use strict ;
use warnings ;

use v5.10 ;
 
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
use List::Util qw(any) ;

use PBS::Build ;
use PBS::Rules ;
use PBS::Depend ;
use PBS::Check ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Information ;
use PBS::Plugin ;
use PBS::PBS::Forked ;

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
	$tree,
	$build_point,
	$build_type,
	) = @_ ;

my $t0_depend = [gettimeofday] ;

my $indent = $PBS::Output::indentation ;

my $short_pbsfile = GetRunRelativePath($pbs_config, $Pbsfile, 1) ;

my $build_directory    = $pbs_config->{BUILD_DIRECTORY} ;
my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;

my ($package, $file_name, $line) = caller() ;

my $config           = { PBS::Config::ExtractConfig($config_snapshot, $config_namespaces) } ;
my $dependency_rules = [PBS::Rules::ExtractRules($pbs_config, $Pbsfile, $rules, @$rules_namespaces)];

RunPluginSubs($pbs_config, 'PreDepend', $pbs_config, $package_alias, $config_snapshot, $config, $source_directories, $dependency_rules) ;

my $start_nodes = scalar(keys %$inserted_nodes) ;
   $start_nodes++ unless 0 == $PBS::Output::indentation_depth; # subpbs target was inserted parent even if it's not in %inserted_nodes

my $available = (chars() // 10_000) - (length($indent x ($PBS::Output::indentation_depth + 2)) + 50 + length($PBS::Output::output_info_label)) ;
my $em = String::Truncate::elide_with_defaults({ length => ($available < 3 ? 3 : $available), truncate => 'middle' });

my $short_target = $em->( join ', ', @$targets) ; 

my $pbs_runs = PBS::PBS::GetPbsRuns() ;

my $parallel_depend = exists $inserted_nodes->{$targets->[0]} && exists $inserted_nodes->{$targets->[0]}{__PARALLEL_DEPEND} ;
my $Depend = 'Depend' . ($parallel_depend ? '∥ ' : '') ;

my $target = _INFO3_($short_target) . _INFO2_( $pbs_config->{PBS_JOBS} ? ", pid: $$" : '') . GetColor('info')  ;

my $pbsfile_file  = "pbsfile: $short_pbsfile" ;
my $pbsfile_nodes = _INFO2_ "total nodes: $start_nodes, [$pbs_runs/$PBS::Output::indentation_depth]" ;
my $pbsfile_info  = "$pbsfile_file, $pbsfile_nodes" ;

if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
	{
	Say Info  "$Depend: $target" ;
	Say Info2 "${indent}$pbsfile_info" ;
	}
elsif($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES})
	{
	Say Info "$Depend: $target\n" . _INFO2_ "${indent}$pbsfile_info"
	}
elsif($pbs_config->{DISPLAY_DEPEND_HEADER})
	{
	Say Info "$Depend: $target"
	}
elsif($pbs_config->{DISPLAY_NO_STEP_HEADER})
	{
	Print Info "\r\e[K$Depend: $target $pbsfile_nodes" unless $pbs_config->{DISPLAY_NO_STEP_HEADER_COUNTER} ;
	PrintInfo "\n" if $pbs_config->{DISPLAY_STEP_HEADER_NL} ;
	}
else
	{
	Say Info "$Depend: $target" 
	}

my $local_time =
	PBS::Depend::CreateDependencyTree
		(
		$pbsfile_chain,
		$Pbsfile,
		$package_alias,
		$load_package,
		$pbs_config,
		$tree,
		$config,
		$inserted_nodes,
		$dependency_rules,
		{},
		) ;

my $added_nodes_in_run = @{(PBS::Depend::GetNodesPerPbsRun()->{$load_package} // [])} ;
$added_nodes_in_run -= 1 unless 0 == $PBS::Output::indentation_depth; # subpbses target is already counted in the parents count

if ($pbs_config->{DISPLAY_DEPEND_END})
	{
	my $end_nodes = scalar(keys %$inserted_nodes) ;
	my $added_nodes = $end_nodes - $start_nodes ;

	Say EC "<I>$Depend: $target, done<I2>, nodes: $added_nodes_in_run, total nodes: $end_nodes (+$added_nodes)" ;
	}

if($pbs_config->{DISPLAY_DEPENDENCY_TIME})
	{
	my $time = sprintf("%0.4f s.", tv_interval ($t0_depend, [gettimeofday])) ;
	my $time2 = sprintf("%0.4f s.", $local_time) ;

	my $template = "$Depend: '%s', time: $time, local time: $time2" ;
	my $available = PBS::Output::GetScreenWidth() - length($template) ;

	my $em = String::Truncate::elide_with_defaults({ length => ($available < 3 ? 3 : $available), truncate => 'middle' }) ;

	Say Info2 sprintf($template, $em->(GetRunRelativePath($pbs_config, $Pbsfile, 1))) ;
	}
	
if ($added_nodes_in_run > $pbs_config->{DISPLAY_TOO_MANY_NODE_WARNING})
	{
	Say Warning "$Depend: warning too many nodes: $added_nodes_in_run, pbsfile: '$Pbsfile'" ;
	}

if($pbs_config->{DEBUG_DISPLAY_RULE_STATISTICS})
	{
	my ($rule_type_max_length, $rule_name_max_length, $calls, $skipped, $matches, $number_of_rules) = (0, 0, 0, 0, 0, 0) ;
	my %types ;

	for my $rule ( @{$rules->{Builtin}}, @{$rules->{User}} )
		{
		my $rule_types = GetRuleTypes($rule) ;

		$types{$rule->{NAME}} = $rule_types ;
		
		my $length = length($rule->{NAME}) ;
		$rule_name_max_length = $length if $length > $rule_name_max_length ; 

		my $type_length = length($rule_types) ;
		$rule_type_max_length = $type_length if $type_length > $rule_type_max_length ; 

		$number_of_rules++ ;
		$calls += $rule->{STATS}{CALLS} // 0 ; 
		$matches += @{$rule->{STATS}{MATCHED} // []} ; 
		$skipped += $rule->{STATS}{SKIPPED} // 0 ; 
		}

	Say Info "$Depend: '" . GetRunRelativePath($pbs_config, $Pbsfile, 1) . "', "
			. "rules: $number_of_rules, "
			. "calls: $calls, "
			. "skipped: $skipped, " 
			. "matches: $matches, "
			. "match rate: " . sprintf("%0.02f", ($matches + $skipped) / ($calls || 1))
			. "\n";

	$rule_name_max_length++ ; # we add ':' to the name

	Say Info "\t\t" . (' ' x $rule_name_max_length) . " called  skipped  matched types\n" ;

	for my $rule (@{$rules->{Builtin}}, @{$rules->{User}} )
		{
		my $matched = scalar(@{$rule->{STATS}{MATCHED} // []}) ;
		$matched = $matched ? sprintf("%7d", $matched) : _ERROR_ sprintf("%7s", 0) ;

		my $stat = sprintf "%${rule_name_max_length}s %6d  %7d %s %-${rule_type_max_length}s",
					"$rule->{NAME}:",
					($rule->{STATS}{CALLS} // 0),
					($rule->{STATS}{SKIPPED} // 0),
					$matched,
					_INFO_ $types{$rule->{NAME}} ;

		Say Info "\t\t$stat" ;
		}
	}
elsif($pbs_config->{DISPLAY_NON_MATCHING_RULES})
	{
	for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
		{
		my $rule = $dependency_rules->[$rule_index] ;

		unless($rule->{MATCHED})
			{
			my $info = $rule->{NAME} . ':' . GetRunRelativePath($pbs_config, $rule->{FILE}) . ':' . $rule->{LINE} ;

			Say Warning3 "$Depend: '$info' @ $short_target didn't match, calls: $rule->{STATS}{CALLS}, skipped: " . ($rule->{STATS}{SKIPPED} // 0) ;
			}
		}
	}

if($pbs_config->{DISPLAY_CONFIG_USAGE})
	{
	my $accessed = PBS::Config::GetConfigAccess($load_package) ;
	my @not_accessed = 
		$pbs_config->{DISPLAY_TARGET_PATH_USAGE}
			? sort grep { ! exists $accessed->{$_} } keys %$config
			: sort grep { ! exists $accessed->{$_} && $_ ne 'TARGET_PATH'} keys %$config ;

	PrintInfo DumpTree { Accessed => $accessed, 'Not accessed' => \@not_accessed},
		 "Config: variable usage for '$targets->[0]':", DISPLAY_ADDRESS => 0 ;
	}

Say ' ' if $pbs_config->{DISPLAY_DEPEND_NEW_LINE} ;

for my $target (@$targets)
	{ 
	RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $inserted_nodes->{$target}, $inserted_nodes, [], $inserted_nodes->{$target})
		if $pbs_config->{DEBUG_VISUALIZE_AFTER_SUPBS} ;
	}

#-------------------------------------------------------------------------------

return (BUILD_SUCCESS, 'Dependended successfuly', [])
	if DEPEND_ONLY == $build_type || $pbs_config->{DEPEND_ONLY} ;

#-------------------------------------------------------------------------------

if($pbs_config->{DISPLAY_NO_STEP_HEADER})
	{
	my $number_of_nodes = scalar(keys %$inserted_nodes) ;
	
	PrintInfo "\r\e[K" unless $pbs_config->{DISPLAY_NO_STEP_HEADER_COUNTER} ;
	PrintInfo "\n" if $pbs_config->{DISPLAY_STEP_HEADER_NL} ;
	}

$pbs_runs = PBS::PBS::GetPbsRuns() ;

my $nodes          = scalar keys %$inserted_nodes ;
my $non_warp_nodes = scalar grep{! exists $inserted_nodes->{$_}{__WARP_NODE}} keys %$inserted_nodes ;
my $warp_nodes     = $nodes - $non_warp_nodes ;

my $time = tv_interval ($t0_depend, [gettimeofday]) ;

if($pbs_config->{DISPLAY_TOTAL_DEPENDENCY_TIME})
	{
	Say Info sprintf("$Depend: pbsfiles: $pbs_runs, time: %0.2f s., nodes: $nodes, warp: $warp_nodes, other: $non_warp_nodes", $time)
		unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;
	}
else
	{
	Say Info "$Depend: pbsfiles: $pbs_runs, nodes: $nodes, warp: $warp_nodes, other: $non_warp_nodes"
		unless $pbs_config->{QUIET} || $pbs_config->{DISPLAY_NO_STEP_HEADER} ;
	}

my ($build_node, $build_sequence) =
	Check
		(
		$pbs_config,
		$config,
		$targets,
		$inserted_nodes,
		$tree,
		$build_point,
		$build_type,
		) ;

#-------------------------------------------------------------------------------

return BUILD_SUCCESS, 'Generated build sequence', $build_sequence 
	if DEPEND_AND_CHECK == $build_type || $pbs_config->{DEPEND_AND_CHECK} ;

#-------------------------------------------------------------------------------

PBS::PBS::Forked::LinkMainGraph($pbs_config, $inserted_nodes, $targets, $time) ;


PBS::PBS::Forked::Build
	(
	$pbs_config,
	$config,
	$targets,
	$inserted_nodes,
	$tree,
	$build_point,
	$build_type,
	$build_node,
	$build_sequence,
	) ;
}

sub Check
{
my 
	(
	$pbs_config,
	$config,
	$targets,
	$inserted_nodes,
	$tree,
	$build_point,
	$build_type,
	) = @_ ;

my $indent = $PBS::Output::indentation ;

my ($build_node, @build_sequence, %trigged_nodes) ;

if($build_point eq '')
	{
	$build_node = $tree ;
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
			my @matches = GetCloseMatches($build_point, $inserted_nodes) ;
			
			if(@matches == 0)
				{
				Say Error "PBS: no such node '$build_point', found nothing matching" ;
				die "\n" ;
				}
			elsif(@matches == 1)
				{
				$build_node = $inserted_nodes->{$matches[0]} ;
				}
			else
				{
				Say Error "PBS: no such node '$build_point'" ;
				DisplayCloseMatches $build_point, $inserted_nodes ;
				die "\n" ;
				}
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
			#~Say Warning "Node '$inserted_nodes->{$node_name}{__NAME}' wasn't checked!" ;
			
			if(exists $inserted_nodes->{$node_name}{__TRIGGER_INSERTED})
				{
				Say EC "<I>Check: <I3>$inserted_nodes->{$node_name}{__NAME} [T]"
					 unless $pbs_config->{DISPLAY_NO_STEP_HEADER} ;

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

Say Info sprintf("Check: time: %0.2f s.", tv_interval ($t0_check, [gettimeofday]))
	if $pbs_config->{DISPLAY_CHECK_TIME} and ! exists $inserted_nodes->{$targets->[0]}{__PARALLEL_HEAD} ;

if($pbs_config->{DISPLAY_FILE_LOCATION_ALL})
	{
	for my $name (keys %$inserted_nodes)
		{
		my $node = $inserted_nodes->{$name} ;
		my $full_name = $node->{__BUILD_NAME} ;

		my $is_alternative_source++ if exists $node->{__ALTERNATE_SOURCE_DIRECTORY} ;
		my $is_virtual = exists $node->{__VIRTUAL} ;
		
		Say EC "<I>Node: <I3>$name" 
			. ($is_alternative_source ? '<I2> -> [R]' : '')
			. ($is_virtual ? '<I2> -> [V]' : $full_name ne $name ? " -> $full_name" : '')
		} 
	}

# die later if check failed (ex: cyclic tree), run visualisation plugins first
my $check_failed = $@ ;

# ie: -tt options
for my $target (@$targets)
	{ 
	RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $inserted_nodes->{$target}, $inserted_nodes, \@build_sequence, $build_node)
		unless $pbs_config->{DEBUG_VISUALIZE_AFTER_SUPBS} ;
	}

if($check_failed !~ /^DEPENDENCY_CYCLE_DETECTED/ && defined $pbs_config->{INTERMEDIATE_WARP_WRITE} && 'CODE' eq ref $pbs_config->{INTERMEDIATE_WARP_WRITE})
	{
	$pbs_config->{INTERMEDIATE_WARP_WRITE}->($tree, $inserted_nodes) ;
	}

if ($check_failed)
	{
	PrintError "PBS: error: $check_failed" ;
	die "\n" ;
	}


$tree->{__BUILD_SEQUENCE} = \@build_sequence ;

$build_node, $tree->{__BUILD_SEQUENCE}
}


sub Build
{
my 
	(
	$pbs_config,
	$config,
	$targets,
	$inserted_nodes,
	$tree,
	$build_point,
	$build_type,
	$build_node,
	$build_sequence,
	) = @_ ;

my ($build_result, $build_message) ;

my $indent = $PBS::Output::indentation ;

if($pbs_config->{DO_BUILD})
	{
	($build_result, $build_message) 
		= PBS::Build::BuildSequence($pbs_config, $build_sequence, $inserted_nodes) ;

	Say Error 'Build: failed' unless $build_result == BUILD_SUCCESS ;
	
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

			Say EC "<I>Build: running post build command for node: <U>'$node->{__NAME}'" 
				if $pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS} ;

			my @r = $node->{__PBS_POST_BUILD}($node, $inserted_nodes) ;

			Say Info2 "${indent}node sub returned: @r" if @r && $pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS} ;
			}
		}

	Say Info sprintf("Build: ran $post_build_commands post build commands in: %0.2f s.", tv_interval($t0_pbs_post_build, [gettimeofday]))
		 if $post_build_commands && $pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS} ;

	}
else
	{
	($build_result, $build_message) = (BUILD_SUCCESS, 'DO_BUILD not set') ;
	
	my $reset_hash_iterator = keys %$pbs_config ;

	while(my ($debug_flag, $value) = each %$pbs_config) 
		{
		Say Warning "Build: $debug_flag" if ! defined $pbs_config->{NO_BUILD} && $debug_flag =~ /^DEBUG/ && defined $value ;
		}

	($build_result, $build_message) = (0, 'No build flags') ;
	}

RunPluginSubs($pbs_config, 'CreateDump', $pbs_config, $tree, $inserted_nodes, $build_sequence, $build_node) ;
RunPluginSubs($pbs_config, 'CreateLog', $pbs_config, $tree, $inserted_nodes, $build_sequence, $build_node) ;

return $build_result, $build_message, $build_sequence ;
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
