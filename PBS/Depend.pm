
package PBS::Depend ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;

#use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
use String::Truncate ;
use List::Util qw(any) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CreateDependencyTree) ;
our $VERSION = '0.08' ;

use PBS::PBS ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Triggers ;
use PBS::PostBuild ;
use PBS::Plugin;
use PBS::Information ;
use PBS::Digest ;

#-----------------------------------------------------------------------------------------

my %has_no_dependencies ;

sub HasNoDependencies
{
my ($package, $file_name, $line) = caller() ;

die ERROR "Invalid 'HasNoDependencies' arguments at $file_name:$line\n" if @_ % 2 ;

_HasNoDependencies($package, $file_name, $line, @_) ;
}

sub _HasNoDependencies
{
my ($package, $file_name, $line, %exclusion_patterns) = @_ ;
 
for my $name (keys %exclusion_patterns)
	{
	if(exists $has_no_dependencies{$package}{$name})
		{
		PrintWarning
			(
			"Depend: overriding HasNoDependencies entry '$name' defined at $has_no_dependencies{$package}{$name}{ORIGIN}:\n"
			. "\t$has_no_dependencies{$package}{$name}{PATTERN} "
			. "with $exclusion_patterns{$name} defined at $file_name:$line\n"
			) ;
		}
		
	$has_no_dependencies{$package}{$name} = {PATTERN => $exclusion_patterns{$name}, ORIGIN => "$file_name:$line"} ;
	}
}

sub OkNoDependencies
{
my ($package, $node) = @_ ;
my ($ok, $node_name, $pbs_config)  = (0, $node->{__NAME}, $node->{__PBS_CONFIG}) ;

for my $name (keys %{$has_no_dependencies{$package}})
	{
	if($node_name =~ $has_no_dependencies{$package}{$name}{PATTERN})
		{
		PrintWarning
			(
			"Depend: '$node_name' OK no dependencies,  rule: '$name' [$has_no_dependencies{$package}{$name}{PATTERN}]"
			. (defined $pbs_config->{ADD_ORIGIN} ? " @ $has_no_dependencies{$package}{$name}{ORIGIN}" : '')
			.".\n"
			) if(defined $pbs_config->{DISPLAY_NO_DEPENDENCIES_OK}) ;
			
		$ok++ ;
		last ;
		}
	}

$ok ;
}

#-------------------------------------------------------------------------------

my %nodes_per_pbs_run ;
sub GetNodesPerPbsRun { \%nodes_per_pbs_run  } 

#-------------------------------------------------------------------------------

sub GetRuleTrace
{
my ($pbs_config, $rule, $all) = @_ ;
my @rule_traces ;

unless 
	(
	# stack of 1 level, displayed and equivalent
	1 == @{$rule->{PBS_STACK}}
	&& $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE}
	&& $rule->{FILE} eq $rule->{PBS_STACK}[0]{FILE}
	&& $rule->{LINE} eq $rule->{PBS_STACK}[0]{LINE}
	&& ! $all
	)
	{
	for my $trace (@{$rule->{PBS_STACK}})
		{
		push @rule_traces, "$trace->{SUB} @ ". GetRunRelativePath($pbs_config, $trace->{FILE}) . ":$trace->{LINE}" ;
		}
	}

@rule_traces
}

sub DisplayRuleTrace
{
my ($pbs_config, $rule) = @_ ;

my @traces = GetRuleTrace($pbs_config, $rule) ;

if (@traces)
	{
	my $indent = $PBS::Output::indentation ;

	PrintInfo2 "${indent}${indent}rule '$rule->{NAME}':\n" ;
	for my $trace (@traces)
		{
		PrintInfo2 "${indent}$indent$indent$trace\n" ;
		}
	}
}

#-------------------------------------------------------------------------------

my %trigger_rules ;

sub CreateDependencyTree
{
my 	
	(
	$pbsfile_chain, $Pbsfile, $package_alias, $load_package,
	$pbs_config, $tree, $config, $inserted_nodes, $dependency_rules,
	$parent_matching_rules) = @_ ;

$load_package = PBS::PBS::CanonizePackageName($load_package) ;
$pbsfile_chain //=  [] ;
$parent_matching_rules //= {} ;

return if(exists $tree->{__DEPENDED}) ;

my ($t0_rules, $rule_time) = ([gettimeofday], 0) ;

$nodes_per_pbs_run{$load_package}++ ;

my (@node_matching_rules, @node_dependencies) ;
my $indent = $PBS::Output::indentation ;
my $node_name = $tree->{__NAME} ;

my $node_name_matches_ddrr = any { $node_name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}} ;

my %dependency_rules ; # keep a list of  which rules generated which dependencies
my $has_dependencies = 0 ;
my @has_matching_non_subpbs_rules ;
my @sub_pbs ; # list of subpbs matching this node

PrintInfo2("Rule: target:" . _INFO3_("'$node_name'") . _INFO2_(", rules: " . scalar(@{$dependency_rules}) . "\n"))
	if ($node_name !~ /^__/) && ($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX} || $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;

for my $post_build_command (PBS::PostBuild::GetPostBuildRules($load_package))
	{
	my ($match) = $post_build_command->{DEPENDER}($node_name) ;
	
	if($match)
		{
		push @{$tree->{__POST_BUILD_COMMANDS}}, $post_build_command ;
		
		PrintInfo "Depend: '$node_name' post build command, '$post_build_command->{NAME}$post_build_command->{ORIGIN}'\n"
			if $pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS} ;
		}
	}

my $available = PBS::Output::GetScreenWidth() ;
my $em_length = $available < 40 ? 40 : $available ;

my $em = String::Truncate::elide_with_defaults
		({
		marker => $pbs_config->{SHORT_DEPENDENCY_PATH_STRING},
		length => $available,
		truncate => 'middle' 
		});

# apply rules to find dependencies
my $rules_matching = 0 ;

for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
	{
	my $rule = $dependency_rules->[$rule_index] ;
	my $rule_name = $rule->{NAME} ;
	my $rule_line = $rule->{LINE} ;

	$rule->{STATS}{CALLS}++ ;

	my ($matched, @not_matched) = (0) ;

	# skip rule if it depends on another rule
	for my $before ( @{ $rule->{BEFORE} // [] })
		{
		if (exists $parent_matching_rules->{$before})
			{
			$matched++
			}
		else
			{
			push @not_matched, $before
			}
		}

	if((! $matched) && @not_matched)
		{
		PrintInfo2 "${indent}skipping rule '$rule_name' waiting for: '" . join(", '", @not_matched) . "'\n"
				if $node_name !~ /^__/ && $pbs_config->{DEBUG_DISPLAY_DEPENDENCY_REGEX} ;
			
		$rule->{STATS}{SKIPPED}++ ;
		next ;
		}

	#DEBUG
	my %debug_data ;
	if($PBS::Debug::debug_enabled)
		{
		%debug_data = 
			(
			TYPE           => 'DEPEND',
			RULE_NAME      => $rule_name,
			NODE_NAME      => $node_name,
			PACKAGE_NAME   => $package_alias,
			PBSFILE        => $Pbsfile,
			TREE           => $tree,
			INSERTED_FILES => $inserted_nodes,
			CONFIG         => $config,
			) ;
			
		$DB::single = 1 if(PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1)) ;
		}
		
	my $file = defined $pbs_config->{PBSFILE_CONTENT} ? 'virtual' : $rule->{FILE} ;
	my $rule_info = GetRunRelativePath($pbs_config, $rule_name . _INFO2_(" @ $file:$rule_line")) ;

   
	$rule->{STATS}{CALLED}++ ;

	my $depender  = $rule->{DEPENDER} ;
	my ($dependency_result, $builder_override) = $depender->($node_name, $config, $tree, $inserted_nodes, $rule) ;

	my ($triggered, @dependencies ) = @$dependency_result ;
	
	die ERROR "Depend: Error: While depending '$node_name', rule $rule_info, returned an undefined dependency\n"
		if grep {! defined } @dependencies ;

	#DEBUG
	$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1, TRIGGERED => $triggered, DEPENDENCIES => \@dependencies) ;
	
	if($triggered)
		{
		push @{$rule->{STATS}{MATCHED}}, $tree ;
		$rules_matching++ ;

		$rule->{MATCHED}++ ; # will be tagged in all the depend branches

		$tree->{__DEPENDED}++ ;
		$tree->{__DEPENDED_AT} = $Pbsfile ;
			
		push @{$tree->{__MATCHING_RULES}}, 
			{
			  RULE => 
				{
				INDEX             => $rule_index,
				DEFINITIONS       => $dependency_rules,
				BUILDER_OVERRIDE  => $builder_override,
				},
			DEPENDENCIES => \@dependencies,
			};
		
		my $subs_list = $rule->{NODE_SUBS} ;
		
		if(defined $subs_list)
			{
			my $subs = [] ;
			
			if('CODE' eq ref $subs_list)
				{
				push @$subs, $subs_list ;
				}
			elsif('ARRAY' eq ref $subs_list)
				{
				for(@$subs_list)
					{
					if('CODE' eq ref $_)
						{
						push @$subs, $_ ;
						}
					else
						{
						die ERROR "Depend: Error: node sub is not a sub in array at rule $rule_info\n" ;
						}
					}
				}
			else
				{
				PrintError "Depend: Error: node sub is not a sub @ $rule_info\n" ; die "\n" ;
				}
				
			my $index = 0 ;
			for my $sub (@$subs)
				{
				$index++ ;
			
				PrintUser(
					"$indent'$node_name'" 
					. _INFO_(" node sub $index/" . scalar(@$subs))
					. _INFO2_(" '$rule_name:$rule->{FILE}:$rule->{LINE}'\n"))
						if $pbs_config->{DISPLAY_NODE_SUBS_RUN} ;
				
				my @r = $sub->($node_name, $config, $tree, $inserted_nodes, $rule) ;
				
				PrintInfo2("$indent${indent}node sub returned: @r\n") if @r && $pbs_config->{DISPLAY_NODE_SUBS_RUN} ;
				}
			}
			
		#-------------
		# subpbs rule
		#-------------
		if(@dependencies && 'HASH' eq ref $dependencies[0])
			{
			$dependencies[0]{__RULE_NAME} = $rule->{NAME} ;
			push @sub_pbs, 
				{
				SUBPBS => $dependencies[0],
				RULE   => $rule,
				} ;
			
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddrr)
				{
				my $no_short_name = $pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH} ;

				my $glyph = '' eq $pbs_config->{TARGET_PATH}
						? "./"
						: $pbs_config->{SHORT_DEPENDENCY_PATH_STRING} ;

				my $short_node_name = $node_name ;
				$short_node_name =~ s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $no_short_name ;

				my $subpbs_file = $rule->{TEXTUAL_DESCRIPTION}{PBSFILE} ;
				$subpbs_file =~ s/^.\//$glyph\// unless $no_short_name ;

				my $rule_info = $rule_name . _INFO2_(" @ $file:$rule_line") ;
				$rule_info = GetRunRelativePath($pbs_config, $rule_info, 1) ;

				my $em_length = $available - length($short_node_name) ;
				$em_length = 40 if $em_length < 40 ;

				my $em = String::Truncate::elide_with_defaults
						({
						marker => $pbs_config->{SHORT_DEPENDENCY_PATH_STRING},
						length => $em_length,
						truncate => 'middle' 
						});

				my $display_node_matching_rule = $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE} || $pbs_config->{DISPLAY_SUBPBS_INFO} ;
				my $display_node_insertion_rule = $pbs_config->{DISPLAY_DEPENDENCY_INSERTION_RULE} || $pbs_config->{DISPLAY_SUBPBS_INFO} ;

				my $node_matching_rule = $display_node_matching_rule ? _INFO2_($em->("$rule_index:$rule_info")) : '' ;

				my $node_insertion_rule = $display_node_insertion_rule
								? _INFO2_(
									"inserted at: "
									. GetRunRelativePath
										(
										$pbs_config,
										exists $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
											? $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE}
											: $tree->{__INSERTED_AT}{INSERTION_RULE},
										1 # no target path replacement
										)
									)
								: '' ;

				if(defined $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
					{
					PrintInfo3
						(
						"${indent}'$short_node_name'\n"
						. _INFO_("$indent${indent}subpbs match") . _INFO2_(", pbsfile:'$subpbs_file'\n")
						. ($display_node_matching_rule ? "$indent${indent}$node_matching_rule\n" : '')
						. ($display_node_insertion_rule ? "$indent$indent$node_insertion_rule\n" : '')
						) ;
					}
				else
					{
					my $comma = _INFO2_(', ') ;

					PrintInfo3
						(
						"${indent}'$short_node_name'"
						. _INFO_(" subpbs match") . _INFO2_(", pbsfile: '$subpbs_file'")
						. ($display_node_matching_rule ? "$comma$node_matching_rule" : '')
						. ($display_node_insertion_rule ? "$comma$node_insertion_rule" : '')
						. "\n"
						) ;
					}

				DisplayRuleTrace($pbs_config, $rule) if defined $pbs_config->{DEBUG_TRACE_PBS_STACK} ;
				}
				
			next ;
			}
		else
			{
			push @has_matching_non_subpbs_rules, "rule '$rule_name', file '$rule->{FILE}:$rule->{LINE}'" ;
			push @node_matching_rules, $rule_name ;
			}
		
		# transform the node name into an internal structure and check for node attributes
		@dependencies = map
				{
				if(('' eq ref $_) && (! /^__/))
					{
					if(/(.*)::(.*)$/)
						{
						# handle node user attribute
						
						# return a hash
							{
							NAME => $1,
							RULE_INDEX => $rule_index,
							USER_ATTRIBUTE => $2,
							}
						}
					else
						{
						# return a hash
							{
							NAME => $_,
							RULE_INDEX => $rule_index,
							}
						}
					}
				else
					{
					# return a hash
						{
						NAME => $_,
						RULE_INDEX => $rule_index,
						}
					}
				} @dependencies ;
				
		#-------------------------------------------------------------------------
		# handle VIRTUAL, LOCAL OR FORCED rule type
		#-------------------------------------------------------------------------
		my %types = map { $_, 1 } (VIRTUAL, LOCAL, FORCED, IMMEDIATE_BUILD) ;
		
		for my $rule_type (@{$rule->{TYPE}})
			{
			$tree->{$rule_type} = 1 if(exists $types{$rule_type}) ;
			}
			
		#----------------------------------------------------------------------------
		# display the dependencies inserted by current rule
		#----------------------------------------------------------------------------
		if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddrr)
			{
			$node_name_matches_ddrr = 0 if ($node_name =~ /^__/) ;
			
			if($node_name_matches_ddrr)
				{
				my @node_type ;
				for my $type (VIRTUAL, LOCAL, FORCED, TRIGGER_INSERTED)
					{
					push @node_type, ($type =~ s/^__//r) if exists $tree->{$type} ;
					}

				my $node_type = scalar(@node_type) ? ' [' . join(', ', @node_type) . '] ' : '' ;
				
				my $rule_info =  $rule->{NAME}
						. (defined $pbs_config->{ADD_ORIGIN} 
							? $rule->{ORIGIN}
							: ':' . $rule->{FILE} . ':' . $rule->{LINE}) ;
				
				$rule_info = GetRunRelativePath($pbs_config, $rule_info, $pbs_config->{DISPLAY_DEPENDENCIES_FULL_PBSFILE}) ;

				my $rule_type = '' ;
				$rule_type .= '[B]'  if(defined $rule->{BUILDER}) ;
				$rule_type .= '[BO]' if($builder_override) ;
				$rule_type .= '[S]'  if(defined $rule->{NODE_SUBS}) ;
				$rule_type = " $rule_type" unless $rule_type eq '' ;

				my @dependency_names = map {$_->{NAME} ;} grep {'' eq ref $_->{NAME}} @dependencies ;
				
				
				my $forced_trigger = '' ;
				if(grep {$_->{NAME} =~ '__PBS_FORCE_TRIGGER' } @dependencies)
					{
					$forced_trigger = ' FORCED_TRIGGER!' ;
					}
				
				my $no_dependencies = '' ;
				unless(@dependency_names)
					{
					my $display_warning = 1 ;
					
					for my $regex (@{ $pbs_config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX} })
						{
						if($node_name =~ /$regex/)
							{
							$display_warning = 0 ;
							last ;
							} 
						}

					$no_dependencies = '' ;
					}

				my $no_short_name = $pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH} ;

				my $glyph = '' eq $pbs_config->{TARGET_PATH}
						? "./"
						: $pbs_config->{SHORT_DEPENDENCY_PATH_STRING} ;

				my $short_node_name = $node_name ;
				$short_node_name =~ s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $no_short_name ;

				my $node_matches = $rules_matching > 1 ? ", node matched $rules_matching rules" : '' ;

				my $node_insertion_rule = $pbs_config->{DISPLAY_DEPENDENCY_INSERTION_RULE}
								? _INFO2_(
									", inserted at: "
									. GetRunRelativePath
										(
										$pbs_config,
										exists $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
											? $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE}
											: $tree->{__INSERTED_AT}{INSERTION_RULE}
										)
									)
								: '' ;

				# the subpbs root node have no insertion data we can use
				$node_insertion_rule = '' if $node_insertion_rule =~ /PBS:Subpbs/ ;

				my $node_matching_rule = $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE}
								? _INFO2_(" $rule_index:$rule_info$rule_type$node_matches")
								: '' ;

				if(defined $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
					{
					PrintInfo3
						(
						$em->("$indent'$short_node_name'${node_type}${forced_trigger}")
						. "$node_matching_rule$node_insertion_rule\n"
						) ;

					if(@dependency_names)
						{
						PrintInfo
							 $indent . $indent
							. join
								(
								"\n$indent$indent",
								map 
									{
									DependencyIsSource($tree, $_, $inserted_nodes)
										? _WARNING_("'" . $em->($_) . "'")
										: _INFO_("'" . $em->($_) . "'")
									} 
									map { s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $no_short_name ; $_ }
										@dependency_names
								)
							. "\n" ;
						}
					else
						{
						PrintInfo "$indent$indent$no_dependencies\n" ;
						}
					}
				else
					{
					my $dd = INFO3 "$indent'$short_node_name'${node_type}${forced_trigger}" ;

					$dd .= @dependency_names
						? _INFO_
							(
							" => [ "
							. join
								(
								' ',
								map { DependencyIsSource($tree, $_, $inserted_nodes) ? _WARNING_("'$_'") : _INFO_("'$_'") }
									map
										{
										s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $no_short_name ; $_
										}
										 @dependency_names
								)
							)
							. _INFO_( " ]")
						: _INFO_(" => []") ;

					$dd .= $node_matching_rule . $node_insertion_rule ;
					$dd .= "\n" ;
					
					PrintNoColor '' . $dd ;
					}
					
				DisplayRuleTrace($pbs_config, $rule) if defined $pbs_config->{DEBUG_TRACE_PBS_STACK} ;

				PrintWithContext
					(
					$rule->{FILE},
					1, 2, # context  size
					$rule->{LINE},
					\&INFO,
					) if $pbs_config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION} ;
				}
			}
			
		if( exists $parent_matching_rules->{$rule_name})
			{
			if(@{$parent_matching_rules->{$rule_name}} + 1 > $pbs_config->{MAXIMUM_RULE_RECURSION})
				{
				PrintError "Depend: maximum rule recusion, rule: '$rule_name', pbsfile '$Pbsfile'\n" ;

				my @trace = ("rule '$rule_name' => '$node_name'") ;

				my $parent_rule = $tree->{__INSERTED_AT}{INSERTION_RULE_NAME} ;
				my $parent = $tree->{__INSERTED_AT}{INSERTING_NODE} ;
				while (defined $parent)
					{
					push @trace, "rule '$parent_rule' => '$parent'" ;

					$parent_rule =  $inserted_nodes->{$parent}{__INSERTED_AT}{INSERTION_RULE_NAME} ;
					$parent = $inserted_nodes->{$parent}{__INSERTED_AT}{INSERTING_NODE} ;
					}
				
				pop @trace ; # PBS root, for this package
				PrintError "Depend: rules trace:\n" ;
				PrintError "$indent$_\n" for reverse @trace ;

				die "\n" ;
				}

			if(@{$parent_matching_rules->{$rule_name}} == 1)
				{
				PrintWarning "$indent${indent}warning, rule '$rule_name' matched '$node_name' and parent '$parent_matching_rules->{$rule_name}[0]'\n", 1 ;
				}

			if
				(
				@{$parent_matching_rules->{$rule_name}} >= $pbs_config->{RULE_RECURSION_WARNING}
				&& ! (@{$parent_matching_rules->{$rule_name}} % 5)
				)
				{
				PrintWarning "$indent${indent}warning, rule '$rule_name' matched '$node_name' and "
						. scalar(@{$parent_matching_rules->{$rule_name}}) . " parent nodes\n", 1 ;
				}
			} 

		#----------------------------------------------------------------------------
		# Check the dependencies
		#----------------------------------------------------------------------------
		for my $dependency (@dependencies)
			{
			my $dependency_name = $dependency->{NAME} ;
			if(my ($reason) = $dependency_name =~ /__PBS_FORCE_TRIGGER:?(.*)?/)
				{
				$reason .= ' ' . $rule->{NAME} . $rule->{ORIGIN} ;

				push @{$tree->{__PBS_FORCE_TRIGGER}}, {NAME => $dependency_name, REASON => $reason} ;
				next ;
				}
				
			next if $dependency_name =~ /^__/ ;
			
			RunPluginSubs($pbs_config, 'CheckNodeName', $dependency_name, $rule) ;
			
			if($node_name eq $dependency_name)
				{
				my $rule_info = defined $pbs_config->{VIRTUAL_PBSFILE_TARGET}
							? $rule->{NAME} . ':virtual_pbsfile:' . $pbs_config->{VIRTUAL_PBSFILE_TARGET} . ':' . $rule->{LINE} 
							: $rule->{NAME} . $rule->{ORIGIN} ;
				
				my $dependency_names = join ' ', map{$_->{NAME}} @dependencies ;
				PrintError "\nDepend: Error: self referential rule\n"
						. "\trule: '$rule_info'\n"
						. "\tcycle: $node_name => $dependency_names\n" ;
				
				PbsDisplayErrorWithContext($pbs_config, $rule->{FILE}, $rule->{LINE}) ;
				die "\n";
				}
			
			if(exists $tree->{$dependency_name})
				{
				unless($dependency_name =~ /^__/)
					{
					if(defined $pbs_config->{DISPLAY_DUPLICATE_INFO})
						{
						my $rule_info = $rule->{NAME} . $rule->{ORIGIN} ;
											
						my $inserting_rule_index = $tree->{$dependency_name}{RULE_INDEX} ;
						my $inserting_rule_info  =  $dependency_rules->[$inserting_rule_index]{NAME}
										. $dependency_rules->[$inserting_rule_index]{ORIGIN} ;
											
						PrintWarning
							(
							  "Depend: ignoring duplicate dependency '$dependency_name'\n"
							. "\tpbsfile: $Pbsfile\n"
							. "\trule: $rule_info\n"
							. "\tnode: '$node_name'\n"
							. "\tinserting rule: $inserting_rule_index:$inserting_rule_info\n"
							) ;
						}
					}
				}
			else
				{
				# temporarily hold the names of the dependencies within the node
				# this is used for checking duplicate dependencies
				$tree->{$dependency_name} = $dependency ;
				}
			}

		push @node_dependencies, @dependencies ;
		}
	else
		{
		# not triggered
		push @{$rule->{STATS}{NOT_MATCHED}}, $tree ;

		my $depender_message = $dependencies[0] // 'No match' ;
		PrintColor('no_match', "$PBS::Output::indentation$depender_message, $rule_info\n") if(defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;
		}
	}

