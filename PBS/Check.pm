
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
use File::Slurp qw (write_file) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Cyclic ;
use PBS::Output ;
use PBS::Digest ;
use PBS::Node ;

#-------------------------------------------------------------------------------

my $checked_dependency_tree = 0 ;
my @cyclic_trail ;

sub CheckDependencyTree
{
# also checks the tree for cyclic dependencies
# generates a build sequence

my ($tree, $node_level, $inserted_nodes, $pbs_config, $config, $trigger_rule, $node_checker_rule, $build_sequence, $files_in_build_sequence)  = @_ ;

if(exists $tree->{__PARALLEL_DEPEND} || exists $tree->{__PARALLEL_NODE})
	{
	my $triggered = (exists $tree->{__CHECKED} and exists $tree->{__TRIGGERED}) ? ', triggered' : '' ;
	
	Say EC "<I>Check: <I3>$tree->{__NAME}<W>, remote node$triggered" if exists $tree->{__PARALLEL_NODE} ;
	Say EC "<I>Check: <I3>$tree->{__NAME}<W>, remote HEAD node$triggered" if exists $tree->{__PARALLEL_DEPEND} ;
	}

return exists $tree->{__TRIGGERED} if exists $tree->{__CHECKED} ; # check once only

# we also build data for the build step
$tree->{__CHILDREN_TO_BUILD} = 0 ;

my $indent = $PBS::Output::indentation ;

PrintInfo "Check: $checked_dependency_tree\r" unless $checked_dependency_tree++ % 100 ;

$build_sequence //= [] ; 
$files_in_build_sequence //= {} ;

my $build_directory    = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ; 

my $triggered = 0 ; 
	
$tree->{__LEVEL} = $node_level ;
my $name = $tree->{__NAME} ;

push @cyclic_trail, $tree ;

if(exists $tree->{__CYCLIC_FLAG})
	{
	$tree->{__CYCLIC_ROOT}++; # used in graph generation
	
	if(NodeIsGenerated($tree))
		{
		my ($number_of_cycles, $cycles) = PBS::Cyclic::GetUserCyclicText($tree, $inserted_nodes, $pbs_config, \@cyclic_trail) ; 
		PrintError "\e[KCheck: cyclic dependencies detected:\n$cycles", 1 ;

		die "cyclic dependencies detected\n" ;
		}
	
	if($pbs_config->{DIE_SOURCE_CYCLIC_WARNING})
		{
		die ;
		}
	else
		{
		if(exists $tree->{__TRIGGERED})
			{
			return 1 ;
			}
		else
			{
			return 0 ;
			}
		}

	my $node_info = "inserted at '$tree->{__INSERTED_AT}{INSERTION_FILE}' rule '$tree->{__INSERTED_AT}{INSERTION_RULE}'" ;
	
	if(NodeIsGenerated($tree))
		{
		#Say Error "Cycle at node '$name' $node_info" ;
		}
	else
		{
		Say Warning "Check: cycle at node '$name' $node_info (source node)" unless ($pbs_config->{NO_SOURCE_CYCLIC_WARNING}) ;
		}
	}
	
$tree->{__CYCLIC_FLAG}++ ; # used to detect when a cycle has started

PrintInfo "\e[K\e[K" ; # bleah!

# warn if node isn't depended or has no dependencies
unless (NodeIsSource($tree))
	{
	#use Carp ;
	#print Carp::croak unless defined $tree->{__NAME} ;

	my $matching_rules = @{$tree->{__MATCHING_RULES}} ;
	 
	my @dependencies = grep { $_ !~ /^__/ } keys %$tree ;

	my $inserted_at = GetRunRelativePath($pbs_config, GetInsertionRule($tree) // '') // '';

	my $depended_at = '' ;

	if($matching_rules)
		{
		my $matching_rule = $tree->{__MATCHING_RULES}[0]{RULE} ;
		my $rule = $matching_rule->{DEFINITIONS}[$matching_rule->{INDEX}] ;
		$depended_at  = $rule->{NAME} . ':' ;
		$depended_at .= GetRunRelativePath($pbs_config, $rule->{FILE}) . ':' ;
		$depended_at .= $rule->{LINE} ;
		}

	Say EC "<I>Check: <I3>$name<W> inserted and depended in different pbsfiles<I2>, inserted: $inserted_at, depended: $depended_at"
		if $tree->{__INSERTED_AND_DEPENDED_DIFFERENT_PACKAGE} && ! $tree->{__MATCHED_SUBPBS};

	if( 0 == @dependencies && ! PBS::Digest::OkNoDependencies($tree->{__LOAD_PACKAGE}, $tree))
		{
		Say EC "<I>Check: <I3>$name<W>, no dependencies"
			. ($matching_rules ? ", matching rules: $matching_rules" : ", no matching rules")
			. "<I2>, inserted: $inserted_at"
			. ($tree->{__INSERTED_AND_DEPENDED_DIFFERENT_PACKAGE} ? "<I2>, depended: $depended_at" : '')
				unless $matching_rules && $pbs_config->{NO_WARNING_MATCHING_WITH_ZERO_DEPENDENCIES} ;
		}
	elsif(0 == $matching_rules)
		{
		Say EC "<I>Check: <I3>$name <W>no matching rules<I2>, inserted: $inserted_at" ;
		}
	}

my ($full_name, $is_alternative_source, $alternative_index) = ('', 0, 0) ;
my $is_virtual = exists $tree->{__VIRTUAL} ;

($full_name, $is_alternative_source, $alternative_index) = 
		LocateSource
			(
			$name,
			$build_directory,
			$source_directories,
			$pbs_config->{DISPLAY_SEARCH_INFO},
			$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
			) ;

if ($is_alternative_source)
	{
	$tree->{__ALTERNATE_SOURCE_DIRECTORY} = $source_directories->[$alternative_index] ;
	}
else
	{
	$tree->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
	}

$full_name = $tree->{__FIXED_BUILD_NAME} if(exists $tree->{__FIXED_BUILD_NAME}) ;
$tree->{__BUILD_NAME} = $full_name ;

Say EC "<I>Place: <I3>$name<I2>" 
	. ($is_alternative_source ? ' -> [R]' : '')
	. ($is_virtual ? ' -> [V]' : $full_name ne $name ? " -> '$full_name'" : '')
	if $pbs_config->{DISPLAY_FILE_LOCATION} && $name !~ /^__/ ;

my @dependency_triggering ;
my @tally ;

# IMPORTANT: this also generates child parents links for parallel build
# do not make the block depend on previous triggers
for my $dependency_name (sort keys %$tree)
	{
	my $dependency = $tree->{$dependency_name} ;

	next if $dependency_name =~ /^__/ ; # eliminate private data
	
	if(DependencyIsSource($tree, $dependency->{__NAME}, $inserted_nodes))
		{
		# trigger on our dependencies because they won't trigger themselves if they match 
		# and are a source node. If a source node triggered, it would need to be rebuild.
		my $trigger_match = 0 ;
		for my $trigger_regex (@{$pbs_config->{TRIGGER}})
			{
			if($dependency_name =~ /$trigger_regex/)
				{
				Say Info2 "Trigger: source $dependency_name matches /$trigger_regex/" if $pbs_config->{DEBUG_DISPLAY_TRIGGER} ;
				$trigger_match++ ;

				push @{$tree->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => ": $dependency_name"} ;
				push @{$dependency->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => ": $trigger_regex"} ;
				$triggered++ ;

				$tree->{__CHILDREN_TO_BUILD}++ ;
				push @tally, EC "<I2>Tally: $name [$tree->{__CHILDREN_TO_BUILD}], child: $dependency_name"
					if $pbs_config->{DISPLAY_JOBS_INFO} ;
				}
			}

		Say Info2 "Trigger: $dependency_name not triggered"
			 if ! $trigger_match && $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY};

		#source file are not checked but they must be located
		my ($full_name, $is_alternative_source, $alternative_index) = 
				LocateSource
					(
					$dependency_name,
					$build_directory,
					$source_directories,
					$pbs_config->{DISPLAY_SEARCH_INFO},
					$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
					) ;

		if ($is_alternative_source)
			{
			$tree->{$dependency_name}{__ALTERNATE_SOURCE_DIRECTORY} = $source_directories->[$alternative_index] ;
			}
		else
			{
			$tree->{$dependency_name}{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
			}

		$full_name = $tree->{$dependency_name}{__FIXED_BUILD_NAME} if(exists $tree->{$dependency_name}{__FIXED_BUILD_NAME}) ;

		$tree->{$dependency_name}{__BUILD_NAME} = $full_name ;
		$tree->{$dependency_name}{__BUILD_DONE}++ ;

		Say EC "<I>Place: <I3>$dependency_name <I2>-> $full_name"
			if $pbs_config->{DISPLAY_FILE_LOCATION} && $dependency_name !~ /^__/ ;
		}
	elsif(exists $dependency->{__CHECKED})
		{
		if($dependency->{__TRIGGERED})
			{
			$triggered = 1 ; # current node also need to be build
			
			my $reason = $dependency->{__TRIGGERED}[0]{NAME} ;
			$reason .= ', ... (' . scalar(@{$dependency->{__TRIGGERED}}) . ')'
					if scalar(@{$dependency->{__TRIGGERED}}) > 1 ;
			
			push @{$tree->{__TRIGGERED}}, {NAME => $dependency_name, REASON => $reason} ;
			
			# data used to parallelize build
			
			push @{$dependency->{__PARENTS}}, $tree ;
			push @dependency_triggering, $dependency ;
			
			$tree->{__CHILDREN_TO_BUILD}++ ;
			
			push @$build_sequence, $dependency if $dependency->{__PARALLEL_DEPEND} ;
			
			push @tally, EC "<I2>Tally: $name [$tree->{__CHILDREN_TO_BUILD}], child: $dependency_name"
				if $pbs_config->{DISPLAY_JOBS_INFO} && $name !~ /^__PBS/ ;
			}
		}
	else
		{
		my ($dependency_triggered) = CheckDependencyTree
							(
							$dependency,
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
		
		if($dependency_triggered)
			{
			my $reason = $dependency->{__TRIGGERED}[0]{NAME} ;
			$reason .= ', ... (' . scalar(@{$dependency->{__TRIGGERED}}) . ')'
					if scalar(@{$dependency->{__TRIGGERED}}) > 1 ;

			push @{$tree->{__TRIGGERED}}, {NAME => $dependency_name, REASON => $reason} ;
			$triggered++ ;
			
			# data used to parallelize build
			$tree->{__CHILDREN_TO_BUILD}++ ;
			push @{$dependency->{__PARENTS}}, $tree ;
			push @dependency_triggering, $dependency ;

			push @tally, EC "<I2>Tally: $name [$tree->{__CHILDREN_TO_BUILD}], child: $dependency_name"
				if $pbs_config->{DISPLAY_JOBS_INFO} && $name !~ /^__PBS/ ;
			}
		}
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
			Say Warning2 "Check: '$name' is VIRTUAL but file '" . GetRunRelativePath($pbs_config, $full_name) . "' exists" ;
			}
		}
	}
	
if(exists $tree->{__FORCED})
	{
	push @{$tree->{__TRIGGERED}}, {NAME => '__FORCED', REASON => 'Forced build'};
	
	Say Warning "Check: '$name' FORCED" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
	$triggered++ ;
	}
	
#----------------------------------------------------------------------------

unless(defined $pbs_config->{DEBUG_TRIGGER_NONE})
	{
	if( ! exists $tree->{__VIRTUAL} && ! -e $full_name)
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__SELF', REASON => ": not found"} ;
		Say Info2 "Check: '$name' not found" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
		$triggered++ ;
		}
	}
	
