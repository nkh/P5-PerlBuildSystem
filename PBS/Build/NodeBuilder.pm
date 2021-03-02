
package PBS::Build::NodeBuilder ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.03' ;

use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Path qw(make_path) ;
use List::Util qw(any) ;

use Data::TreeDumper ;

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
my ($node, $inserted_nodes) = @_ ;

# virtual node have no digests so we can't check it
return 0 if exists $node->{__VIRTUAL} ;

local $PBS::Output::indentation_depth ;
$PBS::Output::indentation_depth += 2 ;

return 1, "\t\t__SELF\n", ["\t\t__SELF\n"], 1 if any { $_->{NAME} eq '__SELF'} @{$node->{__TRIGGERED}} ;

my ($rebuild, $reasons, $number_of_differences) = PBS::Digest::IsNodeDigestDifferent($node, $inserted_nodes) ;

my $why = " digest OK" ;
   $why = "\n\t\tdigest: " . join ("\n\t\tdigest: ", @$reasons) . "\n" if $rebuild ;

unless($rebuild)
	{
	# node exists on disk, sub dependencies exist and have the same signature
	
	# our pbsfile may have change, we need to check the impact

	# if node uses shell commands only
	#	generate the commands now and compare with previous commands
	#	environment variables too!
	#
	# if node uses subs, did the pbsfile and its config change ... or any module that the sub uses!

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
			if ( NodeIsSource($node) )
				{
				if(defined (my $current_md5 = GetFileMD5($node->{__BUILD_NAME})))
					{
					$node->{__MD5} = $current_md5 ;
					}
				else
					{
					#PrintError("Can't open '$node' to compute MD5 digest: $!") ;
					$node->{__MD5} = 'Error: File not found!' ; 
					$why .= "\n\t\t" . $node->{__MD5} . "\n" ;
					}
				}
			}
		}
	}

return $rebuild, $why, $reasons, $number_of_differences ;

# test when one of the dependencies is virtual, all dependencies are virtual
# test when the pbsfile has changed
# test when config has changed
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

my ($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' successful build") ;	
my ($dependencies, $triggered_dependencies) = GetNodeDependencies($file_tree) ;

my $node_needs_rebuild = 1 ;

my $rule_used_to_build ;
my $rules_with_builders = ExtractRulesWithBuilder($file_tree) ;

if(@$rules_with_builders)
	{
	$rule_used_to_build = $rules_with_builders->[-1] ;

	for my $rule (@$rules_with_builders)
		{
		$rule_used_to_build = $rule 
			if $rule->{DEFINITION}{BUILDER} != $rule_used_to_build
				&& any { BUILDER_OVERRIDE eq $_ }  @{$rule->{DEFINITION}{TYPE}} ;
		}
	}

if($file_tree->{__BUILD_DONE})
	{
	#PrintWarning "Build: already build: $file_tree->{__BUILD_DONE}\n" ;
	$node_needs_rebuild = 0 ;
	}

if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	($build_result, $build_message) = (BUILD_FAILED, "--bi set, skip build.") ;
	$node_needs_rebuild = 0 ;
	}

my $skip_build_text = '' ;

