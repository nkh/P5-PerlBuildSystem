
package PBS::Warp::Warp1_5 ;

use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.10' ;

#-------------------------------------------------------------------------------

use PBS::Output ;
use PBS::Digest ;
use PBS::Constants ;
use PBS::Plugin;
use PBS::Warp;
use PBS::Check::ForkedCheck ;

use File::Path;
use JSON::XS ;

use Data::Compare ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use POSIX qw(strftime);
use File::Slurp ;

#-----------------------------------------------------------------------------------------------------------------------

sub WarpPbs
{
my ($targets, $pbs_config, $parent_config) = @_ ;

my ($warp_signature) = PBS::Warp::GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/_warp1_5';
my $warp_file= "$warp_path/pbsfile_$warp_signature.pl" ;

PrintInfo "Warp: file name: '$warp_file'\n" if defined $pbs_config->{DISPLAY_WARP_FILE_NAME} ;

my ($nodes, $node_names, $global_pbs_config, $insertion_file_names, $warp_dependents) ;
my ($version, $number_of_nodes_in_the_dependency_tree, $warp_configuration) ;

my %nodes_index ; # reconstructed from $node_names ;

my ($t0_warp, $t0_warp_check) = ([gettimeofday]) ;

my $run_in_warp_mode = 1 ;

# Loading of warp file can be eliminated if:
# we add the pbsfiles to the watched files
# we are registered with the watch server (it will have the nodes already)

if(-e $warp_file)
	{
	($nodes, $node_names, $global_pbs_config, $insertion_file_names, $warp_dependents,
	$version, $number_of_nodes_in_the_dependency_tree, $warp_configuration)
		= do $warp_file or do
			{
			PrintError("Warp: Couldn't evaluate warp file '$warp_file'\nFile error: $!\nCompilation error: $@") ;
			die "\n" ;
			} ;

	if($pbs_config->{DISPLAY_WARP_TIME})
		{
		my $warp_load_time = tv_interval($t0_warp, [gettimeofday]) ;
		
		PrintInfo(sprintf("Warp: load time: %0.2f s.\n", $warp_load_time)) ;
		}
		
	$t0_warp_check = [gettimeofday];
	
	PrintInfo "Warp: checking $number_of_nodes_in_the_dependency_tree nodes.\n" unless $pbs_config->{QUIET} ;
	
	if(! defined $version || $version != $VERSION)
		{
		PrintWarning2("Warp: version mismatch.\n") ;
		$run_in_warp_mode = 0 ;
		}

	$run_in_warp_mode = 0  unless $number_of_nodes_in_the_dependency_tree ;
	}
else
	{
	PrintWarning("Warp: file '_warp1_5/pbssfile_$warp_signature.pl' doesn't exist.\n") ;
	$run_in_warp_mode = 0 ;
	}

my @build_result ;
if($run_in_warp_mode)
	{
	my $index = 0 ;
	%nodes_index = map { $_ => $index++ ;} @$node_names ;

	my $nodes_in_warp = scalar(keys %$nodes) ;

	# use filewatching or default MD5 checking
	my $IsFileModified = RunUniquePluginSub($pbs_config, 'GetWatchedFilesChecker', $pbs_config, $warp_signature, $nodes) ;

	# skip all tests if nothing is modified
	if($run_in_warp_mode && defined $IsFileModified  && '' eq ref $IsFileModified  && 0 == $IsFileModified )
		{
		if($pbs_config->{DISPLAY_WARP_TIME})
			{
			my $warp_verification_time = tv_interval($t0_warp_check, [gettimeofday]) ;
			PrintInfo(sprintf("Warp: verification time: %0.2f s.\n", $warp_verification_time)) ;
			
			my $warp_total_time = tv_interval($t0_warp, [gettimeofday]) ;
			PrintInfo(sprintf("Warp: total time: %0.2f s.\n", $warp_total_time)) ;
			}
			
		PrintInfo("\e[KWarp: Up to date\n") unless $pbs_config->{QUIET} ;
		return (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, $nodes) ;
		}

	$IsFileModified ||= \&PBS::Digest::IsFileModified ;

	# remove pbsfile triggered nodes and other global dependencies
	my $trigger_log_warp = CheckWarpConfiguration($pbs_config, $nodes, $warp_configuration, $warp_dependents, $node_names, $IsFileModified) ;

	# check and remove all nodes that would trigger
	my ($node_mismatch, $trigger_log)
		 = $pbs_config->{CHECK_JOBS} != 0
			? PBS::Check::ForkedCheck::ParallelCheckNodes($pbs_config, $nodes, $node_names, $IsFileModified, \&_CheckNodes) 
		  	: CheckNodes($pbs_config, $nodes, $node_names, $IsFileModified) ;

	$trigger_log .= "\n" . $trigger_log_warp ;

	my $number_of_removed_nodes = $nodes_in_warp - scalar(keys %$nodes) ;

	# rebuild the data PBS needs from the warp file for the nodes that have not triggered
	for my $node (keys %$nodes)
		{
		$nodes->{$node}{__NAME} = $node ;
		$nodes->{$node}{__BUILD_DONE} = 'Warp 1.5' ;
		$nodes->{$node}{__DEPENDED}++ ;
		$nodes->{$node}{__CHECKED}++ ; # pbs will not check any node (and its subtree) which is marked as checked
		
		$nodes->{$node}{__PBS_CONFIG} = $global_pbs_config unless exists $nodes->{$node}{__PBS_CONFIG} ;
		
		$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_names->[$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE}] ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE} = 'N/A Warp 1.5' ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE_NAME} = 'N/A' ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE_LINE} = 'N/A' ;

		unless(exists $nodes->{$node}{__DEPENDED_AT})
			{
			$nodes->{$node}{__DEPENDED_AT} = $nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
			}
			
		# let our dependent nodes know about their dependencies
		# this is needed when regenerating the warp file from partial warp data
		for my $dependent (map {$node_names->[$_]} keys %{$nodes->{$node}{__DEPENDENT}})
			{
			if(exists $nodes->{$dependent})
				{
				$nodes->{$dependent}{$node} =
					{
					__BUILD_DONE => 'Warp 1.5',
					__CHECKED => 1,
					} ;
				}
			}
		}

	my $now_string = strftime "%d_%b_%H_%M_%S", gmtime;
	write_file "$warp_path/Triggers_${now_string}.pl", "[\n" . $trigger_log . "]\n" unless $trigger_log eq '' ;

	if($pbs_config->{DISPLAY_WARP_TIME})
		{
		PrintInfo(sprintf("Warp: verification time: %0.2f s.\n", tv_interval($t0_warp_check, [gettimeofday]))) ;
		
		my $info = "[$nodes_in_warp/trigger:$node_mismatch/removed:$number_of_removed_nodes]" ;

		PrintInfo(sprintf("Warp: total time: %0.2f s. $info\n", tv_interval($t0_warp, [gettimeofday]))) ;
		}
		
	if($number_of_removed_nodes)
		{
		unless($pbs_config->{DISPLAY_WARP_GENERATED_WARNINGS})
			{
			$pbs_config->{NO_LINK_INFO} = 1 ;
			$pbs_config->{NO_LOCAL_MATCHING_RULES_INFO} = 1 ;
			}
			
		# we can't  generate a warp file while warping.
		# The warp configuration (pbsfiles md5) would be truncated
		# to the files used during the warp
		delete $pbs_config->{GENERATE_WARP1_5_FILE} ;
		
		# much of the "normal" node attributes are stripped in warp nodes
		# let the rest of the system know about this (ex graph generator)
		$pbs_config->{IN_WARP} = 1 ;

		my ($build_result, $build_message, $new_dependency_tree) ;
		
		eval
			{
			# PBS will link to the  warp nodes instead for creating them
			my $node_plural = '' ; $node_plural = 's' if $number_of_removed_nodes > 1 ;
			
			PrintInfo "Warp: running PBS in warp mode. $number_of_removed_nodes node$node_plural to rebuild.\n" ;
			
			local $PBS::Output::indentation_depth = -1 ; 
			($build_result, $build_message, $new_dependency_tree)
				= PBS::PBS::Pbs
					(
					[$pbs_config->{PBSFILE}],
					'ROOT_WARP1_5',
					$pbs_config->{PBSFILE},
					'', # parent package
					$pbs_config,
					$parent_config,
					$targets,
					$nodes,
					"warp_tree",
					DEPEND_CHECK_AND_BUILD,
					) ;
			} ;
			
		if($@)
			{
			if($@ =~ /^BUILD_FAILED/)
				{
				# this exception occurs only when a Builder fails so we can generate a warp file
				GenerateWarpFile
					(
					$targets, $new_dependency_tree, $nodes,
					$pbs_config, $warp_configuration, undef, $node_names, \%nodes_index,
					$warp_dependents
					)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
				}
				
			# died during depend or check
			die $@, "\n" ;
			}
		else
			{
			GenerateWarpFile
				(
				$targets, $new_dependency_tree, $nodes,
				$pbs_config, $warp_configuration, undef, $node_names, \%nodes_index,
				$warp_dependents
				)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
				
			# force a refresh after we build files and generated events
			# TODO: note that the synch should be by file not global
			RunUniquePluginSub($pbs_config, 'ClearWatchedFilesList', $pbs_config, $warp_signature) ;
			}
			
		@build_result = ($build_result, $build_message, $new_dependency_tree, $nodes) ;
		}
	else
		{
		PrintInfo("\e[KWarp: Up to date\n") unless $pbs_config->{QUIET} ;
		@build_result = (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, $nodes) ;
		}
	}
else
	{
	my ($dependency_tree_snapshot, $inserted_nodes_snapshot) ;
	
	$pbs_config->{INTERMEDIATE_WARP_WRITE} = 
		sub
		{
		my $dependency_tree = shift ;
		my $inserted_nodes = shift ;
		
		($dependency_tree_snapshot, $inserted_nodes_snapshot) = ($dependency_tree, $inserted_nodes) ;
		
		GenerateWarpFile
			(
			$targets,
			$dependency_tree,
			$inserted_nodes,
			$pbs_config,
			undef, # warp config
			' [pre-build]',
			) ;
		} unless $pbs_config->{NO_PRE_BUILD_WARP} ;
		
	my ($build_result, $build_message, $dependency_tree, $inserted_nodes) ;

	eval
		{
		local $PBS::Output::indentation_depth = -1 ;

		($build_result, $build_message, $dependency_tree, $inserted_nodes)
			= PBS::PBS::Pbs
				(
				[$pbs_config->{PBSFILE}],
				'ROOT',
				$pbs_config->{PBSFILE},
				'', # parent package
				$pbs_config,
				$parent_config,
				$targets,
				undef, # inserted files
				"root_NEEDS_REBUILD_pbs_$pbs_config->{PBSFILE}", # tree name
				DEPEND_CHECK_AND_BUILD,
				) ;
		} ;
		
		if($@)
			{
			if($@ =~ /^BUILD_FAILED/)
				{
				# this exception occurs only when a Builder fails so we can generate a warp file
				GenerateWarpFile
					(
					$targets,
					$dependency_tree_snapshot,
					$inserted_nodes_snapshot,
					$pbs_config, undef,
					)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
				}
				
			die $@ ;
			}
		else
			{
			GenerateWarpFile
				(
				$targets,
				$dependency_tree,
				$inserted_nodes,
				$pbs_config, undef,
				)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
			}
			
	@build_result = ($build_result, $build_message, $dependency_tree, $inserted_nodes) ;
	}

