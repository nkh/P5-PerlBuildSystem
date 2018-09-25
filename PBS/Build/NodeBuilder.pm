
package PBS::Build::NodeBuilder ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Path ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.02' ;

use PBS::Config ;
use PBS::Depend ;
use PBS::Check ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Digest ;
use PBS::Information ;
use PBS::PBSConfig ;

#-------------------------------------------------------------------------------

sub NodeNeedsRebuild
{
my ($node) = @_ ;

# virtual node have no digests so we can't check it
return(0) if exists $node->{__VIRTUAL} ;

local $PBS::Output::indentation_depth ;
$PBS::Output::indentation_depth += 2 ;

my ($rebuild, $reason, $number_of_differences) = PBS::Digest::IsNodeDigestDifferent($node) ;

for my $trigger (@{ $node->{__TRIGGERED} })
	{
	return(1, '__SELF') if $trigger->{NAME} eq '__SELF' ;
	}

#todo: with a well build digest, if the only difference is the pbsfile itself, and all other variables 
# identical, we can skip the build
# otherwise all the nodes in a pbsfile get rebuild even if the change has no impact on it
# note that rebuilding the graph still has to be done! The changes to the pbsfiles may not 
# have an impact on the node to build but it may have on its position in the graph

# the right way to check this is not by checking if the pbsfile only has changed
# as some changes in the pbsfile may not have impact on the node to be build
# but by comparing all the  contents of  digest, minus the pbsfile
if($number_of_differences == 1 &&  $reason->[0] =~ q{key '__DEPENDING_PBSFILE' is different} )
	{
	if((! $PBS::Shell::silent_commands))
		{
		#PrintWarning "Node doesn't need to be build. Only Pbsfile difference.\n" ;
		}
	
	#expecting people to write correct build systems is dangerous :)	
	#return(0, 'only pbsfile difference, regenerate_digest') ;
	}

my ($dependencies, $triggered_dependencies) = GetNodeDependencies($node) ;

for my $triggered_dependency (@$triggered_dependencies)
	{
	# triggered source dependencies always trigger even if they have the same md5
	my $dependency_is_generated = PBS::Digest::IsDigestToBeGenerated
					(
					$node->{$triggered_dependency}{__LOAD_PACKAGE},
					$node->{$triggered_dependency}
					) ;
	
	unless($dependency_is_generated)
		{
		$rebuild++ ;
		last ;
		}
	}
	
if($rebuild)
	{
	# build normally
	}
else
	{
	if(! $PBS::Shell::silent_commands && ! $node->{__PBS_CONFIG}{CHECK_DEPENDENCIES_AT_BUILD_TIME})
		{
		PrintWarning "No dependencie change (see --cdabt).\n" ;
		}
		
	# remember that we are using the previously generated digest.
	# the digest is in a file but this node is in memory
	# if this node is newly created (not linked from a warp tree)
	# it doesn't have an MD5 which is used in the parent node
	
	# if we don't need to be rebuild, the previous md5 is still valid
	
	if(exists $node->{__VIRTUAL})
		{
		$node->{__MD5} = 'VIRTUAL' ;
		}
	else
		{
		if(defined (my $current_md5 = GetFileMD5($node->{__BUILD_NAME})))
			{
			$node->{__MD5} = $current_md5 ;
			}
		else
			{
			if ( ! PBS::Digest::IsDigestToBeGenerated($node->{__LOAD_PACKAGE}, $node) )
				{
				if(defined (my $current_md5 = GetFileMD5($node->{__BUILD_NAME})))
					{
					$node->{__MD5} = $current_md5 ;
					}
				else
					{
					#PrintError("Can't open '$node' to compute MD5 digest: $!") ;
					$node->{__MD5} = 'Error: File not found!' ; 
					}
				}
			}
		}
	}

return($rebuild) ;

# test when one of the dependencies is virtual, all dependencies are virtual
# test when the pbsfile has changed
# test when a pbs module has changed
# test when config has changed
# o dependency caches are build but have no digest
# what if the builder is a perl sub that has changed?
}

