
package PBS::Check::ForkedCheck ;

use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

use PBS::Output ;
use PBS::Digest ;

use Time::HiRes qw(gettimeofday tv_interval) ;
use Socket;
use IO::Select ;

#-----------------------------------------------------------------------------------------------------------------------

sub ParallelCheckNodes
{
my ($pbs_config, $nodes, $node_names, $IsFileModified, $node_checker) = @_ ;

# location for MD5 computation
for my $node (keys %$nodes)
	{
	$nodes->{$node}{__MD5} //= '' ;

	if('VIRTUAL' ne $nodes->{$node}{__MD5})
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} =	exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;
		}
	}

my ($number_trigger_nodes, $trigger_log) = (0, '') ;
my $number_of_check_processes = $pbs_config->{CHECK_JOBS} ;
	
my $checkers = StartCheckers($number_of_check_processes, $pbs_config, $nodes, $node_names, $IsFileModified, $node_checker)  ;

if($pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES})
	{
	my @terminal_nodes = grep { exists $nodes->{$_}{__TERMINAL} } keys %$nodes ;
	PrintWarning "Warp: terminal nodes: " . scalar(@terminal_nodes) . "\n" ;

	my $checker_index = 0 ;
	for my $slice (distribute(scalar @terminal_nodes, $number_of_check_processes))
		{
		# slice and send node list to check, $checker->Check(@node_list)  ;
		my @nodes_to_check = @terminal_nodes[$slice->[0] .. $slice->[1]] ;
		StartCheckingNodes(@$checkers[$checker_index++], \@nodes_to_check, '')  ;
		}

	my %all_nodes_triggered ;

	my @checker_finished ;
	while(@checker_finished < $checker_index)
		{
		my @finished = WaitForCheckersToFinish($pbs_config, $checkers) ;

		for(@finished)
			{
			# collect list of removed nodes
			my ($nodes_triggered, $trigger_nodes) = CollectNodeCheckResult(@$checkers[$_]) ;

			$all_nodes_triggered{$_}++ for @{$nodes_triggered} ;

			$number_trigger_nodes += @$trigger_nodes ;
			$trigger_log .= "{ NAME => '$_'},\n" for @$trigger_nodes ;
			}

		push @checker_finished, @finished
		}

	# remove from dependency graph
	my @file_triggered_names = keys %all_nodes_triggered ;

	FlushMd5CacheMulti(\@file_triggered_names, $nodes) ; # nodes must still be in $nodes
	delete @{$nodes}{@file_triggered_names} ;
	}
else
	{
	my @nodes_per_level ;
	push @{$nodes_per_level[tr~/~/~]}, $_ for keys %$nodes ;
	shift @nodes_per_level unless defined $nodes_per_level[0] ;

	for my $level (reverse 0 .. @nodes_per_level - 1)
		{
		next unless defined $nodes_per_level[$level] ;
		next unless scalar(@{$nodes_per_level[$level]}) ;

		my $checker_index = 0 ;

		for my $slice (distribute(scalar @{$nodes_per_level[$level]}, $number_of_check_processes))
			{
			# slice and send node list to check, $checker->Check(@node_list)  ;
			my @nodes_to_check = @{$nodes_per_level[$level]}[$slice->[0] .. $slice->[1]] ;
			StartCheckingNodes(@$checkers[$checker_index++], \@nodes_to_check, $level)  ;
			}

		my %all_nodes_triggered ;

		my @checker_finished ;
		while(@checker_finished < $checker_index)
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

		# remove from dependency graph
		my @file_triggered_names = keys %all_nodes_triggered ;

		FlushMd5CacheMulti(\@file_triggered_names, $nodes) ; # nodes must still be in $nodes
		delete @{$nodes}{@file_triggered_names} ;

		# done with the level
		delete $nodes_per_level[$level] ;

		# remove trigger nodes from subsequent checks
		for my $nodes_per_level (@nodes_per_level)
			{
			$nodes_per_level = [ grep {! exists $all_nodes_triggered{$_}} @$nodes_per_level ] ;
			}
		}
	}

TerminateCheckers($pbs_config, $checkers) ;

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
my ($number_of_checkers, $pbs_config, $nodes, $node_names, $IsFileModified, $node_checker) = @_ ;

my @checkers ;
for my $checker_index (0 .. ($number_of_checkers - 1))
	{
	my ($checker_channel) = StartCheckerProcess
				(
				$pbs_config,
				$nodes,
				$node_names,
				$IsFileModified,
				$node_checker,
				) ;
				
	unless(defined $checker_channel)
		{
		PrintError "Warp: Couldn't start parallel checker #$_!\n" ;
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
#my ($pbs_config, $nodes, $node_names, $IsFileModified, $node_checker) = @_ ;

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
my ($pbs_config, $nodes, $node_names, $IsFileModified, $node_checker) = @_ ;

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
			(undef, my $level, my @nodes_to_check) = @command_and_args ;

			# checker caches are synchronized after process checks nodes, start with empty cache 
			PBS::Digest::FlushMd5Cache() ;
			
			my ($nodes_triggered, $trigger_nodes) =
				$node_checker->($pbs_config, $nodes, \@nodes_to_check , $node_names, $IsFileModified, $level) ;

			my (%s1, %s2) ;
			my @nodes_triggered = grep { !$s1{$_}++ } @$nodes_triggered ;
			my @trigger_nodes = grep { !$s2{$_}++ } @$trigger_nodes ;

			print $parent_channel join('__PBS_FORKED_CHECKER__', @nodes_triggered)
						. "__PBS_FORKED_CHECKER_ARG__"
						. join('__PBS_FORKED_CHECKER__', @trigger_nodes) 
						. "__PBS_FORKED_CHECKER__\n" ;
			
			last ;
			} ;
			
		/^GET_CACHE$/ and do
			{
			my $cache = PBS::Digest::GetMd5Cache() ;
			for (keys %$cache)
				{
				print $parent_channel 
						$_ 
						. "__PBS_FORKED_CHECKER__"
						. $cache->{$_} 
						. "__PBS_FORKED_CHECKER__" ;
				}
					
			print $parent_channel "__PBS_FORKED_CHECKER__\n" ;

			last ;
			} ;
		}
	}
exit ;
}

#---------------------------------------------------------------------------------------------------------------

sub StartCheckingNodes
{
my ($pid, $nodes_to_check, $level) = @_ ;

# IPC start the build
my $checker_channel = $pid->{CHECKER_CHANNEL} ;
$pid->{CHECKING} = 1 ;

print $checker_channel "CHECK_NODES" . "__PBS_FORKED_CHECKER__" . $level . "__PBS_FORKED_CHECKER__"
			. join("__PBS_FORKED_CHECKER__", @$nodes_to_check)
			. "__PBS_FORKED_CHECKER__\n" ;
}

#---------------------------------------------------------------------------------------------------------------

sub CollectNodeCheckResult
{
my ($pid) = @_ ;
	
my $checker_channel = $pid->{CHECKER_CHANNEL} ;

my $result = <$checker_channel> ;
chomp $result ;

my ($nodes_triggered, $trigger_nodes) = split /__PBS_FORKED_CHECKER_ARG__/, $result ;

my @nodes_triggered = split /__PBS_FORKED_CHECKER__/, $nodes_triggered ;
my @trigger_nodes = split /__PBS_FORKED_CHECKER__/, $trigger_nodes ;

#------------------
# synchronize cache
#------------------
print $checker_channel "GET_CACHE" . "__PBS_FORKED_CHECKER__" . "\n" ;
$result = <$checker_channel> ;
chomp $result ;

my %cache = (split /__PBS_FORKED_CHECKER__/, $result) ;

PBS::Digest::PopulateMd5Cache(\%cache) ;

return \@nodes_triggered, \@trigger_nodes ;
}

#---------------------------------------------------------------------------------------------------------------

sub TerminateCheckers
{
my ($pbs_config, $checkers) = @_ ;
my $number_of_checkers = @$checkers ;

PrintInfo "Warp: terminating checker processes [$number_of_checkers]\n" if $pbs_config->{DISPLAY_JOBS_INFO} ;

for my $checker (@$checkers)
	{
	my $checker_channel = $checker->{CHECKER_CHANNEL} ;
	
	print $checker_channel "STOP_PROCESS\n" ;
	}
	
for my $checker (@$checkers)
	{
	waitpid($checker->{PID}, 0) ;
	}
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

#-----------------------------------------------------------------------------------------------------------------------

sub FlushMd5CacheMulti
{
my ($file_triggered_names, $nodes) = @_ ;

my @located_nodes = 
	map
	{
	exists $nodes->{$_}{__LOCATION}
		? $nodes->{$_}{__LOCATION} . substr($_, 1) 
		: $_ ;
	} @$file_triggered_names ;

PBS::Digest::FlushMd5CacheMulti(\@located_nodes) ;
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Check::ForkedCheck  -

=head1 DESCRIPTION

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

=cut
