
package PBS::Graph ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.04' ;

use Data::Dumper ;
use Data::TreeDumper ;

use PBS::Constants ;
use PBS::Debug ;
use PBS::GraphViz;
use PBS::Output ;

#-------------------------------------------------------------------------------

use constant PBS_ROOT_NAME => 'PBS ROOT' ;

my $free_config_index = 0 ;
my $free_pbs_config_index = 0 ;
my $free_node_index = 0 ;
my @post_edge_insertion ; # some edges must be drawn after the tree has been processed
my %html_data ; # stores data for the html dumper

sub GenerateTreeGraphFile
{
$free_node_index = 0 ;
$free_config_index = 0 ;
$free_pbs_config_index = 0 ;
@post_edge_insertion = () ;
%html_data = () ;

my $trees          = shift ;
my $inserted_nodes = shift ;
my $title          = shift || 'pbs_tree' ;
my $config         = shift || {} ;

my $primary_tree = shift @$trees ;

PrintInfo("\nGraph: starting generation\n") ;
if($config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE} && $config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES})
	{
	PrintWarning("Graph: graph can't be clustered on definition package and source directory. Definition package will be used\n") ;
	$config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES} = 0 ;
	}
	
PrintInfo("Graph: using package clusters.\n") if $config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE} ;
PrintInfo("Graph: configs will be displayed.\n") if $config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG} ;
PrintInfo("Graph: using source directory clusters.\n") if $config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES} ;
PrintInfo("Graph: build directories will displayed.\n") if $config->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY} ;
PrintInfo("Graph: triggered nodes not parts of the primary build will be shown.\n") if $config->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES} ;
PrintInfo("Graph: dot file will be generated.\n") if($config->{GENERATE_TREE_GRAPH_CANONICAL}) ;

if($config->{GENERATE_TREE_GRAPH_CLUSTER_NODE} && @{$config->{GENERATE_TREE_GRAPH_CLUSTER_NODE}})
	{
	PrintInfo("Graph: these nodes and their dependencies will be displayed as a single unit:\n") ;
	for my $cluster_node_name (@{$config->{GENERATE_TREE_GRAPH_CLUSTER_NODE}})
		{
		PrintInfo("\t$cluster_node_name\n") ;
		}
	}
	
PrintInfo("Graph: Postscript output.\n") if($config->{GENERATE_TREE_GRAPH_POSTSCRIPT}) ;
PrintInfo("Graph: SVG output.\n") if($config->{GENERATE_TREE_GRAPH_SVG}) ;

my %inserted_graph_nodes   = () ;
my %inserted_edges   = () ;
my %inserted_configs = () ;
my %inserted_pbs_configs = () ;

my $primary_group = '' ;
$primary_group = PBS_ROOT_NAME if($config->{GENERATE_TREE_GRAPH_GROUP_MODE} >= GRAPH_GROUP_PRIMARY) ;

my $other_trees_root_rank ;
my $root_name = $primary_tree->{__NAME} ;

if($root_name =~ /^__PBS/)
	{
	$root_name = PBS_ROOT_NAME ;
	$other_trees_root_rank = 1 ; # align other trees with targets, under vistual root
	}
else
	{
	$other_trees_root_rank = 0 ; # no virtual rooot
	}
	
my $graph = PBS::GraphViz->new
		(
		root => $root_name,
		#~ sort => 1,
		#~ concentrate => 1,
		#~ pack => 1,
		#~ fontname => 'Helvetica',
		color => 'grey88',
		style => 'filled',
		fillcolor => 'grey98',
		fontcolor => 'black',
		fontsize => 10,
		ranksep => $config->{GENERATE_TREE_GRAPH_SPACING} * .75,
		nodesep => $config->{GENERATE_TREE_GRAPH_SPACING} * .25,
		URL => "",
		);
						
