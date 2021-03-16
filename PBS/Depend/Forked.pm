
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
use Time::HiRes qw(usleep gettimeofday tv_interval) ;

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
	my $idle_depender = $pbs_config->{USE_DEPEND_SERVER}
				? PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_idle_depender', {}, $$)
				: {} ;

	if(defined $idle_depender->{ADDRESS})
		{
		$node->{__PARALLEL_DEPEND} = $idle_depender->{PID} ;

		$depender =
			sub
			{
			# depend in existing idle depender
			
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

my %forked_children ;
my $parent_pid ;

sub StartNewDepender
{
my ($pbs_config, $node, $args) = @_ ;

my $depender ;
 
my $data = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_depend_resource', {}, $$) // {} ;

my $resource_id = $data->{ID} ;

# save our pid for children 
my $parent_pid_copy = $$ ;

if($resource_id)
	{
	$depender = 
		sub
		{
		my $pid = fork() ;
		
		$node->{__PARALLEL_DEPEND} = $pid ;
		
		if($pid)
			{
			$forked_children{$pid}++ ; 
			#SUT \%forked_children, $$ ;

			# return $build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package)
			return   undef,         undef,          undef,      undef,          "parallel_load_package" ;
			}
		else
			{
			# if fork ok depend in other process otherwise depend in this process
			
			%forked_children = () ; # forget parents children
			$parent_pid = $parent_pid_copy ;
			
			my $node_text = $pbs_config->{DISPLAY_PARALLEL_DEPEND_NODE} ? ", node: $node->{__NAME}" : '' ; 
			Say Color 'test_bg',  "Depend: parallel start$node_text, pid: $$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_START} ;
			
			my $log_file = GetRedirectionFile($pbs_config, $node) ;
			my $redirection = RedirectOutputToFile($pbs_config, $log_file) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
			
			PBS::Net::Post($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'register_parallel_depend', { pid => $$ }, $$) ;
				
			my %nodes_snapshot = %{$_[7]} ;
			my $target = $_[6][0] ;

			my ($build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package) =
				PBS::PBS::Pbs(@_) ;
			
			my @new_nodes = grep { ! exists $nodes_snapshot{$_} } keys %$inserted_nodes ;
			my $new_nodes = @new_nodes ;

			if(defined $pid)
				{
				RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
			
				my $node_text = $pbs_config->{DISPLAY_PARALLEL_DEPEND_NODE} ? ", node: $node->{__NAME}" : '' ; 
				my $info = ", children: " . scalar(keys %forked_children) . ", new nodes: $new_nodes" ;
				
				Say Color 'test_bg2', "Depend: parallel end$node_text$info, pid: $$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_END} ;
				
				PBS::Net::Post
					(
					$pbs_config, $pbs_config->{RESOURCE_SERVER},
					'return_depend_resource',
					{ id => $resource_id },
					$$
					) ;
				
				my %not_depended ;
				my %graph  = 
					(
					PID      => $$,
					TARGET   => $target,
					PARENT   => $parent_pid,
					CHILDREN => \%forked_children,
					
					NODES    => 
							{
							map 
								{
								my $node = $_ ;
								
								$not_depended{$node}++ if ! exists $inserted_nodes->{$node}{__DEPENDED}
											 && ! exists $inserted_nodes->{$node}{__IS_SOURCE} ;
								
								$node =>
									{
									map 
										{
										my $ref = ref $inserted_nodes->{$node}{$_} ;
										
										'' eq $ref
											? ($_ => $inserted_nodes->{$node}{$_})
											: ($_ => $ref)
										} 
										keys %{$inserted_nodes->{$node}}
									}
								} @new_nodes
							},
					) ;
				
				$graph{NOT_DEPENDED}{$_} = $graph{NODES}{$_} for keys %not_depended ;
				
				local $Data::Dumper::Indent = 0 ;
				my $serialized_graph = Data::Dumper->Dump([\%graph], [qw(graph)]) ;
				
				BecomeDependServer($pbs_config, $pbs_config->{RESOURCE_SERVER}, [\@_, $serialized_graph]) ;
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

use Time::HiRes qw(usleep gettimeofday tv_interval) ;

sub Link
{
my ($pbs_config, $inserted_nodes) = @_ ;

if($pbs_config->{DEPEND_JOBS})
	{
	my $data = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_depend_resource_status', {}, $$)  ;
	
	my $wait_counter = 0 ;
	while (! $data->{ALL_DEPENDERS_DONE})
		{
		my $wait_time = 0.01 * $wait_counter ;
		
		Say Warning3 "Depend: waiting for parallel depender to be done, elapsed time: $wait_time s."
			if $pbs_config->{DISPLAY_DEPEND_REMAINING_PROCESSES} && $wait_counter++ > 50 && ! ($wait_counter % 5) ;
		
		usleep 10_000 ;

		$data = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_depend_resource_status', {}, $$) ;
		}

	# handle all the forked dependers
	$data = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_parallel_dependers', {}, $$) ;
	my $serialized_dependers = $data->{SERIALIZED_DEPENDERS} ;

	my $dependers ;
	eval $serialized_dependers ;
	Say Error $@ if $@ ;

	LinkChildren($pbs_config, $serialized_dependers, $dependers, $inserted_nodes) ;

	my $t0_shutdown = [gettimeofday];

	if($pbs_config->{RESOURCE_QUICK_SHUTDOWN})
		{
		kill 'KILL',  $_->{PID}  for values %$dependers ;
		}
	else
		{
		PBS::Net::Post($pbs_config, $_->{ADDRESS}, 'stop', {}, $$)  for values %$dependers ;
		}

	PBS::Net::Post($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'stop') ;

	my $number_of_dependers = scalar keys %$dependers ;
	PrintInfo sprintf("\nDepend: dependers: $number_of_dependers, shutdown time: %0.2f s.\n", tv_interval ($t0_shutdown, [gettimeofday])) ;
	} 
}
	
sub LinkChildren
{
my ($pbs_config, $serialized_dependers, $dependers, $inserted_nodes) = @_ ;

my $t0_link = [gettimeofday];

eval $serialized_dependers unless defined $dependers;
Say Error $@ and die "\n"if $@ ;

my %main_graph =
	(
	PID          => $$,
	TARGET       => 'ROOT',
	PARENT       => $parent_pid,
	CHILDREN     => \%forked_children,
	
	NODES        => $inserted_nodes,

	NOT_DEPENDED => {
			map { $_->{__NAME} => $_ }
				grep { ! exists $_->{__DEPENDED} && ! exists $_->{__IS_SOURCE} }
					values %$inserted_nodes
			},
	) ;

my %graphs = map 
		{
		my $data = PBS::Net::Get($pbs_config, $dependers->{$_}{ADDRESS}, 'get_graph', {}, $$) ;
		my $graph ; eval $data->{GRAPH} ; die $@ if $@ ;

		$_ => $graph ; 
		} keys %$dependers ;

$graphs{$$} = \%main_graph ;

my %nodes ;
my %not_linked ;

for my $graph ( values %graphs)
	{
	for (keys %{$graph->{NODES}})
		{
		Say Debug "Link: duplicate: $_" if exists $nodes{$_} ;
		$nodes{$_} = $graph->{NODES}{$_} ;
		}
	}

my $linked = 0 ;
for my $graph ( values %graphs, \%main_graph)
	{
	for (keys %{$graph->{NOT_DEPENDED}})
		{
		if(exists $nodes{$_})
			{
			$graph->{LINKED}{$_} = $nodes{$_} ;
			$linked++ ;
			#Say Debug "Link: linking: $_, graph: $graph->{PID}" ;
			}
		else
			{
			$not_linked{$_} = $graph->{NOT_DEPENDED}{$_} ;
			Say Debug "Link: can't find node: $_, graph: $graph->{PID}" ;
			}
		}
	}

my $time                = sprintf '%0.2f', tv_interval ($t0_link, [gettimeofday]) ;
my $nodes               = keys %nodes ;
my $not_linked          = keys %not_linked ;
my $number_of_dependers = keys %$dependers ;

Say Info "Depend: gather, ∥ dependers: $number_of_dependers, nodes: $nodes, linked: $linked, not linked: $not_linked, time: $time" ;
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


