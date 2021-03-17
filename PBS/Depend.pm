
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
use List::Util qw(any max) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CreateDependencyTree) ;
our $VERSION = '0.08' ;

use PBS::Depend::Forked ;
use PBS::PBS ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Triggers ;
use PBS::PostBuild ;
use PBS::Plugin;
use PBS::Information ;
use PBS::Digest ;
use PBS::Node ;
use PBS::Net ;

#-------------------------------------------------------------------------------

my %nodes_per_pbs_run ;
sub GetNodesPerPbsRun { \%nodes_per_pbs_run  } 

#-------------------------------------------------------------------------------

my @unicode_numbers = qw / ⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ /;
push @unicode_numbers, ('+') x 100 ; 

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

my (@node_matching_rules, @node_dependencies) ;
my $indent = $PBS::Output::indentation ;
my $node_name = $tree->{__NAME} ;

my $node_name_matches_ddrr = any { $node_name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}} ;
$node_name_matches_ddrr = 0 if any { $node_name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX_NOT}} ;

my %dependency_rules ; # keep a list of  which rules generated which dependencies
my $has_dependencies = 0 ;
my @has_matching_non_subpbs_rules ;
my @subpbses ; # list of subpbs matching this node

PrintInfo2("Rule: target:" . _INFO3_("'$node_name'") . _INFO2_(", rules: " . scalar(@{$dependency_rules}) . "\n"))
	if ($node_name !~ /^__/) && ($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX} || $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;