#-----------------------------
# remove dependency doubles 
#-----------------------------
my (@dependencies, %seen) ;

for my $dependency (@node_dependencies)
	{
	push @dependencies, $tree->{$dependency->{NAME}} unless $seen{$dependency->{NAME}}++ ;
	}

if(@sub_pbs > 1)
	{
	PrintError "Depend: in pbsfile : $Pbsfile, $node_name has multiple matching subpbs:\n" ;
	PrintError(DumpTree(\@sub_pbs, "Subpbs:")) ;
	
	Carp::croak  ;
	}
	

#-------------------------------------------------------------------------
# handle node triggers
#-------------------------------------------------------------------------
my (%triggered_nodes, @triggered_nodes) ;

my $trigger_rules_displayed = exists $trigger_rules{$load_package} ;
my $trigger_rules = ( $trigger_rules{$load_package} //= [PBS::Triggers::GetTriggerRules($load_package)] ) ;
my $number_of_trigger_rules = scalar(@{$trigger_rules}) ;

PrintInfo("Trigger: rules: $number_of_trigger_rules\n") 
	if !$trigger_rules_displayed && $number_of_trigger_rules && defined $pbs_config->{DEBUG_DISPLAY_TRIGGER_RULES} ;

for my $dependency (@dependencies)
	{
	use constant TRIGGERED_NODE_NAME  => 0 ;
	use constant TRIGGERING_NODE_NAME => 1 ;
	use constant TRIGGER_INFO         => 2 ;
	use constant TRIGGER_INFO_NAME    => 3 ;
	
	unless('HASH' eq ref $dependency)
		{
		PrintError \$dependency, 'Trigger: invalid dependency', MAX_DEPTH => 3 ;

		use Carp ;
		confess  ;
		}
	
	my $dependency_name = $dependency->{NAME} ;
	
	for my $trigger_rule (@{$trigger_rules})
		{
		my ($match, $triggered_node_name) = $trigger_rule->{DEPENDER}($dependency_name) ;

		if($match)
			{
			my $trigger_info_name =  $trigger_rule->{NAME} ;
			my $trigger_info =  $trigger_info_name . $trigger_rule->{ORIGIN} ;
								
			my $current_trigger_message = '' ;
			
			next if($triggered_node_name eq $node_name) ;
			
			if(exists $inserted_nodes->{$triggered_node_name})
				{
				$current_trigger_message = "${indent}Trigger: ignoring '$triggered_node_name' from '$trigger_info'"
								. ", trigger: '$dependency_name', was already in the graph.\n" ;
				}
			else
				{
				$current_trigger_message = "${indent}Trigger: adding '$triggered_node_name' from '$trigger_info'"
								. ", trigger: '$dependency_name'.\n" ;
								
				if(exists $triggered_nodes{$triggered_node_name})
					{
					$current_trigger_message .= "${indent}Trigger: ignoring duplicate '$triggered_node_name' from  "
									. "'$triggered_nodes{$triggered_node_name}[TRIGGER_INFO]'"
									. ", was added by trigger: '$triggered_nodes{$triggered_node_name}[TRIGGERING_NODE_NAME]'.\n"
					}
				else
					{
					$triggered_nodes{$triggered_node_name} = [$triggered_node_name, $dependency_name, $trigger_info, $trigger_info_name] ;
					push @triggered_nodes, $triggered_nodes{$triggered_node_name} ;
					}
				}
				
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} || $pbs_config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES})
				{
				PrintInfo($current_trigger_message)  ;
				}
			}
		}
	}
	
