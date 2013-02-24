
=head1 Plugin  EvaluateShellCommand

Let the Build system author evaluate shell commands before they are run.  This allows
her to add variables like %SOME_SPECIAL_VARIABLE without interfering with PBS.


Provides the following shell replacement variables:

	%PBS_REPOSITORIES
	
	%BUILD_DIRECTORY

	%FILE_TO_BUILD_PATH
	%FILE_TO_BUILD_NAME
	%FILE_TO_BUILD_BASENAME
	%FILE_TO_BUILD_NO_EXT
	%FILE_TO_BUILD

	%DEPENDENCY_LIST_RELATIVE_BUILD_DIRECTORY
	%TRIGGERED_DEPENDENCY_LIST
	%DEPENDENCY_LIST


=over 2

=item  --evaluate_shell_command_verbose

=back

=cut

use PBS::PBSConfigSwitches ;
use PBS::PBSConfig ;
use PBS::Information ;
use Data::TreeDumper ;

#-------------------------------------------------------------------------------


our $evaluate_shell_command_verbose ;

PBS::PBSConfigSwitches::RegisterFlagsAndHelp
	(
	'evaluate_shell_command_verbose',
	'EVALUATE_SHELL_COMMAND_VERBOSE',
	"Will display the transformation this plugin does.",
	'',
	) ;
	
use PBS::Build::NodeBuilder ;

#-------------------------------------------------------------------------------

sub EvaluateShellCommand
{
my ($shell_command_ref, $tree, $dependencies, $triggered_dependencies) = @_ ;

my $evaluate_shell_command_verbose = $tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;

if($evaluate_shell_command_verbose)
	{
	PrintDebug "'EvaluateShellCommand' plugin handling '$tree->{__NAME}' shell command:\n\t$$shell_command_ref\n" ;
	}

my @repository_paths = PBS::Build::NodeBuilder::GetNodeRepositories($tree) ;

# %PBS_REPOSITORIES
my %pbs_repositories_replacements ;

while($$shell_command_ref =~ /([^\s]+)?\%PBS_REPOSITORIES/g)
	{
	my $prefix = $1 || '' ;
	
	next if exists $pbs_repositories_replacements{"${prefix}\%PBS_REPOSITORIES"} ;
	
	my $replacement = '';
	for my $repository_path (@repository_paths)
		{
		if($evaluate_shell_command_verbose)
			{
			PrintDebug "\t\trepository: $repository_path\n" ;
			}
			
		$replacement .= "$prefix$repository_path ";
		}
		
	$pbs_repositories_replacements{"${prefix}\%PBS_REPOSITORIES"} = $replacement ;
	}
	
for my $field_to_replace (keys %pbs_repositories_replacements)
	{
	$$shell_command_ref =~ s/$field_to_replace/$pbs_repositories_replacements{$field_to_replace}/g ;
	}

#other %VARIABLE
my $file_to_build = $tree->{__BUILD_NAME} || GetBuildName($tree->{__NAME}, $tree);

my @dependencies ;
unless(defined $dependencies)
	{
	#extract them from tree if not passed as argument
	@dependencies = map {$tree->{$_}{__BUILD_NAME} ;} grep { $_ !~ /^__/ && exists $tree->{$_}{__BUILD_NAME}}(keys %$tree) ;
	}
else
	{
	@dependencies = @$dependencies ;
	}

my $dependency_list = join ' ', @dependencies ;

my $build_directory = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $dependency_list_relative_build_directory = join(' ', map({my $copy = $_; $copy =~ s/\Q$build_directory\E[\/|\\]// ; $copy} @dependencies)) ;

my @triggered_dependencies ;

unless(defined $dependencies)
	{
	# build a list of triggering dependencies and weed out doublets
	my %triggered_dependencies_build_names ;
	for my $triggering_dependency (@{$tree->{__TRIGGERED}})
		{
		my $dependency_name = $triggering_dependency->{NAME} ;
		
		if($dependency_name !~ /^__/ && ! exists $triggered_dependencies_build_names{$dependency_name})
			{
			push @triggered_dependencies, $tree->{$dependency_name}{__BUILD_NAME} ;
			$triggered_dependencies_build_names{$dependency_name} = $tree->{$dependency_name}{__BUILD_NAME} ;
			}
		}
	}
else
	{
	@triggered_dependencies = @$triggered_dependencies ;
	}
	
my $triggered_dependency_list = join ' ', @triggered_dependencies ;

my ($basename, $path, $ext) = File::Basename::fileparse($file_to_build, ('\..*')) ;
$path =~ s/\/$// ;

$$shell_command_ref=~ s/\%BUILD_DIRECTORY/$build_directory/g ;

$$shell_command_ref =~ s/\%FILE_TO_BUILD_PATH/$path/g ;
$$shell_command_ref =~ s/\%FILE_TO_BUILD_NAME/$basename$ext/g ;
$$shell_command_ref =~ s/\%FILE_TO_BUILD_BASENAME/$basename/g ;
$$shell_command_ref =~ s/\%FILE_TO_BUILD_NO_EXT/$path\/$basename/g ;
$$shell_command_ref =~ s/\%FILE_TO_BUILD/$file_to_build/g ;

$$shell_command_ref =~ s/\%DEPENDENCY_LIST_RELATIVE_BUILD_DIRECTORY/$dependency_list_relative_build_directory/g ;
$$shell_command_ref =~ s/\%TRIGGERED_DEPENDENCY_LIST/$triggered_dependency_list/g ;
$$shell_command_ref =~ s/\%DEPENDENCY_LIST/$dependency_list/g ;

PrintDebug "\t=> $$shell_command_ref\n\n" if($evaluate_shell_command_verbose) ; 
}

#-------------------------------------------------------------------------------

1 ;

