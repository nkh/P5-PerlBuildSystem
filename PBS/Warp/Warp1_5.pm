
package PBS::Warp::Warp1_5 ;

use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.06' ;

#-------------------------------------------------------------------------------

use PBS::Output ;
use PBS::Log ;
use PBS::Digest ;
use PBS::Constants ;
use PBS::Plugin;
use PBS::Warp;

use Cwd ;
use File::Path;
use Data::Dumper ;
use Data::Compare ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use POSIX qw(strftime);
use File::Slurp ;
use Socket;
use IO::Select ;

#-------------------------------------------------------------------------------

sub WarpPbs
{
my ($targets, $pbs_config, $parent_config) = @_ ;

my ($warp_signature) = PBS::Warp::GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/_warp1_5';
my $warp_file= "$warp_path/Pbsfile_$warp_signature.pl" ;

$PBS::pbs_run_information->{WARP_1_5}{FILE} = $warp_file ;
PrintInfo "Warp file name: '$warp_file'\n" if defined $pbs_config->{DISPLAY_WARP_FILE_NAME} ;

my ($nodes, $node_names, $global_pbs_config, $insertion_file_names) ;
my ($version, $number_of_nodes_in_the_dependency_tree, $warp_configuration) ;

my $run_in_warp_mode = 1 ;

my $t0_warp_check ;
my $t0_warp = [gettimeofday];

# Loading of warp file can be eliminated if:
# we add the pbsfiles to the watched files
# we are registred with the watch server (it will have the nodes already)

if(-e $warp_file)
	{
	($nodes, $node_names, $global_pbs_config, $insertion_file_names,
	$version, $number_of_nodes_in_the_dependency_tree, $warp_configuration)
		= do $warp_file or do
			{
			PrintError("Couldn't evaluate warp file '$warp_file'\nFile error: $!\nCompilation error: $@") ;
			die "\n" ;
			} ;

	$PBS::pbs_run_information->{WARP_1_5}{SIZE} = -s $warp_file ;
	
	if($number_of_nodes_in_the_dependency_tree)
		{
		$PBS::pbs_run_information->{WARP_1_5}{SIZE_PER_NODE} = int((-s $warp_file) / $number_of_nodes_in_the_dependency_tree) ;
		}
	else
		{
		$PBS::pbs_run_information->{WARP_1_5}{SIZE_PER_NODE} = 'No node in the warp tree' ;
		$run_in_warp_mode = 0 ;
		}
		
	$PBS::pbs_run_information->{WARP_1_5}{VERSION} = $version ;
	$PBS::pbs_run_information->{WARP_1_5}{NODES_IN_DEPENDENCY_GRAPH} = $number_of_nodes_in_the_dependency_tree	;
	
	if($pbs_config->{DISPLAY_WARP_TIME})
		{
		my $warp_load_time = tv_interval($t0_warp, [gettimeofday]) ;
		
		PrintInfo(sprintf("Warp load time: %0.2f s.\n", $warp_load_time)) ;
		$PBS::pbs_run_information->{WARP_1_5}{LOAD_TIME} = $warp_load_time ;
		}
		
	$t0_warp_check = [gettimeofday];
	
	PrintInfo "Warp verify: $number_of_nodes_in_the_dependency_tree nodes.\n" unless $pbs_config->{QUIET} ;
	
	unless(defined $version)
		{
		PrintWarning2("Warp: bad version. Warp file needs to be rebuilt.\n") ;
		$run_in_warp_mode = 0 ;
		}
		
	unless($version == $VERSION)
		{
		PrintWarning2("Warp: bad version. Warp file needs to be rebuilt.\n") ;
		$run_in_warp_mode = 0 ;
		}
		
	# check if all pbs files are still the same
	if(0 == CheckFilesMD5($warp_configuration, 1))
		{
		PrintWarning("Warp: Differences in Pbsfiles. Warp file needs to be rebuilt.\n") ;
		$run_in_warp_mode = 0 ;
		}
	}
else
	{
	PrintWarning("Warp file '_warp1_5/Pbsfile_$warp_signature.pl' doesn't exist.\n") ;
	$run_in_warp_mode = 0 ;
	}

my @build_result ;
if($run_in_warp_mode)
	{
	my $nodes_in_warp = scalar(keys %$nodes) ;

	# use filewatching or default MD5 checking
	my $IsFileModified = RunUniquePluginSub($pbs_config, 'GetWatchedFilesChecker', $pbs_config, $warp_signature, $nodes) ;

	# skip all tests if nothing is modified
	if($run_in_warp_mode && defined $IsFileModified  && '' eq ref $IsFileModified  && 0 == $IsFileModified )
		{
		if($pbs_config->{DISPLAY_WARP_TIME})
			{
			my $warp_verification_time = tv_interval($t0_warp_check, [gettimeofday]) ;
			PrintInfo(sprintf("Warp verification time: %0.2f s.\n", $warp_verification_time)) ;
			$PBS::pbs_run_information->{WARP_1_5}{VERIFICATION_TIME} = $warp_verification_time ;
			
			my $warp_total_time = tv_interval($t0_warp, [gettimeofday]) ;
			PrintInfo(sprintf("Warp total time: %0.2f s.\n", $warp_total_time)) ;
			$PBS::pbs_run_information->{WARP_1_5}{TOTAL_TIME} = $warp_total_time ;
			}
			
		PrintInfo("\e[KWarp: Up to date\n") unless $pbs_config->{QUIET} ;
		return (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, $nodes) ;
		}

	$IsFileModified ||= \&PBS::Digest::IsFileModified ;
	
	# check and remove all nodes that would trigger
	my ($node_mismatch, $trigger_log)
		 = ParallelCheckNodes($pbs_config, $nodes, $node_names, $IsFileModified) ;
		 #= CheckNodes($pbs_config, $nodes, $node_names, $IsFileModified) ;

	my $number_of_removed_nodes = $nodes_in_warp - scalar(keys %$nodes) ;

	# rebuild the data PBS needs from the warp file for the nodes that have not triggered
	for my $node (keys %$nodes)
		{
		$nodes->{$node}{__NAME} = $node ;
		$nodes->{$node}{__BUILD_DONE} = "Field set in warp 1.5" ;
		$nodes->{$node}{__DEPENDED}++ ;
		$nodes->{$node}{__CHECKED}++ ; # pbs will not check any node (and its subtree) which is marked as checked
		
		$nodes->{$node}{__PBS_CONFIG} = $global_pbs_config unless exists $nodes->{$node}{__PBS_CONFIG} ;
		
		$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_names->[$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE}] ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE} = 'N/A Warp 1.5' ;
		
		unless(exists $nodes->{$node}{__DEPENDED_AT})
			{
			$nodes->{$node}{__DEPENDED_AT} = $nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
			}
			
		#let our dependent nodes know about their dependencies
		#this needed when regenerating the warp file from partial warp data
		for my $dependent (map {$node_names->[$_]} @{$nodes->{$node}{__DEPENDENT}})
			{
			if(exists $nodes->{$dependent})
				{
				$nodes->{$dependent}{$node} =
					{
					__BUILD_DONE => 'Field set in warp 1.5',
					__CHECKED => 1,
					} ;
				}
			}
		}

	my $now_string = strftime "%d_%b_%H_%M_%S", gmtime;
	write_file "$warp_path/Triggers_${now_string}.pl", "[\n" . $trigger_log . "]\n" unless $trigger_log eq '' ;

	if($pbs_config->{DISPLAY_WARP_TRIGGERED_NODES})	
		{
		}
	
	if($pbs_config->{DISPLAY_WARP_TIME})
		{
		my $warp_verification_time = tv_interval($t0_warp_check, [gettimeofday]) ;
		PrintInfo(sprintf("Warp verification time: %0.2f s.\n", $warp_verification_time)) ;
		$PBS::pbs_run_information->{WARP_1_5}{VERIFICATION_TIME} = $warp_verification_time ;
		
		my $warp_total_time = tv_interval($t0_warp, [gettimeofday]) ;
		PrintInfo(sprintf("Warp total time: %0.2f s. [$nodes_in_warp/trigger:$node_mismatch/removed:$number_of_removed_nodes]\n", $warp_total_time)) ;

		$PBS::pbs_run_information->{WARP_1_5}{TOTAL_TIME} = $warp_total_time ;
		}
		
	if($number_of_removed_nodes)
		{
		if(defined $pbs_config->{DISPLAY_WARP_BUILD_SEQUENCE})
			{
			}
			
		eval "use PBS::PBS" ;
		die $@ if $@ ;
		
		unless($pbs_config->{DISPLAY_WARP_GENERATED_WARNINGS})
			{
			$pbs_config->{NO_LINK_INFO} = 1 ;
			$pbs_config->{NO_LOCAL_MATCHING_RULES_INFO} = 1 ;
			}
			
		# we can't  generate a warp file while warping.
		# The warp configuration (pbsfiles md5) would be truncated
		# to the files used during the warp
		delete $pbs_config->{GENERATE_WARP1_5_FILE} ;
		
		# much of the "normal" node attributes are stripped in warp nodes
		# let the rest of the system know about this (ex graph generator)
		$pbs_config->{IN_WARP} = 1 ;
		my ($build_result, $build_message) ;
		my $new_dependency_tree ;
		
		eval
			{
			# PBS will link to the  warp nodes instead for regenerating them
			my $node_plural = '' ; $node_plural = 's' if $number_of_removed_nodes > 1 ;
			
			PrintInfo "Running PBS in warp mode. $number_of_removed_nodes node$node_plural to rebuild.\n" ;
			
			local $PBS::Output::indentation_depth = -1 ; 
			($build_result, $build_message, $new_dependency_tree)
				= PBS::PBS::Pbs
					(
					$pbs_config->{PBSFILE},
					'', # parent package
					$pbs_config,
					$parent_config,
					$targets,
					$nodes,
					"warp_tree",
					DEPEND_CHECK_AND_BUILD,
					) ;
			} ;
			
		if($@)
			{
			if($@ =~ /^BUILD_FAILED/)
				{
				# this exception occures only when a Builder fails so we can generate a warp file
				GenerateWarpFile
					(
					$targets, $new_dependency_tree, $nodes,
					$pbs_config, $warp_configuration,
					) ;
				}
				
			# died during depend or check
			die $@ ;
			}
		else
			{
			GenerateWarpFile
				(
				$targets, $new_dependency_tree, $nodes,
				$pbs_config, $warp_configuration,
				) ;
				
			# force a refresh after we build files and generated events
			# TODO: note that the synch should be by file not global
			RunUniquePluginSub($pbs_config, 'ClearWatchedFilesList', $pbs_config, $warp_signature) ;
			}
			
		@build_result = ($build_result, $build_message, $new_dependency_tree, $nodes) ;
		}
	else
		{
		PrintInfo("\e[KWarp: Up to date\n") unless $pbs_config->{QUIET} ;
		@build_result = (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, $nodes) ;
		}
	}
