
package PBS::Information ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(DisplayCloseMatches) ;
our $VERSION = '0.04' ;

use PBS::Output ;
use PBS::Constants ;
use PBS::Digest ;
use PBS::Depend ;

#-------------------------------------------------------------------------------

sub GetNodeHeader
{
my ($file_tree, $pbs_config) = @_ ;

my ($name, $build_name) = ($file_tree->{__NAME}, $file_tree->{__BUILD_NAME} || '') ;

#----------------------
# header
#----------------------

my $type = '' ;
if($file_tree->{__VIRTUAL} || $file_tree->{__FORCED} || $file_tree->{__WARP_NODE} || $file_tree->{__LOCAL})
	{
	$type .= '[' ;
	$type .= 'V' if($file_tree->{__VIRTUAL}) ;
	$type .= 'F' if($file_tree->{__FORCED}) ;
	$type .= 'L' if($file_tree->{__LOCAL}) ;
	$type .= 'W' if($file_tree->{__WARP_NODE}) ;
	$type .= '] ' ;
	}
	
if($pbs_config->{DISPLAY_BUILDER_INFORMATION})
	{
	if(PBS::Build::NodeBuilderUsesPerlSubs($file_tree))
		{
		$type .= '<P> ' ;
		}
	else
		{
		$type .= '<S> ' ;
		}
	}

my $tab = $PBS::Output::indentation ;
	
use Term::Size::Any qw(chars) ;

my $terminal_width = chars() || 10_000 ;

my $columns = length("Node: $type'$name':") ;
$columns = $columns < $terminal_width ? $columns : $terminal_width ;

my $separator = WARNING ('-' x $columns . "\n")  ;

my $node_header = "\n" ;

if(defined $pbs_config->{DISPLAY_NODE_BUILD_NAME})
	{
	$node_header .= WARNING("Node: $type'$name': ", 0) . INFO2("[$build_name]", 0) . "\n" ;
	}
else
	{
	$node_header .= WARNING("Node: $type'$name':", 0) . "\n" ;
	}
	
$node_header .= $separator ;

return $node_header, $type, $tab ;
}

sub GetNodeInformation
{
my ($file_tree, $pbs_config, $generate_for_log, $inserted_nodes) = @_ ;
my ($current_node_info, $log_node_info, $node_info) = ('', '', '') ;

my ($name, $build_name) = ($file_tree->{__NAME}, $file_tree->{__BUILD_NAME} || '') ;
my ($node_header, $type, $tab) = GetNodeHeader($file_tree, $pbs_config) ;

my $no_output = defined $pbs_config->{DISPLAY_NO_BUILD_HEADER} ;

$node_info .= $node_header unless $no_output ;
$log_node_info .= $node_header ;

#----------------------
# insertion origin
#----------------------
if ($generate_for_log ||  $pbs_config->{DISPLAY_NODE_ORIGIN})
	{
	if(exists $file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}) # inserted and depended in different pbsfiles
		{
		my $origin = "${tab}Originated at rule: " 
				. (defined $pbs_config->{ADD_ORIGIN} 

					? "$file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE}" 

					: "$file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE_NAME}"
					  . ":$file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_FILE}"

					# __ROOT rules are automatically added by pbs when depending a node a subpbs
					# it's not part of the user written subpbs
					  . ($file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE_NAME} eq '__ROOT'
						? ''
						: ":$file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE_LINE}")
				  ) ;

		$current_node_info = INFO2 "$origin\n" ;
		}

	my $inserted = "${tab}Inserted at rule: "
			. (defined $pbs_config->{ADD_ORIGIN} 

				? "$file_tree->{__INSERTED_AT}{INSERTION_RULE}"

				: "$file_tree->{__INSERTED_AT}{INSERTION_RULE_NAME}"
				  . ":$file_tree->{__INSERTED_AT}{INSERTION_RULE_FILE}"
				  . ($file_tree->{__INSERTED_AT}{INSERTION_RULE_NAME} eq 'PBS'
					? ''
					: ":$file_tree->{__INSERTED_AT}{INSERTION_RULE_LINE}")
				) ;

	$current_node_info .= INFO "$inserted\n" ;
	$current_node_info .= INFO "${tab}Pbsfile:$file_tree->{__INSERTED_AT}{INSERTION_FILE}\n\n"
				 unless $file_tree->{__INSERTED_AT}{INSERTION_RULE_FILE} eq $file_tree->{__INSERTED_AT}{INSERTION_FILE} ;
	
	$log_node_info .= $current_node_info ;
	$node_info     .= $current_node_info 
	}

