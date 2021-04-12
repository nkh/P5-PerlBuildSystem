
package PBS::Build::NodeBuilder ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.03' ;

use Data::TreeDumper ;
use File::Path qw(make_path) ;
use List::Util qw(any) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Check ;
use PBS::Config ;
use PBS::Constants ;
use PBS::Debug ;
use PBS::Depend ;
use PBS::Digest ;
use PBS::Information ;
use PBS::Output ;
use PBS::PBSConfig ;

#-------------------------------------------------------------------------------

sub BuildNode
{
my ($node, $pbs_config, $inserted_nodes, $node_build_sequencer_info) = @_ ;
my $build_name = $node->{__BUILD_NAME} ;

my $t0 = [gettimeofday];

my ($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' successful build") ;	
my ($dependencies, $triggered_dependencies) = GetNodeDependencies($node) ;

my $node_needs_rebuild = 1 ;

if($node->{__BUILD_DONE})
	{
	#PrintWarning "Build: already build: $node->{__BUILD_DONE}\n" ;
	$node_needs_rebuild = 0 ;
	}

if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	($build_result, $build_message) = (BUILD_FAILED, "--bi set, skip build.") ;
	$node_needs_rebuild = 0 ;
	}

my $rule_used_to_build ;
my $rules_with_builders = ExtractRulesWithBuilder($node) ;

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

my (@node_commands, %node_ENV) ; # update digest if we skip build ; 
my $skip_build_text = '' ;

if($rule_used_to_build && $node_needs_rebuild && $pbs_config->{CHECK_DEPENDENCIES_AT_BUILD_TIME})
	{
	my($why, $reasons, $number_of_differences) ;
	
	if (exists $node->{__VIRTUAL})
		{
		# virtual node have no digests so we can't check it
		($node_needs_rebuild, $why, $reasons, $number_of_differences) = (1, "\t\tVIRTUAL\n", ["__VIRTUAL\n"], 1)
		}
	elsif (any { $_->{NAME} eq '__SELF'} @{$node->{__TRIGGERED}})
		{
		($node_needs_rebuild, $why, $reasons, $number_of_differences) = (1, "\t\tSELF\n", ["__SELF\n"], 1) 
		}
	else
		{
		($node_needs_rebuild, $reasons, $number_of_differences) = PBS::Digest::IsNodeDigestDifferent($node, $inserted_nodes) ;
		
		$why = "\t\tCheck: digest: " . join ("\n\t\tdigest: ", @$reasons) . "\n" if $node_needs_rebuild ;
		}
	
	if(1 == $number_of_differences && ($reasons->[0] =~ /__DEPENDING_PBSFILE/ || $reasons->[0] =~ /__VIRTUAL/))
		{
		$node_needs_rebuild = 0 ;
		
		my @evaluated_commands 
			= RunRuleBuilder
				(
				0, # Get what would be run
				$pbs_config,
				$rule_used_to_build,
				$node,
				$dependencies,
				$triggered_dependencies,
				$inserted_nodes,
				) ;
		
		@node_commands = @evaluated_commands ;
		
		# compare with previous run commands
		my $digest_file_name = PBS::Digest::GetDigestFileName($node) ;
		
		if(-e $digest_file_name)
			{
			my ($digest, $sources, $build_ENV, $run_commands, $pbs_digest) ;
			
			($digest, $sources, $build_ENV, $run_commands, $pbs_digest) = do $digest_file_name ;
			
			if('ARRAY' eq ref $run_commands)
				{
				if(@evaluated_commands == @$run_commands)
					{
					while(@evaluated_commands)
						{
						my ($ec, $rc)  = (shift @evaluated_commands, shift @$run_commands) ;
						
						# code could use modules that have changed, we don't know about those dependencies
						$node_needs_rebuild++ if $ec->[0] =~ /sub \{/ || $rc->[0] =~ /sub\{/ ;
						#SDT [ $ec->[0] , $rc->[0] ]
						#	if $ec->[0] =~ /sub \{/ || $rc->[0] =~ /sub\{/ ;
						
						$node_needs_rebuild++ if $ec->[0] ne $rc->[0] ;
						#SDT [ $ec->[0] , $rc->[0] ]
						#	 if $ec->[0] ne $rc->[0] ;
						}
					
					$why = "\t\tpbsfile and commands mismatch\n" 
						if $node_needs_rebuild ;
					}
				else
					{
					$why = "\t\tpbsfile and different number of commands\n" ;
					$node_needs_rebuild++ ;
					}
					
				unless($node_needs_rebuild)
					{
					# compare ENV
					my ($node_ENV, $warnings, $regex_matches, $regex_number) = GetNodeENV($node) ;
					%node_ENV = %$node_ENV ;
					
					my @diffs = grep { ! exists $node_ENV->{$_} || $node_ENV->{$_} ne $build_ENV->{$_} } keys %$build_ENV ;
					
					my $env_diff = scalar(keys %$node_ENV) != scalar(keys %$build_ENV) ;
					
					$why = "\t\tENV: different number of exported variables\n" if $env_diff ;
					
					$why .= "\t\tENV: variable '$_' is '" 
							. ($node_ENV->{$_} // 'not defined')
							. "', previous build: '$build_ENV->{$_}'\n" for @diffs ;
					
					$node_needs_rebuild += @diffs + $env_diff ;
					}
				}
			}
		else
			{
			$node_needs_rebuild = 1 ;
			$why = "\t\tNo digest to check\n" ;
			} 
		}
	
	if ($node_needs_rebuild)
		{
		$skip_build_text = "\tRuntime check:\n$why\n" ;
		}
	else
		{
		$skip_build_text = "\tRuntine check: skipping\n" ;
		($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' No change.") ;
		}
	}

my $display_node =   any { $node->{__NAME} =~ $_ } @{$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX}} ;
   $display_node = ! any { $node->{__NAME} =~ $_ } @{$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT}} ;

my $node_info_displayed ;

local $PBS::Shell::silent_commands = $PBS::Shell::silent_commands ;
local $PBS::Shell::silent_commands_output = $PBS::Shell::silent_commands_output ;

if($node_needs_rebuild || !$pbs_config->{HIDE_SKIPPED_BUILDS})
	{
	if
		(
		$display_node
		&&  ( $pbs_config->{BUILD_AND_DISPLAY_NODE_INFO} || $pbs_config->{CREATE_LOG} )
		)
		{
		PBS::Information::DisplayNodeInformation($node, $pbs_config, $pbs_config->{CREATE_LOG}, $inserted_nodes) ;
		$node_info_displayed++ ;
		}
	else
		{
		PrintNoColor PBS::Information::GetNodeHeader($node, $pbs_config) if $pbs_config->{BUILD_DISPLAY_RESULT} ;
		
		$PBS::Shell::silent_commands = 1 ;
		$PBS::Shell::silent_commands_output = 1 ;
		}
	
	PrintWarning $skip_build_text if $skip_build_text ne q{} ;
	}

if($node_needs_rebuild)
	{
	if($rule_used_to_build)
		{
		unless ($node->{__VIRTUAL})
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
				$node,
				$dependencies,
				$triggered_dependencies,
				$inserted_nodes,
				) ;
		}
	else
		{
		my $reason .= @{$node->{__MATCHING_RULES}} ? "\tmatching rules have no builder\n" : "\tno matching rule\n"  ;
		
		# show why the node was to be build
		$reason.= "\t$_->{NAME} ($_->{REASON})\n" for @{$node->{__TRIGGERED}} ;
			
		$node->{__BUILD_FAILED} = $reason ;
		
		($build_result, $build_message) = (BUILD_FAILED, $reason) ;
		}
	
	($build_result, $build_message) = RunPostBuildCommands($build_result, $build_message, $pbs_config, $node, $dependencies, $triggered_dependencies, $inserted_nodes) ;
	}
else
	{
	# skipped build, these must ends up in digest
	$node->{__RUN_COMMANDS} = \@node_commands ;
	$node->{__ENV} = \%node_ENV ;
	}

if($build_result == BUILD_SUCCESS)
	{
	# record MD5 while the file is still fresh in the OS file cache
	if(exists $node->{__VIRTUAL})
		{
		$node->{__MD5} = 'VIRTUAL' ;
		#eval { PBS::Digest::GenerateNodeDigest($node) ; } ; # will remove digest
		($build_result, $build_message) = (BUILD_FAILED, "Build: error generating node digest: $@") if $@ ;
	
		if(-e $build_name)
			{
			PrintWarning2 "Build: '$node->{__NAME}' is VIRTUAL but file '$build_name' exists.\n"
				unless -d $build_name && $pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY} ;
			}
		}
	else
		{
		PBS::Digest::FlushMd5Cache($build_name) ;
		my $current_md5 = GetFileMD5($build_name) ;
		
		$node->{__MD5} = $current_md5 ;
		
		if( $current_md5 ne "invalid md5")
			{
			$node->{__MD5} = $current_md5 ;
			
			eval { PBS::Digest::GenerateNodeDigest($node) ; } ;
			($build_result, $build_message) = (BUILD_FAILED, "Build: error generating node digest: $@") if $@ ;
			}
		else
			{
			PBS::Digest::RemoveNodeDigest($node) ;
			($build_result, $build_message) = (BUILD_FAILED, "Build: error generating MD5 for '$build_name', $!.") ;
			}
		}
	}
else
	{
	unless ($node_info_displayed)
		{
		$node->{__PBS_CONFIG}{BUILD_AND_DISPLAY_NODE_INFO}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_CONFIG}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_ORIGIN}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_DEPENDENCIES}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_CAUSE}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_RULES}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_BUILD_SEQUENCER_INFO}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_TEXT_TREE_USE_ASCII}++ ;
		$node->{__PBS_CONFIG}{TIME_BUILDERS}++ ;
		
		PBS::Information::DisplayNodeInformation($node, $node->{__PBS_CONFIG}, 1, $inserted_nodes) ;
		} 
	}


my $build_time = tv_interval ($t0, [gettimeofday]) ;

if($build_result == BUILD_SUCCESS)
	{
	if($pbs_config->{DISPLAY_BUILD_RESULT})
		{
		$build_message //= '' ;
		}

	$node->{__BUILD_DONE} = "BuildNode Done." ;
	$node->{__BUILD_TIME} = $build_time  ;
	}
else
	{
	PrintError("Build: '$node->{__NAME}':\n$build_message\n") ;
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
my ($node) = @_ ;

my @dependencies ;
for my $dependency (grep { $_ !~ /^__/ ;}(keys %$node))
	{
	push @dependencies, exists $node->{$dependency}{__BUILD_NAME}
				? $node->{$dependency}{__BUILD_NAME}
				: $dependency ;
	}
	
my (@triggered_dependencies, %triggered_dependencies_build_names) ;

# build a list of triggering_dependencies and weed out doublets
for my $triggering_dependency (@{$node->{__TRIGGERED}})
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
my ($do_build, $pbs_config, $rule_used_to_build, $node, $dependencies, $triggered_dependencies, $inserted_nodes) = @_ ;

my $builder    = $rule_used_to_build->{DEFINITION}{BUILDER} ;
my $build_name = $node->{__BUILD_NAME} ;
my $name       = $node->{__NAME} ;

my ($build_result, $build_message) = (BUILD_SUCCESS, '') ;

# create path to the node so external commands succeed
my ($basename, $path, $ext) = File::Basename::fileparse($build_name, ('\..*')) ;
mkpath($path) unless(-e $path) ;
	
my @result ;

eval # rules might throw an exception
	{
	#DEBUG HOOK (see PBS::Debug)
	my %debug_data = 
		(
		TYPE                   => 'BUILD',
		CONFIG                 => $node->{__CONFIG},
		NODE_NAME              => $node->{__NAME},
		NODE_BUILD_NAME        => $build_name,
		DEPENDENCIES           => $dependencies,
		TRIGGERED_DEPENDENCIES => $triggered_dependencies,
		NODE                   => $node,
		) ;
		
	#DEBUG HOOK, jump into perl debugger if so asked
	$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1) ;
	
	my ($node_ENV, $warnings, $regex_matches, $regex_number) = GetNodeENV($node) ;

	local %ENV = (%ENV, %$node_ENV) ;

	if ($do_build)
		{
		Say Warning3 $_ for @$warnings ;
		Say Warning "ENV: exported variables: $regex_matches, expected minimum: $regex_number" if $regex_matches < $regex_number ;
		}

	$node->{__ENV} = $node_ENV ; # ends up in digest

	# get all the config variables from the node's package
	local $node->{__LOAD_PACKAGE} = $node->{__NAME} ;

	@result = $builder->
			(
			$do_build,
			$node->{__CONFIG},
			$build_name,
			$dependencies,
			$triggered_dependencies,
			$node,
			$inserted_nodes,
			$rule_used_to_build,
			) ;

	($build_result, $build_message) = @result if $do_build ;

	if($pbs_config->{DISPLAY_NODE_CONFIG_USAGE} && $do_build)
		{
		my $accessed = PBS::Config::GetConfigAccess($node->{__NAME}) ;

		my @not_accessed = grep 
					{
					! exists $accessed->{$_}
					&& ($pbs_config->{DISPLAY_TARGET_PATH_USAGE} || $_ ne 'TARGET_PATH')
					}
					sort keys %{$node->{__CONFIG}} ;

		PrintInfo DumpTree { Accessed => $accessed, 'Not accessed' => \@not_accessed},
			 "\nConfig: variable usage for '$node->{__NAME}:", DISPLAY_ADDRESS => 0 ;
		}

	unless(defined $build_result || $build_result == BUILD_SUCCESS || $build_result == BUILD_FAILED)
		{
		$build_result = BUILD_FAILED ;
		
		my $rule_info = "'" . $rule_used_to_build->{DEFINITION}{NAME} . "' at '"
					. $rule_used_to_build->{DEFINITION}{FILE}  . ":"
					. $rule_used_to_build->{DEFINITION}{LINE}  . "'" ;
			
		$build_message = "Builder $rule_info didn't return a valid build result!" ;
		}
		
	$build_message = 'no message returned by builder' if !defined $build_message || $build_message eq '' ;
	
	#DEBUG HOOK
	$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, POST => 1, BUILD_RESULT => $build_result, BUILD_MESSAGE => $build_message) ;
	} ;

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