return(@build_result) ;
}

#-------------------------------------------------------------------------------

sub CheckWarpConfiguration
{
my ($pbs_config, $nodes, $warp_configuration, $warp_dependents, $node_names, $IsFileModified) = @_ ;
my $trigger_log_warp  = '' ;

for my $file (sort {($warp_dependents->{$b}{MAX_LEVEL} // 0)  <=> ($warp_dependents->{$a}{MAX_LEVEL} // 0)} keys %$warp_configuration)
	{
	# remove all level nodes and their parents
	my @nodes_triggered ;
 
	if ($IsFileModified->($pbs_config, $file, $warp_configuration->{$file}))
		{
		@nodes_triggered = 
			grep{ exists $nodes->{$_} } 
				map {$node_names->[$_]} keys %{$warp_dependents->{$file}{LEVEL}} ;

		$trigger_log_warp .= "{ PBSFILE_NAME => '$file', NODES => " . scalar(@nodes_triggered) . "},\n" ;

		# remove all sub nodes
		for my $sub_level (map {$node_names->[$_]} keys %{$warp_dependents->{$file}{SUB_LEVEL}})
			{
			push @nodes_triggered,
				grep{ exists $nodes->{$_} } 
					map {$node_names->[$_]} keys %{$warp_dependents->{$sub_level}{LEVEL}} ;
			}

		delete @{$nodes}{@nodes_triggered} ;
		}

	if($pbs_config->{DISPLAY_WARP_CHECKED_NODES})
		{
		if($pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} )
			{
			PrintInfo "Warp: checking '$file', removed nodes: " . scalar(@nodes_triggered) . "\n"
				if @nodes_triggered ;
			}
		else
			{
			PrintInfo "Warp: checking '$file', removed nodes: " . scalar(@nodes_triggered) . "\n";
			}
		}
	elsif (@nodes_triggered && $pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} )
		{
		PrintInfo "Warp: checking '$file', removed nodes: " . scalar(@nodes_triggered) . "\n"
		}

	if ($pbs_config->{DISPLAY_WARP_REMOVED_NODES} && @nodes_triggered)
		{
		PrintInfo "Warp: pruning\n" ;
		
		PrintInfo2 $PBS::Output::indentation . "$_\n" for sort @nodes_triggered ;
		}
	}

return $trigger_log_warp ;
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

sub CheckNodes
{
my ($pbs_config, $nodes, $node_names, $IsFileModified) = @_ ;

my @nodes_per_level ;
push @{$nodes_per_level[tr~/~/~]}, $_ for keys %$nodes ;
shift @nodes_per_level unless defined $nodes_per_level[0] ;

my ($number_trigger_nodes, $trigger_log) = (0, '') ;
my $sub_process = 8 ;

# location for MD5 computation
for my $node (keys %$nodes)
	{
	if('VIRTUAL' ne $nodes->{$node}{__MD5})
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} =	exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;
		}
	}

if($pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES})
	{
	my @terminal_nodes = grep { exists $nodes->{$_}{__TERMINAL} } keys %$nodes ;
	PrintWarning "Warp: terminal nodes: " . scalar(@terminal_nodes) . "\n" ;

	my %all_nodes_triggered ;

	for my $slice (distribute(scalar @terminal_nodes, $sub_process))
		{
		my @nodes_to_check = @terminal_nodes[$slice->[0] .. $slice->[1]] ;
		my ($nodes_triggered, $trigger_nodes) =  _CheckNodes($pbs_config, $nodes, \@nodes_to_check , $node_names, $IsFileModified)  ;

		$all_nodes_triggered{$_}++ for @{$nodes_triggered} ;

		$number_trigger_nodes += @$trigger_nodes ;
		$trigger_log .= "{ NAME => '$_'},\n" for @$trigger_nodes ;
		}

	# remove from dependency graph
	my @file_triggered_names = keys %all_nodes_triggered ;

	FlushMd5CacheMulti(\@file_triggered_names, $nodes) ; # nodes must still be in $nodes
	delete @{$nodes}{@file_triggered_names} ;
	}