for my $post_build_command (PBS::PostBuild::GetPostBuildRules($load_package))
	{
	my ($match, $message) = $post_build_command->{DEPENDER}($node_name) ;

	if($match)
		{
		push @{$tree->{__POST_BUILD_COMMANDS}}, $post_build_command ;
		
		PrintInfo3 "$indent'" . GetRunRelativePath($pbs_config, $node_name) . "'"
			. _INFO_
				(
				", post build command: $post_build_command->{NAME}: "
				. GetRunRelativePath($pbs_config, $post_build_command->{FILE})
				. ":$post_build_command->{LINE}\n"
				)
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

	my $node_name_matches_ddrr = $node_name_matches_ddrr ;
	$node_name_matches_ddrr = 1 if any { $rule_name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_RULE_NAME}} ;
	$node_name_matches_ddrr = 0 if any { $rule_name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT}} ;

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

	my ($triggered, @dependencies) = $rule->{DEPENDER}->($node_name, $config, $tree, $inserted_nodes, $rule) ;
	
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
				},

			DEPENDENCIES => 'HASH' eq ref $dependencies[0]
						? [] 
						: \@dependencies, 
			} ;
		
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
			push @subpbses, 
				{
				SUBPBS => $dependencies[0],
				RULE   => $rule,
				} ;
			
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddrr)
				{
				my $short_node_name = GetTargetRelativePath($pbs_config, $node_name) ;

				my $subpbs_file = $rule->{TEXTUAL_DESCRIPTION}{PBSFILE} ;

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
										GetInsertionRule($tree),
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
					
				PBS::Rules::DisplayRuleTrace($pbs_config, $rule) if defined $pbs_config->{DEBUG_TRACE_PBS_STACK} ;
				}
				
			next ;
			}
		else
			{
			push @has_matching_non_subpbs_rules, "rule '$rule_name', file '$rule->{FILE}:$rule->{LINE}'" ;
			push @node_matching_rules, $rule_name ;
			}
		
		# check for node attributes
		@dependencies = map
				{
				if(('' eq ref $_) && (! /^__/))
					{
					if(/(.*)::(.*)$/)
						{
							# node user attribute
							{
							NAME => $1,
							RULE_INDEX => $rule_index,
							USER_ATTRIBUTE => $2,
							}
						}
					else
						{
							{
							NAME => $_,
							RULE_INDEX => $rule_index,
							}
						}
					}
				else
					{
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
					push @node_type, map { $_ eq 'TRIGGER_INSERTED' ? 'T' : $_ } ($type =~ s/^__//r) if exists $tree->{$type} ;
					}

				my $node_type = scalar(@node_type) ? ' [' . join(', ', @node_type) . ']' : '' ;
				
				my $rule_info =  $rule->{NAME}
						. (defined $pbs_config->{ADD_ORIGIN} 
							? $rule->{ORIGIN}
							: ':' . $rule->{FILE} . ':' . $rule->{LINE}) ;
				
				$rule_info = GetRunRelativePath($pbs_config, $rule_info, $pbs_config->{DISPLAY_DEPENDENCIES_FULL_PBSFILE}) ;

				my $rule_type = '' ;
				$rule_type .= '[B]'  if(defined $rule->{BUILDER}) ;
				$rule_type .= '[S]'  if(defined $rule->{NODE_SUBS}) ;
				$rule_type = " $rule_type" unless $rule_type eq '' ;

				my @dependency_names = map {$_->{NAME}} grep {'' eq ref $_->{NAME}} @dependencies ;
				
				my $forced_trigger = (any { $_->{NAME} =~ '__PBS_FORCE_TRIGGER' } @dependencies) ? ' FORCED_TRIGGER' : '' ;
				
				my $short_node_name = GetTargetRelativePath($pbs_config, $node_name) ;

				my $node_matches = $rules_matching > 1 
							? _INFO2_($unicode_numbers[$rules_matching])
							: $rule_type eq ''
								? ' '
								: ''  ;

				my $node_insertion_rule = $pbs_config->{DISPLAY_DEPENDENCY_INSERTION_RULE}
								? _INFO2_(
									", ⬂ "
									. GetRunRelativePath
										(
										$pbs_config,
										GetInsertionRule($tree) ,
										)
									. ' '
									)
								: '' ;

				# the subpbs root node have no insertion data we can use
				$node_insertion_rule = '' if $node_insertion_rule =~ /PBS:Subpbs/ ;

				my $node_matching_rule = $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE}
								? _INFO2_(" $rule_info$rule_type")
								: '' ;

				if(defined $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
					{
					$node_matching_rule = _INFO2_(',') . $node_matching_rule unless @dependency_names || $node_matching_rule eq '' ;
					PrintInfo3
						(
						$em->("$indent'$short_node_name'$node_matches${node_type}${forced_trigger}")
						. ( @dependency_names ? '' : _INFO2_" => ∅ " )
						. $node_matching_rule . $node_insertion_rule . "\n"
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
									my $r_name = GetTargetRelativePath($pbs_config, $_) ;
									my $cache = $pbs_config->{NODE_CACHE_INFORMATION}
											&& exists $inserted_nodes->{$_}
											&& exists $inserted_nodes->{$_}{__WARP_NODE}
												? _INFO2_ ('ᶜ')
												: '' ;

									DependencyIsSource($tree, $_, $inserted_nodes)
										? _WARNING_("'" . $em->($r_name) . $cache . _WARNING_("'"))
										: _INFO_("'" . $em->($r_name) . $cache. _INFO_("'"))
									} 
									@dependency_names
								)
							. "\n" ;
						}
					}
				else
					{
					$node_matching_rule = ',' . $node_matching_rule unless $node_matching_rule eq '' ;
					
					PrintNoColor 
						_INFO3_ "$indent'$short_node_name'${node_type}${forced_trigger}$node_matches"
					
						. (
							 @dependency_names
							?  _INFO_
								(
								' => '
								. join
									(
									' ',
									map 
										{
										my $r_name = GetTargetRelativePath($pbs_config, $_) ;
										my $cache = $pbs_config->{NODE_CACHE_INFORMATION}
												&& exists $inserted_nodes->{$_}
												&& exists $inserted_nodes->{$_}{__WARP_NODE}
													? _INFO2_ ('ᶜ')
													: '' ;

										DependencyIsSource($tree, $_, $inserted_nodes)
											? _WARNING_("'" . $em->($r_name) . $cache . _WARNING_("'"))
											: _INFO_("'" . $em->($r_name) . $cache. _INFO_("'"))
										} 
										@dependency_names
									)
								)
							: _INFO2_(" => ∅ ")
						),
						
						. _INFO2_ $node_matching_rule . $node_insertion_rule ;

					Say Info '' ;
					}
					
				PBS::Rules::DisplayRuleTrace($pbs_config, $rule) if defined $pbs_config->{DEBUG_TRACE_PBS_STACK} ;

				if($pbs_config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION})
					{
					PrintInfo "$indent${indent}'$rule->{NAME}' definition:\n" ;
					PrintWithContext
						(
						$pbs_config,
						$rule->{FILE},
						0, 0, 2, # blank, context before, context after
						$rule->{LINE}, 1,
						\&INFO,
						\&INFO2,
						0, "$indent$indent",
						1, # no file name
						) ;
					}
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
				PrintWarning "$indent${indent}warning: rule '$rule_name' matched '$node_name' and parent '$parent_matching_rules->{$rule_name}[0]'\n", 1 ;
				}

			if
				(
				@{$parent_matching_rules->{$rule_name}} >= $pbs_config->{RULE_RECURSION_WARNING}
				&& ! (@{$parent_matching_rules->{$rule_name}} % 5)
				)
				{
				PrintWarning "$indent${indent}warning: rule '$rule_name' matched '$node_name' and "
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
				PrintError "\nDepend: self referential rule\n"
						. "\trule: '$rule_info'\n"
						. "\tcycle: $node_name => $dependency_names\n" ;
				
				PbsDisplayErrorWithContext $pbs_config, $rule->{FILE}, $rule->{LINE} ;
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
		PrintColor 'no_match', "$PBS::Output::indentation$depender_message, $rule_info\n" if defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT} ;
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

