
package PBS::Log::ForkedLNI ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

use IO::Select ;
use Socket;

use PBS::Build::ForkedNodeBuilder ; # for log file name
use PBS::Output ;

#-----------------------------------------------------------------------------------------------------------------------

my $SEPARATOR = "__PBS_LNI_PROCESS__" ;

sub ParallelLNI
{
my ($pbs_config, $inserted_nodes, $nodes) = @_ ;

my $number_of_processes = 8 ;
my $processes = StartProcesses($number_of_processes, $pbs_config, $inserted_nodes, $nodes)  ;

my $index = 0 ;
for my $slice (distribute(scalar(@$nodes), $number_of_processes))
	{
	GenerateLNI(@$processes[$index++], $slice->[0], $slice->[1])  ;
	}

my @finished_processes ;
while(@finished_processes < $index)
	{
	my @finished = WaitForProcessesToFinish($pbs_config, $processes) ;

	push @finished_processes, @finished
	}

TerminateProcesses($pbs_config, $processes) ;
}

#-----------------------------------------------------------------------------------------------------------------------

sub GenerateLNI
{
my ($pid, $slice_start, $slice_end) = @_ ;

$pid->{RUNNING} = 1 ;
my $channel = $pid->{CHANNEL} ;

print $channel "GENERATE_LNI" . $SEPARATOR 
			. $slice_start . $SEPARATOR
			. $slice_end .$SEPARATOR . "\n" ;
}

#---------------------------------------------------------------------------------------------------------------

sub WaitForProcessesToFinish
{
my ($pbs_config, $processes) = @_ ;

my $select_all = new IO::Select ;
my @waiting_for_messages ;

my $number_of_processes = @$processes ;

for (0 .. ($number_of_processes - 1))
	{
	if($processes->[$_]{RUNNING} == 1)
		{
		push @waiting_for_messages, "process $_" ;
		$select_all->add($processes->[$_]{CHANNEL}) ;
		}
	}

my @processes_ready ;

if(@waiting_for_messages)
	{
	# block till we get end of run from a process 
	my @sockets_ready = $select_all->can_read() ; 
	
	for (0 .. ($number_of_processes - 1))
		{
		for my $socket_ready (@sockets_ready)
			{
			if($socket_ready == $processes->[$_]{CHANNEL})
				{
				push @processes_ready, $_ ;
				}
			}
		}
	}

return(@processes_ready) ;
}

#---------------------------------------------------------------------------------------------------------------

sub StartProcesses
{
my ($number_of_processes, $pbs_config, $inserted_nodes, $nodes) = @_ ;

my @processes ;
for my $index (0 .. ($number_of_processes - 1))
	{
	my ($channel) = StartProcess($pbs_config, $inserted_nodes,  $nodes) ;
				
	unless(defined $channel)
		{
		PrintError "Log: Couldn't start parallel process #$_!\n" ;
		die "\n";
		}
	
	print $channel "GET_PROCESS_ID" . $SEPARATOR . "\n";
	
	my $child_pid = -1 ;
	while(<$channel>)
		{
		last if /$SEPARATOR/ ;
		chomp ;
		$child_pid = $_ ;
		}
	
	$processes[$index] = 
		{
		PID      => $child_pid,
		CHANNEL  => $channel,
		RUNNING  => 0,
		} ;
	}

return(\@processes) ;
}

#---------------------------------------------------------------------------------------------------------------

sub StartProcess
{
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
	
	RunFront($to_parent, @_) ; # waits for commands from parent
	}
}

#-------------------------------------------------------------------------------

sub RunFront 
{
my $parent_channel = shift ; # communication channel to/from parent
my ($pbs_config, $inserted_nodes, $nodes) = @_ ;

while(defined (my $command_and_args = <$parent_channel>))
	{
	# wait for a command
	chomp $command_and_args ;
	
	my @command_and_args = split /$SEPARATOR/, $command_and_args ;
	
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
			print $parent_channel "$$\n$SEPARATOR\n" ;
			last ;
			} ;
			
		/^GENERATE_LNI$/ and do
			{
			(undef, my $slice_start, my $slice_end) = @command_and_args ;
			_GenerateLNI($pbs_config, $inserted_nodes, $nodes, $slice_start, $slice_end) ;
			
			print $parent_channel "$SEPARATOR\n" ;
			
			last ;
			} ;
			
		}
	}

exit ;
}

#---------------------------------------------------------------------------------------------------------------

sub _GenerateLNI
{
my ($pbs_config, $inserted_nodes, $nodes, $slice_start, $slice_end) = @_ ;

for my $node (@{$nodes}[$slice_start .. $slice_end])
	{
	my (undef, $node_info_file) = PBS::Build::ForkedNodeBuilder::GetLogFileNames($node) ;

	my (undef, $log_node_info) = PBS::Information::GetNodeInformation($node, $pbs_config, 1, $inserted_nodes) ;
		
	open(my $fh, '>', $node_info_file) or die ERROR "Error: --lni can't create '$node_info_file'.\n" ;
	print $fh $log_node_info ;
	}
}

#---------------------------------------------------------------------------------------------------------------

sub TerminateProcesses
{
my ($pbs_config, $processes) = @_ ;
my $number_of_processes = @$processes ;

PrintInfo "ForkedLNI: terminating processes [$number_of_processes]\n" if $pbs_config->{DISPLAY_JOBS_INFO} ;

for my $process (@$processes)
	{
	my $channel = $process->{CHANNEL} ;
	print $channel "STOP_PROCESS\n" ;
	}
	
for my $process (@$processes)
	{
	waitpid($process->{PID}, 0) ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

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

1 ;

__END__
=head1 NAME

PBS::Log::ForkedLNI  -

=head1 DESCRIPTION

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

=cut