#----------------------
# parents
#----------------------
if ($generate_for_log || $pbs_config->{DISPLAY_NODE_PARENTS} || $pbs_config->{DISPLAY_NODE_ORIGIN})
	{
	#$current_node_info = INFO "\tDependents:" . join(', ',  GetParentsNames($file_tree)) . "\n" ;

	my $parent_tree = sub
				{
				my ($tree, $depth) = @_ ;
				
				if('HASH' eq ref $tree)
					{
					for (grep {'HASH' eq ref $tree->{$_} && ! /^__/} keys %$tree)
						{
						unless($pbs_config->{NO_NODE_INFO_LINKS})
							{
							my ($link) = /^([^:]*)/ ;
							my $file_link = INFO2("node info: $inserted_nodes->{$link}{__BUILD_NAME}.pbs_log") ;
							
							# set children node info links
							$tree->{$_}{$file_link} = [] ;
							}
						}

					return ('HASH', undef, sort { $b =~ /node info:/ } grep { ! /node info/ unless $depth} grep { ! /^__/} keys %$tree) ;
					}
				
				return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
				} ;

	$current_node_info =
		INFO
			DumpTree
				(
				$file_tree->{__DEPENDENCY_TO},
				"Dependents:",
				FILTER => $parent_tree,
				DISPLAY_ADDRESS => 0, INDENTATION => $tab, USE_ASCII => 1, NO_NO_ELEMENTS => 1,
				) ;

	$log_node_info .= $current_node_info . "\n" ;
	$node_info     .= $current_node_info . "\n" ;
	}

#----------------------
# environment variables
#----------------------
for my $node_env_regex (@{$pbs_config->{DISPLAY_NODE_ENVIRONMENT}})
	{
	my $matching_env = sub
				{
				my $tree = shift ;
				
				if('HASH' eq ref $tree)
					{
					return
						(
						'HASH', undef, 
						sort grep 
							{
							my $match = 0 ;
							for my $env_regex (@{$pbs_config->{NODE_ENVIRONMENT_REGEX}})
								{
								do { $match++ ; last }  if /$env_regex/
								}
								
							$match ;
							} keys %$tree
						) ;
					}
				
				return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
				} ;

	if($name =~ /$node_env_regex/)
		{
		$current_node_info = INFO( DumpTree( \%ENV, "ENV:", FILTER => $matching_env, DISPLAY_ADDRESS => 0, INDENTATION => $tab, USE_ASCII => 1) ) ;
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info ;
		
		last ;
		}
	}

#----------------------
# dependencies
#----------------------
if ($generate_for_log ||  $pbs_config->{DISPLAY_NODE_DEPENDENCIES} || $pbs_config->{DISPLAY_NODE_BUILD_CAUSE})
	{
	my (%triggered_dependencies) ;

	if(exists $file_tree->{__TRIGGERED})
		{
		for my $triggered_dependency_data (@{$file_tree->{__TRIGGERED}})
			{
			next if(ref $triggered_dependency_data eq 'PBS_FORCE_TRIGGER') ;
			
			$triggered_dependencies{$triggered_dependency_data->{NAME}} = $triggered_dependency_data->{REASON} ;
			}
		}

	$current_node_info = INFO("${tab}Dependencies:\n") ;

	for (sort keys %$file_tree)
		{
		next if 0 == index($_, '__') ;
		
		if(exists $triggered_dependencies{$_})
			{
			$current_node_info .= ERROR "${tab}${tab}$_: $triggered_dependencies{$_}\n" ;
			delete $triggered_dependencies{$_}
			}
		else
			{
			$current_node_info .= INFO3 "${tab}${tab}$_\n" if($pbs_config->{DISPLAY_NODE_DEPENDENCIES}) ;
			}
		
		if
			(
			(! $inserted_nodes->{$_}{__WARP_NODE} ) # Warp nodes are like source we know little about them except that their digests checked
			&& PBS::Digest::IsDigestToBeGenerated($inserted_nodes->{$_}{__LOAD_PACKAGE}, $inserted_nodes->{$_})
			&& ! $pbs_config->{NO_NODE_INFO_LINKS}
			) 
			{
			my $file_link = INFO2("node info: $inserted_nodes->{$_}{__BUILD_NAME}.pbs_info") ;
			$current_node_info .= "${tab}${tab}$file_link\n" ;
			}
		}

	# remaining triggers
	$current_node_info .= ERROR("${tab}${tab}$_: $triggered_dependencies{$_}\n") 
		for keys %triggered_dependencies ;
		
	$log_node_info .= $current_node_info ;
	$node_info     .= $current_node_info ;
	}