else
	{
	my ($dependency_tree_snapshot, $inserted_nodes_snapshot) ;
	
	$pbs_config->{INTERMEDIATE_WARP_WRITE} = 
		sub
		{
		my $dependency_tree = shift ;
		my $inserted_nodes = shift ;
		
		($dependency_tree_snapshot, $inserted_nodes_snapshot) = ($dependency_tree, $inserted_nodes) ;
		
		GenerateWarpFile
			(
			$targets,
			$dependency_tree,
			$inserted_nodes,
			$pbs_config,
			undef, # warp config
			' [pre-build]',
			) ;
		} ;
		
	my ($build_result, $build_message, $dependency_tree, $inserted_nodes) ;
	eval
		{
		local $PBS::Output::indentation_depth = -1 ;

		($build_result, $build_message, $dependency_tree, $inserted_nodes)
			= PBS::PBS::Pbs
				(
				$pbs_config->{PBSFILE},
				'', # parent package
				$pbs_config,
				$parent_config,
				$targets,
				undef, # inserted files
				"root_NEEDS_REBUILD_pbs_$pbs_config->{PBSFILE}", # tree name
				DEPEND_CHECK_AND_BUILD,
				) ;
		} ;
		
		if($@)
			{
			if($@ =~ /^BUILD_FAILED/)
				{
				# this exception occures only when a Builder fails so we can generate a warp file
				GenerateWarpFile
					(
					$targets,
					$dependency_tree_snapshot,
					$inserted_nodes_snapshot,
					$pbs_config,
					) ;
				}
				
			die $@ ;
			}
		else
			{
			GenerateWarpFile
				(
				$targets,
				$dependency_tree,
				$inserted_nodes,
				$pbs_config,
				) ;
			}
			
	@build_result = ($build_result, $build_message, $dependency_tree, $inserted_nodes) ;
	}

