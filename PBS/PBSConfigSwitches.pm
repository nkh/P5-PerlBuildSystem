
package PBS::PBSConfigSwitches ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(RegistredFlagsAndHelp) ;
our $VERSION = '0.03' ;

use PBS::Constants ;
use PBS::Output ;

#-------------------------------------------------------------------------------

my @registred_flags_and_help ; # allow plugins to register their switches
my %registred_flags ; #only one flag will be set by Getopt::long. Give a warning to unsuspecting user

RegisterDefaultPbsFlags() ; # reserve them so plugins can't modify their meaning

#-------------------------------------------------------------------------------
sub RegisterFlagsAndHelp 
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $succes = 1 ;

while( my ($switch, $variable, $help1, $help2) = splice(@_, 0, 4))
	{
	my $switch_copy = $switch ;
	$switch_copy =~ s/(=|:).*$// ;
	
	my $switch_is_unique = 1 ;
	for my $switch_unit (split('\|',$switch_copy))
		{
		if(exists $registred_flags{$switch_unit})
			{
			$succes = 0 ;
			$switch_is_unique = 0 ;
			PrintWarning "        In Plugin '$file_name:$line', switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'. Ignoring.\n" ;
			}
		else
			{
			$registred_flags{$switch_unit} = "$file_name:$line" ;
			}
		}
		
	if($switch_is_unique)
		{
		#~ PrintInfo "        Registering switch '$switch' In Plugin '$file_name:$line'.\n" ;
		
		push @registred_flags_and_help, $switch, $variable, $help1, $help2 ;
		}
	}

return($succes) ;
}

#-------------------------------------------------------------------------------