if(! $triggered && defined $node_checker_rule)
	{
	my ($must_build, $why) = $node_checker_rule->($tree, $full_name) ;
	if($must_build)
		{
		push @{$tree->{__TRIGGERED}}, {NAME => '__SELF', REASON => ':' . $why} ;
		Say Info2 "Check: '$name' $why" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
		$triggered++ ;
		}
	}

if(exists $tree->{__PBS_FORCE_TRIGGER})
	{
	for my $forced_trigger (@{$tree->{__PBS_FORCE_TRIGGER}})
		{
		my $message = $forced_trigger->{MESSAGE} // $forced_trigger->{REASON} // 'no message' ;
		
		Say Info "Check: '$name' PBS_FORCE_TRIGGER $message" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
		
		push @{$tree->{__TRIGGERED}}, $forced_trigger ;
		$triggered++ ;
		}
	}

if($pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} && $name !~ /^__/)
	{
	Say Info2 "Check: '$name' triggered by '$_->{__NAME}'" for @dependency_triggering ;
	}

if(exists $tree->{__VIRTUAL})
	{
	# no digest files for virtual nodes
	}
else
	{
	# the dependencies have been checked recursively ; the only thing a digest check could trigger with
	# is package or node dependencies like pbsfile, variables, etc..
	
	unless(defined $pbs_config->{DEBUG_TRIGGER_NONE} || $triggered || ! -e $full_name)
		{
		# check digest
		my $t0 = [gettimeofday];
		
		my ($must_build_because_of_digest, $reason) = (0, '') ;
		($must_build_because_of_digest, $reason) = PBS::Digest::IsNodeDigestDifferent($tree, $inserted_nodes) unless $triggered ;

		if($must_build_because_of_digest)
			{
			for (@$reason)
				{
				push @{$tree->{__TRIGGERED}}, {NAME => '__DIGEST_TRIGGERED', REASON => $_} ;
				Say Info2 "Check: '$name' $_" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
				}
			
			# since we allow nodes to be build by the step before check (ex object files  with "depend and build"
			# we still want to trigger the node as some particular tasks might be done by the "builder
			# ie: write a digest for the node or run post build commands
			$triggered++ ;
			}
		}
	}