#-------------------------------------------------------------------------------

sub BuildNode
{
my $file_tree      = shift ;
my $pbs_config     = shift ;
my $build_name     = $file_tree->{__BUILD_NAME} ;
my $inserted_nodes = shift ;
my $node_build_sequencer_info = shift ;

my $t0 = [gettimeofday];

use Data::TreeDumper ;

if(defined $pbs_config->{DISPLAY_BUILD_SEQUENCER_INFO} && ! $pbs_config->{DISPLAY_NO_BUILD_HEADER})
	{
	PrintInfo("($node_build_sequencer_info) ");
	}

if
	(
	   defined $pbs_config->{BUILD_AND_DISPLAY_NODE_INFO}
	|| defined $pbs_config->{DISPLAY_BUILD_INFO}
	)
	{
	PBS::Information::DisplayNodeInformation($file_tree, $pbs_config) ;
	}

my ($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' successfuly built.") ;	
my ($dependencies, $triggered_dependencies) = GetNodeDependencies($file_tree) ;

my $node_needs_rebuild = 1 ;

if($pbs_config->{CHECK_DEPENDENCIES_AT_BUILD_TIME})
	{
	#todo: md5 for the shell commands and perl subs should be saved in the digest
	#todo: Need to regenerate the digest with the new pbsfile
	# nothing to do

	($node_needs_rebuild, my $why) = NodeNeedsRebuild($file_tree) ;

	unless ($node_needs_rebuild)
		{
		PrintShell "Skipping node build, no dependency change\n" ;
		
		($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' successfuly skipped build.") ;	
		}
	}

if($node_needs_rebuild)
	{
	my $rules_with_builders = ExtractRulesWithBuilder($file_tree) ;
	
	if(@$rules_with_builders)
		{
		# choose last builder if multiple Builders
		my $rule_used_to_build = $rules_with_builders->[-1] ;
		
		if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
			{
			($build_result, $build_message) = (BUILD_FAILED, "Builder skipped because of --bi.") ;
			}
		else
			{
			if(exists $file_tree->{__BUILD_DONE})
				{
				PrintWarning "Build is already done: $file_tree->{__BUILD_DONE}\n" ;
				}
			else
				{
				($build_result, $build_message) 
					= RunRuleBuilder
						(
						$pbs_config,
						$rule_used_to_build,
						$file_tree,
						$dependencies,
						$triggered_dependencies,
						$inserted_nodes,
						) ;
				}
			}
		}
	else
		{
		my $reason ; 
		
		if(@{$file_tree->{__MATCHING_RULES}})
			{
			$reason .= "No builder\n" ; 
			}
		else
			{
			$reason .= "No matching rule\n"  ;
			}
		
		# show why the node was to be build
		for my $triggered_dependency_data (@{$file_tree->{__TRIGGERED}})
			{
			$reason.= "\t$triggered_dependency_data->{NAME} ($triggered_dependency_data->{REASON})\n" ;
			}
			
		$file_tree->{__BUILD_FAILED} = $reason ;
		
		($build_result, $build_message) = (BUILD_FAILED, $reason) ;
		}
	
	if($build_result == BUILD_SUCCESS)
		{
		PBS::Digest::FlushMd5Cache($build_name) ;
		
		eval { PBS::Digest::GenerateNodeDigest($file_tree) ; } ;
			
		($build_result, $build_message) = (BUILD_FAILED, "Error Generating node digest: $@") if $@ ;
		}
		
	if($build_result == BUILD_SUCCESS)
		{
		# record MD5 while the file is still fresh in theOS  file cache
		if(exists $file_tree->{__VIRTUAL})
			{
			$file_tree->{__MD5} = 'VIRTUAL' ;
			}
		else
			{
			if(defined (my $current_md5 = GetFileMD5($build_name)))
				{
				$file_tree->{__MD5} = $current_md5 ;
				}
			else
				{
				($build_result, $build_message) = (BUILD_FAILED, "Error Generating MD5 for '$build_name', $!.") ;
				}
			}
		}
	}
	
# log the build
if(defined (my $lh = $pbs_config->{CREATE_LOG}))
	{
	my $build_string = "Build result for '$build_name' : $build_result : $build_message\n" ;
	
	if($build_result == BUILD_FAILED)
		{
		print $lh ERROR $build_string ;
		}
	else
		{
		print $lh INFO $build_string ;
		}
	}
	
if($build_result == BUILD_SUCCESS)
	{
	if($pbs_config->{DISPLAY_BUILD_RESULT})
		{
		$build_message ||= '' ;
		PrintInfo("Build result for '$build_name' : $build_result : $build_message\n") ;
		}
		
	($build_result, $build_message) = RunPostBuildCommands($pbs_config, $file_tree, $dependencies, $triggered_dependencies) ;
	}
else
	{
	PrintError("\nBuilding '$build_name' : BUILD_FAILED : $build_message\n") ;
	}
	
my $build_time = tv_interval ($t0, [gettimeofday]) ;

if($build_result == BUILD_SUCCESS)
	{
	$file_tree->{__BUILD_DONE} = "BuildNode Done." ;
	$file_tree->{__BUILD_TIME} = $build_time  ;
	}

if($pbs_config->{TIME_BUILDERS} && ! $pbs_config->{DISPLAY_NO_BUILD_HEADER})
	{
	PrintInfo(sprintf("Build time: %0.3f s.\n", $build_time)) ;
	}

return($build_result, $build_message) ;
}

#-------------------------------------------------------------------------------------------------------

sub GetNodeRepositories
{
my $tree = shift ;

my @repository_paths ;

if($tree->{__NAME} =~ /^\./)
	{
	my $target_path = (File::Basename::fileparse($tree->{__NAME}))[1] ;
	$target_path =~ s~/$~~ ;
	
	for my $repository (@{$tree->{__PBS_CONFIG}->{SOURCE_DIRECTORIES}})
		{
		push @repository_paths, CollapsePath("$repository/$target_path") ;
		}
	}
	
return(@repository_paths) ;
}

#-------------------------------------------------------------------------------------------------------

sub GetNodeDependencies
{
my $file_tree = shift ;

my @dependencies ;
for my $dependency (grep { $_ !~ /^__/ ;}(keys %$file_tree))
	{
	if(exists $file_tree->{$dependency}{__BUILD_NAME})
		{
		push @dependencies, $file_tree->{$dependency}{__BUILD_NAME};
		}
	else
		{
		push @dependencies, $dependency ;
		}
	}
	
my (@triggered_dependencies, %triggered_dependencies_build_names) ;

# build a list of triggering_dependencies and weed out doublets
for my $triggering_dependency (@{$file_tree->{__TRIGGERED}})
	{
	if('PBS_FORCE_TRIGGER' eq ref $triggering_dependency )
		{
		#~ my $message = $forced_trigger->{MESSAGE} ;
		}
	else
		{
		my $dependency_name = $triggering_dependency->{NAME} ;
		
		next if $dependency_name =~ /^__/ ; #__SELF is triggering but is not a real dependency node
		
		if(exists $triggering_dependency->{__BUILD_NAME})
			{
			$dependency_name = $triggering_dependency->{__BUILD_NAME};
			}
			
		if(! exists $triggered_dependencies_build_names{$dependency_name})
			{
			push @triggered_dependencies, $dependency_name  ;
			$triggered_dependencies_build_names{$dependency_name} = $dependency_name  ;
			}
		}
	}
	
return(\@dependencies, \@triggered_dependencies) ;
}

#-------------------------------------------------------------------------------------------------------

sub RunRuleBuilder
{
my ($pbs_config, $rule_used_to_build, $file_tree, $dependencies, $triggered_dependencies, $inserted_nodes) = @_ ;

my $builder    = $rule_used_to_build->{DEFINITION}{BUILDER} ;
my $build_name = $file_tree->{__BUILD_NAME} ;
my $name       = $file_tree->{__NAME} ;

my ($build_result, $build_message) = (BUILD_SUCCESS, '') ;

# create path to the node so external commands succeed
my ($basename, $path, $ext) = File::Basename::fileparse($build_name, ('\..*')) ;
mkpath($path) unless(-e $path) ;
	
eval # rules might throw an exception
	{
	#DEBUG HOOK (see PBS::Debug)
	my %debug_data = 
		(
		TYPE                   => 'BUILD',
		CONFIG                 => $file_tree->{__CONFIG},
		NODE_NAME              => $file_tree->{__NAME},
		NODE_BUILD_NAME        => $build_name,
		DEPENDENCIES           => $dependencies,
		TRIGGERED_DEPENDENCIES => $triggered_dependencies,
		NODE                   => $file_tree,
		) ;
		
	#DEBUG HOOK, jump into perl debugger if so asked
	$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, PRE => 1)) ;
	
	($build_result, $build_message) = $builder->
						(
						$file_tree->{__CONFIG},
						$build_name,
						$dependencies,
						$triggered_dependencies,
						$file_tree,
						$inserted_nodes,
						$rule_used_to_build,
						) ;
						
	unless(defined $build_result || $build_result == BUILD_SUCCESS || $build_result == BUILD_FAILED)
		{
		$build_result = BUILD_FAILED ;
		
		my $rule_info = "'" . $rule_used_to_build->{DEFINITION}{NAME} . "' at '"
			. $rule_used_to_build->{DEFINITION}{FILE}  . ":"
			. $rule_used_to_build->{DEFINITION}{LINE}  . "'" ;
			
		$build_message = "Builder $rule_info didn't return a valid build result!" ;
		}
		
	$build_message ||= 'no message returned by builder' ;
	
	#DEBUG HOOK
	$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, POST => 1, BUILD_RESULT => $build_result, BUILD_MESSAGE => $build_message)) ;
	} ;

