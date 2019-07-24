
package PBS::Check ;

use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use File::Spec::Functions qw(:ALL) ;
use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CheckDependencyTree) ;
our $VERSION = '0.04' ;

use File::Basename ;
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Cyclic ;
use PBS::Output ;
use PBS::Digest ;

#-------------------------------------------------------------------------------

my $checked_dependency_tree = 0 ;

sub CheckDependencyTree
{
# also checks the tree for cyclic dependencies
# generates a build sequence

my ($tree, $node_level, $inserted_nodes, $pbs_config, $config, $trigger_rule, $node_checker_rule, $build_sequence, $files_in_build_sequence)  = @_ ;

return exists $tree->{__TRIGGERED} if exists $tree->{__CHECKED} ; # check once only
	
PrintInfo "$checked_dependency_tree\r" unless $checked_dependency_tree++ % 100 ;

$build_sequence //= [] ; 
$files_in_build_sequence //= {} ;

my $build_directory    = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ; 

my $triggered = 0 ; 
	
$tree->{__LEVEL} = $node_level ;
my $name = $tree->{__NAME} ;

if(exists $tree->{__CYCLIC_FLAG})
	{
	# lets this sub find the cycle
	if($tree->{__CYCLIC_FLAG} > 1)
		{
		$tree->{__CYCLIC_ROOT}++; # used in graph generation
		
		# already displayed the cycle, stop cycling
		
		if(PBS::Digest::IsDigestToBeGenerated($tree->{__LOAD_PACKAGE}, $tree))
			{
			my ($number_of_cycles, $cycles) = PBS::Cyclic::GetUserCyclicText($tree, $inserted_nodes, $pbs_config) ; 
			print STDERR ERROR("\e[KCyclic dependencies detected ($number_of_cycles):\n$cycles") ;

			die "DEPENDENCY_CYCLE_DETECTED\n" ;
			}
		
		if($pbs_config->{DIE_SOURCE_CYCLIC_WARNING})
			{
			die ;
			}
		else
			{
			if(exists $tree->{__TRIGGERED})
				{
				return(1) ;
				}
			else
				{
				return(0) ;
				}
			}
		}
	
	my $node_info = "inserted at '$tree->{__INSERTED_AT}{INSERTION_FILE}' rule '$tree->{__INSERTED_AT}{INSERTION_RULE}'" ;
	
	if(PBS::Digest::IsDigestToBeGenerated($tree->{__LOAD_PACKAGE}, $tree))
		{
		#PrintError "Cycle at node '$name' $node_info.\n" ;
		}
	else
		{
		PrintWarning "Cycle at node '$name' $node_info (source node).\n" unless ($pbs_config->{NO_SOURCE_CYCLIC_WARNING}) ;
		}
	}
	
$tree->{__CYCLIC_FLAG}++ ; # used to detect when a cycle has started

unless(exists $tree->{__DEPENDED})
	{
	if(PBS::Digest::IsDigestToBeGenerated($tree->{__LOAD_PACKAGE}, $tree))
		{
		PrintWarning "Depend: NOT DEPENDED '$name' $tree->{__INSERTED_AT}{INSERTION_RULE}\n" ;
		}
	}
	
my ($full_name, $is_alternative_source, $alternative_index) = LocateSource($name, $build_directory, $source_directories) ;

if ($is_alternative_source)
	{
	$tree->{__ALTERNATE_SOURCE_DIRECTORY} = $source_directories->[$alternative_index] ;
	}
else
	{
	$tree->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
	}

$full_name = $tree->{__FIXED_BUILD_NAME} if(exists $tree->{__FIXED_BUILD_NAME}) ;
my $is_virtual = exists $tree->{__VIRTUAL} ;

$tree->{__BUILD_NAME} = $full_name ;

if($pbs_config->{DISPLAY_FILE_LOCATION} && $name !~ /^__/)
	{
	PrintInfo "node: $name"
			. ($is_alternative_source ? ' -> [R]' : '')
			. ($is_virtual ? ' -> [V]' : $full_name ne $name ? " -> $full_name" : '')
			. "\n" ;
	}
	
#----------------------------------------------------------------------------
# handle the node type
#----------------------------------------------------------------------------
if($is_virtual)
	{
	if(exists $tree->{__LOCAL})
		{
		die ERROR("Node/File '$name' can't be VIRTUAL and LOCAL") ;
		}
		
	if(-e $full_name)
		{
		if(-d $full_name && $pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY})
			{
			# do not generate warning
			}
		else
			{
			PrintWarning2("$name is VIRTUAL but file '$full_name' exists!\n") ;
			}
		}
	}
	
