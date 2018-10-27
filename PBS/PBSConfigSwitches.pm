
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

$PBS::Output::colorize++ ;

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
$pbs_config->{DISPLAY_NODE_INFO} ||= [] ;
$pbs_config->{USER_OPTIONS} ||= {} ;
$pbs_config->{COMMAND_LINE_DEFINITIONS} ||= {} ;
$pbs_config->{DISPLAY_DEPENDENCIES_REGEX} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_NODE} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_EXCLUDE} ||= [] ;
$pbs_config->{GENERATE_TREE_GRAPH_INCLUDE} ||= [] ;
$pbs_config->{DISPLAY_PBS_CONFIGURATION} ||= [] ;
$pbs_config->{VERBOSITY} ||= [] ;
$pbs_config->{POST_PBS} ||= [] ;
$pbs_config->{DISPLAY_TREE_FILTER} ||= [] ;
$pbs_config->{DISPLAY_TEXT_TREE_REGEX} ||= [] ;

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
		
	'w|wizard:s'                      => \$pbs_config->{WIZARD},
		'Starts a wizard.',
		'',
		
	'wi|display_wizard_info'          => \$pbs_config->{DISPLAY_WIZARD_INFO},
		'Shows Informatin about the found wizards.',
		'',
		
	'wh|display_wizard_help'          => \$pbs_config->{DISPLAY_WIZARD_HELP},
		'Tell the choosen wizards to show help.',
		'',
		
	'v|version'                       => \$pbs_config->{DISPLAY_VERSION},
		'Displays Pbs version.',
		'',
		
	'no_color'                        => \&PBS::Output::NoColors,
		'Removes colors from output. Usefull when redirecting to a file.',
		'',
		
	'info_label'             => \&PBS::Output::InfoLabel,
		'Adds a text label specifying the type of output.',
		'',
		
	'c|colorize'                      => \$PBS::Output::colorize,
		'Colorize output.',
		<<EOT,
If Term::AnsiColor is installed on your system, use this switch to 
colorize PBS output.

PBS has default colors but colorization is not turned on by default.

Colors can be defined through switches (try pbs -h | grep color) 

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

Check 'Term::AnsiColor' for more information. 
EOT
	'ce|color_error=s'                => \&PBS::Output::SetOutputColor,
		'Set the error color.',
		'',

	'cw|color_warning=s'              => \&PBS::Output::SetOutputColor,
		'Set the warning color.',
		'',

	'cw2|color_warning2=s'            => \&PBS::Output::SetOutputColor,
		'Set the alternate warning color.',
		'',

	'ci|color_info=s'                 => \&PBS::Output::SetOutputColor,
		'Set the information color.',
		'',

	'ci2|color_info2=s'               => \&PBS::Output::SetOutputColor,
		'Set the information2 color.',
		'',

	'ci3|color_info3=s'               => \&PBS::Output::SetOutputColor,
		'Set the information3 color.',
		'',

	'cu|color_user=s'                 => \&PBS::Output::SetOutputColor,
		'Set the user color.',
		'',

	'cs|color_shell=s'                => \&PBS::Output::SetOutputColor,
		'Set the shell color.',
		'',

	'cd|color_debug=s'                => \&PBS::Output::SetOutputColor,
		'Set the debugger color.',
		'',

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
		
	'dsi|display_subpbs_info'         => \$pbs_config->{DISPLAY_DEPENDENCY_INFO},
		'Display a message when depending a node in a subpbs.',
		'',
		
	'sfi|subpbs_file_info'                => \$pbs_config->{SUBPBS_FILE_INFO},
		'PBS displays the sub pbs file name.',
		'',
		
	'allow_virtual_to_match_directory'    => \$pbs_config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY},
		'PBS won\'t display any warning if a virtual node matches a directory name.',
		'',
		
	'nli|no_link_info'                => \$pbs_config->{NO_LINK_INFO},
		'PBS won\'t display which dependency node are linked instead of generated.',
		'',
		
	'nlmi|no_local_match_info'        => \$pbs_config->{NO_LOCAL_MATCHING_RULES_INFO},
		'PBS won\'t display a warning message if a linked node matches local rules.',
		'',
		
	'ndi|no_duplicate_info'           => \$pbs_config->{NO_DUPLICATE_INFO},
		'PBS won\'t display which dependency are duplicated for a node.',
		'',
		
	'ntii|no_trigger_import_info'     => \$pbs_config->{NO_TRIGGER_IMPORT_INFO},
		'PBS won\'t display which triggers are imported in a package.',
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
		
	'nbn|node_build_name'             => \$pbs_config->{DISPLAY_NODE_BUILD_NAME},
		'Display the build name in addition to the logical node name.',
		'',
		
	'no|node_origin'                  => \$pbs_config->{DISPLAY_NODE_ORIGIN},
		'Display where the node has been inserted in the dependency tree.',
		'',
		
	'nd|node_dependencies'            => \$pbs_config->{DISPLAY_NODE_DEPENDENCIES},
		'Display the dependencies for a node.',
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
		
	'nsb|node_sub_builder'                  => \$pbs_config->{DISPLAY_SUB_BUILDER},
		'Display information about sub being run (even if --nb is not set).',
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

	'kpbb|keep_pbs_build_buffers'     => \$pbs_config->{KEEP_PBS_BUILD_BUFFERS},
		'PBS will not remove the output buffers generated by build processes.',
		'When building in parallel, The build processes buffer the build output '
		 .'in the KEEP_PBS_BUILD_BUFFERS/ directory. When the build is done, the '
		 .'build processes forward the buffers to PBS and unlink the files. You '
		 .'can keep the buffers by specifying this switch',
		 
	'l|log|create_log'                    => \$pbs_config->{CREATE_LOG},
		'Create a main log and a log for each node',
		'',
		
	'log_html|create_log_html'              => \$pbs_config->{CREATE_LOG_HTML},
		'createe an html log for each node, implies --create_log and --keep_pbs_build_buffers',
		'',
		
	#----------------------------------------------------------------------------------
		
	'dpos|display_original_pbsfile_source'      => \$pbs_config->{DISPLAY_PBSFILE_ORIGINAL_SOURCE},
		'Display original Pbsfile source.',
		'',
		
	'dps|display_pbsfile_source'      => \$pbs_config->{DISPLAY_PBSFILE_SOURCE},
		'Display Modified Pbsfile source.',
		'',
		
	'dpc|display_pbs_configuration=s'=> $pbs_config->{DISPLAY_PBS_CONFIGURATION},
		'Display the configuration (switches) for the the package being processed by PBS.',
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
		
	'dde|display_depend_end'        => \$pbs_config->{DISPLAY_DEPEND_END},
		'Display when a depend ends.',
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
		
	'dddo|display_different_digest_only'   => \$pbs_config->{DISPLAY_DIFFERENT_DIGEST_ONLY},
		'Only display when a digest are diffrent.',
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
		' limits how many trees are displayed.',
		'',
		
	'ttmm|text_tree_match_max:i'      => \$pbs_config->{DISPLAY_TEXT_TREE_MAX_MATCH},
		' limits how many trees are displayed.',
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

	'tnt|tree_node_triggered'           => \$pbs_config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED},
		'(DF) Display if the node must be rebuild by append a star if it does.',
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
		
	#----------------------------------------------------------------------------------
	'f|files|nodes'                   => \$pbs_config->{DISPLAY_FILE_LOCATION},
		'Show all the nodes in the dependency tree and their final location.',
		'',
	#----------------------------------------------------------------------------------
	'bi|build_info=s'                 => $pbs_config->{DISPLAY_BUILD_INFO},
		'Options: --b --d --bc --br. A file or \'*\' can be specified. No Builds are done.',
		'',
		
	'nbh|no_build_header'             => \$pbs_config->{DISPLAY_NO_BUILD_HEADER},
		"Don't display the name of the node to be build.",
		'',
		
	'dpb|display_progress_bar'        => \$pbs_config->{DISPLAY_PROGRESS_BAR},
		"Force silent build mode and displays a progress bar. This is Pbs default, see --ndpb.",
		'',
		
	'ndpb|display_no_progress_bar'    => \$pbs_config->{DISPLAY_NO_PROGRESS_BAR},
		"Force verbose build mode and displays a progress bar.",
		'',
		
	'bre|build_result'                 => \$pbs_config->{DISPLAY_BUILD_RESULT},
		'Shows the result returned by the builder.',
		'',
		
	'bni|build_and_display_node_information' => \$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO},
		'Display information about the node to be build.',
		<<EOT,
Adds the following switches to the run:
'no|node_origin'
'nd|node_dependencies'
'nc|node_build_cause' 
'nr|node_build_rule' 
'nb|node_builder'
'npbc|node_build_post_build_commands'

You may want to also add:

'nbn|node_build_name' 
'nconf|node_config'
'nil|node_information_located'
EOT

	#----------------------------------------------------------------------------------
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

	#----------------------------------------------------------------------------------
	
	'debug:s'                             => \&PBS::Debug::EnableDebugger,
		'Enable debug support A startup file defining breakpoints can be given.',
		'',
	
	'dump'                             => \$pbs_config->{DUMP},
		'Dump an evaluable tree.',
		'',
		
	#----------------------------------------------------------------------------------
	
	'dwfn|display_warp_file_name'      => \$pbs_config->{DISPLAY_WARP_FILE_NAME},
		"Display the name of the warp file on creation or use.",
		'',
		
	'display_warp_time'                => \$pbs_config->{DISPLAY_WARP_TIME},
		"Display the time spend in warp creation or use.",
		'',
		
	'warp=s'             => \$pbs_config->{WARP},
		"specify which warp to use.",
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

sub LoadConfig
{
my ($switch, $file_name, $pbs_config) = @_ ;

$pbs_config->{LOAD_CONFIG} = $file_name ;

my ($loaded_pbs_config, $loaded_config) = do $file_name ;

if(! defined $loaded_config|| ! defined $loaded_pbs_config)
	{
	die WARNING2 "Error in configuration file'$file_name'!\n" ;
	}
else
	{
	# add the configs
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
PerlBuildSystem:
	
	pbs [-p Pbsfile[.pl]] [[-switch]...] target [target ...]
	
switches:
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