if(@subpbses > 1)
	{
	PrintInfo3 _INFO3_("$indent'$node_name' ") . _ERROR_(scalar(@subpbses) . " matching subpbs rules.\n") ;

	for (@subpbses)
		{
		PrintWithContext
			(
			$pbs_config,
			$_->{RULE}{FILE},
			0, 0, 2, # blank, context before, context after
			$_->{RULE}{LINE}, 1,
			\&WARNING,
			\&INFO2,
			0, $indent,
			0, # show title
			1, # shorten name
			) ;

		PrintNoColor("\n") ;
		}

=pod
	# just the name and file:line
	my $max = max map { length $_->{RULE}{NAME} } @subpbses ;

	PrintError 
		sprintf
			(
			"$indent%-${max}s "
				. _INFO2_
					(
					"@ "
					. GetRunRelativePath($pbs_config, $_->{RULE}{FILE})
					. ":$_->{RULE}{LINE}\n"
					),
			$_->{RULE}{NAME}
			) for @subpbses ;

	# tree of subpbs rules
	PrintError(DumpTree \@subpbses, "Subpbs:", MAX_DEPTH => 4, DISPLAY_ADDRESS => 0) ;
=cut
	die _ERROR_("PBS: error: multiple matching subpbs rules") . "\n" ;
	}
	

#-------------------------------------------------------------------------
# handle node triggers
#-------------------------------------------------------------------------
my (%triggered_nodes, @triggered_nodes) ;

my $trigger_rules_displayed = exists $trigger_rules{$load_package} ;
my $trigger_rules = ( $trigger_rules{$load_package} //= [PBS::Triggers::GetTriggerRules($load_package)] ) ;
my $number_of_trigger_rules = scalar(@{$trigger_rules}) ;

PrintInfo2("${indent}trigger rules: $number_of_trigger_rules\n") 
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
			my $trigger_info =  $trigger_info_name . ':' . $trigger_rule->{FILE} . ':' . $trigger_rule->{LINE};
								
			next if($triggered_node_name eq $node_name) ;
			
			my $trigger_message = '' ;
			sub format_trigger_message
				{
				  INFO("${PBS::Output::indentation}Trigger:")
				. _INFO3_(" '$_[1]'")
				. _INFO_
					(
					" $_[2]"
					. ", triggered by: " . _INFO3_("'$_[3]'")
					. _INFO2_ (" @ '" . GetRunRelativePath($_[0], $_[4]) . "'\n")
					) 
				}

			if(exists $inserted_nodes->{$triggered_node_name})
				{
				$trigger_message = format_trigger_message $pbs_config,
							$triggered_node_name,
							'was already in the graph',
							$dependency_name,
							$trigger_info,
				}
			else
				{
				if(exists $triggered_nodes{$triggered_node_name})
					{
					$trigger_message = format_trigger_message $pbs_config,
								$triggered_node_name,
								'ignoring duplicate',
								$triggered_nodes{$triggered_node_name}[TRIGGERING_NODE_NAME],
								$triggered_nodes{$triggered_node_name}[TRIGGER_INFO]
					}
				else
					{
					$trigger_message = format_trigger_message $pbs_config,
								$triggered_node_name,
								'added',
								$dependency_name,
								$trigger_info ;

					$triggered_nodes{$triggered_node_name} = [$triggered_node_name, $dependency_name, $trigger_info, $trigger_info_name] ;
					push @triggered_nodes, $triggered_nodes{$triggered_node_name} ;
					}
				}
				
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} || $pbs_config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES})
				{
				PrintNoColor($trigger_message)  ;
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
		__TRIGGER_ROOT     => 1,
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
		$parent_matching_rules,
		) ;
	}