sub RegisterDefaultPbsFlags
{
my @flags_and_help = GetSwitches() ;

while(my ($switch, $variable, $help1, $help2) = splice(@flags_and_help, 0, 4))
	{
	$switch =~ s/(=|:).*$// ;
	
	for my $switch_unit (split('\|', $switch))
		{
		if(exists $registred_flags{$switch_unit})
			{
			die ERROR "Switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'.\n" ;
			}
		else
			{
			$registred_flags{$switch_unit} = "PBS reserved switch " . __PACKAGE__ ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub Get_GetoptLong_Data
{
my $pbs_config = shift || die 'Missing argument.' ;

my @flags_and_help = GetSwitches($pbs_config) ;

my $flag_element_counter = 0 ;
my @getoptlong_data ;

for (my $i = 0 ; $i < @flags_and_help; $i += 4)
	{
	my ($flag, $variable) = ($flags_and_help[$i], $flags_and_help[$i + 1]) ;
	push @getoptlong_data, ($flag, $variable)  ;
	}

return(@getoptlong_data) ;
}

#-------------------------------------------------------------------------------

sub GetSwitches
{
my $pbs_config = shift || {} ;

$pbs_config->{DO_BUILD} = 1 ;
$pbs_config->{TRIGGER} = [] ;

$pbs_config->{JOBS_DIE_ON_ERROR} = 0 ;

$pbs_config->{GENERATE_TREE_GRAPH_GROUP_MODE} = GRAPH_GROUP_NONE ;
$pbs_config->{GENERATE_TREE_GRAPH_SPACING} = 1 ;

$pbs_config->{RULE_NAMESPACES} ||= [] ;
$pbs_config->{CONFIG_NAMESPACES} ||= [] ;
$pbs_config->{SOURCE_DIRECTORIES} ||= [] ;
$pbs_config->{PLUGIN_PATH} ||= [] ;
$pbs_config->{LIB_PATH} ||= [] ;
$pbs_config->{DISPLAY_BUILD_INFO} ||= [] ;
$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX} ||= [] ;
$pbs_config->{DISPLAY_NODE_INFO} ||= [] ;
$pbs_config->{DISPLAY_NODE_ENVIRONMENT} ||= [] ;
$pbs_config->{NODE_ENVIRONMENT_REGEX} ||= [] ;
$pbs_config->{LOG_NODE_INFO} ||= [] ;
$pbs_config->{USER_OPTIONS} ||= {} ;
$pbs_config->{KEEP_ENVIRONMENT} ||= [] ;
$pbs_config->{COMMAND_LINE_DEFINITIONS} ||= {} ;
$pbs_config->{DISPLAY_DEPENDENCIES_REGEX} ||= [] ;
$pbs_config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_NODE} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_EXCLUDE} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_INCLUDE} ||= [] ;
$pbs_config->{DISPLAY_PBS_CONFIGURATION} ||= [] ;
$pbs_config->{VERBOSITY} ||= [] ;
$pbs_config->{POST_PBS} ||= [] ;
$pbs_config->{DISPLAY_TREE_FILTER} ||= [] ;
$pbs_config->{DISPLAY_TEXT_TREE_REGEX} ||= [] ;
$pbs_config->{BREAKPOINTS} ||= [] ;

my $load_config_closure = sub {LoadConfig(@_, $pbs_config) ;} ;

my @flags_and_help =
	(
	'h|help'                          => \$pbs_config->{DISPLAY_HELP},
		'Displays this help.',
		'',
		
	'hs|help_switch=s'                => \$pbs_config->{DISPLAY_SWITCH_HELP},
		'Displays help for the given switch.',
		'',
		
	'hnd|help_narrow_display'         => \$pbs_config->{DISPLAY_HELP_NARROW_DISPLAY},
		'Writes the flag name and its explanation on separate lines.',
		'',

	'generate_bash_completion_script'   => \$pbs_config->{GENERATE_BASH_COMPLETION_SCRIPT},
		'Output a bash completion script and exits.',
		'',

	'pp|pbsfile_pod'                    => \$pbs_config->{DISPLAY_PBSFILE_POD},
		"Displays a user defined help. See 'Online help' in pbs.pod",
		<<'EOH',
=for PBS =head1 SOME TITLE

this is extracted by the --pbsfile_pod command

the format is /^for PBS =pod_formating title$/

=cut 

# some code

=head1 NORMAL POD DOCUMENTATION

this is extracted by the --pbs2pod command

=cut

# more stuff

=for PBS =head1 SOME TITLE\n"

this is extracted by the --pbsfile_pod command and added to the
previous =for PBS section

=cut 

EOH
		
	'pbs2pod'                         => \$pbs_config->{PBS2POD},
		'Extracts the pod contained in the Pbsfile (except user documentation POD).',
		'See --pbsfile_pod.',
		
	'raw_pod'                         => \$pbs_config->{RAW_POD},
		'-pbsfile_pod or -pbs2pod is dumped in raw pod format.',
		'',
		
	'd|display_pod_documenation:s'    => \$pbs_config->{DISPLAY_POD_DOCUMENTATION},
		'Interactive PBS documentation display and search.',
		'',
		
	'wizard:s'                      => \$pbs_config->{WIZARD},
		'Starts a wizard.',
		'',
		
	'wi|display_wizard_info'          => \$pbs_config->{DISPLAY_WIZARD_INFO},
		'Shows Informatin about the found wizards.',
		'',
		
	'wh|display_wizard_help'          => \$pbs_config->{DISPLAY_WIZARD_HELP},
		'Tell the choosen wizards to show help.',
		'',
		
	'v|version'                     => \$pbs_config->{DISPLAY_VERSION},
		'Displays Pbs version.',
		'',
		
	'info_label=s'                  => \&PBS::Output::InfoLabel,
		'Adds a text label to all output.',
		'',
		
	'c|color=s'                     => \&PBS::Output::SetOutputColorDepth,
		'Set color depth. Valid values are 2 = no_color, 16 = 16 colors, 256 = 256 colors',
		<<EOT,
Term::AnsiColor is used  to color output.

Recognized colors are :
	'bold'   
	'dark'  
	'underline'
	'underscore'
	'blink'
	'reverse'
	'black'    'on_black'  
	'red'     'on_red' 
	'green'   'on_green'
	'yellow'  'on_yellow'
	'blue'    'on_blue'  
	'magenta' 'on_magenta'
	'cyan'    'on_cyan'  
	'white'   'on_white'

	or RGB5 values, check 'Term::AnsiColor' for more information. 
EOT

	'cs|color_set=s'                => \&PBS::Output::SetOutputColor,
		"Set a color. Argument is a string with format 'color_name:ansi_code_string; eg: -cs 'user:cyan on_yellow'",
		<<EOT,
Color names used in Pbs:
	error
	warning
	warning_2
	info
	info_2
	info_3
	user
	shell
	debug
EOT

	'output_indentation=s'            => \$PBS::Output::indentation,
		'set the text used to indent the output. This is repeated "subpbs level" times.',
		'',

	'p|pbsfile=s'                     => \$pbs_config->{PBSFILE},
		'Pbsfile use to defines the build.',
		'',
		
	'prf|pbs_response_file=s'         => \$pbs_config->{PBS_RESPONSE_FILE},
		'File containing switch definitions and targets.',
		'',
		
	'q|quiet'                         => \$pbs_config->{QUIET},
		'Reduce the output from the command. See --ndpb, --so, --sco.',
		'',
		
	'naprf|no_anonymous_pbs_response_file'     => \$pbs_config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
		'Use only a response file named after the user or the one given on the command line.',
		'',
		
	'nprf|no_pbs_response_file'       => \$pbs_config->{NO_PBS_RESPONSE_FILE},
		'Don\'t use any response file.',
		'',
		
	'plp|pbs_lib_path=s'              => $pbs_config->{LIB_PATH},
		"Path to the pbs libs. Multiple directories can be given, each directory must start at '/' (root) or '.' or pbs will display an error message and exit.",
		'',
		
	'display_pbs_lib_path'            => \$pbs_config->{DISPLAY_LIB_PATH},
		"Displays PBS lib paths (for the current project) and exits.",
		'',
		
	'ppp|pbs_plugin_path=s'           => $pbs_config->{PLUGIN_PATH},
		"Path to the pbs plugins. The directory must start at '/' (root) or '.' or pbs will display an error message and exit.",
		'',
		
	'display_pbs_plugin_path'         => \$pbs_config->{DISPLAY_PLUGIN_PATH},
		"Displays PBS plugin paths (for the current project) and exits.",
		'',
		
	'no_default_path_warning'              => \$pbs_config->{NO_DEFAULT_PATH_WARNING},
		"When this switch is used, PBS will not display a warning when using the distribution's PBS lib and plugins.",
		'',
		
	'dpli|display_plugin_load_info'   => \$pbs_config->{DISPLAY_PLUGIN_LOAD_INFO},
		"displays which plugins are loaded.",
		'',
		
	'display_plugin_runs'             => \$pbs_config->{DISPLAY_PLUGIN_RUNS},
		"displays which plugins subs are run.",
		'',
		
	'dpt|display_pbs_time'            => \$pbs_config->{DISPLAY_PBS_TIME},
		"Display where time is spend in PBS.",
		'',
		
	'dmt|display_minimum_time=f'        => \$pbs_config->{DISPLAY_MINIMUM_TIME},
		"Don't display time if it is less than this value (in seconds, default 0.5s).",
		'',
		
	'dptt|display_pbs_total_time'            => \$pbs_config->{DISPLAY_PBS_TOTAL_TIME},
		"Display How much time is spend in PBS.",
		'',
		
	'dpu|display_pbsuse'              => \$pbs_config->{DISPLAY_PBSUSE},
		"displays which pbs module is loaded by a 'PbsUse'.",
		'',
		
	'dpuv|display_pbsuse_verbose'     => \$pbs_config->{DISPLAY_PBSUSE_VERBOSE},
		"displays which pbs module is loaded by a 'PbsUse' (full path) and where the the PbsUse call was made.",
		'',
		
	'dput|display_pbsuse_time'        => \$pbs_config->{DISPLAY_PBSUSE_TIME},
		"displays the time spend in 'PbsUse' for each pbsfile.",
		'',
		
	'dputa|display_pbsuse_time_all'    => \$pbs_config->{DISPLAY_PBSUSE_TIME_ALL},
		"displays the time spend in each pbsuse.",
		'',
		
	'dpus|display_pbsuse_statistic'    => \$pbs_config->{DISPLAY_PBSUSE_STATISTIC},
		"displays 'PbsUse' statistic.",
		'',
		
	'display_md5_statistic'            => \$pbs_config->{DISPLAY_MD5_STATISTICS},
		"displays 'MD5' statistic.",
		'',
		
	'display_md5_time'            => \$PBS::Digest::display_md5_time,
		"displays the time it takes to hash each node",
		'',
		
	'build_directory=s'               => \$pbs_config->{BUILD_DIRECTORY},
		'Directory where the build is to be done.',
		'',
		
	'mandatory_build_directory'       => \$pbs_config->{MANDATORY_BUILD_DIRECTORY},
		'PBS will not run unless a build directory is given.',
		'',
		
	'sd|source_directory=s'           => $pbs_config->{SOURCE_DIRECTORIES},
		'Directory where source files can be found. Can be used multiple times.',
		<<EOT,
Source directories are searched in the order they are given. The current 
directory is taken as the source directory if no --SD switch is given on
the command line. 

See also switches: --display_search_info --display_all_alternatives
EOT
	'rule_namespace=s'                => $pbs_config->{RULE_NAMESPACES},
		'Rule name space to be used by DefaultBuild()',
		'',
		
	'config_namespace=s'              => $pbs_config->{CONFIG_NAMESPACES},
		'Configuration name space to be used by DefaultBuild()',
		'',
		
	'save_config=s'                   => \$pbs_config->{SAVE_CONFIG},
		'PBS will save the config, used in each PBS run, in the build directory',
		"Before a subpbs is run, its start config will be saved in a file. PBS will display the filename so you "
		  . "can load it later with '--load_config'. When working with a hirarchical build with configuration "
		  . "defined at the top level, it may happend that you want to run pbs at lower levels but without configuration, "
		  . "PBS will probably fail. Run you system from the top level with '--save_config', then run from the subpbs " 
		  . "with the the saved config as argument to the '--load_config' option.",
		
	'load_config=s'                   => $load_config_closure,
		'PBS will load the given config before running the Pbsfile.',
		'see --save_config.',
		
	'no_config_inheritance'           =>  \$pbs_config->{NO_CONFIG_INHERITANCE},
		'Configuration variables are not iherited by child nodes/package.',
		'',
		
	'fb|force_build'                  => \$pbs_config->{FORCE_BUILD},
		'Debug flags cancel the build pass, this flag re-enables the build pass.',
		'',
		
	'cdabt|check_dependencies_at_build_time' => \$pbs_config->{CHECK_DEPENDENCIES_AT_BUILD_TIME},
		'Skipps the node build if no dependencies have changed or where rebuild to the same state.',
		'',

	'check_only_terminal_nodes' => \$pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES},
		'Skipps the checking of generated artefacts.',
		'',

	'no_build'                     => \$pbs_config->{NO_BUILD},
		'Cancel the build pass. Only the dependency and check passes are run.',
		'',

	'nub|no_user_build'               => \$pbs_config->{NO_USER_BUILD},
		'User defined Build() is ignored if present.',
		'',

	'ns|no_stop'                      => \$pbs_config->{NO_STOP},
		'Continues building even if a node couldn\'t be buid. See --bi.',
		'',
		
	'nh|no_header'                    => \$pbs_config->{DISPLAY_NO_STEP_HEADER},
		'PBS won\'t display the steps it is at. (Depend, Check, Build).',
		'',

	'no_external_link'                => \$pbs_config->{NO_EXTERNAL_LINK},
		'Dependencies Linking from other Pbsfile stops the build if any local rule can match.',
		'',

	'nsi|no_subpbs_info'              => \$pbs_config->{NO_SUBPBS_INFO},
		'Dependency information will be displayed on the same line for all depend.',
		'',
		
	'ds|display_subpbs_start'         => \$pbs_config->{DISPLAY_DEPENDENCY_INFO},
		'Display a message when depending a node in a subpbs.',
		'',
		
	'dsi|display_subpbs_start_info'                => \$pbs_config->{SUBPBS_FILE_INFO},
		'PBS displays the sub pbs file name.',
		'',
		
	'allow_virtual_to_match_directory'    => \$pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY},
		'PBS won\'t display any warning if a virtual node matches a directory name.',
		'',
		
	'nli|no_link_info'                => \$pbs_config->{NO_LINK_INFO},
		'PBS won\'t display which dependency node are linked instead of generated.',
		'',
	'no_warning_matching_with_zero_dependencies' => \$pbs_config->{NO_WARNING_MATCHING_WITH_ZERO_DEPENDENCIES},
		'PBS won\'t warn if a node has no dependencies but a matching rule.',
		'',
		
	'nlmi|no_local_match_info'        => \$pbs_config->{NO_LOCAL_MATCHING_RULES_INFO},
		'PBS won\'t display a warning message if a linked node matches local rules.',
		'',
		
	'display_no_dependencies_ok'        => \$pbs_config->{DISPLAY_NO_DEPENDENCIES_OK},
		'Display a message if a node was tagged has having no dependencies with HasNoDependencies.',
		"Non source files (nodes with digest) are checked for dependencies since they need to be build from something, "
		. "some nodes are generated from non files or don't always have dependencies as for C cache which dependency file "
		. "is created on the fly if it doens't exist.",

	'display_duplicate_info'           => \$pbs_config->{DISPLAY_DUPLICATE_INFO},
		'PBS will display which dependency are duplicated for a node.',
		'',
	
	'ntii|no_trigger_import_info'     => \$pbs_config->{NO_TRIGGER_IMPORT_INFO},
		'PBS won\'t display which triggers are imported in a package.',
		'',
	
	'nhnd|no_has_no_dependencies=s'     => $pbs_config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX},
		'PBS won\'t display warning if node does not have dependencies.',
		'',
		
	'sc|silent_commands'              => \$PBS::Shell::silent_commands,
		'shell commands are not echoed to the console.',
		'',
		
	'sco|silent_commands_output'       => \$PBS::Shell::silent_commands_output,
		'shell commands output are not displayed, except if an error occures.',
		'',
		
	'qow|query_on_warning'            => \$PBS::Output::query_on_warning,
		'When displaying a warning, Pbs will query you for continue or stop.',
		'',
		
	'dm|dump_maxdepth=i'              => \$pbs_config->{MAX_DEPTH},
		'Maximum depth of the structures displayed by pbs.',
		'',
		
	'di|dump_indentation=i'           => \$pbs_config->{INDENT_STYLE},
		'Data dump indent style (0-1-2).',
		'',
		
	'ni|node_information=s'           => $pbs_config->{DISPLAY_NODE_INFO},
		'Display information about the node matching the given regex before the build.',
		'',
	
	'nonil|no_node_info_links'  => \$pbs_config->{NO_NODE_INFO_LINKS},
		'Pbs inserts node_info files links in info_files and logs, disable it',
		'',
	
	'lni|log_node_information=s'      => $pbs_config->{LOG_NODE_INFO},
		'Log information about nodes matching the given regex before the build.',
		'',
		
	'nbn|node_build_name'             => \$pbs_config->{DISPLAY_NODE_BUILD_NAME},
		'Display the build name in addition to the logical node name.',
		'',
		
	'no|node_origin'                  => \$pbs_config->{DISPLAY_NODE_ORIGIN},
		'Display where the node has been inserted in the dependency tree.',
		'',
		
	'np|node_parents'            => \$pbs_config->{DISPLAY_NODE_PARENTS},
		"Display the node's parents.",
		'',
		
	'nd|node_dependencies'            => \$pbs_config->{DISPLAY_NODE_DEPENDENCIES},
		'Display the dependencies for a node.',
		'',
		
	'ne|node_environment=s'            => $pbs_config->{DISPLAY_NODE_ENVIRONMENT},
		'Display the environment variables for the nodes matching the regex.',
		'',
		
	'ner|node_environment_regex=s'      => $pbs_config->{NODE_ENVIRONMENT_REGEX},
		'Display the environment variables  matching the regex.',
		'',
		
	'nc|node_build_cause'             => \$pbs_config->{DISPLAY_NODE_BUILD_CAUSE},
		'Display why a node is to be build.',
		'',
		
	'nr|node_build_rule'              => \$pbs_config->{DISPLAY_NODE_BUILD_RULES},
		'Display the rules used to depend a node (rule defining a builder ar tagged with [B].',
		'',
		
	'nb|node_builder'                  => \$pbs_config->{DISPLAY_NODE_BUILDER},
		'Display the rule which defined the Builder and which command is being run.',
		'',
		
	'nconf|node_config'                => \$pbs_config->{DISPLAY_NODE_CONFIG},
		'Display the config used to build a node.',
		'',
		
	'npbc|node_build_post_build_commands'  => \$pbs_config->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS},
		'Display the post build commands for each node.',
		'',

	'ppbc|pbs_build_post_build_commands'  => \$pbs_config->{DISPLAY_PBS_POST_BUILD_COMMANDS},
		'Display the Pbs build post build commands.',
		'',

	'o|origin'                        => \$pbs_config->{ADD_ORIGIN},
		'PBS will also display the origin of rules in addition to their names.',
		<<EOT,
The origin contains the following information:
	* Name
	* Package
	* Namespace
	* Definition file
	* Definition line
EOT

	'j|jobs=i'                        => \$pbs_config->{JOBS},
		'Maximum number of commands run in parallel.',
		'',
		
	'jdoe|jobs_die_on_errors=i'       => \$pbs_config->{JOBS_DIE_ON_ERROR},
		'0 (default) finish running jobs. 1 die immediatly. 2 build as much as possible.',
		'',
		
	'cj|check_jobs=i'                      => \$pbs_config->{CHECK_JOBS},
		'Maximum number of checker run in parallel.',
		'Depending on the amount of nodes and their size, running checks in parallel can reduce check time, YMMV.',

	'ubs|use_build_server=s'   => \$pbs_config->{LIGHT_WEIGHT_FORK},
		'If set, Pbs will connect to a build server for all the nodes that use shell commands to build'
			. "\n this expects the address of the build server. ex : localhost:12_000 ",
		'Forking a full Pbs is expensive, the build server is light weight.',
		
	'distribute=s'                   => \$pbs_config->{DISTRIBUTE},
		'Define where to distribute the build.',
		'The file should return a list of hosts in the format defined by the default distributor '
		 .'or define a distributor.',
		 
	'display_shell_info'                   => \$pbs_config->{DISPLAY_SHELL_INFO},
		'Displays which shell executes a command.',
		'',
		
	'dbi|display_builder_info'                 => \$pbs_config->{DISPLAY_BUILDER_INFORMATION},
		'Displays if a node is build by a perl sub or shell commands.',
		'',
		
	'time_builders'                   => \$pbs_config->{TIME_BUILDERS},
		'Displays the total time a builders took to run.',
		'',
		
	'dji|display_jobs_info'           => \$pbs_config->{DISPLAY_JOBS_INFO},
		'PBS will display extra information about the parallel build.',
		'',

	'djr|display_jobs_running'        => \$pbs_config->{DISPLAY_JOBS_RUNNING},
		'PBS will display which nodes are under build.',
		'',

	'l|log|create_log'                => \$pbs_config->{CREATE_LOG},
		'Create a log for the build',
		'Node build output is always kept in the build directory.',
		
	'log_tree'                        => \$pbs_config->{LOG_TREE},
		'Add a tree dump to the log, an option as during incremental build this takes most of the time.',
		'',
		
	'log_html|create_log_html'              => \$pbs_config->{CREATE_LOG_HTML},
		'create a html log for each node, implies --create_log ',
		'',
		
	#----------------------------------------------------------------------------------
		
	'dpos|display_original_pbsfile_source'      => \$pbs_config->{DISPLAY_PBSFILE_ORIGINAL_SOURCE},
		'Display original Pbsfile source.',
		'',
		
	'dps|display_pbsfile_source'      => \$pbs_config->{DISPLAY_PBSFILE_SOURCE},
		'Display Modified Pbsfile source.',
		'',
		
	'dpc|display_pbs_configuration=s'=> $pbs_config->{DISPLAY_PBS_CONFIGURATION},
		'Display the pbs configuration matching  the regex.',
		'',
		
	'dec|display_error_context'       => \$PBS::Output::display_error_context,
		'When set and if an error occures in a Pbsfile, PBS will display the error line.',
		'',
		
	'dpl|display_pbsfile_loading'     => \$pbs_config->{DISPLAY_PBSFILE_LOADING},
		'Display which pbsfile is loaded as well as its runtime package.',
		'',
		
	'dspd|display_sub_pbs_definition' => \$pbs_config->{DISPLAY_SUB_PBS_DEFINITION},
		'Display sub pbs definition.',
		'',
		
	'display_nodes_per_pbsfile'        => \$pbs_config->{DISPLAY_NODES_PER_PBSFILE},
		'Display how many nodes where added by each pbsfile run.',
		'',
		
	'de|display_depend_end'        => \$pbs_config->{DISPLAY_DEPEND_END},
		'Display when a depend ends.',
		'',
		
	'display_too_many_nodes_warning=i'        => \$pbs_config->{DISPLAY_TOO_MANY_NODE_WARNING},
		'Display a warning when a pbsfile adds too many nodes.',

		'',
	'display_rule_to_order'          => \$pbs_config->{DISPLAY_RULES_TO_ORDER},
		'Display that there are rules order.',
		'',
		
	'display_rule_order'          => \$pbs_config->{DISPLAY_RULES_ORDER},
		'Display the order rules.',
		'',
		
	'display_rule_ordering'          => \$pbs_config->{DISPLAY_RULES_ORDERING},
		'Display the pbsfile used to order rules and the rules order.',
		'',
		
	'maximum_rule_recursion'          => \$pbs_config->{MAXIMUM_RULE_RECURSION},
		'Set the maximum rule recusion before pbs, aborts the build',
		'',
		
	'rule_recursion_warning'          => \$pbs_config->{RULE_RECURSION_WARNING},
		'Set the level at which pbs starts warning aabout rule recursion',
		'',
		
	'dur|display_used_rules'          => \$pbs_config->{DISPLAY_USED_RULES},
		'Display the rules used during the dependency pass.',
		'',
		
	'durno|display_used_rules_name_only' => \$pbs_config->{DISPLAY_USED_RULES_NAME_ONLY},
		'Display the names of the rules used during the dependency pass.',
		'',
		
	'dar|display_all_rules'           => \$pbs_config->{DISPLAY_ALL_RULES},
		'Display all the registred rules.',
		'If you run a hierarchical build, these rules will be dumped every time a package runs a dependency step.',
		
	'dc|display_config'               => \$pbs_config->{DISPLAY_CONFIGURATION},
		'Display the config used during a Pbs run (simplified and from the used config namespaces only).',
		'',
		
	'dcs|display_config_start'        => \$pbs_config->{DISPLAY_CONFIGURATION_START},
		'Display the config to be used in a Pbs run before loading the Pbsfile',
		'',
		
        'display_config_delta'            => \$pbs_config->{DISPLAY_CONFIGURATION_DELTA},
		'Display the delta between the parent config and the config after the Pbsfile is run.',
		'',
					
	'dcn|display_config_namespaces'   => \$pbs_config->{DISPLAY_CONFIGURATION_NAMESPACES},
		'Display the config namespaces used during a Pbs run (even unused config namspaces).',
		'',
		
	'dac|display_all_configs'         => \$pbs_config->{DEBUG_DISPLAY_ALL_CONFIGURATIONS},
		'(DF). Display all configurations.',
		'',
		
	'dam|display_configs_merge'       => \$pbs_config->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE},
		'(DF). Display how configurations are merged.',
		'',
		
	'display_package_configuration'   => \$pbs_config->{DISPLAY_PACKAGE_CONFIGURATION},
		'If PACKAGE_CONFIGURATION for a subpbs exists, it will be displayed if this option is set (also displayed when --dc is set)',
		'',
		
	'no_silent_override'         => \$pbs_config->{NO_SILENT_OVERRIDE},
		'Makes all SILENT_OVERRIDE configuration visible.',
		'',
		
	'display_subpbs_search_info'         => \$pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO},
		'Display information about how the subpbs files are found.',
		'',
		
	'display_all_subpbs_alternatives'         => \$pbs_config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES},
		'Display all the subpbs files that could match.',
		'',
		
	'dsd|display_source_directory'    => \$pbs_config->{DISPLAY_SOURCE_DIRECTORIES},
		'display all the source directories (given through the -sd switch ot the Pebsfile).',
		'',
		
	'display_search_info'         => \$pbs_config->{DISPLAY_SEARCH_INFO},
		'Display the files searched in the source directories. See --daa.',
		<<EOT,
