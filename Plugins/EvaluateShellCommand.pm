
=head1 Plugin  EvaluateShellCommand

Provides the following replacement variables:

	%PBS_REPOSITORIES
	
	%BUILD_DIRECTORY

	%FILE_TO_BUILD_PATH
	%FILE_TO_BUILD_DIR
	%FILE_TO_BUILD_NAME
	%FILE_TO_BUILD_BASENAME
	%FILE_TO_BUILD_NO_EXT
	%FILE_TO_BUILD

	%TARGET_PATH
	%TARGET_DIR
	%TARGET_NAME
	%TARGET_BASENAME
	%TARGET_NO_EXT
	%TARGET

	%DEPENDENCY_LIST_RELATIVE_BUILD_DIRECTORY
	%TRIGGERED_DEPENDENCY_LIST
	%DEPENDENCY_LIST
	%DEPENDENCIES

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
	"Will display the transformation this plugin does.",
	'',
	'EVALUATE_SHELL_COMMAND_VERBOSE',
	) ;
	
use PBS::Build::NodeBuilder ;

#-------------------------------------------------------------------------------

sub EvaluateShellCommand
{
my ($shell_command_ref, $tree, $dependencies, $triggered_dependencies) = @_ ;

my $source_entry = $$shell_command_ref ;

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
		PrintInfo2 "Config: PBS_REPOSITORIES => $repository_path\n"
			if $tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
			
		$replacement .= "$prefix$repository_path ";
		}
		
	$pbs_repositories_replacements{"${prefix}\%PBS_REPOSITORIES"} = $replacement ;
	}
	
for my $field_to_replace (keys %pbs_repositories_replacements)
	{
	$$shell_command_ref =~ s/$field_to_replace/$pbs_repositories_replacements{$field_to_replace}/g ;
	}

#other %VARIABLES
my $file_to_build = $tree->{__BUILD_NAME} || PBS::Rules::Builders::GetBuildName($tree->{__NAME}, $tree);

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

@dependencies = sort @dependencies ;
my $dependency_list = join ' ', @dependencies ;

my $build_directory = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $dependency_list_relative_build_directory = join ' ', map { s/\Q$build_directory\E[\/|\\]//r} @dependencies ;

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
	
my $triggered_dependency_list = join ' ', sort @triggered_dependencies ;


my ($basename, $path, $ext) = File::Basename::fileparse($file_to_build, ('\..*')) ;
$path =~ s/\/$// ;

for 
	(
	[ BUILD_DIRECTORY                          => $build_directory ],

	[ FILE_TO_BUILD_DIR                        => $path ],
	[ FILE_TO_BUILD_PATH                       => $path ],
	[ FILE_TO_BUILD_NAME                       => "$basename$ext" ],
	[ FILE_TO_BUILD_BASENAME                   => $basename ],
	[ FILE_TO_BUILD_NO_EXT                     => "$path\/$basename"],
	[ FILE_TO_BUILD                            => $file_to_build ],

	[ TARGET_DIR                               => $path ],
	[ TARGET_PATH                              => $path ],
	[ TARGET_NAME                              => "$basename$ext" ],
	[ TARGET_BASENAME                          => $basename ],
	[ TARGET_NO_EXT                            => "$path\/$basename"],
	[ TARGET                                   => $file_to_build ],

	[ DEPENDENCY_LIST_RELATIVE_BUILD_DIRECTORY => $dependency_list_relative_build_directory],
	[ TRIGGERED_DEPENDENCY_LIST                => $triggered_dependency_list],
	[ DEPENDENCY_LIST                          => $dependency_list],
	[ DEPENDENCIES                             => $dependency_list],
	)
	{
	if($$shell_command_ref =~ m/\%$_->[0]/)
		{
		PrintInfo2 "Config: $_->[0] => $_->[1]\n"
			 if $tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
	
		$$shell_command_ref =~ s/\%$_->[0]/$_->[1]/g ;
		}
	}

for( grep {  ! /^__/ && defined $tree->{$_}{__USER_ATTRIBUTE} } keys %$tree)
	{
	my ($user_attribute, $build_name) = ($tree->{$_}{__USER_ATTRIBUTE}, $tree->{$_}{__BUILD_NAME}) ;

	my ($basename, $path, $ext) = File::Basename::fileparse($build_name, ('\..*')) ;
	$path =~ s/\/$// ;

	if($$shell_command_ref =~ m/\%$user_attribute/)
		{
		$$shell_command_ref =~ s/\%${user_attribute}_PATH/$path/g ;
		$$shell_command_ref =~ s/\%$user_attribute/$build_name/g ;

		PrintInfo2 "Config: $user_attribute => $build_name\n"
			 if $tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
		}
	}
}

#-------------------------------------------------------------------------------

1 ;