# handle node triggers finished

for my $dependency_definition (@dependencies)
	{
	my $dependency_name = $dependency_definition->{NAME} ;
	my $rule_index      = $dependency_definition->{RULE_INDEX} ;
	my $user_attribute  = $dependency_definition->{USER_ATTRIBUTE} ;
	my $rule            = $dependency_rules->[$rule_index] ;
	
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
		my $rule_name = $rule->{NAME} ;
		my $rule_file = $rule->{FILE} ;
		my $rule_line = $rule->{LINE} ;
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
		
		my $dependency = $inserted_nodes->{$dependency_name} = $tree->{$dependency_name} = {} ;

		$dependency->{__MATCHING_RULES}  = [] ;
		$dependency->{__CONFIG}          = $config ;
		$dependency->{__NAME}            = $dependency_name ;
		$dependency->{__USER_ATTRIBUTE}  = $user_attribute if defined $user_attribute ;
		
		$dependency->{__PACKAGE}         = $package_alias ;
		$dependency->{__LOAD_PACKAGE}    = $load_package ;
		$dependency->{__PBS_CONFIG}      = $pbs_config ;
		
		$dependency->{__INSERTED_AT} = {
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
						
		$dependency->{__TRIGGER_INSERTED} = $pbs_config->{ROOT_TRIGGER} if exists $pbs_config->{ROOT_TRIGGER} ;
								
		push @{$nodes_per_pbs_run{$load_package}}, "$dependency_name, rule: $rule_name" ; 

		#DEBUG
		$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1) ;
		}
	}
	
