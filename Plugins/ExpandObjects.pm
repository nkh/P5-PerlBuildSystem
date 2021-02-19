
=head1 Plugin  ExpandObjects

Expand /objects in %DEPENDENCY_LIST_EXPANDED

=cut

use PBS::Output;
use PBS::SubpbsResult ;

use Data::TreeDumper ;

#-------------------------------------------------------------------------------

sub EvaluateShellCommand
{
my ($shell_command_ref, $tree, $dependencies, $triggered_dependencies) = @_ ;

my $evaluate_shell_command_verbose = $tree->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
	
my $expanded_variables = 0 ;

if($$shell_command_ref =~ /([^\s]+)?\%DEPENDENCY_LIST_OBJECTS_EXPANDED/)
	{
	my $expanded_dependency_list = '' ;
	
	for my $dependency (@$dependencies)
		{
		if($dependency =~ /\.objects$/)
			{
			$expanded_dependency_list .= ' ' . join(' ', GetFiles(new PBS::SubpbsResult($dependency))) ;
			}
		else
			{
			$expanded_dependency_list .= ' ' . $dependency ;
			}
		}
	
	$expanded_variables++ ;

	PrintInfo2 "\t" . __FILE__ . ':' . __LINE__ . "\n" if $evaluate_shell_command_verbose && $expanded_variables == 1 ;
	PrintDebug "\t\tDEPENDENCY_LIST_OBJECTS_EXPANDED => $expanded_dependency_list\n" if $evaluate_shell_command_verbose ; 

	$$shell_command_ref =~ s/\%DEPENDENCY_LIST_OBJECTS_EXPANDED/$expanded_dependency_list/g ;
	}

print "\n" if $evaluate_shell_command_verbose && $expanded_variables ; 
}

sub GetFiles
{
# extract files from fileAndMd5 class

my ($subpbs_result) = @_ ;

map{$_->{FILE}} @{ $subpbs_result->GetFileAndMd5()}
}

#-------------------------------------------------------------------------------

1 ;