if($@)
	{
	if('' ne ref $@ && $@->isa('PBS::Shell'))
		{
		$build_result = BUILD_FAILED ;
		
		$build_message = "\n\t" . $@->{error} . "\n" ;
		$build_message .= "\tCommand   : '" . $@->{command} . "'\n" if defined $PBS::Shell::silent_commands ;
		$build_message .=  "\tErrno     : " . $@->{errno} . "\n\tErrno text: " . $@->{errno_string} . "\n" ;
		}
	else
		{
		$build_result = BUILD_FAILED ;
		
		my $rule_info = 
			"'" . $rule_used_to_build->{DEFINITION}{NAME} . "' at '"
			. $rule_used_to_build->{DEFINITION}{FILE}  . ":"
			. $rule_used_to_build->{DEFINITION}{LINE}  . "'" ;
		
		$build_message = "\n\t Building $build_name '$rule_info': Exception type: $@" ;
		}
	}

if($build_result == BUILD_FAILED)
	{
	#~ PrintInfo("Removing '$build_name'.\n") ;
	unlink($build_name) if PBS::Digest::IsDigestToBeGenerated($file_tree->{__LOAD_PACKAGE}, $file_tree) ;
		
	my $rule_info =  $rule_used_to_build->{DEFINITION}{NAME}
			. $rule_used_to_build->{DEFINITION}{ORIGIN} ;
			
	$build_message .="\n\tBuilder: #$rule_used_to_build->{INDEX} '$rule_info'.\n" ;
	$file_tree->{__BUILD_FAILED} = $build_message ;
	}

