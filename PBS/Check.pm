
package PBS::Check ;

use v5.10 ; use strict ; use warnings ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CheckDependencyTree) ;
our $VERSION = '0.04' ;

use Data::Dumper ;
use Data::TreeDumper ;
use File::Basename ;
use File::Slurp qw (write_file) ;
use File::Spec::Functions qw(:ALL) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Cyclic ;
use PBS::Digest ;
use PBS::Node ;
use PBS::Output ;

#-------------------------------------------------------------------------------

my $checked_dependency_tree = 0 ;
my @cyclic_trail ;

sub CheckDependencyTree
{
# checks the tree for cyclic dependencies and  generates a build sequence

my ($node, $node_level, $inserted_nodes, $pbs_config, $config, $trigger_rule, $node_checker_rule, $build_sequence, $files_in_build_sequence)  = @_ ;

return exists $node->{__TRIGGERED} if exists $node->{__CHECKED} ; # check once

$build_sequence //= [] ; 
$files_in_build_sequence //= {} ;

$node->{__LEVEL} = $node_level ;

my $name = $node->{__NAME} ;
my $triggered = 0 ; 

# collect data for the build step
$node->{__CHILDREN_TO_BUILD} = 0 ;

Print EC "\e[K<I>Check: $checked_dependency_tree<I2> \\<$$>\r", 0
	unless $checked_dependency_tree++ % 29 || \$config->{DISPLAY_NO_STEP_HEADER_COUNTER} ;

my $cycle = CheckCycle($node, $inserted_nodes, $pbs_config, \@cyclic_trail) ; 
return $cycle if defined $cycle ;

if(NodeIsGenerated($node) && ! exists $node->{__PARALLEL_DEPEND} )
	{
	# warn if node isn't depended or has no dependencies
	#use Carp ;
	#print Carp::croak unless defined $node->{__NAME} ;

	my $matching_rules = @{$node->{__MATCHING_RULES}} ;
	 
	my @dependencies = grep { $_ !~ /^__/ } keys %$node ;

	my $inserted_at = GetRunRelativePath($pbs_config, GetInsertionRule($node) // '') // '';

	my $depended_at = '' ;

	if($matching_rules)
		{
		my $matching_rule = $node->{__MATCHING_RULES}[0]{RULE} ;
		my $rule = $matching_rule->{DEFINITIONS}[$matching_rule->{INDEX}] ;
		$depended_at  = $rule->{NAME} . ':' ;
		$depended_at .= GetRunRelativePath($pbs_config, $rule->{FILE}) . ':' ;
		$depended_at .= $rule->{LINE} ;
		}
	
	Say EC "<I>Check: <I3>$name<W> inserted and depended in different pbsfiles<I2>, inserted: $inserted_at, depended: $depended_at"
		if $node->{__INSERTED_AND_DEPENDED_DIFFERENT_PACKAGE} && ! $node->{__MATCHED_SUBPBS};
	
	if( 0 == @dependencies && ! PBS::Digest::OkNoDependencies($node->{__LOAD_PACKAGE}, $node))
		{
		Say EC "<I>Check: <I3>$name<W>, no dependencies"
			. ($matching_rules ? ", matching rules: $matching_rules" : ", no matching rules")
			. "<I2>, inserted: $inserted_at"
			. ($node->{__INSERTED_AND_DEPENDED_DIFFERENT_PACKAGE} ? "<I2>, depended: $depended_at" : '')
				unless $matching_rules && $pbs_config->{NO_WARNING_ZERO_DEPENDENCIES} ;
		}
	elsif(0 == $matching_rules)
		{
		Say EC "<I>Check: <I3>$name <W>no matching rules<I2>, inserted: $inserted_at" ;
		}
	}

my $is_virtual         = exists $node->{__VIRTUAL} ;
my $build_directory    = $node->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $node->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ;

my ($build_name, $alt_source, $alt_index) = 
		LocateSource
			(
			$name,
			$build_directory,
			$source_directories,
			$pbs_config->{DISPLAY_SEARCH_INFO},
			$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
			) ;

$build_name = $node->{__BUILD_NAME} = exists $node->{__FIXED_BUILD_NAME} ? $node->{__FIXED_BUILD_NAME} : $build_name ;

if ($alt_source)
	{
	$node->{__ALTERNATE_SOURCE_DIRECTORY} = $source_directories->[$alt_index] ;
	}
else
	{
	$node->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
	}

Say EC "<I>Place: <I3>$name<I2>" . ($alt_source ? ' -> [R]' : '') . ($is_virtual ? ' -> [V]' : $build_name ne $name ? " -> '$build_name'" : '')
	if $pbs_config->{DISPLAY_FILE_LOCATION} && $name !~ /^__/ ;

if(NodeIsGenerated($node))
	{
	my $trigger_match = 0 ;
	for my $trigger_regex (@{$pbs_config->{TRIGGER}})
		{
		if($name =~ /$trigger_regex/)
			{
			Say Info2 "Trigger: '$name' matches /$trigger_regex/"
				 if $pbs_config->{DEBUG_DISPLAY_TRIGGER} && $name !~ /^__PBS/
					 && ! exists $node->{__TRIGGERED} ;
			
			$trigger_match++ ;
			
			push @{$node->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => "'$trigger_regex'"} ;
			$triggered++ ;
			}
		}
	
	Say Info2 "Trigger: '$name' not triggered"
		 if ! $trigger_match
			&& $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY}
			&& $name !~ /^__PBS/ ;
	}

my (@dependency_triggering, @tally) ;

# NOTE: this also generates child parents links for parallel build
# do not make the block depend on previous triggers
for my $dependency_name (sort grep { ! /^__/ } keys %$node)
	{
	my $dependency = $node->{$dependency_name} ;
	
	if(DependencyIsSource($node, $dependency->{__NAME}, $inserted_nodes))
		{
		$node->{$dependency_name}{__BUILD_DONE}++ ;
		
		# trigger on our dependencies because they won't trigger themselves if they match 
		# and are a source node. If a source node triggered, it would need to be rebuild.
		my $trigger_match = 0 ;
		for my $trigger_regex (@{$pbs_config->{TRIGGER}})
			{
			if($dependency_name =~ /$trigger_regex/)
				{
				Say Info2 "Trigger: $name dependency $dependency_name matches /$trigger_regex/"
					if $pbs_config->{DEBUG_DISPLAY_TRIGGER}
						&& ! exists $node->{__TRIGGERED} ;
				
				$trigger_match++ ;
				
				push @{$node->{__TRIGGERED}}, {NAME => '__OPTION --trigger', REASON => ": $dependency_name"} ;
				$triggered++ ;
				
				push @tally, "<I2>Tally: $name [$node->{__CHILDREN_TO_BUILD}], child: $dependency_name" ;
				}
			}
		
		Say Info2 "Trigger: $dependency_name not triggered"
			 if ! $trigger_match && $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY};
		
		#source file are not checked but they must be located
		my ($located_name, $alt_source, $alt_index) = 
				LocateSource
					(
					$dependency_name,
					$build_directory,
					$source_directories,
					$pbs_config->{DISPLAY_SEARCH_INFO},
					$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
					) ;
		
		if ($alt_source)
			{
			$node->{$dependency_name}{__ALTERNATE_SOURCE_DIRECTORY} = $source_directories->[$alt_index] ;
			}
		else
			{
			$node->{$dependency_name}{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
			}
		
		$located_name = $node->{$dependency_name}{__BUILD_NAME} = exists $node->{$dependency_name}{__FIXED_BUILD_NAME}
										 ? $node->{$dependency_name}{__FIXED_BUILD_NAME}
										 : $located_name ; 
		
		Say EC "<I>Place: <I3>$dependency_name <I2>-> $located_name" if $pbs_config->{DISPLAY_FILE_LOCATION} ;
		}
	elsif(exists $dependency->{__CHECKED})
		{
		if($dependency->{__TRIGGERED})
			{
			$triggered = 1 ; # current node also need to be build
			
			my $reason = $dependency->{__TRIGGERED}[0]{NAME} ;
			$reason .= ', ... (' . scalar(@{$dependency->{__TRIGGERED}}) . ')'
					if scalar(@{$dependency->{__TRIGGERED}}) > 1 ;
			
			push @{$node->{__TRIGGERED}}, {NAME => $dependency_name, REASON => $reason} ;
			
			# data used to parallelize build
			
			push @{$dependency->{__PARENTS}}, $node ;
			push @dependency_triggering, $dependency ;
			
			$node->{__CHILDREN_TO_BUILD}++ ;
			
			push @tally, "<I2>Tally: $name [$node->{__CHILDREN_TO_BUILD}], child: $dependency_name" ;
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
			
			push @{$node->{__TRIGGERED}}, {NAME => $dependency_name, REASON => $reason} ;
			$triggered++ ;
			
			# data used to parallelize build
			$node->{__CHILDREN_TO_BUILD}++ ;
			push @{$dependency->{__PARENTS}}, $node ;
			push @dependency_triggering, $dependency ;
			
			push @tally, "<I2>Tally: $name [$node->{__CHILDREN_TO_BUILD}], child: $dependency_name" ;
			}
		}
	}

# handle the node type
if($is_virtual)
	{
	if(exists $node->{__LOCAL})
		{
		die ERROR("Node/File '$name' can't be VIRTUAL and LOCAL") ;
		}
		
	if(-e $build_name)
		{
		if(-d $build_name && $pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY})
			{
			# do not generate warning
			}
		else
			{
			Say Warning2 "Check: '$name' is VIRTUAL but file '" . GetRunRelativePath($pbs_config, $build_name) . "' exists" ;
			}
		}
	}
	
#----------------------------------------------------------------------------

local $PBS::Output::indentation_depth = 0 ;

if(exists $node->{__PARALLEL_DEPEND})
	{
	Say EC "<I>Check<W>ᴾ<I>: <I3>$node->{__NAME}<I2>, pid: $$"
		if exists $node->{__PARALLEL_HEAD} && $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING} ;
	
	push @{$node->{__TRIGGERED}}, {NAME => $node->{__NAME}, REASON => '__PARALLEL_DEPEND'} ;
	$triggered++ ;
	}

if(exists $node->{__FORCED})
	{
	Say Warning "Check: '$name' FORCED" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;

	push @{$node->{__TRIGGERED}}, {NAME => '__FORCED', REASON => 'Forced build'} ;
	$triggered++ ;
	}

unless(defined $pbs_config->{DEBUG_TRIGGER_NONE})
	{
	if( ! exists $node->{__VIRTUAL} && ! -e $build_name)
		{
		Say Info2 "Check: '$name' not found" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
		
		push @{$node->{__TRIGGERED}}, {NAME => '__SELF', REASON => ": not found"} ;
		$triggered++ ;
		}
	}
	
if(! $triggered && defined $node_checker_rule)
	{
	my ($must_build, $why) = $node_checker_rule->($node, $build_name) ;
	if($must_build)
		{
		Say Info2 "Check: '$name' $why" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
	
		push @{$node->{__TRIGGERED}}, {NAME => '__SELF', REASON => ':' . $why} ;
		$triggered++ ;
		}
	}