#----------------------
# matching rules
#----------------------
my @rules_with_builders ;
my $builder = 0 ;

if($generate_for_log || $pbs_config->{DISPLAY_NODE_BUILD_RULES})
	{
	my $builder_override ;
	
	for my $rule (@{$file_tree->{__MATCHING_RULES}})
		{
		my $rule_number = $rule->{RULE}{INDEX} ;
		my $dependencies_and_build_rules = $rule->{RULE}{DEFINITIONS} ;
		
		$builder          = $dependencies_and_build_rules->[$rule_number]{BUILDER} ;
		$builder_override = $rule->{RULE}{BUILDER_OVERRIDE} ;
		
		my $builder_override_tag ;
		if(defined $builder_override)
			{
			if(defined $builder_override->{BUILDER})
				{
				$builder_override_tag = '[BO]' ;
				
				my $rule_info =
					{
					INDEX => $rule_number,
					DEFINITION => $builder_override,
					} ;
					
				$rule_info->{OVERRIDES_OWN_BUILDER}++ if($builder);
				
				push @rules_with_builders, $rule_info ;
				}
			else
				{
				$builder_override_tag = '[B] = undef! in Override]' ;
				}
			}
		else
			{
			push @rules_with_builders, {INDEX => $rule_number, DEFINITION => $dependencies_and_build_rules->[$rule_number] }
				if(defined $builder) ;
			}
			
		my $rule_dependencies ;
		if(@{$rule->{DEPENDENCIES}})
			{
			$rule_dependencies = join ' ', map {$_->{NAME}} @{$rule->{DEPENDENCIES}} ;
			}
		else
			{
			$rule_dependencies = 'no derived dependency' ;
			}
			
		my $rule_tag = '' ;
		$rule_tag .= '[B]'  if defined $builder ;
		$rule_tag .= '[BO]' if defined $builder_override ;
		$rule_tag .= '[S]'  if defined $file_tree->{__INSERTED_AT}{NODE_SUBS} ;
		#~ $rule_tag .= '[CREATOR]' if $creator;
		
		my $rule_info = $dependencies_and_build_rules->[$rule_number]{NAME}
					. (defined $pbs_config->{ADD_ORIGIN} 
						? $dependencies_and_build_rules->[$rule_number]{ORIGIN}

						: ':' . $dependencies_and_build_rules->[$rule_number]{FILE}
						  .':' . $dependencies_and_build_rules->[$rule_number]{LINE}
					  ) ;
							
		$current_node_info = INFO ("${tab}Matching rule: #$rule_number$rule_tag '$rule_info'\n") ;
		$current_node_info .= INFO3 ("${tab}${tab}=> $rule_dependencies\n") ;
		
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info ;
		}
	}

#----------------------
# node config
#----------------------
if (($generate_for_log || $pbs_config->{DISPLAY_NODE_CONFIG}) && defined $file_tree->{__CONFIG})
	{
	my $config = INFO(DumpTree($file_tree->{__CONFIG}, "Node config:", INDENTATION => $tab, USE_ASCII => 1)) ;

	$log_node_info .= $config ;
	$node_info .= $config ;
	}

#----------------------
# builder
#----------------------
if($generate_for_log || $pbs_config->{DISPLAY_NODE_BUILDER})
	{
	my $more_than_one_builder = 0 ;

	# choose last builder if multiple Builders
	if(@rules_with_builders)
		{
		my $rule_used_to_build = $rules_with_builders[-1] ;
		   $builder            = $rule_used_to_build->{DEFINITION}{BUILDER} ;
		
		my $rule_tag = '' ;
		unless(exists $rule_used_to_build->{DEFINITION}{SHELL_COMMANDS_GENERATOR})
			{
			$rule_tag = "[P]" ;
			}
			
		my $rule_info = $rule_used_to_build->{INDEX} 
				. $rule_tag . ' '
				. $rule_used_to_build->{DEFINITION}{NAME}
				. ( $pbs_config->{ADD_ORIGIN}
					? $rule_used_to_build->{DEFINITION}{ORIGIN}
					: ":" . $rule_used_to_build->{DEFINITION}{FILE}
					  . ":" . $rule_used_to_build->{DEFINITION}{LINE} ) ;
							
		$current_node_info = INFO ("${tab}Using builder from rule: #$rule_info\n") ;
		
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info
		}
	}

