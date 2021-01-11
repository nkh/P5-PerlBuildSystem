
$PBS::Dependency::BuildDependencyTree_calls = 0 ;

package PBS::Depend ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
use String::Truncate ;

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

#-----------------------------------------------------------------------------------------

sub FORCE_TRIGGER
{
my $reason = shift || die "Forced trigger must have a reason\n" ;

return
	(
	bless ( { MESSAGE => $reason }, "PBS_FORCE_TRIGGER" ) 
	) ;
}

#-------------------------------------------------------------------------------

my %has_no_dependencies ;

sub HasNoDependencies
{
my ($package, $file_name, $line) = caller() ;

die ERROR "Invalid 'ExcludeFromDigestGeneration' arguments at $file_name:$line\n" if @_ % 2 ;

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

my $node_name  = $node->{__NAME} ;
my $pbs_config = $node->{__PBS_CONFIG} ;

my $ok = 0 ;

for my $name (keys %{$has_no_dependencies{$package}})
	{
	if($node_name =~ $has_no_dependencies{$package}{$name}{PATTERN})
		{
		if(defined $pbs_config->{DISPLAY_NO_DEPENDENCIES_OK})
			{
			PrintWarning("Depend: '$node_name' OK no dependencies,  rule: '$name' [$has_no_dependencies{$package}{$name}{PATTERN}]") ;
			PrintWarning(" @ $has_no_dependencies{$package}{$name}{ORIGIN}") if defined $pbs_config->{ADD_ORIGIN} ;
			PrintWarning(".\n") ;
			}
			
		$ok = 1 ;
		last ;
		}
	}

return($ok) ;
}

#-------------------------------------------------------------------------------

my %trigger_rules ;

sub CreateDependencyTree
{
my $pbsfile_chain    = shift // [] ;
my $Pbsfile          = shift ;
my $package_alias    = shift ;
my $load_package     = PBS::PBS::CanonizePackageName(shift) ;
my $pbs_config       = shift ;
my $tree             = shift ;
my $config           = shift ; 
my $inserted_nodes   = shift ;
my $dependency_rules = shift ;

return if(exists $tree->{__DEPENDED}) ;

$PBS::Depend::BuildDependencyTree_calls++ ;
my $indent = $PBS::Output::indentation ;

my $node_name = $tree->{__NAME} ;

my $node_name_matches_ddrr = 0 ;
for my $regex (@{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}})
	{
	if($node_name =~ /$regex/)
		{
		$node_name_matches_ddrr = 1 ;
		last ;
		}
	}
	
my %dependency_rules ; # keep a list of  which rules generated which dependencies
my $has_dependencies = 0 ;
my @has_matching_non_subpbs_rules ;
my @sub_pbs ; # list of subpbs matching this node

my @post_build_rules = PBS::PostBuild::GetPostBuildRules($load_package) ;

if
	(
	   defined $tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX}
	|| defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}
	)
	{
	PrintInfo2("Rule: target:" . INFO3("'$node_name'\n", 0))
		if ($node_name !~ /^__/) ;
	}

# check if the current node has matching post build rules
for my $post_build_rule (@post_build_rules)
	{
	my ($match, $message) = $post_build_rule->{DEPENDER}($node_name) ;
	
	if($match)
		{
		push @{$tree->{__POST_BUILD_COMMANDS}}, $post_build_rule ;
		
		if($pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS})
			{
			my $post_build_command_info =  $post_build_rule->{NAME}
							. $post_build_rule->{ORIGIN} ;
								
			PrintInfo("Depend: $node_name has matching post build command, '$post_build_command_info'\n") ;
			}
		}
	}

my $available = PBS::Output::GetScreenWidth() ;
my $em = String::Truncate::elide_with_defaults({ length => $available, truncate => 'middle' });

my $node_is_source = 
	sub
		{
		my($dependent, $node_name) = @_ ;

		if (exists $inserted_nodes->{$node_name})
			{
			! PBS::Digest::IsDigestToBeGenerated
				(
				$inserted_nodes->{$node_name}{__LOAD_PACKAGE} // $dependent->{__LOAD_PACKAGE},
				$inserted_nodes->{$node_name}
				) ; 
			}
		else
			{
			! PBS::Digest::IsDigestToBeGenerated
				(
				$dependent->{__LOAD_PACKAGE},
				{__NAME => $node_name, __PBS_CONFIG => $dependent->{__PBS_CONFIG}}
				) ;
			}
		} ;

