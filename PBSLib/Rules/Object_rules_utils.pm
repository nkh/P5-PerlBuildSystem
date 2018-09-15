

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
	my ($build_name, $is_alternative_source, $other_source_index) 
		= PBS::Check::LocateSource($source, $build_directory, $source_directories, $tree->{__PBS_CONFIG}{DISPLAY_SEARCH_INFO}) ;

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
			print WARNING 
				$PBS::Output::indentation
				. "Additional 'exists_on_disk' for rule: $rule_definition->{NAME}\n"
					 # "@ $rule_definition->{FILE}:$rule_definition->{LINE}\n" 
				. $PBS::Output::indentation x 2
				. "dependency '$source' not found on disk as '$build_name'.\n" ;
			}

		# all listed dependencies in the must exist
		@my_dependencies = () ;
		$triggered = 0 ;
		last ;
		}
	}

unshift @my_dependencies, $triggered ;

return(\@my_dependencies, $builder_override) ;
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

if($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
	{
	}

if (@dependencies > 1)
	{
	print WARNING 
		$PBS::Output::indentation
		. "Additional 'only_one_dependency' for rule: $rule_definition->{NAME}\n" ;

	PrintError "Error: multiple dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n"
			. $PBS::Output::indentation . "Rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
			. $PBS::Output::indentation . "(try pbs options: -dpl -ddl  --display_dependency_regex --display_search_info)\n" ; 	

	for (@dependencies)
		{
		my $rule = $tree->{__MATCHING_RULES}[0]{RULE}{DEFINITIONS}[$tree->{$_}{RULE_INDEX}] ;

		PrintError "\t$_ rule " . $tree->{$_}{RULE_INDEX} . ' @ ' . $rule->{NAME} . ':' . $rule->{FILE} . ':' . $rule->{LINE} . "\n" ;
		}
	die "\n";
	}
elsif (0 == @dependencies)
	{
	PrintWarning 
		$PBS::Output::indentation . "Additional 'only_one_dependency' for rule: $rule_definition->{NAME}\n"
		. "Warning: no dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n" 
		. $PBS::Output::indentation . "Rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
		. $PBS::Output::indentation . "(try pbs options: -dpl -ddl --display_dependency_regex  --display_search_info)\n" ; 	

	}

return [0] ;
}

#-------------------------------------------------------------------------------

use File::Slurp ;
use File::Path ;

sub read_dependencies_cache
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

use PBS::Rules::Builders ;
my $file_to_build = $tree->{__BUILD_NAME} || PBS::Rules::Builders::GetBuildName($tree->{__NAME}, $tree) ;
my$dependency_file = "$file_to_build.dependencies" ;

if ( -e $file_to_build && -e $dependency_file)
	{
	my @dependencies = read_file($dependency_file, chomp => 1) ;

	if 	(
		$dependencies[0] =~ /^C dependencies PBS generated at/
		&& $dependencies[-1] =~ /^END C dependencies PBS/
		)
		{
		# valid cache
		# note: if compilation fails, the dependencies cache generation fails and we have a make rule
		shift @dependencies ; pop @dependencies ;
			
		my @invalid = grep { ! -e $_ } @dependencies ;
	
		if(@invalid)
			{
			$tree->{__PBS_POST_BUILD} =  \&InsertDependencyNodes ;
			return [1, $dependency_file] ; # triggered
			}
		else
			{
			$tree->{__PBS_POST_BUILD} = \&InsertDependencyNodes ;
			return [1, @dependencies] ;
			}
		}
	else
		{
		$tree->{__PBS_POST_BUILD} = \&InsertDependencyNodes ;
		return [1, $dependency_file] ; # triggered
		}
	}
else
	{
	$tree->{__PBS_POST_BUILD} =  \&InsertDependencyNodes ;
	return [1, $dependency_file] ; # triggered
	}
}


#-------------------------------------------------------------------------------

sub InsertDependencyNodes
{
## explain!!! -j digest regeneration, double warp passes, post pbs build, BUILD_DONE, MD5 computing

# called whenever the node is inserted, added in sub read_dependencies_cache, itself called as a depender

my ($node, $inserted_nodes) = @_ ;

return unless exists $node->{__BUILD_DONE} ;

my $build_name = $node->{__BUILD_NAME} ;
my $dependency_file = "$build_name.dependencies" ; # was generated by compiler

use File::Slurp ;
my $o_dependencies = read_file $dependency_file ;

$o_dependencies =~ s/^.*:\s+// ;
$o_dependencies =~ s/\\/ /g ;
$o_dependencies =~ s/\n/:/g ;
$o_dependencies =~ s/\s+/:/g ;

my %dependencies = map { $_ => 1 } grep { /\.h$/ } split(/:+/, $o_dependencies) ;
#my @dependencies = sort  map { $_ = "./$_" unless (/^\// || /^\.\//); $_} keys %dependencies ;
my @dependencies =  keys %dependencies ;

my $cache = "C dependencies PBS generated at " . __FILE__ . ':' . __LINE__ . "\n" ;

for my $d (@dependencies, $dependency_file)
	{
	$cache .= "$d\n" ;

	if(exists $inserted_nodes->{$d})
		{
		$node->{$d}{__MD5} = GetFileMD5($d) ; 
		$node->{$d} = $inserted_nodes->{$d} ; 
		}
	else
		{
		$inserted_nodes->{$d} = $node->{$d} = 
			{
			__NAME => $d,
			__BUILD_NAME => $d,
			__BUILD_DONE => 1,
			
			__INSERTED_AT =>
				{
				INSERTING_NODE => $node->{__NAME},
				INSERTION_RULE => 'c_depender',
				INSERTION_FILE => __FILE__ . ':' . __LINE__,
				INSERTION_PACKAGE=> 'NA',
				INSERTION_TIME => Time::HiRes::time
				},
				
			__PBS_CONFIG =>
				{
				BUILD_DIRECTORY    => $node->{__PBS_CONFIG}{BUILD_DIRECTORY},
				SOURCE_DIRECTORIES => $node->{__PBS_CONFIG}{SOURCE_DIRECTORIES},
				},

			__LOAD_PACKAGE => $node->{__LOAD_PACKAGE},
			__MD5 => GetFileMD5($d), # wasn't in the tree, need MD5  
			} ;
		}
	}


$cache .= "END C dependencies PBS\n" ;

write_file $dependency_file, $cache ;

# make sure object file digest doesn't use the temporary dependency file MD5
PBS::Digest::FlushMd5Cache($dependency_file) ;
$inserted_nodes->{$dependency_file}{__MD5} = GetFileMD5($dependency_file) ;  

# regenerate our own digest
eval { PBS::Digest::GenerateNodeDigest($node) } ;

# todo handle digest generation error
die "Error Generating node digest: $@" if $@ ;
}

#-------------------------------------------------------------------------------

1 ;