if(exists $tree->{__FORCED})
	{
	push @{$tree->{__TRIGGERED}}, {NAME => '__FORCED', REASON => 'Forced build'};
	
	PrintInfo("$name: trigged on [FORCED] type.\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
	$triggered++ ;
	}
	
#----------------------------------------------------------------------------

unless(defined $pbs_config->{DEBUG_TRIGGER_NONE})
	{
	if( ! exists $tree->{__VIRTUAL} && ! -e $full_name)
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__SELF', REASON => ": not found on disk"} ;
		PrintInfo("$name: trigged on itself [Doesn't exist]\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
		$triggered++ ;
		}
	}

if(! $triggered && defined $node_checker_rule)
	{
	my ($must_build, $why) = $node_checker_rule->($tree, $full_name) ;
	if($must_build)
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__SELF', REASON => ':' . $why} ;
		PrintInfo("$name: trigged on itself [$why]\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
		$triggered++ ;
		}
	}

if(exists $tree->{__PBS_FORCE_TRIGGER})
	{
	for my $forced_trigger (@{$tree->{__PBS_FORCE_TRIGGER}})
		{
		if('PBS_FORCE_TRIGGER' eq ref $forced_trigger )
			{
			my $message = $forced_trigger->{MESSAGE} ;
			
			PrintInfo("$name: trigged because of $message\n") if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
			
			push @{$tree->{__TRIGGERED}}, $forced_trigger ;
			$triggered++ ;
			}
		else
			{
			die "trigger is not of type 'PBS_FORCE_TRIGGER'!" ;
			}
		}
	}

# IMPORTANT: this also generates child parents links for parallel build
# do not make the block depend on previous triggers
for my $dependency (keys %$tree)
	{
	next if $dependency =~ /^__/ ; # eliminate private data
	
	if(exists $tree->{$dependency}{__CHECKED})
		{
		if($tree->{$dependency}{__TRIGGERED})
			{
			$triggered = 1 ; # current node also need to be build

			my $reason = $tree->{$dependency}{__TRIGGERED}[0]{NAME} ;
			$reason .= ', ... (' . scalar(@{$tree->{$dependency}{__TRIGGERED}}) . ')'
					if scalar(@{$tree->{$dependency}{__TRIGGERED}}) > 1 ;

			push @{$tree->{__TRIGGERED}}, {NAME => $dependency, REASON => $reason} ;
			
			# data used to parallelize build
			$tree->{__CHILDREN_TO_BUILD}++ ;
			push @{$tree->{$dependency}{__PARENTS}}, $tree ;
			}
		}
	else
		{
		my ($subdependency_triggered) = CheckDependencyTree
							(
							$tree->{$dependency},
							$node_level + 1,
							$inserted_nodes,
							$pbs_config,
							$config,
							$trigger_rule,
							$node_checker_rule,
							$build_sequence,
							$files_in_build_sequence,
							$build_directory,
							$source_directories,
							) ;
		
		if($subdependency_triggered)
			{
			my $reason = $tree->{$dependency}{__TRIGGERED}[0]{NAME} ;
			$reason .= ', ... (' . scalar(@{$tree->{$dependency}{__TRIGGERED}}) . ')'
					if scalar(@{$tree->{$dependency}{__TRIGGERED}}) > 1 ;

			push @{$tree->{__TRIGGERED}}, {NAME => $dependency, REASON => $reason} ;
			$triggered++ ;
			
			# data used to parallelize build
			$tree->{__CHILDREN_TO_BUILD}++ ;
			push @{$tree->{$dependency}{__PARENTS}}, $tree ;
			}
		}

	if(!PBS::Digest::IsDigestToBeGenerated($tree->{__LOAD_PACKAGE}, $tree->{$dependency}))
		{
		# trigger on our dependencies because they won't trigger themselves if they match 
		# and are a source node. If a source node triggered, it would need to be rebuild.
		my $trigger_match = 0 ;
		for my $trigger_regex (@{$pbs_config->{TRIGGER}})
			{
			if($dependency =~ /$trigger_regex/)
				{
				PrintUser "Trigger (source): MATCH $dependency =~ '$trigger_regex'\n" if $pbs_config->{DEBUG_DISPLAY_TRIGGER} ;
				$trigger_match++ ;

				push @{$tree->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => ": $dependency"} ;
				push @{$tree->{$dependency}{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => ": $trigger_regex"} ;
				$triggered++ ;
				}
			}

		PrintInfo2 "Trigger (source): $dependency\n" if ! $trigger_match && $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY} ;
		}
	}

if(exists $tree->{__VIRTUAL})
	{
	# no digest files for virtual nodes
	}
else
	{
	# the dependencies have been checked recursively ; the only thing a digest check could trigger with
	# is package or node dependencies like pbsfile, variables, etc.. there should be a switch to only check that
	
	unless(defined $pbs_config->{DEBUG_TRIGGER_NONE} ||  $triggered)
		{
		# check digest
		my $t0 = [gettimeofday];
		
		my ($must_build_because_of_digest, $reason) = (0, '') ;
		($must_build_because_of_digest, $reason) = PBS::Digest::IsNodeDigestDifferent($tree) unless $triggered ;

		if($must_build_because_of_digest)
			{
			for (@$reason)
				{
				push @{$tree->{__TRIGGERED}}, {NAME => '__DIGEST_TRIGGERED', REASON => ': ' . $_} ;
				PrintInfo("$name: trigged on '__DIGEST_TRIGGERED'[$_]\n")
					 if $pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES} ;
				}
			
			# since we allow nodes to be build by the step before check (ex object files  with "depend and build"
			# we still want to trigger the node as some particular tasks might be done by the "builder
			# ie: write a digest for the node ot run post build commands
			$triggered++ ;
			}
		}
	}

if(PBS::Digest::IsDigestToBeGenerated($tree->{__LOAD_PACKAGE}, $tree))
	{
	my $trigger_match = 0 ;
	for my $trigger_regex (@{$pbs_config->{TRIGGER}})
		{
		if($name =~ /$trigger_regex/)
			{
			PrintUser "Trigger: MATCH $name =~ '$trigger_regex'\n" if $pbs_config->{DEBUG_DISPLAY_TRIGGER} ;
			$trigger_match++ ;

			push @{$tree->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => ": $trigger_regex"} ;
			$triggered++ ;
			}
		}

	PrintInfo2 "Trigger: $name\n" if ! $trigger_match && $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY} ;
	}

# node is checked, add it to the build sequence if triggered
if($triggered)
	{
	my $full_name ;
	if(exists $tree->{__FIXED_BUILD_NAME})
		{
		$full_name = $tree->{__FIXED_BUILD_NAME}  ;
		}
	else
		{
		($full_name) = LocateSource($name, $build_directory) ;
		}
	
	if($tree->{__BUILD_NAME} ne $full_name)
		{
		if(defined $pbs_config->{DISPLAY_FILE_LOCATION})
			{
			PrintWarning("Relocating '$name' @ '$full_name'\n\tWas $tree->{__BUILD_NAME}.\n")  ;
			PrintWarning(DumpTree($tree->{__TRIGGERED}, 'Cause:')) ;
			}
			
		$tree->{__BUILD_NAME} = $full_name ;
		$tree->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
		delete $tree->{__ALTERNATE_SOURCE_DIRECTORY} ;
		}
		
		
	$files_in_build_sequence->{$name} = $tree ;
	push @$build_sequence, $tree  ;
	}
else
	{
	if(exists $tree->{__LOCAL})
		{
		# never get here if the node doesn't exists as it would have triggered
		
		my ($build_directory_name) = LocateSource($name, $build_directory) ;
		my ($repository_name) = LocateSource($name, $build_directory, $source_directories) ;
		
		my $repository_digest_name = $repository_name . '.pbs_md5' ;
		my $build_directory_digest_name = $build_directory_name . '.pbs_md5' ;
		
		unless($repository_name eq $build_directory_name)
			{
			PrintWarning("Forcing local copy of '$repository_name' to '$build_directory_name'.\n") if defined $pbs_config->{DISPLAY_FILE_LOCATION} ;
			
			# build a  localizer rule on the fly for this node
			my $localizer =
				[
					{
					TYPE => ['__LOCAL'],
					NAME => '__LOCAL:Internal rule', # name, package, ...
					FILE => 'Internal',
					LINE => 0,
					ORIGIN => '',
					DEPENDER => undef,
					BUILDER  => sub 
							{
							use File::Copy ;
							
							my ($basename, $path, $ext) = File::Basename::fileparse($build_directory_name, ('\..*')) ;
							
							# create path to the node so external commands succeed
							unless(-e $path)
								{
								use File::Path ;
								mkpath($path) ;
								}
								
							my $result ;
							eval 
								{
								$result = copy($repository_name, $build_directory_name) ;
								
								return($result) unless $result ;
								
								return($result) ;
								} ;
							
							if($@)
								{
								return(0, "Copy '$repository_name' -> '$build_directory_name' failed! $@\n") ;
								}
								
							if($result)
								{
								return(1, "Copy '$repository_name' -> '$build_directory_name' succes.\n") ;
								}
							else
								{
								return(0, "Copy '$repository_name' -> '$build_directory_name' failed! $!\n") ;
								}
							},
					TEXTUAL_DESCRIPTION => 'Rule to localize a file from the repository.',
					}
				] ;
				
			# localizer will be called as it is the last rule
			push @{$tree->{__MATCHING_RULES}}, 
				{
				RULE => 
					{
					INDEX        => -1,
					DEFINITIONS  => $localizer,
					},

				DEPENDENCIES => [],
				};
			
			push @{$tree->{__TRIGGERED}}, {NAME => '__LOCAL', REASON => 'Local file'};
			
			$files_in_build_sequence->{$name} = $tree ;
			push @$build_sequence, $tree  ; # build once only
			}
		}
	else
		{
		$tree->{__BUILD_DONE} = "node not triggered" ;
		}
	}
	