my $rules_matching = 0 ;

# find the dependencies by applying the rules
for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
	{
	my $dependency_rule = $dependency_rules->[$rule_index] ;
	my $rule_name = $dependency_rule->{NAME} ;
	my $rule_line = $dependency_rule->{LINE} ;
	my $rule_info = $rule_name . INFO2(" @ $dependency_rule->{FILE}:$rule_line", 0) ;
	
	my $depender  = $dependency_rule->{DEPENDER} ;
   
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
		
	$dependency_rule->{STATS}{CALLED}++ ;
	my ($dependency_result, $builder_override) = $depender->($node_name, $config, $tree, $inserted_nodes, $dependency_rule) ;
	
	my ($triggered, @dependencies ) = @$dependency_result ;
	
	if(grep {! defined } @dependencies)
		{
		die ERROR("Depend: Error: While depending '$node_name', rule $rule_info, returned an undefined dependency\n")
		}

	#DEBUG
	$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1, TRIGGERED => $triggered, DEPENDENCIES => \@dependencies)) ;
	
	if($triggered)
		{
		push @{$dependency_rule->{STATS}{MATCHED}}, $tree ;
		$rules_matching++ ;

		$tree->{__DEPENDED}++ ; # depend sub tree once only flag
		$tree->{__DEPENDED_AT} = $Pbsfile ;
		
		my $subs_list = $dependency_rule->{NODE_SUBS} ;
		
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
				die ERROR "Depend: Error: node sub is not a sub @ $rule_info\n" ;
				}
				
			my $index = 0 ;
			for my $sub (@$subs)
				{
				$index++ ;
			
				PrintUser(
					"$indent'$node_name'" 
					. INFO(" node sub $index/" . scalar(@$subs), 0)
					. INFO2(" '$rule_name:$dependency_rule->{FILE}:$dependency_rule->{LINE}'\n", 0))
						if $pbs_config->{DISPLAY_NODE_SUBS_RUN} ;
				
				my @r = $sub->($node_name, $config, $tree, $inserted_nodes) ;
				
				PrintInfo2("$indent${indent}node sub returned: @r\n") 
					if @r && $pbs_config->{DISPLAY_NODE_SUBS_RUN} ;
				}
			}
			
		#----------------------------------------------------------------------------
		# is it a subpbs definition?
		#----------------------------------------------------------------------------
		if(@dependencies && 'HASH' eq ref $dependencies[0])
			{
			$dependencies[0]{__RULE_NAME} = $dependency_rule->{NAME} ;
			push @sub_pbs, 
				{
				SUBPBS => $dependencies[0],
				RULE   => $dependency_rule,
				} ;
			
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddrr)
				{
				PrintInfo3("${indent}'$node_name' has matching subpbs: $rule_index:$rule_info\n") ;
				}
				
			next ;
			}
		else
			{
			push @has_matching_non_subpbs_rules, "rule '$rule_name', file '$dependency_rule->{FILE}:$dependency_rule->{LINE}'" ;
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
		
		for my $rule_type (@{$dependency_rule->{TYPE}})
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
					push @node_type, "$type" if exists $tree->{$type} ;
					}

				my $node_type = scalar(@node_type) ? '[' . join(', ', @node_type) . '] ' : '' ;
				
				my $rule_info =  $dependency_rule->{NAME}
						. (defined $pbs_config->{ADD_ORIGIN} 
							? $dependency_rule->{ORIGIN}
							: ':' . $dependency_rule->{FILE} . ':' . $dependency_rule->{LINE}) ;

				my $rule_type = '' ;
				$rule_type .= '[B]'  if(defined $dependency_rule->{BUILDER}) ;
				$rule_type .= '[BO]' if($builder_override) ;
				$rule_type .= '[S]'  if(defined $dependency_rule->{NODE_SUBS}) ;
				$rule_type = " $rule_type" unless $rule_type eq '' ;

				my @dependency_names = map {$_->{NAME} ;} grep {'' eq ref $_->{NAME}} @dependencies ;
				
				
				my $forced_trigger = '' ;
				if(grep {'PBS_FORCE_TRIGGER' eq ref $_->{NAME}} @dependencies) # use List::Utils::Any
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

					$no_dependencies = ' no dependencies' ;
					}

				if(defined $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
					{
					PrintInfo3($em->("$indent'$node_name' ${node_type}${forced_trigger}\n")) ;
					
					PrintInfo2($em->("$indent$indent$rule_index:$rule_info $rule_type [$rules_matching]\n"))
						if $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE} ;
					
					if(@dependency_names)
						{
						PrintInfo
							 $indent . $indent
							. join
								(
								"\n$indent$indent",
								map { $node_is_source->($tree, $_) ? WARNING("'" . $em->($_) . "'", 0) : INFO("'" . $em->($_) . "'", 0) } 
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
					my $dd = INFO3 "$indent'$node_name' ${node_type}${forced_trigger}" ;

					$dd .= @dependency_names
						? INFO(" dependencies [ " . join(' ', map { $node_is_source->($tree, $_) ? WARNING("'$_'", 0) : INFO("'$_'", 0) } @dependency_names), 0)
							 . INFO( " ]", 0)
						: INFO("[$no_dependencies ]", 0) ;

					$dd .= defined $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE}
						? INFO2(" $rule_index:$rule_info$rule_type [$rules_matching]", 0)
						: '' ;
					
					$dd .= "\n" ;
					
					PrintNoColor '' . $dd ;
					}
					
				PrintWithContext
					(
					$dependency_rule->{FILE},
					1, 2, # context  size
					$dependency_rule->{LINE},
					\&INFO,
					) if $pbs_config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION} ;
				}
			}
			
		#----------------------------------------------------------------------------
		# Check the dependencies
		#----------------------------------------------------------------------------
		for my $dependency (@dependencies)
			{
			my $dependency_name = $dependency->{NAME} ;
			if(ref $dependency_name eq 'PBS_FORCE_TRIGGER')
				{
				push @{$tree->{__PBS_FORCE_TRIGGER}}, $dependency_name ;
				next ;
				}
				
			if(ref $dependency_name eq 'PBS_SYNCHRONIZE')
				{
				my 
				(
				$unsynchronized_dependency_file_name,
				$dependency_file_name,
				$message_format,
				) = @$dependency_name{'SOURCE_FILE', 'DESTINATION_FILE', 'MESSAGE_FORMAT'} ;
				
				$tree->{__SYNCHRONIZE}{$unsynchronized_dependency_file_name} = 
					{
					TO_FILE        => $dependency_file_name,
					MESSAGE_FORMAT => $message_format,
					} ;
					
				next ;
				}
				
			next if $dependency_name =~ /^__/ ;
			
			RunPluginSubs($pbs_config, 'CheckNodeName', $dependency_name, $dependency_rule) ;
			
			if($node_name eq $dependency_name)
				{
				my $rule_info = $dependency_rule->{NAME} . $dependency_rule->{ORIGIN} ;
									
				my $dependency_names = join ' ', map{$_->{NAME}} @dependencies ;
				PrintError( "Depend: self referencial rule #$rule_index '$rule_info' for $node_name: $dependency_names.\n") ;
				
				PbsDisplayErrorWithContext($dependency_rule->{FILE}, $dependency_rule->{LINE}) ;
				die "\n";
				}
			
			if(exists $tree->{$dependency_name})
				{
				unless($dependency_name =~ /^__/)
					{
					unless (defined $pbs_config->{NO_DUPLICATE_INFO})
						{
						my $rule_info = $dependency_rule->{NAME} . $dependency_rule->{ORIGIN} ;
											
						my $inserting_rule_index = $tree->{$dependency_name}{RULE_INDEX} ;
						my $inserting_rule_info  =  $dependency_rules->[$inserting_rule_index]{NAME}
										. $dependency_rules->[$inserting_rule_index]{ORIGIN} ;
											
						PrintWarning
							(
							  "Depend: in pbsfile : $Pbsfile, while at rule '$rule_info', node '$node_name':\n"
							. "    $dependency_name already inserted by rule "
							. "'$inserting_rule_index:$inserting_rule_info'"
							. ", Ignoring duplicate dependency.\n"
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
			
		# keep a log of matching rules
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
		}
	else
		{
		# not triggered
		push @{$dependency_rule->{STATS}{NOT_MATCHED}}, $tree ;

		my $depender_message = $dependencies[0] // 'No match' ;
		PrintColor('no_match', "$PBS::Output::indentation$depender_message, $rule_info\n") if(defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;
		}
	}

#-------------------------------------------------------------------------
# continue with single definition of dependencies 
# and remove temporary dependency names
#-------------------------------------------------------------------------
my @dependencies = () ;
for my $dependency_name (keys %$tree)
	{
	if(($dependency_name !~ /^__/) && ('' eq ref $tree->{$dependency_name}{NAME}))
		{
		push @dependencies, $tree->{$dependency_name}  ;
		}
	}

if(@sub_pbs > 1)
	{
	PrintError "Depend: in pbsfile : $Pbsfile, $node_name has multiple matching subpbs:\n" ;
	PrintError(DumpTree(\@sub_pbs, "Sub Pbs:")) ;
	
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
	
	use Carp ;
	unless('HASH' eq ref $dependency)
		{
		PrintNoColor $dependency ;
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
		LinkNode($pbs_config, $dependency_name, $tree, $inserted_nodes, $Pbsfile, $config, $dependency_rules, $rule_index) ;
		}
	else
		{
		# a new node is born
		my $rule_name = $dependency_rules->[$rule_index]{NAME} ;
		my $rule_file = $dependency_rules->[$rule_index]{FILE} ;
		my $rule_line = $dependency_rules->[$rule_index]{LINE} ;
		my $rule_info = $rule_name . $dependency_rules->[$rule_index]{ORIGIN} ;

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
			
			#DEBUG	
			$DB::single = 1 if(PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1)) ;
			}
		
		my %dependency_tree_hash ;
		
		$tree->{$dependency_name}                     = \%dependency_tree_hash ;
		$tree->{$dependency_name}{__MATCHING_RULES}   = [] ;
		$tree->{$dependency_name}{__CONFIG}           = $config ;
		$tree->{$dependency_name}{__NAME}             = $dependency_name ;
		$tree->{$dependency_name}{__USER_ATTRIBUTE}   = $dependency->{USER_ATTRIBUTE} if exists $dependency->{USER_ATTRIBUTE} ;
		
		$tree->{$dependency_name}{__PACKAGE}          = $package_alias ;
		$tree->{$dependency_name}{__LOAD_PACKAGE}     = $load_package ;
		$tree->{$dependency_name}{__PBS_CONFIG}       = $pbs_config ;
		
		$tree->{$dependency_name}{__INSERTED_AT}      = {
								PBSFILE_CHAIN          => $pbsfile_chain,
								INSERTION_FILE         => $Pbsfile,
								INSERTION_PACKAGE      => $package_alias,
								INSERTION_LOAD_PACKAGE => $load_package,
								INSERTION_RULE         => $rule_info,
								INSERTION_RULE_NAME    => $rule_name,
								INSERTION_RULE_FILE    => $rule_file,
								INSERTION_RULE_LINE    => $rule_line,
								INSERTION_TIME         => $time,
								INSERTING_NODE         => $tree->{__NAME},
								} ;
								
		$inserted_nodes->{$dependency_name} = $tree->{$dependency_name} ;
			
		#DEBUG
		$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1)) ;
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
	# if the rules applied to the node are identical, we thus only remember the pbsfile with matching rules
	$tree->{__DEPENDING_PBSFILE} = PBS::Digest::GetFileMD5($Pbsfile) ;
	$tree->{__LOAD_PACKAGE} = $load_package;
	
	for my $dependency (keys %$tree)
		{
		next if $dependency =~ /^__/ ;
		
		# keep parent relationship
		my $key_name = $node_name . ': ' ;
		
		for my $rule (@{$dependency_rules{$dependency}})
			{
			$key_name .= "rule: " . join(':', @$rule) . " "  ;
			}
		
		$tree->{$dependency}{__DEPENDENCY_TO}{$key_name} = $tree->{__DEPENDENCY_TO} ;
		
		# help user keep sanity by revealing some of the depend history
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
				my ($dependency_result) = $dependency_rules->[$matching_rule_index]{DEPENDER}->($dependency, $config, $tree->{$dependency}, $inserted_nodes,  $dependency_rules->[$matching_rule_index]) ;
				if($dependency_result->[0])
					{
					my $rule_info =  $dependency_rules->[$matching_rule_index]{NAME}
								. $dependency_rules->[$matching_rule_index]{ORIGIN} ;
										
					$ignored_rules .= "\t$matching_rule_index:$rule_info\n" ;
					}
				}
				
			PrintWarning("Depend: ignoring local matching rules from '$Pbsfile':\n$ignored_rules") if $ignored_rules ne '' ;
			}
		
		if (! exists $tree->{$dependency}{__DEPENDED} && ! $node_is_source->($tree, $dependency) ) 
			{
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
				$dependency_rules
				) ;
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
		
	my $sub_pbs_hash    = $sub_pbs[0]{SUBPBS} ;

	my $unlocated_sub_pbs_name = my $sub_pbs_name = $sub_pbs_hash->{PBSFILE} ;
	my $sub_pbs_package = $sub_pbs_hash->{PACKAGE} ;
	
	my $alias_message = '' ;
	$alias_message = "aliased as '$sub_pbs_hash->{ALIAS}'" if(defined $sub_pbs_hash->{ALIAS}) ;
	
	$sub_pbs_name = LocatePbsfile($pbs_config, $Pbsfile, $sub_pbs_name, $sub_pbs[0]{RULE}) ;
	$sub_pbs_hash->{PBSFILE_LOCATED} = $sub_pbs_name ;
	
	unless(defined $pbs_config->{NO_SUBPBS_INFO})
		{
		if(defined $pbs_config->{SUBPBS_FILE_INFO})
			{
			PrintWarning "[$PBS::PBS::pbs_runs/$PBS::Output::indentation_depth] Depend: '$node_name' $alias_message\n" ;
			my $node_info = "inserted at '$inserted_nodes->{$node_name}->{__INSERTED_AT}{INSERTION_RULE}'" ;
			PrintInfo2  "\t$node_info, \n"
					. "\twith subpbs '$sub_pbs_package:$sub_pbs_name'.\n" ;
			}
		}
		
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
	
	my $already_inserted_nodes = $inserted_nodes ;
	$already_inserted_nodes    = {} if(defined $sub_pbs_hash->{LOCAL_NODES}) ;
	
	my %inserted_nodes_snapshot ;
	%inserted_nodes_snapshot = %$inserted_nodes if $node_is_trigger_inserted ;

	my ($build_result, $build_message, $sub_tree, $inserted_nodes, $sub_pbs_load_package)
		= PBS::PBS::Pbs
			(
			[@$pbsfile_chain, $sub_pbs_name],
			'SUBPBS',
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
	# no subpbs no non-subpbs

	if 
		(
		$node_name_matches_ddrr &&
		$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} &&
		$node_name !~ /^__/ &&
		PBS::Digest::IsDigestToBeGenerated($tree->{__LOAD_PACKAGE}, $tree)
		)
		{
		PrintWarning "$PBS::Output::indentation'$node_name' wasn't depended,"
				. INFO2(" pbsfile: '$pbs_config->{PBSFILE}'\n") ;
		}
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
			die "BUILD_FAILED\n" ;
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
}

sub LinkNode
{
my ($pbs_config, $dependency_name, $tree, $inserted_nodes, $Pbsfile, $config, $dependency_rules, $rule_index) = @_ ;

# user defined plugin which can fail the graph generation
RunPluginSubs($pbs_config, 'CheckLinkedNode', @_) ;
	
my $indent = $PBS::Output::indentation ;

# the dependency already exists within the graph, link to it
$tree->{$dependency_name} = $inserted_nodes->{$dependency_name} ;
$tree->{$dependency_name}{__LINKED}++ ;

my $display_linked_node_info = 0 ;
$display_linked_node_info++ if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && (! $pbs_config->{NO_LINK_INFO})) ;

my $rule_name =  $dependency_rules->[$rule_index]{NAME} ;
my $rule_info =  $rule_name . $dependency_rules->[$rule_index]{ORIGIN} ;

my ($dependency, @link_type) = ( $inserted_nodes->{$dependency_name} ) ;

# display link information depending on the type of node
# 	note that warp loses the __LOAD_PACKAGE information, but running in warp
#	removed the warnings unless --display_warp_generated_warnings is used, we still
#	are missing __LOAD_PACKAGE information and we just approximate it with the current node's __LOAD_PACKAGE 
if(PBS::Digest::IsDigestToBeGenerated($dependency->{__LOAD_PACKAGE} // $tree->{__LOAD_PACKAGE}, $dependency))
	{
	push @link_type, 'warning: not depended' unless exists $dependency->{__DEPENDED} ;
	push @link_type, 'no dependencies'       unless scalar ( grep { ! /^__/ } keys %$dependency ) ;
	}
else
	{
	push @link_type, 'source' ;

	push @link_type, 'warning: depended'         if exists $dependency->{__DEPENDED} ;
	push @link_type, 'warning: has dependencies' if scalar ( grep { ! /^__/ } keys %$dependency ) ;
	}

push @link_type, 'trigger inserted'  if exists $dependency->{__TRIGGER_INSERTED} ;
push @link_type, 'different pbsfile' if $dependency->{__INSERTED_AT}{INSERTION_FILE} ne $Pbsfile ;

my $link_type = @link_type ? '[' . join(', ', @link_type) . ']' : '' ;


my $linked_node_info = INFO3("${indent}'$dependency_name'") . INFO2(" linking $link_type", 0) ;
$linked_node_info .= INFO2( ", rule: $dependency->{__INSERTED_AT}{INSERTION_RULE}", 0) if $pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE} ;
$linked_node_info .= "\n" ;
	
if($dependency->{__INSERTED_AT}{INSERTION_FILE} ne $Pbsfile)
	{
	die ERROR("Error: --no_external_link switch specified, stop.\n") if defined $pbs_config->{DEBUG_NO_EXTERNAL_LINK} ;
		
	unless($pbs_config->{NO_LOCAL_MATCHING_RULES_INFO})
		{
		my @local_rules_matching ;
		
		for(my $matching_rule_index = 0 ; $matching_rule_index < @$dependency_rules ; $matching_rule_index++)
			{
			my ($dependency_result) = $dependency_rules->[$matching_rule_index]{DEPENDER}->($dependency_name, $config, $dependency, $inserted_nodes, $dependency_rules->[$matching_rule_index]) ;
			push @local_rules_matching, $matching_rule_index if($dependency_result->[0]) ;
			}
		
		if(exists $dependency->{__DEPENDED} && @local_rules_matching)
			{
			my @local_rules_matching_info ;
			
			for my $matching_rule_index (@local_rules_matching)
				{
				push @local_rules_matching_info, 
					"$matching_rule_index:"
					. $dependency_rules->[$matching_rule_index]{NAME}
					. $dependency_rules->[$matching_rule_index]{ORIGIN} ;
				}
			
			$linked_node_info .= USER( "${indent}Ignoring local rules:\n") ;
			$linked_node_info .= USER( "${indent}${indent}$_\n") for (@local_rules_matching_info) ;

			$display_linked_node_info++ ;
			}
		}
	}
	
PrintNoColor($linked_node_info) if $display_linked_node_info ;
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
					PrintInfo "Ignoring pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Located pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
					}
					
				$found_pbsfile = $searched_pbsfile ;
				
				last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
				}
			}
		else
			{
			if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
				{
				PrintInfo "Couldn't find pbsfile '$sub_pbs_name' in '$source_directory' $info.\n" ;
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
			PrintInfo "Found stem '$sub_pbs_name_stem'.\n" ;
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
						PrintWarning2("Relocated '$sub_pbs_name_stem' in '$source_directory' $info.\n") ;
						}
					else
						{
						if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
							{
							PrintInfo "Keeping '$sub_pbs_name_stem' from '$source_directory' $info.\n" ;
							}
						}
						
					last unless $pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES} ;
					}
				else
					{
					if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
						{
						PrintInfo "Ignoring relocation of '$sub_pbs_name_stem' in '$source_directory' $info.\n" ;
						}
					}
				}
			else
				{
				if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
					{
					PrintInfo "Couldn't relocate '$sub_pbs_name_stem' in '$source_directory' $info.\n" ;
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