if($rule_used_to_build && $node_needs_rebuild && $pbs_config->{CHECK_DEPENDENCIES_AT_BUILD_TIME})
	{
	my ($rebuild, $why, $reasons, $number_of_differences)
		= NodeNeedsRebuild($file_tree, $inserted_nodes) ;

	$node_needs_rebuild = $rebuild ;

	if(1 == $number_of_differences && $reasons->[0] =~ /__DEPENDING_PBSFILE/)
		{
		my (@evaluated_commands) 
			= RunRuleBuilder
				(
				0, # Get what would be run
				$pbs_config,
				$rule_used_to_build,
				$file_tree,
				$dependencies,
				$triggered_dependencies,
				$inserted_nodes,
				) ;
		
		#compare with previous run commands
		my $digest_file_name = PBS::Digest::GetDigestFileName($file_tree) ;

		if(-e $digest_file_name)
			{
			my ($digest, $sources, $run_commands, $pbs_digest) ;

			($digest, $sources, $run_commands, $pbs_digest) = do $digest_file_name ;
			
			#SDT [$run_commands, \@evaluated_commands] ;
				
			if('ARRAY' eq ref $run_commands)
				{
				$why = " pbsfile and commands mismatch" ;

				if(@evaluated_commands == @$run_commands)
					{
					my $found_mismatch = 0 ;

					while(@evaluated_commands)
						{
						my ($ec, $rc)  = (shift @evaluated_commands, shift @$run_commands) ;

						# code could use modules that have changed, we don't know about those dependencies
						$found_mismatch++ if $ec->[0] =~ /sub \{/ || $rc->[0] =~ /sub\{/ ;
							
						$found_mismatch++ if $ec->[0] ne $rc->[0] ;
						} ;
					
					$node_needs_rebuild = $found_mismatch ;
					}
				}
			}
		}
	
	if ($node_needs_rebuild)
		{
		$skip_build_text = "\tBuild:$why\n" ;
		}
	else
		{
		$skip_build_text = "\tBuild: skipping\n" ;
		($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' No change.") ;
		}
	}

my $display_node =   any { $file_tree->{__NAME} =~ $_ } @{$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX}} ;
   $display_node = ! any { $file_tree->{__NAME} =~ $_ } @{$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT}} ;

local $PBS::Shell::silent_commands = $PBS::Shell::silent_commands ;
local $PBS::Shell::silent_commands_output = $PBS::Shell::silent_commands_output ;

if($node_needs_rebuild || !$pbs_config->{HIDE_SKIPPED_BUILDS})
	{
	if
		(
		$display_node
		&&  ( $pbs_config->{BUILD_AND_DISPLAY_NODE_INFO}
			|| $pbs_config->{DISPLAY_BUILD_INFO}
			|| $pbs_config->{CREATE_LOG}
			)
		)
		{
		PBS::Information::DisplayNodeInformation($file_tree, $pbs_config, $pbs_config->{CREATE_LOG}, $inserted_nodes) ;
		}
	else
		{
		PrintNoColor PBS::Information::GetNodeHeader($file_tree, $pbs_config) if $pbs_config->{BUILD_DISPLAY_RESULT} ;

		$PBS::Shell::silent_commands = 1 ;
		$PBS::Shell::silent_commands_output = 1 ;
		}

	PrintWarning $skip_build_text if $skip_build_text ne q{} ;
	}

if($node_needs_rebuild)
	{
	if($rule_used_to_build)
		{
		unless ($file_tree->{__VIRTUAL})
			{
			my ($basename, $path, $ext) = File::Basename::fileparse($build_name, ('\..*')) ;
			make_path($path, { error => \my $make_path_errors}) ;
			
			if ($make_path_errors && @$make_path_errors)
				{
				my $error = join ', ' , map {my (undef, $message) = %$_; $message} @$make_path_errors ;
				
				return (BUILD_FAILED, "'$build_name' error: $error.") ;
				}
			}
		
		($build_result, $build_message) 
			= RunRuleBuilder
				(
				1, # do it!
				$pbs_config,
				$rule_used_to_build,
				$file_tree,
				$dependencies,
				$triggered_dependencies,
				$inserted_nodes,
				) ;
		}
	else
		{
		my $reason .= @{$file_tree->{__MATCHING_RULES}} ? "\tmatching rules have no builder\n" : "\tno matching rule\n"  ;
		
		# show why the node was to be build
		$reason.= "\t$_->{NAME} ($_->{REASON})\n" for @{$file_tree->{__TRIGGERED}} ;
			
		$file_tree->{__BUILD_FAILED} = $reason ;
		
		($build_result, $build_message) = (BUILD_FAILED, $reason) ;
		}
	
	($build_result, $build_message) = RunPostBuildCommands($build_result, $build_message, $pbs_config, $file_tree, $dependencies, $triggered_dependencies, $inserted_nodes) ;

	if($build_result == BUILD_SUCCESS)
		{
		# record MD5 while the file is still fresh in the OS file cache
		if(exists $file_tree->{__VIRTUAL})
			{
			$file_tree->{__MD5} = 'VIRTUAL' ;
			eval { PBS::Digest::GenerateNodeDigest($file_tree) ; } ; # will remove digest
			($build_result, $build_message) = (BUILD_FAILED, "Build: error generating node digest: $@") if $@ ;
		
			if(-e $build_name)
				{
				PrintWarning2 "Build: '$file_tree->{__NAME}' is VIRTUAL but file '$build_name' exists.\n"
					unless -d $build_name && $pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY} ;
				}
			}
		else
			{
			PBS::Digest::FlushMd5Cache($build_name) ;
			my $current_md5 = GetFileMD5($build_name) ;

			$file_tree->{__MD5} = $current_md5 ;

			if( $current_md5 ne "invalid md5")
				{
				$file_tree->{__MD5} = $current_md5 ;
				
				eval { PBS::Digest::GenerateNodeDigest($file_tree) ; } ;
				($build_result, $build_message) = (BUILD_FAILED, "Build: error generating node digest: $@") if $@ ;
				}
			else
				{
				PBS::Digest::RemoveNodeDigest($file_tree) ;
				($build_result, $build_message) = (BUILD_FAILED, "Build: error generating MD5 for '$build_name', $!.") ;
				}
			}
		}
	}
	