if(NodeIsGenerated($tree))
	{
	my $trigger_match = 0 ;
	for my $trigger_regex (@{$pbs_config->{TRIGGER}})
		{
		if($name =~ /$trigger_regex/)
			{
			Say Info2 "Trigger: '$name' matches /$trigger_regex/"
				 if $pbs_config->{DEBUG_DISPLAY_TRIGGER} && $name !~ /^__PBS/ ;

			$trigger_match++ ;

			push @{$tree->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => "'$trigger_regex'"} ;
			$triggered++ ;
			}
		}

	Say Info2 "Trigger: '$name' not triggered"
		 if ! $trigger_match
			&& $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY}
			&& $name !~ /^__PBS/ ;
	}

# node is checked, add it to the build sequence if triggered
if($triggered)
	{
	use Data::Dumper ;
	local $Data::Dumper::Terse = 1 ;
	local $Data::Dumper::Pad = "\t" ;
	local $Data::Dumper::Sortkeys = 1 ;

	write_file
		(
		$pbs_config->{TRIGGERS_FILE},
		{append => 1, err_mode => "carp"},
		"{NAME => '$tree->{__NAME}', TRIGGERS =>\n"
			. Data::Dumper->Dump([$tree->{__TRIGGERED}])
			."},\n"
		) or do
			{
			Say Error "Check: Couldn't append to trigger file '$pbs_config->{TRIGGERS_FILE}'" ;
			die "\n" ;
			} ;

	my $full_name ;
	if(exists $tree->{__FIXED_BUILD_NAME})
		{
		$full_name = $tree->{__FIXED_BUILD_NAME}  ;
		}
	else
		{
		($full_name) = LocateSource
					(
					$name,
					$build_directory,
					undef,
					$pbs_config->{DISPLAY_SEARCH_INFO},
					$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
					) ;
		}
	
	if($tree->{__BUILD_NAME} ne $full_name)
		{
		if(defined $pbs_config->{DISPLAY_FILE_LOCATION})
			{
			Say Warning "Check: relocating '$name' @ '$full_name'\n\tWas $tree->{__BUILD_NAME}"  ;
			PrintWarning DumpTree($tree->{__TRIGGERED}, 'Cause:') ;
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
		
		my ($build_directory_name) = LocateSource
						(
						$name,
						$build_directory,
						undef,
						$pbs_config->{DISPLAY_SEARCH_INFO},
						$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
						) ;

		my ($repository_name) = LocateSource
						(
						$name,
						$build_directory,
						$source_directories,
						$pbs_config->{DISPLAY_SEARCH_INFO},
						$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
						) ;
		
		unless($repository_name eq $build_directory_name)
			{
			Say Warning "PBS: forcing local copy of '$repository_name' to '$build_directory_name'" if defined $pbs_config->{DISPLAY_FILE_LOCATION} ;
			
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
								} ;
							
							if($@)
								{
								return 0, "Copy '$repository_name' -> '$build_directory_name' failed! $@\n" ;
								}
								
							if($result)
								{
								return 1, "Copy '$repository_name' -> '$build_directory_name' succes.\n" ;
								}
							else
								{
								return 0, "Copy '$repository_name' -> '$build_directory_name' failed! $!\n" ;
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
			push @$build_sequence, $tree  ; # build only once
			}
		}
	else
		{
		$tree->{__BUILD_DONE} = "node not triggered" ;
		}
	}
	
Say $_ for sort @tally ;

delete($tree->{__CYCLIC_FLAG}) ;
pop @cyclic_trail ;

$tree->{__CHECKED}++ ;

return $triggered ;
}

