
AddRule 'all', [ 'all' => 'special_file_containing_dependencies.objects' ]
	=> '%LD -shared -o %FILE_TO_BUILD %FLATTEN_DEPENDENCY_LIST -lc -lm' ;

# register the plugin at run time, could also be with the other plugins
my $pbs_config = GetPbsConfig() ;
PBS::Plugin::LoadPluginFromSubRefs($pbs_config, __FILE__, 'EvaluateShellCommand' => \&Filter_FLATTEN_DEPENDENCY_LIST) ;

sub Filter_FLATTEN_DEPENDENCY_LIST
{
my ($shell_command_ref, $tree, $dependencies, $triggered_dependencies) = @_ ;

my $evaluate_shell_command_verbose = $tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
PrintInfo2 __FILE__ . ':' . __LINE__ . "\n" if $evaluate_shell_command_verbose ;

if($$shell_command_ref =~ /%FLATTEN_DEPENDENCY_LIST/)
	{
	my $object_files = '';
	
	for my $dependency (@$dependencies)
		{
		if($dependency =~ /\.objects$/)
			{
			my @files_and_md5 = read_file($dependency) ;
			
			for my $entry (@files_and_md5)
				{
				my ($file, $md5) = split(' =>', $entry) ;
				$object_files .= "$file\n" ;
				}
			}
		else
			{
			$object_files .= "$dependency\n";
			}
		}
	
	my $dependency_file_from_dot_objects = "$tree->{__BUILD_NAME}.objects_no_md5" ;
	write_file($dependency_file_from_dot_objects, $object_files) ;
	
	PrintDebug "\tFLATTEN_DEPENDENCY_LIST => ...\n" if $evaluate_shell_command_verbose ; 

	$$shell_command_ref =~ s/%FLATTEN_DEPENDENCY_LIST/`cat $dependency_file_from_dot_objects`/ ;
	}
	
print "\n" if evaluate_shell_command_verbose ; 
} ;