my $build_time = tv_interval ($t0, [gettimeofday]) ;

if($build_result == BUILD_SUCCESS)
	{
	if($pbs_config->{DISPLAY_BUILD_RESULT})
		{
		$build_message //= '' ;
		}

	$file_tree->{__BUILD_DONE} = "BuildNode Done." ;
	$file_tree->{__BUILD_TIME} = $build_time  ;
	}
else
	{
	PrintError("Build: '$file_tree->{__NAME}':\n$build_message\n") ;
	}
	
if($pbs_config->{TIME_BUILDERS} && ! $pbs_config->{DISPLAY_NO_BUILD_HEADER})
	{
	my $c = $build_result == BUILD_SUCCESS ? \&INFO : \&ERROR ;
	print STDERR $c->(sprintf("Build: time: %0.3f s.\n", $build_time)) ;
	}

return $build_result, $build_message ;
}

#-------------------------------------------------------------------------------------------------------

sub GetNodeRepositories
{
my ($tree) = @_ ;

my $target_path = ((File::Basename::fileparse($tree->{__NAME}))[1]) =~ s~/$~~r ;
	
$tree->{__NAME} =~ /^\./
	? map {  CollapsePath("$_/$target_path") } @{$tree->{__PBS_CONFIG}->{SOURCE_DIRECTORIES}}
	: ()
}

#-------------------------------------------------------------------------------------------------------

sub GetNodeDependencies
{
my ($file_tree) = @_ ;

my @dependencies ;
for my $dependency (grep { $_ !~ /^__/ ;}(keys %$file_tree))
	{
	push @dependencies, exists $file_tree->{$dependency}{__BUILD_NAME}
				? $file_tree->{$dependency}{__BUILD_NAME}
				: $dependency ;
	}
	
my (@triggered_dependencies, %triggered_dependencies_build_names) ;

# build a list of triggering_dependencies and weed out doublets
for my $triggering_dependency (@{$file_tree->{__TRIGGERED}})
	{
	my $dependency_name = $triggering_dependency->{NAME} ;
	
	next if $dependency_name =~ /^__/ ; #__SELF is triggering but is not a real dependency
	
	$dependency_name = $triggering_dependency->{__BUILD_NAME}
		if exists $triggering_dependency->{__BUILD_NAME} ;
		
	if(! exists $triggered_dependencies_build_names{$dependency_name})
		{
		push @triggered_dependencies, $dependency_name  ;
		$triggered_dependencies_build_names{$dependency_name} = $dependency_name  ;
		}
	}
	
return \@dependencies, \@triggered_dependencies ;
}