if(@has_matching_non_subpbs_rules)
	{
	if(@subpbses)
		{
		PrintError DumpTree
			{
			AddRule => \@has_matching_non_subpbs_rules,
			AddSubpbsRule => \@subpbses,
			},
			"Depend: '$node_name' Error: found rules and subpbs rules, Pbsfile: $Pbsfile" ;
			
		die "\n" ;
		}
		
	# a node can be inserted from different pbsfile, still the result should be the same
	# if the rules applied to the node are identical, only remember the pbsfile with matching rules
	$tree->{__DEPENDING_PBSFILE} = PBS::Digest::GetFileMD5($Pbsfile) ;
	$tree->{__LOAD_PACKAGE} = $load_package;
	
	my $inserted_in_file = GetInsertionFile($tree) ;

	$tree->{__INSERTED_AND_DEPENDED_DIFFERENT_PACKAGE}++ if $inserted_in_file ne $Pbsfile ;

	# order so dependencies that do not match subpbs are depended first
	my (@non_matching, @non_subpbs_dependencies, @subpbs_dependencies) ;

	my $sort_tree                = {} ;
	$sort_tree->{__CONFIG}       = $config ;
	$sort_tree->{__PACKAGE}      = $package_alias ;
	$sort_tree->{__LOAD_PACKAGE} = $load_package ;
	$sort_tree->{__PBS_CONFIG}   = $pbs_config ;
			
	for my $dependency (map {$_->{NAME}} @dependencies)
		{
		if (DependencyIsSource($tree, $dependency, $inserted_nodes))
			{
			$tree->{$dependency}{__IS_SOURCE}++ ;
			
			push @non_subpbs_dependencies, [$dependency, 'non subpbs'] ;
			next ;
			}
			
		my ($matched, $matched_subpbs) = (0, 0) ;
		
		$sort_tree->{__NAME} = $dependency ;
		
		# decide in  which order dependencies will be depended 
		for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
			{
			my $rule = $dependency_rules->[$rule_index] ;
			
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
			
			my ($triggered, @dependencies) = $rule->{DEPENDER}->($dependency, $config, $sort_tree, $inserted_nodes, $rule) ;
			
			if($triggered)
				{
				if(@dependencies && 'HASH' eq ref $dependencies[0])
					{
					$matched_subpbs++ ;
					}
				else
					{
					$matched++ ;
					}
				}
			}
		
		if($matched)
			{
			# dependency may match both subpbs and non subpbs rules
			# we put it in the non subpbs so the error is handled in this process
			push @non_subpbs_dependencies, [$dependency, 'non subpbs'] ;
			}
		elsif($matched_subpbs)
			{
			$tree->{$dependency}{__PARALLEL_SCHEDULE}++ ;
 			
			push @subpbs_dependencies, [$dependency, 'subpbs'] ;
			}
		else
			{
			push @non_matching, [$dependency, 'non matching'] ;
			}
		}
		
	# run the last subpbs dependency in this process
	delete $tree->{$subpbs_dependencies[-1][0]}{__PARALLEL_SCHEDULE} if @subpbs_dependencies ;
	
	$rule_time = tv_interval($t0_rules, [gettimeofday]) ;
	
	for (@non_matching, @non_subpbs_dependencies, @subpbs_dependencies)
		{
		my ($dependency, $type) = @$_ ;
		
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
			! exists $tree->{$dependency}{__WARP_NODE}
			&& $tree->{$dependency}{__INSERTED_AT}{INSERTION_FILE} eq $Pbsfile
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
				
				my ($matched) = $rule->{DEPENDER}->($dependency, $config, $tree->{$dependency}, $inserted_nodes, $rule) ;
				
				$ignored_rules .= "\t$matching_rule_index:$rule->{NAME}$rule->{ORIGIN}\n" if($matched) ;
				}
				
			PrintColor 'ignoring_local_rule', "Depend: ignoring local matching rules from '$Pbsfile':\n$ignored_rules" if $ignored_rules ne '' ;
			}
			
		if (! exists $tree->{$dependency}{__DEPENDED} && ! DependencyIsSource($tree, $dependency, $inserted_nodes) ) 
			{
			my %sum_matching_rules = %{$parent_matching_rules} ;
			
			map { push @{$sum_matching_rules{$_}}, $node_name } @node_matching_rules if $node_name !~ /^__/ ;
			
			# rule run once
			my @sub_dependency_rules = $pbs_config->{RULE_RUN_ONCE}
							? grep { $_->{MULTI} || ! exists $_->{MATCHED} } @$dependency_rules
							: () ;
			
			$PBS::Output::indentation_depth++ if $pbs_config->{DISPLAY_DEPEND_INDENTED} && $node_name !~ /^__PBS/ ;
			
			PrintInfo2 $PBS::Output::indentation . $pbs_config->{DISPLAY_DEPEND_SEPARATOR} . "\n"
				if defined $pbs_config->{DISPLAY_DEPEND_SEPARATOR} ;
			
			my $local_time = CreateDependencyTree 
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
			
			$PBS::Output::indentation_depth-- if $pbs_config->{DISPLAY_DEPEND_INDENTED} && $node_name !~ /^__PBS/ ;
			
			$rule_time += $local_time ;
			}
		}
	}
