
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

use File::Path ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
use Data::Dumper ;
use PBS::Depend ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Net ;

#-------------------------------------------------------------------------------------------------------

sub Subpbs
{
my ($pbs_config, $node, $args) = @_ ;

my $depender ;

if($pbs_config->{DEPEND_JOBS} && exists $node->{__PARALLEL_SCHEDULE})
	{
	my $idle_depender = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_idle_depender', {}, $$) // 0 ;
	
	if(defined $idle_depender->{ADDRESS})
		{
		$node->{__PARALLEL_DEPEND} = $idle_depender->{PID} ;

		$depender =
			sub
			{
			# depend in idle depender

			my 	
				(
				$pbsfile_chain, $pbsfile_rule_name, $Pbsfile, $parent_package, $pbs_config,
				$parent_config, $targets, $inserted_nodes, $dependency_tree_name, $depend_and_build,
				) = @_ ;
			
			PBS::Net::Post
				(
				$pbs_config, $idle_depender->{ADDRESS},
				'depend_node',
					{
					id => $idle_depender->{ID}, node => $_[6][0], resource_server => $pbs_config->{RESOURCE_SERVER},
					
					pbsfile_chain        => Data::Dumper->Dump([$pbsfile_chain], [qw(pbsfile_chain)]),
					pbsfile_rule_name    => $pbsfile_rule_name,
					Pbsfile              => $Pbsfile,
					parent_package       => $parent_package,
					pbs_config           => Data::Dumper->Dump([$pbs_config], [qw($pbs_config)]),
					parent_config        => Data::Dumper->Dump([$parent_config], [qw($parent_config)]),
					targets              => $targets->[0],
					#inserted_nodes       => $inserted_nodes,
					dependency_tree_name => $dependency_tree_name,
					depend_and_build     => $depend_and_build,
					},
				$$
				) ;
			
			# return $build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package)
			return   undef,         undef,          undef,      undef,          "parallel_load_package" ;
			} ;
		}
	else
		{
		$depender = StartNewDepender($pbs_config, $node, $args) ;
		}

	}

$depender //= \&PBS::PBS::Pbs ;

$depender->(@$args) ;
}

sub Pbs
{
my ($data , $p) = @_ ;

my $pbsfile_chain ;
eval $p->{pbsfile_chain} ;
die $@ if $@ ;
 
my $pbs_config ;
eval $p->{pbs_config} ;
die $@ if $@ ;

my $parent_config ;
eval $p->{parent_config} ;
die $@ if $@ ;

#SDT $data, '', MAX_DEPTH => 1 ; 

PBS::PBS::Pbs
	(
	$pbsfile_chain,
	$p->{pbsfile_rule_name},
	$p->{Pbsfile},
	$p->{parent_package},
	$pbs_config,
	$parent_config,
	[$p->{targets}],

	$data->[7], # $inserted_nodes,

	$p->{dependency_tree_name},
	$p->{depend_and_build},
	) ;
}

sub StartNewDepender
{
my ($pbs_config, $node, $args) = @_ ;

my $depender ;
 
my $data = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_depend_resource', {}, $$) // 0 ;

my $resource_id = $data->{ID} ;

if($resource_id)
	{
	$depender = 
		sub
		{
		my $pid = fork() ;
		
		$node->{__PARALLEL_DEPEND} = $pid ;
		
		if($pid)
			{
			# return $build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package)
			return   undef,         undef,          undef,      undef,          "parallel_load_package" ;
			}
		else
			{
			# if fork ok depend in other process otherwise depend in this process
			
			Say Color 'test_bg',  "Depend: parallel start, node: $node->{__NAME}, pid: $$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_START} ;
			
			my $log_file = GetRedirectionFile($pbs_config, $node) ;
			my $redirection = RedirectOutputToFile($pbs_config, $log_file) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
			
			PBS::Net::Post($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'register_parallel_depend', { pid => $$ }, $$) ;
				
			my ($build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package) =
				PBS::PBS::Pbs(@_) ;
			
			if(defined $pid)
				{
				RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
				
				Say Color 'test_bg2',  "Depend: parallel end, node: $node->{__NAME}, pid:$$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_END} ;
				
				PBS::Net::Post
					(
					$pbs_config, $pbs_config->{RESOURCE_SERVER},
					'return_depend_resource',
					{ id => $resource_id },
					$$
					) ;
				
				BecomeDependServer($pbs_config, $pbs_config->{RESOURCE_SERVER}, \@_) ;
				exit 0 ;
				}
			else
				{
				RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
				return $build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package ;
				}
			} ;
			
		}
	}
else
	{
	Say Warning3 "Depend: no resource to run depend in parallel, node: $node->{__NAME}, pid: $$"
		if $pbs_config->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE} ;
	}

$depender ; 
}

#-------------------------------------------------------------------------------------------------------

sub BecomeDependServer
{
my ($pbs_config, $resource_server_url, $data) = @_ ;

my $d = PBS::Net::StartHttpDeamon($pbs_config) ;

PBS::Net::Post($pbs_config, $resource_server_url, 'parallel_depend_idling', { pid => $$ , address => $d->url }, $$) ;

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