#-------------------------------------------------------------------------------------------------------

sub RunRuleBuilder
{
my ($do_build, $pbs_config, $rule_used_to_build, $file_tree, $dependencies, $triggered_dependencies, $inserted_nodes) = @_ ;

my $builder    = $rule_used_to_build->{DEFINITION}{BUILDER} ;
my $build_name = $file_tree->{__BUILD_NAME} ;
my $name       = $file_tree->{__NAME} ;

my ($build_result, $build_message) = (BUILD_SUCCESS, '') ;

# create path to the node so external commands succeed
my ($basename, $path, $ext) = File::Basename::fileparse($build_name, ('\..*')) ;
mkpath($path) unless(-e $path) ;
	
my @evaluated_commands ;

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
	$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1) ;
	
	local %ENV = %ENV ;

	if(exists $file_tree->{__EXPORT_CONFIG})
		{
		for my $regex ( @{ $file_tree->{__EXPORT_CONFIG} } )
			{
			for my $config_key (keys %{$file_tree->{__CONFIG}})
				{
				$ENV{$config_key} = $file_tree->{__CONFIG}{$config_key} if $config_key =~ $regex ;
				}
			}
		}

=pod
	$ENV{$_} = $file_tree->{__CONFIG}{$_} for
		grep { my $k = $_ ; any { $k =~ $_ } @{$file_tree->{__EXPORT_CONFIG} // []} }
			 keys %{$file_tree->{__CONFIG}} ;

	$ENV{$_} = $config{$_} for grep { $a = $_ ; any { $a =~ $_ } @regexes } keys %config ;
=cut
	# get all the config variables from the node's package
	local $file_tree->{__LOAD_PACKAGE} = $file_tree->{__NAME} ;

	if ($do_build)
		{
		($build_result, $build_message) = $builder->
							(
							$do_build,
							$file_tree->{__CONFIG},
							$build_name,
							$dependencies,
							$triggered_dependencies,
							$file_tree,
							$inserted_nodes,
							$rule_used_to_build,
							) ;
		}
	else
		{
		@evaluated_commands 
			= $builder->
				(
				$do_build,
				$file_tree->{__CONFIG},
				$build_name,
				$dependencies,
				$triggered_dependencies,
				$file_tree,
				$inserted_nodes,
				$rule_used_to_build,
				) 
		}

	if($pbs_config->{DISPLAY_NODE_CONFIG_USAGE})
		{
		my $accessed = PBS::Config::GetConfigAccess($file_tree->{__NAME}) ;

		my @not_accessed = grep 
					{
					! exists $accessed->{$_}
					&& ($pbs_config->{DISPLAY_TARGET_PATH_USAGE} || $_ ne 'TARGET_PATH')
					}
					sort keys %{$file_tree->{__CONFIG}} ;

		PrintInfo DumpTree { Accessed => $accessed, 'Not accessed' => \@not_accessed},
			 "\nConfig: variable usage for '$file_tree->{__NAME}:", DISPLAY_ADDRESS => 0 ;
		}

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
	$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1, BUILD_RESULT => $build_result, BUILD_MESSAGE => $build_message) ;
	} ;

return @evaluated_commands unless $do_build;

if($@)
	{
	$build_result = BUILD_FAILED ;

	if('' ne ref $@ && $@->isa('PBS::Shell'))
		{
		$build_message = ERROR "\tCommand: $@->{command}\n"
					. "\tType: $@->{error} \n"
					. "\tErrno: $@->{errno}, $@->{errno_string}\n" ;
		}
	else
		{
		my $rule_info = "'" . $rule_used_to_build->{DEFINITION}{NAME} . "' @ '"
				. $rule_used_to_build->{DEFINITION}{FILE}  . ":"
				. $rule_used_to_build->{DEFINITION}{LINE}  . "'" ;
		
		$build_message = ERROR "\texception: $@\n\tbuild name: $build_name\n" ;
		}
	}