delete($tree->{__CYCLIC_FLAG}) ;
$tree->{__CHECKED}++ ;

return($triggered) ;
}

#-------------------------------------------------------------------------------

sub LocateSource
{
# returns the directory where the file is located
# if the file doesn't exist in any of the build directory or other directories
# the file is then locate in the build directory

my $file                     = shift ;
my $build_directory          = shift ;
my $other_source_directories = shift ;
my $display_search_info      = shift ;
my $display_all_alternates   = shift ;

my $located_file = $file ; # for files starting at root
my $alternative_source = 0 ;
my $other_source_index = -1 ;

unless(file_name_is_absolute($file))
	{
	my $unlocated_file = $file ;
	
	$file =~ s/^\.\/// ;

	$located_file = "$build_directory/$file" ;
	$located_file =~ s!//!/! ;
	
	my $file_found = 0 ;
	PrintInfo("Locating '$unlocated_file' \@:\n") if $display_search_info ;
	
	if(-e $located_file)
		{
		$file_found++ ;
		
		my ($file_size, undef, undef, $modification_time) = (stat($located_file))[7..10];
		my ($sec,$min,$hour,$month_day,$month,$year,$week_day,$year_day) = gmtime($modification_time) ;
		$year += 1900 ;
		$month++ ;
		
		PrintInfo("   located in build directory '$build_directory'. s: $file_size t: $month_day-$month-$year $hour:$min:$sec\n") if $display_search_info ;
		}
	else
		{
		if($display_search_info)
			{
			PrintInfo("   in build directory '$build_directory': ") ;
			PrintError("not found.\n") ;
			}
		}
		
	if((! $file_found) || $display_all_alternates)
		{
		for my $source_directory (@$other_source_directories)
			{
			$other_source_index++ unless $alternative_source ;
			
			if('' eq ref $source_directory)
				{
				my $searched_file = "$source_directory/$file" ;
				PrintInfo("   '$searched_file': ") if $display_search_info ;
				
				if(-e $searched_file)
					{
					my ($file_size, undef, undef, $modification_time) = (stat($searched_file))[7..10];
					my ($sec, $min, $hour, $month_day, $month, $year, $week_day, $year_day) = gmtime($modification_time) ;
					$year += 1900 ;
					$month++ ;
					
					if($file_found)
						{
						PrintWarning("NOT USED. size: $file_size time: $month_day-$month-$year $hour:$min:$sec\n") if $display_search_info ;
						}
					else
						{
						$file_found++ ;
						PrintInfo("Relocated. size: $file_size time: $month_day-$month-$year $hour:$min:$sec\n") if $display_search_info ;
						$located_file = $searched_file ;
						$alternative_source++ ;
						last unless $display_all_alternates ;
						}
					}
				else
					{
					PrintError("not found.\n") if $display_search_info ;
					}
				}
			else
				{
				die "Search path sub is unimplemented!" ;
				}
			}
		}
	}
	
return($located_file, $alternative_source, $other_source_index) ;
}

#-------------------------------------------------------------------------------

sub CheckTimeStamp
{
my $dependent_tree  = shift ;
my $dependent       = shift ;
my $dependency_tree = shift ;
my $dependency      = shift ;

if(-e $dependent)
	{
	if((stat($dependency))[9] > (stat($dependent))[9])
		{
		return(1, "$dependency newer than $dependent") ;
		}
	else
		{
		return(0, "Time stamp OK") ;
		}
	}
else
	{
	if(-e $dependency)
		{
		return(0, "'$dependent' doesn't exist") ;
		}
	else
		{
		die ERROR "Can't Check time stamp on non existing nodes!" ;
		}
	}
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Check  -

=head1 SYNOPSIS

	use PBS::Check ;
	my $triggered = CheckDependencyTree
				(
				$tree,
				$inserted_nodes,
				$pbs_config,
				$config,
				$trigger_rule,
				$node_checker_rule,
				$build_sequence, # output
				$files_in_build_sequence, # output
				) ;

=head1 DESCRIPTION

	sub RegisterUserCheckSub: exported function available in Pbsfiles
	sub GetUserCheckSub
	sub CheckDependencyTree: checks a tree and generates a build sequence
	sub LocateSource: find a file in the build directory or source directories
	sub CheckTimeStamp: check 2 nodes time stamps with each other

=head2 EXPORT

	CheckDependencyTree
	RegisterUserCheckSub

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO


=cut