PBS will display its search for source files. 

  $> pwd
  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05

  $>perl pbs.pl -o --display_search_info all
  No Build directory! Using '/home/nadim/Dev/PerlModules/PerlBuildSystem-0.05'.
  No source directory! Using '/home/nadim/Dev/PerlModules/PerlBuildSystem-0.05'.
  ...

  **Checking**
  Trying ./all @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/all: not found.
  Trying ./HERE.o @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/HERE.o: not found.
  Trying ./HERE.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/HERE.c: not found.
  Trying ./HERE.h @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/HERE.h: not found.
  Final Location for ./HERE.h @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/HERE.h
  Final Location for ./HERE.c @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/HERE.c
  Final Location for ./HERE.o @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/HERE.o
  ...
  
See switch: --display_all_alternatives.
EOT

	'daa|display_all_alternates'      => \$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
		'Display all the files found in the source directories.',
		<<EOT,
When PBS searches for a node in the source directories, it stops at the first found node.
if you have multiple source directories, you might want to see the files 'PBS' didn't choose.
The first one will still be choosen.

  $>perl pbs.pl -o -sd ./d1 -sd ./d2 -sd . -dsi -daa -c all
  ...

  Trying ./a.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/d1/a.c: Relocated. s: 0 t: 15-2-2003 20:54:57
  Trying ./a.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/d2/a.c: NOT USED. s: 0 t: 15-2-2003 20:55:0
  Trying ./a.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/a.c: not found.
  ...

  Final Location for ./a.h @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/a.h
  Final Location for ./a.c @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/a.c
EOT
		
	#----------------------------------------------------------------------------------
	'dr|display_rules'                => \$pbs_config->{DEBUG_DISPLAY_RULES},
		'(DF) Display which rules are registred. and which rule packages are queried.',
		'',
		
	'drd|display_rule_definition'     => \$pbs_config->{DEBUG_DISPLAY_RULE_DEFINITION},
		'(DF) Display the definition of each registrated rule.',
		'',
		
	'drs|display_rule_statistics'     => \$pbs_config->{DEBUG_DISPLAY_RULE_STATISTICS},
		'(DF) Display rule statistics after each pbs run.',
		'',
		
	'dtr|display_trigger_rules'       => \$pbs_config->{DEBUG_DISPLAY_TRIGGER_RULES},
		'(DF) Display which triggers are registred. and which trigger packages are queried.',
		'',
		
	'dtrd|display_trigger_rule_definition' => \$pbs_config->{DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION},
		'(DF) Display the definition of each registrated trigger.',
		'',
		
	# -------------------------------------------------------------------------------	
	'dpbcr|display_post_build_commands_registration' => \$pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION},
		'(DF) Display the registration of post build commands.',
		'',
		
	'dpbcd|display_post_build_command_definition' => \$pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION},
		'(DF) Display the definition of post build commands when they are registered.',
		'',
		
	'dpbc|display_post_build_commands' => \$pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS},
		'(DF) Display which post build command will be run for a node.',
		'',
		
	'dpbcre|display_post_build_result'  => \$pbs_config->{DISPLAY_POST_BUILD_RESULT},
		'Display the result code and message returned buy post build commands.',
		'',
		
	#-------------------------------------------------------------------------------	
	'dd|display_dependencies'         => \$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES},
		'(DF) Display the dependencies for each file processed.',
		'',
		
	'ddl|display_dependencies_long'         => \$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG},
		'(DF) Display one dependency perl line.',
		'',
		
	'ddt|display_dependency_time'     => \$pbs_config->{DISPLAY_DEPENDENCY_TIME},
		' Display the time spend in each Pbsfile.',
		'',
		
	'dct|display_check_time'          => \$pbs_config->{DISPLAY_CHECK_TIME},
		' Display the time spend checking the dependency tree.',
		'',
		
	'dre|dependency_result'           => \$pbs_config->{DISPLAY_DEPENDENCY_RESULT},
		'Display the result of each dependency step.',
		'',
		
	'ddrr|display_dependencies_regex=s'=> $pbs_config->{DISPLAY_DEPENDENCIES_REGEX},
		'Define the regex used to qualify a dependency for display.',
		'',
		
	'dnsr|display_node_subs_run'      => \$pbs_config->{DISPLAY_NODE_SUBS_RUN},
		'Show when a node sub is run.',
		'',

	'ddrd|display_dependency_rule_definition' => \$pbs_config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION},
		'Display the definition of the rule that generates a dependency.',
		'',
		
	'ddr|display_dependency_regex'        => \$pbs_config->{DEBUG_DISPLAY_DEPENDENCY_REGEX},
		'(DF) Display the regex used to depend a node.',
		'',
		
	'ddmr|display_dependency_matching_rule' => \$pbs_config->{DISPLAY_DEPENDENCY_MATCHING_RULE},
		'Display the rule which matched the node.',
		'',
		
	'dlmr|display_link_matching_rule' => \$pbs_config->{DISPLAY_LINK_MATCHING_RULE},
		'Display the rule which matched the node that is being linked.',
		'',
		
	'dtin|display_trigger_inserted_nodes' => \$pbs_config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES},
		'(DF) Display the nodes inserted because of a trigger.',
		'',
		
	'dt|display_trigged'              => \$pbs_config->{DEBUG_DISPLAY_TRIGGED_DEPENDENCIES},
		'(DF) Display the files that need to be rebuild and why they need so.',
		'',
		
	'display_digest_exclusion'        => \$pbs_config->{DISPLAY_DIGEST_EXCLUSION},
		'Display when an exclusion or inclusion rule for a node matches.',
		'',
		
	'display_digest'                  => \$pbs_config->{DISPLAY_DIGEST},
		'Display the expected and the actual digest for each node.',
		'',
		
	'dddo|display_different_digest_only'  => \$pbs_config->{DISPLAY_DIFFERENT_DIGEST_ONLY},
		'Only display when a digest are diffrent.',
		'',
		
	'devel_no_distribution_check'  => \$pbs_config->{DEVEL_NO_DISTRIBUTION_CHECK},
		'A development flag, not for user.',
		<<EOT,
Pbs checks its distribution when building and rebuilds everything if it has changed.