#-------------------------------------------------------------------------
# insert triggered nodes
#-------------------------------------------------------------------------
for my $triggered_node_data (@triggered_nodes)
	{
	my $triggered_node_name  = $triggered_node_data->[TRIGGERED_NODE_NAME] ;
	my $triggering_node_name = $triggered_node_data->[TRIGGERING_NODE_NAME] ;
	my $rule_info            = $triggered_node_data->[TRIGGER_INFO],
	my $rule_name            = $triggered_node_data->[TRIGGER_INFO_NAME],
	my $rule_line            = '',
	
	my $time = Time::HiRes::time() ;
	
	my %triggered_node_tree ;
	
	%triggered_node_tree = 
		(
		__NAME               => $triggered_node_name,
		__DEPENDENCY_TO      => {PBS => 'Perl Build System'},
		__INSERTED_AT        => {
					PBSFILE_CHAIN          => $pbsfile_chain,
					INSERTION_FILE         => $Pbsfile,
					INSERTION_PACKAGE      => $package_alias,
					INSERTION_LOAD_PACKAGE => $load_package,
					INSERTION_RULE         => $rule_info,
					INSERTION_RULE_NAME    => $rule_name,
					INSERTION_RULE_LINE    => $rule_line,
					INSERTION_TIME         => $time,
					INSERTING_NODE         => $triggering_node_name,
					},
		__CONFIG           => $config,
		__PACKAGE          => $package_alias,
		__LOAD_PACKAGE     => $load_package,
		__PBS_CONFIG       => $pbs_config,
		__TRIGGER_INSERTED => $triggering_node_name,
		__MATCHING_RULES   => [],
		) ;
		
	$inserted_nodes->{$triggered_node_name} = \%triggered_node_tree ;
	
	CreateDependencyTree
		(
		$pbsfile_chain,
		$Pbsfile,
		$package_alias,
		$load_package,
		$pbs_config,
		\%triggered_node_tree,
		$config,
		$inserted_nodes,
		$dependency_rules,
		) ;
	}
# handle node triggers finished

for my $dependency (@dependencies)
	{
	my $dependency_name = $dependency->{NAME} ;
	my $rule_index      = $dependency->{RULE_INDEX} ;
	
	$has_dependencies++ ;
	
	# remember which rule inserted which dependency
	push @{$dependency_rules{$dependency_name}}, [$rule_index, @{$dependency_rules->[$rule_index]}{qw/NAME/}] ;
	
	if(exists $inserted_nodes->{$dependency_name})
		{
		LinkNode
			(
			$pbs_config, $dependency_name, $tree, $inserted_nodes, $Pbsfile, $config,
			$dependency_rules, $rule_index,
			$parent_matching_rules, \@node_matching_rules
			) ;
		}
	else
		{
		# a new node is born
		my $rule_name = $dependency_rules->[$rule_index]{NAME} ;
		my $rule_file = $dependency_rules->[$rule_index]{FILE} ;
		my $rule_line = $dependency_rules->[$rule_index]{LINE} ;
		my $rule_info = $rule_name . ':' . $rule_file . ':' . $rule_line ;

		my $time = Time::HiRes::time() ;
		
		#DEBUG
		my %debug_data ;
		if($PBS::Debug::debug_enabled)
			{
			%debug_data = 
				(
				TYPE           => 'INSERT',
				PARENT_NAME    => $node_name,
				NODE_NAME      => $dependency_name,
				PACKAGE_NAME   => $package_alias,
				PBSFILE        => $Pbsfile,
				TREE           => $tree,
				INSERTED_FILES => $inserted_nodes,
				CONFIG         => $config,
				) ;
			
			$DB::single = 1 if(PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1)) ;
			}
		
		$tree->{$dependency_name}                     = {} ;
		$tree->{$dependency_name}{__MATCHING_RULES}   = [] ;
		$tree->{$dependency_name}{__CONFIG}           = $config ;
		$tree->{$dependency_name}{__NAME}             = $dependency_name ;
		$tree->{$dependency_name}{__USER_ATTRIBUTE}   = $dependency->{USER_ATTRIBUTE} if exists $dependency->{USER_ATTRIBUTE} ;
		
		$tree->{$dependency_name}{__PACKAGE}          = $package_alias ;
		$tree->{$dependency_name}{__LOAD_PACKAGE}     = $load_package ;
		$tree->{$dependency_name}{__PBS_CONFIG}       = $pbs_config ;
		
		$tree->{$dependency_name}{__INSERTED_AT}      = {
								PBSFILE_CHAIN              => $pbsfile_chain,
								INSERTION_FILE             => $Pbsfile,
								INSERTION_PACKAGE          => $package_alias,
								INSERTION_LOAD_PACKAGE     => $load_package,
								INSERTION_RULE_DEFINITION  => $dependency_rules->[$rule_index],
								INSERTION_RULE             => $rule_info,
								INSERTION_RULE_NAME        => $rule_name,
								INSERTION_RULE_FILE        => $rule_file,
								INSERTION_RULE_LINE        => $rule_line,
								INSERTION_TIME             => $time,
								INSERTING_NODE             => $tree->{__NAME},
								} ;
								
		$inserted_nodes->{$dependency_name} = $tree->{$dependency_name} ;
			
		$nodes_per_pbs_run{$load_package}++ if DependencyIsSource($tree, $dependency_name, $inserted_nodes) ; 

		#DEBUG
		$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1) ;
		}
	}
	