return @result unless $do_build;

if($build_result == BUILD_FAILED)
	{
	#~ PrintInfo("Removing '$build_name'.\n") ;
	unlink($build_name) if NodeIsGenerated($node) ;
		
	my $rule_info =  $rule_used_to_build->{DEFINITION}{NAME}
			. $rule_used_to_build->{DEFINITION}{ORIGIN} ;
			
	$build_message .= ERROR "\tbuilder: #$rule_used_to_build->{INDEX} '$rule_info'. \n" ;

	$node->{__BUILD_FAILED} = $build_message ;
	}

return $build_result, $build_message ;
}

sub GetNodeENV
{
my ($node) = @_ ;

my (%node_ENV, @warnings) ;
my ($regex_number, $regex_matches) = (0, 0) ;

for my $regex ( @{ $node->{__EXPORT_CONFIG} // [] } )
	{
	$regex_number++ ;

	for my $key (grep { $_ =~ $regex } keys %{$node->{__CONFIG}})
		{
		$regex_matches++ ;

		my $node_value = $node->{__CONFIG}{$key} ;
		my $shell_value = exists $ENV{$key} ? "'$ENV{$key}'" : 'not found' ;

		push @warnings, "ENV: setting '$key' to '$node_value' was $shell_value" if $node_value ne $shell_value ;

		$node_ENV{$key} = $node_value ;
		}
	}

\%node_ENV, \@warnings, $regex_matches, $regex_number
}
#-------------------------------------------------------------------------------------------------------

sub ExtractRulesWithBuilder
{
my ($node) = @_ ;

# returns a list with elements following this format:
# {INDEX => rule_number, DEFINITION => rule } ;

my $pbs_config = $node->{__PBS_CONFIG} ;

my @rules_with_builders ;

for my $rule (@{$node->{__MATCHING_RULES}})
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
my ($node_build_result, $node_build_message, $pbs_config, $node, $dependencies, $triggered_dependencies, $inserted_nodes) = @_ ;

my $build_name = $node->{__BUILD_NAME} ;
my $name       = $node->{__NAME} ;

return $node_build_result, $node_build_message unless exists $node->{__POST_BUILD_COMMANDS} ;

my ($build_result, $build_message) = (BUILD_FAILED, 'default post build message') ;

for my $post_build_command (@{$node->{__POST_BUILD_COMMANDS}})
	{
	eval
		{
		#DEBUG HOOK
		my %debug_data = 
			(
			TYPE                   => 'POST_BUILD',
			CONFIG                 => $node->{__CONFIG},
			NODE_NAME              => $node->{__NAME},
			NODE_BUILD_NAME        => $build_name,
			DEPENDENCIES           => $dependencies,
			TRIGGERED_DEPENDENCIES => $triggered_dependencies,
			ARGUMENTS              => \$post_build_command->{BUILDER_ARGUMENTS},
			NODE                   => $node,
			NODE_BUILD_RESULT      => $node_build_result,
			NODE_BUILD_MESSAGE     => $node_build_message, 
			) ;
		
		#DEBUG HOOK
		$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data, PRE => 1) ;

		($build_result, my $pb_build_message) = $post_build_command->{BUILDER}
							(
							$node_build_result,
							$node_build_message,
							$node->{__CONFIG},
							[$name, $build_name],
							$dependencies,
							$triggered_dependencies,
							$post_build_command->{BUILDER_ARGUMENTS},
							$node,
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
		unlink($build_name) if NodeIsGenerated($node) ;
		$node->{__BUILD_FAILED} = $build_message ;
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


