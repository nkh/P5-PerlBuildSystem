
package PBS::PBS::Forked ;

use v5.10 ;
use strict ;
use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.02' ;

use File::Path ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
use Storable qw(freeze thaw) ;
use Compress::Zlib ;
use Time::HiRes qw(usleep gettimeofday tv_interval) ;

use PBS::Constants ;
use PBS::Depend ;
use PBS::Net ;
use PBS::Output ;
use PBS::Plugin ;

use constant 
	{
	PBSFILE_CHAIN  => 0,
	INSERTED_AT    => 1,
	SUBPBS_NAME    => 2,
	LOAD_PACKAGE   => 3,
	PBS_CONFIG     => 4,
	CONFIG         => 5,
	TARGETS        => 6,
	INSERTED_NODES => 7,
	TREE_NAME      => 8,
	BUILD_TYPE     => 9,
	
	RAW            => 1,
	} ;

#-------------------------------------------------------------------------------------------------------

sub Subpbs
{
my ($pbs_config, $node, $args) = @_ ;

my $depender ;

if($pbs_config->{PBS_JOBS} && exists $node->{__PARALLEL_SCHEDULE})
	{
	my $idle_depender = $pbs_config->{USE_DEPEND_SERVER}
				? PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_idle_depender', {}, $$)
				: {} ;
	
	if(defined $idle_depender->{ADDRESS})
		{
		die Error("PBS: depend in existing idle depender is not enabled") . "\n" ;

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
					id => $idle_depender->{ID}, node => $targets->[0], resource_server => $pbs_config->{RESOURCE_SERVER},
					
					pbsfile_chain        => Data::Dumper->Dump([$pbsfile_chain], [qw(pbsfile_chain)]),
					pbsfile_rule_name    => $pbsfile_rule_name,
					Pbsfile              => $Pbsfile,
					parent_package       => $parent_package,
					pbs_config           => Data::Dumper->Dump([$pbs_config], [qw($pbs_config)]),
					parent_config        => Data::Dumper->Dump([$parent_config], [qw($parent_config)]),
					targets              => $targets->[0],
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
		$depender = GetParallelDepender($pbs_config, $node, \&PBS::PBS::Pbs, $args, $args) ;
		}
	
	}

$depender //= \&PBS::PBS::Pbs ;

$depender->(@$args) ;
}

sub Pbs
{
my ($data, $p) = @_ ;

my $pbsfile_chain = thaw $p->{pbsfile_chain} ;
my $pbs_config    = thaw $p->{pbs_config} ;
my $parent_config = thaw $p->{parent_config} ;

PBS::PBS::Pbs
	(
	$pbsfile_chain,
	$p->{pbsfile_rule_name},
	$p->{Pbsfile},
	$p->{parent_package},
	$pbs_config,
	$parent_config,
	[$p->{targets}],
	
	$data->{ARGS}[INSERTED_NODES],
	
	$p->{dependency_tree_name},
	$p->{depend_and_build},
	) ;
}

my %nodes_snapshot ;
my %forked_children ;
my $parent_pid ;
my $parent_pid_copy ;

sub GetParallelDepender
{
my ($pbs_config, $node, $pbs_entry_point, $entry_point_args, $args) = @_ ;

# save our pid for children 
$parent_pid_copy = $$ ;

my $depender ; 
my $response = PBS::Net::Get($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'get_depend_resource', {}, $$) // {} ;

my $resource_id = $response->{ID} ;

if($resource_id)
	{
	$depender = sub
		{
		my $pid = fork() ;
		
		if($pid)
			{
			$node->{__PARALLEL_DEPEND} = $pid ;
			
			$forked_children{$pid}++ ; 
			
			# return $build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package)
			return   undef,         undef,          undef,      undef,          "parallel_load_package" ;
			}
		else
			{
			RunParallelPbs($$, $resource_id, $pbs_config, $node, $pbs_entry_point, $entry_point_args, $args) ;
			}
		}
	}
else
	{
	Say Warning3 "Depend: no resource to run depend in parallel, node: $node->{__NAME}, pid: $$"
		if $pbs_config->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE} ;
	}

$depender ; 
}

sub RunParallelPbs
{
my ($pid, $resource_id, $pbs_config, $node, $pbs_entry_point, $entry_point_args, $args) = @_ ;

my $t0 = [gettimeofday];

$node->{__PARALLEL_DEPEND} = $$ ;
$node->{__PARALLEL_HEAD} = $$ ;

PBS::PBS::ResetPbsRuns() ;

%forked_children = () ; # forget parents children
$parent_pid = $parent_pid_copy ;
my $target = $args->[TARGETS][0] ;

my $node_text = $pbs_config->{DISPLAY_PARALLEL_DEPEND_NODE} ? ", node: $node->{__NAME}" : '' ; 
Say Color 'test_bg',  "Depend: parallel start$node_text, pid: $$", 1, 1 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_START} ;

my $log_file    = GetRedirectionFile($pbs_config, $node) ;
my $redirection = RedirectOutputToFile($pbs_config, $log_file) if $pbs_config->{LOG_PARALLEL_DEPEND} ;

PBS::Net::Post($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'register_parallel_depend', { pid => $pid }, $$) ;
	
%nodes_snapshot = %{$args->[INSERTED_NODES]} ;

$args->[BUILD_TYPE] = DEPEND_AND_CHECK ;

# RUN
local $PBS::Output::indentation_depth = -1 ;

my ($build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package, $build_sequence) =
	$pbs_entry_point->(@$entry_point_args) ;

my @new_nodes = grep { ! exists $nodes_snapshot{$_} } keys %$inserted_nodes ;
my $new_nodes = @new_nodes ;

if(defined $pid)
	{
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
	
	my $server     = PBS::Net::StartHttpDeamon($pbs_config) ;
	my $server_url = $server->url ;
	
	for (@new_nodes, $target)
		{
		$inserted_nodes->{$_}{__PARALLEL_NODE}   = $$ ;
		$inserted_nodes->{$_}{__PARALLEL_SERVER} = $server_url
		}
	
	# remove undefined variables from pbs_configs, 10% speedup, 20% size
	for my $pbs_config (grep { state %seen ; ! $seen{$_}++ } map { $inserted_nodes->{$_}{__PBS_CONFIG} } @new_nodes, $target )
		{
		delete @$pbs_config{ grep { ! defined $pbs_config->{$_} } keys %$pbs_config }
		}
	
	my %not_depended ;
	my %graph  = 
		(
		TIME           => sprintf("%0.2f s.", tv_interval ($t0, [gettimeofday])),
		PID            => $$,
		ADDRESS        => $server_url,
		
		TARGET         => $target,
		INSERTING_NODE => $node->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE} // $node->{__INSERTED_AT}{INSERTING_NODE},
		PARENT         => $parent_pid,
		CHILDREN       => \%forked_children,
		PBS_RUNS       => PBS::PBS::GetPbsRuns(),
		
		NODES => 
			{
			map 
				{
				my $node_name = $_ ;
				my $node = $inserted_nodes->{$node_name} ;
				
				$not_depended{$node_name}++ if ! exists $node->{__DEPENDED} && ! $node->{__IS_SOURCE} ;
				
				$node_name =>
					{
					(
					map 
						{
						my $ref = ref $node->{$_} ;
						
						'' eq $ref
							? ($_ => $node->{$_})
							: 'HASH' eq $ref
								? 
									(
									$_ eq '__PBS_CONFIG' || $_ eq '__CONFIG'
										? ($_ => $node->{$_})
										: ($_ => {} )
									)
								:
									(
									$_ eq  '__TRIGGERED'
										? ($_ => $node->{$_})
										: ($_ => [] )
									)
						} 
						keys %$node
					),
					__PARENTS => [ map { $_->{__NAME}} $node->{__PARENTS}->@* ],
					}
				} @new_nodes, $target
			},
		) ;
	
	$graph{NOT_DEPENDED}{$_} = $graph{NODES}{$_} for keys %not_depended ;
	
	my $serialized_graph = freeze \%graph ;
	   $serialized_graph = Compress::Zlib::memGzip($serialized_graph) if $pbs_config->{DEPEND_PARALLEL_USE_COMPRESSION} ;
	
	RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;

	BecomeDependServer
		(
		$pbs_config, $pbs_config->{RESOURCE_SERVER}, $server, $log_file,
		{
			NODE    => $node,
			ARGS    => $args,
			ADDRESS => $server_url,
			GRAPH   => $serialized_graph
		}) ;
	
	exit 0 ;
	}
else
	{
	RestoreOutput($redirection) if $pbs_config->{LOG_PARALLEL_DEPEND} ;
	return $build_result, $build_message, $sub_tree, $inserted_nodes, $subpbs_load_package ;
	}


} 

#-------------------------------------------------------------------------------------------------------