#-----------------------------------------
# display override information
#-----------------------------------------
if(@rules_with_builders)
	{
	for my $rule (@rules_with_builders)
		{
		# display override information
		
		my $rule_info = $rule->{DEFINITION}{NAME} . $rule->{DEFINITION}{ORIGIN} ;
		
		my $overriden_rule_info = '' ;
		for my $overriden_rule_type (@{$rule->{DEFINITION}{TYPE}})
			{
			if(CREATOR eq $overriden_rule_type)
				{
				$overriden_rule_info .= '[CREATOR] ' ;
				}
			}
			
		# display if the rule generated a  builder override and had builder in its definition.
		my $current_node_info = '' ;
		
		if($rule->{OVERRIDES_OWN_BUILDER} || $rule->{DEFINITION}{BUILDER} != $builder)
			{
			$current_node_info = $node_header if $no_output ; # force a header  when displaying a warning
			}
			
		if($rule->{OVERRIDES_OWN_BUILDER})
			{
			$current_node_info .= WARNING ("${tab}Rule Overrides its own builder: $overriden_rule_info#$rule->{INDEX} '$rule_info'.\n") ;
			}
			
		if($rule->{DEFINITION}{BUILDER} != $builder)
			{
			# override from a rule to another
			$current_node_info .= WARNING ("${tab}Ignoring Builder from rule: $overriden_rule_info#$rule->{INDEX} '$rule_info'.\n") ;
			}
			
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info ;
		}
	}

#-------------------------------------------------
#display shell and commands if any
#-------------------------------------------------
if(exists $pbs_config->{DISPLAY_BUILD_INFO} && @{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	#display shell and commands if any
	}
	
#----------------------
# post build
#----------------------
if($generate_for_log || $pbs_config->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS})
	{
	if(defined $file_tree->{__POST_BUILD_COMMANDS})
		{
		$current_node_info = INFO ("${tab}Post Build Commands:\n") ;
		
		for my $post_build_command (@{$file_tree->{__POST_BUILD_COMMANDS}})
			{
			my $rule_info = $post_build_command->{NAME}
								. $post_build_command->{ORIGIN} ;
			$current_node_info .= INFO ("${tab}${tab}$rule_info\n") ;
			}
			
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info
		}
	}

$node_info, $log_node_info
}

sub DisplayNodeInformation
{
my ($file_tree, $pbs_config, $generate_for_log, $inserted_nodes) = @_ ;

if(defined $pbs_config->{BUILD_AND_DISPLAY_NODE_INFO} || defined $pbs_config->{BUILD_NODE_INFO} || defined $pbs_config->{DISPLAY_BUILD_INFO})
	{
	my ($node_info) = GetNodeInformation($file_tree, $pbs_config, $generate_for_log, $inserted_nodes) ;
	print STDERR $node_info ;
	}
}

#----------------------------------------------------------------------

sub DisplayCloseMatches
{
# displays the nodes that match a  simple regex

my $node_name = shift ;
my $tree = shift ;

my @matches ;
for (keys %$tree)
	{
	if( $tree->{$_}{__NAME} =~ /$node_name/)
		{
		push @matches, $tree->{$_}{__NAME} ;
		}
	}

if(@matches)
	{
	PrintInfo("PBS: found nodes:\n") ;
	
	for (@matches)
		{
		PrintInfo("\t$_\n") ;
		}
	}
}

#-------------------------------------------------------------------------------

sub GetParentsNames
{
my $node = shift ;

map {/^([^:]+)/; $1} grep {! /^__/} keys %{$node->{__DEPENDENCY_TO}} ;
}

#----------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Information  -

=head1 SYNOPSIS

  use PBS::Information ;
  DisplayNodeInformation($node, $pbs_config) ;

=head1 DESCRIPTION

I<DisplayNodeInformation> print information about a node to STDERR and to the B<PBS> log. The amount of information displayed
depend on the configuration passed to the function. The configuration can be controled through I<pbs> commmand line switches.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