my $tree_node = GenerateTreeGraph
			(
			$graph,
			$primary_tree,
			$root_name,
			'',
			$config,
			\%inserted_graph_nodes,
			\%inserted_edges,
			\%inserted_configs,
			\%inserted_pbs_configs,
			'lightyellow', # fill color
			0, # root rank 
			0, # start rank
			$primary_group,
			);

if($config->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES})
	{
	my $start_rank = 0 ;
	
	for my $other_tree (@$trees)
		{
		$start_rank += 10_000 ;
		
		my $secondary_group = '' ;
		$secondary_group = $other_tree->{__NAME} if($config->{GENERATE_TREE_GRAPH_GROUP_MODE} >= GRAPH_GROUP_SECONDARY) ;
		
		GenerateTreeGraph
					(
					$graph,
					$other_tree,
					$other_tree->{__NAME},
					'', # clustering node name
					$config,
					\%inserted_graph_nodes,
					\%inserted_edges,
					\%inserted_configs,
					\%inserted_pbs_configs,
					'grey88', # fill color
					$other_trees_root_rank,
					$start_rank,
					$secondary_group,
					);
		}
	}
	
$graph->add_edge($_) for (@post_edge_insertion) ;

use POSIX qw(strftime);
my $now_string = strftime "%a %b %e %H:%M:%S %Y", gmtime;

my $graph_name ;

$graph_name .= "$title\n PBS on $now_string" ;
$graph_name .= "Using warp.\n" if($config->{IN_WARP}) ;
$graph_name .= "Using package clusters.\n" if($config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE}) ;
$graph_name .= "Using source directory clusters.\n" if($config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES}) ;

my $title_node = $graph->add_node
			({
			shape => 'box',
			name => $graph_name,
			color => 'white',
			#~ fontname => 'arial',
			fontsize => 8, 
			});
									
$graph->add_edge({ style => 'invis', from => $title_node, to => $tree_node} );

if($config->{GENERATE_TREE_GRAPH_HTML})
	{
	use PBS::Graph::Html ;
	
	PrintInfo("Graph: generating html data.\n") ;
	
	$html_data{DIRECTORY} = $config->{GENERATE_TREE_GRAPH_HTML} ;
	$html_data{TREE}      = $primary_tree ;
	$html_data{PNG}       = $graph->as_png() ;
	$html_data{CMAP}      = $graph->as_cmap() ;
	$html_data{USE_FRAME} = $config->{GENERATE_TREE_GRAPH_HTML_FRAME} ; 
	
	PBS::Graph::Html::GenerateHtmlGraph(\%html_data) ;
	}

if(defined $config->{GENERATE_TREE_GRAPH_CANONICAL})
	{
	$config->{GENERATE_TREE_GRAPH_CANONICAL} .= '.dot' unless $config->{GENERATE_TREE_GRAPH_CANONICAL} =~ /\.dot$/ ;
	PrintInfo("Graph: dot file: '$config->{GENERATE_TREE_GRAPH_CANONICAL}'.\n") ;
	$graph->as_canon($config->{GENERATE_TREE_GRAPH_CANONICAL}) ;
	}

my $gtg_format = $config->{GENERATE_TREE_GRAPH_FORMAT} // 'svg' ;
$gtg_format = lc $gtg_format ;