sub BecomeDependServer
{
my ($pbs_config, $resource_server_url, $server, $log_file, $data) = @_ ;

PBS::Net::Post($pbs_config, $resource_server_url, 'parallel_depend_idling', { pid => $$ , address => $server->url, log => $log_file}, $$) ;
PBS::Net::BecomeServer($pbs_config, 'depender', $server, $data) ;
}

#-------------------------------------------------------------------------------------------------------

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = "${mday}_${mon}_${hour}_${min}_${sec}" ;

sub GetRedirectionFile
{
my ($pbs_config, $node) = @_ ;

my $redirection_file = $pbs_config->{BUILD_DIRECTORY} . "/.parallel_depend_$now_string/$$/$node->{__NAME}" ; 
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

sub LinkMainGraph
{
my ($pbs_config, $inserted_nodes, $targets, $depend_start_time, $dependers) = @_ ;

my $number_of_dependers = scalar keys %$dependers ;

my $graphs = LinkChildren($pbs_config, $dependers, $inserted_nodes, $targets) ;

for my $graph ( grep { $_->{ADDRESS} ne 'main graph' } values %$graphs)
	{
	#my $response = PBS::Net::Post($pbs_config, $graph->{ADDRESS}, 'build', {}, $$) ;
	}

my $t0 = [gettimeofday];

if($pbs_config->{RESOURCE_QUICK_SHUTDOWN})
	{
	kill 'KILL',  $_->{PID}  for values %$dependers ;
	}
else
	{
	PBS::Net::Post($pbs_config, $_->{ADDRESS}, 'stop', {}, $$)  for values %$dependers ;
	}

#PBS::Net::Post($pbs_config, $pbs_config->{RESOURCE_SERVER}, 'stop') ;

PrintInfo sprintf("PBS∥ : shutdown: %0.2f s.\n", tv_interval ($t0, [gettimeofday])) ;
PrintInfo sprintf("PBS∥ : time: %0.2f s.\n", tv_interval ($depend_start_time, [gettimeofday])) ;

if($pbs_config->{DISPLAY_PARALLEL_DEPEND_TREE})
	{
	local $pbs_config->{DEBUG_DISPLAY_TREE_NAME_ONLY} = 1 ;
	local $pbs_config->{DEBUG_DISPLAY_TEXT_TREE} = 1 ;

	RunPluginSubs($pbs_config, 'PostDependAndCheck', $pbs_config, $inserted_nodes->{$_}, $inserted_nodes, [], $inserted_nodes->{$_})
		for (@$targets) ;
	}
}

sub LinkChildren
{
my ($pbs_config, $dependers, $inserted_nodes, $targets) = @_ ;

my $t0_link = [gettimeofday];

my ($pbs_runs, $data_size)  = (0, 0) ;
my ($target, $target_pid) = ($targets->[0]) ;

my %graphs = map 
		{
		my $response = PBS::Net::Get($pbs_config, $dependers->{$_}{ADDRESS}, 'get_graph', {}, $$, RAW) ;
		$data_size += length $response ;
	
		$response = Compress::Zlib::memGunzip($response) if $pbs_config->{DEPEND_PARALLEL_USE_COMPRESSION} ;
		my $graph = thaw $response ;
		
		$pbs_runs += $graph->{PBS_RUNS} ;
		
		$target_pid = $graph->{PID} if $target eq $graph->{TARGET} ;
		
		$_ => $graph ; 
		} keys %$dependers ;

my $unit = 0 ;
++$unit and $data_size /= 1024 until $data_size < 1024 ;
$data_size = sprintf "%.2f %s",  $data_size, qw[ bytes KB MB GB ][$unit] ;

my $download_time = sprintf '%0.2f', tv_interval ($t0_link, [gettimeofday]) ;

my (%nodes, %targets, %not_linked, %processes) ;

my (@target_dependencies, %target_parents) ;

for my $graph (values %graphs)
	{
	push @target_dependencies, [$graph->{PID}, keys %{$graph->{CHILDREN}}] ;
	$target_parents{$_} = $graph->{PID} for keys $graph->{CHILDREN}->%* ;
	
	$processes{$graph->{PID}}{$_} = ( $processes{$_} //= {} ) for keys %{$graph->{CHILDREN}} ;
	$targets{$graph->{TARGET}}    = $graph ;
	
	Say Debug3 "Depend∥ : fetch $graph->{PID} < $graph->{ADDRESS} >" if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE} ;
	
	for (keys %{$graph->{NODES}})
		{
		if(exists $nodes{$_})
			{
			if(exists $graph->{NODES}{$_}{__PARALLEL_DEPEND})
				{
				#Say Debug "Depend∥ : fetch $_, skipping $graph->{PID}, previous: $nodes{$_}{PID}"
				#	if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE}
			
				# nodes that start another depend process gets overridden
				next ;
				}
			
			if(exists $nodes{$_}{NODES}{$_}{__PARALLEL_DEPEND})
				{
				#Say Debug "Depend∥ : fetch $_, $graph->{PID} overrides $nodes{$_}{PID}"
				#	if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE} ;
				}
			else
				{
				Say Error "Depend∥ : fetch $_, duplicate node in $graph->{PID}, previous: $nodes{$_}{PID}" ;
				}
			}
		
		$nodes{$_} = $graph ;
		}
	}

# de-trigger nodes
my ($build_success, @order) = PBS::Rules::Order::topo_sort(\@target_dependencies) ;

for (@order)
	{
	my $target = $graphs{$_}{TARGET} ;
	my $node   = $graphs{$_}{NODES}{$target} ;
	
	for my $trigger_index (keys $node->{__TRIGGERED}->@*) 
		{
		if($node->{__TRIGGERED}[$trigger_index]{REASON} eq '__PARALLEL_DEPEND')
			{
			splice $node->{__TRIGGERED}->@*, $trigger_index, 1 ;
			last
			}
		}

	if(0 != $node->{__TRIGGERED}->@*)
		{
		next ; # node still triggers, no de-triggering needed
		}
	else
		{
		delete $node->{__TRIGGERED} ;

#Say Debug "detrigger node $target" ;
		next unless exists $target_parents{$_} ;
		
		my $parent_graph = $graphs{$target_parents{$_}} ;
		my $parent_node  = $parent_graph->{NODES}{$graphs{$_}{INSERTING_NODE}} ;
		
		my $node_in_parent_graph  = $parent_graph->{NODES}{$target} ;
		delete $node_in_parent_graph->{__TRIGGERED} ;

		my @ancestors = [$parent_node, $target] ;
		
#Say Debug "detrigger parent node name $parent_node->{__NAME}, trigger: $target"  ;
		
		while (my $t = shift @ancestors)
			{
			my ($ancestor_node, $child_name) = $t->@* ;
			
			for my $trigger_index (keys $ancestor_node->{__TRIGGERED}->@*) 
				{
				if($ancestor_node->{__TRIGGERED}[$trigger_index]{NAME} eq $child_name)
					{
					splice $ancestor_node->{__TRIGGERED}->@*, $trigger_index, 1 ;
#Say Debug "detrigger remove trigger $child_name from $ancestor_node->{__NAME}" ;
					
					if(0 == $ancestor_node->{__TRIGGERED}->@*)
						{
						delete $ancestor_node->{__TRIGGERED} ;
					
#Say Debug "detrigger add ancestors to $ancestor_node->{__NAME} " . join ' ' , $ancestor_node->{__PARENTS}->@* ;
						#de-trigger it's parents
						push @ancestors, map { [$parent_graph->{NODES}{$_}, $ancestor_node->{__NAME}] } $ancestor_node->{__PARENTS}->@* ;
						}
					last ;
					}
				}
			
			# Todo: send the updated node trigger list and build sequence to the parallel pbs
			# send list of de-triggered nodes
			}
		}
	}

my $triggered = scalar @{$graphs{$target_pid}{NODES}{$graphs{$target_pid}{TARGET}}{__TRIGGERED} // []} ;

SIT $processes{$target_pid},
	EC("∥ $target_pid ($triggered)<I2> $graphs{$target_pid}{TARGET}, " . scalar(keys %{$graphs{$target_pid}{NODES}}) . "/" . $graphs{$target_pid}{TIME}),
	DISPLAY_ADDRESS => 0,
	NO_NO_ELEMENTS => 1,
	FILTER => sub 
			{
			my ($tree, $level, $path, $nodes_to_display, $setup) = @_ ;
			if('HASH' eq ref $tree)
				{
				my @keys_to_dump ;
				
				for (keys %$tree)
					{
					my $triggered = scalar @{$graphs{$_}{NODES}{$graphs{$_}{TARGET}}{__TRIGGERED} // []};
					
					push @keys_to_dump, [ $_,  EC("∥ $_ ($triggered)<I2> $graphs{$_}{TARGET}, " . scalar(keys %{$graphs{$_}{NODES}}) . "/" . $graphs{$_}{TIME}) ],
					}
					
				return('HASH', undef, sort @keys_to_dump) ;
				}
				
			return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
			}
	 if $pbs_config->{DISPLAY_PARALLEL_DEPEND_PROCESS_TREE} ;

# re-generate main graph

for my $node (keys %nodes)
	{
	my $display_info = $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE} ;
	my $main_graph ;
	
	if(exists $inserted_nodes->{$node})
		{
		$main_graph = $inserted_nodes->{$node} == $nodes{$node}{NODES}{$node} ;
		$display_info &&= ! $main_graph ;
		
		die ERROR("Depend∥ : merge: $node already depended") . "\n"
			if exists $inserted_nodes->{$node}{__DEPENDED}
				# except if it's a sub graph node that needs to be linked
				and ! $main_graph ;
		}
	else
		{
		$inserted_nodes->{$node} = $nodes{$node}{NODES}{$node} ;
		}
		
	Say Info "Depend∥ : merge $node from $nodes{$node}{ADDRESS} " if $display_info ;
	
	for my $element (keys %{$nodes{$node}{NODES}{$node}})
		{
 		if ($element !~ /^__/)
			{
			$inserted_nodes->{$element} = $nodes{$node}{NODES}{$element}
				unless exists $inserted_nodes->{$element} ;
			
			$inserted_nodes->{$node}{$element} = $inserted_nodes->{$element} ;
			
			Say Info2 "                $element" if $display_info ;
			}
		else
			{
			$inserted_nodes->{$node}{$element} = $nodes{$node}{NODES}{$node}{$element} unless $main_graph ;
			}
		}
	}

my $linked = 0 ;
for my $graph ( values %graphs)
	{
	for (keys %{$graph->{NOT_DEPENDED}})
		{
		if(exists $nodes{$_} and $nodes{$_}{PID} != $graph->{PID})
			{
			$graph->{LINKED}{$_} = $nodes{$_} ;
			$linked++ ;
			#Say Debug "Depend∥ : link $_, graph: $graph->{PID}" ;
			}
		elsif(exists $targets{$_})
			{
			$graph->{LINKED}{$_} = $targets{$_} ;
			$linked++ ;
			#Say Debug "Depend∥ : link  $_, graph: $graph->{PID}" ;
			}
		else
			{
			$not_linked{$_} = $graph->{NOT_DEPENDED}{$_} ;
			Say Error "Depend∥ : link : no candidate for $_, graph: $graph->{PID}" ;
			}
		}
	}

my $linked_dependers = 0 ;
my %chained_nodes ;

for my $graph ( values %graphs)
	{
	my $not_depended = scalar keys %{$graph->{NOT_DEPENDED}} ;
	
	my $links = scalar keys %{$graph->{LINKED}} ;
	$linked_dependers++  if $links ;
	
	if($not_depended != $links)
		{
		Say Warning "Depend∥ : not linked: $not_depended/$links, depender: < $graph->{PID} - $graph->{ADDRESS} >" ;
	
		for my $not_depended (keys %{$graph->{NOT_DEPENDED}})
			{
			Say Warning "         $not_depended" unless exists $graph->{LINKED}{$not_depended} ;
			}
		}
	else
		{
		my $main_header_displayed ;
		
 		for (keys %{$graph->{LINKED}})
			{
			Say EC "<I>Depend∥ : chain <I2>< $graph->{PID} - $graph->{ADDRESS} > <I3>$graph->{TARGET}"
				if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING} && ! $main_header_displayed++ ;
			
			Say EC "<I2>                < $graph->{LINKED}{$_}{PID} - $graph->{LINKED}{$_}{ADDRESS} ><I3> $_"
					if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE} ;
			
			# link to main process, send link info to remote pbs later
			#SDT $graphs{$graph->{LINKED}{$_}{PID}}{NODES}{$_}, "remote node", MAX_DEPTH => 1 ;
				
			my $node = $graph->{NODES}{$_}{__NAME} ;
			my $remote_node = $graphs{$graph->{LINKED}{$_}{PID}}{NODES}{$_} ;
			
			for my $element (keys %$remote_node)
				{
				if ($element !~ /^__/)
					{
					$inserted_nodes->{$element} = $remote_node->{$element}
						unless exists $inserted_nodes->{$element} ;
					
					$inserted_nodes->{$node}{$element} = $inserted_nodes->{$element} ;
					
					#Say Info2 "\t                $element"
					#	if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING} ;
					}
				else
					{
					#next if $element eq '' ;
					next if $element eq '__DEPENDENCY_TO' ;
					next if $element eq '__INSERTED_AT' ;
					next if $element eq '__MATCHING_RULES' ;
					
					$inserted_nodes->{$node}{$element} = $remote_node->{$element} ;
					}
				}
			
			push @{$chained_nodes{$graph->{ADDRESS}}},
				{
				node_name    => $_,
				node_pid     => $graph->{LINKED}{$_}{PID},
				node_address => $graph->{LINKED}{$_}{ADDRESS},
				} ;
			}
		}
	}

# send chain info to remote pbs
PBS::Net::Put($pbs_config, $_, 'link', freeze($chained_nodes{$_}), $$) for keys %chained_nodes ;

my $time2                   = sprintf '%0.2f', tv_interval ($t0_link, [gettimeofday]) ;
my $nodes                   = keys %nodes ;
my $not_linked              = keys %not_linked ;
my $number_of_dependers     = keys %$dependers ;
my $dependers_with_no_links = $number_of_dependers - $linked_dependers ;

Say Info "Depend∥ : dependers: $number_of_dependers, pbsfiles: $pbs_runs, linked: $linked_dependers, terminal: $dependers_with_no_links"
		. ", nodes: $nodes, links: $linked/$not_linked"
		. ", time: $time2 s., dl: $data_size in $download_time s." ;

\%graphs
}


#-------------------------------------------------------------------------------------------------------

my $counter = 0 ;

sub Link
{
my ($pbs_config, $data, $frozen_nodes) = @_ ;

my $nodes = thaw $frozen_nodes ;
 
local $PBS::Output::indentation_depth = 0 ;
use Carp ;

Say EC "<I>Depend∥ : link  <I2>< $$ - $data->{ADDRESS} >" . join(':', caller()) . Carp::longmess() . $counter++
	if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING} ;

for my $node (@$nodes)
	{
	Say EC "<I>                <I2>< $node->{node_pid} - $node->{node_address} ><I3>$node->{node_name}"
		if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE} ;
					
	$data->{ARGS}[INSERTED_NODES]{$node}{__PARALLEL_NODE}   = $node->{node_pid} ;
	$data->{ARGS}[INSERTED_NODES]{$node}{__PARALLEL_SERVER} = $node->{node_address} ;
	}
}

#-------------------------------------------------------------------------------------------------------

sub Build
{
my
	(
	$pbs_config,
	$config,
	$targets,
	$inserted_nodes,
	$tree,
	$build_point,
	$build_type,
	$build_node,
	$build_sequence,
	) = @_ ;

if(0 && $pbs_config->{PBS_JOBS})
	{
	PBS::Net::Post
		(
		$pbs_config, $pbs_config->{RESOURCE_SERVER},
		'build_all',
			{
			},
		$$
		) ;
	}
else
	{
	PBS::DefaultBuild::Build(@_) ;
	}
}