return($build_result, $build_message) ;
}

#-------------------------------------------------------------------------------------------------------

sub ExtractRulesWithBuilder
{
my ($file_tree) = @_ ;

# returns a list with elements following this format:
# {INDEX => rule_number, DEFINITION => rule } ;

my @rules_with_builders ;
for my $rule (@{$file_tree->{__MATCHING_RULES}})
	{
	my $rule_number = $rule->{RULE}{INDEX} ;
	my $dependencies_and_build_rules = $rule->{RULE}{DEFINITIONS} ;
	
	my $builder = $dependencies_and_build_rules->[$rule_number]{BUILDER} ;
	
	# change the name of this variable as it is a rule now not a builder
	my $builder_override  = $rule->{RULE}{BUILDER_OVERRIDE} ;
	my $rule_dependencies = join ' ', map {$_->{NAME}} @{$rule->{DEPENDENCIES}} ;
	
	if(defined $builder_override)
		{
		if(defined $builder_override->{BUILDER})
			{
			push @rules_with_builders,
				{
				INDEX => $rule_number,
				DEFINITION => $builder_override,
				} ;
			}
		else
			{
			my $info = 
				"'" . $builder_override->{NAME} . "' at  '"
				. $builder_override->{FILE}  . ":"
				. $builder_override->{LINE}  . "'" ;
				
			PrintError "\nBuilder override $info didn't define a builder!\n" ;
			PbsDisplayErrorWithContext($builder_override->{FILE}, $builder_override->{LINE}) ;
			}
		}
	else
		{
		if(defined $builder)
			{
			push @rules_with_builders, {INDEX => $rule_number, DEFINITION => $dependencies_and_build_rules->[$rule_number] } ;
			}
		}
	}
	
return(\@rules_with_builders) ;
}