if($config->{GENERATE_TREE_GRAPH})
	{
	if($gtg_format eq 'svg')
		{
		$config->{GENERATE_TREE_GRAPH} .= '.svg' unless $config->{GENERATE_TREE_GRAPH} =~ /\.svg$/ ;
		PrintInfo("Graph: svg file: '$config->{GENERATE_TREE_GRAPH}'.\n") ;
		if(open(SVG, ">", $config->{GENERATE_TREE_GRAPH}))
			{
			print SVG $graph->as_svg() ;
			close SVG ;
			}
		else
			{
			PrintErro("Graph: can't open '$config->{GENERATE_TREE_GRAPH}' : $!") ;
			}
		}
	elsif($gtg_format eq 'ps')
		{
		$config->{GENERATE_TREE_GRAPH} .= '.ps' unless $config->{GENERATE_TREE_GRAPH} =~ /\.ps$/ ;
		PrintInfo("Graph:  postscript file: '$config->{GENERATE_TREE_GRAPH}'.\n") ;
		if(open(PS, ">", $config->{GENERATE_TREE_GRAPH}))
			{
			print PS $graph->as_ps() ;
			close PS ;
			}
		else
			{
			PrintErro("Graph: can't open '$config->{GENERATE_TREE_GRAPH}' : $!") ;
			}
		}
	elsif($gtg_format eq 'png')
		{
		$config->{GENERATE_TREE_GRAPH} .= '.png' unless $config->{GENERATE_TREE_GRAPH} =~ /\.png$/ ;
		PrintInfo("Graph: png file: '$config->{GENERATE_TREE_GRAPH}'.\n") ;
		$graph->as_png($config->{GENERATE_TREE_GRAPH}) ;
		}
	}

if($config->{GENERATE_TREE_GRAPH_SNAPSHOTS})
	{
	use PBS::Graph::Snapshots ;
	PBS::Graph::Snapshots::GenerateSnapshots
		(
		[$primary_tree, @$trees], 
		$inserted_nodes,
		$graph,
		$primary_tree->{__PBS_CONFIG}{GENERATE_TREE_GRAPH_SNAPSHOTS},
		\%inserted_graph_nodes, # this and below contain name only
		\%inserted_edges,
		\%inserted_configs,
		\%inserted_pbs_configs,
		) ;
	}
	
PrintInfo("Graph: done.\n") ;
}

#-------------------------------------------------------------------------------
my @cluster_regex_colors = qw(orange plum gold wheat seagreen1 skyblue1 grey80) ;
my $cluster_regex_color_index = 0 ;
my $cluster_regex_color_size = @cluster_regex_colors ;

sub GenerateTreeGraph
{
my
	(
	$graph,
	$node,
	$name,
	$clustering_node_name,
	$config,
	$inserted_graph_nodes, $inserted_edges, $inserted_configs, $inserted_pbs_configs,
	$fill_color,
	$root_rank,
	$rank,
	$group,
	) = @_ ;

my $display_definition_package = $config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE} ;
my $display_source_directory   = $config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES} ;
my $display_build_directory    = $config->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY} ;

$name ||= $node->{__NAME} ;
$group ||= '' ;

my $include_node = 1 ;

for my $exclude_node_regex (@{$config->{GENERATE_TREE_GRAPH_EXCLUDE}})
	{
	if($name =~ /$exclude_node_regex/)
		{
		$include_node = 0 ;
		
		for my $include_node_regex (@{$config->{GENERATE_TREE_GRAPH_INCLUDE}})
			{
			if($name =~ /$include_node_regex/)
				{
				$include_node = 1 ;
				last ;
				}
			}
			
		last ;
		}
	}

unless($include_node == 1)
	{
	PrintInfo("Graph: excluding node '$name' and it's dependency.\n") ;
	return() ;
	}
else
	{
	#PrintInfo("Graph: adding node '$name' and it's dependency.\n") ;
	}

my $inserting_node_link = 0 ; # used to verify if inserted link has been drawn

my $label = $name ;
if($display_build_directory)
	{
	if(exists $node->{__BUILD_NAME})
		{
		if($node->{__BUILD_NAME} ne $name)
			{
			$label = $name . "\n" . $node->{__BUILD_NAME}  ;
			}
		#else
			# display node name only
		}
	else
		{
		$label = $name . "\n" . 'build directory not set because of cyclic dependency' ;
		}
	}
	
my $node_type = ref $node ;
my $graph_node ;