if($build_result == BUILD_FAILED)
	{
	#~ PrintInfo("Removing '$build_name'.\n") ;
	unlink($build_name) if NodeIsGenerated($file_tree) ;
		
	my $rule_info =  $rule_used_to_build->{DEFINITION}{NAME}
			. $rule_used_to_build->{DEFINITION}{ORIGIN} ;
			
	$build_message .= ERROR "\tbuilder: #$rule_used_to_build->{INDEX} '$rule_info'. \n" ;

	$file_tree->{__BUILD_FAILED} = $build_message ;
	}

return $build_result, $build_message ;
}

#-------------------------------------------------------------------------------------------------------

sub ExtractRulesWithBuilder
{
my ($file_tree) = @_ ;

# returns a list with elements following this format:
# {INDEX => rule_number, DEFINITION => rule } ;

my $pbs_config = $file_tree->{__PBS_CONFIG} ;

my @rules_with_builders ;

for my $rule (@{$file_tree->{__MATCHING_RULES}})
	{
	my $rule_number = $rule->{RULE}{INDEX} ;
	my $dependencies_and_build_rules = $rule->{RULE}{DEFINITIONS} ;

	my $builder = $dependencies_and_build_rules->[$rule_number]{BUILDER} ;
	
	push @rules_with_builders, {INDEX => $rule_number, DEFINITION => $dependencies_and_build_rules->[$rule_number] } 
		if defined $builder ;
	}
	
return \@rules_with_builders ;
}

#-------------------------------------------------------------------------------------------------------

sub RunPostBuildCommands
{
my ($node_build_result, $node_build_message, $pbs_config, $file_tree, $dependencies, $triggered_dependencies, $inserted_nodes) = @_ ;

my $build_name = $file_tree->{__BUILD_NAME} ;
my $name       = $file_tree->{__NAME} ;

return $node_build_result, $node_build_message unless exists $file_tree->{__POST_BUILD_COMMANDS} ;

my ($build_result, $build_message) = (BUILD_FAILED, 'default post build message') ;

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
			NODE_BUILD_RESULT      => $node_build_result,
			NODE_BUILD_MESSAGE     => $node_build_message, 
			) ;
		
		#DEBUG HOOK
		$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1) ;

		($build_result, my $pb_build_message) = $post_build_command->{BUILDER}
							(
							$node_build_result,
							$node_build_message,
							$file_tree->{__CONFIG},
							[$name, $build_name],
							$dependencies,
							$triggered_dependencies,
							$post_build_command->{BUILDER_ARGUMENTS},
							$file_tree,
							$inserted_nodes,
							) ;
							
		$build_message .= "$pb_build_message " ;

		#DEBUG HOOK
		$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1, BUILD_RESULT => $build_result, BUILD_MESSAGE => $build_message) ;
		} ;
		
	my $rule_info = $post_build_command->{NAME} . $post_build_command->{ORIGIN} ;
	
	if($@) 
		{
		$build_result = BUILD_FAILED ;
		$build_message = "\n\t post build  $build_name '$rule_info': error: $@" ;
		}
		
	if(defined (my $lh = $pbs_config->{LOG_FH}))
		{
		print $lh INFO "Post build result for '$rule_info' on '$name': $build_result : $build_message\n\n" ;
		}
		
	if($pbs_config->{DISPLAY_POST_BUILD_RESULT})
		{
		PrintInfo "Post build result for '$rule_info' on '$name': $build_result : $build_message\n" ;
		}
		
	if($build_result == BUILD_FAILED)
		{
		unlink($build_name) if NodeIsGenerated($file_tree) ;
		$file_tree->{__BUILD_FAILED} = $build_message ;
		last ;
		}
	}

return $build_result, "Post build: $build_message\n" ;
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