While developping we are constantly changing the distribution but want to see the effect
of the latest change without rebuilding everything which makes finding the effect of the
latest change more difficult.
EOT

	'wnmw|warp_no_md5_warning'             => \$pbs_config->{WARP_NO_DISPLAY_DIGEST_FILE_NOT_FOUND},
		'Do not display a warning if the file to compute hash for does not exist during warp verification.',
		'',
		
	'dfc|display_file_check'   => \$pbs_config->{DISPLAY_FILE_CHECK},
		'Display hash checking for individual files.',
		'',
		
	'display_cyclic_tree'             => \$pbs_config->{DEBUG_DISPLAY_CYCLIC_TREE},
		'(DF) Display the portion of the dependency tree that is cyclic',
		'',
		
	'no_source_cyclic_warning'             => \$pbs_config->{NO_SOURCE_CYCLIC_WARNING},
		'No warning is displayed if a cycle involving source files is found.',
		'',
		
	'die_source_cyclic_warning'             => \$pbs_config->{DIE_SOURCE_CYCLIC_WARNING},
		'Die if a cycle involving source files is found (default is warn).',
		'',
		
	'tt|text_tree'                  => \$pbs_config->{DEBUG_DISPLAY_TEXT_TREE},
		'(DF) Display the dependency tree using a text dumper',
		'',
		
	'ttmr|text_tree_match_regex:s'      => $pbs_config->{DISPLAY_TEXT_TREE_REGEX},
		'limits how many trees are displayed.',
		'',
		
	'ttmm|text_tree_match_max:i'      => \$pbs_config->{DISPLAY_TEXT_TREE_MAX_MATCH},
		'limits how many trees are displayed.',
		'',
		
	'ttf|text_tree_filter=s'          => $pbs_config->{DISPLAY_TREE_FILTER},
		'(DF) List the fields that are to be displayed when -tt is active. The switch can be used multiple times.',
		'',
		
	'tta|text_tree_use_ascii'         => \$pbs_config->{DISPLAY_TEXT_TREE_USE_ASCII},
		'Use ASCII characters instead for Ansi escape codes to draw the tree.',
		'',
		
	'ttdhtml|text_tree_use_dhtml=s'     => \$pbs_config->{DISPLAY_TEXT_TREE_USE_DHTML},
		'Generate a dhtml dump of the tree in the specified file.',
		'',
		
	'ttmd|text_tree_max_depth=i'       => \$pbs_config->{DISPLAY_TEXT_TREE_MAX_DEPTH},
		'Limit the depth of the dumped tree.',
		'',
		
	'tno|tree_name_only'               => \$pbs_config->{DEBUG_DISPLAY_TREE_NAME_ONLY},
		'(DF) Display the name of the nodes only.',
		'',
		
	'tda|tree_depended_at'               => \$pbs_config->{DEBUG_DISPLAY_TREE_DEPENDED_AT},
		'(DF) Display which Pbsfile was used to depend each node.',
		'',
		
	'tia|tree_inserted_at'               => \$pbs_config->{DEBUG_DISPLAY_TREE_INSERTED_AT},
		'(DF) Display where the node was inserted.',
		'',
		
	'tnd|tree_display_no_dependencies'        => \$pbs_config->{DEBUG_DISPLAY_TREE_NO_DEPENDENCIES},
		'(DF) Don\'t show child nodes data.',
		'',
		
	'tad|tree_display_all_data'        => \$pbs_config->{DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA},
		'Unset data within the tree are normally not displayed. This switch forces the display of all data.',
		'',
		
	'tnb|tree_name_build'               => \$pbs_config->{DEBUG_DISPLAY_TREE_NAME_BUILD},
		'(DF) Display the build name of the nodes. Must be used with --tno',
		'',
		
	'trigger_none'                        => \$pbs_config->{DEBUG_TRIGGER_NONE},
		'(DF) As if no node triggered, see --trigger',
		'',
		
	'trigger=s'                           => $pbs_config->{TRIGGER},
		'(DF) Force the triggering of a node if you want to check its effects.',
		'',
		
	'trigger_list=s'                       => \$pbs_config->{DEBUG_TRIGGER_LIST},
		'(DF) Points to a file containing trigers.',
		'',

	'display_trigger'                       => \$pbs_config->{DEBUG_DISPLAY_TRIGGER},
		'(DF) display which files are processed and triggered',
		'',

	'display_trigger_match_only'            => \$pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY},
		'(DF) display only files which are triggered',
		'',

	'tntr|tree_node_triggered_reason'   => \$pbs_config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON},
		'(DF) Display why a node is to be rebuild.',
		'',
		
	#-------------------------------------------------------------------------------	
	'gtg|generate_tree_graph=s'       => \$pbs_config->{GENERATE_TREE_GRAPH},
		'Generate a graph for the dependency tree. Give the file name as argument.',
		'',
		
	'gtg_p|generate_tree_graph_package'=> \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE},
		'Groups the node by definition package.',
		'',
		
	'gtg_canonical=s'=> \$pbs_config->{GENERATE_TREE_GRAPH_CANONICAL},
		'Generates a canonical dot file.',
		'',
		
	'gtg_format=s'                        => \$pbs_config->{GENERATE_TREE_GRAPH_FORMAT},
		'chose graph format between: svg (default), ps, png.',
		'',
		
	'gtg_html=s'=> \$pbs_config->{GENERATE_TREE_GRAPH_HTML},
		'Generates a set of html files describing the build tree.',
		'',
		
	'gtg_html_frame'=> \$pbs_config->{GENERATE_TREE_GRAPH_HTML_FRAME},
		'The use a frame in the graph html.',
		'',
		
	'gtg_snapshots=s'=> \$pbs_config->{GENERATE_TREE_GRAPH_SNAPSHOTS},
		'Generates a serie of snapshots from the build.',
		'',
		
	'gtg_cn=s'                         => $pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_NODE},
		'The node given as argument and its dependencies will be displayed as a single unit. Multiple gtg_cn allowed.',
		'',
		
	'gtg_cr=s'                         => $pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX},
		'Put nodes matching the given regex in a node named as the regx. Multiple gtg_cr allowed.',
		<<'EOT',
$> pbs -gtg_cr '\.c$' --gtg

