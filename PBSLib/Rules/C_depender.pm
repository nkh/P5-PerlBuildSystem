
use File::Slurp ;
use File::Path ;
use PBS::Rules::Builders ;

#-------------------------------------------------------------------------------

sub InsertDependencyNodes
{
# C depender for object files (not part of the core pbs but distributed with it)

# old C depender:
#	created dependency files during the depend step
#	handled a complex cache creation and verification
#	had for goal to present a complete dependency graph before the build
#
#	some points were good enough but "wrong", dependencies belonged to the
#	C file except one could not do variant nodes on the fly, that was
#	a goal for pbs but not implemented, in a way the depender was too advanced
#
#	the dependencies were computed sequentially 

# the new depender:
#	creates dependency files during the build and in a post build step
#
#	this the following advantages:
#	
#	very little code specific to the depender, this sub,read_dependencies_cache and two rules
#
#	the cache code is much simpler and most is handled by the pbs core mechanism
#
#	builds are triggered properly if no dependency cache is found but the cache generation
#	is handled by the compiler, in gcc example, as a side effect of the build
#	
#	No need to wait for the dependency of all the C files, starts building directly
#	
#	the cache is generated in parallel, if the build is done with -j option
#
#	the dependencies are merged back to the graph in a post build step, this is necessary
#	as the nodes are build in separate processes that do not share the graph
#
#	each node is responsible for integrating its dependencies, this means that the mechanism
#	is open for other types of nodes not just object files dependencies 
#
#	the cache is specific for the object node even if they share C nodes, no more configuration
#	dependencies for the dependency cache, it's just a list of source header files
#
#	warp, pre and post-build, is handled properly as object nodes regenerate their digest and the
#	digest of their dependencies after the build
#
#	in case a dependency cache is invalid, its contents are not added to the pre-build warp file,
#	insuring validity of the warp cache which would retrigger the dependency step if necessary
#
#	it's one tenth of the old code size   


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
my @dependencies = sort  map { $_ = "./$_" unless (/^\// || /^\.\//); $_} keys %dependencies ;

use POSIX qw(strftime);
my $now = strftime "%a %b %e %H:%M:%S %Y", gmtime;

my $cache = "C dependencies PBS generated at " . __FILE__ . ':' . __LINE__ . " $now\n" ;

my $insertion_data =
	{
	INSERTING_NODE => $node->{__NAME},
	INSERTION_RULE => 'c_depender',
	INSERTION_FILE => __FILE__ . ':' . __LINE__,
	INSERTION_PACKAGE=> 'NA',
	INSERTION_TIME => Time::HiRes::time,
	} ;

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
			__NAME         => $d,
			__BUILD_NAME   => $d,
			__BUILD_DONE   => 1,
			__INSERTED_AT  => $insertion_data,
			__PBS_CONFIG   => $node->{__PBS_CONFIG},
			__LOAD_PACKAGE => $node->{__LOAD_PACKAGE},
			__MD5          => GetFileMD5($d),  
			} ;
		}
	}

$cache .= "END C dependencies PBS\n" ;

write_file $dependency_file, $cache ;

# make sure object file digest doesn't use the temporary dependency file hash 
PBS::Digest::FlushMd5Cache($dependency_file) ;
$inserted_nodes->{$dependency_file}{__MD5} = GetFileMD5($dependency_file) ;  

# regenerate our own digest
eval { PBS::Digest::GenerateNodeDigest($node) } ;

die "Error Generating node digest: $@" if $@ ;
}

#-------------------------------------------------------------------------------

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

1 ;

