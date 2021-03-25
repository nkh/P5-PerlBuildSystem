
package PBS::Build::ForkedNodeBuilder ;

use 5.006 ;

use strict ;
use warnings ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Path ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;

our $VERSION = '0.01' ;

use PBS::Output ;
use PBS::Log ;
use PBS::Log::Html ;
use PBS::Constants ;
use PBS::Build::NodeBuilder ;

#-------------------------------------------------------------------------------

sub NodeBuilder
{
my $parent_channel = shift ; # communication channel to/from parent
my ($pbs_config) = @_ ;

$pbs_config->{PARENT_CHANNEL} = $parent_channel ; # make it available for RPC requests

my ($build_log, $build_output) ; # file names for the last build
my ($build_result, $build_message, $build_time) ; #last node build info

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

			($build_result, $build_message, $build_log, $build_output, $build_time)
				= BuildNode($parent_channel, $node_name, $node_build_sequencer_info, @_) ;

			my $BUILD_DONE = 'BUILD_DONE' ;

			print $parent_channel "${BUILD_DONE}__PBS_FORKED_BUILDER__${build_result}__PBS_FORKED_BUILDER__${build_message}\n" ;
			
			last ;
			} ;
			
		/^GET_LOG$/ and do
			{
			if(defined $pbs_config->{CREATE_LOG})
				{
				SendFile($parent_channel, $build_log) ;
				}
			else
				{
				print $parent_channel 'No log option was given.' . "__PBS_FORKED_BUILDER___\n" ;
				}

			last ;
			} ;
			
		/^GET_OUTPUT$/ and do
			{
			SendFile($parent_channel, $build_output) ;
			last ;
			} ;
		}
	}
exit ;
}

#-------------------------------------------------------------------------------

sub GetLogFileNames
{
my ($node) = @_ ;

my $redirection_base = $node->{__BUILD_NAME} // PBS::Rules::Builders::GetBuildName($node->{__NAME}, $node);
my ($base_basename, $base_path, $base_ext) = File::Basename::fileparse($redirection_base, ('\..*')) ;

$redirection_base = $base_path ;

my $redirection_file = "$redirection_base/.$base_basename$base_ext.pbs_log" ;
my($basename, $path, $ext) = File::Basename::fileparse($redirection_file, ('\..*')) ;
mkpath($path) unless(-e $path) ;

# todo: remove
my $redirection_file_log = "$redirection_base/.$base_basename$base_ext.pbs_old_log_should_not_be_created" ;
($basename, $path, $ext) = File::Basename::fileparse($redirection_file_log, ('\..*')) ;
mkpath($path) unless(-e $path) ;

return $redirection_base, $redirection_file, $redirection_file_log ;
}

#-------------------------------------------------------------------------------------------------------

sub BuildNode
{
my 
	(
	$parent_channel,
	$node_name,
	$node_build_sequencer_info,
	$pbs_config,
	$inserted_nodes,
	$shell,
	$shell_origin,
	) = @_ ;

my $t0 = [gettimeofday] ;

my $node = %$inserted_nodes{$node_name} ;

my ($redirection_path, $redirection_file, $redirection_file_log) = GetLogFileNames($node) ;
#all output goes to a log file, once the build is finished, the output is send to the master process

my $file_fail = $redirection_file . '_fail' ;
unlink $file_fail ;

no warnings 'once';
open(OLDOUT, ">&STDOUT") ;
open STDOUT, '>', $redirection_file or die "Can't redirect STDOUT to '$redirection_file': $!";
STDOUT->autoflush(1) ;

open(OLDERR, ">&STDERR") ;
open STDERR, '>>&=' . fileno(STDOUT) or die "Can't redirect STDERR to '$redirection_file': $!" ;

PrintInfo2 "Build: building node: '$node_name', level: $node->{__LEVEL}, stats: $node_build_sequencer_info.\n"
	if defined $pbs_config->{DISPLAY_JOBS_INFO} ;

if(defined $node)
	{
	if(defined $shell && ! defined $node->{__SHELL_OVERRIDE})
		{
		#~ # override which shell is going to build this node
		$node->{__SHELL_OVERRIDE} = $shell ;
		$node->{__SHELL_ORIGIN}   = $shell_origin ;
		}
		
	my ($build_result, $build_message) = (BUILD_FAILED, '?') ;

	# when building in parallel, we can put as much possible in the log even if
	# the progress bar is displayed, when it isn't, it's up to the user what gets in
	local $node->{__PBS_CONFIG} = $node->{__PBS_CONFIG} ;
	local $PBS::Shell::silent_commands = $PBS::Shell::silent_commands ;
	local $PBS::Shell::silent_commands_output = $PBS::Shell::silent_commands_output ; 

	if($node->{__PBS_CONFIG}{DISPLAY_PROGRESS_BAR} || $node->{__PBS_CONFIG}{CREATE_LOG})
		{
		$node->{__PBS_CONFIG}{BUILD_AND_DISPLAY_NODE_INFO}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_CONFIG}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_ORIGIN}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_DEPENDENCIES}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_CAUSE}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_RULES}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_BUILD_SEQUENCER_INFO}++ ;
		
		$node->{__PBS_CONFIG}{DISPLAY_TEXT_TREE_USE_ASCII}++ ;
		$node->{__PBS_CONFIG}{TIME_BUILDERS}++ ;
		
		$PBS::Shell::silent_commands = 0 ;
		$PBS::Shell::silent_commands_output = 0 ; 
		}
	
	eval 
		{
		($build_result, $build_message) =
			PBS::PBS::Forked::BuildNode
				(
				$node,
				$node->{__PBS_CONFIG},
				$inserted_nodes,
				$node_build_sequencer_info
				) ;
		} ;
	
	my $exception = $@ ;

	if	(
		($exception || $build_result == BUILD_FAILED)
		&& ! $node->{__PBS_CONFIG}{DISPLAY_PROGRESS_BAR}
		&& ! $node->{__PBS_CONFIG}{BUILD_AND_DISPLAY_NODE_INFO}
		)
		{
		$node->{__PBS_CONFIG}{BUILD_AND_DISPLAY_NODE_INFO}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_CONFIG}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_ORIGIN}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_DEPENDENCIES}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_CAUSE}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_RULES}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_BUILD_SEQUENCER_INFO}++ ;
		$node->{__PBS_CONFIG}{DISPLAY_TEXT_TREE_USE_ASCII}++ ;
		$node->{__PBS_CONFIG}{TIME_BUILDERS}++ ;
		
		Say Info2 "Build: detected -bpb0 but no --build_verbose, generating extra node information:"  ;

		PBS::Information::DisplayNodeInformation($node, $node->{__PBS_CONFIG}, 1, $inserted_nodes) ;
		}

	if($exception)
		{
		($build_result, $build_message) = (BUILD_FAILED,  "Caught unexpected exception from Build::NodeBuilder::BuildNode") ;
		
		print OLDERR ERROR "Caught unexpected exception from Build::NodeBuilder::BuildNode:\n$exception" ;
		print STDERR ERROR "Caught unexpected exception from Build::NodeBuilder::BuildNode:\n$exception" ;
		}
	
	if($build_result == BUILD_FAILED)
		{
		rename  $redirection_file, $file_fail or die "Can't move log file '$redirection_file' to '$file_fail': $!" ;

		$redirection_file = $file_fail ;
		}

	PBS::Log::Html::LogNodeData($node, $redirection_path, $redirection_file, $redirection_file_log)
		if defined $pbs_config->{CREATE_LOG_HTML} ;

	open(STDERR, ">&OLDERR");
	open(STDOUT, ">&OLDOUT");

	return $build_result, $build_message, $redirection_file_log, $redirection_file, tv_interval ($t0, [gettimeofday]) ;
	}
else
	{
	#close(STDERR);
	open(STDERR, ">&OLDERR");
	open(STDOUT, ">&OLDOUT");

	die ERROR("ForkedBuilder: Couldn't find node '$node_name' in build_sequence") . "\n" ;
	}
}

#--------------------------------------------------------------------------------------------

sub SendFile
{
my ($channel, $file) =  @_ ;

open FILE_TO_SEND, '<', $file or die "Can't open '$file': $!" ;
while(<FILE_TO_SEND>)
	{
	print $channel $_ ;
	}
	
close(FILE_TO_SEND) ;

print $channel "__PBS_FORKED_BUILDER___\n" ;
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