else
	{
	for my $level (reverse 0 .. @nodes_per_level - 1)
		{
		next unless defined $nodes_per_level[$level] ;
		next unless scalar(@{$nodes_per_level[$level]}) ;

		my %all_nodes_triggered ;

		my ($nodes_triggered, $trigger_nodes) =
			_CheckNodes($pbs_config, $nodes, $nodes_per_level[$level] , $node_names, $IsFileModified)  ;

		$all_nodes_triggered{$_}++ for @{$nodes_triggered} ;

		$number_trigger_nodes += @$trigger_nodes ;
		$trigger_log .= "{ NAME => '$_'},\n" for @$trigger_nodes ;

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

return ($number_trigger_nodes, $trigger_log) ;
}

sub _CheckNodes
{
my ($pbs_config, $nodes, $nodes_to_check, $node_names, $IsFileModified) = @_ ;

my ($number_of_removed_nodes, $node_verified) = (0, 0) ;
my (@trigger_nodes, @nodes_triggered) ;

for my $node (@$nodes_to_check)
	{
	PrintInfo "Warp: verified nodes: $node_verified\r"
		if ! $pbs_config->{QUIET}
		   && ($node_verified + $number_of_removed_nodes) % 3330 ;
		
	$node_verified++ ;
	
	next unless exists $nodes->{$node} ; 
	
	if($pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES} && ! exists $nodes->{$node}{__TERMINAL})
		{
		#PrintWarning "Check: --check_only_terminal_nodes, skipping $node\n" ;
		next ;
		}

	my $remove_this_node = 0 ;
	
	# virtual nodes don't have MD5
	if('VIRTUAL' ne $nodes->{$node}{__MD5})
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} =	exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;

		$remove_this_node += $IsFileModified->($pbs_config, $nodes->{$node}{__BUILD_NAME}, $nodes->{$node}{__MD5}) ;
		}

	$remove_this_node++ if(exists $nodes->{$node}{__FORCED}) ;

	push @trigger_nodes, $node if $remove_this_node ;

	if($pbs_config->{DISPLAY_WARP_CHECKED_NODES})
		{
		if ($remove_this_node)	
			{
			PrintInfo "\e[KWarp: " . ERROR('Removing') . INFO("  $node\n") ;
			}
		else
			{
			PrintInfo("\e[KWarp: OK: $node\n") unless $pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} ;
			}
		}

	if($remove_this_node) #and its dependents and its triggerer if any
		{
		my @nodes_to_remove = ($node) ;
		
		PrintInfo "\e[KWarp: pruning\n" 
			if $pbs_config->{DISPLAY_WARP_REMOVED_NODES} && @nodes_to_remove ;

		while(@nodes_to_remove)
			{
			my @dependent_nodes ;
			
			for my $node_to_remove (grep{ exists $nodes->{$_} } @nodes_to_remove)
				{
				PrintInfo2 $PBS::Output::indentation . "$node_to_remove\n"
					if $pbs_config->{DISPLAY_WARP_REMOVED_NODES} ;
				
				push @dependent_nodes, grep{ exists $nodes->{$_} } map {$node_names->[$_]} keys %{$nodes->{$node_to_remove}{__DEPENDENT}} ;
				
				# remove triggering node and its dependents
				if(exists $nodes->{$node_to_remove}{__TRIGGER_INSERTED})
					{
					my $trigerring_node = $nodes->{$node_to_remove}{__TRIGGER_INSERTED} ;
					push @dependent_nodes, grep{ exists $nodes->{$_} } map {$node_names->[$_]} keys %{$nodes->{$trigerring_node}{__DEPENDENT}} ;
					push @nodes_triggered, $trigerring_node ;
					}
					
				push @nodes_triggered, $node_to_remove ;
				
				$number_of_removed_nodes++ ;
				}
				
			@nodes_to_remove = @dependent_nodes ;
			}
		}
	}

