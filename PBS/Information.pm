
package PBS::Information ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GetCloseMatches DisplayCloseMatches) ;
our $VERSION = '0.04' ;

use Data::TreeDumper ;
use List::Util qw(any) ;

use PBS::Output ;
use PBS::Constants ;
use PBS::Rules ;
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
	
$type .= PBS::Build::NodeBuilderUsesPerlSubs($file_tree) ? '<P> ' : '<S> '
	if $pbs_config->{DISPLAY_BUILDER_INFORMATION} ;

my $tab = $PBS::Output::indentation ;
	
use Term::Size::Any qw(chars) ;

my $terminal_width = chars() || 10_000 ;

my $node_header = '' ;

$node_header .= $pbs_config->{DISPLAY_NODE_BUILD_NAME}
			? _INFO3_("Node: $type'$name':") . _INFO2_(" $build_name\n")
			: _INFO3_ "Node: $type'$name':\n" ;
	
return $node_header, $type, $tab ;
}

#-------------------------------------------------------------------------------------------------------

sub GetNodeInformation
{
my ($file_tree, $pbs_config, $generate_for_log, $inserted_nodes) = @_ ;
my ($current_node_info, $log_node_info, $node_info) = ('', '', '') ;

my ($name, $build_name) = ($file_tree->{__NAME}, $file_tree->{__BUILD_NAME} || '') ;
my ($node_header, $type, $tab) = GetNodeHeader($file_tree, $pbs_config) ;

my $no_output = $pbs_config->{DISPLAY_NO_BUILD_HEADER} ;

$node_info .= $node_header unless $no_output ;
$log_node_info .= $node_header ;

#----------------------
# is source
#----------------------
if(NodeIsSource($file_tree))
	{
	$current_node_info = WARNING2 "${tab}Type: 'source node', source node must exist not be generated.\n\n" ;
	$log_node_info .= $current_node_info ;
	$node_info     .= $current_node_info ;
	}

#----------------------
# insertion origin
#----------------------
if ($generate_for_log || $pbs_config->{DISPLAY_NODE_ORIGIN})
	{
	$current_node_info = '' ;

	if(exists $file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}) # inserted and depended in different pbsfiles
		{
		my $inserted = $file_tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} ;
		my $origin = "${tab}Originated at rule: " 
				. ($pbs_config->{ADD_ORIGIN} 
					? $inserted->{INSERTION_RULE} 
					: "$inserted->{INSERTION_RULE_NAME}:$inserted->{INSERTION_FILE}"
						. ($inserted->{INSERTION_RULE_NAME} eq '__ROOT'
							? ''
							: ":$inserted->{INSERTION_RULE_LINE}")
				  ) ;

		$current_node_info = INFO2 "$origin\n" ;
		}

	my $inserted = "${tab}Inserted at rule: "
			. ($pbs_config->{ADD_ORIGIN} 

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
if ($generate_for_log || (($pbs_config->{DISPLAY_NODE_PARENTS} || $pbs_config->{DISPLAY_NODE_ORIGIN}) && ! $pbs_config->{DISPLAY_NO_NODE_PARENTS}))
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

							my $file = exists $inserted_nodes->{$link}{__BUILD_NAME}
									? "$inserted_nodes->{$link}{__BUILD_NAME}.pbs_log"
									: '' ;

							my $file_link = INFO2 "node info: $file" ;
							
							# set children node info links
							$tree->{$_}{$file_link} = [] ;
							}
						}

					return ('HASH', undef, sort { $b =~ /node info:/ } grep { ! /node info/ unless $depth} grep { ! /^__/} keys %$tree) ;
					}
				
				return Data::TreeDumper::DefaultNodesToDisplay($tree) ;
				} ;

	$current_node_info = INFO DumpTree
					$file_tree->{__DEPENDENCY_TO},
					"Dependents:",
					FILTER => $parent_tree,
					DISPLAY_ADDRESS => 0, INDENTATION => $tab, USE_ASCII => 1, NO_NO_ELEMENTS => 1 ;

	$log_node_info .= $current_node_info . "\n" ;
	$node_info     .= $current_node_info . "\n" if $pbs_config->{DISPLAY_NODE_PARENTS} || $pbs_config->{DISPLAY_NODE_ORIGIN} ;
 	}

#----------------------
# environment variables
#----------------------
for my $node_env_regex (@{$pbs_config->{DISPLAY_NODE_ENVIRONMENT}})
	{
	my $matching_env = sub
				{
				my ($tree) = @_ ;
				
				if('HASH' eq ref $tree)
					{
					return
						(
						'HASH', undef, 
						sort grep 
							{
							my $key = $_ ;
							any { $key =~ /$_/ } @{$pbs_config->{NODE_ENVIRONMENT_REGEX}} ;
							} keys %$tree
						) ;
					}
				
				return Data::TreeDumper::DefaultNodesToDisplay($tree) ;
				} ;

	if($name =~ /$node_env_regex/)
		{
		$current_node_info = INFO DumpTree( \%ENV, "ENV:", FILTER => $matching_env, DISPLAY_ADDRESS => 0, INDENTATION => $tab, USE_ASCII => 1) ;
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info ;
		}
	}