create a graph where all the .c files are clustered in a single node named '.c$'
EOT
	'gtg_crl=s'                         => \$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST},
		'List of regexes, as if you gave multiple --gtg_cr, one per line',
		'',
		
	'gtg_sd|generate_tree_graph_source_directories' => \$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES},
		'As generate_tree_graph but groups the node by source directories, uncompatible with --generate_tree_graph_package.',
		'',
		
	'gtg_exclude|generate_tree_graph_exclude=s'       => $pbs_config->{GENERATE_TREE_GRAPH_EXCLUDE},
		"Exclude nodes and their dependenies from the graph.",
		'',
		
	'gtg_include|generate_tree_graph_include=s' => $pbs_config->{GENERATE_TREE_GRAPH_INCLUDE},
		"Forces nodes and their dependencies back into the graph.",
		'Ex: pbs -gtg tree -gtg_exclude "*.c" - gtg_include "name.c".',
		
	'gtg_bd'                           => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY},
		'The build directory for each node is displayed.',
		'',
		
	'gtg_rbd'                          => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY},
		'The build directory for the root is displayed.',
		'',
		
	'gtg_tn'                           => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES},
		'Node inserted by Triggerring are also displayed.',
		'',
		
	'gtg_config'                       => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG},
		'Configs are also displayed.',
		'',
		
	'gtg_config_edge'                  => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE},
		'Configs are displayed as well as an edge from the nodes using it.',
		'',
		
	'gtg_pbs_config'                   => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG},
		'Package configs are also displayed.',
		'',
		
	'gtg_pbs_config_edge'              => \$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE},
		'Package configs are displayed as well as an edge from the nodes using it.',
		'',
		
	'gtg_gm|generate_tree_graph_group_mode=i' => \$pbs_config->{GENERATE_TREE_GRAPH_GROUP_MODE},
		'Set the grouping mode.0 no grouping, 1 main tree is grouped (default), 2 each tree is grouped.',
		'',
		
	'gtg_spacing=f'                    => \$pbs_config->{GENERATE_TREE_GRAPH_SPACING},
		'Multiply node spacing with given coefficient.',
		'',
		
	'gtg_printer|generate_tree_graph_printer'=> \$pbs_config->{GENERATE_TREE_GRAPH_PRINTER},
		'Non triggerring edges are displayed as dashed lines.',
		'',
		
	'gtg_sn|generate_tree_graph_start_node=s'       => \$pbs_config->{GENERATE_TREE_GRAPH_START_NODE},
		'Generate a graph from the given node.',
		'',
		
	'a|ancestors=s'                   => \$pbs_config->{DEBUG_DISPLAY_PARENT},
		'(DF) Display the ancestors of a file and the rules that inserted them.',
		'',
		
	'dbsi|display_build_sequencer_info'      => \$pbs_config->{DISPLAY_BUILD_SEQUENCER_INFO},
		'Display information about which node is build.',
		'',

	'dbs|display_build_sequence'      => \$pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE},
		'(DF) Dumps the build sequence data.',
		'',
		
	'dbss|display_build_sequence_simple'      => \$pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE},
		'(DF) List the nodes to be build.',
		'',
		
	'save_build_sequence_simple=s'      => \$pbs_config->{SAVE_BUILD_SEQUENCE_SIMPLE},
		'Save a list of nodes to be build to a file.',
		'',
		
	'f|files|nodes'                   => \$pbs_config->{DISPLAY_FILE_LOCATION},
		'Show all the nodes in the current_dependency tree and their final location.',
		'In warp only shows the nodes that have triggered, see option nodes_all for all nodes',

	'fa|files_all|nodes_all'          => \$pbs_config->{DISPLAY_FILE_LOCATION_ALL},
		'Show all the nodes in the current_dependency tree and their final location.',
		'',

	'bi|build_info=s'                 => $pbs_config->{DISPLAY_BUILD_INFO},
		'Options: --b --d --bc --br. A file or \'*\' can be specified. No Build is done.',
		'',
		
	'nbh|no_build_header'             => \$pbs_config->{DISPLAY_NO_BUILD_HEADER},
		"Don't display the name of the node to be build.",
		'',
		
	'dpb0|display_nop_progress_bar'        => \$pbs_config->{DISPLAY_PROGRESS_BAR_NOP},
		"Force silent build mode and displays an empty progress bar.",
		'',

	'dpb1|display_progress_bar'        => \$pbs_config->{DISPLAY_PROGRESS_BAR},
		"Force silent build mode and displays a progress bar. This is Pbs default, see --ndpb.",
		'',

	'dpb2|display_progress_bar_file'  => \$pbs_config->{DISPLAY_PROGRESS_BAR_FILE},
		"Built node names are displayed above the progress bar",
		'',

	'dpb3|display_progress_bar_process'  => \$pbs_config->{DISPLAY_PROGRESS_BAR_PROCESS},
		"A progress per build process is displayed above the progress bar",
		'',

	'ndpb|display_no_progress_bar'    => \$pbs_config->{DISPLAY_NO_PROGRESS_BAR},
		"Verbose build mode.",
		'',
		
	'ndpbm|display_no_progress_bar_minimum'  => \$pbs_config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM},
		"Slightly less verbose build mode.",
		'',
		
	'bre|display_build_result'       => \$pbs_config->{DISPLAY_BUILD_RESULT},
		'Shows the result returned by the builder.',
		'',
		
	'box_node' => \$pbs_config->{BOX_NODE},
		'Display a colored margin for each node display.',
		'',

	'bnir|build_and_display_node_information_regex=s' => $pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX},
		'Only display information for matching nodes.',
		'',

	'bni_result' => \$pbs_config->{BUILD_DISPLAY_RESULT},
		'display node header and build result even if not matched by --bnir.',
		'',

	'bni|build_and_display_node_information' => \$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO},
		'Display information about the node to be build; see also --bn|build_node_information.',
		<<EOT,
these switches are turned on:
	'no|node_origin'
	'nd|nod_dependencies'
	'nc|node_build_cause' 
	'nr|node_build_rule' 
	'nb|node_builder'
	'npbc|node_build_post_build_commands'

You may want to also add:
	'np|mode_parents'
	'nbn|node_build_name' 
	'nconf|node_config'
	'nil|node_information_located'
EOT

	'verbosity=s'                 => $pbs_config->{VERBOSITY},
		'Used in user defined modules.',
		<<EOT,
-- verbose is not used by PBS. It is intended for user defined modules.

I recomment to use the following settings:

0 => Completely silent (except for errors)
1 => Display what is to be done
2 => Display serious warnings
3 => Display less serious warnings
4 => Display display more information about what is to be done
5 => Display detailed information
6 =>
7 => Debug information level 1
8 => Debug information level 2
9 => All debug information

'string' => user defined verbosity level (ex 'my_module_9')
EOT

	'u|user_option=s'                 => $pbs_config->{USER_OPTIONS},
		'options to be passed to the Build sub.',
		'',
		
	'D=s'                             => $pbs_config->{COMMAND_LINE_DEFINITIONS},
		'Command line definitions.',
		'',

	'ke|keep_environment=s'           => $pbs_config->{KEEP_ENVIRONMENT},
		"Pbs empties %ENV, user --ke 'regex' to keep specific variables.",
		'',

	'display_environment_info'       => \$pbs_config->{DISPLAY_ENVIRONMENT_INFO},
		"Display a statistics about environment variables",
		'',

	'display_environment'            => \$pbs_config->{DISPLAY_ENVIRONMENT},
		"Display which environment variables are kept and discarded",
		'',

	'display_environment_kept'       => \$pbs_config->{DISPLAY_ENVIRONMENT_KEPT},
		"Only display the evironment variables kept",
		'',

	#----------------------------------------------------------------------------------
	
	'debug:s'                         => $pbs_config->{BREAKPOINTS},
		'Enable debug support A startup file defining breakpoints can be given.',
		'',

	'debug_display_breakpoint_header' => \$pbs_config->{DISPLAY_BREAKPOINT_HEADER},
		'Display a message when a breakpoint is run.',
		'',

	'dump'                            => \$pbs_config->{DUMP},
		'Dump an evaluable tree.',
		'',
		
	#----------------------------------------------------------------------------------
	
	'dwfn|display_warp_file_name'      => \$pbs_config->{DISPLAY_WARP_FILE_NAME},
		"Display the name of the warp file on creation or use.",
		'',
		
	'display_warp_time'                => \$pbs_config->{DISPLAY_WARP_TIME},
		"Display the time spend in warp creation or use.",
		'',
		
	'w|warp=s'             => \$pbs_config->{WARP},
		"specify which warp to use.",
		'',
		
	'warp_human_format'    => \$pbs_config->{WARP_HUMAN_FORMAT},
		"Generate warp file in a readable format.",
		'',
		
	'no_pre_build_warp'             => \$pbs_config->{NO_PRE_BUILD_WARP},
		"no pre-build warp will be generated.",
		'',
		
	'no_post_build_warp'             => \$pbs_config->{NO_POST_BUILD_WARP},
		"no post-build warp will be generated.",
		'',
		
	'no_warp'             => \$pbs_config->{NO_WARP},
		"no warp will be used.",
		'',
		
	'dww|display_warp_generated_warnings'  => \$pbs_config->{DISPLAY_WARP_GENERATED_WARNINGS},
		"When doing a warp build, linking info and local rule match info are disable. this switch re-enables them.",
		'',
		
	'display_warp_checked_nodes'  => \$pbs_config->{DISPLAY_WARP_CHECKED_NODES},
		"Display which nodes are contained in the warp tree and their status.",
		'',
			
	'display_warp_checked_nodes_fail_only'  => \$pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY},
		"Display which nodes, in the warp tree, has a different MD5.",
		'',
			
	'display_warp_removed_nodes'  => \$pbs_config->{DISPLAY_WARP_REMOVED_NODES},
		"Display which nodes are removed during warp.",
		'',
			
	'display_warp_triggered_nodes'  => \$pbs_config->{DISPLAY_WARP_TRIGGERED_NODES},
		"Display which nodes are removed from the warp tree and why.",
		'',

	#----------------------------------------------------------------------------------
	
	'post_pbs=s'                        => $pbs_config->{POST_PBS},
		"Run the given perl script after pbs. Usefull to generate reports, etc.",
		'',
		
	) ;

