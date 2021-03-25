
package PBS::Warp::Warp1_5 ;

use strict ;
use warnings ;

use v5.10 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.11' ;

#-------------------------------------------------------------------------------

use PBS::Check::ForkedCheck ;
use PBS::Constants ;
use PBS::Digest ;
use PBS::Output ;
use PBS::Plugin;
use PBS::Warp;

use Data::Compare ;
use File::Slurp ;
use File::Path;
use JSON::XS ;
use List::Util qw(uniq) ;
use Time::HiRes qw(gettimeofday tv_interval) ;

#-----------------------------------------------------------------------------------------------------------------------

sub WarpPbs
{
my ($targets, $pbs_config, $parent_config) = @_ ;

my %external_checked ;

if(@{$pbs_config->{EXTERNAL_CHECKERS}})
	{
	%external_checked = map { chomp ; $_ => 1 } map { read_file($_) } uniq @{$pbs_config->{EXTERNAL_CHECKERS}} ;
	
	if(0 == keys %external_checked)
		{
		Say Info "\e[KWarp: Up to date" unless $pbs_config->{QUIET} ;

		return (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, 0) ;
		}
	}

my ($warp_signature) = PBS::Warp::GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/.warp1_5';
mkpath($warp_path) unless(-e $warp_path) ;
my $warp_file= "$warp_path/pbsfile_$warp_signature.pl" ;

Say Info "Warp: file name: '$warp_file'" if defined $pbs_config->{DISPLAY_WARP_FILE_NAME} ;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = "${mday}_${mon}_${hour}_${min}_${sec}" ;
my $triggers_file = "$warp_path/Triggers_${now_string}.pl" ;
$pbs_config->{TRIGGERS_FILE} = $triggers_file ;

my ($nodes, $node_names, $global_pbs_config, $warp_dependents) ;
my ($version, $number_of_nodes_in_the_dependency_tree, $warp_configuration, $distribution_digest) ;

my ($t0_warp, $t0_warp_check) = ([gettimeofday]) ;

my $run_in_warp_mode = 1 ;

# Loading of warp file can be eliminated if:
# we add the pbsfiles to the watched files
# we are registered with the watch server (it will have the nodes already)

my $warp_load_time = 0 ;

if(-e $warp_file)
	{
	($nodes, $node_names, $global_pbs_config, $warp_dependents,
	$version, $number_of_nodes_in_the_dependency_tree, $warp_configuration, $distribution_digest)
		= do $warp_file or do
			{
			PrintError "Warp: Couldn't evaluate warp file '$warp_file'\nFile error: $!\nCompilation error: $@" ;
			die "\n" ;
			} ;

	$warp_load_time = tv_interval($t0_warp, [gettimeofday]) ;

	$t0_warp_check = [gettimeofday];
	
	$run_in_warp_mode = 0  unless $number_of_nodes_in_the_dependency_tree ;

	# check distribution
	my ($rebuild_because_of_digest, $result_message, $number_of_difference) = PBS::Digest::CheckDistribution($pbs_config, $distribution_digest, 'Warp1_5') ;

	if ($rebuild_because_of_digest)
		{
		Say Info2 'Warp: changes in pbs distribution' ;
		$run_in_warp_mode = 0 ;
		}
	elsif(! defined $version || $version != $VERSION)
		{
		Say Info2 '"Warp: version mismatch.' ;
		$run_in_warp_mode = 0 ;
		}
	else
		{
		Say Info "Warp: checking $number_of_nodes_in_the_dependency_tree nodes." unless $pbs_config->{QUIET} ;
		}
	}
else
	{
	#Say Warning "Warp: file '_warp1_5/pbssfile_$warp_signature.pl' doesn't exist." ;
	$run_in_warp_mode = 0 ;
	}

my @build_result ;
if($run_in_warp_mode)
	{
	my $nodes_in_warp = scalar(keys %$nodes) ;

	# use filewatching, external checker, or default MD5 checking
	my $IsFileModified = RunUniquePluginSub($pbs_config, 'GetWatchedFilesChecker', $warp_signature, $nodes) ;

	if(@{$pbs_config->{EXTERNAL_CHECKERS}})
		{
		$IsFileModified = 
			sub
			{
			my ($pbs_config, $file, $warp_configurationi_file) = @_ ;
			
			exists $external_checked{$file} ;
			} ;
		}
	elsif($run_in_warp_mode && defined $IsFileModified  && '' eq ref $IsFileModified  && 0 == $IsFileModified )
		{
		# skip all tests if nothing is modified
		if($pbs_config->{DISPLAY_WARP_TIME})
			{
			my $warp_verification_time = tv_interval($t0_warp_check, [gettimeofday]) ;
			my $warp_total_time = tv_interval($t0_warp, [gettimeofday]) ;
			
			Say Info sprintf
					(
					"Warp: load time: %0.2f s., verification time: %0.2f s. total time: %0.2f s.",
					$warp_load_time, $warp_verification_time, $warp_total_time
					) unless $pbs_config->{QUIET} ;
			}
			
		Say Info "\e[KWarp: Up to date" unless $pbs_config->{QUIET} ;
		return (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, $nodes) ;
		}

	$IsFileModified //= \&PBS::Digest::IsFileModified ;

	# remove pbsfile triggered nodes and other global dependencies
	my $trigger_log_warp = CheckWarpConfiguration($pbs_config, $nodes, $warp_configuration, $warp_dependents, $node_names, $IsFileModified) ;

	# check and remove all nodes that would trigger
	my ($node_mismatch, $trigger_log)
		 = $pbs_config->{CHECK_JOBS} > 1
			? PBS::Check::ForkedCheck::ParallelCheckNodes($pbs_config, $nodes, $node_names, $IsFileModified, \&_CheckNodes) 
			: CheckNodes($pbs_config, $nodes, $node_names, $IsFileModified) ;

	$trigger_log .= "\n" . $trigger_log_warp ;

	my $number_of_removed_nodes = $nodes_in_warp - scalar(keys %$nodes) ;

	my $rebuilt = 0 ;
	# revivify the data PBS needs from the warp file for the nodes remaining from previous build
	for my $node (keys %$nodes)
		{
		PrintInfo2 "\e[KWarp: rebuilt node $rebuilt\r" if $rebuilt % 100 ;
		$rebuilt++ ;

		$nodes->{$node}{__NAME} = $node ;
		$nodes->{$node}{__BUILD_DONE} = 'Warp' ;
		$nodes->{$node}{__DEPENDED}++ ;
		$nodes->{$node}{__CHECKED}++ ; # pbs will not check any node (and its subtree) which is marked as checked
		
		$nodes->{$node}{__PBS_CONFIG} = $global_pbs_config unless exists $nodes->{$node}{__PBS_CONFIG} ;
		
		$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} = $node_names->[$nodes->{$node}{__INSERTED_AT}{INSERTION_FILE}] ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE} = 'N/A' ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE_NAME} = 'N/A' ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE_FILE} = 'N/A' ;
		$nodes->{$node}{__INSERTED_AT}{INSERTION_RULE_LINE} = 'N/A' ;
		$nodes->{$node}{__INSERTED_AT}{INSERTING_NODE} = $node_names->[$nodes->{$node}{__INSERTED_AT}{INSERTING_NODE}] ;

		$nodes->{$node}{__DEPENDED_AT} = $nodes->{$node}{__INSERTED_AT}{INSERTION_FILE} unless exists $nodes->{$node}{__DEPENDED_AT} ;
			
		# let our dependent nodes know about their dependencies
		# this is needed when regenerating the warp file from partial warp data
		for my $dependent (map {$node_names->[$_]} keys %{$nodes->{$node}{__DEPENDENT}})
			{
			$nodes->{$dependent}{$node} = $nodes->{$node} if(exists $nodes->{$dependent})
			}
		}
	write_file $pbs_config->{TRIGGERS_FILE}, "[ # warp triggers\n" . $trigger_log . "],\n" unless $trigger_log eq '' ;
	
	
	PrintInfo "\r\e[K" ;
	
	if($pbs_config->{DISPLAY_WARP_TIME} && (!$pbs_config->{QUIET} || $number_of_removed_nodes))
		{
		my $warp_verification_time = tv_interval($t0_warp_check, [gettimeofday]) ;
		
		my $info = "nodes: $nodes_in_warp, triggered:$node_mismatch, removed:$number_of_removed_nodes" ;
		
		Say Info sprintf("Warp: $info, load time: %0.2f s., check time: %0.2f s.", $warp_load_time, $warp_verification_time) ;
		}
	
	if($number_of_removed_nodes)
		{
		# we can't  generate a warp file while warping.
		# The warp configuration (pbsfiles md5) would be truncated
		# to the files used during the warp
		delete $pbs_config->{GENERATE_WARP1_5_FILE} ;
		
		# much of the "normal" node attributes are stripped in warp nodes
		# let the rest of the system know about this (ex graph generator)
		$pbs_config->{IN_WARP} = 1 ;

		my ($build_result, $build_message, $new_dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;
		
		eval
			{
			# PBS will link to the  warp nodes instead for creating them
			my $node_plural = '' ; $node_plural = 's' if $number_of_removed_nodes > 1 ;
			
			local $PBS::Output::indentation_depth = -1 ; 
			($build_result, $build_message, $new_dependency_tree, $inserted_nodes, $load_package, $build_sequence)
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
					$warp_file,
					$targets,
					$new_dependency_tree,
					$nodes,
					$pbs_config,
					'',
					$node_names, 
					)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
				}
				
			# died during depend or check
			die $@, "\n" ;
			}
		else
			{
			GenerateWarpFile
				(
				$warp_file,
				$targets,
				$new_dependency_tree,
				$nodes,
				$pbs_config, 
				'',
				$node_names, 
				)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
				
			# force a refresh after we build files and generated events
			# TODO: note that the synch should be by file not global
			RunUniquePluginSub($pbs_config, 'ClearWatchedFilesList', $warp_signature) ;
			}
			
		@build_result = ($build_result, $build_message, $new_dependency_tree, $nodes, $load_package, $build_sequence) ;
		}
	else
		{
		Say Info "\e[KWarp: Up to date" unless $pbs_config->{QUIET} ;
		@build_result = (BUILD_SUCCESS, "Warp: Up to date", {READ_ME => "Up to date warp doesn't have any tree"}, $nodes, 'warp up to date', []) ;
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
			$warp_file,
			$targets,
			$dependency_tree,
			$inserted_nodes,
			$pbs_config,
			) ;
			
		PrintInfo "\e[K" ;
		} unless $pbs_config->{NO_PRE_BUILD_WARP} ;
		
	my ($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;

	eval
		{
		local $PBS::Output::indentation_depth = -1 ;

		($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence)
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
					$warp_file,
					$targets,
					$dependency_tree_snapshot,
					$inserted_nodes_snapshot,
					$pbs_config,
					)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
				}
				
			die $@ ;
			}
		else
			{
			GenerateWarpFile
				(
				$warp_file,
				$targets,
				$dependency_tree,
				$inserted_nodes,
				$pbs_config,
				)  unless $pbs_config->{NO_POST_BUILD_WARP} ;
			}
			
	@build_result = ($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;
	}