if(@has_matching_non_subpbs_rules)
	{
	if(@sub_pbs)
		{
		PrintError DumpTree
			{
			AddRule => \@has_matching_non_subpbs_rules,
			AddSubpbsRule => \@sub_pbs,
			},
			"Depend: '$node_name' Error: found rules and subpbs rules, Pbsfile: $Pbsfile" ;
			
		die "\n" ;
		}
		
	# a node can be inserted from different pbsfile, still the result should be the same
	# if the rules applied to the node are identical, only remember the pbsfile with matching rules
	$tree->{__DEPENDING_PBSFILE} = PBS::Digest::GetFileMD5($Pbsfile) ;
	$tree->{__LOAD_PACKAGE} = $load_package;
	
	# order so dependencies that do not match subpbs are depended first
	my (@non_matching, @non_subpbs_dependencies, @subpbs_dependencies) ;

	my $sort_tree                    = {} ;
	$sort_tree->{__CONFIG}           = $config ;
	$sort_tree->{__PACKAGE}          = $package_alias ;
	$sort_tree->{__LOAD_PACKAGE}     = $load_package ;
	$sort_tree->{__PBS_CONFIG}       = $pbs_config ;
			
	for my $dependency (map {$_->{NAME}} @dependencies)
		{
		if (DependencyIsSource($tree, $dependency, $inserted_nodes))
			{
			push @non_subpbs_dependencies, $dependency ;
			next ;
			}

		my $matched = 0 ;

		$sort_tree->{__NAME} = $dependency ;

		# decide in  which order dependencies will be depended 
		for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
			{
			my $rule = $dependency_rules->[$rule_index] ;
			my $depender  = $rule->{DEPENDER} ;

			# skip rule if it depends on another rule
			$rule->{STATS}{CALLS}++ ;

			my ($found_before, @not_matched) = (0) ;
			for my $before ( @{ $rule->{BEFORE} // [] })
				{
				if (exists $parent_matching_rules->{$before} || any { $_ eq $before } @node_matching_rules)
					{
					$found_before++ ;
					}
				else
					{
					push @not_matched, $before ;
					}
				}

			if((! $found_before) && @not_matched)
				{
				#PrintDebug "${indent}skipping rule '$rule->{NAME}' waiting for: '" . join(", '", @not_matched) . "'\n" ;
				$rule->{STATS}{SKIPPED}++ ;
				next ;
				}

			local $sort_tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX} = 0 ; # temporarily disable message
			my ($dependency_result) = $depender->($dependency, $config, $sort_tree, $inserted_nodes, $rule) ;

			my ($triggered, @dependencies ) = @$dependency_result ;
			
			if($triggered)
				{
				if(@dependencies && 'HASH' eq ref $dependencies[0])
					{
					push @subpbs_dependencies, $dependency ;
					}
				else
					{
					push @non_subpbs_dependencies, $dependency ;
					}

				$matched++ ;
				last ;
				}
			}
		
		push @non_matching, $dependency unless $matched ;
		}

	$rule_time = tv_interval($t0_rules, [gettimeofday]) ;

	for my $dependency (@non_matching, @non_subpbs_dependencies, @subpbs_dependencies)
		{
		# keep parent relationship
		my $key_name = $node_name . ': ' ;
		
		for my $rule (@{$dependency_rules{$dependency}})
			{
			$key_name .= "rule: " . join(':', @$rule) . " "  ;
			}
		
		$tree->{$dependency}{__DEPENDENCY_TO}{$key_name} = $tree->{__DEPENDENCY_TO} ;
		
		# show some pertinent depend information
		if
			(
			$tree->{$dependency}{__INSERTED_AT}{INSERTION_FILE} eq $Pbsfile
			&& defined $tree->{$dependency}{__DEPENDED_AT}
			&& $tree->{$dependency}{__DEPENDED_AT} ne $Pbsfile
			)
			{

			my @depending_rules ;

			for my $matching_rule (@{$tree->{$dependency}{__MATCHING_RULES}})
				{
				my $index = $matching_rule->{RULE}{INDEX} ;
				my $rule = $matching_rule->{RULE}{DEFINITIONS}[$index] ;
			
				push @depending_rules, "'$index:$rule->{NAME}:$rule->{LINE}'" ;
				}

			my $depending_rules = join ', ', @depending_rules ;

			PrintWarning
				(
				  "Depend: '$node_name' has dependency '$dependency' which was inserted at rule: "
				. "$tree->{$dependency}{__INSERTED_AT}{INSERTION_RULE} "
				. " [Pbsfile: $tree->{$dependency}{__INSERTED_AT}{INSERTION_FILE}]"
				. " but has been depended in another pbsfile: '$tree->{$dependency}{__DEPENDED_AT}' by $depending_rules\n"
				) ;
			
			my $ignored_rules ='' ;
			
			for(my $matching_rule_index = 0 ; $matching_rule_index < @$dependency_rules ; $matching_rule_index++)
				{
				local $tree->{$dependency}{DEBUG_DISPLAY_DEPENDENCY_REGEX} = 0 ; # temporarily disable message

				my $rule = $dependency_rules->[$matching_rule_index] ;

				my ($dependency_result) = $rule->{DEPENDER}->($dependency, $config, $tree->{$dependency}, $inserted_nodes, $rule) ;

				$ignored_rules .= "\t$matching_rule_index:$rule->{NAME}$rule->{ORIGIN}\n" if($dependency_result->[0]) ;
				}
				
			PrintWarning("Depend: ignoring local matching rules from '$Pbsfile':\n$ignored_rules") if $ignored_rules ne '' ;
			}
	
		if (! exists $tree->{$dependency}{__DEPENDED} && ! DependencyIsSource($tree, $dependency, $inserted_nodes) ) 
			{
			my %sum_matching_rules = %{$parent_matching_rules} ;
			push @{$sum_matching_rules{$_}}, $node_name for (@node_matching_rules) ;

			# rule run once
			my @sub_dependency_rules = $pbs_config->{RULE_RUN_ONCE}
							? grep { $_->{MULTI} || ! exists $_->{MATCHED} } @$dependency_rules
							: () ;

			my $local_time = 
				CreateDependencyTree
				(
				$pbsfile_chain,
				$Pbsfile,
				$package_alias,
				$load_package,
				$pbs_config,
				$tree->{$dependency},
				$config,
				$inserted_nodes,
				$pbs_config->{RULE_RUN_ONCE} ? \@sub_dependency_rules : $dependency_rules,
				\%sum_matching_rules,
				) ;

			$rule_time += $local_time ;
			}
		}
	}
elsif(@sub_pbs)
	{
	if(@sub_pbs != 1)
		{
		PrintError "Depend: in pbsfile : $Pbsfile, $node_name has multiple subpbs defined:\n" ;
		PrintError(DumpTree(\@sub_pbs, "Sub Pbs:")) ;
		Carp::croak  ;
		}

	$tree->{__MATCHED_SUBPBS}++ ;
	my $sub_pbs_hash = $sub_pbs[0]{SUBPBS} ;

	my $unlocated_sub_pbs_name = my $sub_pbs_name = $sub_pbs_hash->{PBSFILE} ;
	my $sub_pbs_package = $sub_pbs_hash->{PACKAGE} ;
	
	my $alias_message = '' ;
	$alias_message = "aliased as '$sub_pbs_hash->{ALIAS}'" if(defined $sub_pbs_hash->{ALIAS}) ;
	
	$sub_pbs_name = LocatePbsfile($pbs_config, $Pbsfile, $sub_pbs_name, $sub_pbs[0]{RULE}) ;
	$sub_pbs_hash->{PBSFILE_LOCATED} = $sub_pbs_name ;
	
	#-------------------------------------------------------------
	# run subpbs
	#-------------------------------------------------------------
	my $node_is_trigger_inserted = exists $tree->{__TRIGGER_INSERTED} ;
	PrintInfo3("${indent}Subpbs: trigger_inserted '$node_name'\n") if $node_is_trigger_inserted ; 

	# temporarily eliminate ourself from the existing nodes list
	# this means that any extra information in the node will not be available to subpbs, eg: we display the trigger insert info before the subps
	delete $inserted_nodes->{$node_name} ;
	
	my $tree_name = "sub_pbs$sub_pbs_name" ;
	$tree_name =~ s~^\./~_~ ;
	$tree_name =~ s~/~_~g ;
	
	PrintInfo(DumpTree($sub_pbs_hash, "subpbs:")) if defined $pbs_config->{DISPLAY_SUB_PBS_DEFINITION} ;
		
	# Synchronize with elements from the subpbs definition, specially build and source dirs 
	# we override elements
	my $sub_pbs_config = {%{$tree->{__PBS_CONFIG}}, %$sub_pbs_hash, SUBPBS_HASH => $sub_pbs[0]{RULE}} ;
	$sub_pbs_config->{PARENT_PACKAGE} = $package_alias ;
	$sub_pbs_config->{PBS_COMMAND} ||= DEPEND_ONLY ;
	
	my $sub_node_name = $node_name ;
	$sub_node_name    = $sub_pbs_hash->{ALIAS} if(defined $sub_pbs_hash->{ALIAS}) ;
	
	my $sub_config = PBS::Config::get_subps_configuration
				(
				$sub_pbs_hash,
				\@sub_pbs,
				$tree,
				$sub_node_name,
				$pbs_config,
				$load_package,
				) ;
	
	PrintInfo(DumpTree($sub_config, "subpbs config:")) if defined $pbs_config->{DISPLAY_SUB_PBS_CONFIG} ;

	my $already_inserted_nodes = $inserted_nodes ;
	$already_inserted_nodes    = {} if(defined $sub_pbs_hash->{LOCAL_NODES}) ;
	
	my %inserted_nodes_snapshot ;
	%inserted_nodes_snapshot = %$inserted_nodes if $node_is_trigger_inserted ;

	$rule_time = tv_interval($t0_rules, [gettimeofday]) ;

	my ($build_result, $build_message, $sub_tree, $inserted_nodes, $sub_pbs_load_package)
		= PBS::PBS::Pbs
			(
			[@$pbsfile_chain, $sub_pbs_name],
			"supbs_${Pbsfile}",
			$sub_pbs_name,
			$load_package,
			$sub_pbs_config,
			$sub_config,
			[$sub_node_name],
			$already_inserted_nodes,
			$tree_name,
			$sub_pbs_config->{PBS_COMMAND},
			) ;
		
	# mark all the nodes from the subpbs run as trigger_inserted if node is trigger inserted
	if ($node_is_trigger_inserted)
		{
		for my $name (keys %$already_inserted_nodes)
			{
			unless (exists $inserted_nodes_snapshot{$name})
				{
				$already_inserted_nodes->{$name}{__TRIGGER_INSERTED} = $tree->{__TRIGGER_INSERTED}
					unless exists $already_inserted_nodes->{$name}{__TRIGGER_INSERTED} ;
				}
			}
		} 

	$sub_tree->{$sub_node_name}{__TRIGGER_INSERTED} = $tree->{__TRIGGER_INSERTED} if $node_is_trigger_inserted ;
	
	# keep this node insertion info
	$sub_tree->{$sub_node_name}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} = $tree->{__INSERTED_AT} ;
	
	# keep parent relationship
	for my $dependency_to_key (keys %{$tree->{__DEPENDENCY_TO}})
		{
		$sub_tree->{$sub_node_name}{__DEPENDENCY_TO}{$dependency_to_key} = $tree->{__DEPENDENCY_TO}{$dependency_to_key};
		}
		
	# copy the data generated by subpbs
	for my $new_key (keys %{$sub_tree->{$sub_node_name}})
		{
		# keep attributes defined from the current Pbs
		next if $new_key =~ /__NAME/ ;
		next if $new_key =~ /__USER_ATTRIBUTE/ ;
		next if $new_key =~ /__LINKED/ ;
		
		$tree->{$new_key} = $sub_tree->{$sub_node_name}{$new_key} ;
		}
		
	# make ourself the real node again
	$inserted_nodes->{$node_name} = $tree ;
	}