if(exists $node->{__PBS_FORCE_TRIGGER})
	{
	for my $forced_trigger (@{$node->{__PBS_FORCE_TRIGGER}})
		{
		my $message = $forced_trigger->{MESSAGE} // $forced_trigger->{REASON} // 'no message' ;
		
		Say Info "Check: '$name' PBS_FORCE_TRIGGER $message" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
		
		push @{$node->{__TRIGGERED}}, $forced_trigger ;
		$triggered++ ;
		}
	}

if($pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} && $name !~ /^__/)
	{
	Say Info2 "Check: '$name' triggered by '$_->{__NAME}'" for @dependency_triggering ;
	}

if(exists $node->{__VIRTUAL})
	{
	# no digest files for virtual nodes
	}
else
	{
	# the dependencies have been checked recursively ; the only thing a digest check could trigger with
	# is package or node dependencies like pbsfile, variables, etc..
	
	unless(defined $pbs_config->{DEBUG_TRIGGER_NONE} || $triggered || ! -e $build_name)
		{
		# check digest
		my $t0 = [gettimeofday];
		
		my ($must_build_because_of_digest, $reason) = (0, '') ;
		($must_build_because_of_digest, $reason) = PBS::Digest::IsNodeDigestDifferent($node, $inserted_nodes) unless $triggered ;
		
		if($must_build_because_of_digest)
			{
			for (@$reason)
				{
				push @{$node->{__TRIGGERED}}, {NAME => '__DIGEST_TRIGGERED', REASON => $_} ;
				Say Info2 "Check: '$name' $_" if $pbs_config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES} ;
				}
			
			# since we allow nodes to be build by the step before check (ex object files  with "depend and build"
			# we still want to trigger the node as some particular tasks might be done by the "builder
			# ie: write a digest for the node or run post build commands
			$triggered++ ;
			}
		}
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
		"{NAME => '$node->{__NAME}', TRIGGERS =>\n"
			. Data::Dumper->Dump([$node->{__TRIGGERED}])
			."},\n"
		) or do
			{
			Say Error "Check: Couldn't append to trigger file '$pbs_config->{TRIGGERS_FILE}'" ;
			die "\n" ;
			} ;
	
	my $build_name ;
	if(exists $node->{__FIXED_BUILD_NAME})
		{
		$build_name = $node->{__FIXED_BUILD_NAME}  ;
		}
	else
		{
		($build_name) = LocateSource
					(
					$name,
					$build_directory,
					undef,
					$pbs_config->{DISPLAY_SEARCH_INFO},
					$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
					) ;
		}
	
	if($node->{__BUILD_NAME} ne $build_name)
		{
		if(defined $pbs_config->{DISPLAY_FILE_LOCATION})
			{
			Say Warning "Check: relocating '$name' @ '$build_name'\n\tWas $node->{__BUILD_NAME}"  ;
			PrintWarning DumpTree($node->{__TRIGGERED}, 'Cause:') ;
			}
			
		$node->{__BUILD_NAME} = $build_name ;
		$node->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
		delete $node->{__ALTERNATE_SOURCE_DIRECTORY} ;
		}
	
	$files_in_build_sequence->{$name} = $node ;
	push @$build_sequence, $node  ;
	}