#----------------------
# dependencies
#----------------------
my (%triggered_dependencies) ;

if ($generate_for_log || $pbs_config->{DISPLAY_NODE_DEPENDENCIES} || $pbs_config->{DISPLAY_NODE_BUILD_CAUSE})
	{
	if(exists $file_tree->{__TRIGGERED})
		{
		for my $triggered_dependency_data (@{$file_tree->{__TRIGGERED}})
			{
			$triggered_dependencies{$triggered_dependency_data->{NAME}} = $triggered_dependency_data->{REASON} ;
			}
		}

	$current_node_info = INFO "${tab}Dependencies:\n" ;

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
			my $cache = $inserted_nodes->{$_}{__WARP_NODE} && $pbs_config->{NODE_CACHE_INFORMATION} ? _INFO2_('ᶜ') : '' ;

			$current_node_info .= "${tab}${tab}"
						. 	(
							exists $triggered_dependencies{$_} || $file_tree->{$_}{__TRIGGERED}
								? _ERROR_ $_ . $cache . "\n"
								: $inserted_nodes->{$_}{__IS_SOURCE} || NodeIsSource($inserted_nodes->{$_})
									? _WARNING_ $_ . $cache . "\n"
									: _INFO3_   $_ . $cache . "\n"
							)
						 if $pbs_config->{DISPLAY_NODE_DEPENDENCIES} ;
			}
		
		if
			(
			(! $inserted_nodes->{$_}{__WARP_NODE} ) # Warp nodes are like source we know little about them except that their digests checked
			&& NodeIsGenerated($inserted_nodes->{$_})
			&& ! $pbs_config->{NO_NODE_INFO_LINKS}
			) 
			{
			my $file_link = INFO2 "node info: $inserted_nodes->{$_}{__BUILD_NAME}.pbs_info" ;
			$current_node_info .= "${tab}${tab}$file_link\n" ;
			}
		}

	# remaining triggers
	$current_node_info .= ERROR "${tab}${tab}$_: $triggered_dependencies{$_}\n" 
		for sort keys %triggered_dependencies ;
		
	$log_node_info .= $current_node_info ;
	$node_info     .= $current_node_info if $pbs_config->{DISPLAY_NODE_DEPENDENCIES} || $pbs_config->{DISPLAY_NODE_BUILD_CAUSE} ;
	}

#----------------------
# matching rules
#----------------------
my @rules_with_builders ;

if(($generate_for_log || $pbs_config->{DISPLAY_NODE_BUILD_RULES}) && ! $pbs_config->{DISPLAY_NO_NODE_BUILD_RULES} )
	{
	my @matching_rules = @{$file_tree->{__MATCHING_RULES}} ;

	for my $rule (@matching_rules)
		{
		my $rule_number     = $rule->{RULE}{INDEX} ;
		my $rule_definition = $rule->{RULE}{DEFINITIONS}[$rule_number] ;
		
		push @rules_with_builders, {INDEX => $rule_number, DEFINITION => $rule_definition }
			if defined $rule_definition->{BUILDER} ;
			
		my $rule_dependencies ;
					
		if(@{$rule->{DEPENDENCIES}})
			{
			$rule_dependencies = 
				"\n${tab}${tab}${tab}=> "
				. join( ' ', 
					map 	
						{
						my $cache = $inserted_nodes->{$_}{__WARP_NODE} && $pbs_config->{NODE_CACHE_INFORMATION} ? _INFO2_('ᶜ') : '' ;
 
						exists $triggered_dependencies{$_} || $file_tree->{$_}{__TRIGGERED}
							? _ERROR_ $_ . $cache
							: $inserted_nodes->{$_}{__IS_SOURCE} || NodeIsSource($inserted_nodes->{$_})
								? _WARNING_ $_ . $cache
								: _INFO3_   $_ . $cache
							if $pbs_config->{DISPLAY_NODE_DEPENDENCIES} ;
						}
						map { $_->{NAME} } @{$rule->{DEPENDENCIES}})
				. "\n" ;
			}
		else
			{
			$rule_dependencies = " => no dependencies\n" ;
			}

		my $rule_tag = GetRuleTypes($rule_definition) ;
		$rule_tag = _WARNING_ $rule_tag if $rule_tag =~ 'BO' ;
		
		my $rule_info = $rule_definition->{NAME}
					. ($pbs_config->{ADD_ORIGIN} 
						? $rule_definition->{ORIGIN}

						: ':' . $rule_definition->{FILE}
						  .':' . $rule_definition->{LINE}
					  ) ;
							
		my $rule_index = @matching_rules > 1 ? "#$rule_number" : '' ;

		$current_node_info =  INFO "${tab}${tab}rule: ${rule_index} $rule_tag " . _INFO_(GetRunRelativePath($pbs_config, $rule_info)) ;
		$current_node_info .= INFO2 $rule_dependencies ;
		
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info ;
		}

	unless(@{$file_tree->{__MATCHING_RULES}})
		{
		my $current_node_info = _WARNING_("${tab}No matching rule\n") ;
		$log_node_info .= $current_node_info ;
		$node_info     .= $current_node_info ;
		}
	}