return(@build_result) ;
}

#-----------------------------------------------------------------------------------------------------------------------

sub ParallelCheckNodes
{
my ($pbs_config, $nodes, $node_names, $IsFileModified) = @_ ;

# location for MD% computation
for my $node (keys %$nodes)
	{
	if('VIRTUAL' ne $nodes->{$node}{__MD5})
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} =	exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;
		}
	}

my @nodes_per_level ;
push @{$nodes_per_level[tr~/~/~]}, $_ for keys %$nodes ;
shift @nodes_per_level unless defined $nodes_per_level[0] ;

my ($number_trigger_nodes, $trigger_log) = (0, '') ;
my $number_of_check_processes = 16 ;
	
my $checkers = StartCheckers($number_of_check_processes, $pbs_config, $nodes, $node_names, $IsFileModified)  ;

for my $level (reverse 0 .. @nodes_per_level - 1)
	{
	next unless defined $nodes_per_level[$level] ;
	next unless scalar(@{$nodes_per_level[$level]}) ;

	my $checker_index = 0 ;

	for my $slice (distribute(scalar @{$nodes_per_level[$level]}, $number_of_check_processes))
		{
		# slice and send node list to check, $checker->Check(@node_list)  ;
		my @nodes_to_check = @{$nodes_per_level[$level]}[$slice->[0] .. $slice->[1]] ;
		StartCheckingNodes(@$checkers[$checker_index++], \@nodes_to_check)  ;
		}

	my %all_nodes_triggered ;

	my @checker_finished ;
	while(@checker_finished < $number_of_check_processes)
		{
		my @finished = WaitForCheckersToFinish($pbs_config, $checkers) ;

		for(@finished)
			{
			# collect list of removed nodes
			my ($nodes_triggered, $trigger_nodes) = CollectNodeCheckResult(@$checkers[$_]) ;
			#PrintDebug DumpTree [$nodes_triggered, $trigger_nodes], 'results' ; 

			$all_nodes_triggered{$_}++ for @{$nodes_triggered} ;

			$number_trigger_nodes += @$trigger_nodes ;
			$trigger_log .= "{ NAME => '$_'},\n" for @$trigger_nodes ;
			}

		push @checker_finished, @finished
		}

	delete @{$nodes}{keys %all_nodes_triggered} ; # remove from dependency graph

	delete $nodes_per_level[$level] ; # done with the level

	# remove trigger nodes from subsequent checks
	for my $nodes_per_level (@nodes_per_level)
		{
		$nodes_per_level = [ grep {! exists $all_nodes_triggered{$_}} @$nodes_per_level ] ;
		}
	}

