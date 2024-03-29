
package PBS::Build::Forked ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.04' ;

use Data::TreeDumper ;
use File::Slurp qw(append_file write_file);
use IO::Select ;
use List::PriorityQueue ;
use List::Util qw(all) ;
use Socket;
use String::Truncate ;
use Term::ANSIColor qw( :constants color) ;
use Term::Size::Any qw(chars) ;
use Text::ANSI::Util qw( ta_highlight ta_length);
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Build ;
use PBS::Build::ForkedNodeBuilder ;
use PBS::Build::NodeBuilder ;
use PBS::Constants ;
use PBS::Distributor ;
use PBS::Output ;

#-------------------------------------------------------------------------------

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

my $target = $pbs_config->{TARGETS}[0] // 'no target' ;
my $number_of_nodes_to_build = scalar(grep {$_->{__NAME} !~ /^__/} @$build_sequence) ; # remove PBS root

my $node_build_index = 0 ;

my $root_node = @$build_sequence[-1] ; # we guess, wrongly, that there is only one root in the build sequence

if($pbs_config->{DISPLAY_PROGRESS_BAR} && $pbs_config->{DISPLAY_PROGRESS_BAR_PROCESS})
	{
	Say Info3 'Build' for (0 .. ($number_of_builders - 1)) ;
	}

my $available = (chars() // 10_000) - length($PBS::Output::indentation x ($PBS::Output::indentation_depth)) ;
my $em = String::Truncate::elide_with_defaults({ length => ($available < 3 ? 3 : $available) , truncate => 'middle' });
my @failed_nodes ;

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
	
	
	# PBS::RPC::Handle(@builder) # todo: check if build send an RPC request
	
	for my $builder (@builders)
		{
		my $built_node = $builder->{NODE} ;
		
		if($built_node->{__LEVEL} != 0) # hide PBS top node
			{
			$level_statistics->[$built_node->{__LEVEL} - 1 ]{nodes}++ ;
			}
		
		my ($build_result, $build_time, $node_error_output) =
			 CollectNodeBuildResult($pbs_config, $built_node, $builders) ;
		
		$number_of_already_build_node++ ;
		
		write_file($pbs_config->{TRIGGERS_FILE}, {append => 1, err_mode => "carp"}, "{NAME => '$built_node->{__NAME}', BUILD_RESULT => $build_result},\n") or 
			do
			{
			Say Error "Build: couldn't append to trigger file '$pbs_config->{TRIGGERS_FILE}'" ;
			die "\n" ;
			} ;
		
		my @actions_entries = grep { $built_node->{__NAME} =~ $_->[0]} @{$pbs_config->{NODE_BUILD_ACTIONS}} ;
		
		for my $template (grep { m/^\s*message\s+/i } map {@$_} @actions_entries)
			{
			(my $text = $template) =~ s/^\s*message\s+//i ;
			$text =~ s/%name/$built_node->{__NAME}/g ;
			$text =~ s/%build_result/$build_result/g ;
			
			Say User "Queue: $text" if $text ne q{} ;
			}
			
		for my $stop (grep { m/^\s*stop\b/i } map { @$_ } @actions_entries)
			{
			(my $text = $stop) =~ s/^\s*stop\s*//i ;
			$text =~ s/%name/$built_node->{__NAME}/g ;
			$text =~ s/%build_result/$build_result/g ;
			
			$text = "'$built_node->{__NAME}'" if $text eq q{} ;
			
			Say Warning "Stop : $text" ;
			
			$number_of_failed_builders++ ;
			$error_output = "\t\tstopped by user defined action\n" ;
			}
			
		if($build_result == BUILD_SUCCESS)
			{
			if($pbs_config->{DISPLAY_PROGRESS_BAR})
				{
				if($pbs_config->{DISPLAY_PROGRESS_BAR_FILE})
					{
					PrintInfo3 "\r\e[K$built_node->{__NAME}\n" ;
					}
				elsif($pbs_config->{DISPLAY_PROGRESS_BAR_PROCESS})
					{
					for ($number_of_builders)
						{
						my $distance = $number_of_builders - $builder->{INDEX} ;  
						
						PrintInfo2 "\e[${distance}A"
								. "\r\e[K"
								. $em ->("Queue: [$builder->{INDEX}] $built_node->{__NAME}")
								. "\e[${distance}B" ;
						}
					}
				
				my $time_remaining = (tv_interval ($t0, [gettimeofday]) / $number_of_already_build_node) * ($number_of_nodes_to_build - $number_of_already_build_node) ;
				
				$time_remaining = $time_remaining < 60 
							? sprintf("%0.2f", $time_remaining) . "s." 
							: sprintf("%02d:%02d:%02d",(gmtime($time_remaining))[2,1,0]) ;
				
				do
					{
					my $remaining_nodes = $number_of_nodes_to_build - $number_of_already_build_node ;
				
					PrintInfo "\r\e[KQueue: ETA: $time_remaining, nodes: $remaining_nodes"
						if $pbs_config->{DISPLAY_PROGRESS_ETA} ;
				
					if (0 == $remaining_nodes)
						{
						PrintNoColor "\r\e[K" ;
						
						my $build_time = '' ;
						$build_time = sprintf "time: %0.2f s, sub time: %0.2f s.", tv_interval ($t0, [gettimeofday]), $builder_using_perl_time
							if $pbs_config->{DISPLAY_TOTAL_BUILD_TIME} ;
							
						Say EC "<I>Build: success<I3>, target: $target<I2>, nodes: $number_of_already_build_node, $build_time, pid: $$"
							unless $pbs_config->{QUIET} ;
						}
					}
					unless $pbs_config->{DISPLAY_NO_PROGRESS_BAR} || $number_of_failed_builders ;
				}
			
			$builder_using_perl_time += $build_time 
				if PBS::Build::NodeBuilderUsesPerlSubs($built_node) ;
			
			EnqueueNodeParents($pbs_config, $built_node, $build_queue) ;
			
			if(defined $pbs_config->{DISPLAY_JOBS_RUNNING})
				{
				my $index = 1 ;
				for my $level (@$level_statistics)
					{
					Say Info6 "Queue: level: " . $index++ . ', done: ' . ($level->{done} // 0) . ', total: ' . $level->{nodes}  ; 
					}
				}
			}
		else
			{
			$error_output .= $node_error_output ;
			$number_of_failed_builders++ ;
			
			$excluded += MarkAllParentsAsFailed($pbs_config, $built_node) ;
			push @failed_nodes, $built_node ;
			}
		
		}
	}

TerminateBuilders($builders) ;

SWT \%builder_stats, 'Queue: process statistics:', DISPLAY_ADDRESS => 0 if defined $pbs_config->{DISPLAY_SHELL_INFO} ;

my $build_time = sprintf "time: %0.2f s, sub time: %0.2f s.", tv_interval ($t0, [gettimeofday]), $builder_using_perl_time ;
$build_time = EC "<I2>Build: $target, $build_time" ;

if ($number_of_failed_builders)
	{
	Say $build_time if $pbs_config->{DISPLAY_TOTAL_BUILD_TIME} ;

	Say EC "<E>Build: errors: $number_of_failed_builders\n" . $error_output . "\n" 
		. "<E>Build: nodes: $number_of_nodes_to_build, failed: $number_of_failed_builders"
		. ($excluded ? "<W>, excluded: $excluded" : '')
		. '<I>, success: ' . ($number_of_already_build_node - $number_of_failed_builders) ;
	
	Say EC "<E>Build: failed: <I3>$_->{__NAME}" . ($_->{__IMMEDIATE_BUILD} ? '<W3> [IMMEDIATE_BUILD]' : '')
		for @failed_nodes ;
	}

return !$number_of_failed_builders ;
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
	Say Warning "Queue: excluding node '$parent->{__NAME}'" if $pbs_config->{NO_STOP} ;
	$excluded++ ;
	
	$excluded += MarkAllParentsAsFailed($pbs_config, $parent) ;
	}

return $excluded ;
}

my %descendents ; # cache

sub GetDescendents
{
my ($node) = @_ ;

#SDT [ map { $_->{__NAME} } GetDescendents($node) ], $node->{__NAME} ;

return @{$descendents{$node->{__NAME}}} if exists $descendents{$node->{__NAME}} ;

my @all ;

for my $dependent ( grep { ! /^__/ } keys %$node )
	{
	push @all, $node->{$dependent} ;
	push @all, GetDescendents($node->{$dependent}) ;
	}

$descendents{$node->{__NAME}} = \@all ;

@all ;
}


#---------------------------------------------------------------------------------------------------------------

sub EnqueuTerminalNodes
{
my ($build_sequence, $pbs_config) = @_ ;

my ($build_queue, $number_of_terminal_nodes, @level_statistics) = (List::PriorityQueue->new, 0) ;
my (%already_built_nodes, @enqueued_nodes) ;

for my $node (reverse @$build_sequence)
	{
	# node in the build sequence might have been build already.
	# when a node is build, its __BUILD_DONE field is set
	
	for my $child (keys %$node)
		{
		next if $child =~ /^__/ ;
		
		if(defined $node->{__CHILDREN_TO_BUILD} && exists $node->{$child}{__TRIGGERED} && defined $node->{$child}{__BUILD_DONE})
			{
			#$already_built_nodes{$child}++ ;
			$node->{__CHILDREN_TO_BUILD}-- ;
			
			#Say Warning "Queue: $node->{__NAME}, decremented child to build count: $node->{__CHILDREN_TO_BUILD}, removed child: '$child'" ;
			}
		}
	
	$level_statistics[$node->{__LEVEL} - 1 ]{nodes}++ if $node->{__LEVEL} != 0 ; # hide PBS top node
	
	my $priority = $node->{__WEIGHT_PRIORITY}  // 8 ; # set by parent or default
	
	my $inherit_priority ;
	for my $actions (grep { $node->{__NAME} =~ $_->[0] } @{$pbs_config->{NODE_BUILD_ACTIONS}})
		{
		for my $prio (map { m/^\s*priority\s+(\d+)/i ? $1 : () } @$actions)
			{
			Say Warning 'PBS: invalid priority in --node_build_actions, must be 0 <= prio <= 8, ignoring' && next if $prio >= 9 ;
		
			$priority = $prio if $prio < $priority ;
			$inherit_priority++ ;
			}
		}

	all { $_->{__WEIGHT_PRIORITY} = $priority if $priority < $_->{__WEIGHT_PRIORITY} ; 1 } GetDescendents($node) if $inherit_priority ;

	$node->{__WEIGHT} = $node->{__LEVEL} << $priority | ($node->{__CHILDREN_TO_BUILD} // 0) ;
	$node->{__WEIGHT_PRIORITY} = $priority ;
	
	# give lowest weight to remote node
	$node->{__WEIGHT} = 16 * 1024 if exists $node->{__PARALLEL_DEPEND} && ! exists $node->{__PARALLEL_HEAD} ;
	
	#enqueue node if it's terminal
	if(! defined $node->{__CHILDREN_TO_BUILD} || 0 == $node->{__CHILDREN_TO_BUILD})
		{
		if(defined $pbs_config->{DISPLAY_JOBS_INFO})
			{
			Say EC "<I2>Queue: $node->{__NAME}, weight: $node->{__WEIGHT}/"
				. ( $priority != 8 ? "<W3>$priority" : "<I2>$priority") ;
			}
			
		$number_of_terminal_nodes++ ;
		$build_queue->insert($node, $node->{__WEIGHT}) ;
		}
	}
	
	#Say Info2 "Queue: already built $_ ($already_built_nodes{$_})" for (sort keys %already_built_nodes) ;

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

Say Info "Build: process: $number_of_builders, max: $pbs_config->{JOBS}, terminal nodes: $number_of_terminal_nodes"
	if defined $pbs_config->{DISPLAY_JOBS_INFO} ;

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
	
	my ($builder_channel, $pid) = StartBuilderProcess
				(
				$pbs_config,
				$inserted_nodes,
				$shell,
				"[$builder_index] " . __PACKAGE__ . ' ' . __FILE__ . ':' . __LINE__,
				) ;
				
	unless(defined $builder_channel)
		{
		Say Error "Build: Couldn't start build process #$builder_index" ;
		die "\n" ;
		}
	else
		{
		Say Info6 "Build: started build process, index: $builder_index, pid: $pid" if defined $pbs_config->{DISPLAY_JOBS_RUNNING} ;
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
my ($pbs_config, $build_sequence, $inserted_nodes, $shell, $builder_info) = @_ ;

# PBS sends the name of the node to build, the builder returns the build result
my ($to_child, $to_parent) ;
socketpair($to_child, $to_parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC)  or  die "socketpair: $!";

my $pid = fork() ;
if($pid)
	{
	close($to_parent) ;
	
	$to_child->autoflush(1);
	
	return($to_child, $pid) ;
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
	
	PBS::Build::ForkedNodeBuilder::NodeBuilder($to_parent, @_) ; # waits for commands from parent
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
	if($builders->[$_]{BUILDING})
		{
		my $builder = $builders->[$_] ;
		push @waiting_for_messages, "'$builder->{NODE}{__NAME}', shell: '" . $builder->{SHELL}->GetInfo() . ', builder pid:' .  $builder->{PID} ;
		$select_all->add($builders->[$_]{CHANNEL}) ;
		}
	}

my @built_nodes ;

if(@waiting_for_messages)
	{
	if(defined $pbs_config->{DISPLAY_JOBS_RUNNING})
		{
		Say Info6 "Queue : waiting for $_" for(@waiting_for_messages) ;
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

my $available = (chars() // 10_000) - length($PBS::Output::indentation x ($PBS::Output::indentation_depth)) ;
my $em = String::Truncate::elide_with_defaults({ length => ($available < 3 ? 3 : $available) , truncate => 'middle' });

# find which builder finished, start building on them
for my $builder (@$builders)
	{
	next if $builder->{BUILDING} ; # skip active builders

	my $node_to_build ; 
	
	# find a node to build which didn't have a descendent that failed
	while( defined( $node_to_build = $build_queue->pop() ) && exists $node_to_build->{__HAS_FAILED_CHILD} ) { ; }

	return 0 unless defined $node_to_build ;
	
	$started_builders++ ;

	$builder->{BUILDING}++ ;
	$builder->{NODE} = $node_to_build ;
	
	$node_to_build->{__SHELL_ORIGIN} = __PACKAGE__ . __FILE__ . __LINE__ ;
	
	if(defined $builder->{SHELL})
		{
		$node_to_build->{__SHELL_INFO} = $builder->{SHELL}->GetInfo() ;
		}
		
	my $override = exists $node_to_build->{__SHELL_OVERRIDE} ? " [L] " : '' ;

	push @{$builder_stats->{'PID ' . $builder->{PID}}{NODES}}, 
		"$node_to_build->{__NAME}$override" ;
		
	# keep the sequence in which the node where build
	$node_to_build->{__BUILD_PARALLEL_TIMESTAMP} = $build_parallel_timestamp++ ;
	
	# keep some stats on which builder ran
	$builder_stats->{'PID ' . $builder->{PID}}{RUNS}++ ;
	$builder_stats->{'PID ' . $builder->{PID}}{NAME} = $builder->{SHELL}->GetInfo() ;
	
	my $node_index = $started_builders + $node_build_index ;
	SendIpcToBuildNode($pbs_config, $node_to_build, $node_index, $number_of_nodes_to_build, $builder) ;
	
	my $distance = @$builders - $builder->{INDEX} ;  

	if($pbs_config->{DISPLAY_PROGRESS_BAR_PROCESS})
		{
		PrintInfo3 "\e[${distance}A"
				. "\r\e[K"
				. $em ->("Queue: $node_to_build->{__NAME}, builder: $builder->{INDEX}")
				. "\e[${distance}B" ;
		}

	if(defined $pbs_config->{DISPLAY_JOBS_INFO})
		{
		my $priority = $node_to_build->{__WEIGHT_PRIORITY} ;
		my $percent_done = int(($node_index * 100) / $number_of_nodes_to_build) ;
		my $node_build_sequencer_info = "$node_index/$number_of_nodes_to_build, $percent_done%" ;
		
		Say EC  "<I2>Queue: $node_to_build->{__NAME}, weight: $node_to_build->{__WEIGHT}/"
			. ( $priority != 8 ? "<W>$priority" : "<I2>$priority")
			. "<I2>, stat: $node_build_sequencer_info, pid: $builder->{PID}" ;
		}
	}

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

my @bg_color_classes = ([qw ( box_11 box_12 )], [qw ( box_21 box_22 )]) ;
my $bg_color_class = 0 ;

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
	Say Error "Build: can't find builder for built node '$built_node->{__NAME}'" ;
	die "\n" ;
	}

my ($type, $build_result,$build_message) = split /__PBS_FORKED_BUILDER__/, (<$builder_channel> // "0__PBS_FORKED_BUILDER__No message\n") ;
chomp $build_message ;
$build_message = '"' . $build_message . '"' ;

$build_result = BUILD_FAILED unless defined $build_result ;

my ($build_time, $error_output) = (-1, '') ;

#print STDERR "\n" unless $build_result == BUILD_SUCCESS ;

if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
	{
	Say Warning "--bi defined, continuing." ;
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
	
	my $no_output = $PBS::Shell::silent_commands && $PBS::Shell::silent_commands_output ;

	my @bg_colors = @{$bg_color_classes[$bg_color_class]} ;
	$bg_color_class ^= 1 ;

	my $bg_color = 0 ;

	if($build_result == BUILD_SUCCESS)
		{
		$built_node->{__BUILD_DONE} = "PBS::Build::Forked Done." ;
		
		if(exists $built_node->{__VIRTUAL})
			{
			$built_node->{__MD5} = 'VIRTUAL' ;
			}
		else
			{
			my $build_name = $built_node->{__BUILD_NAME} ;
			
			PBS::Digest::FlushMd5Cache($build_name) ;
			my $current_md5 = PBS::Digest::GetFileMD5($build_name) ;
			
			$built_node->{__MD5} = $current_md5 ;
			}
		
		unless($no_output)
			{
			print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
			
			my $print_separator ;
			
			# collect builder output and display it
			while(<$builder_channel>)
				{
				last if /__PBS_FORKED_BUILDER__/ ;
				
				chomp ;
				$_ = $PBS::Output::indentation if ($_ eq '' || $_ eq "\t") ;
				
				my $length = length($PBS::Output::indentation) || 4 ;
				my $o = $pbs_config->{BOX_NODE}
						? ta_highlight((ta_length($_) == 0 ? (' ' x $length) : $_) , qr/.{$length}/, GetColor($bg_colors[$bg_color])) 
						: $_ ;
						
				PrintVerbatim "$o\n" ;
				
				$print_separator++ unless $o eq q{} ;
				}
			
			PrintVerbatim "\n" if $print_separator ;
			}
		}
	else
		{
		# the build failed, save the builder output to display later and stop building
		Say EC "<I>Build: <I3>$built_node->{__NAME} <E>error will be reported below" ;
		  
		print $builder_channel "GET_OUTPUT" . "__PBS_FORKED_BUILDER__" . "\n" ;
		while(<$builder_channel>)
			{
			last if /__PBS_FORKED_BUILDER__/ ;
			
			chomp ;
			$_ = '   ' if ($_ eq '' || $_ eq "\t") ;
			
			my $o = $pbs_config->{BOX_NODE}
					? ta_highlight((ta_length($_) == 0 ? ' ' : $_) , qr/./, GetColor('on_error')) 
					: $_ ;
			
			$error_output .= $o . "\n" ;
			}
		}
	}
	
if($build_result == BUILD_FAILED)
	{
	Say Error "Build: $built_node->{__NAME}, result: $build_result, message: $build_message" ;
	}
else
	{
	Say Info2 "Build: $built_node->{__NAME}, message: $build_message"
		if defined $pbs_config->{DISPLAY_JOBS_INFO} ;
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
			my $priority = $parent->{__WEIGHT_PRIORITY} ;

			Say EC "<I2>Queue: $parent->{__NAME} [0], weight: $parent->{__WEIGHT}/"
				. ( $priority != 8 ? "<W3>$priority" : "<I2>$priority" ) ;
			}

		$build_queue->insert($parent, $parent->{__WEIGHT}) ;
		}
	else
		{
		Say Info2 "Tally: $parent->{__NAME} [$parent->{__CHILDREN_TO_BUILD}], built: $node->{__NAME}"
				if $pbs_config->{DISPLAY_JOBS_INFO} && ! $pbs_config->{DISPLAY_JOBS_NO_TALLY} ;
		}
	}
}

#---------------------------------------------------------------------------------------------------------------

sub TerminateBuilders
{
my ($builders) = @_;
my $number_of_builders = @$builders ;

#Say Info "Queue: terminating build processes [$number_of_builders]" ;

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