else
	{
	# no subpbs and no non-subpbs
	if 
		(
		   $node_name_matches_ddrr
		&& $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES}
		&& $node_name !~ /^__/
		&& NodeIsGenerated($tree)
		)
		{
		my $no_short_name = $pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH} ;
		my $glyph = '' eq $pbs_config->{TARGET_PATH}
				? "./"
				: $pbs_config->{SHORT_DEPENDENCY_PATH_STRING} ;

		my $short_node_name = $node_name ;
		$short_node_name =~ s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $no_short_name ;

		my $inserted_at = exists $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
					? $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE}
					: $tree->{__INSERTED_AT}{INSERTION_RULE} ;

		$inserted_at = GetRunRelativePath($pbs_config, $inserted_at) ;
		
		PrintInfo3 "$PBS::Output::indentation'$short_node_name'"
				. _WARNING_(" no matching rules")
				. _INFO2_(", inserted at: $inserted_at'\n") ;
		}

	$rule_time = tv_interval($t0_rules, [gettimeofday]) ;
	}

# section below is disabled
# we could generate the node log info after each node depend but do it after the check step
# that adds the check status for the dependencies
# the best solution would be to add information incrementally, generate the node log info during depend (rules  inserting dependencies)
# and adding the check information later
# alternatively we could check the nodes immediately but that wouldn't work with late depend that delays the insertion of dependencies
#	we would have a wrong status for the dependencies
if(0 && @{$pbs_config->{LOG_NODE_INFO}} && $node_name !~ /^__/)
	{
	for my $node_info_regex (@{$pbs_config->{LOG_NODE_INFO}})
		{
		if($node_name =~ /$node_info_regex/)
			{
			my (undef, $node_info_file) =
				PBS::Build::ForkedNodeBuilder::GetLogFileNames($inserted_nodes->{$node_name}) ;

			my ($node_info, $log_node_info) = 
				PBS::Information::GetNodeInformation($inserted_nodes->{$node_name}, $pbs_config, 1, $inserted_nodes) ;
				
			open(my $fh, '>', $node_info_file) or die ERROR "Error: --lni can't create '$node_info_file' for '$node_name'.\n" ;
			print $fh $log_node_info ;
			
			last ;
			}
		}
	}

if($tree->{__IMMEDIATE_BUILD}  && ! exists $tree->{__BUILD_DONE})
	{
	PrintInfo2("Depend: -- Immediate build of node $node_name --\n") ;
	my(@build_sequence, %trigged_files) ;
	
	my $nodes_checker ;
	PBS::Check::CheckDependencyTree
		(
		$tree,
		0, # node level
		$inserted_nodes,
		$pbs_config,
		$config,
		$nodes_checker,
		undef, # single node checker
		\@build_sequence,
		\%trigged_files,
		) ;
		
	RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $tree, $inserted_nodes, \@build_sequence, $tree) ;
	
	if($pbs_config->{DO_BUILD})
		{
		my ($build_result, $build_message) = PBS::Build::BuildSequence
							(
							$pbs_config,
							\@build_sequence,
							$inserted_nodes,
							) ;
			
		if($build_result == BUILD_SUCCESS)
			{
			#~ PrintInfo2("Depend: -- Immediate build of node '$node_name' Done --\n") ;
			}
		else
			{
			PrintError("Depend: -- Immediate build of node '$node_name' Failed --\n") ;
			die "Depend: IMMEDIATE_BUILD FAILED\n" ;
			}
		}
	else
		{
		PrintInfo2("Depend: -- Immediate build of node '$node_name' Skipped --\n") ;
		}
	}
	
#DEBUG
if($PBS::Debug::debug_enabled)
	{
	my %debug_data = 
		(
		TYPE           => 'TREE',
		PACKAGE_NAME   => $package_alias,
		PBSFILE        => $Pbsfile,
		TREE           => $tree,
		INSERTED_FILES => $inserted_nodes,
		) ;
		
	$DB::single = 1 if (PBS::Debug::CheckBreakpoint($pbs_config, %debug_data)) ;
	}

return $rule_time ;
}