TerminateCheckers($checkers) ;

return ($number_trigger_nodes, $trigger_log) ;
}

#---------------------------------------------------------------------------------------------------------------

sub WaitForCheckersToFinish
{
my ($pbs_config, $checkers) = @_ ;
	
my $select_all = new IO::Select ;
my @waiting_for_messages ;

my $number_of_checkers = @$checkers ;

for (0 .. ($number_of_checkers - 1))
	{
	if($checkers->[$_]{CHECKING} == 1)
		{
		push @waiting_for_messages, "Checker $_" ;
		$select_all->add($checkers->[$_]{CHECKER_CHANNEL}) ;
		}
	}


my @checker_ready ;

if(@waiting_for_messages)
	{
	if(defined $pbs_config->{DISPLAY_JOBS_RUNNING})
		{
		PrintWarning "Waiting for:\n" ;
		
		local $PBS::Output::indentation_depth ;
		$PBS::Output::indentation_depth++ ;
		
		PrintWarning "$_\n" for(@waiting_for_messages) ;
		print "\n" ;
		}
		
	# block till we get end of check from a checker process 
	my @sockets_ready = $select_all->can_read() ; 
	
	for (0 .. ($number_of_checkers - 1))
		{
		for my $socket_ready (@sockets_ready)
			{
			if($socket_ready == $checkers->[$_]{CHECKER_CHANNEL})
				{
				push @checker_ready, $_ ;
				}
			}
		}
	}

return(@checker_ready) ;
}

#---------------------------------------------------------------------------------------------------------------

sub StartCheckers
{
my ($number_of_checkers, $pbs_config, $nodes, $node_names, $IsFileModified) = @_ ;

my @checkers ;
for my$checker_index (0 .. ($number_of_checkers - 1))
	{
	my ($checker_channel) = StartCheckerProcess
				(
				$pbs_config,
				$nodes,
				$node_names,
				$IsFileModified,
				) ;
				
	unless(defined $checker_channel)
		{
		PrintError "Parallel check: Couldn't start checker #$_!\n" ;
		die "\n";
		}
	
	print $checker_channel "GET_PROCESS_ID" . "__PBS_FORKED_CHECKER__" . "\n";
	
	my $child_pid = -1 ;
	while(<$checker_channel>)
		{
		last if /__PBS_FORKED_CHECKER__/ ;
		chomp ;
		$child_pid = $_ ;
		}
	
	$checkers[$checker_index] = 
		{
		PID              => $child_pid,
		CHECKER_CHANNEL  => $checker_channel,
		CHECKING => 0,
		} ;
	}

return(\@checkers) ;
}