else
	{
	$node->{__BUILD_DONE} = "node not triggered" ;
	}
	
if($pbs_config->{DISPLAY_JOBS_INFO} && ! $pbs_config->{DISPLAY_JOBS_NO_TALLY})
	{
	Say EC $_ for sort @tally ;
	}

ClearCycleFlag($node, \@cyclic_trail) ;

$node->{__CHECKED}++ ;

$triggered
}

#-------------------------------------------------------------------------------

sub CheckCycle
{
my ($node, $inserted_nodes, $pbs_config, $cyclic_trail) = @_ ;
 
my $node_name = $node->{__NAME} ;

push @$cyclic_trail, $node ;

if(exists $node->{__CYCLIC_FLAG})
	{
	$node->{__CYCLIC_ROOT}++; # used in graph generation
	
	if(NodeIsGenerated($node))
		{
		my $cycles = PBS::Cyclic::GetUserCyclicText($node, $inserted_nodes, $pbs_config, $cyclic_trail) ; 
		PrintError "\e[KCheck: cyclic dependencies detected:\n$cycles", 1 ;
		
		die "cyclic dependencies detected @ $node_name\n" ;
		}
	
	if($pbs_config->{DIE_SOURCE_CYCLIC_WARNING})
		{
		die "cyclic dependencies detected @ $node_name\n" ;
		}
	else
		{
		if(exists $node->{__TRIGGERED})
			{
			return 1 ;
			}
		else
			{
			return 0 ;
			}
		}
	
	my $node_info = "inserted at '$node->{__INSERTED_AT}{INSERTION_FILE}' rule '$node->{__INSERTED_AT}{INSERTION_RULE}'" ;
	
	if(NodeIsGenerated($node))
		{
		#Say Error "Cycle at node '$name' $node_info" ;
		}
	else
		{
		Say Warning "Check: cycle at node '$node_name' $node_info (source node)" unless ($pbs_config->{NO_SOURCE_CYCLIC_WARNING}) ;
		}
	}
	
$node->{__CYCLIC_FLAG}++ ; # used to detect when a cycle has started

return undef
}

sub ClearCycleFlag
{
my ($node, $cyclic_trail) = @_ ;

delete $node->{__CYCLIC_FLAG} ;
pop @$cyclic_trail ;
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
				$node,
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