#-------------------------------------------------------------------------------

sub LocateSource
{
# returns the directory where the file is located
# if the file doesn't exist in any of the build directory or other directories
# the file is then locate in the build directory

my ($file, $build_directory, $other_source_directories, $display_search_info, $display_all_alternates) = @_ ; 

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
	Say EC "<I2>Place: target: <I3>$unlocated_file" if $display_search_info ;
	
	if(-e $located_file)
		{
		$file_found++ ;
		
		my ($file_size, undef, undef, $modification_time) = (stat($located_file))[7..10];
		my ($sec,$min,$hour,$month_day,$month,$year,$week_day,$year_day) = gmtime($modification_time) ;
		$year += 1900 ;
		$month++ ;
		
		Say Info2 "Place: in build directory: '$build_directory'. s: $file_size t: $month_day-$month-$year $hour:$min:$sec"
			if $display_search_info ;
		}
	else
		{
		Say Info2 "Place: not in build directory: '$build_directory'" if $display_search_info ;
		}
		
	if((! $file_found) || $display_all_alternates)
		{
		for my $source_directory (@$other_source_directories)
			{
			$other_source_index++ unless $alternative_source ;
			
			if('' eq ref $source_directory)
				{
				my $searched_file = "$source_directory/$file" ;
				
				if(-e $searched_file)
					{
					my ($file_size, undef, undef, $modification_time) = (stat($searched_file))[7..10];
					my ($sec, $min, $hour, $month_day, $month, $year, $week_day, $year_day) = gmtime($modification_time) ;
					$year += 1900 ;
					$month++ ;
					
					if($file_found)
						{
						Say Warning3
							"Place:: also located as "
							. " '$searched_file'"
							. ", size: $file_size, time: $month_day-$month-$year $hour:$min:$sec", 
								if $display_search_info ;
						}
					else
						{
						$file_found++ ;
						Say Info2
							"Place: found:"
							. " '$searched_file'"
							. ", size: $file_size, time: $month_day-$month-$year $hour:$min:$sec", 
								if $display_search_info ;
						
						$located_file = $searched_file ;
						$alternative_source++ ;
						last unless $display_all_alternates ;
						}
					}
				else
					{
					#Say Info "Locate: not located as:" . _INFO2_(" '$searched_file'") if $display_search_info ;
					}
				}
			else
				{
				die ERROR("Locate: Error: Search path sub is unimplemented!") . "\n" ;
				}
			}
		}
	}
else
	{
	Say Info2 "Place: absolute path: $located_file" if $display_search_info ;
	}

Say Info2 "Place: => '$located_file'" if $display_search_info ;

return $located_file, $alternative_source, $other_source_index ;
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

=head2 EXPORT

	CheckDependencyTree
	RegisterUserCheckSub

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO


=cut
