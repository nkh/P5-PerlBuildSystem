
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

$|++ ;

#-------------------------------------------------------------------------------


sub Build
{
=pod

The parallelisation algorithm is simple and effective enough as most dependency trees have many dependencies 
for each node making the graph look triangular to a very wide base triangular. Note that this is not the most
effective parallelisation algorithm. Building the nodes that have parents with few children first is more
effective as it maximizes that number of build thread that are active. This means that we build hight first instead
for depth first. Since nodes have different build time, the parallelisation algorithm (in fact the prioritisation of the 
terminal nodes) should be dynamic to be optimal and in that case, should take into account the load on the cpu building
the node as build time is not only a factor of the CPU but also network and other I/O.

keeping previous build time to build the longest nodes to build first can also make the end of the build more effective as it
keeps the builder pool full.

=cut

my $t0 = [gettimeofday];

my $pbs_config      = shift ;
our $build_sequence = shift ;
my $inserted_nodes  = shift ;

my $build_queue = EnqueuTerminalNodes($build_sequence, $pbs_config) ;


my $number_of_nodes_to_build = scalar(@$build_sequence) - 1 ; # -1 as PBS root is never build
my $number_of_terminal_nodes = scalar(keys %$build_queue) ;

my $distributor        = PBS::Distributor::CreateDistributor($pbs_config, $build_sequence) ;
my $number_of_builders = GetNumberOfBuilders($number_of_terminal_nodes, $pbs_config, $distributor) ;
my $builders           = StartBuilders($number_of_builders, $pbs_config, $distributor, $build_sequence, $inserted_nodes) ;

my $number_of_already_build_node = 0 ;
my $number_of_failed_builders = 0 ;
my $error_output = '' ;

my %builder_stats ;
my $builder_using_perl_time = 0 ;

my $progress_bar = CreateProgressBar($pbs_config, $number_of_nodes_to_build) ;
my $node_build_index = 0 ;

my $root_node = @$build_sequence[-1] ; # we guess, wrongly, that there is only one root in the build sequence

my $parallel_build_state = 
sub
{
my ($tree) = @_ ;

if('HASH' eq ref $tree)
	{
	my @keys_to_dump ;
	
	for(sort keys %$tree)
		{
		if(/^__/)
			{
			if
			(
			   (/^__BUILD_NAME$/  && defined $pbs_config->{DEBUG_DISPLAY_TREE_NAME_BUILD})
			|| (/^__TRIGGERED$/   && defined $pbs_config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON})
			#~ || /^__VIRTUAL/
			)
				{
				# display these
				}
			else
				{
				next ;
				}
			}
			
		my $replacement_key_name = my $key_name = $_ ;
		if( ! /^__/)
			{
			if('HASH' eq ref $tree->{$key_name})
				{
				# triggered
				if(defined $pbs_config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED} && exists $tree->{$key_name}{__TRIGGERED})
					{
					$replacement_key_name = "* $key_name" ;
					}

				# building 
				if('HASH' eq ref $build_queue->{$key_name} && exists $build_queue->{$key_name}{PID})
                                        {
					$replacement_key_name = 
						Term::ANSIColor::color('yellow') 
						. $replacement_key_name
						. ' [Building] ' 
						#$PBS::OUTPUT::global_info2_escape_code
						. Term::ANSIColor::color('reset') 
						. Term::ANSIColor::color('green') 
						#. $PBS::OUTPUT::global_info_escape_code
						;
                                        }
				else
					{
					# Queued 
					if(exists $build_queue->{$key_name})
						{
						$replacement_key_name = 
							Term::ANSIColor::color('cyan') 
							. $replacement_key_name
							. ' [Queued] ' 
							#$PBS::OUTPUT::global_info2_escape_code
							. Term::ANSIColor::color('reset') 
							. Term::ANSIColor::color('green') 
							#. $PBS::OUTPUT::global_info_escape_code
							;
						}
					}
				
				# built
				if(exists $tree->{$key_name}{__BUILD_DONE})
					{
					my $build_timestamp = 
						exists $tree->{$key_name}{__BUILD_PARALLEL_TIMESTAMP} 
							? " @ t:$tree->{$key_name}{__BUILD_PARALLEL_TIMESTAMP}"
							: '' ;

					$replacement_key_name = 
						Term::ANSIColor::color('bold blue') 
						. $replacement_key_name
						. " [done$build_timestamp]"
						#$PBS::OUTPUT::global_info2_escape_code
						. Term::ANSIColor::color('reset') 
						. Term::ANSIColor::color('green') 
						#. $PBS::OUTPUT::global_info_escape_code ;
					}
				}
			}
		
		push @keys_to_dump, [$key_name, $replacement_key_name] ;
		}
	
	#return('HASH', undef, sort {$a =~ /^__/ ? 1 : $b =~ /^__/ ? 1 : 0 } sort @keys_to_dump) ;
	return('HASH', undef, @keys_to_dump) ;
	}
	
return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
} ;

while(%$build_queue)
	{
	# start building a node if a process is free and no error occured
	unless($number_of_failed_builders)
		{
		my $started_builders = StartEnqueuedNodesBuild
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
	
	PrintInfo DumpTree($root_node, 'Parallel build info:', FILTER => $parallel_build_state, DISPLAY_ADDRESS => 0) 
		if $pbs_config->{DISPLAY_JOBS_TREE} ;

	my @built_nodes = WaitForBuilderToFinish($pbs_config, $builders) ;
	
	
	@built_nodes || last if $number_of_failed_builders ; # stop if nothing is building and an error occured
		
	for my $built_node_name (@built_nodes)
		{
		my ($build_result, $build_time, $node_error_output) = CollectNodeBuildResult($pbs_config, $built_node_name, $build_queue) ;
		
		$number_of_already_build_node++ ;
		
		if($build_result == BUILD_SUCCESS)
			{
			$progress_bar->update($number_of_already_build_node) if $progress_bar ;
			$builder_using_perl_time += $build_time if PBS::Build::NodeBuilderUsesPerlSubs($build_queue->{$built_node_name}) ;
			
			PBS::Depend::SynchronizeAfterBuild($build_queue->{$built_node_name}{NODE}) ;
			EnqueueNodeParents($pbs_config, $build_queue->{$built_node_name}{NODE}, $build_queue) ;
			}
		else
			{
			$error_output .= $node_error_output ;
			$number_of_failed_builders++ ;
			}
		
		delete $build_queue->{$built_node_name} ;
		}
	}

TerminateBuilders($builders) ;

if($number_of_failed_builders)
	{
	PrintError "** Failed build@{[$number_of_failed_builders > 1 ? 's' : '']} **\n" ;
	print $error_output ;
	}

PrintInfo DumpTree($root_node, 'Parallel build, final state:', FILTER => $parallel_build_state, DISPLAY_ADDRESS => 0)
	if $pbs_config->{DISPLAY_JOBS_TREE} ;
	
if(defined $pbs_config->{DISPLAY_SHELL_INFO})
	{
	print WARNING DumpTree(\%builder_stats, '** Builder process statistics: **', DISPLAY_ADDRESS => 0) ;
	}
	
if($pbs_config->{DISPLAY_TOTAL_BUILD_TIME})
	{
	PrintInfo(sprintf("Total build time: %0.2f s. Perl subs time: %0.2f s.\n", tv_interval ($t0, [gettimeofday]), $builder_using_perl_time)) ;
	}

return(!$number_of_failed_builders) ;
}

#---------------------------------------------------------------------------------------------------------------

sub EnqueuTerminalNodes
{
my ($build_sequence, $pbs_config) = @_ ;
my %build_queue ;

my (@removed_nodes, @enqueued_nodes) ;

if(defined $pbs_config->{DISPLAY_JOBS_INFO})
	{
	PrintInfo2 "Enqueuing terminal nodes:\n" ;
	}
	
for my $node (@$build_sequence)
	{
	# node in the build sequence might have been build already.
	# when a node is build, its __BUILD_DONE field is set
	
	#print  "$node->{__NAME} " . (defined $node->{__CHILDREN_TO_BUILD} ? $node->{__CHILDREN_TO_BUILD} : 'undef') . "\n" ;
	for my $child (keys %$node)
		{
		next if $child =~ /^__/ ;
		
		if(defined $node->{__CHILDREN_TO_BUILD} && exists $node->{$child}{__TRIGGERED} && defined $node->{$child}{__BUILD_DONE})
			{
			push @removed_nodes, $node->{$child}{__NAME} ;
			$node->{__CHILDREN_TO_BUILD}-- ;
			}
		}

	#enqueue node if it's terminal
	#print  "$node->{__NAME} " . (defined $node->{__CHILDREN_TO_BUILD} ? $node->{__CHILDREN_TO_BUILD} : 'undef') . "\n" ;

	if(! defined $node->{__CHILDREN_TO_BUILD} || 0 == $node->{__CHILDREN_TO_BUILD})
		{
		if(defined $pbs_config->{DISPLAY_JOBS_INFO})
			{
			local $PBS::Output::indentation_depth ;
			$PBS::Output::indentation_depth++ ;
			PrintInfo2 "$node->{__NAME}\n" ;
			}
			
		$build_queue{$node->{__NAME}} = {NODE => $node} ;
		}
	}
	
if(defined $pbs_config->{DISPLAY_JOBS_INFO} && @removed_nodes)
	{
	PrintInfo2("Removed nodes from parallel sequence dependency (build already done):\n") ;
	local $PBS::Output::indentation_depth ;
	$PBS::Output::indentation_depth++ ;
	PrintInfo2 "$_\n" for @removed_nodes ;
	}
			
	
return(\%build_queue) ;
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

PrintInfo("Parallel build: using $number_of_builders $build_process out of maximum $pbs_config->{JOBS} for $number_of_terminal_nodes terminal nodes.\n") ;

return($number_of_builders ) ;
}

#----------------------------------------------------------------------------------------------------------------------

sub StartBuilders
{
my ($number_of_builders, $pbs_config, $distributor, $build_sequence, $inserted_nodes)  = @_ ;

my @builders ;
for my$builder_index (0 .. ($number_of_builders - 1))
	{
	my $shell = $distributor->GetShell($builder_index) ;
	
	my ($builder_channel) = StartBuilderProcess
				(
				$pbs_config,
				$build_sequence,
				$inserted_nodes,
				$shell,
				"[$builder_index] " . __PACKAGE__ . ' ' . __FILE__ . ':' . __LINE__,
				) ;
				
	unless(defined $builder_channel)
		{
		PrintError "Couldn't start a forked builder #$_!\n" ;
		die ;
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
		PID              => $child_pid,
		BUILDER_CHANNEL  => $builder_channel,
		SHELL            => $shell,
		BUILDING         => 0,
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
		push @waiting_for_messages, "$builders->[$_]{NODE} on '" . $builders->[$_]{SHELL}->GetInfo() ;
		$select_all->add($builders->[$_]{BUILDER_CHANNEL}) ;
		}
	}


my @build_nodes ;

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
		
	# block till we get end of build from a builder thread
	my @sockets_ready = $select_all->can_read() ; 
	
	for (0 .. ($number_of_builders - 1))
		{
		for my $socket_ready (@sockets_ready)
			{
			if($socket_ready == $builders->[$_]{BUILDER_CHANNEL})
				{
				push @build_nodes, $builders->[$_]{NODE} ;
				}
			}
		}
	}

return(@build_nodes) ;
}

#----------------------------------------------------------------------------------------------------------------------
my $build_parallel_timestamp = 0 ;

sub StartEnqueuedNodesBuild
{
my ($pbs_config, $build_queue, $builders, $node_build_index, $number_of_nodes_to_build, $builder_stats) = @_ ;

my $number_of_builders = @$builders ;
my $started_builders = 0 ;

if(defined $pbs_config->{DISPLAY_JOBS_INFO})
	{
	PrintInfo2 "Starting parallel build of:\n" ;
	}
	
for my $enqued_node (keys %$build_queue)
	{
	my $node_pid = $build_queue->{$enqued_node}{PID} ;
	
	next if defined $node_pid ; # node is under build
	
	my $pid = undef ;
	for (0 .. ($number_of_builders - 1))
		{
		if($builders->[$_]{BUILDING} == 0)
			{
			$pid = $builders->[$_] ;
			last ;
			}
		}
			
	if($pid)
		{
		$started_builders++ ;
		$build_queue->{$enqued_node}{PID} = $pid ;
		$pid->{BUILDING} = 1 ;
		$pid->{NODE} = $enqued_node ;
		
		# this info is for the root process. The modification we make here
		# are not seen in the builder processes
		$build_queue->{$enqued_node}{NODE}{__SHELL_ORIGIN} = __PACKAGE__ . __FILE__ . __LINE__ ;
		
		if(defined $pid->{SHELL})
			{
			$build_queue->{$enqued_node}{NODE}{__SHELL_INFO} = $pid->{SHELL}->GetInfo() ;
			}
			
		# keep some stats on which builder ran
		$builder_stats->{'PID ' . $pid->{PID}}{RUNS}++ ;
		$builder_stats->{'PID ' . $pid->{PID}}{NAME} = $pid->{SHELL}->GetInfo() ;
		
		unless(exists $build_queue->{$enqued_node}{NODE}{__SHELL_OVERRIDE})
			{
			push @{$builder_stats->{'PID ' . $pid->{PID}}{NODES}}, $enqued_node ;
			}
		else
			{
			push @{$builder_stats->{'PID ' . $pid->{PID}}{NODES}}, "$enqued_node [L]";
			}
			
		my $node_index = $started_builders + $node_build_index ;
		SendIpcToBuildNode($pbs_config, $build_queue->{$enqued_node}{NODE}, $node_index, $number_of_nodes_to_build, $pid) ;
		
		# keep the sequence in which the node where build
		$build_queue->{$enqued_node}{NODE}{__BUILD_PARALLEL_TIMESTAMP} = $build_parallel_timestamp++ ;
		
		if(defined $pbs_config->{DISPLAY_JOBS_INFO})
			{
			my $percent_done = int(($node_index * 100) / $number_of_nodes_to_build) ;
			my $node_build_sequencer_info = "$node_index/$number_of_nodes_to_build, $percent_done%" ;
			
			local $PBS::Output::indentation_depth ;
			$PBS::Output::indentation_depth++ ;
			PrintInfo2 "$build_queue->{$enqued_node}{NODE}{__NAME} ($node_build_sequencer_info) in '@{[$pid->{SHELL}->GetInfo()]}' pid: $pid->{PID}\n" ;
			}
	
		}
	else
		{
		last ;
		}
	}

print "\n" if(defined $pbs_config->{DISPLAY_JOBS_INFO}) ;

return($started_builders) ;
}

#---------------------------------------------------------------------------------------------------------------

sub SendIpcToBuildNode
{
my ($pbs_config, $node, $node_index, $number_of_nodes_to_build, $pid) = @_ ;
my $node_name = $node->{__NAME} ; 

# IPC start the build
my $percent_done = int(($node_index * 100) / $number_of_nodes_to_build ) ;
my $builder_channel = $pid->{BUILDER_CHANNEL} ;

# leaks file handles !!!
#~ print `lsof |  grep pbs | wc -l ` . $node_name ;
print $builder_channel "BUILD_NODE" . "__PBS_FORKED_BUILDER__"
			. $node_name . "__PBS_FORKED_BUILDER__"
			. "$node_index/$number_of_nodes_to_build, $percent_done%\n" ;
}

#---------------------------------------------------------------------------------------------------------------

sub CollectNodeBuildResult
{
my ($pbs_config, $built_node_name, $build_queue) = @_ ;
	
my $built_node = $build_queue->{$built_node_name}{NODE} ;

my $pid = $build_queue->{$built_node_name}{PID} ;
$pid->{BUILDING} = 0 ;

my $builder_channel = $pid->{BUILDER_CHANNEL} ;

my ($build_result,$build_message) = split /__PBS_FORKED_BUILDER__/, <$builder_channel> ;
$build_result = BUILD_FAILED unless defined $build_result ;

my $build_time = -1 ;
my $error_output = '' ;

print "\n" unless $build_result == BUILD_SUCCESS ;

if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	PrintWarning("--bi defined, continuing.\n") ;
	print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
	
	while(<$builder_channel>)
		{
		last if /__PBS_FORKED_BUILDER__/ ;
		print $_ ;
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
		print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
		
		# collect builder output and display it
		while(<$builder_channel>)
			{
			last if /__PBS_FORKED_BUILDER__/ ;
			print $_ unless $no_output ;
			}
		}
	else
		{
		# the build failed, save the builder output to display later and stop building
		PrintError "#------------------------------------------------------------------------------\n"
			  ."Error building node '$built_node_name'! Error will be reported bellow.\n" ;
			  
		print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
		while(<$builder_channel>)
			{
			last if /__PBS_FORKED_BUILDER__/ ;
			$error_output  .= $_ ;
			}
		}
	}
	
# handle log
if(defined (my $lh = $pbs_config->{CREATE_LOG}))
	{
	print $builder_channel "GET_LOG" . "__PBS_FORKED_BUILDER__" . "\n" ;
	while(<$builder_channel>)
		{
		last if /__PBS_FORKED_BUILDER__/ ;
		print $lh $_ ;
		}
	}
	
if(defined $pbs_config->{DISPLAY_JOBS_INFO})
	{
	PrintInfo "'$built_node_name': build result: $build_result, message: $build_message\n" ;
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
			PrintInfo2 "Enqueuing parent node '$parent->{__NAME}'.\n" ;
			}
			
		$build_queue->{$parent->{__NAME}} = {NODE => $parent} ;
		}
	}
}

#---------------------------------------------------------------------------------------------------------------

sub TerminateBuilders
{
my ($builders) = @_;
my $number_of_builders = @$builders ;

PrintInfo "\n** Terminating Builders **\n" ;

for my $builder_index (0 .. ($number_of_builders - 1))
	{
	my $builder_channel = $builders->[$builder_index]{BUILDER_CHANNEL} ;
	
	if($builders->[$builder_index]{BUILDING})
		{
		# 20 feb 2005, I don't think this can happend any more NK.
		# happend 20 May 2005 :-)
		die ; 
		}
		
	print $builder_channel "STOP_PROCESS\n" ;
	}
	
for (0 .. ($number_of_builders - 1))
	{
	waitpid($builders->[$_], 0) ;
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


