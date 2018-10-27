
$PBS::Dependency::BuildDependencyTree_calls = 0 ;

package PBS::Depend ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Time::HiRes ;
use Tie::Hash::Indexed ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;

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

$PBS::Depend::BuildDependencyTree_calls++ ;

return if(exists $tree->{__DEPENDED}) ;

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

tie my %triggered_nodes, 'Tie::Hash::Indexed';

my @post_build_rules = PBS::PostBuild::GetPostBuildRules($load_package) ;

if
	(
	   defined $tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX}
	|| defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}
	)
	{
	PrintInfo("Depend: '$node_name'\n")
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

# find the dependencies by applying the rules
for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
	{
	my $rule_name = $dependency_rules->[$rule_index]{NAME} ;
	my $rule_line = $dependency_rules->[$rule_index]{LINE} ;
	my $rule_info = $rule_name . INFO2(" @ $dependency_rules->[$rule_index]{FILE}:$dependency_rules->[$rule_index]{LINE}", 0) ;
	
	my $depender  = $dependency_rules->[$rule_index]{DEPENDER} ;
   
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
			
		$DB::single = 1 if(PBS::Debug::CheckBreakpoint(%debug_data, PRE => 1)) ;
		}
		
	my ($dependency_result, $builder_override) = $depender->($node_name, $config, $tree, $inserted_nodes, $dependency_rules->[$rule_index]) ;
	
	my ($triggered, @dependencies ) = @$dependency_result ;
	
	if(grep {! defined } @dependencies)
		{
		die ERROR("Error: While depending '$node_name', rule $rule_info, returned an undefined dependency\n")
		}

	#DEBUG	
	$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, POST => 1, TRIGGERED => $triggered, DEPENDENCIES => \@dependencies)) ;
	
	if($triggered)
		{
		$tree->{__DEPENDED}++ ; # depend sub tree once only flag
		$tree->{__DEPENDED_AT} = $Pbsfile ;
		
		my $subs_list = $dependency_rules->[$rule_index]{NODE_SUBS} ;
		
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
						die ERROR "Build: node sub is not a sub in array at rule $rule_info\n" ;
						}
					}
				}
			else
				{
				die ERROR "Build: node sub is not a sub @ $rule_info\n" ;
				}
				
			if(@$subs)
				{
				PrintInfo 'Build: running node subs ['  . scalar(@$subs) . "] at '$rule_name:$dependency_rules->[$rule_index]{FILE}:$dependency_rules->[$rule_index]{LINE}'\n" 
					if $pbs_config->{DISPLAY_NODE_SUBS_RUN} ;
				
				my $index = -1 ;
				for my $sub (@$subs)
					{
					$index++ ;
					PrintInfo "Build: running node sub index '$index'\n" if $pbs_config->{DISPLAY_NODE_SUBS_RUN} ;
					
					$sub->($node_name, $config, $tree, $inserted_nodes) ;
					}
				}
			}
			
		#----------------------------------------------------------------------------
		# is it a subpbs definition?
		#----------------------------------------------------------------------------
		if(@dependencies && 'HASH' eq ref $dependencies[0])
			{
			$dependencies[0]{__RULE_NAME} = $dependency_rules->[$rule_index]{NAME} ;
			push @sub_pbs, 
				{
				SUBPBS => $dependencies[0],
				RULE   => $dependency_rules->[$rule_index],
				} ;
			
			if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddrr)
				{
				PrintInfo("[$PBS::Output::indentation_depth] Depend: '$node_name' in subpbs, rule $rule_index:$rule_info\n") ;
				}
				
			next ;
			}
		else
			{
			push @has_matching_non_subpbs_rules, "rule '$rule_name', file '$dependency_rules->[$rule_index]{FILE}:$dependency_rules->[$rule_index]{LINE}'" ;
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
		
		for my $rule_type (@{$dependency_rules->[$rule_index]{TYPE}})
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
				my $node_type = '' ;
				for my $type (VIRTUAL, LOCAL, FORCED)
					{
					$node_type .= " $type " if exists $tree->{$type} ;
					}
				$node_type = '[' . $node_type . '] ' if $node_type ne '' ;
				
				my $rule_info =  $dependency_rules->[$rule_index]{NAME}
						. (defined $pbs_config->{ADD_ORIGIN} 
							? $dependency_rules->[$rule_index]{ORIGIN}
							: ':' .$dependency_rules->[$rule_index]{FILE}) ;

				my $rule_type = '' ;
				$rule_type .= '[B]'  if(defined $dependency_rules->[$rule_index]{BUILDER}) ;
				$rule_type .= '[BO]' if($builder_override) ;
				$rule_type .= '[S]'  if(defined $dependency_rules->[$rule_index]{NODE_SUBS}) ;
				$rule_type = " $rule_type" unless $rule_type eq '' ;

				my @dependency_names = map {$_->{NAME} ;} grep {'' eq ref $_->{NAME}} @dependencies ;
				
				
				my $forced_trigger = '' ;
				if(grep {'PBS_FORCE_TRIGGER' eq ref $_->{NAME}} @dependencies) # use List::Utils::Any
					{
					$forced_trigger = ' FORCED_TRIGGER!' ;
					}
					
				use String::Truncate ;
				my $em = String::Truncate::elide_with_defaults({ length => 28, truncate => 'middle' });
				my $el = String::Truncate::elide_with_defaults({ length => 28, truncate => 'left' });

				if(defined $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG})
					{
					my $dependency_info = "[$PBS::Output::indentation_depth] '" . $el->($node_name) . "'${node_type}${forced_trigger} rule $rule_index:" . $em->($rule_info) . $rule_type ;
					
					if(@dependency_names)
						{
						$dependency_info .= ":\n" ;
						my $dependency_info_deps =  $PBS::Output::indentation . join("\n     ", map {"'" . $el->($_) . "'"} @dependency_names) ;
						$dependency_info_deps .= "\n\n" ;
			
						PrintInfo($dependency_info) ;
						PrintUser($dependency_info_deps) ;
						}
					else
						{
						$dependency_info .= ".\n\n" ;
						PrintInfo($dependency_info) ;
						}
					}
				else
					{
					PrintInfo "[$PBS::Output::indentation_depth] '$node_name' ${node_type}${forced_trigger}has dependencies [" . USER("@dependency_names", 0) . INFO("], rule $rule_index:$rule_info:$rule_type\n\n", 0) ;
					}
					
				PrintWithContext
					(
					$dependency_rules->[$rule_index]{FILE},
					1, 2, #context  size
					$dependency_rules->[$rule_index]{LINE},
					\&INFO,
					) if defined $pbs_config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION} ;
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
			
			RunPluginSubs($pbs_config, 'CheckNodeName', $dependency_name, $dependency_rules->[$rule_index]) ;
			
			if($node_name eq $dependency_name)
				{
				my $rule      = $dependency_rules->[$rule_index] ;
				my $rule_info =  $rule->{NAME} . $rule->{ORIGIN} ;
									
				my $dependency_names = join ' ', map{$_->{NAME}} @dependencies ;
				PrintError( "Depend: self referencial rule #$rule_index '$rule_info' for $node_name: $dependency_names.\n") ;
				
				PbsDisplayErrorWithContext($rule->{FILE}, $rule->{LINE}) ;
				die "\n";
				}
			
			if(exists $tree->{$dependency_name})
				{
				unless($dependency_name =~ /^__/)
					{
					unless (defined $pbs_config->{NO_DUPLICATE_INFO})
						{
						my $rule_info =  $dependency_rules->[$rule_index]{NAME}
											. $dependency_rules->[$rule_index]{ORIGIN} ;
											
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
				# temporarely hold the names of the dependencies within the node
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
		my $depender_message = $dependencies[0] // 'No match' ;
		PrintError("$PBS::Output::indentation$depender_message, $rule_info\n") if(defined $pbs_config->{DISPLAY_DEPENDENCY_RESULT}) ;
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
	PrintError "Depend: in pbsfile : $Pbsfile, $node_name has multiple subpbs defined:\n" ;
	PrintError(DumpTree(\@sub_pbs, "Sub Pbs:")) ;
	
	Carp::croak  ;
	}
	

#-------------------------------------------------------------------------
# handle node triggers
#-------------------------------------------------------------------------
for my $dependency (@dependencies)
	{
	use constant TRIGGERED_NODE_NAME  => 0 ;
	use constant TRIGGERING_NODE_NAME => 1 ;
	use constant TRIGGER_INFO         => 2 ;
	use constant TRIGGER_INFO_NAME    => 3 ;
	
	use Carp ;
	unless('HASH' eq ref $dependency)
		{
		print STDERR $dependency ;
		confess  ;
		}
	
	my $dependency_name = $dependency->{NAME} ;
	
	for my $trigger_rule (PBS::Triggers::GetTriggerRules($load_package))
		{
		my ($match, $triggered_node_name) = $trigger_rule->{DEPENDER}($dependency_name) ;

		my $trigger_info_name =  $trigger_rule->{NAME} ;
		my $trigger_info =  $trigger_info_name . $trigger_rule->{ORIGIN} ;
								
		if($match)
			{
			my $current_trigger_message = '' ;
			
			next if($triggered_node_name eq $node_name) ;
			
			if(exists $inserted_nodes->{$triggered_node_name})
				{
				$current_trigger_message = "'$triggered_node_name' would have been inserted by trigger: '$trigger_info' "
								. "on node '$dependency_name', but was found among the nodes.\n" ;
				}
			else
				{
				$current_trigger_message = "'$triggered_node_name' was inserted by trigger: '$trigger_info' "
														. " on node '$dependency_name'.\n" ;
														
				if(exists $triggered_nodes{$triggered_node_name})
					{
					$current_trigger_message .= "'$triggered_node_name' was already trigger inserted by trigger "
									. "'$triggered_nodes{$triggered_node_name}[TRIGGER_INFO]' on "
									. "node '$triggered_nodes{$triggered_node_name}[TRIGGERING_NODE_NAME]'."
									. "Ignoring duplicate triggered node.\n" ;
					}
				else
					{
					$triggered_nodes{$triggered_node_name} = [$triggered_node_name, $dependency_name, $trigger_info, $trigger_info_name] ;
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
for my $triggered_node_data (values %triggered_nodes)
	{
	my $triggered_node_name  = $triggered_node_data->[TRIGGERED_NODE_NAME] ;
	my $triggering_node_name = $triggered_node_data->[TRIGGERING_NODE_NAME] ;
	my $rule_info            = $triggered_node_data->[TRIGGER_INFO],
	my $rule_name            = $triggered_node_data->[TRIGGER_INFO_NAME],
	my $rule_line            = '',
	
	my $time = Time::HiRes::time() ;
	
	tie my %triggered_node_tree, "Tie::Hash::Indexed" ;
	
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
		#~__USER_ATTRIBUTE   => $dependency->[DEPENDENCY_USER_ATTRIBUTE],
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
	push @{$dependency_rules{$dependency_name}}, [$rule_index, $dependency_rules->[$rule_index]{NAME}] ;
	
	if(exists $inserted_nodes->{$dependency_name})
		{
		# the dependency already exists within the tree (inserted through another node)
		$tree->{$dependency_name} = $inserted_nodes->{$dependency_name} ;
		$tree->{$dependency_name}{__LINKED}++ ;
		
		my $display_linked_node_info = 0 ;
		$display_linked_node_info++ if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && (! $pbs_config->{NO_LINK_INFO})) ;
		
		my $rule_name =  $dependency_rules->[$rule_index]{NAME} ;
		my $rule_info =  $rule_name . $dependency_rules->[$rule_index]{ORIGIN} ;

		my $linked_node_is_depended = exists $inserted_nodes->{$dependency_name}{__DEPENDED}
						? ''
						: ' [not depended yet]'  ;
							
		my $linked_node_info = "      Linking '$dependency_name'" 
					. $linked_node_is_depended
					. " from $inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_FILE}" 
					. ":$inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_RULE}\n" ;
		
			
		if($inserted_nodes->{$dependency_name}{__INSERTED_AT}{INSERTION_FILE} ne $Pbsfile)
			{
			die ERROR("--no_external_link switch specified, stop.\n") if(defined $pbs_config->{DEBUG_NO_EXTERNAL_LINK}) ;
				
			unless($pbs_config->{NO_LOCAL_MATCHING_RULES_INFO})
				{
				my @local_rules_matching ;
				
				for(my $matching_rule_index = 0 ; $matching_rule_index < @$dependency_rules ; $matching_rule_index++)
					{
					my ($dependency_result) = $dependency_rules->[$matching_rule_index]{DEPENDER}->($dependency_name, $config, $inserted_nodes->{$dependency_name}, $inserted_nodes, $dependency_rules->[$matching_rule_index]) ;
					push @local_rules_matching, $matching_rule_index if($dependency_result->[0]) ;
					}
				
				if(exists $inserted_nodes->{$dependency_name}{__DEPENDED} && @local_rules_matching)
					{
					my @local_rules_matching_info ;
					
					for my $matching_rule_index (@local_rules_matching)
						{
						push @local_rules_matching_info, 
							"$matching_rule_index:"
							. $dependency_rules->[$matching_rule_index]{NAME}
							. $dependency_rules->[$matching_rule_index]{ORIGIN} ;
						}
					
					$linked_node_info .= "         Ignoring local matching rules from '$Pbsfile': " . join(', ', @local_rules_matching_info) . "\n" ;
					$display_linked_node_info++ ;
					}
				}
			}
			
		PrintWarning $linked_node_info if $display_linked_node_info ;
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
			$DB::single = 1 if(PBS::Debug::CheckBreakpoint(%debug_data, PRE => 1)) ;
			}
		
		tie my %dependency_tree_hash, "Tie::Hash::Indexed" ;
		
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
		$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, POST => 1)) ;
		}
	}
	
if(@has_matching_non_subpbs_rules)
	{
	if(@sub_pbs)
		{
		PrintError DumpTree(\@has_matching_non_subpbs_rules, "In Pbsfile : $Pbsfile, $node_name has locally matching rules:") ;
		PrintError(DumpTree(\@sub_pbs, "And matching Sub Pbs definition:")) ;
			
		Carp::croak ;
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
			$key_name .= $rule->[0] . ' ' . $rule->[1] ;
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
			
		unless(exists $tree->{$dependency}{__DEPENDED})
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
else
	{
	if(@sub_pbs)
		{
		if(@sub_pbs != 1)
			{
			PrintError "Depend: in pbsfile : $Pbsfile, $node_name has multiple subpbs defined:\n" ;
			PrintError(DumpTree(\@sub_pbs,, "Sub Pbs:")) ;
			
			Carp::croak  ;
			}
			
		# the node had no dependencie but a single subpbs matched
		
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
				my $node_info = "inserted at '$inserted_nodes->{$node_name}->{__INSERTED_AT}{INSERTION_RULE}'" ;
				PrintWarning("[$PBS::PBS::pbs_runs/$PBS::Output::indentation_depth] Depend: '$node_name' $alias_message, $node_info, with subpbs '$sub_pbs_package:$sub_pbs_name'.\n") ;
				}
			else
				{
				PrintWarning("Depend: '$node_name' $alias_message with subpbs '$sub_pbs_package:$sub_pbs_name'.\n") ;
				}
			}
			
		#-------------------------------------------------------------
		# run subpbs
		#-------------------------------------------------------------
		
		delete $inserted_nodes->{$node_name} ; # temporarily eliminate ourself from the existing nodes list
		
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
			# keep some  attributes defined from the current Pbs
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
		next if $node_name =~ /^__/ ;
		my $dependency_info = '' ;

		if($pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} && $node_name_matches_ddrr)
			{
			if(PBS::Digest::IsDigestToBeGenerated($load_package, $tree))
				{
				if( ! $has_dependencies)
					{
					if(@{$tree->{__MATCHING_RULES}})
						{
						$dependency_info = "'$node_name' has no locally defined dependencies" ;
						}
					else
						{
						$dependency_info = "'$node_name' wasn't depended" ;
						}
						
					PrintWarning "$dependency_info (rules from '$pbs_config->{PBSFILE}').\n" ;
					}
				}
			else
				{
				#source
				if(@{$tree->{__MATCHING_RULES}})
					{
					PrintWarning "Depend: '$node_name' matched rules, rules from '$pbs_config->{PBSFILE}'.\n" ;
					}
					
				if($has_dependencies)
					{
					PrintWarning2 "Depend: '$node_name' has dependencies, rules from '$pbs_config->{PBSFILE}'.\n" ;
					}
				}
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
		
	$DB::single = 1 if (PBS::Debug::CheckBreakpoint(%debug_data)) ;
	}
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
any pertinent information it gathers in the node.

=head2 EXPORT

None by default.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut

