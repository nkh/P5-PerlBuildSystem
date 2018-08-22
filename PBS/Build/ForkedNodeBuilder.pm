
package PBS::Build::ForkedNodeBuilder ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use Digest::MD5 qw(md5_hex) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.01' ;

use PBS::Output ;
use PBS::Constants ;
use PBS::Build::NodeBuilder ;

#-------------------------------------------------------------------------------

sub NodeBuilder
{
my $parent_channel = shift ; # communication channel to/from parent
my $pbs_config     = $_[0] ;

my ($build_log, $build_output) ; # file names for the last build
my $build_time ; #last node build time

while(defined (my $command_and_args = <$parent_channel>))
	{
	# wait for the name of the node to build or a command
	chomp $command_and_args ;
	
	my @command_and_args = split /__PBS_FORKED_BUILDER__/, $command_and_args ;
	
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
			print $parent_channel "$$\n__PBS_FORKED_BUILDER__\n" ;
			last ;
			} ;
			
		/^GET_BUILD_TIME/ and do
			{
			print $parent_channel "$build_time\n__PBS_FORKED_BUILDER__\n" ;
			last ;
			} ;
			
		/^BUILD_NODE$/ and do
			{
			my ($node_name, $node_build_sequencer_info) ;
			
			(undef, $node_name, $node_build_sequencer_info) = @command_and_args ;
			($build_log, $build_output, $build_time) = BuildNode($parent_channel, $node_name, $node_build_sequencer_info, @_) ;
			
			last ;
			} ;
			
		/^GET_LOG$/ and do
			{
			SendFile($parent_channel, $build_log, !$pbs_config->{KEEP_PBS_BUILD_BUFFERS}) ;
			last ;
			} ;
			
		/^GET_OUTPUT$/ and do
			{
			SendFile($parent_channel, $build_output, !$pbs_config->{KEEP_PBS_BUILD_BUFFERS}) ;
			last ;
			} ;
		}
	}
exit ;
}

#-------------------------------------------------------------------------------

sub BuildNode
{
my 
	(
	$parent_channel,
	$node_name,
	$node_build_sequencer_info,
	$pbs_config,
	$build_sequence,
	$inserted_nodes,
	$shell,
	$shell_origin,
	) = @_ ;

my $t0 = [gettimeofday] ;

my $node ;
for(@$build_sequence)
	{
	if($_->{__NAME} eq $node_name)
		{
		$node = $_ ;
		last ;
		}
	}
	
my $redirection_file =  md5_hex($shell->GetInfo() . '_node_' . $node_name) ;

my $pbs_build_buffers_directory = $node->{__PBS_CONFIG}{BUILD_DIRECTORY} . "/PBS_BUILD_BUFFERS/";

unless(-e $pbs_build_buffers_directory)
	{
	use File::Path ;
	mkpath($pbs_build_buffers_directory) ;
	}
	
$redirection_file = $pbs_build_buffers_directory . $redirection_file ;

#all output goes to files that might be kept if KEEP_PBS_BUILD_BUFFERS is set
#once the build is finished, the output is send to the master process

local *STDOUT ;
local *STDERR ;

open STDOUT, '>', $redirection_file or die "Can't redirect STDOUT to '$redirection_file': $!";
STDOUT->autoflush(1) ;

open STDERR, '>&' . fileno(STDOUT) or die "Can't redirect STDERR to '$redirection_file': $!";
STDERR->autoflush(1) ;

my $redirection_file_log = "${redirection_file}_log" ;
if(defined $pbs_config->{CREATE_LOG})
	{
	die "LOG not implemented in -j mode yet";
	open LOG, '>', $redirection_file_log or die "Can't redirect log to '$redirection_file_log': $!";
	LOG->autoflush(1) ;
	
	$pbs_config->{CREATE_LOG} = *LOG ;
	}
	
if(defined $pbs_config->{DISPLAY_JOBS_INFO})
	{
	PrintInfo2 "Building with parallel builder, node: '$node_name' ($node_build_sequencer_info).\n" ;
	}

if(defined $node)
	{
	if(defined $shell && ! defined $node->{__SHELL_OVERRIDE})
		{
		#~ # override which shell is going to build this node
		$node->{__SHELL_OVERRIDE} = $shell ;
		$node->{__SHELL_ORIGIN}   = $shell_origin ;
		}
		
	my ($build_result, $build_message) = (BUILD_FAILED, '?') ;
	
	eval 
		{
		($build_result, $build_message) = PBS::Build::NodeBuilder::BuildNode($node, $node->{__PBS_CONFIG}, $inserted_nodes, $node_build_sequencer_info) ;
		} ;
		
	if($@)
		{
		($build_result, $build_message) = (BUILD_FAILED,  "Caught unexpected exception from Build::NodeBuilder::BuildNode") ;
		
		#add exception message to the command output
		print ERROR "Caught unexpected exception from Build::NodeBuilder::BuildNode:\n$@" ;
		}
	
	# status
	print $parent_channel "${build_result}__PBS_FORKED_BUILDER__${build_message}\n" ;
	
	return($redirection_file_log, $redirection_file, tv_interval ($t0, [gettimeofday])) ;
	}
else
	{
	die ERROR "ForkedBuilder: Couldn't find node '$node_name' in build_sequence.\n" ;
	}
}

#~ #--------------------------------------------------------------------------------------------

sub SendFile
{
my ($channel,$file, $remove_file) =  @_ ;

open FILE_TO_SEND, '<', $file or die "Can't open '$file': $!" ;
while(<FILE_TO_SEND>)
	{
	print $channel $_ ;
	}
	
close(FILE_TO_SEND) ;	

print $channel "__PBS_FORKED_BUILDER___\n" ;

unlink($file) if $remove_file;
}

#-------------------------------------------------------------------------------------------------------

1 ;

__END__

=head1 NAME

PBS::Build::ForkedNodeBuilder -

=head1 DESCRIPTION

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut


