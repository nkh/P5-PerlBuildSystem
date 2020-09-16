
use PBS::Output ;

#-------------------------------------------------------------------------------

sub exists_on_disk
{
my
	(
	$dependent_to_check,
	$config,
	$tree,
	$inserted_nodes,
	$dependencies,         # rule local
	$builder_override,     # rule local
	$rule_definition,      # for introspection
	) = @_ ;

my $build_directory    = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ;

my ($triggered, @my_dependencies) ;

shift @$dependencies ; # previous trigger state

for my $source (@$dependencies)
	{
	my ($build_name) = PBS::Check::LocateSource($source, $build_directory, $source_directories, $tree->{__PBS_CONFIG}{DISPLAY_SEARCH_INFO}) ;

	if( -e $build_name)
		{
		push @my_dependencies, $source ;
		$triggered = 1 ;
		}
	else
		{
		my $node_name_matches_ddrr = 0 ;
		if ($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
			{
			for my $regex (@{$tree->{__PBS_CONFIG}{DISPLAY_DEPENDENCIES_REGEX}})
				{
				if($dependent_to_check =~ /$regex/)
					{
					$node_name_matches_ddrr = 1 ;
					last ;
					}
				}
			}

		if($node_name_matches_ddrr)
			{
			PrintInfo 
				$PBS::Output::indentation x 2
				. "'exists_on_disk: rule: $rule_definition->{NAME},"  # "@ $rule_definition->{FILE}:$rule_definition->{LINE}\n" 
				. " no match\n" ;
			}

		# all listed dependencies must exist
		($triggered, @my_dependencies) = (0) ;
		last ;
		}
	}

return([$triggered, @my_dependencies], $builder_override) ;
}

#-------------------------------------------------------------------------------

# dynamic depender that checks that a node only has one dependency
# we use this, for example, in the rule set that automatically finds
# the dependency for object files from different possible language implementations
sub OnlyOneDependency
{
my
        (
        $dependent_to_check,
        $config,
        $tree,
        $inserted_nodes,
        $dependencies,         # rule local
        $builder_override,     # rule local
        $rule_definition,      # for introspection
        ) = @_ ;


my @dependencies = grep {! /^__/ } keys %$tree ;
my $indentation = $PBS::Output::indentation ;

if (@dependencies > 1)
	{
	PrintInfo $indentation . "'only_one_dependency': rule: $rule_definition->{NAME}\n" ;

	PrintError "Depend: error: multiple dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n"
			. $indentation . "rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
			. $indentation . "(try pbs options: -dpl -ddl  --display_dependency_regex --display_search_info)\n" ; 	

	for (@dependencies)
		{
		my $rule = $tree->{__MATCHING_RULES}[0]{RULE}{DEFINITIONS}[$tree->{$_}{RULE_INDEX}] ;

		PrintError "\t$_ rule: " . $tree->{$_}{RULE_INDEX} . ' @ ' . $rule->{NAME} . ':' . $rule->{FILE} . ':' . $rule->{LINE} . "\n" ;
		}

	die "\n";
	}
elsif (0 == @dependencies)
	{
	PrintWarning 
		$indentation . "'only_one_dependency': rule: $rule_definition->{NAME}\n"
		. "Warning: no dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n" 
		. $indentation . "rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
		. $indentation . "(try pbs options: -dpl -ddl --display_dependency_regex  --display_search_info)\n" ; 	

	}

return [0] ;
}

#-------------------------------------------------------------------------------

1 ;