elsif(@subpbses)
	{
	$tree->{__MATCHED_SUBPBS} = @subpbses ;
	
	SET \@subpbses, "Depend: error '$node_name' @ pbsfile '$Pbsfile'  matches multiple subpbs" && die "\n"
		if @subpbses != 1 ;
	
	my $subpbs_definition = $subpbses[0]{SUBPBS} ;
	
	my $subpbs_name = $subpbs_definition->{PBSFILE_LOCATED} =
		 LocatePbsfile
			(
			$pbs_config,
			$Pbsfile,
			$subpbs_definition->{PBSFILE},
			$subpbses[0]{RULE}
			) ;
	
	SIT $subpbs_definition, "subpbs:" if defined $pbs_config->{DISPLAY_SUB_PBS_DEFINITION} ;
	
	# override pbs_config with subpbs pbs_config
	my $subpbs_pbs_config =
		{
		%{$tree->{__PBS_CONFIG}},
		%$subpbs_definition,
		#SUBPBS_HASH => $subpbses[0]{RULE}
		} ;
	
	$subpbs_pbs_config->{PBS_COMMAND}    = DEPEND_ONLY ;
	$subpbs_pbs_config->{ROOT_TRIGGER}   = $tree->{__TRIGGER_INSERTED} if exists $tree->{__TRIGGER_INSERTED} ;
	$subpbs_pbs_config->{PARENT_PACKAGE} = $package_alias ;
	
	my $sub_node_name = $node_name;
	
	if(defined $subpbs_definition->{ALIAS})
		{
		$sub_node_name = $subpbs_definition->{ALIAS} ;
		$inserted_nodes->{$sub_node_name} = $tree ;
		}
	
	my $subpbs_config = PBS::Config::get_subps_configuration
				(
				$subpbs_definition,
				\@subpbses,
				$tree,
				$sub_node_name,
				$pbs_config,
				$load_package,
				) ;
	
	SIT $subpbs_config, "subpbs config:" if defined $pbs_config->{DISPLAY_SUB_PBS_CONFIG} ;
	
	$rule_time = tv_interval($t0_rules, [gettimeofday]) ;
	
	# un-depend ourself for subpbs to match
	delete $tree->{__DEPENDED} ;
	$tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} = $tree->{__INSERTED_AT} ;
	
	my ($build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package)
		= PBS::Depend::Forked::Subpbs
			(
			$pbs_config, $tree,
				[
				[@$pbsfile_chain, $subpbs_name],
				GetRunRelativePath($pbs_config, GetInsertionRule($tree)), # inserted_at
				$subpbs_name,
				$load_package,
				$subpbs_pbs_config,
				$subpbs_config,
				[$sub_node_name],
				$inserted_nodes,
				("subpbses$subpbs_name" =~ s~[^a-zA-Z0-9_]*~_~gr), # tree name
				DEPEND_ONLY,
				],
			) ;
		
	shift @{$nodes_per_pbs_run{$subpbs_load_package}} ; # node existed before subpbs
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
		my $short_node_name = GetTargetRelativePath($pbs_config, $node_name) ;
		
		my $inserted_at = GetInsertionRule($tree) ;
		$inserted_at = GetRunRelativePath($pbs_config, $inserted_at) ;
		
		PrintInfo3 "$PBS::Output::indentation'$short_node_name'"
				. _WARNING_(" no matching rules")
				. _INFO2_(", inserted at: $inserted_at'\n") ;
		}
		
	$rule_time = tv_interval($t0_rules, [gettimeofday]) ;
	}

# section below is disabled as it takes too much time, see -dl
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
	my(@build_sequence, %trigged_files) ;
	
	my $nodes_checker ;
	
	if($pbs_config->{DO_BUILD} || $pbs_config->{DO_IMMEDIATE_BUILD})
		{
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
			
		if (@build_sequence)
			{
			RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $tree, $inserted_nodes, \@build_sequence, $tree) ;
		
			PrintInfo "$indent" . _INFO3_("'$node_name'") . _WARNING3_ (" [IMMEDIATE_BUILD]\n") ;
			$PBS::Output::indentation_depth++ ;
			
			my ($build_result, $build_message) = PBS::Build::BuildSequence
								(
								$pbs_config,
								\@build_sequence,
								$inserted_nodes,
								) ;
				
			$PBS::Output::indentation_depth-- ;
			
			$build_result == BUILD_SUCCESS ? PrintNoColor "\n" : die "\n" ;
			}
		else
			{
			#PrintInfo "$indent" . _INFO3_("'$node_name'") . _INFO_(' nothing to do') . _WARNING3_ (" [IMMEDIATE_BUILD]\n") ;
			}
		}
	else
		{
		PrintWarning "$indent" . _INFO3_("'$node_name'") . _WARNING_ (" skipped [IMMEDIATE_BUILD]\n") ;
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

return if exists $dependency->{__WARP_NODE} ;

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
			
			my ($matched) = $rule->{DEPENDER}->($dependency_name, $config, $dependency, $inserted_nodes, $rule) ;
			
			if($matched)
				{
				$local_rule_info .= COLOR 'ignoring_local_rule', "${indent}${indent}ignoring local rule", 0, 1 ;
				
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

my $link_indent = $indent . $indent ; # -dd
$link_indent .= $indent if $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG} ; # -ddl
$link_indent .= $indent if $pbs_config->{DISPLAY_DEPEND_INDENTED} && ! $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG};