# Say Info 'Warp: done' unless $pbs_config->{QUIET} ;

return(@build_result) ;
}

#-------------------------------------------------------------------------------

sub CheckWarpConfiguration
{
my ($pbs_config, $nodes, $warp_configuration, $warp_dependents, $node_names, $IsFileModified) = @_ ;
my $trigger_log_warp  = '' ;

for my $file (sort {($warp_dependents->{$b}{LEVEL} // 0)  <=> ($warp_dependents->{$a}{LEVEL} // 0)} keys %$warp_configuration)
	{
	# remove all level nodes and their parents
	my @nodes_triggered ;
 
	if ($IsFileModified->($pbs_config, $file, $warp_configuration->{$file}))
		{
		@nodes_triggered = 
			grep{ exists $nodes->{$_} } 
				map {$node_names->[$_]} keys %{$warp_dependents->{$file}{DEPENDENTS}} ;

		$trigger_log_warp .= "{ PBSFILE_NAME => '$file', NODES => " . scalar(@nodes_triggered) . "},\n" ;

		delete @{$nodes}{@nodes_triggered} ;

		# remove all sub nodes
		for my $sub_level (map {$node_names->[$_]} keys %{$warp_dependents->{$file}{SUB_LEVELS}})
			{
			push @nodes_triggered,
				grep{ exists $nodes->{$_} } 
					map {$node_names->[$_]} keys %{$warp_dependents->{$sub_level}{DEPENDENTS}} ;
	
			delete @{$nodes}{@nodes_triggered} ;
			}
		}

	if ($pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} )
		{
		Say Info "Warp: checking '$file', " . ERROR('removed nodes: ' . scalar(@nodes_triggered))
			if @nodes_triggered ;
		}
	elsif($pbs_config->{DISPLAY_WARP_CHECKED_NODES})
		{
		if (@nodes_triggered)
			{
			Say Info "Warp: checking '$file', " . ERROR('removed nodes: ' . scalar(@nodes_triggered)) ;
			}
		else
			{
			Say Info "Warp: checking '$file', OK" ;
			}
		}

	if ($pbs_config->{DISPLAY_WARP_REMOVED_NODES} && @nodes_triggered)
		{
		Say Info  'Warp: pruning' ;
		Say Info2 $PBS::Output::indentation . $_ for sort @nodes_triggered ;
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
	if('VIRTUAL' ne ($nodes->{$node}{__MD5} // ''))
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} = exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;
		}
	}

if($pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES})
	{
	my @terminal_nodes = grep { exists $nodes->{$_}{__TERMINAL} } keys %$nodes ;
	Say Warning "Warp: terminal nodes: " . scalar(@terminal_nodes) ;

	my %all_nodes_triggered ;

	my ($nodes_triggered, $trigger_nodes) =  _CheckNodes($pbs_config, $nodes, \@terminal_nodes , $node_names, $IsFileModified)  ;

	$all_nodes_triggered{$_}++ for @{$nodes_triggered} ;

	$number_trigger_nodes += @$trigger_nodes ;
	$trigger_log .= "{ NAME => '$_'},\n" for @$trigger_nodes ;

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
			_CheckNodes($pbs_config, $nodes, $nodes_per_level[$level] , $node_names, $IsFileModified, $level)  ;

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
my ($pbs_config, $nodes, $nodes_to_check, $node_names, $IsFileModified, $level) = @_ ;

$level  = defined $level && $level ne '' ? "<$level>" : '' ;

my ($number_of_removed_nodes, $node_verified) = (0, 0) ;
my (@trigger_nodes, @nodes_triggered, %nodes_triggered) ;

for my $node (@$nodes_to_check)
	{
	my $colorizer = $pbs_config->{QUIET} ? \&PrintInfo2 : \&PrintInfo ; 

	$colorizer->("\e[KWarp: verified nodes: $level$node_verified\r")
		   if $node_verified + $number_of_removed_nodes % 30 ;
		
	$node_verified++ ;
	
	next if ! exists $nodes->{$node} ; 
	
	if($pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES} && ! exists $nodes->{$node}{__TERMINAL})
		{
		#Say Warning "Check: --check_only_terminal_nodes, skipping $node" ;
		next ;
		}

	my $remove_this_node = 0 ;
	my @reasons ;

	# virtual nodes don't have MD5
	if('VIRTUAL' ne ($nodes->{$node}{__MD5} // '') && !$nodes->{$node}{__VIRTUAL} )
		{
		# rebuild the build name
		$nodes->{$node}{__BUILD_NAME} =	exists $nodes->{$node}{__LOCATION}
							? $nodes->{$node}{__LOCATION} . substr($node, 1) 
							: $node ;

		if (($nodes->{$node}{"__MD5"} // '' ) eq "invalid md5")
			{
			$remove_this_node++ ;
			push @reasons, "signature = '" . ($nodes->{$node}{"__MD5"} // '') . "'" ;
			}
		elsif($IsFileModified->($pbs_config, $nodes->{$node}{__BUILD_NAME}, $nodes->{$node}{__MD5}))
			{
			$remove_this_node++ ;
			push @reasons, 'modified' ;
			}
		}

	if(exists $nodes->{$node}{__FORCED})
		{
		$remove_this_node++ ;
		push @reasons, '__FORCED' ;
		}

	push @trigger_nodes, $node if $remove_this_node ;

	if($pbs_config->{DISPLAY_WARP_CHECKED_NODES})
		{
		if ($remove_this_node)
			{
			Say Info "\e[KWarp: removing: " . INFO3($node) . INFO2(" [" . join(' ,', @reasons) . "]") ;
			}
		else
			{
			Say Info "\e[KWarp: OK: " . INFO3($node) unless $pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} ;
			}
		}

	if($remove_this_node) #and its dependents and its triggerers if any
		{
		my @nodes_to_remove = ($node) ;
		
		Say Info "\e[KWarp: pruning from " . INFO3($node)
			if $pbs_config->{DISPLAY_WARP_REMOVED_NODES} && @nodes_to_remove ;

		while(@nodes_to_remove)
			{
			my @dependent_nodes ;
			
			for my $node_to_remove (grep{ exists $nodes->{$_} } @nodes_to_remove)
				{
				Say Info2 $PBS::Output::indentation . $node_to_remove
					if $pbs_config->{DISPLAY_WARP_REMOVED_NODES} && ! exists $nodes_triggered{$node_to_remove} ;
				
				push @dependent_nodes, grep{ ! exists $nodes_triggered{$_} } map {$node_names->[$_]} keys %{$nodes->{$node_to_remove}{__DEPENDENT}} ;
				
				# remove triggering node and its dependents
				if(exists $nodes->{$node_to_remove}{__TRIGGER_INSERTED})
					{
					my $trigerring_node = $nodes->{$node_to_remove}{__TRIGGER_INSERTED} ;
					push @dependent_nodes, grep{! exists $nodes_triggered{$_} } map {$node_names->[$_]} keys %{$nodes->{$trigerring_node}{__DEPENDENT}} ;
					push @nodes_triggered, $trigerring_node unless exists $nodes_triggered{$trigerring_node} ;
					$nodes_triggered{$trigerring_node}++ ;
					}
					
				push @nodes_triggered, $node_to_remove unless exists $nodes_triggered{$node_to_remove};
				$nodes_triggered{$node_to_remove}++ ;
				
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
my ($warp_file, $targets, $dependency_tree, $inserted_nodes, $pbs_config, $warp_message, $node_names,) = @_ ;
$warp_message //='' ;

unless($pbs_config->{DO_BUILD})
	{
	#Say Warning 'Warp: no generation, nothing built' ;
	return ;
	}

my $warp_configuration = PBS::Warp::GetWarpConfiguration($pbs_config) ;

Say Info "\e[KWarp: generation ... $warp_message" unless $pbs_config->{QUIET} ;
my $t0_warp_generate =  [gettimeofday] ;

my ($warp_signature, $warp_signature_source) = PBS::Warp::GetWarpSignature($targets, $pbs_config) ;
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/.warp1_5';
mkpath($warp_path) unless(-e $warp_path) ;

PBS::Warp::GenerateWarpInfoFile('1.5', $warp_path, $warp_signature, $targets, $pbs_config) ;

my $global_pbs_config = # cache to reduce warp file size
	{
	BUILD_DIRECTORY    => $pbs_config->{BUILD_DIRECTORY},
	SOURCE_DIRECTORIES => $pbs_config->{SOURCE_DIRECTORIES},
	} ;

(my $nodes, $node_names, my $warp_dependents) = 
	WarpifyTree1_5($pbs_config, $warp_configuration, $inserted_nodes, $global_pbs_config, $node_names) ;

my $number_of_nodes_in_the_dependency_tree = keys %$nodes ;

open(WARP, ">", $warp_file) or die qq[Can't open $warp_file: $!] ;
print WARP PBS::Log::GetHeader('Warp', $pbs_config) ;

local $Data::Dumper::Purity = 1 ;
local $Data::Dumper::Indent = 1 ;
local $Data::Dumper::Sortkeys = 1 ; 

my $js = $pbs_config->{WARP_HUMAN_FORMAT} ? JSON::XS->new->pretty(1) : JSON::XS->new ;

print WARP '$global_pbs_config = decode_json qq{' . $js->encode( $global_pbs_config ) . "} ;\n\n" ;
print WARP '$nodes = decode_json qq{' . $js->encode( $nodes ) . "} ;\n\n" ;
print WARP '$node_names = decode_json qq{' . $js->encode( $node_names ) . "} ;\n\n" ;
print WARP '$warp_dependents = decode_json qq{' . $js->encode( $warp_dependents ) . "} ;\n\n" ;
print WARP '$warp_configuration = decode_json qq{' . $js->encode( $warp_configuration ) . "} ;\n\n" ;

my ($pbs_digest) = PBS::Digest::GetPbsDigest($pbs_config) ; 
print WARP '$pbs_distribution_digest = decode_json qq{' . $js->encode( $pbs_digest ) . "} ;\n\n" ;

print WARP "\$version = $VERSION ;\n\$number_of_nodes_in_the_dependency_tree = $number_of_nodes_in_the_dependency_tree ;\n" ;

print WARP 'return $nodes, $node_names, $global_pbs_config, $warp_dependents,
	$version, $number_of_nodes_in_the_dependency_tree, $warp_configuration, $pbs_distribution_digest;';

close(WARP) ;

if($pbs_config->{DISPLAY_WARP_TIME})
	{
	my $warp_generation_time = tv_interval($t0_warp_generate, [gettimeofday]) ;
	Say Info sprintf("Warp: time: %0.2f s.", $warp_generation_time) ;
	}
}

#-----------------------------------------------------------------------------------------------------------------------

sub WarpifyTree1_5
{
my ($pbs_config, $warp_configuration, $inserted_nodes, $global_pbs_config, $node_names) = @_ ;

my ($package, $file_name, $line) = caller() ;

my %nodes ;
my @node_names = defined $node_names ? (@$node_names) : () ;

my %nodes_index ;
my $nodes_index_rebuild = 0 ;
$nodes_index{$_} = $nodes_index_rebuild++ for (@node_names) ;

my %libs ;
my %warp_dependents;

PBS::Digest::ClearMd5Cache() ;
my $new_nodes = 0 ;

for my $node_name (keys %$inserted_nodes)
	{
	my $node = $inserted_nodes->{$node_name} ;
	
	if(exists $node->{__WARP_NODE})
		{
		# reuse the revivified warp nodes directly
		$nodes{$node_name} = $node ;
		
		# remove data we re-generated when loading warp, those were needed by different parts of pbs
		delete @{$nodes{$node_name}}
				{qw(
				 __NAME __BUILD_DONE __BUILD_NAME __DEPENDED __DEPENDED_AT
				__LINKED __CHECKED __PBS_CONFIG__DEPENDENCY_TO __DEPENDENCY_TO
				__PBS_CONFIG
				)} ;
		
		$nodes{$node_name}{__INSERTED_AT}{INSERTING_NODE} = $nodes_index{$node->{__INSERTED_AT}{INSERTING_NODE}} ;
		$nodes{$node_name}{__INSERTED_AT}{INSERTION_FILE} = $nodes_index{$node->{__INSERTED_AT}{INSERTION_FILE}} ;
		
		delete $nodes{$node_name}{__INSERTED_AT}{INSERTION_RULE} ; 
		delete $nodes{$node_name}{__INSERTED_AT}{INSERTION_RULE_NAME} ; 
		delete $nodes{$node_name}{__INSERTED_AT}{INSERTION_RULE_FILE} ; 
		delete $nodes{$node_name}{__INSERTED_AT}{INSERTION_RULE_LINE} ; 
		
		for my $dependency (keys %{$nodes{$node_name}})
			{
			delete $nodes{$node_name}{$dependency} unless 0 == index($dependency, '__') ;
			}
		
		my @pbsfile_chain = @{$node->{__INSERTED_AT}{PBSFILE_CHAIN} // []} ;
		my $node_pbsfile_id = pop @pbsfile_chain ;
		
		# See "pbsfile change" comments below 
		if(defined $node_pbsfile_id)
			{
			my $node_pbsfile = $node_names[$node_pbsfile_id] ;
			
			$warp_dependents{$node_pbsfile}{DEPENDENTS}{$nodes_index{$node_name}}++ ;
			$warp_dependents{$node_pbsfile}{NODES}++ ;
			$warp_dependents{$node_pbsfile}{LEVEL} = @pbsfile_chain ;
			
			for my $pbsfile (@pbsfile_chain)
				{
				$warp_dependents{$node_names[$pbsfile]}{SUB_LEVELS}{$node_pbsfile_id}++ ;
				}
			}
		
		#todo: node can be linked to by new node and its pbsfile chain needs to be updated
		#	linking during non warp depend should also update the pbsfile chain 
		#	the linking is done by the parent
		}
	else
		{
		$new_nodes++ ;
		$nodes{$node_name}{__VIRTUAL} = 1 if(exists $node->{__VIRTUAL}) ;
			
		my $node_is_source = NodeIsSource($node) ;
		$nodes{$node_name}{__IS_SOURCE} = $node_is_source ;
		
		if(exists $node->{__LOAD_PACKAGE})
			{
			$nodes{$node_name}{__TERMINAL} = 1 if $node_is_source
			}
		elsif(exists $node->{__TERMINAL})
			{
			# remember which node is terminal for later optimization
			$nodes{$node_name}{__TERMINAL} = 1 ;
			}
		
		if(exists $node->{__FORCED})
			{
			$nodes{$node_name}{__FORCED}++ ;
			}
		
		if(!exists $node->{__VIRTUAL} && $node_name =~ /^\.(.*)/)
			{
			($nodes{$node_name}{__LOCATION}) = ($node->{__BUILD_NAME} // '')  =~ /^(.*)$1$/ ;
			
			delete $nodes{$node_name}{__LOCATION} if exists $nodes{$node_name}{__LOCATION} and $nodes{$node_name}{__LOCATION} eq '.' ;
			delete $nodes{$node_name}{__LOCATION} unless defined $nodes{$node_name}{__LOCATION} ;
			}
			
		my $inserting_node = exists $node->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
					&& exists $node->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
					? $node->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
					: $node->{__INSERTED_AT}{INSERTING_NODE} ;
		
		unless (exists $nodes_index{$inserting_node})
			{
			push @node_names, $inserting_node ;
			$nodes_index{$inserting_node} = $#node_names ;
			}
		
		$nodes{$node_name}{__INSERTED_AT}{INSERTING_NODE} = $nodes_index{$inserting_node} ;
		
		if(exists $node->{__DEPENDED_AT})
			{
			if($node->{__INSERTED_AT}{INSERTION_FILE} ne $node->{__DEPENDED_AT})
				{
				$nodes{$node_name}{__DEPENDED_AT} = $node->{__DEPENDED_AT} ;
				}
			}
			
		#reduce amount of data by indexing Insertion files (Pbsfile)
		my $insertion_file = $node->{__INSERTED_AT}{INSERTION_FILE} ;
		
		unless (exists $nodes_index{$insertion_file})
			{
			push @node_names, $insertion_file ;
			$nodes_index{$insertion_file} = $#node_names ;
			}
			
		$nodes{$node_name}{__INSERTED_AT}{INSERTION_FILE} = $nodes_index{$insertion_file} ;
		
		if
			(
			   $node->{__PBS_CONFIG}{BUILD_DIRECTORY}  ne $global_pbs_config->{BUILD_DIRECTORY}
			|| ! Compare($node->{__PBS_CONFIG}{SOURCE_DIRECTORIES}, $global_pbs_config->{SOURCE_DIRECTORIES})
			)
			{
			$nodes{$node_name}{__PBS_CONFIG}{BUILD_DIRECTORY} = $node->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
			$nodes{$node_name}{__PBS_CONFIG}{SOURCE_DIRECTORIES} = [@{$node->{__PBS_CONFIG}{SOURCE_DIRECTORIES}}] ; 
			}

		if(exists $node->{__BUILD_DONE})
			{
			# build done, can also be a node that did not trigger, up to date
			if(exists $node->{__VIRTUAL})
				{
				$nodes{$node_name}{__MD5} = 'VIRTUAL' ;
				}
			else
				{
				if(exists $node->{__INSERTED_AT}{INSERTION_TIME})
					{
					# this is a new node
					if(defined $node->{__MD5} && $node->{__MD5} ne 'invalid md5')
						{
						$nodes{$node_name}{__MD5} = $node->{__MD5} ;
						}
					else
						{
						if(defined (my $current_md5 = GetFileMD5($node->{__BUILD_NAME})))
							{
							$nodes{$node_name}{__MD5} = $node->{__MD5} = $current_md5 ;
							}
						else
							{
							Say Error "Warp: can't open '$node' to compute MD5 digest (old node/built/not_found): $!" ;
							die "\n" ;
							}
						}
					}
				else
					{
					# use the old md5
					$nodes{$node_name}{__MD5} = $node->{__MD5} ;
					}
				}
			}
		else
			{
			$nodes{$node_name}{__MD5} = 'not built yet' ; 
			}
		
		my $node_index ;
		if (exists $nodes_index{$node_name})
			{
			$node_index = $nodes_index{$node_name} ;
			}
		else
			{
			push @node_names, $node_name ;
			$node_index = $nodes_index{$node_name} = $#node_names;
			}

		if(exists $node->{__INSERTED_AT}{INSERTION_TIME})
			{
			for my $dependency (keys %{$node})
				{
				next if $dependency =~ /^__/ ;
				$nodes{$dependency}{__DEPENDENT}{$node_index}++ ;
				}
			}

		if (exists $node->{__TRIGGER_INSERTED})
			{
			$nodes{$node_name}{__TRIGGER_INSERTED} = $node->{__TRIGGER_INSERTED} ;
			}

		# add package dependencies to the node
		# package dependencies is sugar, we need to assign it in nodes to avoid triggering the whole
		# warp graph for a change that only impacts a few nodes

		# reduce size by transforming to indexes
		my @pbsfile_chain  ;

		@pbsfile_chain = map
				{
				my $node_index ;
				if (exists $nodes_index{$_})
					{
					$node_index = $nodes_index{$_} ;
					}
				else
					{
					push @node_names, $_ ;
					$node_index = $nodes_index{$_} = $#node_names ;
					}

				$node_index
				} @{$node->{__INSERTED_AT}{PBSFILE_CHAIN} // []} ;

		$nodes{$node_name}{__INSERTED_AT}{PBSFILE_CHAIN} = [@pbsfile_chain] ;
		
		my $node_pbsfile = pop @pbsfile_chain ;
		unless(defined $node_pbsfile)
			{
			# top level nodes and nodes inserted by pbs, ie: deppendencies
			$nodes{$node_name}{__WARP_NODE}++ ;
			next ;
			}

		$warp_dependents{$node_names[$node_pbsfile]}{DEPENDENTS}{$node_index}++ ;
		$warp_dependents{$node_names[$node_pbsfile]}{NODES}++ ;
		$warp_dependents{$node_names[$node_pbsfile]}{LEVEL} = @pbsfile_chain ;

		for my $pbsfile (@pbsfile_chain)
			{
			# pbsfile change: 

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
			$warp_dependents{$node_names[$pbsfile]}{SUB_LEVELS}{$node_pbsfile}++ ;
			}


		# extract package digest dependencies, note that this is only meaningful for new nodes
		# revivified nodes have a list of package dependencies

		if(exists $node->{__LOAD_PACKAGE}) # only new nodes have a __LOAD_PACKAGE 
			{
			my $package_digest = {
						%{PBS::Digest::GetPackageDigest($node->{__LOAD_PACKAGE})},
						%{PBS::Digest::GetNodeDigestNoChildren($node)},
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
						unless (exists $nodes_index{$1})
							{
							my $inserting_node = $node_names[$node_pbsfile] ;

							unless (exists $nodes_index{$inserting_node})
								{
								push @node_names, $inserting_node ;
								$nodes_index{$inserting_node} = $#node_names ;
								}

							$nodes{$1} =
								{
								__MD5 => $package_digest->{$package_dependency},
								__INSERTED_AT =>
									{
									INSERTION_FILE => 0,
									PBSFILE_CHAIN => [],
									INSERTING_NODE => $nodes_index{$inserting_node},
									},
								__TERMINAL => 1,
								__WARP_NODE => 1,
								} ;

							push @node_names, $1 ;
							$nodes_index{$1} = $#node_names ;
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

						unless (exists $nodes{$lib})
							{
							my $inserting_node = $node_names[$node_pbsfile] ;

							unless (exists $nodes_index{$inserting_node})
								{
								push @node_names, $inserting_node ;
								$nodes_index{$inserting_node} = $#node_names ;
								}

							$nodes{$lib} =
								{
								__MD5 => $package_digest->{$package_dependency} // '?',
								__INSERTED_AT =>
									{
									INSERTION_FILE => 0,
									PBSFILE_CHAIN => [],
									INSERTING_NODE => $nodes_index{$inserting_node},
									},
								__TERMINAL => 1,
								__WARP_NODE => 1,
								} ;

							push @node_names, $lib ;
							$nodes_index{$lib} = $#node_names ;
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

		$nodes{$node_name}{__WARP_NODE}++ ;
		}
	}

Say Info 'Warp: nodes: ' . scalar (keys %nodes) . ', new nodes: ' . $new_nodes unless $pbs_config->{QUIET} ;

# add nodes level above, to trigger
for my $warp_dependent_name (keys %warp_dependents)
	{
	$warp_configuration->{$warp_dependent_name} = GetFileMD5($warp_dependent_name) ;
	my $warp_dependent = $warp_dependents{$warp_dependent_name} ;
	
	for my $dependent ( keys %{$warp_dependent->{DEPENDENTS}} )
		{
		my @parents = GetWarpNodeParents($dependent, \%nodes, \@node_names)  ;

		for my $parent (@parents) 
			{
			unless (exists $warp_dependent->{DEPENDENTS}{$parent}) 
				{
				$warp_dependent->{DEPENDENTS}{$parent}++ ;
				}
			}
		}
	}

return(\%nodes, \@node_names, \%warp_dependents) ;
}

#-----------------------------------------------------------------------------------------------------------------------

sub GetWarpNodeParents
{
my ($node_id, $nodes, $node_names) = @_ ;

my @dependents = keys %{$nodes->{$node_names->[$node_id]}{__DEPENDENT}} ;

my @parents ;
push @parents, @dependents ;

for my $parent_id (@dependents) 
	{
	push @parents, GetWarpNodeParents($parent_id, $nodes, $node_names) ;
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
