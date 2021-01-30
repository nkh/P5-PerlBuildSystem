
use File::Slurp ;
use File::Path ;
use File::Spec::Functions qw(:ALL) ;
use PBS::Rules::Builders ;

#use POSIX qw(strftime);
use Cwd ;

#-------------------------------------------------------------------------------

# C depender for object files (not part of the core pbs but distributed with it)

#	creates dependency files during the build and integrates them in the node's graph
#
#	this the following advantages:
#	
#	very little code specific to the depender, this module and two PBS rules
#
#	builds are triggered properly if no dependency cache is found
#
#	cache generation is handled by the compiler, in gcc example, as a side effect of the build
#	
#	No need to wait for the dependency of all the object files, starts building directly
#	
#	the cache is generated in parallel, if the build is done with -j option
#
#	the dependencies are merged back to the graph in a post build steps
#		just after the build for digest and after all node builds for the warp cache
#
#	each node is responsible for integrating its dependencies, this means that the mechanism
#	is open for other types of nodes not just object files dependencies 
#
#	the cache is specific for the object node
#
#	in case a dependency cache is invalid, its contents are not added to the pre-build warp file,
#	insuring validity of the warp cache which would retrigger the dependency step if necessary

#-------------------------------------------------------------------------------

sub GetObjectDependencies
{
my
        (
        undef,
        undef,
        $tree,
        undef,
        $dependencies,         # rule local
        $builder_override,     # rule local
        ) = @_ ;

my ($triggered, @previous_dependencies, @my_dependencies) ;

if(defined $dependencies && @$dependencies && $dependencies->[0] == 1 && @$dependencies > 1)
        {
        # previous depender defined dependencies
        $triggered       = shift @{$dependencies} ;
        @previous_dependencies = @{$dependencies} ;
        }

my $digest_file_name = PBS::Digest::GetDigestFileName($tree) ;

# if .o node was previously build the dependencies will be cached in the .o digest
if(-e $digest_file_name)
	{
	my $digest ;
	unless (($digest) = do $digest_file_name) 
		{
		PrintWarning "Depend: GetObjectDependencies couldn't parse '$digest_file_name': $@\n" ;
		}
		
	if('HASH' eq ref $digest)
		{
		my ($source) = ( grep {/\.c$/} keys %$digest) ;

		if($digest->{$source} eq PBS::Digest::GetFileMD5($source))
			{
			for my $dependency ( grep {/\.h$/} keys %$digest)
				{
				if($digest->{$dependency} ne  PBS::Digest::GetFileMD5($dependency))
					{
					my  $pbs_config = $tree->{__PBS_CONFIG} ;

					PrintWarning "Depend: C depender: '$tree->{__NAME}' dependency '$dependency' changed, removing cached dependencies.\n" 
						if $pbs_config->{DISPLAY_DIGEST} ;

					@my_dependencies = () ;
					last ;
					}

				push @my_dependencies, $dependency ;
				}
			}
		}	
	}

$triggered = 1 ;
unshift @my_dependencies, $triggered ;
push @my_dependencies, @previous_dependencies ;

return(\@my_dependencies, $builder_override) ;
}

#-------------------------------------------------------------------------------

sub InsertDependencyNodes
{
my ($node, $inserted_nodes) = @_ ;

#return unless exists $node->{__BUILD_DONE} ;

my $dependency_name = "$node->{__NAME}.pbs_o_dep" ;

my ($volume,$directories,$file) = splitpath($node->{__BUILD_NAME});
my ($dependency_file, $o_dependencies) = ("$directories.$file.pbs_o_dep", '') ;

$o_dependencies = read_file $dependency_file or die ERROR "C_DEPENDER: can't read '$dependency_file, $!'\n" ;

# in gcc case, it is a makefile we parse
$o_dependencies =~ s/^.*:\s+// ;
$o_dependencies =~ s/\\/ /g ;
$o_dependencies =~ s/\n/:/g ;
$o_dependencies =~ s/\s+/:/g ;

my %dependencies = map { $_ => 1 } grep { /\.h$/ } split(/:+/, $o_dependencies) ;
my @dependencies = sort  map { $_ = "./$_" unless (/^\// || /^\.\//); $_} keys %dependencies ;

# base dependencies in ./ if possible
my $source_directory = $node->{__PBS_CONFIG}{SOURCE_DIRECTORIES}[0] ;
$source_directory = cwd if $source_directory eq './' ;

for my $d (@dependencies)
	{
	$d =~ s/^$source_directory/./ ;

	if(exists $inserted_nodes->{$d})
		{
		$node->{$d}{__MD5} = GetFileMD5($d) ; 
		$node->{$d} = $inserted_nodes->{$d} ; 
		}
	else
		{
		my $file = __FILE__ ;
		($file) = ( $file =~ /^'(.*)'$/) ;

		$inserted_nodes->{$d} = $node->{$d} = 
			{
			__NAME         => $d,
			__BUILD_NAME   => $d,
			__BUILD_DONE   => 1,

			__INSERTED_AT  => 
				{
				INSERTING_NODE => $node->{__NAME},
				INSERTION_RULE => 'c_depender',
				INSERTION_RULE_NAME => 'c_depender',
				INSERTION_RULE_LINE => __LINE__,
				INSERTION_RULE_FILE => $file,
				INSERTION_FILE => $file,
				INSERTION_PACKAGE=> 'NA',
				INSERTION_TIME => Time::HiRes::time,
				} ,

			__PBS_CONFIG   => $node->{__PBS_CONFIG},
			__LOAD_PACKAGE => $node->{__LOAD_PACKAGE},
			__MD5          => GetFileMD5($d),  
			} ;
		}
	}

delete $node->{$dependency_name} ;  

# regenerate .o digest
eval { PBS::Digest::GenerateNodeDigest($node) } ;

die "Error Generating node '$node->{__NAME}' digest: $@\n" if $@ ;

return "Inserted node '$node->{__NAME}' dependencies [" . scalar(@dependencies) . "] in the graph ($dependency_file)\n" ;
}

#-------------------------------------------------------------------------------

1 ;