my $short_dependency_name = GetTargetRelativePath($pbs_config, $dependency_name) ;

#  ⁻ · ⁽ ⁾ ⁺ ⁻ ⁼ 
# ⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹
#ᴬ ᴮ ᶜ ᴰ ᴱ ᶠ ᴳ ᴴ ᴵ ᴶ ᴷ ᴸ ᴹ ᴺ ᴼ ᴾ ᵠ ᴿ ˢ ᵀ ᵁ ⱽ ᵂ ˣ ʸ ᶻ > 
#ᵃ ᵇ ᶜ ᵈ ᵉ ᶠ ᵍ ʰ ⁱ ʲ ᵏ ˡ ᵐ ⁿ ᵒ ᵖ ᵠ ʳ ˢ ᵗ ᵘ ᵛ ʷ ˣ ʸ ᶻ 
# • ■ ○ dkmdklf
# ☘ ♾ ♿ ⚒ ⚓ ⚔ ⚕ ⚖ ⚗ ⚘ ⚙ ⚚ ⚛ ⚜ ☀ 

my ($linked_node_info, @link_type) ;

if($dependency_is_source)
	{
	$linked_node_info  = _WARNING_ "$link_indent" . "'$short_dependency_name'" ;
	$linked_node_info .= _WARNING_ ' [T]'  if exists $dependency->{__TRIGGER_INSERTED} ;
	
	push @link_type, " ᴸᴵᴺᴷ" ;
	push @link_type, $local_node ? 'ˡᵒᶜᵃˡ' : 'ᵒᵗʰᵉʳ ᵖᵇˢ' ;
	#push @link_type, 'ˢᵒᵘʳᶜᵉ' ;
	
	push @link_type, 'ᴰᴱᴾᴱᴺᴰᴱᴰ' if exists $dependency->{__DEPENDED} ;
	push @link_type, _WARNING_ 'ᴴᴬˢ ᴰᴱᴾᴱᴺᴰᴱᴺᶜᴵᴱˢ' if scalar ( grep { ! /^__/ } keys %$dependency ) ;
	}
else
	{
	$linked_node_info  = _INFO3_ "$link_indent" . "'$short_dependency_name'" ;
	$linked_node_info .= _INFO3_ ' [T]'  if exists $dependency->{__TRIGGER_INSERTED} ;
	
	push @link_type, " ᴸᴵᴺᴷ" ;
	push @link_type, $local_node ? 'ˡᵒᶜᵃˡ' : 'ᵒᵗʰᵉʳ ᵖᵇˢ' ;
	push @link_type, exists $dependency->{__DEPENDED}
				? scalar ( grep { ! /^__/ } keys %$dependency )
					? ()
					:'ᴺᴼ ᴰᴱᴾᴱᴺᴰᴱᴺᶜᴵᴱˢ' 
				: _WARNING3_('ᴺᴼᵀ ᴰᴱᴾᴱᴺᴰᴱᴰ') . GetColor('info2') ;
	}

Say Info2 $link_indent . $pbs_config->{DISPLAY_DEPEND_SEPARATOR} if defined $pbs_config->{DISPLAY_DEPEND_SEPARATOR} ;

$linked_node_info .= _INFO2_ join(' ⁻ ', @link_type) ;

