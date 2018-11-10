
use PBS::Plugin ;


PBS::Plugin::LoadPluginFromSubRefs(GetPbsConfig(), '+001C.pm', 'EvaluateShellCommand' =>
	\&C_eval) ;

#-------------------------------------------------------------------------------

sub C_eval 
{
my ($shell_command_ref, $tree, $dependencies, $triggered_dependencies) = @_ ;

if($$shell_command_ref =~ /%C_SOURCE/)
	{
	PrintDebug __FILE__. ':' . __LINE__ . " [%C_SOURCE]\n\t$$shell_command_ref\n"
		if($tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE}) ;

	my $c_source = '' ;

	for my $dependency (grep { ! /^__/ } keys %$tree)
		{
		$c_source .= "$dependency" if $dependency =~ /\. c (?:pp)? /x ;
		}

	$$shell_command_ref =~ s/%C_SOURCE/$c_source/ ;

	PrintInfo3 "\t$$shell_command_ref\n\n" 
		if($tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE}) ;
	}

if($$shell_command_ref =~ /%CFLAGS_INCLUDE/)
	{
	PrintDebug __FILE__. ':' . __LINE__ . " [%CFLAGS_INCLUDE]\n\t$$shell_command_ref\n"
		if($tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE}) ;

	my $cflags_include = GetCFileIncludePaths($tree);
	
	$$shell_command_ref =~ s/%CFLAGS_INCLUDE/$cflags_include/ ;

	PrintInfo3 "\t$$shell_command_ref\n\n" 
		if($tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE}) ;
	}

if($$shell_command_ref =~ /%C_DEPENDER/)
	{
	PrintDebug __FILE__. ':' . __LINE__ . " [%C_DEPENDER]\n\t$$shell_command_ref\n"
		if($tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE}) ;

	my $c_depender = $tree->{__CONFIG}{C_DEPENDER} ;

	unless(defined $c_depender)
		{
		PrintWarning("\t'C_DEPENDER' isn't defined.\n") ;
		}
	else
		{
		$$shell_command_ref =~ s/%C_DEPENDER/$c_depender/ ;
		}

	PrintInfo3 "\t$$shell_command_ref\n\n" 
		if($tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE}) ;
	}
}

#-------------------------------------------------------------------------------

sub GetCFileIncludePaths
{
my ($tree) = @_;
	
my $pbs_config = $tree->{__PBS_CONFIG};

my @source_directories = @{ $pbs_config->{SOURCE_DIRECTORIES} };

my @include_paths = split(/\s*-I\s*/, $tree->{__CONFIG}{CFLAGS_INCLUDE});
# Remove the empty element before the first -I
shift @include_paths;

my $dependent = $tree->{__NAME};
my $dependent_path = (File::Basename::fileparse($dependent))[1] ;

my $result = '';

# Add the dependent path, to make includes like: #include "header" work
for my $include_path ($dependent_path, @include_paths)
	{
	$include_path =~ s~/$~~ ;
	$include_path =~ s|^"||;
	$include_path =~ s|"$||;
	$include_path =~ s/^\s+// ;
	$include_path =~ s/\s+$// ;
	
	if (File::Spec->file_name_is_absolute($include_path))
		{
		$result .= qq| -I "$include_path"|;
		}
	else
		{
		for my $source_directory (@source_directories)
			{
			$result .= ' -I "' . CollapsePath("$source_directory/$include_path") . '"';
			}
		}
	}
	
return $result;
}

#-------------------------------------------------------------------------------

1;