#---------------------------------------------------------------------------------------------------------------

sub StartCheckerProcess
{
my ($pbs_config, $nodes, $node_names, $IsFileModified) = @_ ;

my ($to_child, $to_parent) ;
socketpair($to_child, $to_parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC)  or  die "socketpair: $!";

my $pid = fork() ;
if($pid)
	{
	close($to_parent) ;
	
	$to_child->autoflush(1);
	
	return($to_child) ;
	}
else
	{
	# new process
	unless(defined $pid)
		{
		# couldn't fork
		close($to_child) ;
		close($to_parent) ;
		return ;
		}
		
	close($to_child) ;
	
	$to_parent->autoflush(1) ;
	
	CheckerFront($to_parent, @_) ; # waits for commands from parent
	}
}

#-------------------------------------------------------------------------------

sub CheckerFront 
{
my $parent_channel = shift ; # communication channel to/from parent
my ($pbs_config, $nodes, $node_names, $IsFileModified) = @_ ;

my ($build_log, $build_output) ; # file names for the last build

while(defined (my $command_and_args = <$parent_channel>))
	{
	# wait for a command
	chomp $command_and_args ;
	
	my @command_and_args = split /__PBS_FORKED_CHECKER__/, $command_and_args ;
	
	for ($command_and_args[0])
		{
		/^STOP_PROCESS$/ and do
			{
			if($pbs_config->{DISPLAY_JOBS_INFO})
				{
				#~ PrintInfo("Stopping builder process [$$].\n") ; #debug only, should go to log
				}
				
			close($parent_channel) ;
			exit ;
			} ;
			
		/^GET_PROCESS_ID$/ and do
			{
			print $parent_channel "$$\n__PBS_FORKED_CHECKER__\n" ;
			last ;
			} ;
			
		/^CHECK_NODES$/ and do
			{
			(undef, my @nodes_to_check) = @command_and_args ;

			my ($nodes_triggered, $trigger_nodes) =  _CheckNodes($pbs_config, $nodes, \@nodes_to_check , $node_names, $IsFileModified)  ;

			my (%s1, %s2) ;
			my @nodes_triggered = grep { !$s1{$_}++ } @$nodes_triggered ;
			my @trigger_nodes = grep { !$s2{$_}++ } @$trigger_nodes ;

			print $parent_channel join('__PBS_FORKED_CHECKER__', @nodes_triggered)
						. "__PBS_FORKED_CHECKER_ARG__"
						. join('__PBS_FORKED_CHECKER__', @trigger_nodes) 
						. "__PBS_FORKED_CHECKER__\n" ;
			
			last ;
			} ;
			
		/^GET_TRIGGERED_NODE$/ and do
			{
			(undef, my @nodes_to_check) = @command_and_args ;
			my ($nodes_triggered, $trigger_nodes) =  _CheckNodes($pbs_config, $nodes, \@nodes_to_check , $node_names, $IsFileModified)  ;
			print $parent_channel "Done checking\n__PBS_FORKED_CHECKER__\n" ;
			
			last ;
			} ;
		}
	}
exit ;
}

#---------------------------------------------------------------------------------------------------------------

sub StartCheckingNodes
{
my ($pid, $nodes_to_check) = @_ ;

# IPC start the build
my $checker_channel = $pid->{CHECKER_CHANNEL} ;
$pid->{CHECKING} = 1 ;

print $checker_channel "CHECK_NODES" . "__PBS_FORKED_CHECKER__"
			. join("__PBS_FORKED_CHECKER__", @$nodes_to_check)
			. "__PBS_FORKED_CHECKER__\n" ;
}

#---------------------------------------------------------------------------------------------------------------

sub CollectNodeCheckResult
{
my ($pid) = @_ ;
	
my $builder_channel = $pid->{CHECKER_CHANNEL} ;

my $result = <$builder_channel> ;
chomp $result ;

my ($nodes_triggered, $trigger_nodes) = split /__PBS_FORKED_CHECKER_ARG__/, $result ;

my @nodes_triggered = split /__PBS_FORKED_CHECKER__/, $nodes_triggered ;
my @trigger_nodes = split /__PBS_FORKED_CHECKER__/, $trigger_nodes ;

return \@nodes_triggered, \@trigger_nodes ;
}

#---------------------------------------------------------------------------------------------------------------