my @registred_flags_and_help_pointing_to_pbs_config ;
my @rfh = @registred_flags_and_help ;

while( my ($switch, $variable, $help1, $help2) = splice(@rfh, 0, 4))
	{
	if('' eq ref $variable)
		{
		$variable = \$pbs_config->{$variable} ;
		}
		
	push @registred_flags_and_help_pointing_to_pbs_config, $switch, $variable, $help1, $help2 ;
	}

return(@flags_and_help, @registred_flags_and_help_pointing_to_pbs_config) ;
}

#-------------------------------------------------------------------------------

my $message_displayed = 0 ; # called twice but want a single message

sub LoadConfig
{
my ($switch, $file_name, $pbs_config) = @_ ;

$pbs_config->{LOAD_CONFIG} = $file_name ;

$file_name = "./$file_name" if( $file_name !~ /^\\/ && -e $file_name) ;

my ($loaded_pbs_config, $loaded_config) = do $file_name ;

if(! defined $loaded_config || ! defined $loaded_pbs_config)
	{
	die WARNING2 "Config: error loading file'$file_name'\n" ;
	}
else
	{
	# add the configs
	PrintInfo "Config: loading '$file_name'\n" unless $message_displayed ;
	$message_displayed++ ;

	$pbs_config->{LOADED_CONFIG} = $loaded_config ;
	}
}

#-------------------------------------------------------------------------------

sub DisplaySwitchHelp
{
my $switch = shift ;

my @flags_and_help = GetSwitches() ;
my $help_was_displayed = 0 ;

for (my $i = 0 ; $i < @flags_and_help; $i += 4)
	{
	my ($switch_definition, $help_text, $long_help_text) = ($flags_and_help[$i], $flags_and_help[$i + 2], $flags_and_help[$i + 3]) ;
	
	for (split /\|/, $switch_definition)
		{
		if(/^$switch$/)
			{
			print(ERROR("$switch_definition: ")) ;
			print(INFO( "$help_text\n")) ;
			print(INFO( "\n$long_help_text\n")) unless $long_help_text eq '' ;
			
			$help_was_displayed++ ;
			}
		}
		
	last if $help_was_displayed ;
	}
	
print(ERROR("Unrecognized switch '$switch'.\n")) unless $help_was_displayed ;	
}

#-------------------------------------------------------------------------------

sub DisplayUserHelp
{
my $Pbsfile = shift ;
my $display_pbs_pod = shift ;
my $raw = shift ;

eval "use Pod::Select ; use Pod::Text;" ;
die $@ if $@ ;

if(defined $Pbsfile && $Pbsfile ne '')
	{
	open INPUT, '<', $Pbsfile or die "Can't open '$Pbsfile'!\n" ;
	open my $out, '>', \my $all_pod or die "Can't redirect to scalar output: $!\n";
	
	my $parser = new Pod::Select();
	$parser->parse_from_filehandle(\*INPUT, $out);
	
	$all_pod .= '=cut' ; #add the =cut taken away by above parsing
	
	my ($pbs_pod, $other_pod) = ('', '') ;
	my $pbs_pod_level = 1_000_000 ;  #invalid level
	
	while($all_pod =~ /(^=.*?(?=\n=))/smg)
		{
		my $section = $1 ;
		
		my $section_level = $1 if($section =~ /=head([0-9])/) ;
		$section_level ||= 1_000_000 ;
		
		if($section =~ s/^=for PBS STOP\s*//i)
			{
			$pbs_pod_level = 1_000_000 ;
			next ;
			}
				
		if(($pbs_pod_level && $pbs_pod_level < $section_level) || $section =~ /^=for PBS/i)
			{
			$pbs_pod_level = $section_level < $pbs_pod_level ? $section_level : $pbs_pod_level ;
			
			$section =~ s/^=for PBS\s*//i ;
			$pbs_pod .= $section . "\n" ;
			}
		else
			{
			$pbs_pod_level = 1_000_000 ;
			$other_pod .= $section . "\n" ;
			}
		}
		
	my $pod = $display_pbs_pod ? $pbs_pod : $other_pod ;
	
	if($raw)
		{
		print $pod ;
		}
	else
		{
		open my $input, '<', \$pod or die "Can't redirect from scalar input: $!\n";
		Pod::Text->new (alt => 1, sentence => 0, width => 78)->parse_from_file ($input) ;
		}
	}
else
	{
	print(ERROR("No Pbsfile to extract user information from. For PBS modules, use a pod converter (ie 'pod2html').\n")) ;	
	}
}

#-------------------------------------------------------------------------------

sub DisplayHelp
{
my $narrow_display  = shift ;

my @flags_and_help = GetSwitches() ;

PrintInfo <<EOH ;
Usage: pbs [-p Pbsfile[.pl]] [[-switch]...] target [target ...]
	
Options:
EOH

my $max_length = 0 ;
unless($narrow_display)
	{
	for (my $i = 0 ; $i < @flags_and_help; $i += 4)
		{
		$max_length = length($flags_and_help[$i]) if length($flags_and_help[$i]) > $max_length ;
		}
	}

for (my $i = 0 ; $i < @flags_and_help; $i += 4)
	{
	my ($flag, $help_text, $long_help_text) = ($flags_and_help[$i], $flags_and_help[$i + 2], $flags_and_help[$i + 3]) ;
	
	my $long_helpt_text_available = ' ' ;
	$long_helpt_text_available = '*' if $long_help_text ne '' ;
	
	print(ERROR( sprintf("--%-${max_length}s$long_helpt_text_available: ", $flag))) ;
	print("\n  ") if $narrow_display ;
	print(INFO( "$help_text\n")) ;
	}
}                    

#-------------------------------------------------------------------------------

use Term::Bash::Completion::Generator ;

sub GenerateBashCompletionScript
{
my @flags_and_help = GetSwitches() ;

my @switches ;
for (my $i = 0 ; $i < @flags_and_help; $i += 4)
	{
	my ($switch, $help_text, $long_help_text) = ($flags_and_help[$i], $flags_and_help[$i + 2], $flags_and_help[$i + 3]) ;
	push @switches, $switch ;
	}

my $completion_list = Term::Bash::Completion::Generator::de_getop_ify_list(\@switches) ;

my ($completion_command, $perl_script) = Term::Bash::Completion::Generator::generate_perl_completion_script('pbs', $completion_list, 1) ;

print STDOUT $completion_command ;
print STDERR $perl_script ;
}

#-------------------------------------------------------------------------------

1 ;

#-------------------------------------------------------------------------------

__END__
=head1 NAME

PBS::PBSConfigSwitches  -

=head1 DESCRIPTION

I<GetSwitches> returns a data structure containing the switches B<PBS> uses and some documentation. That
data structure is processed by I<Get_GetoptLong_Data> to produce a data structure suitable for use I<Getopt::Long::GetoptLong>.

I<DisplaySwitchHelp>, I<DisplayUserHelp> and I<DisplayHelp> also use that structure to display help.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