return (\@nodes_triggered, \@trigger_nodes) ;
}

#-----------------------------------------------------------------------------------------------------------------------

sub GenerateWarpFile
{
my ($targets, $dependency_tree, $inserted_nodes,
	$pbs_config,
	$warp_configuration,
	$warp_message,
	$node_names, $nodes_index,
	$warp_dependents
	) = @_ ;

$warp_message //='' ;

$warp_configuration = PBS::Warp::GetWarpConfiguration($pbs_config, $warp_configuration) ;

PrintInfo("\e[KWarp: generation.$warp_message\n") ;
my $t0_warp_generate =  [gettimeofday] ;

my ($warp_signature, $warp_signature_source) = PBS::Warp::GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/_warp1_5';
mkpath($warp_path) unless(-e $warp_path) ;

PBS::Warp::GenerateWarpInfoFile('1.5', $warp_path, $warp_signature, $targets, $pbs_config) ;

my $warp_file= "$warp_path/pbsfile_$warp_signature.pl" ;

my $global_pbs_config = # cache to reduce warp file size
	{
	BUILD_DIRECTORY    => $pbs_config->{BUILD_DIRECTORY},
	SOURCE_DIRECTORIES => $pbs_config->{SOURCE_DIRECTORIES},
	} ;

my ($nodes, $insertion_file_names) ;

($nodes, $node_names, $insertion_file_names, $warp_dependents) = 
	WarpifyTree1_5($pbs_config, $warp_configuration, $inserted_nodes, $global_pbs_config, $node_names, $nodes_index, $warp_dependents) ;

my $number_of_nodes_in_the_dependency_tree = keys %$nodes ;

open(WARP, ">", $warp_file) or die qq[Can't open $warp_file: $!] ;
print WARP PBS::Log::GetHeader('Warp', $pbs_config) ;

local $Data::Dumper::Purity = 1 ;
local $Data::Dumper::Indent = 1 ;
local $Data::Dumper::Sortkeys = 1 ; 

#my $js = JSON::XS->new->pretty(1)->canonical(1) ; # sort keys, slower 
my $js = JSON::XS->new->pretty(1) ;

print WARP '$global_pbs_config = decode_json qq{' . $js->encode( $global_pbs_config ) . "} ;\n\n" ;
print WARP '$nodes = decode_json qq{' . $js->encode( $nodes ) . "} ;\n\n" ;
print WARP '$node_names = decode_json qq{' . $js->encode( $node_names ) . "} ;\n\n" ;
print WARP '$insertion_file_names = decode_json qq{' . $js->encode( $insertion_file_names ) . "} ;\n\n" ;
print WARP '$warp_dependents = decode_json qq{' . $js->encode( $warp_dependents ) . "} ;\n\n" ;
print WARP '$warp_configuration = decode_json qq{' . $js->encode( $warp_configuration ) . "} ;\n\n" ;

print WARP "\$version = $VERSION ;\n\$number_of_nodes_in_the_dependency_tree = $number_of_nodes_in_the_dependency_tree ;\n" ;

print WARP 'return $nodes, $node_names, $global_pbs_config, $insertion_file_names, $warp_dependents,
	$version, $number_of_nodes_in_the_dependency_tree, $warp_configuration;';

close(WARP) ;

if($pbs_config->{DISPLAY_WARP_TIME})
	{
	my $warp_generation_time = tv_interval($t0_warp_generate, [gettimeofday]) ;
	PrintInfo(sprintf("Warp: total time: %0.2f s.\n", $warp_generation_time)) ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

sub WarpifyTree1_5
{
my ($pbs_config, $warp_configuration, $inserted_nodes, $global_pbs_config, $node_names, $nodes_index, $warp_dependents) = @_ ;

my ($package, $file_name, $line) = caller() ;

my (%nodes) ;

$node_names //= [] ;
$nodes_index //= {} ;
$warp_dependents //= {} ;

use Data::TreeDumper ;
#PrintUser DumpTree $nodes_index, 'node indexes', DISPLAY_ROOT_ADDRESS => 1 ;

my (@insertion_file_names, %insertion_file_index, %libs) ;

my $new_nodes = 0 ;

#PrintDebug  DumpTree$warp_dependents, 'warp dependents:' ;
for my $node (keys %$inserted_nodes)
	{
	if(exists $inserted_nodes->{$node}{__WARP_NODE})
		{
		# try to reuse the inserted nodes directly in writing the warp file
		# inserted nodes is itself mainly warp revivified nodes

		$nodes{$node} = $inserted_nodes->{$node} ;
		delete @{$nodes{$node}}
				{qw(
				 __NAME __BUILD_DONE __BUILD_NAME __DEPENDED __DEPENDED_AT
				__LINKED __CHECKED __PBS_CONFIG__DEPENDENCY_TO __DEPENDENCY_TO
				__PBS_CONFIG
				)} ;

		# remove dependencies, warp nodes have no dependencies!

		my $insertion_file = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
		
		unless (exists $insertion_file_index{$insertion_file})
			{
			push @insertion_file_names, $insertion_file ;
			$insertion_file_index{$insertion_file} = $#insertion_file_names ;
			}
			
		$nodes{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_index{$insertion_file} ;
		
		delete $nodes{$node}{__INSERTED_AT}{INSERTION_RULE} ; 
		
		# let our dependent nodes know about their dependencies
		# this is needed when regenerating the warp file from partial warp data
		for my $dependent (keys %{$nodes{$node}})
			{
			delete $nodes{$node}{$dependent} unless 0 == index($dependent, '__') ;
			}
	
		#todo: node can be linked to by new node and its pbsfile chain needs to be updated
		# the linking is done by the parent
		}
	else
		{
		$new_nodes++ ;
		if(exists $inserted_nodes->{$node}{__VIRTUAL})
			{
			$nodes{$node}{__VIRTUAL} = 1 ;
			}
			
		if(exists $inserted_nodes->{$node}{__LOAD_PACKAGE})
			{
			unless(PBS::Digest::IsDigestToBeGenerated($inserted_nodes->{$node}{__LOAD_PACKAGE}, $inserted_nodes->{$node}))
				{
				# remember which node is terminal for later optimization
				$nodes{$node}{__TERMINAL} = 1 ;
				}
			}
		elsif(exists $inserted_nodes->{$node}{__TERMINAL})
			{
			# remember which node is terminal for later optimization
			$nodes{$node}{__TERMINAL} = 1 ;
			}

		if(exists $inserted_nodes->{$node}{__FORCED})
			{
			$nodes{$node}{__FORCED} = 1 ;
			}

		if(!exists $inserted_nodes->{$node}{__VIRTUAL} && $node =~ /^\.(.*)/)
			{
			($nodes{$node}{__LOCATION}) = ($inserted_nodes->{$node}{__BUILD_NAME} =~ /^(.*)$1$/) ;
			}
			
		#this can also be reduced for a +/- 10% reduction
		if(exists $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
			&& exists $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE})
			{
			$nodes{$node}{__INSERTED_AT}{INSERTING_NODE} = $inserted_nodes->{$node}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
			}
		else
			{
			$nodes{$node}{__INSERTED_AT}{INSERTING_NODE} = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTING_NODE} ;
			}
		
		if(exists $inserted_nodes->{$node}{__DEPENDED_AT})
			{
			if($inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ne $inserted_nodes->{$node}{__DEPENDED_AT})
				{
				$nodes{$node}{__DEPENDED_AT} = $inserted_nodes->{$node}{__DEPENDED_AT} ;
				}
			}
			
		#reduce amount of data by indexing Insertion files (Pbsfile)
		my $insertion_file = $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ;
		
		unless (exists $insertion_file_index{$insertion_file})
			{
			push @insertion_file_names, $insertion_file ;
			$insertion_file_index{$insertion_file} = $#insertion_file_names ;
			}
			
		$nodes{$node}{__INSERTED_AT}{INSERTION_FILE} = $insertion_file_index{$insertion_file} ;
		
		if
			(
			   $inserted_nodes->{$node}{__PBS_CONFIG}{BUILD_DIRECTORY}  ne $global_pbs_config->{BUILD_DIRECTORY}
			|| ! Compare($inserted_nodes->{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES}, $global_pbs_config->{SOURCE_DIRECTORIES})
			)
			{
			$nodes{$node}{__PBS_CONFIG}{BUILD_DIRECTORY} = $inserted_nodes->{$node}{__PBS_CONFIG}{BUILD_DIRECTORY} ;
			$nodes{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES} = [@{$inserted_nodes->{$node}{__PBS_CONFIG}{SOURCE_DIRECTORIES}}] ; 
			}

		if(exists $inserted_nodes->{$node}{__BUILD_DONE})
			{
			# build done, can also be a node that did not trigger, up to date
			if(exists $inserted_nodes->{$node}{__VIRTUAL})
				{
				$nodes{$node}{__MD5} = 'VIRTUAL' ;
				}
			else
				{
				if(exists $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_TIME})
					{
					# this is a new node
					if(defined $inserted_nodes->{$node}{__MD5} && $inserted_nodes->{$node}{__MD5} ne 'not built yet')
						{
						#PrintUser "using new node md5 $node  $inserted_nodes->{$node}{__MD5}\n" ;
						$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} ;
						}
					else
						{
						if(defined (my $current_md5 = GetFileMD5($inserted_nodes->{$node}{__BUILD_NAME})))
							{
							$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} = $current_md5 ;
							}
						else
							{
							PrintError("Warp: can't open '$node' to compute MD5 digest (old node/built/not_found): $!\n") ;
							die "\n" ;
							}
						}
					}
				else
					{
					#PrintUser "using old md5 $node  $inserted_nodes->{$node}{__MD5}\n" ;
					# use the old md5
					$nodes{$node}{__MD5} = $inserted_nodes->{$node}{__MD5} ;
					}
				}
			}
		else
			{
			$nodes{$node}{__MD5} = 'not built yet' ; 
			}
		
		my $node_index ;	
		if (exists $nodes_index->{$node})
			{
			$node_index = $nodes_index->{$node} ;
			}
		else
			{
			push @$node_names, $node ;
			$node_index = $nodes_index->{$node} = $#$node_names;
			}

		if(exists $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_TIME})
			{
			for my $dependency (keys %{$inserted_nodes->{$node}})
				{
				next if $dependency =~ /^__/ ;
				$nodes{$dependency}{__DEPENDENT}{$node_index}++ ;
				}
			}

		if (exists $inserted_nodes->{$node}{__TRIGGER_INSERTED})
			{
			$nodes{$node}{__TRIGGER_INSERTED} = $inserted_nodes->{$node}{__TRIGGER_INSERTED} ;
			}

		# add package dependencies to the node
		# package dependencies is sugar, we need to assign it in nodes to avoid triggering the whole
		# warp graph for a change that only impacts a few nodes

		# reduce size by transforming to indexes
		# bug: when reloading a warp file they are already indexed
		my @pbsfile_chain  ;

		if (exists $inserted_nodes->{$node}{__WARP_NODE})
			{
			@pbsfile_chain = @{$inserted_nodes->{$node}{__INSERTED_AT}{PBSFILE_CHAIN} // []} ;
			}
		else
			{
			@pbsfile_chain = map
					{
					my $node_index ;	
					if (exists $nodes_index->{$_})
						{
						$node_index = $nodes_index->{$_} ;
						}
					else
						{
						push @$node_names, $_ ;
						$node_index = $nodes_index->{$_} = $#$node_names ;
						}

					$node_index
					} @{$inserted_nodes->{$node}{__INSERTED_AT}{PBSFILE_CHAIN} // []} ;
			}

		$nodes{$node}{__INSERTED_AT}{PBSFILE_CHAIN} = [@pbsfile_chain] ;
		
		my $node_pbsfile = pop @pbsfile_chain ;

		next unless defined $node_pbsfile ; # top level nodes and nodes inserted by pbs, ie: deppendencies

		$warp_dependents->{$node_names->[$node_pbsfile]}{LEVEL}{$node_index}++ ;
		$warp_dependents->{$node_names->[$node_pbsfile]}{MAX_LEVEL} = @pbsfile_chain ;

		for my $pbsfile (@pbsfile_chain)
			{
			# a pbsfile change means that we do not know if the warp graph is correct anymore
			# as the change may have added or removed sub graphs

			# a pbsfile change means that the nodes, above the current level, must be triggered (removing them)
			# for a rebuild _and_ that the nodes below must be removes for the graph to be correct

			# in this loop the pbsfile p2 is part of the chain, ie: N2: p1->p2->p3
			# so we can trigger N2 if a pbsfile has changed.

			# say that the graph is like this Nroot: N2
			# when pbs checks Nroot, it finds it untriggered and the build is considered done,
			# the Nroot need to be triggered too

			# the right way to trigger nodes above is to follow the dependency chain and remove
			# the nodes along the way (that's done when warp checking , this only builds the list)
			# and remove all the nodes in the levels below

			# nodes for pbsfile level and below, to remove
			$warp_dependents->{$node_names->[$pbsfile]}{SUB_LEVEL}{$node_pbsfile}++ ;
			}


		# extract package digest dependencies, note that this is only meaningful for new noddes
		# revivified nodes do not have a __LOAD_PACKAGE 
		if(exists $inserted_nodes->{$node}{__LOAD_PACKAGE})
			{
			my $package_digest = {
						%{PBS::Digest::GetPackageDigest($inserted_nodes->{$node}{__LOAD_PACKAGE})},
						%{PBS::Digest::GetNodeDigestNoChildren($inserted_nodes->{$node})},
						} ;

			for my $package_dependency (keys %$package_digest)
				{
				if($package_dependency =~ /^__FILE:(.*)/)
					{
					# This node gets triggered by a change to the file
					# the file is in the digest but warp is a mega digest and knows nothing about the digest

					# only the node needs to be removed, it doesn't change the graph like a pbsfile
					# it doesn't even need to be among the warp config

					# add it as a node, if not already there and trigger this node if it changes
					# warp verify takes all nodes, even if we add them here and removes all its dependents
					# dependents are written by node_index, which we have for this node

					unless(exists $nodes{$1})
						{
						unless (exists $nodes_index->{$1})
							{
							$new_nodes++ ;

							$nodes{$1} =
								{
								__MD5 => $package_digest->{$package_dependency},
								__INSERTED_AT =>
									{
									INSERTION_FILE => 0,
									PBSFILE_CHAIN => $inserted_nodes->{$node}{__INSERTED_AT}{PBSFILE_CHAIN} // [],
									INSERTING_NODE => $node_pbsfile,
									},
								__TERMINAL => 1,
								__WARP_NODE => 1,
								} ;

							push @$node_names, $1 ;
							$nodes_index->{$1} = $#$node_names ;
							}
						}

					$nodes{$1}{__DEPENDENT}{$node_index}++ ;
					}
				elsif($package_dependency =~ /^__PBS_LIB_PATH\/(.*)/)
					{
					use File::Spec::Functions qw(:ALL) ;
					
					my $lib = $1 ;

					if(exists $libs{$lib})
						{
						$lib = $libs{$lib} ;
						}
					else
						{
						my $location = '' ;
						if(file_name_is_absolute($lib) || $lib =~ m~^./~)
							{
							$location = '' ;
							}
						else
							{
							for my $lib_path (@{$pbs_config->{LIB_PATH}})
								{
								$lib_path .= '/' unless $lib_path =~ /\/$/ ;
								
								if(-e $lib_path . $lib)
									{
									$location = $lib_path ;
									last ;
									}
								}
							}

						$lib = $libs{$lib} = $location . $lib ;

						unless (exists $nodes_index->{$lib})
							{
							$new_nodes++ ;

							$nodes{$lib} =
								{
								__MD5 => $package_digest->{$package_dependency} // '?',
								__INSERTED_AT =>
									{
									INSERTION_FILE => 0,
									PBSFILE_CHAIN => $inserted_nodes->{$node}{__INSERTED_AT}{PBSFILE_CHAIN} // [],
									INSERTING_NODE => $node_pbsfile,
									},
								__TERMINAL => 1,
								__WARP_NODE => 1,
								} ;

							push @$node_names, $lib ;
							$nodes_index->{$lib} = $#$node_names ;
							}
						}

					$nodes{$lib}{__DEPENDENT}{$node_index}++ ;
					}
				else
					{
					#todo:
					# add dependencies added at package level for specific nodes
					# or remove the possibility altogether, it's better to add it in rules than at package level
					# note that it wasn't supported by previous warp, nor is ENV, variable, ...

					#die ERROR("Warp: $package_dependency is not handled by warp, for node '$node' "
					#	. "inserted in '" . $inserted_nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} ."'")
					#	. "\n" ;
					}
				}
			}
		}

	$nodes{$node}{__WARP_NODE}++ ;
	}

PrintInfo "Warp: nodes: " . scalar (keys %nodes) . ", new_nodes = $new_nodes\n" ;

# add nodes level above, to trigger
for my $file (keys %$warp_dependents)
	{
	$warp_configuration->{$file} = GetFileMD5($file) ;

	my $dependents = $warp_dependents->{$file} ;

	for my $node ( keys %{ $dependents->{LEVEL} } )
		{
		for my $parent (map { $_->{__NAME} } grep { $_->{__NAME} !~ /^__/ } GetParents($inserted_nodes->{$node_names->[$node]})) 
			{
			$dependents->{LEVEL}{$nodes_index->{$parent}}++ unless exists $dependents->{LEVEL}{$nodes_index->{$parent}} ;
			}
		}
	}

return(\%nodes, $node_names, \@insertion_file_names, $warp_dependents) ;
}

#-----------------------------------------------------------------------------------------------------------------------

sub GetParents
{
my ($node) = @_ ;

my @parents ;

if(exists $node->{__PARENTS})
	{
	push @parents, @{$node->{__PARENTS}} ;

	for my $parent (@{$node->{__PARENTS}}) 
		{
		push @parents, GetParents($parent) ;
		}
	}

return @parents ;
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Warp::Warp1_5  -

=head1 DESCRIPTION

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS::Information>.

=cut