if($node_type eq 'HASH') 
	{
	my %triggering_dependencies ;
	
	my $html_link = "node$free_node_index.html" ;
	$html_data{NODES}{"$free_node_index"}{FILE} = $html_link ;
	$html_data{NODES}{"$free_node_index"}{DATA} = $node ;
	$free_node_index++ ;
	
	if(exists $node->{__TRIGGERED})
		{
		for my $triggered_dependency_data (@{$node->{__TRIGGERED}})
			{
			my $dependency_name = $triggered_dependency_data->{NAME} ;
			
			$triggering_dependencies{$dependency_name}++ ;
			}
		}
		
	my @node_attributes ; 
	push @node_attributes, (fontname => 'arial') unless $config->{GENERATE_TREE_GRAPH_POSTSCRIPT} ;
	
	if($display_definition_package)
		{
		my $Pbsfile = $node->{__PBS_CONFIG}{PBSFILE}  || 'no pbsfile in pbsconfig';
		my $package = $node->{__PBS_CONFIG}{PACKAGE} || 'no package in pbs config';
		
		push @node_attributes, (cluster => $package . ':' . $Pbsfile) ;
		}
	
	push @node_attributes,
		(
		height   => 0.2,
		URL      => "$html_link",
		fontsize => 10,
		name     => $name,
		group    => $group,
		) ;
		
	# try to align nodes snugly
	if($root_rank >= 0)
		{
		push @node_attributes, (rank => $root_rank) ;
		
		if($config->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY})
			{
			$label .=  "\nBuild directory: " . $node->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
			}
		
		$root_rank = -1  ;
		}
	else
		{
		push @node_attributes, (rank => $rank) 
			unless $display_definition_package ; # rank stops the cluster generation
		}
		
	$rank++ ;
		
	if($fill_color ne 'none')
		{
		push @node_attributes, (style => 'filled') ;
		push @node_attributes, (fillcolor => $fill_color) ;
		}
			
	if($config->{IN_WARP})
		{
		unless (exists $node->{__TRIGGERED})
			{
			push @node_attributes, (style => 'filled') ;
			push @node_attributes, (fillcolor => 'darkolivegreen1') ;
			}
		
		push @node_attributes, (shape => 'house') ;
		}
	else
		{
		if(! defined $node->{__DEPENDED_AT} || $node->{__INSERTED_AT}{INSERTION_FILE} ne $node->{__DEPENDED_AT})
			{
			push @node_attributes, (shape => 'house') ;
			}
		}
		
	if(defined $node->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} || $name eq PBS_ROOT_NAME)
		{
		push @node_attributes, (shape => 'invhouse') ;
		}
	
	if($display_source_directory && defined $node->{__ALTERNATE_SOURCE_DIRECTORY})
		{
		push @node_attributes, (cluster => $node->{__ALTERNATE_SOURCE_DIRECTORY}) ;
		}
		
	if(exists $node->{__TRIGGER_INSERTED})
		{
		push @node_attributes, (shape => 'diamond') ;
		}
		
	if(exists $node->{__VIRTUAL})
		{
		push @node_attributes, (style => 'dotted') ;
		}
		
	if(exists $node->{__FORCED})
		{
		push @node_attributes, (style => 'bold') ;
		}
	
	use constant TRIGGERED_COLOR => 'red' ;
	use constant DEFAULT_COLOR   => 'black' ;
	
	if(keys %triggering_dependencies)
		{
		push @node_attributes, (color => TRIGGERED_COLOR) ;
		}
	else
		{
		push @node_attributes, (color => DEFAULT_COLOR) ;
		}
		
	if(exists $node->{__CYCLIC_FLAG})
		{
		push @node_attributes, 
			(
			style => 'filled',
			fillcolor => 'red',
			fontcolor => 'white',
			) ;
		}
		
	#------------------------------------------------------
	# config
	#------------------------------------------------------
	my $config_name ;
	
	if($config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG} && $name ne PBS_ROOT_NAME)
		{
		my $Pbsfile = $node->{__PBS_CONFIG}{PBSFILE}  || 'no pbsfile in pbsconfig';
		my $package = $node->{__PBS_CONFIG}{PACKAGE} || 'no package in pbs config';
		
		my $html_link = "config$free_config_index.html" ;
		$html_data{CONFIG}{"$free_config_index"}{FILE} = $html_link ;
		$html_data{CONFIG}{"$free_config_index"}{DATA} = $node->{__CONFIG} ;
		$html_data{CONFIG}{"$free_config_index"}{PACKAGE} = $package ;
		
		my $config_md5 ;
		
		use Digest::MD5 qw(md5_hex) ;
		
		{
		# remove private configuration variable from config before we compute md5
		local $Data::Dumper::Sortkeys ;
		my $DumpFilter = sub 
			{
			my $hash = shift ;
			
			my @keys_to_dump ;
			for(keys %$hash)

				{
				next if(/^__/) ;
				next if(/^TARGET_PATH/) ;
				push @keys_to_dump, $_ ;
				}
			
			@keys_to_dump = sort @keys_to_dump ;
			
			return(\@keys_to_dump) ;
			} ;
			
		$Data::Dumper::Sortkeys = $DumpFilter ;
		
		#PrintInfo(Data::Dumper->Dump([$node->{__CONFIG}], ['config']));
		$config_md5 = md5_hex(Data::Dumper->Dump([$node->{__CONFIG}], ['config'])) ;
		}
		
		$config_name = $config_md5 . ($package || '') ;
		my $config_node ;
		
		if(exists $inserted_graph_nodes->{$config_name})
			{
			#~ $config_node = $inserted_graph_nodes->{$config_md5} ;
			}
		else
			{
			my $config_label = "#$free_config_index" ;
			
			if(exists $inserted_configs->{$config_md5})
				{
				$config_label .= " (== $inserted_configs->{$config_md5})" ;
				}
			else
				{
				$inserted_configs->{$config_md5} = $free_config_index ;
				}
				
			$config_label .= "\n$Pbsfile" unless ($display_definition_package) ;
			
			my @config_node_attributes =
					(
					height => 0.2,
					fontsize => 10,
					group => $group,
					shape => 'octagon',
					#style => 'bold',
					color => 'lightsalmon2',
					name  => $config_name,
					label => $config_label,
					#~ "config #$free_config_index",
					URL   => $html_link,
					) ;
					
			if(exists $node->{__CONFIG}{__LOCKED} && $node->{__CONFIG}{__LOCKED} == 1)
				{
				push @config_node_attributes, (color => 'red') ;
				}
				
			if($display_definition_package)
				{
				my $Pbsfile = $node->{__PBS_CONFIG}{PBSFILE} ;
				my $package = $node->{__PBS_CONFIG}{PACKAGE} ;
		
				push @config_node_attributes, (cluster => $package . ':' . $Pbsfile) ;
				}
				
			unless($config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE})
				{
				push @config_node_attributes, (rank => 1) ;
				}
				
			$config_node = $graph->add_node(@config_node_attributes) ;
					
			#~ $inserted_graph_nodes->{$config_name} = $graph_node ;
			$inserted_graph_nodes->{$config_name} = $free_config_index ;
			$free_config_index++ ;
			}
			
		unless($config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE})
			{
			$label = "[" . $inserted_graph_nodes->{$config_name} . "] " . $label ;
			}
		}
	#------------------------------------------------------
	
	#------------------------------------------------------
	#PBS config
	#------------------------------------------------------
	my $pbs_config_name ;
	
	if($config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG} && $name ne PBS_ROOT_NAME)
		{
		my $html_link = "pbs_config$free_pbs_config_index.html" ;
		
		$html_data{PBS_CONFIG}{"$free_pbs_config_index"}{FILE} = $html_link ;
		$html_data{PBS_CONFIG}{"$free_pbs_config_index"}{DATA} = $node->{__PBS_CONFIG} ;
		
		my $Pbsfile = $node->{__PBS_CONFIG}{PBSFILE} ;
		my $package = $node->{__PBS_CONFIG}{PACKAGE} ;
		my $pbs_config_md5 ;
		
		use Digest::MD5 qw(md5_hex) ;
		
		{
		my $MD5 = sub
				{
				my ($tree, $level) = @_ ;
				
				if('HASH' eq ref $tree && $level == 0)
					{
					return
						(
						'HASH',
						undef,
						qw(
							BUILD_DIRECTORY 
							SOURCE_DIRECTORIES
							COMMAND_LINE_DEFINITIONS
							CONFIG_NAMESPACES
							LIB_PATH
							USER_OPTIONS
							RULE_NAMESPACES
							NO_EXTERNAL_LINK
							),
						) ;
					}
				
				return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
				} ;
				
		#~ PrintInfo(DumpTree($node->{__PBS_CONFIG}, 'PBS config:', FILTER => $MD5, USE_ASCII => 1)) ;
		$pbs_config_md5 = md5_hex(DumpTree($node->{__PBS_CONFIG}, 'pbs_config', FILTER => $MD5, USE_ASCII => 1)) ;
		}
		
		$pbs_config_name = 'pbs_config' . $pbs_config_md5 . $package ;
		my $pbs_config_node ;
		
		if(exists $inserted_graph_nodes->{$pbs_config_name})
			{
			#~ $pbs_config_node = $inserted_graph_nodes->{$pbs_config_md5} ;
			}
		else
			{
			$inserted_pbs_configs->{$package}{$pbs_config_md5} = $free_pbs_config_index ;
			
			my $pbs_config_label = "#$free_pbs_config_index" ;
			
			# show if this nodes pbs config  is equal to its parent config
			if(defined $node->{__PBS_CONFIG}{PARENT_PACKAGE})
				{
				my $parent_package = $node->{__PBS_CONFIG}{PARENT_PACKAGE} ;
				if(exists $inserted_pbs_configs->{$parent_package}{$pbs_config_md5})
					{
					$pbs_config_label .= " (== $inserted_pbs_configs->{$parent_package}{$pbs_config_md5})" ;
					}
				}
				
			$pbs_config_label .= "\n$Pbsfile" unless ($display_definition_package) ;
			
			my @pbs_config_node_attributes =
					(
					height => 0.2,
					fontsize => 10,
					group => $group,
					shape => 'doubleoctagon',
					#~ style => 'bold',
					name  => $pbs_config_name,
					label => $pbs_config_label,
					#~ "Pbs config, # $free_pbs_config_index"
					color => 'dodgerblue1',
					URL => $html_link,
					tooltip  => "Pbs config",
					) ;
					
				
			if($display_definition_package)
				{
				my $Pbsfile = $node->{__PBS_CONFIG}{PBSFILE} ;
				my $package = $node->{__PBS_CONFIG}{PACKAGE} ;
				
				push @pbs_config_node_attributes, (cluster => $package . ':' . $Pbsfile) ;
				}
				
			unless($config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE})
				{
				push @pbs_config_node_attributes, (rank => 0) ;
				}
				
			$pbs_config_node = $graph->add_node(@pbs_config_node_attributes) ;
					
			$inserted_graph_nodes->{$pbs_config_name} = $free_pbs_config_index ;
			$free_pbs_config_index++ ;
			}
			
		unless($config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE})
			{
			$label = "[pbs:" . $inserted_graph_nodes->{$pbs_config_name} . "] " . $label ;
			}
		}
	#------------------------------------------------------
	
	my $regex_node = '' ;

	for my $cluster_regex (@{$config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX}})
		{
		if($name =~ /$cluster_regex/)
			{
			$regex_node = $cluster_regex ;
			last ;
			}
		}

	if($regex_node ne '')
		{
		#PrintDebug "clustering $label in $regex_node\n" ;
		if (exists $inserted_graph_nodes->{$regex_node})
			{
			$graph_node = $inserted_graph_nodes->{$name} = $inserted_graph_nodes->{$regex_node} ;
			}
		else
			{
			push @node_attributes, 
				(
				shape => 'egg',
				fillcolor =>  $cluster_regex_colors[$cluster_regex_color_index++ % $cluster_regex_color_size]
				) ;
			
			$graph_node = $graph->add_node(label => $regex_node,  @node_attributes) ;

			$inserted_graph_nodes->{$name} = $inserted_graph_nodes->{$regex_node} = $graph_node ;
			}
		}
	else
		{
		if($clustering_node_name eq '')
			{
			for my $cluster_node_regex (@{$config->{GENERATE_TREE_GRAPH_CLUSTER_NODE}})
				{
				if($name =~ /^$cluster_node_regex$/)
					{
					$clustering_node_name = $name ;
					push @node_attributes, (peripheries => 2) ;
					last ;
					}
				}
				
			#PrintDebug DumpTree [@node_attributes, label => $label ] ;
			$graph_node = $graph->add_node(label => $label,  @node_attributes) ;
			$inserted_graph_nodes->{$name} = $graph_node ;
			}
		else
			{
			$inserted_graph_nodes->{$name} = $clustering_node_name  ;
			$graph_node = $clustering_node_name  ;
			}
		}

	#------------------------------------------------------
	# More config
	#------------------------------------------------------
	if
		(
		   $config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE} 
		&& $name ne PBS_ROOT_NAME
		)
		{
		$graph->add_edge
			({
			arrowsize => 0.65,
			style => 'dotted',
			color => 'orange',
			from => $graph_node,
			to => $config_name,
			URL => "config $config_name",
			tooltip  => "config edge",
			});
		}
	if
		(
		   $config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE} 
		&& $name ne PBS_ROOT_NAME
		)
		{
		$graph->add_edge
			({
			arrowsize => 0.65,
			style => 'dotted',
			color => 'dodgerblue1',
			from => $graph_node,
			to => $pbs_config_name,
			URL => "Pbs config $pbs_config_name",
			tooltip  => "Pbs config edge",
			});
		}
	#------------------------------------------------------
		
	if(exists $node->{__CYCLIC_ROOT})
		{
		my $Pbsfile = $node->{__PBS_CONFIG}{PBSFILE} ;
		my $package = $node->{__PBS_CONFIG}{PACKAGE} ;
		my @cycle_root_information_attributes =
			(
			height => 0.2,
			#~ fontname => 'arial',
			fontsize => 10,
			name => 'Cycle root',
			shape => 'rectangle',
			URL => "explaination of cyclic root",
			tooltip  => "cyclic root",
			) ;
			
		push @cycle_root_information_attributes, (cluster => $package . ':' . $Pbsfile)  if$display_definition_package ;
		
		my $information_node = $graph->add_node(@cycle_root_information_attributes) ;
						
		unless (exists $inserted_edges->{"cycle_root_information=>$graph_node"})
			{
			$graph->add_edge
				({
				from     => $information_node,
				to       => $graph_node,
				color    => 'black',
				arrowhead => 'none',
				}) ;
				
			$inserted_edges->{"cycle_root_information=>$graph_node"}++ ;
			}
		}
		
	if(keys %$node)
		{
		for my $key_name ( keys(%$node) ) 
			{
			next if($key_name =~ /^__/) ;
			
			my $graph_child_node ;
			
			if(exists $inserted_graph_nodes->{$key_name})
				{
				$graph_child_node = $inserted_graph_nodes->{$key_name} ;
				}
			else
				{
				$graph_child_node = GenerateTreeGraph
							(
							$graph,
							$node->{$key_name}, $key_name,
							$clustering_node_name,
							$config,
							$inserted_graph_nodes, $inserted_edges, $inserted_configs, $inserted_pbs_configs,
							$fill_color,
							-1,
							$rank,
							$group,
							) ;
											
				#PrintDebug "$label ($regex_node) child: $key_name -> $graph_child_node\n" ;
				if(defined $graph_child_node)
					{
					$inserted_graph_nodes->{$key_name} =  $graph_child_node ;
					}
				}
				
			if(defined $graph_child_node)
				{
				my $edge_color = DEFAULT_COLOR ;
				my $edge_style = '' ;
				
				if(exists $triggering_dependencies{$key_name})				
					{
					$edge_color = TRIGGERED_COLOR  ;
					}
				else
					{
					$edge_style = 'dashed' if $config->{GENERATE_TREE_GRAPH_PRINTER} ;
					}
						
				# diplay links to node with a circle
				my $arrow_tail = 'odot' ;
				
				if(defined $node->{$key_name}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA})
					{
					if(exists $node->{$key_name}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
						&&   $node->{$key_name}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTING_NODE}
eq $name) 
						{
						$arrow_tail = 'none' ;
						}
					}
				else
					{
					$arrow_tail = 'none' if($node->{$key_name}{__INSERTED_AT}{INSERTING_NODE} eq $name) ;
					}
					
				if(exists $node->{__TRIGGER_INSERTED})
					{
					if($node->{__TRIGGER_INSERTED} eq $key_name)
						{
						$arrow_tail = 'empty' ;
						$inserting_node_link++ ;
						}
					}
					
				$arrow_tail = 'none' if(PBS_ROOT_NAME eq $name) ;
				
				unless (exists $inserted_edges->{"$graph_node=>$graph_child_node"})
					{
					unless($inserted_graph_nodes->{$graph_child_node} eq $inserted_graph_nodes->{$graph_node})
						{
						$graph->add_edge
							({
							color     => $edge_color,
							from      => $graph_node,
							to        => $graph_child_node,
							arrowtail => $arrow_tail,
							#~ fontname => 'arial',
							#~ fontsize => 8,
							#~ label => '',
							URL => "edge",
							tooltip  => "edge",
							style => $edge_style,
							});
						}
						
					$inserted_edges->{"$graph_node=>$graph_child_node"}++ ;
					}
				}
			}
		}
		
	if(exists $node->{__TRIGGER_INSERTED} && $inserting_node_link == 0)
		{
		push @post_edge_insertion,
				{
				from       => $node->{__TRIGGER_INSERTED},
				to         => $name,
				arrowhead  => 'empty',
				color      => 'blue',
				style      => 'dotted',
				URL        => "trigger edge",
				tooltip    => "trigger edge",
				} ;
		}
		
	unless (exists $node->{__VIRTUAL} || exists $inserted_edges->{"$graph_node=>$graph_node"})
		{
		if(exists $triggering_dependencies{__SELF})
			{
			$graph->add_edge
				({
				arrowsize => 0.65,
				color     => 'gray',
				from      => $graph_node,
				to        => $graph_node,
				#~ URL       => "self",
				#~ name      => "self",
				});
				
			$inserted_edges->{"$graph_node=>$graph_node"}++ ;
			}
			
		if(exists $triggering_dependencies{__DIGEST_TRIGGERED})
			{
			$graph->add_edge
				({
				arrowsize => 0.65,
				color     => 'blue',
				from      => $graph_node,
				to        => $graph_node,
				#~ URL       => "digest",
				#~ name      => "digest",
				#~ fontname => 'arial',
				#~ fontsize => 8,
				#~ label => "Digest",
				});
				
			$inserted_edges->{"$graph_node=>$graph_node"}++ ;
			}
		}
	}
else
	{
	PrintError("Graph: unexpected node '$name' of type '$node_type' in tree while generating graph.\n") ;
	die ;
	}
	
return($inserted_graph_nodes->{$graph_node}) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Graph  -

=head1 DESCRIPTION

I<GenerateTreeGraphFile> generates a graphical representation of the dependency try just before a build starts.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

$> pbs -h | grep gtg

=cut