#----------------------
# builder
#----------------------
my ($has_bo, $builder)  = (0) ;

for my $rule (@rules_with_builders)
	{
	my $rule_tag = GetRuleTypes($rule->{DEFINITION}) ;
	$rule_tag .= "[P]" if exists $rule->{DEFINITION}{COMMANDS_RUN_CODE} ;

	my $rule_info = "#$rule->{INDEX}$rule_tag "
			. $rule->{DEFINITION}{NAME} . ':'
			. GetRunRelativePath($pbs_config, $rule->{DEFINITION}{FILE}) . ':'
			. $rule->{DEFINITION}{LINE} ;
	
	# display used builder and possible overrides
	my $current_node_info = '' ;
	
	my $is_bo = any { BUILDER_OVERRIDE eq $_ } @{$rule->{DEFINITION}{TYPE}} ;

	if(! defined $builder)
		{
		$has_bo++ if $is_bo ;
		
		$builder = $rule->{DEFINITION}{BUILDER} ;
		$current_node_info .= INFO "${tab}Build: using builder, rule: $rule_info\n" ;
		}
	else
		{
		if($is_bo)
			{
			$builder = $rule->{DEFINITION}{BUILDER} ;
			$has_bo++ ;

			$current_node_info = $node_header if $no_output ; # force a header  when displaying a warning
			$current_node_info .= WARNING "${tab}Build: using override builder rule: $rule_info\n" ;
			}
		elsif($has_bo)
			{
			$current_node_info = $node_header if $no_output ;
			$current_node_info .= WARNING "${tab}Build: ignoring builder, rule: $rule_info\n" ;
			}
		else
			{
			$current_node_info .= WARNING "${tab}Build: using later defined builder, rule: $rule_info\n" ;
			$builder = $rule->{DEFINITION}{BUILDER} ;
			}
		}

	$log_node_info .= $current_node_info ;
	$node_info     .= $current_node_info ;
	}

#----------------------
# node config
#----------------------
if (($generate_for_log || $pbs_config->{DISPLAY_NODE_CONFIG}) && defined $file_tree->{__CONFIG})
	{
	my $config = INFO DumpTree($file_tree->{__CONFIG}, "Config:", DISPLAY_ADDRESS => 0, INDENTATION => $tab, USE_ASCII => 1) ;

	$log_node_info .= $config ;
	$node_info .= $config if $pbs_config->{DISPLAY_NODE_CONFIG} ;
	}

#-------------------------
#display shell  if any
#-------------------------
if(exists $pbs_config->{DISPLAY_BUILD_INFO} && @{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	#display shell if any
	}
	
#----------------------
# post build
#----------------------
if($generate_for_log || $pbs_config->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS})
	{
	if($file_tree->{__POST_BUILD_COMMANDS})
		{
		$current_node_info = INFO "${tab}Post Build Commands:\n" ;
		
		for my $post_build_command (@{$file_tree->{__POST_BUILD_COMMANDS}})
			{
			my $rule_info = $post_build_command->{NAME} . $post_build_command->{ORIGIN} ;

			$current_node_info .= INFO "${tab}${tab}$rule_info\n" ;
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

if($pbs_config->{BUILD_AND_DISPLAY_NODE_INFO} || $pbs_config->{BUILD_NODE_INFO} || $pbs_config->{DISPLAY_BUILD_INFO})
	{
	my ($node_info) = GetNodeInformation($file_tree, $pbs_config, $generate_for_log, $inserted_nodes) ;
	PrintNoColor "$node_info\n" ;
	}
}

#----------------------------------------------------------------------

sub GetCloseMatches     { grep { $_[1]->{$_}{__NAME} =~ /$_[0]/ } keys %{$_[1]} }
sub DisplayCloseMatches { PrintInfo2 "PBS: found:\n\t" . join("\n\t", GetCloseMatches(@_)) }

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