#-------------------------------------------------------------------------------------------------------

sub RunPostBuildCommands
{
my ($pbs_config, $file_tree, $dependencies, $triggered_dependencies, $inserted_nodes) = @_ ;

my $build_name = $file_tree->{__BUILD_NAME} ;
my $name       = $file_tree->{__NAME} ;

my ($build_result, $build_message) = (BUILD_SUCCESS, '') ;

for my $post_build_command (@{$file_tree->{__POST_BUILD_COMMANDS}})
	{
	eval
		{
		#DEBUG HOOK
		my %debug_data = 
			(
			TYPE                   => 'POST_BUILD',
			CONFIG                 => $file_tree->{__CONFIG},
			NODE_NAME              => $file_tree->{__NAME},
			NODE_BUILD_NAME        => $build_name,
			DEPENDENCIES           => $dependencies,
			TRIGGERED_DEPENDENCIES => $triggered_dependencies,
			ARGUMENTS              => \$post_build_command->{BUILDER_ARGUMENTS},
			NODE                   => $file_tree,
			) ;
		
		#DEBUG HOOK
		$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, PRE => 1)) ;
		
		($build_result, $build_message) = $post_build_command->{BUILDER}
							(
							$file_tree->{__CONFIG},
							[$name, $build_name],
							$dependencies,
							$triggered_dependencies,
							$post_build_command->{BUILDER_ARGUMENTS},
							$file_tree,
							$inserted_nodes,
							) ;
							
		#DEBUG HOOK
		$DB::single = 1 if($PBS::Debug::debug_enabled && PBS::Debug::CheckBreakpoint(%debug_data, POST => 1, BUILD_RESULT => $build_result, BUILD_MESSAGE => $build_message)) ;
		} ;
		
	my $rule_info = $post_build_command->{NAME} . $post_build_command->{ORIGIN} ;
	
	if($@) 
		{
		$build_result = BUILD_FAILED ;
		$build_message = "\n\t Building $build_name '$rule_info': Exception type: $@" ;
		}
		
	if(defined (my $lh = $pbs_config->{CREATE_LOG}))
		{
		print $lh INFO "Post build result for '$rule_info' on '$name': $build_result : $build_message\n" ;
		}
		
	if(defined $pbs_config->{DISPLAY_POST_BUILD_RESULT})
		{
		PrintInfo("Post build result for '$rule_info' on '$name': $build_result : $build_message\n") ;
		}
		
	if($build_result == BUILD_FAILED)
		{
		unlink($build_name) if PBS::Digest::IsDigestToBeGenerated($file_tree->{__LOAD_PACKAGE}, $file_tree) ;
		$file_tree->{__BUILD_FAILED} = $build_message ;
		last ;
		}
	}

return($build_result, $build_message) ;
}

#-------------------------------------------------------------------------------------------------------

1 ;

__END__

=head1 NAME

PBS::Build::NodeBuilder -

=head1 DESCRIPTION

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut


