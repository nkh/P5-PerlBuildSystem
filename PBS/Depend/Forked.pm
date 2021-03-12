
package PBS::Depend::Forked ;

use 5.006 ;
use strict ;
use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

#use Data::Dumper ;
#use Data::TreeDumper ;

#use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Path ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
#use String::Truncate ;
#use List::Util qw(any max) ;
#use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Depend ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Net ;

#-------------------------------------------------------------------------------------------------------

my $forked_depends = 0 ;

sub CreateDependencyTree
{
my ($pbs_config, $node, $type , $turntable_request, $subpbs_dependencies, $args) = @_ ;

my $depender = \&PBS::Depend::CreateDependencyTree ;

if($pbs_config->{DEPEND_JOBS} && $type eq 'subpbs' && $$turntable_request < $subpbs_dependencies)
	{
	my $resource_handle = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_depend_resource', {}, $$) // 0 ;
	
	if($resource_handle)
		{
		$forked_depends++ ;
		
		$node->{__PARALLEL_DEPEND}++ ;
		$$turntable_request++ ;
		
		$depender = 
			sub
			{
			my $pid = fork() ;
			
			if($pid)
				{
				return 0 ;
				}
			else
				{
				# if fork ok depend in other process otherwise depend in this process
				
				Say Color 'test_bg',  "Depend: parallel start, node: $node->{__NAME}, pid: $$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_START} ;
				
				my $log_file = GetRedirectionFile($pbs_config, $node) ;
				my $redirection = RedirectOutputToFile($pbs_config, $log_file) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
				
				PBS::Depend::CreateDependencyTree(@_) ;
				
				if(defined $pid)
					{
					RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
					
					Say Color 'test_bg2',  "Depend: parallel end, node: $node->{__NAME}, pid:$$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_END} ;
					
					PBS::Net::Post($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'register_parallel_depend', { id => $$ }, $$) ;
					
					PBS::Net::Post
						(
						$pbs_config, $pbs_config->{RESOURCE_SERVER},
						'return_depend_resource',
						{ handle => $resource_handle },
						$$
						) ;
	 				
					BecomeDependServer($pbs_config, $pbs_config->{RESOURCE_SERVER}, [@_]) ;
					exit 0 ;
					}
				else
					{
					RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
					return 0 ;
					}
				} ;
				
			}
		}
	else
		{
		Say Warning3 "Depend: no resource to run depend in parallel, node: parallel start, index: $forked_depends, pid: $$"
			if $pbs_config->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE} ;
		}
	}

$depender->(@$args) ;
}

#-------------------------------------------------------------------------------------------------------

sub BecomeDependServer
{
my ($pbs_config, $resource_server_url, $data) = @_ ;

my $d = PBS::Net::StartHttpDeamon($pbs_config) ;

PBS::Net::Post($pbs_config, $resource_server_url, 'parallel_depend_waiting', { id => $$ , address => $d->url }, $$) ;

PBS::Net::BecomeServer($pbs_config, 'depender', $d, $data) ;
}

#-------------------------------------------------------------------------------------------------------

sub GetRedirectionFile
{
my ($pbs_config, $node) = @_ ;

my $redirection_file = $pbs_config->{BUILD_DIRECTORY} . "/parallel_depend/$node->{__NAME}" ; 
$redirection_file =~ s/\/\.\//\//g ;

my ($basename, $path, $ext) = File::Basename::fileparse($redirection_file, ('\..*')) ;

mkpath($path) unless(-e $path) ;

$redirection_file = $path . '.' . $basename . $ext . ".pbs_depend_log" ;
}

sub RedirectOutputToFile
{
my ($pbs_config, $redirection_file) = @_ ;

open my $OLDOUT, ">&STDOUT" ;

local *STDOUT unless $pbs_config->{DEPEND_LOG_MERGED} ;

open STDOUT,  ">", $redirection_file or die "Can't redirect STDOUT to '$redirection_file': $!";
STDOUT->autoflush(1) ;

open my $OLDERR, ">&STDERR" ;
open STDERR, '>>&STDOUT' ;

return [$OLDOUT, $OLDERR] ;
}

sub RestoreOutput
{
my ($OLDOUT, $OLDERR) = @{$_[0]} ;

open STDERR, '>&' . fileno($OLDERR) or die "Can't restore STDERR: $!";
open STDOUT, '>&' . fileno($OLDOUT) or die "Can't restore STDOUT: $!";
}

#-------------------------------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Depend::Forked  -

=head1 SYNOPSIS

=head1 DESCRIPTION

Support functionality to depend in parallel

=cut


