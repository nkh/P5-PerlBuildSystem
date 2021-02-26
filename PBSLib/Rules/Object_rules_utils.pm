
use PBS::Output ;
use List::Util qw( any) ;

#-------------------------------------------------------------------------------

sub exists_on_disk
{
my
	(
	$dependent_to_check,
	$config,
	$tree,
	$inserted_nodes,
	$rule_definition, # for introspection
	) = @_ ;

my $build_directory    = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ;

my $missing = 0 ;
my $message ;

for my $source ( grep { $_ !~ /^__/ } keys %$tree )
	{
	my ($build_name) = PBS::Check::LocateSource($source, $build_directory, $source_directories, $tree->{__PBS_CONFIG}{DISPLAY_SEARCH_INFO}) ;

	unless(-e $build_name)
		{
		$missing++ ;
		
		$message //= $tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX} 
				&& any { $dependent_to_check =~ $_ } @{$tree->{__PBS_CONFIG}{DISPLAY_DEPENDENCIES_REGEX}} ;
		
		$message = 0 if any { $dependent_to_check =~ $_ } @{$tree->{__PBS_CONFIG}{DISPLAY_DEPENDENCIES_REGEX_NOT}} ;
		
		PrintInfo 
			$PBS::Output::indentation x 2
			. "'exists_on_disk: rule: $rule_definition->{NAME},"  # "@ $rule_definition->{FILE}:$rule_definition->{LINE}\n" 
			. " $source not found\n"
				if $message ;
		}
	}

die ERROR("PBS: exists on disk failed ($missing)") . "\n" if $missing ;

1 ;
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
        $rule_definition, # for introspection
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
		. "warning: no dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n" 
		. $indentation . "rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
		. $indentation . "(try pbs options: -dpl -ddl --display_dependency_regex  --display_search_info)\n" ; 	

	}

return 0 ;
}

#-------------------------------------------------------------------------------

1 ;

