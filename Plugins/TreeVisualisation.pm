

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
use PBS::Information ;
use Data::TreeDumper ;
use Data::TreeDumper::Utils ;

#-------------------------------------------------------------------------------

my $no_header_files_display ;
my @display_filter_regexes ;
my $tree_color_levels ;
my $wrap_width ;
my $tnto ;

PBS::PBSConfigSwitches::RegisterFlagsAndHelp
	(
	'tnto',
	\$tnto,
	"Display only triggering nodes.",
	'',
	
	'tnonh',
	\$no_header_files_display,
	"Do not display header files in the tree dump.",
	'',
	
	'tnonr=s',
	\@display_filter_regexes ,
	"Removes files matching the passed regex from the tree dump.",
	'',

	'tww=i',
	\$wrap_width ,
	"Set the wrap width.",
	'',

	'ttcl',
	\$tree_color_levels ,
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
				if(/\.h$/ && $no_header_files_display)
					{
					next ;
					}
					
				# handle --tnonr
				my $excluded ;
				for my $regex (@display_filter_regexes)
					{
					if($_ =~ $regex)
						{
						$excluded++ ;
						last ;
						}
					}
				next if $excluded ;
				
				
				# handle --tnto
				next if $tnto and 'HASH' eq ref $tree->{$_} and ! exists $tree->{$_}{__TRIGGERED} ;
				
				push @keys_to_dump, $_ ;
				}
			
			my @keys_sorted = Data::TreeDumper::Utils::first_nsort_last( AT_START => [qr/^_/], KEYS => \@keys_to_dump ) ;
			for (@keys_sorted)
				{
				if(! /^__/)
					{
					if('HASH' eq ref $tree->{$_} && exists $tree->{$_}{__TRIGGERED})
						{
						$_ = [$_, "* $_"] ;
						}
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
						next if $tnto and 'HASH' eq ref $tree->{$_} and ! exists $tree->{$_}{__TRIGGERED} ;
						
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
	PrintInfo "Generating DHTML dump of the dependency tree in '$pbs_config->{DISPLAY_TEXT_TREE_USE_DHTML}' ...\n" ;
	
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
my @colors = map { Term::ANSIColor::color($_) }	( 'green', 'yellow', 'cyan') ;
push @extra_options, 'COLOR_LEVELS' => [\@colors, ''] if $tree_color_levels ;

# terminal width
push @extra_options, 'WRAP_WIDTH' => $wrap_width if $wrap_width ;

push @extra_options, 'MAX_DEPTH' => $pbs_config->{MAX_DEPTH} if $pbs_config->{MAX_DEPTH} ;

my @trees ;

my $matching_nodes = 0 ;

if (@{$pbs_config->{DISPLAY_TEXT_TREE_REGEX}})
	{
	for my $node_name (sort keys %$inserted_nodes)
		{
		last if $matching_nodes == $pbs_config->{DISPLAY_TEXT_TREE_MAX_MATCH} ;

		for my $regex (@{$pbs_config->{DISPLAY_TEXT_TREE_REGEX}})
			{
			if($node_name =~ $regex)
				{
				push @trees, $node_name ;
				$matching_nodes++;
				last ;
				}
			}
		}

	if(@trees == 0)
		{ 
		PrintWarning("Tree visualization: No node matched the regex you gave.\n") ;
		}
	if(@trees == 1)
		{
		PrintInfo DumpTree($dependency_tree, "Dependen: graph", FILTER => $FilterDump, @extra_options) ;
		PrintInfo "Depend:\n" 
				. DumpTree
					(
					$dependency_tree,
					"dependency graph",
					FILTER => $FilterDump,
					INDENTATION => $PBS::Output::indentation,
					@extra_options
					) ;
		}
	else
		{
		my %trees = ( map { ($_ => $inserted_nodes->{$_}) } @trees ) ;

		PrintInfo "Depend:\n" 
				. DumpTree
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
	PrintInfo "Depend:\n" 
			. DumpTree
				(
				$dependency_tree,
				"dependency graph",
				FILTER => $FilterDump,
				INDENTATION => $PBS::Output::indentation,
				@extra_options
				)
		if $pbs_config->{DEBUG_DISPLAY_TEXT_TREE} ;
	}
	
print Term::ANSIColor::color('reset');

# find the inserted roots
# todo: make this an option
#for my $node_name (keys %$inserted_nodes)
#	{
#	if(exists $inserted_nodes->{$node_name}{__TRIGGER_INSERTED})
#		{
#		push @trees, $node_name + title: "$node_name, triggered by '$inserted_nodes->{$node_name}{__TRIGGER_INSERTED}')"
#		}
#	}
}

#-------------------------------------------------------------------------------

1 ;