if ($error_linking || $pbs_config->{DISPLAY_LINK_MATCHING_RULE} || $pbs_config->{DISPLAY_DEPENDENCY_INSERTION_RULE})
	{
	$linked_node_info .= exists $dependency->{__WARP_NODE}
				? ''
				: _INFO2_ ", inserted at rule '"
					. GetRunRelativePath($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE})
					. "'" ;
	
	my $trace_separator = $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG} ? "\n$link_indent" : ', trace: ' ;
	
	if ($pbs_config->{DEBUG_TRACE_PBS_STACK} && PBS::Rules::GetRuleTrace($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE_DEFINITION}))
		{
		for my $trace (PBS::Rules::GetRuleTrace($pbs_config, $dependency->{__INSERTED_AT}{INSERTION_RULE_DEFINITION}, 1))
			{
			$linked_node_info .= INFO2 "$trace_separator$trace"
			}
		}
	}

$linked_node_info .= "\n" ;

$display_linked_node_info = 0 if $dependency->{__MATCHED_SUBPBS} ;

PrintNoColor $linked_node_info . $local_rule_info if $display_linked_node_info || $error_linking ;

PrintError "Depend: error linking to non local node\n" if $error_linking ;
die "\n" if $error_linking ;
}

#-------------------------------------------------------------------------------

sub LocatePbsfile
{
my ($pbs_config, $Pbsfile, $subpbs_name, $rule) = @_ ;

my $info = $pbs_config->{ADD_ORIGIN} ? "rule '$rule->{NAME}' at '$rule->{FILE}\:$rule->{LINE}'" : '' ;

my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;
my $subpbses_name_stem ;

if(file_name_is_absolute($subpbs_name))
	{
	PrintWarning "Using absolute subpbs: '$subpbs_name' $info.\n" ;
	}
else
	{
	my ($basename, $path, $ext) = File::Basename::fileparse($Pbsfile, ('\..*')) ;
	
	my $found_pbsfile ;
	for my $source_directory (@$source_directories, $path)
		{
		my $searched_pbsfile = PBS::PBSConfig::CollapsePath("$source_directory/$subpbs_name") ;
		
		if(-e $searched_pbsfile)
			{
			if($found_pbsfile)
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Locate: ignoring pbsfile '$subpbs_name' in '$source_directory' $info.\n" ;
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Locate: located pbsfile '$subpbs_name' in '$source_directory' $info.\n" ;
					}
					
				$found_pbsfile = $searched_pbsfile ;
				
				last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
				}
			}
		else
			{
			if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
				{
				PrintInfo "Locate: couldn't find pbsfile '$subpbs_name' in '$source_directory' $info.\n" ;
				}
			}
		}
		
	my $subpbses_name_stem ;
	$found_pbsfile ||= "$path$subpbs_name" ;
	
	#check if we can find it somewhere else in the source directories
	for my $source_directory (@$source_directories)
		{
		my $flag = '' ;
		$flag = '(?i)' if $^O eq 'MSWin32' ;
		
		if($found_pbsfile =~ /$flag^$source_directory(.*)/)
			{
			$subpbses_name_stem = $1
			}
		}
		
	my $relocated_subpbs ;
	if(defined $subpbses_name_stem)
		{
		if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
			{
			PrintInfo "Locate: found stem '$subpbses_name_stem'.\n" ;
			}
			
		for my $source_directory (@$source_directories)
			{
			my $relocated_from_stem = PBS::PBSConfig::CollapsePath("$source_directory/$subpbses_name_stem") ;
			
			if(-e $relocated_from_stem)
				{
				unless($relocated_subpbs)
					{
					$relocated_subpbs = $relocated_from_stem  ;
					
					if($relocated_from_stem ne $found_pbsfile)
						{
						PrintWarning2("Locate: relocated '$subpbses_name_stem' in '$source_directory' $info.\n") ;
						}
					else
						{
						if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
							{
							PrintInfo "Locate: keeping '$subpbses_name_stem' from '$source_directory' $info.\n" ;
							}
						}
						
					last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
					}
				else
					{
					if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
						{
						PrintInfo "Locate: ignoring relocation of '$subpbses_name_stem' in '$source_directory' $info.\n" ;
						}
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Locate: couldn't relocate '$subpbses_name_stem' in '$source_directory' $info.\n" ;
					}
				}
			}
		}
		
	$subpbs_name = $relocated_subpbs || $found_pbsfile || $subpbs_name;
	}

return($subpbs_name) ;
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

Given a node and a set of rules, B<CreateDependencyTree> will recursively build the entire dependency tree 

=cut