sub TerminateCheckers
{
my ($checkers) = @_ ;
my $number_of_checkers = @$checkers ;

PrintInfo "Parallel Check:  terminating Check processes [$number_of_checkers]\n" ;

for my $checker_index (0 .. ($number_of_checkers - 1))
	{
	my $checker_channel = $checkers->[$checker_index]{CHECKER_CHANNEL} ;
	
	print $checker_channel "STOP_PROCESS\n" ;
	}
	
for (0 .. ($number_of_checkers - 1))
	{
	waitpid($checkers->[$_], 0) ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

sub CheckNodes
{
my ($pbs_config, $nodes, $node_names, $IsFileModified) = @_ ;

my @nodes_per_level ;
push @{$nodes_per_level[tr~/~/~]}, $_ for keys %$nodes ;
shift @nodes_per_level unless defined $nodes_per_level[0] ;

my ($number_trigger_nodes, $trigger_log) = (0, '') ;
my $sub_process = 8 ;

for my $level (reverse 0 .. @nodes_per_level - 1)
	{
	next unless defined $nodes_per_level[$level] ;
	next unless scalar(@{$nodes_per_level[$level]}) ;

	my %all_nodes_triggered ;

	for my $slice (distribute(scalar @{$nodes_per_level[$level]}, $sub_process))
		{
		my @nodes_to_check = @{$nodes_per_level[$level]}[$slice->[0] .. $slice->[1]] ;
		my ($nodes_triggered, $trigger_nodes) =  _CheckNodes($pbs_config, $nodes, \@nodes_to_check , $node_names, $IsFileModified)  ;

		$all_nodes_triggered{$_}++ for @{$nodes_triggered} ;

		$number_trigger_nodes += @$trigger_nodes ;
		$trigger_log .= "{ NAME => '$_'},\n" for @$trigger_nodes ;
		}

	delete @{$nodes}{keys %all_nodes_triggered} ; # remove from dependency graph

	delete $nodes_per_level[$level] ; # done with the level

	# remove trigger nodes from subsequent checks
	for my $nodes_per_level (@nodes_per_level)
		{
		$nodes_per_level = [ grep {! exists $all_nodes_triggered{$_}} @$nodes_per_level ] ;
		}
	}

return ($number_trigger_nodes, $trigger_log) ;
}

sub distribute
{
use integer ;

my ($size, $pools) = @_ ;
my ($start, @distribution) = (0) ;

my ($chunk, $remainder)  = ($size / $pools, $size % $pools) ;

for (0 .. $pools - 1)
	{
	my $pool_size = $chunk + ($_ < $remainder ? 1 : 0) ;

	if($pool_size)
		{
		my $end = ($start + $pool_size) - 1 ;
		push @distribution, [$start, $end] ; 
		}
	else
		{
		last ;
		}

	$start += $pool_size ;
	}

return @distribution ;
}

sub _CheckNodes
{
my ($pbs_config, $nodes, $nodes_to_check, $node_names, $IsFileModified) = @_ ;

my ($number_of_removed_nodes, $node_verified) = (0, 0) ;
my (@trigger_nodes, @nodes_triggered) ;

for my $node (@$nodes_to_check)
	{
	PrintInfo "warp: verified nodes: $node_verified\r"
		if $pbs_config->{DISPLAY_WARP_CHECKED_NODES}
		   && ! $pbs_config->{QUIET}
		   && ($node_verified + $number_of_removed_nodes) % 100 ;
		
	$node_verified++ ;
	
	next unless exists $nodes->{$node} ; 
	
	my $remove_this_node = 0 ;
	
	# virtual nodes don't have MD5
	if('VIRTUAL' ne $nodes->{$node}{__MD5})
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} =	exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;
			
		$remove_this_node += $IsFileModified->($pbs_config, $nodes->{$node}{__BUILD_NAME}, $nodes->{$node}{__MD5}) ;
		}

	$remove_this_node++ if(exists $nodes->{$node}{__FORCED}) ;

	push @trigger_nodes, $node if $remove_this_node ;

	if($pbs_config->{DISPLAY_WARP_CHECKED_NODES})
		{
		if ($remove_this_node)	
			{
			PrintInfo "Warp verify: " . ERROR('Removing') . INFO("  $node\n") ;
			}
		else
			{
			PrintInfo("Warp verify: OK, $node\n") unless $pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} ;
			}
		}

	if($remove_this_node) #and its dependents and its triggerer if any
		{
		my @nodes_to_remove = ($node) ;
		
		PrintInfo "Warp Prune:\n" 
			if $pbs_config->{DISPLAY_WARP_REMOVED_NODES} && @nodes_to_remove ;

		while(@nodes_to_remove)
			{
			my @dependent_nodes ;
			
			for my $node_to_remove (grep{ exists $nodes->{$_} } @nodes_to_remove)
				{
				PrintInfo2 $PBS::Output::indentation . "$node_to_remove\n"
					if $pbs_config->{DISPLAY_WARP_REMOVED_NODES} ;
				
				push @dependent_nodes, grep{ exists $nodes->{$_} } map {$node_names->[$_]} @{$nodes->{$node_to_remove}{__DEPENDENT}} ;
				
				# remove triggering node and its dependents
				if(exists $nodes->{$node_to_remove}{__TRIGGER_INSERTED})
					{
					my $trigerring_node = $nodes->{$node_to_remove}{__TRIGGER_INSERTED} ;
					push @dependent_nodes, grep{ exists $nodes->{$_} } map {$node_names->[$_]} @{$nodes->{$trigerring_node}{__DEPENDENT}} ;
					push @nodes_triggered, $trigerring_node ;
					}
					
				push @nodes_triggered, $node_to_remove ;
				
				$number_of_removed_nodes++ ;
				}
				
			@nodes_to_remove = @dependent_nodes ;
			}
		}
	}

