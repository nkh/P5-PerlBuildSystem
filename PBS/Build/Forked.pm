
package PBS::Build::Forked ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.04' ;

use PBS::Output ;
use PBS::Constants ;
use PBS::Distributor ;
use PBS::Build::NodeBuilder ;
use PBS::Build::ForkedNodeBuilder ;
use Data::TreeDumper ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use PBS::Build ;

use Socket;
use IO::Select ;
use PBS::ProgressBar ;
use List::PriorityQueue ;
use String::Truncate ;
use Term::Size::Any qw(chars) ;

$|++ ;

#-------------------------------------------------------------------------------

sub Build
{
my $t0 = [gettimeofday];

my ($pbs_config, $build_sequence, $inserted_nodes)  = @_ ;

my ($build_queue, $number_of_terminal_nodes, $level_statistics) = EnqueuTerminalNodes($build_sequence, $pbs_config) ;

my $distributor        = PBS::Distributor::CreateDistributor($pbs_config, $build_sequence) ;
my $number_of_builders = GetNumberOfBuilders($number_of_terminal_nodes, $pbs_config, $distributor) ;
my $builders           = StartBuilders($number_of_builders, $pbs_config, $distributor, $inserted_nodes) ;

my ($number_of_already_build_node, $number_of_failed_builders, $excluded, $error_output) = (0, 0, 0, '') ;
my ($builder_using_perl_time, %builder_stats) = (0,) ;

my $number_of_nodes_to_build = scalar(grep {$_->{__NAME} !~ /^__/} @$build_sequence) ; # remove PBS root
my $node_build_index = 0 ;

my $root_node = @$build_sequence[-1] ; # we guess, wrongly, that there is only one root in the build sequence

if($pbs_config->{DISPLAY_PROGRESS_BAR} && $pbs_config->{DISPLAY_PROGRESS_PER_BUILD_PROCESS})
	{
	PrintInfo3 "Builder $_\n" for (0 .. ($number_of_builders - 1)) ;
	}

my $progress_bar = CreateProgressBar($pbs_config, $number_of_nodes_to_build) ;

my $available = chars() - length($PBS::Output::indentation x ($PBS::Output::indentation_depth)) ;
my $em = String::Truncate::elide_with_defaults({ length => $available, truncate => 'middle' });

while ($number_of_nodes_to_build > $number_of_already_build_node)
	{
	# start building a node if a process is free
	if(!$number_of_failed_builders || $pbs_config->{NO_STOP})
		{
		my $started_builders = StartNodesBuild
					(
					$pbs_config,
					$build_queue,
					$builders,
					$node_build_index,
					$number_of_nodes_to_build,
					\%builder_stats,
					) ;
					
		$node_build_index += $started_builders ; 
		}
	
	my @builders = WaitForBuilderToFinish($pbs_config, $builders) ;
	@builders || last if $number_of_failed_builders ; # stop if nothing is building and an error occurred
		

	for my $builder (@builders)
		{
		my $built_node = $builder->{NODE} ;

		$level_statistics->[$built_node->{__LEVEL} - 1]{done}++ ;
		
		my ($build_result, $build_time, $node_error_output) =
			 CollectNodeBuildResult($pbs_config, $built_node, $builders) ;
		
		$number_of_already_build_node++ ;
		
		if($build_result == BUILD_SUCCESS)
			{
			if($progress_bar)
				{
				if($pbs_config->{DISPLAY_PROGRESS_BAR_FILE})
					{
					PrintInfo3 "\r\e[K$built_node->{__NAME}\n" ;
					}
				elsif($pbs_config->{DISPLAY_PROGRESS_PER_BUILD_PROCESS})
					{
					for ($number_of_builders)
						{
						my $distance = $number_of_builders - $builder->{INDEX} ;  

						PrintInfo2 "\e[${distance}A"
								. "\r\e[K"
								. $em ->("Builder $builder->{INDEX}: $built_node->{__NAME}")
								. "\e[${distance}B" ;

						}
					}

				$progress_bar->update($number_of_already_build_node) ;
				} 

			$builder_using_perl_time += $build_time 
				if PBS::Build::NodeBuilderUsesPerlSubs($built_node) ;
			
			EnqueueNodeParents($pbs_config, $built_node, $build_queue) ;
			}
		else
			{
			$error_output .= $node_error_output ;
			$number_of_failed_builders++ ;

			$excluded += MarkAllParentsAsFailed($pbs_config, $built_node) ;
			}

		if(defined $pbs_config->{DISPLAY_JOBS_RUNNING})
			{
			PrintWarning "Build: nodes built per level:\n" ;
			local $PBS::Output::indentation_depth ;
			$PBS::Output::indentation_depth++ ;

			my $index = 1 ;
			for my $level (@$level_statistics)
				{
				PrintWarning( $index++ . ' = ' . ($level->{done} // 0) . '/' . $level->{nodes} . "\n" ) ; 
				}
			}
		}
	}

TerminateBuilders($builders) ;

if($number_of_failed_builders)
	{
	my $plural = ('','')[$number_of_failed_builders] // 's' ;

	PrintError "Build: $number_of_failed_builders error$plural:\n" ;
	PrintError $error_output ;
	}

if(defined $pbs_config->{DISPLAY_SHELL_INFO})
	{
	PrintWarning DumpTree(\%builder_stats, 'Build: process statistics:', DISPLAY_ADDRESS => 0) ;
	}
	
if($pbs_config->{DISPLAY_TOTAL_BUILD_TIME})
	{
	PrintInfo(sprintf("Build: parallel build time: %0.2f s, sub time: %0.2f s.\n", tv_interval ($t0, [gettimeofday]), $builder_using_perl_time)) ;

	print STDERR (
		($number_of_failed_builders ? ERROR("Build: ") : INFO("Build: "))
		. INFO("nodes to build: $number_of_nodes_to_build"
		. ", success: " . ($number_of_already_build_node - $number_of_failed_builders))
		. ($number_of_failed_builders
			? ERROR(", failures: $number_of_failed_builders")
			: INFO (", failures: 0")) 
		. ($excluded
			? WARNING(", excluded: $excluded\n")
			: INFO ("\n"))
		) ;
	}

return(!$number_of_failed_builders) ;
}

#---------------------------------------------------------------------------------------------------------------

sub MarkAllParentsAsFailed
{
my ($pbs_config, $built_node) = @_ ;

local $PBS::Output::indentation_depth ;
$PBS::Output::indentation_depth++ ;

my $excluded = 0 ;

for my $parent (@{ $built_node->{__PARENTS} })
	{
	next if $parent->{__NAME} =~ /^__/ ;

	next if exists $parent->{__HAS_FAILED_CHILD} ;

	$parent->{__HAS_FAILED_CHILD}++ ;
	PrintWarning "Build: excluding node '$parent->{__NAME}'\n" if $pbs_config->{NO_STOP} ;
	$excluded++ ;

	$excluded += MarkAllParentsAsFailed($pbs_config, $parent) ;
	}

return $excluded ;
}


#---------------------------------------------------------------------------------------------------------------

sub EnqueuTerminalNodes
{
my ($build_sequence, $pbs_config) = @_ ;

my ($build_queue, $number_of_terminal_nodes, @level_statistics) = (List::PriorityQueue->new, 0) ;
my (@removed_nodes, @enqueued_nodes) ;

if(defined $pbs_config->{DISPLAY_JOBS_INFO})
	{
	PrintInfo2 "Build: computing nodes weight\n" ;
	PrintInfo2 "Build: enqueuing terminal nodes:\n" ;
	}
	
for my $node (@$build_sequence)
	{
	# node in the build sequence might have been build already.
	# when a node is build, its __BUILD_DONE field is set
	
	for my $child (keys %$node)
		{
		next if $child =~ /^__/ ;
		
		if(defined $node->{__CHILDREN_TO_BUILD} && exists $node->{$child}{__TRIGGERED} && defined $node->{$child}{__BUILD_DONE})
			{
			push @removed_nodes, $node->{$child}{__NAME} ;
			$node->{__CHILDREN_TO_BUILD}-- ;
			}
		}

	if($node->{__LEVEL} != 0) # we hide PBS top node
		{
		$level_statistics[$node->{__LEVEL} - 1 ]{nodes}++ ;
		}

	$node->{__WEIGHT} = $node->{__LEVEL} << 8 | ($node->{__CHILDREN_TO_BUILD} // 0) ;

	#enqueue node if it's terminal
	if(! defined $node->{__CHILDREN_TO_BUILD} || 0 == $node->{__CHILDREN_TO_BUILD})
		{
		if(defined $pbs_config->{DISPLAY_JOBS_INFO})
			{
			local $PBS::Output::indentation_depth ;
			$PBS::Output::indentation_depth++ ;
			PrintInfo2 "$node->{__NAME} ($node->{__WEIGHT})\n" ;
			}
			
		$number_of_terminal_nodes++ ;
		$build_queue->insert($node, $node->{__WEIGHT}) ;
		}
	}
	
if(defined $pbs_config->{DISPLAY_JOBS_INFO} && @removed_nodes)
	{
	PrintInfo2("Build: removed nodes from sequence (build already done):\n") ;
	local $PBS::Output::indentation_depth ;
	$PBS::Output::indentation_depth++ ;
	PrintInfo2 "$_\n" for @removed_nodes ;
	}
			
	
return($build_queue, $number_of_terminal_nodes, \@level_statistics) ;
}

#----------------------------------------------------------------------------------------------------------------------

sub GetNumberOfBuilders
{
my ($number_of_terminal_nodes, $pbs_config, $distributor)  = @_ ;

my $number_of_builders = $pbs_config->{JOBS} ;

if($number_of_builders > 0)
	{
	$number_of_builders = $number_of_builders > $distributor->GetNumberOfShells() ? $distributor->GetNumberOfShells() : $number_of_builders ;
	}
else
	{
	# let distributor determine the number of build threads
	$number_of_builders = $pbs_config->{JOBS} = $distributor->GetNumberOfShells() ;
	}
	
if($number_of_builders > $number_of_terminal_nodes)
	{
	$number_of_builders = $number_of_terminal_nodes ;
	}

$number_of_builders ||= 1 ; #safeguard for user errors

my $builder_plural = '' ; $builder_plural = 'es' if($number_of_builders > 1) ;
my $build_process = "build process$builder_plural" ;

PrintInfo("Build: using $number_of_builders $build_process out of maximum $pbs_config->{JOBS} for $number_of_terminal_nodes terminal nodes.\n") ;

return($number_of_builders ) ;
}

#----------------------------------------------------------------------------------------------------------------------

sub StartBuilders
{
my ($number_of_builders, $pbs_config, $distributor, $inserted_nodes)  = @_ ;

my @builders ;
for my$builder_index (0 .. ($number_of_builders - 1))
	{
	my $shell = $distributor->GetShell($builder_index) ;
	
	my ($builder_channel) = StartBuilderProcess
				(
				$pbs_config,
				$inserted_nodes,
				$shell,
				"[$builder_index] " . __PACKAGE__ . ' ' . __FILE__ . ':' . __LINE__,
				) ;
				
	unless(defined $builder_channel)
		{
		PrintError "Build: Couldn't start build process #$_!\n" ;
		die "\n" ;
		}
	
	print $builder_channel "GET_PROCESS_ID" . "__PBS_FORKED_BUILDER__" . "\n";
	
	my $child_pid = -1 ;
	while(<$builder_channel>)
		{
		last if /__PBS_FORKED_BUILDER__/ ;
		chomp ;
		$child_pid = $_ ;
		}
	
	$builders[$builder_index] = 
		{
		INDEX    => $builder_index,
		PID      => $child_pid,
		CHANNEL  => $builder_channel,
		SHELL    => $shell,
		BUILDING => 0,
		NODE     => undef,
		} ;
	}

return(\@builders) ;
}

#----------------------------------------------------------------------------------------------------------------------

sub StartBuilderProcess
{
# all arguments are passed to PBS::Build::ForkedNodeBuilder::NodeBuilder
#my ($pbs_config, $build_sequence, $inserted_nodes, $shell, $builder_info) = @_ ;

# PBS sends the name of the node to build, the builder returns the build result
my ($to_child, $to_parent) ;
socketpair($to_child, $to_parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC)  or  die "socketpair: $!";

my $pid = fork() ;
if($pid)
	{
	close($to_parent) ;
	#~ shutdown($to_parent, 2);
	
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
	#~ shutdown($to_child, 2);
	
	$to_parent->autoflush(1) ;
	
	PBS::Build::ForkedNodeBuilder::NodeBuilder($to_parent, @_) ; # waits for commands from parent
	}
}

#-------------------------------------------------------------------------------------------------------

sub CreateProgressBar
{
my ($pbs_config, $number_of_nodes_to_build) = @_ ;

if($pbs_config->{DISPLAY_PROGRESS_BAR})
	{
	return
		(
		PBS::ProgressBar->new
			({
			count => $number_of_nodes_to_build,
			ETA   => "linear", 
			})
		);
	}
}

#----------------------------------------------------------------------------------------------------------------------

sub WaitForBuilderToFinish
{
my ($pbs_config, $builders) = @_ ;
	
my $select_all = new IO::Select ;
my @waiting_for_messages ;

my $number_of_builders = @$builders ;

for (0 .. ($number_of_builders - 1))
	{
	if($builders->[$_]{BUILDING} == 1)
		{
		push @waiting_for_messages, "$builders->[$_]{NODE}{__NAME} on '" . $builders->[$_]{SHELL}->GetInfo() ;
		$select_all->add($builders->[$_]{CHANNEL}) ;
		}
	}

my @built_nodes ;

if(@waiting_for_messages)
	{
	if(defined $pbs_config->{DISPLAY_JOBS_RUNNING})
		{
		PrintWarning "Build: waiting for:\n" ;
		
		local $PBS::Output::indentation_depth ;
		$PBS::Output::indentation_depth++ ;
		
		PrintWarning "$_\n" for(@waiting_for_messages) ;
		print STDERR "\n" ;
		}
		
	# block till we get end of build from a builder thread
	my @sockets_ready = $select_all->can_read() ; 
	
	for (0 .. ($number_of_builders - 1))
		{
		for my $socket_ready (@sockets_ready)
			{
			if($socket_ready == $builders->[$_]{CHANNEL})
				{
				push @built_nodes, $builders->[$_] ;
				}
			}
		}
	}

return(@built_nodes) ;
}

#----------------------------------------------------------------------------------------------------------------------
my $build_parallel_timestamp = 0 ;

sub StartNodesBuild
{
my ($pbs_config, $build_queue, $builders, $node_build_index, $number_of_nodes_to_build, $builder_stats) = @_ ;

my $started_builders = 0 ;

PrintInfo2 "Build: starting:\n" 
	if defined $pbs_config->{DISPLAY_JOBS_INFO} ;

my $available = chars() - length($PBS::Output::indentation x ($PBS::Output::indentation_depth)) ;
my $em = String::Truncate::elide_with_defaults({ length => $available, truncate => 'middle' });

# find which builder finished, start building on them
for my $builder (@$builders)
	{
	next if $builder->{BUILDING} != 0 ; # skip active builders

	my $node_to_build ; 
	
	#find a node to build which didn't have a descendent that failed
	while( defined( $node_to_build = $build_queue->pop() )  && exists $node_to_build->{__HAS_FAILED_CHILD} ) { ; }

	return 0 unless defined $node_to_build ;
	
	$started_builders++ ;

	$builder->{BUILDING} = 1 ;
	$builder->{NODE} = $node_to_build ;
	
	$node_to_build->{__SHELL_ORIGIN} = __PACKAGE__ . __FILE__ . __LINE__ ;
	
	if(defined $builder->{SHELL})
		{
		$node_to_build->{__SHELL_INFO} = $builder->{SHELL}->GetInfo() ;
		}
		
	# keep some stats on which builder ran
	$builder_stats->{'PID ' . $builder->{PID}}{RUNS}++ ;
	$builder_stats->{'PID ' . $builder->{PID}}{NAME} = $builder->{SHELL}->GetInfo() ;
	
	my $override = exists $node_to_build->{__SHELL_OVERRIDE}
			? " [L] "
			: '' ;

	push @{$builder_stats->{'PID ' . $builder->{PID}}{NODES}}, 
		"$node_to_build->{__NAME}$override" ;
		
	my $node_index = $started_builders + $node_build_index ;
	SendIpcToBuildNode($pbs_config, $node_to_build, $node_index, $number_of_nodes_to_build, $builder) ;
	
	# keep the sequence in which the node where build
	$node_to_build->{__BUILD_PARALLEL_TIMESTAMP} = $build_parallel_timestamp++ ;
	
	my $distance = @$builders - $builder->{INDEX} ;  

	if($pbs_config->{DISPLAY_PROGRESS_PER_BUILD_PROCESS})
		{
		PrintInfo3 "\e[${distance}A"
				. "\r\e[K"
				. $em ->("Builder $builder->{INDEX}: $node_to_build->{__NAME}")
				. "\e[${distance}B" ;
		}

	if(defined $pbs_config->{DISPLAY_JOBS_INFO})
		{
		my $percent_done = int(($node_index * 100) / $number_of_nodes_to_build) ;
		my $node_build_sequencer_info = "$node_index/$number_of_nodes_to_build, $percent_done%" ;
		
		local $PBS::Output::indentation_depth ;
		$PBS::Output::indentation_depth++ ;
		PrintInfo2 "$node_to_build->{__NAME} ($node_build_sequencer_info) in '@{[$builder->{SHELL}->GetInfo()]}' pid: $builder->{PID}\n" ;
		}
	}

print STDERR "\n" if(defined $pbs_config->{DISPLAY_JOBS_INFO}) ;

return($started_builders) ;
}

#---------------------------------------------------------------------------------------------------------------

sub SendIpcToBuildNode
{
my ($pbs_config, $node, $node_index, $number_of_nodes_to_build, $builder) = @_ ;
my $node_name = $node->{__NAME} ; 

$number_of_nodes_to_build = 1 if $number_of_nodes_to_build < 1 ;

# IPC start the build
my $percent_done = int(($node_index * 100) / $number_of_nodes_to_build ) ;
my $builder_channel = $builder->{CHANNEL} ;

# leaks file handles !!!
#~ print `lsof |  grep pbs | wc -l ` . $node_name ;
print $builder_channel "BUILD_NODE" . "__PBS_FORKED_BUILDER__"
			. $node_name . "__PBS_FORKED_BUILDER__"
			. "$node_index/$number_of_nodes_to_build, $percent_done%\n" ;
}

#---------------------------------------------------------------------------------------------------------------

sub CollectNodeBuildResult
{
my ($pbs_config, $built_node, $builders) = @_ ;
	
my $builder_channel ;

for my $builder (@$builders)
	{
	if($builder->{NODE} == $built_node)
		{
		$builder_channel = $builder->{CHANNEL} ;
		$builder->{BUILDING} = 0 ;
		last ;
		}
	}

unless ($builder_channel)
	{
	PrintError "Build: can't find builder for built node '$built_node->{__NAME}'\n" ;
	die "\n" ;
	}

my ($build_result,$build_message) = split /__PBS_FORKED_BUILDER__/, (<$builder_channel> // "0__PBS_FORKED_BUILDER__No message\n") ;
$build_result = BUILD_FAILED unless defined $build_result ;

my ($build_time, $error_output) = (-1, '') ;

print STDERR "\n" unless $build_result == BUILD_SUCCESS ;

if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	PrintWarning("--bi defined, continuing.\n") ;
	print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
	
	while(<$builder_channel>)
		{
		last if /__PBS_FORKED_BUILDER__/ ;
		print STDERR $_ ;
		}
	}
else
	{
	print $builder_channel "GET_BUILD_TIME" . "__PBS_FORKED_BUILDER__" . "\n";
	
	while(<$builder_channel>)
		{
		last if /__PBS_FORKED_BUILDER__/ ;
		chomp ;
		$build_time = $_ ;
		}
	
	my $no_output = defined $PBS::Shell::silent_commands && defined $PBS::Shell::silent_commands_output ;
	
	if($build_result == BUILD_SUCCESS)
		{
		$built_node->{__BUILD_DONE} = "PBS::Build::Forked Done." ;

		unless($no_output)
			{
			print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;

			# collect builder output and display it
			while(<$builder_channel>)
				{
				last if /__PBS_FORKED_BUILDER__/ ;
				print STDERR $_ unless $no_output ;
				}
			}
		}
	else
		{
		# the build failed, save the builder output to display later and stop building
		PrintError "Build: '$built_node->{__NAME}', error will be reported below.\n" ;
			  
		print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
		while(<$builder_channel>)
			{
			last if /__PBS_FORKED_BUILDER__/ ;
			$error_output  .= $_ ;
			}
		}
	}
	
if(defined $pbs_config->{DISPLAY_JOBS_INFO})
	{
	PrintInfo "Build: '$built_node->{__NAME}': build result: $build_result, message: $build_message\n" ;
	}
	
return($build_result, $build_time, $error_output) ;
}

#---------------------------------------------------------------------------------------------------------------

sub EnqueueNodeParents
{
my ($pbs_config, $node, $build_queue) = @_ ;

# check if any node waiting for a child node to be build can be build
for my $parent (@{$node->{__PARENTS}})
	{
	$parent->{__CHILDREN_TO_BUILD}-- ;
	
	next if $parent->{__NAME} =~ /^__/ ;
	
	if(0 == $parent->{__CHILDREN_TO_BUILD})
		{
		if(defined $pbs_config->{DISPLAY_JOBS_INFO})
			{
			PrintInfo2 "Build: enqueuing parent '$parent->{__NAME}'.\n" ;
			}
			
		$build_queue->insert($parent, $parent->{__WEIGHT}) ;
		}
	}
}

#---------------------------------------------------------------------------------------------------------------

sub TerminateBuilders
{
my ($builders) = @_;
my $number_of_builders = @$builders ;

PrintInfo "Build: terminating build processes [$number_of_builders]\n" ;

for my $builder (@$builders)
	{
	my $channel = $builder->{CHANNEL} ; 	
	print $channel "STOP_PROCESS\n" ;
	}
	
for my $builder (@$builders)
	{
	waitpid $builder->{PID}, 0 ;
	}
}

#------------------------------------------------------------------------------------------------------------

1 ;

__END__

=head1 NAME

PBS::Build::Forked -

=head1 DESCRIPTION

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut


