
# call with: pbs -my_flag -my_flag_string a_string -my_flag_string_list a -my_flag_string_list b -my_flag_integer 1 -my_flag_integer_list 1 -my_flag_integer_list 2 -my_flag_integer_hash first_key = 1 -my_flag_integer_hash second_key = 2 -evaluate_shell_command_verbose all

my $pbs_config = GetPbsConfig() ;

my %my_options ;

for my $key (keys %{$pbs_config})
	{
	if($key =~ /^MY_/)
		{
		$my_options{$key} = $pbs_config->{$key} ;
		}
	}

use Data::TreeDumper ;
print DumpTree \%my_options, 'my options:' ;

AddRule 'use with --evaluate_shell_command_verbose',
	['all'],
	"echo %FILE_TO_BUILD %PBS_REPOSITORIES %DEPENDENCY_LIST_OBJECTS_EXPANDED" ;
	
 