return (\@nodes_triggered, \@trigger_nodes) ;
}

#-----------------------------------------------------------------------------------------------------------------------

sub GenerateWarpFile
{
# indexing the node name  saves another 10% in size
# indexing the location name saves another 10% in size

my ($targets, $dependency_tree, $inserted_nodes, $pbs_config, $warp_configuration, $warp_message) = @_ ;
$warp_message //='' ;

$warp_configuration = PBS::Warp::GetWarpConfiguration($pbs_config, $warp_configuration) ; #$warp_configuration can be undef or from a warp file

PrintInfo("\e[KWarp: generation.$warp_message\n") ;
my $t0_warp_generate =  [gettimeofday] ;

my ($warp_signature, $warp_signature_source) = PBS::Warp::GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/_warp1_5';
mkpath($warp_path) unless(-e $warp_path) ;

PBS::Warp::GenerateWarpInfoFile('1.5',$warp_path, $warp_signature, $targets, $pbs_config) ;

my $warp_file= "$warp_path/Pbsfile_$warp_signature.pl" ;

my $global_pbs_config = # cache to reduce warp file size
	{
	BUILD_DIRECTORY    => $pbs_config->{BUILD_DIRECTORY},
	SOURCE_DIRECTORIES => $pbs_config->{SOURCE_DIRECTORIES},
	} ;
	
my $number_of_nodes_in_the_dependency_tree = keys %$inserted_nodes ;

my ($nodes, $node_names, $insertion_file_names) = WarpifyTree1_5($inserted_nodes, $global_pbs_config) ;

open(WARP, ">", $warp_file) or die qq[Can't open $warp_file: $!] ;
print WARP PBS::Log::GetHeader('Warp', $pbs_config) ;

local $Data::Dumper::Purity = 1 ;
local $Data::Dumper::Indent = 1 ;
local $Data::Dumper::Sortkeys = 1 ; 

#~ print WARP Data::Dumper->Dump([$warp_signature_source], ['warp_signature_source']) ;

print WARP Data::Dumper->Dump([$global_pbs_config], ['global_pbs_config']) ;

print WARP Data::Dumper->Dump([ $nodes], ['nodes']) ;

print WARP "\n" ;
print WARP Data::Dumper->Dump([$node_names], ['node_names']) ;

print WARP "\n\n" ;
print WARP Data::Dumper->Dump([$insertion_file_names], ['insertion_file_names']) ;

print WARP "\n\n" ;
print WARP Data::Dumper->Dump([$warp_configuration], ['warp_configuration']) ;
print WARP "\n\n" ;
print WARP Data::Dumper->Dump([$VERSION], ['version']) ;
print WARP Data::Dumper->Dump([$number_of_nodes_in_the_dependency_tree], ['number_of_nodes_in_the_dependency_tree']) ;

print WARP "\n\n" ;


print WARP 'return $nodes, $node_names, $global_pbs_config, $insertion_file_names,
	$version, $number_of_nodes_in_the_dependency_tree, $warp_configuration;';
	
close(WARP) ;

if($pbs_config->{DISPLAY_WARP_TIME})
	{
	my $warp_generation_time = tv_interval($t0_warp_generate, [gettimeofday]) ;
	PrintInfo(sprintf("Warp total time: %0.2f s.\n", $warp_generation_time)) ;
	$PBS::pbs_run_information->{WARP_1_5}{GENERATION_TIME} = $warp_generation_time ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

sub WarpifyTree1_5
{
my $inserted_nodes = shift ;
my $global_pbs_config = shift ;

my ($package, $file_name, $line) = caller() ;

my (%nodes, @node_names, %nodes_index) ;
my (@insertion_file_names, %insertion_file_index) ;

for my $node (keys %$inserted_nodes)
	{
	# this doesn't work with LOCAL_NODES
	if(exists $inserted_nodes->{$node}{__VIRTUAL})
		{
		$nodes{$node}{__VIRTUAL} = 1 ;
		}
	else
		{
		# here some attempt to start handling AddDependency and micro warps
		#$nodes{$node}{__DIGEST} = GetDigest($inserted_nodes->{$node}) ;
		}
		
	if(exists $inserted_nodes->{$node}{__FORCED})
		{
		$nodes{$node}{__FORCED} = 1 ;
		}

	if(!exists $inserted_nodes->{$node}{__VIRTUAL} && $node =~ /^\.(.*)/)
		{
		($nodes{$node}{__LOCATION}) = ($inserted_nodes->{$node}{__BUILD_NAME} =~ /^(.*)$1$/) ;
		}
		
	#this can also be reduced for a +/- 10% reduction
	if(exists $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
		&& exists $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE})
		{
		$nodes{$node}{__INSERTED_AT}{INSERTING_NODE} = $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
		}
	else
		{
		$nodes{$node}{__INSERTED_AT}{INSERTING_NODE} = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTING_NODE} ;
		}
	
	if(exists $inserted_nodes->{$node}{__DEPENDED_AT})
		{
		if($inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ne $inserted_nodes->{$node}{__DEPENDED_AT})
			{
			$nodes{$node}{__DEPENDED_AT} = $inserted_nodes->{$node}{__DEPENDED_AT} ;
			}
		}
		
	#reduce amount of data by indexing Insertion files (Pbsfile)
	my $insertion_file = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
	
	unless (exists $insertion_file_index{$insertion_file})
		{
		push @insertion_file_names, $insertion_file ;
		$insertion_file_index{$insertion_file} = $#insertion_file_names ;
		}
		
	$nodes{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_index{$insertion_file} ;
	
	if
		(
		   $inserted_nodes->{$node}{__PBS_CONFIG}{BUILD_DIRECTORY}  ne $global_pbs_config->{BUILD_DIRECTORY}
		|| ! Compare($inserted_nodes->{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES}, $global_pbs_config->{SOURCE_DIRECTORIES})
		)
		{
		$nodes{$node}{__PBS_CONFIG}{BUILD_DIRECTORY} = $inserted_nodes->{$node}{__PBS_CONFIG}{BUILD_DIRECTORY} ;
		$nodes{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES} = [@{$inserted_nodes->{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES}}] ; 
		}
		
	if(exists $inserted_nodes->{$node}{__BUILD_DONE})
		{
		# build done, can also be a node that did not trigger, up to date
		if(exists $inserted_nodes->{$node}{__VIRTUAL})
			{
			$nodes{$node}{__MD5} = 'VIRTUAL' ;
			}
		else
			{
			if(exists $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_TIME})
				{
				# this is a new node
				if(defined $inserted_nodes->{$node}{__MD5} && $inserted_nodes->{$node}{__MD5} ne 'not built yet')
					{
					$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} ;
					}
				else
					{
					if(defined (my $current_md5 = GetFileMD5($inserted_nodes->{$node}{__BUILD_NAME})))
						{
						$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} = $current_md5 ;
						}
					else
						{
						die ERROR("Can't open '$node' to compute MD5 digest (old node/built/not_found): $!") ;
						}
					}
				}
			else
				{
				# use the old md5
				$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} ;
				}
			}
		}
	else
		{
		$nodes{$node}{__MD5} = 'not built yet' ; 
		}
		
	unless (exists $nodes_index{$node})
		{
		push @node_names, $node ;
		$nodes_index{$node} = $#node_names;
		}
		
	for my $dependency (keys %{$inserted_nodes->{$node}})
		{
		next if $dependency =~ /^__/ ;
		
		push @{$nodes{$dependency}{__DEPENDENT}}, $nodes_index{$node} ;
		}
		
	if (exists $inserted_nodes->{$node}{__TRIGGER_INSERTED})
		{
		$nodes{$node}{__TRIGGER_INSERTED} = $inserted_nodes->{$node}{__TRIGGER_INSERTED} ;
		}
	}
	
return(\%nodes, \@node_names, \@insertion_file_names) ;
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Warp::Warp1_5  -

=head1 DESCRIPTION

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS::Information>.

=cut