sub LinkNode
{
my ($pbs_config, $dependency_name, $tree, $inserted_nodes, $Pbsfile, $config, $dependency_rules, $rule_index, $parent_matching_rules, $node_matching_rules) = @_ ;

RunPluginSubs($pbs_config, 'CheckLinkedNode', @_) ;

# link node 
$tree->{$dependency_name} = $inserted_nodes->{$dependency_name} ;
$tree->{$dependency_name}{__LINKED}++ ;

my $dependency = $inserted_nodes->{$dependency_name} ;

return if $pbs_config->{NO_WARP_NODE_LINK_INFO} && exists $dependency->{__WARP_NODE} ;

my $dependency_is_source = DependencyIsSource($tree, $dependency_name, $inserted_nodes) ;

my $display_linked_node_info = $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && (! $pbs_config->{NO_LINK_INFO}) ;
my $indent = $PBS::Output::indentation ;

my $rule_name = $dependency_rules->[$rule_index]{NAME} ;
my $rule_info = $rule_name . $dependency_rules->[$rule_index]{ORIGIN} ;

my ($local_node, $error_linking, $local_rule_info) = (0, 0, '') ;

if($dependency->{__INSERTED_AT}{INSERTION_FILE} eq $Pbsfile)
	{
	$local_node++ ;
	return if $pbs_config->{NO_LOCAL_LINK_INFO} ;
	}
else
	{
	$error_linking++ if $pbs_config->{NO_EXTERNAL_LINK} ;
	
	if (exists $dependency->{__DEPENDED} && ! $pbs_config->{NO_LOCAL_MATCHING_RULES_INFO})
		{
		for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
			{
			local $dependency->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX} = 0 ; # temporarily disable message

			my $rule = $dependency_rules->[$rule_index] ;

			# skip rule if it depends on another rule
			$rule->{STATS}{CALLS}++ ;

			my ($found_before, @not_matched) = (0) ;
			for my $before ( @{ $rule->{BEFORE} // [] })
				{
				if (exists $parent_matching_rules->{$before} || any { $_ eq $before } @$node_matching_rules)
					{
					$found_before++ ;
					}
				else
					{
					push @not_matched, $before ;
					}
				}

			if((! $found_before) && @not_matched)
				{
				#PrintDebug "${indent}Linking skipping rule '$rule->{NAME}' waiting for: '" . join(", '", @not_matched) . "'\n" ;
				$rule->{STATS}{SKIPPED}++ ;
				next ;
				}

			my ($dependency_result) = $rule->{DEPENDER}->($dependency_name, $config, $dependency, $inserted_nodes, $rule) ;

			if($dependency_result->[0])
				{
				$local_rule_info .= WARNING "${indent}${indent}ignoring local rule" ;

				$local_rule_info .= _INFO2_ ", $rule_index:"
							. GetRunRelativePath
								(
								$pbs_config,
								$dependency_rules->[$rule_index]{NAME} . ':'
								. $dependency_rules->[$rule_index]{FILE} . ':'
								. $dependency_rules->[$rule_index]{LINE}
								)
							. "\n" ;

				$display_linked_node_info++ ;
				} 
			}
		}
	}

my ($linked_node_info, @link_type) ;
#  ⁻ · ⁽ ⁾ ⁺ ⁻ ⁼
#ᴬ ᴮ ᶜ ᴰ ᴱ ᶠ ᴳ ᴴ ᴵ ᴶ ᴷ ᴸ ᴹ ᴺ ᴼ ᴾ ᵠ ᴿ ˢ ᵀ ᵁ ⱽ ᵂ ˣ ʸ ᶻ > 
#ᵃ ᵇ ᶜ ᵈ ᵉ ᶠ ᵍ ʰ ⁱ ʲ ᵏ ˡ ᵐ ⁿ ᵒ ᵖ ᵠ ʳ ˢ ᵗ ᵘ ᵛ ʷ ˣ ʸ ᶻ 
# • ■ ○ dkmdklf
# ☘ ♾ ♿ ⚒ ⚓ ⚔ ⚕ ⚖ ⚗ ⚘ ⚙ ⚚ ⚛ ⚜ ☀ 

push @link_type, $local_node ? 'ᴸᴼᶜᴬᴸ ᴺᴼᴰᴱ' : 'ᴰᴵᶠᶠᴱᴿᴱᴺᵀ ᴾᴮˢᶠᴵᴸᴱ' ;
push @link_type, 'trigger inserted'  if exists $dependency->{__TRIGGER_INSERTED} ;

if($dependency_is_source)
	{
	$linked_node_info = WARNING "${indent}'$dependency_name' " . _INFO_("ᴸᴵᴺᴷᴵᴺᴳ");

	push @link_type, 'ˢᴼᵁᴿᶜᵉ' ;

	push @link_type, 'ᴰᴱᴾᴱᴺᴰᴱᴰ' if exists $dependency->{__DEPENDED} ;
	push @link_type, 'ᴴᴬˢ ᴰᴱᴾᴱᴺᴰᴱᴺᶜᴵᴱˢ' if scalar ( grep { ! /^__/ } keys %$dependency ) ;
	}
else
	{
	$linked_node_info = INFO3 "${indent}'$dependency_name' " . _INFO_("ᴸᴵᴺᴷᴵᴺᴳ");

	push @link_type, exists $dependency->{__DEPENDED}
				? scalar ( grep { ! /^__/ } keys %$dependency )
					? ()
					:'ᴺᴼ ᴰᴱᴾᴱᴺᴰᴱᴺᶜᴵᴱˢ' 
				: _WARNING3_('ᴺᴼᵀ ᴰᴱᴾᴱᴺᴰᴱᴰ') . GetColor('info_2') ;
	}

$linked_node_info .= _INFO2_ ' ⁽' . join('· ', @link_type) . '⁾' ;

if ($error_linking || $pbs_config->{DISPLAY_LINK_MATCHING_RULE} || $pbs_config->{DISPLAY_DEPENDENCY_INSERTION_RULE})
	{
	if ($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
		{
		if ($pbs_config->{DEBUG_TRACE_PBS_STACK})
			{
			my @traces = GetRuleTrace($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE_DEFINITION}) ;

			if (@traces)
				{
				$linked_node_info .= INFO2 "\n${indent}${indent}inserted at rule '$dependency->{__INSERTED_AT}{INSERTION_RULE_NAME}':" ;

				for my $trace (GetRuleTrace($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE_DEFINITION}, 1))
					{
					$linked_node_info .= INFO2 "\n${indent}${indent}${indent}$trace"
					}
				}
			else
				{
				my $insertion_rule = GetRunRelativePath($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE}) ;
				$linked_node_info .= INFO2 "\n${indent}${indent}inserted at: $insertion_rule"
				}
			}
		else
			{
 			my $insertion_rule = GetRunRelativePath($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE}) ;
			$linked_node_info .= INFO2 "\n${indent}${indent}inserted at: $insertion_rule"
			}
		}
	else
		{
		if ($pbs_config->{DEBUG_TRACE_PBS_STACK})
			{
			my @traces = GetRuleTrace($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE_DEFINITION}) ;

			if (@traces)
				{
				$linked_node_info .= _INFO2_ ", inserted at rule '$dependency->{__INSERTED_AT}{INSERTION_RULE_NAME}'" ;

				for my $trace (GetRuleTrace($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE_DEFINITION}, 1))
					{
					$linked_node_info .= _INFO2_ ", trace: $trace" ;
					}
				}
			else
				{
 				my $insertion_rule = GetRunRelativePath($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE}) ;
				$linked_node_info .= _INFO2_ ", inserted at: $insertion_rule" ;
				}
			}
		else
			{
 			my $insertion_rule = GetRunRelativePath($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE}) ;
			$linked_node_info .= _INFO2_ ", inserted at: $insertion_rule" ;
			}
		}
	}

$linked_node_info .= "\n" ;

PrintNoColor $linked_node_info . $local_rule_info if $display_linked_node_info || $error_linking ;

PrintError "Depend: error linking to non local node\n" if $error_linking ;
die "\n" if $error_linking ;
}

#-------------------------------------------------------------------------------

sub LocatePbsfile
{
my ($pbs_config, $Pbsfile, $sub_pbs_name, $rule) = @_ ;

my $info = $pbs_config->{ADD_ORIGIN} ? "rule '$rule->{NAME}' at '$rule->{FILE}\:$rule->{LINE}'" : '' ;

my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;
my $sub_pbs_name_stem ;

if(file_name_is_absolute($sub_pbs_name))
	{
	PrintWarning "Using absolute subpbs: '$sub_pbs_name' $info.\n" ;
	}
else
	{
	my ($basename, $path, $ext) = File::Basename::fileparse($Pbsfile, ('\..*')) ;
	
	my $found_pbsfile ;
	for my $source_directory (@$source_directories, $path)
		{
		my $searched_pbsfile = PBS::PBSConfig::CollapsePath("$source_directory/$sub_pbs_name") ;
		
		if(-e $searched_pbsfile)
			{
			if($found_pbsfile)
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Locate: ignoring pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Locate: located pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
					}
					
				$found_pbsfile = $searched_pbsfile ;
				
				last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
				}
			}
		else
			{
			if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
				{
				PrintInfo "Locate: couldn't find pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
				}
			}
		}
		
	my $sub_pbs_name_stem ;
	$found_pbsfile ||= "$path$sub_pbs_name" ;
	
	#check if we can find it somewhere else in the source directories
	for my $source_directory (@$source_directories)
		{
		my $flag = '' ;
		$flag = '(?i)' if $^O eq 'MSWin32' ;
		
		if($found_pbsfile =~ /$flag^$source_directory(.*)/)
			{
			$sub_pbs_name_stem = $1
			}
		}
		
	my $relocated_subpbs ;
	if(defined $sub_pbs_name_stem)
		{
		if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
			{
			PrintInfo "Locate: found stem '$sub_pbs_name_stem'.\n" ;
			}
			
		for my $source_directory (@$source_directories)
			{
			my $relocated_from_stem = PBS::PBSConfig::CollapsePath("$source_directory/$sub_pbs_name_stem") ;
			
			if(-e $relocated_from_stem)
				{
				unless($relocated_subpbs)
					{
					$relocated_subpbs = $relocated_from_stem  ;
					
					if($relocated_from_stem ne $found_pbsfile)
						{
						PrintWarning2("Locate: relocated '$sub_pbs_name_stem' in '$source_directory' $info.\n") ;
						}
					else
						{
						if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
							{
							PrintInfo "Locate: keeping '$sub_pbs_name_stem' from '$source_directory' $info.\n" ;
							}
						}
						
					last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
					}
				else
					{
					if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
						{
						PrintInfo "Locate: ignoring relocation of '$sub_pbs_name_stem' in '$source_directory' $info.\n" ;
						}
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Locate: couldn't relocate '$sub_pbs_name_stem' in '$source_directory' $info.\n" ;
					}
				}
			}
		}
		
	$sub_pbs_name = $relocated_subpbs || $found_pbsfile || $sub_pbs_name;
	}

return($sub_pbs_name) ;
}

#-------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Depend  -

=head1 SYNOPSIS

  use PBS::Depend ;
  my $tree = {...} ;
  CreateDependencyTree(...) ;

=head1 DESCRIPTION

Given a node and a set of rules, B<CreateDependencyTree> will recursively build the entire dependency tree, inserting 
