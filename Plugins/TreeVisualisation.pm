

=head1 Plugin TreeVisualisation.pm

This plugin handles the following PBS defined switches:

=over 2

=item  --tt

=item --ttno

=item --ttcl

=back

And add the following functionality:

=over 2

=item --tnto, Display only triggering nodes

=item --tnonh, removes header files from the tree dump

=item --tnonr, removes files matching the passed regex

=item --tww, set the wrap width

=back

=cut

use PBS::PBSConfigSwitches ;
use PBS::Output ;
use PBS::Digest ;
use PBS::Information ;
use Data::TreeDumper ;
use Data::TreeDumper::Utils ;
use List::Util qw(any) ;

#-------------------------------------------------------------------------------

PBS::PBSConfigSwitches::RegisterFlagsAndHelp
	(
	'tnonh',
	'NO_HEADER_FILES_DISPLAY',
	"Do not display header files in the tree dump.",
	'',
	
	'tnonr=s',
	'@DISPLAY_FILTER_REGEXES' ,
	"Removes files matching the passed regex from the tree dump.",
	'',

	'tww=i',
	'WRAP_WIDTH' ,
	"Set the wrap width.",
	'',

	'ttcl',
	'TREE_COLOR_LEVELS' ,
	"Color the tree glyphs per level.",
	'',
	) ;
	
sub PostDependAndCheck
{
my ($pbs_config, $dependency_tree, $inserted_nodes) = @_ ;

#------------------
#  DTD filters,
#------------------
my $FilterDump;

if(defined $pbs_config->{DEBUG_DISPLAY_TREE_NAME_ONLY})
	{
	$FilterDump = 
		sub #no private data
		{
		my ($tree) = @_ ;
		
		if('HASH' eq ref $tree)
			{
			my @keys_to_dump ;
			
			for(keys %$tree)
				{
				if(/^__/)
					{
					if
					(
					   (/^__BUILD_NAME$/  && defined $pbs_config->{DEBUG_DISPLAY_TREE_NAME_BUILD})
					|| (/^__TRIGGERED$/   && defined $pbs_config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON})
					|| (/^__DEPENDED_AT$/ && defined $pbs_config->{DEBUG_DISPLAY_TREE_DEPENDED_AT})
					|| (/^__INSERTED_AT$/ && defined $pbs_config->{DEBUG_DISPLAY_TREE_INSERTED_AT})
					#~ || /^__VIRTUAL/
					)
						{
						# display these
						}
					else
						{
						next ;
						}
					}
					
				# handle --tnonh
				if(/\.h$/ && $pbs_config->{NO_HEADER_FILES_DISPLAY})
					{
					next ;
					}
				
				if('HASH' eq ref $tree->{$_} && exists $tree->{$_}{__WARP_NODE} && ! exists $tree->{$_}{__LINKED} )
					{
					# only display the __WARP_NODEs that have been linked to the new node
					# generated during warp
					next ;
					}
					
				# handle --tnonr
				my $excluded ;
				for my $regex (@{$pbs_config->{DISPLAY_FILTER_REGEXES}})
					{
					if($_ =~ $regex)
						{
						$excluded++ ;
						last ;
						}
					}
				next if $excluded ;
				
				
				# handle --tnto
				next if $pbs_config->{DISPLAY_ONLY_TRIGGERING_NODES} and 'HASH' eq ref $tree->{$_} and ! exists $tree->{$_}{__TRIGGERED} ;
				
				push @keys_to_dump, $_ ;
				}
			
			my @keys_sorted = Data::TreeDumper::Utils::first_nsort_last( AT_START => [qr/^_/], KEYS => \@keys_to_dump ) ;
			for (@keys_sorted)
				{
				if(! /^__/ && 'HASH' eq ref $tree->{$_})
					{
					my $is_source = NodeIsSource($tree->{$_}) ;
					
					my $parallel_depend   = exists $inserted_nodes->{$_}{__PARALLEL_DEPEND} ;
					my $parallel_depended = exists $inserted_nodes->{$_}{__PARALLEL_NODE} ;
					my $parallel_node     = $parallel_depend || $parallel_depended ;
					
					my $rules = ! $parallel_node && ! @{$tree->{$_}{__MATCHING_RULES} // []} && ! $is_source
							? _ERROR_(' ∅ ')
							: '' ;
					
					my $tag ;
					
					$tag  = "[V] " . ($tag // $_) if(exists $tree->{$_}{__VIRTUAL}) ;
					$tag .= "* " . ($tag // $_)   if(exists $tree->{$_}{__TRIGGERED}) ;
					
					$tag  = $is_source ? _WARNING_($tag // $_) : _INFO3_($tag // $_) ;
					
					$tag .= _WARNING_(' ⋂') if $tree->{$_}{__INSERTED_AND_DEPENDED_DIFFERENT_PACKAGE} && ! $tree->{$_}{__MATCHED_SUBPBS};
					
					$tag .=  exists $inserted_nodes->{$_}{__WARP_NODE} ? _INFO2_ ('ᶜ') :  $rules ;
					
					$tag .= $parallel_depend
							? _WARNING2_ ('∥ ')
							: $parallel_depended
								? _INFO2_ ('∥ ')
								: '' ;
					
 					$tag .= GetColor('info2')  ;
					
					
					$_ = [$_, $tag] if defined $tag ;
					}
				}
			
			return ( 'HASH', undef, @keys_sorted ) ;
			}
			
		return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
		} ;
	}
else
	{
	if(defined $pbs_config->{DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA})
		{
		$FilterDump = undef ;
		}
	else
		{
		$FilterDump = sub
			{
			# try to reduce tree dump to a minimum
			# undefined entries or entries pointing to empty structure are not displayed
			
			my ($tree, $level, $path, $nodes_to_display, $setup, $filter_argument) = @_ ;
			
			if('HASH' eq ref $tree)
				{
				my @keys_to_dump ;
				
				for (keys %$tree)
					{
					if(/^__/)
						{
						if(defined $pbs_config->{DISPLAY_TREE_FILTER})
							{
							next unless exists $pbs_config->{DISPLAY_TREE_FILTER}{$_}
							}
						elsif(/^__PARENTS$/)
							{
							next ;
							}
							
						push @keys_to_dump, $_ ;
						}
					else
						{
						# handle -tnd
						if($pbs_config->{DEBUG_DISPLAY_TREE_NO_DEPENDENCIES})
							{
							my $last_element = $setup->{__PATH_ELEMENTS}[-1] ;
							my $name = $last_element->[1] || '' ;
							
							if($name !~ /__/ && /^[^__]/ )
								{
								#~ PrintDebug "skipping $_\n" ;
								next ;
								}
							}
							
						# handle --tnto
						next if $pbs_config->{DISPLAY_ONLY_TRIGGERING_NODES} and 'HASH' eq ref $tree->{$_} and ! exists $tree->{$_}{__TRIGGERED} ;
						
						# remove empty entries
						for my $reference_type (ref $tree->{$_})
							{
							'' eq $reference_type && do
								{
								push @keys_to_dump, $_ if defined $tree->{$_} ;
								last ;
								} ;
								
							'HASH' eq $reference_type && do
								{
								push @keys_to_dump, $_ unless 0 == keys %{$tree->{$_}} ;
								last ;
								} ;
								
							'ARRAY' eq $reference_type && do
								{
								push @keys_to_dump, $_ unless 0 == @{$tree->{$_}} ;
								last ;
								} ;
								
							push @keys_to_dump, $_ ;
							}
						}
					}
					
				return('HASH', undef, sort @keys_to_dump) ;
				}
				
			return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
			} ;
		}
	}
# end DTD filters.

if(defined $pbs_config->{DISPLAY_TEXT_TREE_USE_DHTML})
	{
	PrintInfo "Tree Visualisation: Generating DHTML dump of the dependency tree in '$pbs_config->{DISPLAY_TEXT_TREE_USE_DHTML}' ...\n" ;
	
	open DHTML, '>', $pbs_config->{DISPLAY_TEXT_TREE_USE_DHTML} 
		or die "can't open dhtml file '$pbs_config->{DISPLAY_TEXT_TREE_USE_DHTML}': @!\n" ;
		
		
	print DHTML <<EOT;
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html 
     PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
     
<html>
EOT

	my $style = '' ;

	my $body = DumpTree
			(
			$dependency_tree,
			"Tree for $dependency_tree->{__NAME}:",
			DISPLAY_ROOT_ADDRESS => 1,
			#DISPLAY_PERL_SIZE => 1,
			FILTER =>$FilterDump,
			
			RENDERER => 
				{
				NAME => 'DHTML',
				STYLE => \$style,
				BUTTON =>
					{
					COLLAPSE_EXPAND => 1,
					SEARCH => 1,
					},
				},
			) ;
			
	print DHTML <<EOT;
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html 
     PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"
>
     
<html>

<!--
Automatically generated by Data::TreeDumper::DHTML
-->

<head>
<title>pbs</title>

<style type='text/css' >
	a{text-decoration: none;}
</style>

$style
</head>
<body>
$body
</body>
</html>
EOT

	close(DHTML) ;
	}

my @extra_options ;

# colorize tree in blocks
use Term::ANSIColor qw(:constants) ;
my @colors = map { GetColor($_) } qw ( ttcl1 ttcl2 ttcl3 ttcl4 ) ;
my @one_color = map { GetColor($_) } qw ( ttcl1 ) ;

push @extra_options, 'COLOR_LEVELS' => $pbs_config->{TREE_COLOR_LEVELS} ? [\@colors, ''] : [\@one_color, ''] ;
push @extra_options, 'WRAP_WIDTH' => $pbs_config->{WRAP_WIDTH} if $pbs_config->{WRAP_WIDTH} ;
push @extra_options, 'MAX_DEPTH' => $pbs_config->{MAX_DEPTH} if $pbs_config->{MAX_DEPTH} ;

my ($matching_nodes, @trees)  = (0) ;

if (@{$pbs_config->{DISPLAY_TEXT_TREE_REGEX}})
	{
	for my $node_name (sort keys %$inserted_nodes)
		{
		last if $matching_nodes == $pbs_config->{DISPLAY_TEXT_TREE_MAX_MATCH} ;

		if(any { $node_name =~ $_ } @{$pbs_config->{DISPLAY_TEXT_TREE_REGEX}})
			{
			push @trees, $node_name ;
			$matching_nodes++;
			last ;
			}
		}

	if(@trees == 0)
		{ 
		PrintWarning("Tree visualization: No node matched the regex you gave.\n") ;
		}
	if(@trees == 1)
		{
		my ($node, $node_name) ;

		if ($dependency_tree->{__INSERTED_AT}{INSERTING_NODE} eq 'Root load')
			{
			($node_name) = grep {!/^__/} keys %$dependency_tree ;
			$node = $dependency_tree->{$node_name} ;
			}
		else
			{
			($node, $node_name) = ($dependency_tree, $dependency_tree->{__NAME}) ;
			}

		PrintInfo DumpTree
				(
				$node,
				_INFO3_($node_name),
				FILTER => $FilterDump,
				INDENTATION => $PBS::Output::indentation,
				@extra_options
				)
		}
	else
		{
		my %trees = ( map { ($_ => $inserted_nodes->{$_}) } @trees ) ;

		PrintInfo DumpTree
				(
				\%trees,
				"dependency graphs",
				FILTER => $FilterDump,
				INDENTATION => $PBS::Output::indentation,
				@extra_options
				) ;
		}
	}
else
	{
	my ($node, $node_name) ;

	if ($dependency_tree->{__INSERTED_AT}{INSERTING_NODE} eq 'Root load')
		{
		($node_name) = grep {!/^__/} keys %$dependency_tree ;
		$node = $dependency_tree->{$node_name} ;
		}
	else
		{
		($node, $node_name) = ($dependency_tree, $dependency_tree->{__NAME}) ;
		}

	my $root = $node ;
	my $root_name = $node_name ;

	my @roots  = {$root_name => $root} ;

	for my $node_name (keys %$inserted_nodes)
		{
		if(exists $inserted_nodes->{$node_name}{__TRIGGER_ROOT})
			{
			$root_name = 'roots' ;

			push @roots, 
				{
				"$node_name" . _INFO2_ (", triggered by: '$inserted_nodes->{$node_name}{__TRIGGER_INSERTED}'")
					 => $inserted_nodes->{$node_name}
				} ;
			}
		}

	PrintInfo DumpTree
			(
			(@roots == 1 ? $root : \@roots),
			$root_name,
			FILTER => $FilterDump,
			INDENTATION => $PBS::Output::indentation,
			@extra_options
			)
		if $pbs_config->{DEBUG_DISPLAY_TEXT_TREE} ;
	}
	
print Term::ANSIColor::color('reset');

}

#-------------------------------------------------------------------------------

1 ;

