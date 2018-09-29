
use File::Slurp ;
use File::Path ;
use PBS::Rules::Builders ;

use POSIX qw(strftime);
use Cwd ;

#-------------------------------------------------------------------------------

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
#	very little code specific to the depender, this module and two PBS rules
#
#	the cache code is much simpler and most is handled by the pbs core mechanism
#
#	builds are triggered properly if no dependency cache is found
#
#	cache generation is handled by the compiler, in gcc example, as a side effect of the build
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


my $cache_header = "C dependencies PBS generated at " ;
my $cache_footer = 'END C dependencies PBS' ;

#-------------------------------------------------------------------------------

sub read_dependencies_cache
{
my (undef, undef, $node) = @_ ;

my $file_to_build = $node->{__NAME} ; 
my $dependency_file = "$file_to_build.dependencies" ;

# base dependency cache in ./ 
my $source_directory = $node->{__PBS_CONFIG}{SOURCE_DIRECTORIES}[0] ;
$source_directory = cwd if $source_directory eq './' ;

$dependency_file =~ s/^$source_directory/./ ;

# handle the newly generated cache, if any
$node->{__PBS_POST_BUILD} =  \&InsertDependencyNodes ;

my @dependencies_cache ;

if 
	(
	   -e $dependency_file
	&& ( @dependencies_cache = read_file($dependency_file, chomp => 1) )
	&& ( $dependencies_cache[0] =~ /^$cache_header/ && $dependencies_cache[-1] =~ /^$cache_footer/ )
	)
	{
	# valid cache, remove header and footer
	shift @dependencies_cache ; pop @dependencies_cache ;

	return [1, @dependencies_cache, ] ; 
	}
else
	{
	return [1, $dependency_file] ;
	}
}

#-------------------------------------------------------------------------------

sub InsertDependencyNodes
{
my ($node, $inserted_nodes) = @_ ;

return unless exists $node->{__BUILD_DONE} ;

my ($dependency_file, $o_dependencies) = ($node->{__BUILD_NAME} . '.dependencies', '') ;

$o_dependencies = read_file $dependency_file ; # in gcc case, this is a makefile
$o_dependencies =~ s/^.*:\s+// ;
$o_dependencies =~ s/\\/ /g ;
$o_dependencies =~ s/\n/:/g ;
$o_dependencies =~ s/\s+/:/g ;

my %dependencies = map { $_ => 1 } grep { /\.h$/ } split(/:+/, $o_dependencies) ;
my @dependencies = sort  map { $_ = "./$_" unless (/^\// || /^\.\//); $_} keys %dependencies ;

my $now = strftime "%a %b %e %H:%M:%S %Y", gmtime;
my $cache = $cache_header . __FILE__ . ':' . __LINE__ . " $now\n" ;

# base dependencies in ./ if possible
my $source_directory = $node->{__PBS_CONFIG}{SOURCE_DIRECTORIES}[0] ;
$source_directory = cwd if $source_directory eq './' ;


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
	$d =~ s/^$source_directory/./ ;

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

$cache .= "$cache_footer\n" ;

write_file $dependency_file, $cache ;

# make sure object file digest doesn't use the temporary dependency file hash 
PBS::Digest::FlushMd5Cache($dependency_file) ;
$inserted_nodes->{$dependency_file}{__MD5} = GetFileMD5($dependency_file) ;  

# regenerate our own digest, could be done by PBS for all nodes with a post PBS build
eval { PBS::Digest::GenerateNodeDigest($node) } ;

die "Error Generating node '$node->{__NAME}' digest: $@\n" if $@ ;
}

#-------------------------------------------------------------------------------

1 ;