sub BuildNode
{
my ($node, $pbs_config, $inserted_nodes, $node_build_sequencer_info) = @_ ;
my $build_name = $node->{__BUILD_NAME} ;

if (exists $node->{__PARALLEL_NODE})
	{
	my $t0 = [gettimeofday];
	
	Say EC "<I>Build<W>∥ <I>: <I3>$node->{__NAME}<I2> < $node->{__PARALLEL_SERVER} >" ;
	
	my ($build_result, $build_message) = (BUILD_SUCCESS, "'$build_name' successful build") ;	
	
	#my ($dependencies, $triggered_dependencies) = GetNodeDependencies($node) ;
	 
	my $node_needs_rebuild = 1 ;
	
	if($node->{__BUILD_DONE})
		{
		#PrintWarning "Build: already build: $file_tree->{__BUILD_DONE}\n" ;
		$node_needs_rebuild = 0 ;
		}
	
	if(@{$pbs_config->{DISPLAY_BUILD_INFO}})
		{
		($build_result, $build_message) = (BUILD_FAILED, "--bi set, skip build.") ;
		$node_needs_rebuild = 0 ;
		}
		
	$build_result, $build_message
	#BUILD_FAILED, 'parallel node_build not implemented' ;
	}
else
	{
	PBS::Build::NodeBuilder::BuildNode(@_) ;
	}
}

#-------------------------------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::PBS::Forked  -

=head1 SYNOPSIS

=head1 DESCRIPTION

Support functionality to depend and build separate Pbs processes

=cut

