
package PBS::PBSConfigSwitches ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
use Carp ;
use List::Util qw(max);

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
my (@options) = @_ ;

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ; $file_name =~ s/'$// ;

my $succes = 1 ;

while( my ($switch, $variable, $help1, $help2) = splice(@options, 0, 4))
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
			Say Warning "In Plugin '$file_name:$line', switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'. Ignoring." ;
			}
		else
			{
			$registred_flags{$switch_unit} = "$file_name:$line" ;
			}
		}
		
	if($switch_is_unique)
		{
		push @registred_flags_and_help, $switch, $variable, $help1, $help2 ;
		}
	}

return $succes ;
}

#-------------------------------------------------------------------------------

sub RegisterDefaultPbsFlags
{
my ($options) = GetOptions() ;

while(my ($switch, $variable, $help1, $help2) = splice(@$options, 0, 4))
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
my ($options, @t) = @_  ;

my @c = @$options ; # don't splice user data

push @t, [ splice @c, 0, 4 ] while @c ;

map { $_->[0], $_->[1] } @t
}

#-------------------------------------------------------------------------------

sub GetOptions
{
my $config = shift // {} ;

$config->{DO_BUILD} = 1 ;
$config->{TRIGGER} = [] ;

$config->{SHORT_DEPENDENCY_PATH_STRING} = '…' ;

$config->{JOBS_DIE_ON_ERROR} = 0 ;

$config->{GENERATE_TREE_GRAPH_GROUP_MODE} = GRAPH_GROUP_NONE ;
$config->{GENERATE_TREE_GRAPH_SPACING} = 1 ;

$config->{PBS_QR_OPTIONS} ||= [] ;
$config->{RULE_NAMESPACES} ||= [] ;
$config->{CONFIG_NAMESPACES} ||= [] ;
$config->{SOURCE_DIRECTORIES} ||= [] ;
$config->{PLUGIN_PATH} ||= [] ;
$config->{LIB_PATH} ||= [] ;
$config->{DISPLAY_BUILD_INFO} ||= [] ;
$config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX} ||= [] ;
$config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT} ||= [] ;
$config->{DISPLAY_NODE_INFO} ||= [] ;
$config->{DISPLAY_NODE_ENVIRONMENT} ||= [] ;
$config->{NODE_ENVIRONMENT_REGEX} ||= [] ;
$config->{LOG_NODE_INFO} ||= [] ;
$config->{USER_OPTIONS} ||= {} ;
$config->{KEEP_ENVIRONMENT} ||= [] ;
$config->{COMMAND_LINE_DEFINITIONS} ||= {} ;
$config->{DISPLAY_DEPENDENCIES_REGEX} ||= [] ;
$config->{DISPLAY_DEPENDENCIES_REGEX_NOT} ||= [] ;
$config->{DISPLAY_DEPENDENCIES_RULE_NAME} ||= [] ;
$config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT} ||= [] ;
$config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX} ||= [] ;
$config->{GENERATE_TREE_GRAPH_CLUSTER_NODE} ||= [] ;
$config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX} ||= [] ;
$config->{GENERATE_TREE_GRAPH_EXCLUDE} ||= [] ;
$config->{GENERATE_TREE_GRAPH_INCLUDE} ||= [] ;
$config->{DISPLAY_PBS_CONFIGURATION} ||= [] ;
$config->{VERBOSITY} ||= [] ;
$config->{POST_PBS} ||= [] ;
$config->{DISPLAY_TREE_FILTER} ||= [] ;
$config->{DISPLAY_TEXT_TREE_REGEX} ||= [] ;
$config->{BREAKPOINTS} ||= [] ;
$config->{NODE_BUILD_ACTIONS} ||= [] ;

my $load_config_closure = sub {LoadConfig(@_, $config) ;} ;

my @options =
	(
	'h|help'                          => \$config->{DISPLAY_HELP},
		'Displays this help.',
		'',
		
	'hs|help_switch=s'                => \$config->{DISPLAY_SWITCH_HELP},
		'Displays help for the given switch.',
		'',
		
	'hnd|help_narrow_display'         => \$config->{DISPLAY_HELP_NARROW_DISPLAY},
		'Writes the flag name and its explanation on separate lines.',
		'',

	'generate_bash_completion_script'   => \$config->{GENERATE_BASH_COMPLETION_SCRIPT},
		'create a bash completion script and exits.',
		'',

	'get_bash_completion'   => \$config->{GET_BASH_COMPLETION},
		'return completion list.',
		'',

	'get_options_list'   => \$config->{GET_OPTIONS_LIST},
		'return completion list on stdout.',
		'',

	'pbs_options=s'   => \$config->{PBS_OPTIONS},
		'start list subpbs options, argumet is a regex matching the target.',
		'',

	'pbs_options_local=s'   => \$config->{PBS_OPTIONS_LOCAL},
		'as pbs_options but only applied at the local subpbs level.',
		'',

	'pbs_options_end'   => \my $not_used,
		'ends the list of options for specific subpbs.',
		'',

	'pp|pbsfile_pod'                    => \$config->{DISPLAY_PBSFILE_POD},
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
		
	'pbs2pod'                         => \$config->{PBS2POD},
		'Extracts the pod contained in the Pbsfile (except user documentation POD).',
		'See --pbsfile_pod.',
		
	'raw_pod'                         => \$config->{RAW_POD},
		'-pbsfile_pod or -pbs2pod is dumped in raw pod format.',
		'',
		
	'd|display_pod_documenation:s'    => \$config->{DISPLAY_POD_DOCUMENTATION},
		'Interactive PBS documentation display and search.',
		'',
		
	'wizard:s'                      => \$config->{WIZARD},
		'Starts a wizard.',
		'',
		
	'wi|display_wizard_info'          => \$config->{DISPLAY_WIZARD_INFO},
		'Shows Informatin about the found wizards.',
		'',
		
	'wh|display_wizard_help'          => \$config->{DISPLAY_WIZARD_HELP},
		'Tell the choosen wizards to show help.',
		'',
		
	'v|version'                     => \$config->{DISPLAY_VERSION},
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

	'no_indentation'            => \$PBS::Output::no_indentation,
		'',
		'',

	'p|pbsfile=s'               => \$config->{PBSFILE},
		'Pbsfile use to defines the build.',
		'',
		
	'pfn|pbsfile_names=s'               => \$config->{PBSFILE_NAMES},
		'string containing space separated file names that can be pbsfiles.',
		'',
		
	'pfe|pbsfile_extensions=s'               => \$config->{PBSFILE_EXTENSIONS},
		'string containing space separated extensionss that can match a pbsfile.',
		'',
		
	'prf|pbs_response_file=s'         => \$config->{PBS_RESPONSE_FILE},
		'File containing switch definitions and targets.',
		'',
		
	'q|quiet'                         => \$config->{QUIET},
		'Reduce the output from the command. See --bdn, --so, --sco.',
		'',
		
	'naprf|no_anonymous_pbs_response_file'     => \$config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
		'Use only a response file named after the user or the one given on the command line.',
		'',
		
	'nprf|no_pbs_response_file'       => \$config->{NO_PBS_RESPONSE_FILE},
		'Don\'t use any response file.',
		'',
		
	'plp|pbs_lib_path=s'              => $config->{LIB_PATH},
		"Path to the pbs libs. Multiple directories can be given, each directory must start at '/' (root) or '.' or pbs will display an error message and exit.",
		'',
		
	'display_pbs_lib_path'            => \$config->{DISPLAY_LIB_PATH},
		"Displays PBS lib paths (for the current project) and exits.",
		'',
		
	'ppp|pbs_plugin_path=s'           => $config->{PLUGIN_PATH},
		"Path to the pbs plugins. The directory must start at '/' (root) or '.' or pbs will display an error message and exit.",
		'',
		
	'display_pbs_plugin_path'         => \$config->{DISPLAY_PLUGIN_PATH},
		"Displays PBS plugin paths (for the current project) and exits.",
		'',
		
	'no_default_path_warning'              => \$config->{NO_DEFAULT_PATH_WARNING},
		"When this switch is used, PBS will not display a warning when using the distribution's PBS lib and plugins.",
		'',
		
	'dpli|display_plugin_load_info'   => \$config->{DISPLAY_PLUGIN_LOAD_INFO},
		"displays which plugins are loaded.",
		'',
		
	'display_plugin_runs'             => \$config->{DISPLAY_PLUGIN_RUNS},
		"displays which plugins subs are run.",
		'',
		
	'dpt|display_pbs_time'            => \$config->{DISPLAY_PBS_TIME},
		"Display where time is spend in PBS.",
		'',
		
	'dmt|display_minimum_time=f'        => \$config->{DISPLAY_MINIMUM_TIME},
		"Don't display time if it is less than this value (in seconds, default 0.5s).",
		'',
		
	'dptt|display_pbs_total_time'            => \$config->{DISPLAY_PBS_TOTAL_TIME},
		"Display How much time is spend in PBS.",
		'',
		
	'dpu|display_pbsuse'              => \$config->{DISPLAY_PBSUSE},
		"displays which pbs module is loaded by a 'PbsUse'.",
		'',
		
	'dpuv|display_pbsuse_verbose'     => \$config->{DISPLAY_PBSUSE_VERBOSE},
		"displays which pbs module is loaded by a 'PbsUse' (full path) and where the the PbsUse call was made.",
		'',
		
	'dput|display_pbsuse_time'        => \$config->{DISPLAY_PBSUSE_TIME},
		"displays the time spend in 'PbsUse' for each pbsfile.",
		'',
		
	'dputa|display_pbsuse_time_all'    => \$config->{DISPLAY_PBSUSE_TIME_ALL},
		"displays the time spend in each pbsuse.",
		'',
		
	'dpus|display_pbsuse_statistic'    => \$config->{DISPLAY_PBSUSE_STATISTIC},
		"displays 'PbsUse' statistic.",
		'',
		
	'display_md5_statistic'            => \$config->{DISPLAY_MD5_STATISTICS},
		"displays 'MD5' statistic.",
		'',
		
	'display_md5_time'            => \$PBS::Digest::display_md5_time,
		"displays the time it takes to hash each node",
		'',
		
	'build_directory=s'               => \$config->{BUILD_DIRECTORY},
		'Directory where the build is to be done.',
		'',
		
	'mandatory_build_directory'       => \$config->{MANDATORY_BUILD_DIRECTORY},
		'PBS will not run unless a build directory is given.',
		'',
		
	'sd|source_directory=s'           => $config->{SOURCE_DIRECTORIES},
		'Directory where source files can be found. Can be used multiple times.',
		<<EOT,
Source directories are searched in the order they are given. The current 
directory is taken as the source directory if no --SD switch is given on
the command line. 

See also switches: --display_search_info --display_all_alternatives
EOT
	'rule_namespace=s'                => $config->{RULE_NAMESPACES},
		'Rule name space to be used by DefaultBuild()',
		'',
		
	'config_namespace=s'              => $config->{CONFIG_NAMESPACES},
		'Configuration name space to be used by DefaultBuild()',
		'',
		
	'save_config=s'                   => \$config->{SAVE_CONFIG},
		'PBS will save the config, used in each PBS run, in the build directory',
		"Before a subpbs is run, its start config will be saved in a file. PBS will display the filename so you "
		  . "can load it later with '--load_config'. When working with a hirarchical build with configuration "
		  . "defined at the top level, it may happend that you want to run pbs at lower levels but have no configuration, "
		  . "your build will probably fail. Run pbs from the top level with '--save_config', then run the subpbs " 
		  . "with the the saved config as argument to the '--load_config' option.",
		
	'load_config=s'                   => $load_config_closure,
		'PBS will load the given config before running the Pbsfile.',
		'see --save_config.',
		
	'no_config_inheritance'           =>  \$config->{NO_CONFIG_INHERITANCE},
		'Configuration variables are not iherited by child nodes/package.',
		'',
		
	'fb|force_build'                  => \$config->{FORCE_BUILD},
		'Debug flags cancel the build pass, this flag re-enables the build pass.',
		'',
		
	'cdabt|check_dependencies_at_build_time' => \$config->{CHECK_DEPENDENCIES_AT_BUILD_TIME},
		'Skipps the node build if no dependencies have changed or where rebuild to the same state.',
		'',

	'hsb|hide_skipped_builds' => \$config->{HIDE_SKIPPED_BUILDS},
		'Builds skipped due to -check_dependencies_at_build_time are not displayed.',
		'',

	'check_only_terminal_nodes' => \$config->{DEBUG_CHECK_ONLY_TERMINAL_NODES},
		'Skipps the checking of generated artefacts.',
		'',

	'no_check'                     => \$config->{NO_CHECK},
		'Cancel the check and build pass. Only the dependency pass is run.',
		'',

	'no_build'                     => \$config->{NO_BUILD},
		'Cancel the build pass. Only the dependency and check passes are run.',
		'',

	'do_immediate_build'                     => \$config->{DO_IMMEDIATE_BUILD},
		'do immediate build even if --no_build is set.',
		'',

	'nba|node_build_actions=s'               => $config->{NODE_BUILD_ACTIONS},
		'actions that are run on a node at build time.',
		q~example: pbs -ke .  -nba '3::stop' -nba "trigger::priority 4::message '%name'" -trigger '.' -w 0  -fb -dpb0 -j 12 -nh~,

	'ns|no_stop'                      => \$config->{NO_STOP},
		'Continues building even if a node couldn\'t be buid. See --bi.',
		'',
		
	'nh|no_header'                    => \$config->{DISPLAY_NO_STEP_HEADER},
		'PBS won\'t display the steps it is at. (Depend, Check, Build).',
		'',

	'nhc|no_header_counter'           => \$config->{DISPLAY_NO_STEP_HEADER_COUNTER},
		'Hide depend counter',
		'',

	'dsi|display_subpbs_info'         => \$config->{DISPLAY_SUBPBS_INFO},
		'Display extra information for nodes matching a subpbs rule.',
		'',
		
	'allow_virtual_to_match_directory'    => \$config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY},
		'PBS won\'t display any warning if a virtual node matches a directory name.',
		'',
		
	'link_no_external'                => \$config->{NO_EXTERNAL_LINK},
		'Dependencies Linking from other Pbsfile stops the build if any local rule can match.',
		'',

	'lni|link_no_info'                => \$config->{NO_LINK_INFO},
		'PBS won\'t display which dependency node are linked instead for generated.',
		'',

	'lnli|link_no_local_info'                => \$config->{NO_LOCAL_LINK_INFO},
		'PBS won\'t display linking to local nodes.',
		'',

	'nlmi|no_local_match_info'        => \$config->{NO_LOCAL_MATCHING_RULES_INFO},
		'PBS won\'t display a warning message if a linked node matches local rules.',
		'',
		
	'nwmwzd|no_warning_matching_with_zero_dependencies' => \$config->{NO_WARNING_MATCHING_WITH_ZERO_DEPENDENCIES},
		'PBS won\'t warn if a node has no dependencies but a matching rule.',
		'',
		
	'display_no_dependencies_ok'        => \$config->{DISPLAY_NO_DEPENDENCIES_OK},
		'Display a message if a node was tagged has having no dependencies with HasNoDependencies.',
		"Non source files (nodes with digest) are checked for dependencies since they need to be build from something, "
		. "some nodes are generated from non files or don't always have dependencies as for C cache which dependency file "
		. "is created on the fly if it doens't exist.",

	'display_duplicate_info'           => \$config->{DISPLAY_DUPLICATE_INFO},
		'PBS will display which dependency are duplicated for a node.',
		'',
	
	'ntii|no_trigger_import_info'     => \$config->{NO_TRIGGER_IMPORT_INFO},
		'PBS won\'t display which triggers are imported in a package.',
		'',
	
	'nhnd|no_has_no_dependencies=s'     => $config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX},
		'PBS won\'t display warning if node does not have dependencies.',
		'',
		
	'sc|silent_commands'              => \$PBS::Shell::silent_commands,
		'shell commands are not echoed to the console.',
		'',
		
	'sco|silent_commands_output'       => \$PBS::Shell::silent_commands_output,
		'shell commands output are not displayed, except if an error occures.',
		'',
		
	'dm|dump_maxdepth=i'              => \$config->{MAX_DEPTH},
		'Maximum depth of the structures displayed by pbs.',
		'',
		
	'di|dump_indentation=i'           => \$config->{INDENT_STYLE},
		'Data dump indent style (0-1-2).',
		'',
		
	'ni|node_information=s'           => $config->{DISPLAY_NODE_INFO},
		'Display information about the node matching the given regex before the build.',
		'',
	
	'nnr|no_node_build_rule'              => \$config->{DISPLAY_NO_NODE_BUILD_RULES},
		'Rules used to depend a node are not displayed',
		'',

	'nnp|no_node_parents'            => \$config->{DISPLAY_NO_NODE_PARENTS},
		"Don't display the node's parents.",
		'',

	'nonil|no_node_info_links'  => \$config->{NO_NODE_INFO_LINKS},
		'Pbs inserts node_info files links in info_files and logs, disable it',
		'',
	
	'nli|log_node_information=s'      => $config->{LOG_NODE_INFO},
		'Log information about nodes matching the given regex before the build.',
		'',
		
	'nci|node_cache_information'        => \$config->{NODE_CACHE_INFORMATION},
		'Display if the node is from the cache.',
		'',
		
	'nbn|node_build_name'             => \$config->{DISPLAY_NODE_BUILD_NAME},
		'Display the build name in addition to the logical node name.',
		'',
		
	'no|node_origin'                  => \$config->{DISPLAY_NODE_ORIGIN},
		'Display where the node has been inserted in the dependency tree.',
		'',
		
	'np|node_parents'            => \$config->{DISPLAY_NODE_PARENTS},
		"Display the node's parents.",
		'',
		
	'nd|node_dependencies'            => \$config->{DISPLAY_NODE_DEPENDENCIES},
		'Display the dependencies for a node.',
		'',
		
	'ne|node_environment=s'            => $config->{DISPLAY_NODE_ENVIRONMENT},
		'Display the environment variables for the nodes matching the regex.',
		'',
		
	'ner|node_environment_regex=s'      => $config->{NODE_ENVIRONMENT_REGEX},
		'Display the environment variables  matching the regex.',
		'',
		
	'nc|node_build_cause'             => \$config->{DISPLAY_NODE_BUILD_CAUSE},
		'Display why a node is to be build.',
		'',
		
	'nr|node_build_rule'              => \$config->{DISPLAY_NODE_BUILD_RULES},
		'Display the rules used to depend a node (rule defining a builder ar tagged with [B].',
		'',
		
	'nb|node_builder'                  => \$config->{DISPLAY_NODE_BUILDER},
		'Display the rule which defined the Builder and which command is being run.',
		'',
		
	'nconf|node_config'                => \$config->{DISPLAY_NODE_CONFIG},
		'Display the config used to build a node.',
		'',
		
	'npbc|node_build_post_build_commands'  => \$config->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS},
		'Display the post build commands for each node.',
		'',

	'ppbc|pbs_build_post_build_commands'  => \$config->{DISPLAY_PBS_POST_BUILD_COMMANDS},
		'Display the Pbs build post build commands.',
		'',

	'o|origin'                        => \$config->{ADD_ORIGIN},
		'PBS will also display the origin of rules in addition to their names.',
		<<EOT,
The origin contains the following information:
	* Name
	* Package
	* Namespace
	* Definition file
	* Definition line
EOT

	'j|jobs=i'                        => \$config->{JOBS},
		'Maximum number of commands run in parallel.',
		'',
		
	'jdoe|jobs_die_on_errors=i'       => \$config->{JOBS_DIE_ON_ERROR},
		'0 (default) finish running jobs. 1 die immediatly. 2 build as much as possible.',
		'',
		
	'dj|depend_jobs=i'                        => \$config->{DEPEND_JOBS},
		'Maximum number of dependers run in parallel.',
		'',
		
	'cj|check_jobs=i'                      => \$config->{CHECK_JOBS},
		'Maximum number of checker run in parallel.',
		'Depending on the amount of nodes and their size, running checks in parallel can reduce check time, YMMV.',

	'distribute=s'                   => \$config->{DISTRIBUTE},
		'Define where to distribute the build.',
		'The file should return a list of hosts in the format defined by the default distributor '
		 .'or define a distributor.',
		 
	'display_shell_info'                   => \$config->{DISPLAY_SHELL_INFO},
		'Displays which shell executes a command.',
		'',
		
	'dbi|display_builder_info'                 => \$config->{DISPLAY_BUILDER_INFORMATION},
		'Displays if a node is build by a perl sub or shell commands.',
		'',
		
	'time_builders'                   => \$config->{TIME_BUILDERS},
		'Displays the total time a builders took to run.',
		'',
		
	'dji|display_jobs_info'           => \$config->{DISPLAY_JOBS_INFO},
		'PBS will display extra information about the parallel build.',
		'',

	'djr|display_jobs_running'        => \$config->{DISPLAY_JOBS_RUNNING},
		'PBS will display which nodes are under build.',
		'',

	'l|log|create_log'                => \$config->{CREATE_LOG},
		'Create a log for the build',
		'Node build output is always kept in the build directory.',
		
	'log_tree'                        => \$config->{LOG_TREE},
		'Add a tree dump to the log, an option as during incremental build this takes most of the time.',
		'',
		
	'log_html|create_log_html'              => \$config->{CREATE_LOG_HTML},
		'create a html log for each node, implies --create_log ',
		'',
		
	#----------------------------------------------------------------------------------
		
	'dpos|display_original_pbsfile_source'      => \$config->{DISPLAY_PBSFILE_ORIGINAL_SOURCE},
		'Display original Pbsfile source.',
		'',
		
	'dps|display_pbsfile_source'      => \$config->{DISPLAY_PBSFILE_SOURCE},
		'Display Modified Pbsfile source.',
		'',
		
	'dpc|display_pbs_configuration=s'=> $config->{DISPLAY_PBS_CONFIGURATION},
		'Display the pbs configuration matching  the regex.',
		'',
		
	'dpcl|display_configuration_location'=> \$config->{DISPLAY_PBS_CONFIGURATION_LOCATION},
		'Display the pbs configuration location.',
		'',
		
	'dec|display_error_context'       => \$PBS::Output::display_error_context,
		'When set and if an error occures in a Pbsfile, PBS will display the error line.',
		'',
		
	'display_no_perl_context'         => \$config->{DISPLAY_NO_PERL_CONTEXT},
		'When displaying an error with context, do not parse the perl code to find the context end.',
		'',
		
	'dpl|display_pbsfile_loading'     => \$config->{DISPLAY_PBSFILE_LOADING},
		'Display which pbsfile is loaded.',
		'',
		
	'dplt|display_pbsfile_load_time'  => \$config->{DISPLAY_PBSFILE_LOAD_TIME},
		'Display the time to load and evaluate a pbsfile.',
		'',
		
	'dspd|display_sub_pbs_definition' => \$config->{DISPLAY_SUB_PBS_DEFINITION},
		'Display sub pbs definition.',
		'',
		
	'dspc|display_sub_config' => \$config->{DISPLAY_SUB_PBS_CONFIG},
		'Display sub pbs config.',
		'',
		
	'dcu|display_config_usage' => \$config->{DISPLAY_CONFIG_USAGE},
		'Display config variables not used.',
		'',
		
	'dncu|display_node_config_usage' => \$config->{DISPLAY_NODE_CONFIG_USAGE},
		'Display config variables not used by nodes.',
		'',
		
	'display_target_path_usage' => \$config->{DISPLAY_TARGET_PATH_USAGE},
		"Don't remove TARGET_PATH from config usage report.",
		'',
		
	'display_nodes_per_pbsfile'        => \$config->{DISPLAY_NODES_PER_PBSFILE},
		'Display how many nodes where added by each pbsfile run.',
		'',
		
	'display_nodes_per_pbsfile_names'        => \$config->{DISPLAY_NODES_PER_PBSFILE_NAMES},
		'Display which nodes where added by each pbsfile run.',
		'',
		
	'dl|depend_log' => \$config->{DEPEND_LOG},
		'Created a log for each subpbs.',
		'',
		
	'dlm|depend_log_merged' => \$config->{DEPEND_LOG_MERGED},
		'Merge children subpbs output in log.',
		'',
		
	'dfl|depend_full_log' => \$config->{DEPEND_FULL_LOG},
		'Created a log for each subpbs with extra display options set. Logs are not merged',
		'',
		
	'dflo|depend_full_log_options=s' => \$config->{DEPEND_FULL_LOG_OPTIONS},
		'Set extra display options for full log.',
		'',
		
	'ddi|display_depend_indented' => \$config->{DISPLAY_DEPEND_INDENTED},
		'Add indentation before node.',
		'',
		
	'dds|display_depend_separator=s' => \$config->{DISPLAY_DEPEND_SEPARATOR},
		'Display a separator between nodes.',
		'',
		
	'ddnl|display_depend_new_line' => \$config->{DISPLAY_DEPEND_NEW_LINE},
		'Display an extra blank line araound a depend.',
		'',
		
	'dde|display_depend_end'        => \$config->{DISPLAY_DEPEND_END},
		'Display when a depend ends.',
		'',
		
	'log_parallel_depend' =>\$config->{LOG_PARALLEL_DEPEND},
		'Creates a log of the parallel depend.',
		'',

	'dpds|display_parallel_depend_start' =>\$config->{DISPLAY_PARALLEL_DEPEND_START},
		'Display a message when a parallel depend starts.',
		'',

	'dpde|display_parallel_depend_end' =>\$config->{DISPLAY_PARALLEL_DEPEND_END},
		'Display a message when a parallel depend end.',
		'',

	'dpdnr|display_parallel_depend_no_resource' =>\$config->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE},
		'Display a message when a parallel depend could be done but no resource is available.',
		'',

	'ddrp|display_depend_remaining_processes' =>\$config->{DISPLAY_DEPEND_REMAINING_PROCESSES},
		'Display how many depend processes are running after the main depend process ended.',
		'',

	'display_too_many_nodes_warning=i'        => \$config->{DISPLAY_TOO_MANY_NODE_WARNING},
		'Display a warning when a pbsfile adds too many nodes.',
		'',

	'display_rule_to_order'          => \$config->{DISPLAY_RULES_TO_ORDER},
		'Display that there are rules order.',
		'',
		
	'display_rule_order'          => \$config->{DISPLAY_RULES_ORDER},
		'Display the order rules.',
		'',
		
	'display_rule_ordering'          => \$config->{DISPLAY_RULES_ORDERING},
		'Display the pbsfile used to order rules and the rules order.',
		'',
		
	'rro|rule_run_once'          => \$config->{RULE_RUN_ONCE},
		'Rules run only once except if they are tagged as MULTI',
		'',
		
	'rns|rule_no_scope'          => \$config->{RULE_NO_SCOPE},
		'Disable rule scope.',
		'',
		
	'display_rule_scope'          => \$config->{DISPLAY_RULE_SCOPE},
		'display scope parsing and generation',
		'',
		
	'maximum_rule_recursion'          => \$config->{MAXIMUM_RULE_RECURSION},
		'Set the maximum rule recusion before pbs, aborts the build',
		'',
		
	'rule_recursion_warning'          => \$config->{RULE_RECURSION_WARNING},
		'Set the level at which pbs starts warning aabout rule recursion',
		'',
		
	'dnmr|display_non_matching_rules' => \$config->{DISPLAY_NON_MATCHING_RULES},
		'Display the rules used during the dependency pass.',
		'',
		
	'dur|display_used_rules'          => \$config->{DISPLAY_USED_RULES},
		'Display the rules used during the dependency pass.',
		'',
		
	'durno|display_used_rules_name_only' => \$config->{DISPLAY_USED_RULES_NAME_ONLY},
		'Display the names of the rules used during the dependency pass.',
		'',
		
	'dar|display_all_rules'           => \$config->{DISPLAY_ALL_RULES},
		'Display all the registred rules.',
		'If you run a hierarchical build, these rules will be dumped every time a package runs a dependency step.',
		
	'dc|display_config'               => \$config->{DISPLAY_CONFIGURATION},
		'Display the config used during a Pbs run (simplified and from the used config namespaces only).',
		'',
		
	'dcs|display_config_start'        => \$config->{DISPLAY_CONFIGURATION_START},
		'Display the config to be used in a Pbs run before loading the Pbsfile',
		'',
		
        'display_config_delta'            => \$config->{DISPLAY_CONFIGURATION_DELTA},
		'Display the delta between the parent config and the config after the Pbsfile is run.',
		'',
					
	'dcn|display_config_namespaces'   => \$config->{DISPLAY_CONFIGURATION_NAMESPACES},
		'Display the config namespaces used during a Pbs run (even unused config namspaces).',
		'',
		
	'dac|display_all_configs'         => \$config->{DEBUG_DISPLAY_ALL_CONFIGURATIONS},
		'(DF). Display all configurations.',
		'',
		
	'dam|display_configs_merge'       => \$config->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE},
		'(DF). Display how configurations are merged.',
		'',
		
	'display_package_configuration'   => \$config->{DISPLAY_PACKAGE_CONFIGURATION},
		'If PACKAGE_CONFIGURATION for a subpbs exists, it will be displayed if this option is set (also displayed when --dc is set)',
		'',
		
	'no_silent_override'         => \$config->{NO_SILENT_OVERRIDE},
		'Makes all SILENT_OVERRIDE configuration visible.',
		'',
		
	'display_subpbs_search_info'         => \$config->{DISPLAY_SUBPBS_SEARCH_INFO},
		'Display information about how the subpbs files are found.',
		'',
		
	'display_all_subpbs_alternatives'         => \$config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES},
		'Display all the subpbs files that could match.',
		'',
		
	'dsd|display_source_directory'    => \$config->{DISPLAY_SOURCE_DIRECTORIES},
		'display all the source directories (given through the -sd switch ot the Pebsfile).',
		'',
		
	'display_search_info'         => \$config->{DISPLAY_SEARCH_INFO},
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

	'daa|display_all_alternates'      => \$config->{DISPLAY_SEARCH_ALTERNATES},
		'Display all the files found in the source directories.',
		<<EOT,
When PBS searches for a node in the source directories, it stops at the first found node.
if you have multiple source directories, you might want to see the files 'PBS' didn't choose.
The first one will still be choosen.

  $>perl pbs.pl -o -sd ./d1 -sd ./d2 -sd . -daa -c all
  ...

  Trying ./a.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/d1/a.c: Relocated. s: 0 t: 15-2-2003 20:54:57
  Trying ./a.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/d2/a.c: NOT USED. s: 0 t: 15-2-2003 20:55:0
  Trying ./a.c @  /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/a.c: not found.
  ...

  Final Location for ./a.h @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/a.h
  Final Location for ./a.c @ /home/nadim/Dev/PerlModules/PerlBuildSystem-0.05/a.c
EOT
		
	#----------------------------------------------------------------------------------
	'dr|display_rules'                => \$config->{DEBUG_DISPLAY_RULES},
		'(DF) Display which rules are registred. and which rule packages are queried.',
		'',
		
	'dir|display_inactive_rules'      => \$config->{DISPLAY_INACTIVE_RULES},
		'Display rules present i the åbsfile but tagged as NON_ACTIVE.',
		'',
		
	'drd|display_rule_definition'     => \$config->{DEBUG_DISPLAY_RULE_DEFINITION},
		'(DF) Display the definition of each registrated rule.',
		'',
		
	'drs|display_rule_statistics'     => \$config->{DEBUG_DISPLAY_RULE_STATISTICS},
		'(DF) Display rule statistics after each pbs run.',
		'',
		
	'dtr|display_trigger_rules'       => \$config->{DEBUG_DISPLAY_TRIGGER_RULES},
		'(DF) Display which triggers are registred. and which trigger packages are queried.',
		'',
		
	'dtrd|display_trigger_rule_definition' => \$config->{DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION},
		'(DF) Display the definition of each registrated trigger.',
		'',
		
	# -------------------------------------------------------------------------------	
	'dpbcr|display_post_build_commands_registration' => \$config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION},
		'(DF) Display the registration of post build commands.',
		'',
		
	'dpbcd|display_post_build_command_definition' => \$config->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION},
		'(DF) Display the definition of post build commands when they are registered.',
		'',
		
	'dpbc|display_post_build_commands' => \$config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS},
		'(DF) Display which post build command will be run for a node.',
		'',
		
	'dpbcre|display_post_build_result'  => \$config->{DISPLAY_POST_BUILD_RESULT},
		'Display the result code and message returned buy post build commands.',
		'',
		
	#-------------------------------------------------------------------------------	
	'display_full_dependency_path'         => \$config->{DISPLAY_FULL_DEPENDENCY_PATH},
		'Display full dependency_path.',
		'',
		
	'short_dependency_path_string=s'         => \$config->{SHORT_DEPENDENCY_PATH_STRING},
		'Replace full dependency_path with argument.',
		'',
		
	'dd|display_dependencies'         => \$config->{DEBUG_DISPLAY_DEPENDENCIES},
		'(DF) Display the dependencies for each file processed.',
		'',
		
	'dh|depend_header'                => \$config->{DISPLAY_DEPEND_HEADER},
		"Show depend header.",
		'',
		
	'ddl|display_dependencies_long'         => \$config->{DEBUG_DISPLAY_DEPENDENCIES_LONG},
		'(DF) Display one dependency perl line.',
		'',
		
	'ddt|display_dependency_time'     => \$config->{DISPLAY_DEPENDENCY_TIME},
		' Display the time spend in each Pbsfile.',
		'',
		
	'dct|display_check_time'          => \$config->{DISPLAY_CHECK_TIME},
		' Display the time spend checking the dependency tree.',
		'',
		
	'dre|dependency_result'           => \$config->{DISPLAY_DEPENDENCY_RESULT},
		'Display the result of each dependency step.',
		'',
		
	'ddrr|display_dependencies_regex=s'=> $config->{DISPLAY_DEPENDENCIES_REGEX},
		'Node matching the regex are displayed.',
		'',
		
	'ddrrn|display_dependencies_regex_not=s'=> $config->{DISPLAY_DEPENDENCIES_REGEX_NOT},
		'Node matching the regex are not displayed.',
		'',
		
	'ddrn|display_dependencies_rule_name=s'=> $config->{DISPLAY_DEPENDENCIES_RULE_NAME},
		'Node matching rules matching the regex are displayed.',
		'',
		
	'ddrnn|display_dependencies_rule_name_not=s'=> $config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT},
		'Node matching rules matching the regex are not displayed.',
		'',
		
	'dnsr|display_node_subs_run'      => \$config->{DISPLAY_NODE_SUBS_RUN},
		'Show when a node sub is run.',
		'',

	'trace_pbs_stack'        => \$config->{DEBUG_TRACE_PBS_STACK},
		'(DF) Display the call stack within pbs runs.',
		'',
		
	'ddrd|display_dependency_rule_definition' => \$config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION},
		'Display the definition of the rule that generates a dependency.',
		'',
		
	'ddr|display_dependency_regex'        => \$config->{DEBUG_DISPLAY_DEPENDENCY_REGEX},
		'(DF) Display the regex used to depend a node.',
		'',
		
	'ddmr|display_dependency_matching_rule' => \$config->{DISPLAY_DEPENDENCY_MATCHING_RULE},
		'Display the rule which matched the node.',
		'',
		
	'ddfp|display_dependency_full_pbsfile'   => \$config->{DISPLAY_DEPENDENCIES_FULL_PBSFILE},
		'in conjonction with --display_dependency_matching_rule, display the fullpbsfile path rather than relative to target.',
		'',
		
	'ddir|display_dependency_insertion_rule' => \$config->{DISPLAY_DEPENDENCY_INSERTION_RULE},
		'Display the rule which added the node.',
		'',
		
	'dlmr|display_link_matching_rule' => \$config->{DISPLAY_LINK_MATCHING_RULE},
		'Display the rule which matched the node that is being linked.',
		'',
		
	'dtin|display_trigger_inserted_nodes' => \$config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES},
		'(DF) Display the nodes inserted because of a trigger.',
		'',
		
	'dt|display_triggered'              => \$config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES},
		'(DF) Display the files that need to be rebuild and why they need so.',
		'',
		
	'display_digest_exclusion'        => \$config->{DISPLAY_DIGEST_EXCLUSION},
		'Display when an exclusion or inclusion rule for a node matches.',
		'',
		
	'display_digest'                  => \$config->{DISPLAY_DIGEST},
		'Display the expected and the actual digest for each node.',
		'',
		
	'dddo|display_different_digest_only'  => \$config->{DISPLAY_DIFFERENT_DIGEST_ONLY},
		'Only display when a digest are diffrent.',
		'',
		
	'devel_no_distribution_check'  => \$config->{DEVEL_NO_DISTRIBUTION_CHECK},
		'A development flag, not for user.',
		<<EOT,
Pbs checks its distribution when building and rebuilds everything if it has changed.

While developping we are constantly changing the distribution but want to see the effect
of the latest change without rebuilding everything which makes finding the effect of the
latest change more difficult.
EOT

	'wnmw|warp_no_md5_warning'             => \$config->{WARP_NO_DISPLAY_DIGEST_FILE_NOT_FOUND},
		'Do not display a warning if the file to compute hash for does not exist during warp verification.',
		'',
		
	'dfc|display_file_check'   => \$config->{DISPLAY_FILE_CHECK},
		'Display hash checking for individual files.',
		'',
		
	'display_cyclic_tree'             => \$config->{DEBUG_DISPLAY_CYCLIC_TREE},
		'(DF) Display the portion of the dependency tree that is cyclic',
		'',
		
	'no_source_cyclic_warning'             => \$config->{NO_SOURCE_CYCLIC_WARNING},
		'No warning is displayed if a cycle involving source files is found.',
		'',
		
	'die_source_cyclic_warning'             => \$config->{DIE_SOURCE_CYCLIC_WARNING},
		'Die if a cycle involving source files is found (default is warn).',
		'',
		
	'tt|text_tree'                  => \$config->{DEBUG_DISPLAY_TEXT_TREE},
		'(DF) Display the dependency tree using a text dumper',
		'',
		
	'ttmr|text_tree_match_regex:s'      => $config->{DISPLAY_TEXT_TREE_REGEX},
		'limits how many trees are displayed.',
		'',
		
	'ttmm|text_tree_match_max:i'      => \$config->{DISPLAY_TEXT_TREE_MAX_MATCH},
		'limits how many trees are displayed.',
		'',
		
	'ttf|text_tree_filter=s'          => $config->{DISPLAY_TREE_FILTER},
		'(DF) List the fields that are to be displayed when -tt is active. The switch can be used multiple times.',
		'',
		
	'tta|text_tree_use_ascii'         => \$config->{DISPLAY_TEXT_TREE_USE_ASCII},
		'Use ASCII characters instead for Ansi escape codes to draw the tree.',
		'',
		
	'ttdhtml|text_tree_use_dhtml=s'     => \$config->{DISPLAY_TEXT_TREE_USE_DHTML},
		'Generate a dhtml dump of the tree in the specified file.',
		'',
		
	'ttmd|text_tree_max_depth=i'       => \$config->{DISPLAY_TEXT_TREE_MAX_DEPTH},
		'Limit the depth of the dumped tree.',
		'',
		
	'tno|tree_name_only'               => \$config->{DEBUG_DISPLAY_TREE_NAME_ONLY},
		'(DF) Display the name of the nodes only.',
		'',
		
	'vas|visualize_after_subpbs'       => \$config->{DEBUG_VISUALIZE_AFTER_SUPBS},
		'(DF) visualization plugins run after every subpbs.',
		'',
		
	'tda|tree_depended_at'               => \$config->{DEBUG_DISPLAY_TREE_DEPENDED_AT},
		'(DF) Display which Pbsfile was used to depend each node.',
		'',
		
	'tia|tree_inserted_at'               => \$config->{DEBUG_DISPLAY_TREE_INSERTED_AT},
		'(DF) Display where the node was inserted.',
		'',
		
	'tnd|tree_display_no_dependencies'        => \$config->{DEBUG_DISPLAY_TREE_NO_DEPENDENCIES},
		'(DF) Don\'t show child nodes data.',
		'',
		
	'tad|tree_display_all_data'        => \$config->{DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA},
		'Unset data within the tree are normally not displayed. This switch forces the display of all data.',
		'',
		
	'tnb|tree_name_build'               => \$config->{DEBUG_DISPLAY_TREE_NAME_BUILD},
		'(DF) Display the build name of the nodes. Must be used with --tno',
		'',
		
	'TA|trigger_all'                        => \$config->{DEBUG_TRIGGER_ALL},
		'(DF) As if all node triggered, see --trigger',
		'',
		
	'TN|trigger_none'                        => \$config->{DEBUG_TRIGGER_NONE},
		'(DF) As if no node triggered, see --trigger',
		'',
		
	'T|trigger=s'                           => $config->{TRIGGER},
		'(DF) Force the triggering of a node if you want to check its effects.',
		'',
		
	'TL|trigger_list=s'                       => \$config->{DEBUG_TRIGGER_LIST},
		'(DF) Points to a file containing trigers.',
		'',

	'TD|display_trigger'                       => \$config->{DEBUG_DISPLAY_TRIGGER},
		'(DF) display which files are processed and triggered',
		'',

	'TDM|display_trigger_match_only'            => \$config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY},
		'(DF) display only files which are triggered',
		'',

	'tntr|tree_node_triggered_reason'   => \$config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON},
		'(DF) Display why a node is to be rebuild.',
		'',
		
	#-------------------------------------------------------------------------------	
	'gtg|generate_tree_graph=s'       => \$config->{GENERATE_TREE_GRAPH},
		'Generate a graph for the dependency tree. Give the file name as argument.',
		'',
		
	'gtg_p|generate_tree_graph_package'=> \$config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE},
		'Groups the node by definition package.',
		'',
		
	'gtg_canonical=s'=> \$config->{GENERATE_TREE_GRAPH_CANONICAL},
		'Generates a canonical dot file.',
		'',
		
	'gtg_format=s'                        => \$config->{GENERATE_TREE_GRAPH_FORMAT},
		'chose graph format between: svg (default), ps, png.',
		'',
		
	'gtg_html=s'=> \$config->{GENERATE_TREE_GRAPH_HTML},
		'Generates a set of html files describing the build tree.',
		'',
		
	'gtg_html_frame'=> \$config->{GENERATE_TREE_GRAPH_HTML_FRAME},
		'The use a frame in the graph html.',
		'',
		
	'gtg_snapshots=s'=> \$config->{GENERATE_TREE_GRAPH_SNAPSHOTS},
		'Generates a serie of snapshots from the build.',
		'',
		
	'gtg_cn=s'                         => $config->{GENERATE_TREE_GRAPH_CLUSTER_NODE},
		'The node given as argument and its dependencies will be displayed as a single unit. Multiple gtg_cn allowed.',
		'',
		
	'gtg_cr=s'                         => $config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX},
		'Put nodes matching the given regex in a node named as the regx. Multiple gtg_cr allowed.',
		<<'EOT',
$> pbs -gtg_cr '\.c$' --gtg

create a graph where all the .c files are clustered in a single node named '.c$'
EOT
	'gtg_crl=s'                         => \$config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST},
		'List of regexes, as if you gave multiple --gtg_cr, one per line',
		'',
		
	'gtg_sd|generate_tree_graph_source_directories' => \$config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES},
		'As generate_tree_graph but groups the node by source directories, uncompatible with --generate_tree_graph_package.',
		'',
		
	'gtg_exclude|generate_tree_graph_exclude=s'       => $config->{GENERATE_TREE_GRAPH_EXCLUDE},
		"Exclude nodes and their dependenies from the graph.",
		'',
		
	'gtg_include|generate_tree_graph_include=s' => $config->{GENERATE_TREE_GRAPH_INCLUDE},
		"Forces nodes and their dependencies back into the graph.",
		'Ex: pbs -gtg tree -gtg_exclude "*.c" - gtg_include "name.c".',
		
	'gtg_bd'                           => \$config->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY},
		'The build directory for each node is displayed.',
		'',
		
	'gtg_rbd'                          => \$config->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY},
		'The build directory for the root is displayed.',
		'',
		
	'gtg_tn'                           => \$config->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES},
		'Node inserted by Triggerring are also displayed.',
		'',
		
	'gtg_config'                       => \$config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG},
		'Configs are also displayed.',
		'',
		
	'gtg_config_edge'                  => \$config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE},
		'Configs are displayed as well as an edge from the nodes using it.',
		'',
		
	'gtg_pbs_config'                   => \$config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG},
		'Package configs are also displayed.',
		'',
		
	'gtg_pbs_config_edge'              => \$config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE},
		'Package configs are displayed as well as an edge from the nodes using it.',
		'',
		
	'gtg_gm|generate_tree_graph_group_mode=i' => \$config->{GENERATE_TREE_GRAPH_GROUP_MODE},
		'Set the grouping mode.0 no grouping, 1 main tree is grouped (default), 2 each tree is grouped.',
		'',
		
	'gtg_spacing=f'                    => \$config->{GENERATE_TREE_GRAPH_SPACING},
		'Multiply node spacing with given coefficient.',
		'',
		
	'gtg_printer|generate_tree_graph_printer'=> \$config->{GENERATE_TREE_GRAPH_PRINTER},
		'Non triggerring edges are displayed as dashed lines.',
		'',
		
	'gtg_sn|generate_tree_graph_start_node=s'       => \$config->{GENERATE_TREE_GRAPH_START_NODE},
		'Generate a graph from the given node.',
		'',
		
	'a|ancestors=s'                   => \$config->{DEBUG_DISPLAY_PARENT},
		'(DF) Display the ancestors of a file and the rules that inserted them.',
		'',
		
	'dbsi|display_build_sequencer_info'      => \$config->{DISPLAY_BUILD_SEQUENCER_INFO},
		'Display information about which node is build.',
		'',

	'dbs|display_build_sequence'      => \$config->{DEBUG_DISPLAY_BUILD_SEQUENCE},
		'(DF) Dumps the build sequence data.',
		'',
		
	'dbss|display_build_sequence_simple'      => \$config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE},
		'(DF) List the nodes to be build.',
		'',
		
	'save_build_sequence_simple=s'      => \$config->{SAVE_BUILD_SEQUENCE_SIMPLE},
		'Save a list of nodes to be build to a file.',
		'',
		
	'f|files|nodes'                   => \$config->{DISPLAY_FILE_LOCATION},
		'Show all the nodes in the current_dependency tree and their final location.',
		'In warp only shows the nodes that have triggered, see option nodes_all for all nodes',

	'fa|files_all|nodes_all'          => \$config->{DISPLAY_FILE_LOCATION_ALL},
		'Show all the nodes in the current_dependency tree and their final location.',
		'',

	'bi|build_info=s'                 => $config->{DISPLAY_BUILD_INFO},
		'Options: --b --d --bc --br. A file or \'*\' can be specified. No Build is done.',
		'',
		
	'nbh|no_build_header'             => \$config->{DISPLAY_NO_BUILD_HEADER},
		"Don't display the name of the node to be build.",
		'',
		
	'bpb0|display_nop_progress_bar'        => \$config->{DISPLAY_PROGRESS_BAR_NOP},
		"Force silent build mode and displays an empty progress bar.",
		'',

	'bpb1|display_progress_bar'        => \$config->{DISPLAY_PROGRESS_BAR},
		"Force silent build mode and displays a progress bar. This is Pbs default, see --build_verbose.",
		'',

	'bpb2|display_progress_bar_file'  => \$config->{DISPLAY_PROGRESS_BAR_FILE},
		"Built node names are displayed above the progress bar",
		'',

	'bpb3|display_progress_bar_process'  => \$config->{DISPLAY_PROGRESS_BAR_PROCESS},
		"A progress per build process is displayed above the progress bar",
		'',

	'bv|build_verbose'    => \$config->{DISPLAY_NO_PROGRESS_BAR},
		"Verbose build mode.",
		'',
		
	'bvm|display_no_progress_bar_minimum'  => \$config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM},
		"Slightly less verbose build mode.",
		'',
		
	'bvmm|display_no_progress_bar_minimum_minimum'  => \$config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2},
		"Frankly less verbose build mode.",
		'',

	'bre|display_build_result'       => \$config->{DISPLAY_BUILD_RESULT},
		'Shows the result returned by the builder.',
		'',
		
	'bn|box_node' => \$config->{BOX_NODE},
		'Display a colored margin for each node display.',
		'',

	'bnir|build_and_display_node_information_regex=s' => $config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX},
		'Only display information for matching nodes.',
		'',

	'bnirn|build_and_display_node_information_regex_not=s' => $config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT},
		"Don't  display information for matching nodes.",
		'',

	'bni_result' => \$config->{BUILD_DISPLAY_RESULT},
		'display node header and build result even if not matched by --bnir.',
		'',

	'bni|build_and_display_node_information' => \$config->{BUILD_AND_DISPLAY_NODE_INFO},
		'Display information about the node to be build.',
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

	'verbosity=s'                 => $config->{VERBOSITY},
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

	'u|user_option=s'                 => $config->{USER_OPTIONS},
		'options to be passed to the Build sub.',
		'',
		
	'D=s'                             => $config->{COMMAND_LINE_DEFINITIONS},
		'Command line definitions.',
		'',

	'ek|keep_environment=s'           => $config->{KEEP_ENVIRONMENT},
		"Pbs empties %ENV, user --ke 'regex' to keep specific variables.",
		'',

	'ed|display_environment'            => \$config->{DISPLAY_ENVIRONMENT},
		"Display which environment variables are kept and discarded",
		'',

	'edk|display_environment_kept'       => \$config->{DISPLAY_ENVIRONMENT_KEPT},
		"Only display the evironment variables kept",
		'',

	'es|display_environment_statistic'       => \$config->{DISPLAY_ENVIRONMENT_STAT},
		"Display a statistics about environment variables",
		'',

	#----------------------------------------------------------------------------------

	'hdp|http_display_post' => \$config->{HTTP_DISPLAY_POST},
		'Display a message when a POST is issued.',
		'',

	'hdg|http_display_get' => \$config->{HTTP_DISPLAY_GET},
		'Display a message when a GET is issued.',
		'',

	'hdss|http_display_server_start' => \$config->{HTTP_DISPLAY_SERVER_START},
		'Display a message when a server is started.',
		'',

	'hdr|http_display_request' => \$config->{HTTP_DISPLAY_REQUEST},
		'Display a message when a Request is received.',
		'',

	#----------------------------------------------------------------------------------
	
	'bp|debug:s'                         => $config->{BREAKPOINTS},
		'Enable debug support A startup file defining breakpoints can be given.',
		'',

	'bph|debug_display_breakpoint_header' => \$config->{DISPLAY_BREAKPOINT_HEADER},
		'Display a message when a breakpoint is run.',
		'',

	'dump'                            => \$config->{DUMP},
		'Dump an evaluable tree.',
		'',
		
	#----------------------------------------------------------------------------------
	
	'dwfn|display_warp_file_name'      => \$config->{DISPLAY_WARP_FILE_NAME},
		"Display the name of the warp file on creation or use.",
		'',
		
	'display_warp_time'                => \$config->{DISPLAY_WARP_TIME},
		"Display the time spend in warp creation or use.",
		'',
		
	'w|warp=s'             => \$config->{WARP},
		"specify which warp to use.",
		'',
		
	'warp_human_format'    => \$config->{WARP_HUMAN_FORMAT},
		"Generate warp file in a readable format.",
		'',
		
	'no_pre_build_warp'             => \$config->{NO_PRE_BUILD_WARP},
		"no pre-build warp will be generated.",
		'',
		
	'no_post_build_warp'             => \$config->{NO_POST_BUILD_WARP},
		"no post-build warp will be generated.",
		'',
		
	'display_warp_checked_nodes'  => \$config->{DISPLAY_WARP_CHECKED_NODES},
		"Display which nodes are contained in the warp tree and their status.",
		'',
			
	'display_warp_checked_nodes_fail_only'  => \$config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY},
		"Display which nodes, in the warp tree, has a different MD5.",
		'',
			
	'display_warp_removed_nodes'  => \$config->{DISPLAY_WARP_REMOVED_NODES},
		"Display which nodes are removed during warp.",
		'',
			
	'display_warp_triggered_nodes'  => \$config->{DISPLAY_WARP_TRIGGERED_NODES},
		"Display which nodes are removed from the warp tree and why.",
		'',

	#----------------------------------------------------------------------------------
	
	'post_pbs=s'                        => $config->{POST_PBS},
		"Run the given perl script after pbs. Usefull to generate reports, etc.",
		'',
		
	) ;

my @rfh = @registred_flags_and_help ;

while( my ($switch, $variable, $help1, $help2) = splice(@rfh, 0, 4))
    {
    if('' eq ref $variable)
        {
        if($variable =~ s/^@//)
            {
            $variable = $config->{$variable} = [] ;
            }
        else
            {
            $variable = \$config->{$variable} ;
            }
        }

    push @options, $switch, $variable, $help1, $help2 ;
    }


\@options, $config ;
}

#-------------------------------------------------------------------------------

sub AliasOptions
{
use File::Slurp ;

my ($arguments) = @_ ;

my $alias_file = 'pbs_option_aliases' ;
my %aliases ;

if (-e $alias_file)
	{
	for my $line (read_file $alias_file)
		{
		next if $line =~ /^\s*#/ ;
		next if $line =~ /^$/ ;
		$line =~ s/^\s*// ;
		
		my ($alias, @rest) = split /\s+/, $line ;
		$alias =~ s/^-+// ;

		$aliases{$alias} = \@rest if @rest ;
		}
	}

my @aliased = map { /^-+/ && exists $aliases{s/^-+//r} ? @{$aliases{s/^-+//r}} : $_ } @$arguments ;

@{$arguments} = @aliased ; 

return \%aliases ;
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
	Say Info "Config: loading '$file_name'" unless $message_displayed ;
	$message_displayed++ ;

	$pbs_config->{LOADED_CONFIG} = $loaded_config ;
	}
}

#-------------------------------------------------------------------------------

sub DisplaySwitchHelp
{
my ($switch) = @_ ;
my ($options, $config, @t) = GetOptions() ;

push @t, [splice @$options, 0, 4 ] while @$options ;

HELP:
for (@t)
	{
	my ($name, $help, $long_help) = @{$_}[0, 2, 3] ;
	
	for (split /\|/, $name)
		{
		if(/^$switch\s*=*.*$/)
			{
			Say Error "$name: " . _INFO_($help) ;
			Say Info  "\n$long_help" unless $long_help eq '' ;
			
			last HELP ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub DisplayUserHelp
{
my ($Pbsfile, $display_pbs_pod, $raw) = @_ ;

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
		my $pod_output = '' ;
		open my $input, '<', \$pod or die "Can't redirect from scalar input: $!\n";
		open my $output, '>', \$pod_output  or die "Can't redirect from scalar input: $!\n";
		Pod::Text->new (alt => 1, sentence => 1, width => 78)->parse_from_file ($input, $output) ;

		Print Debug $pod_output ;
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
my ($narrow_display) = @_ ;

my ($options, $config, @t) = GetOptions() ;

push @t, [splice @$options, 0, 4 ] while @$options ;

my $max_length = $narrow_display ? 0 : max map { length $_->[0] } @t ;
my $lh = $->[3] eq '' ? '' : '*' ;

print STDOUT Error(sprintf("--%-${max_length}s$lh:", $_->[0])
		. ($narrow_display ? "\n  " : ' ') . _INFO_( $_->[2] )) . "\n"
			for @t ;
}                    

#-------------------------------------------------------------------------------

use Term::Bash::Completion::Generator ;

sub GenerateBashCompletionScript
{
my $file_name = 'pbs_perl_completion' ;

if (-e $file_name)
	{
	if (-e "$file_name.bak")
		{
		Say Warning "PBS: backup file '$file_name.bak' for command completion exist, nothing generated" ;
		return ;
		}
	else
		{
		rename $file_name, "$file_name.bak" ;
		}
	}

my ($options) = GetOptions() ;

my (@slice, @switches) ;
push @switches, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 

my $completion_list = Term::Bash::Completion::Generator::de_getop_ify_list(\@switches) ;

my ($completion_command, $perl_script) = Term::Bash::Completion::Generator::generate_perl_completion_script('pbs', $completion_list, 1) ;

open my $completion_file, '+>', $file_name ;
print $completion_file $perl_script ;
chmod 0755, $completion_file ;

use Cwd ;
my $cwd = Cwd::getcwd() ;

Say Info                                "# Bash completion script '$file_name' generated, add the completion to Bash with:" ;
PBS::Output::PrintStdOutColor \&WARNING, "complete -o default -C '$cwd/pbs_perl_completion' pbs\n" ;
}

#-------------------------------------------------------------------------------

sub GetCompletion
{
my ($options) = @_ ;

shift @ARGV ;
my ($command_name, $word_to_complete, $previous_arguments) = @ARGV ;

if($word_to_complete !~ /^\s?$/)
	{
	my (@slice, @options) ;
	push @options, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 

	my $names = Term::Bash::Completion::Generator::de_getop_ify_list(\@options) ;

	my $aliases = AliasOptions([]) ;
	push @$names, keys %$aliases ;

	use Tree::Trie ;
	my $trie = new Tree::Trie ;
	$trie->add( map { ("-" . $_) , ("--" . $_) } @{$names }) ;

	my @matches = $trie->lookup($word_to_complete) ;

	if(@matches)
		{
		print join("\n", @matches) . "\n" ;
		}
	else
		{
		if($word_to_complete =~ /\?$/)
			{
			my ($word) = $word_to_complete =~ m/^-*(.+)\?$/ ;

			@matches = grep { /^$word\s*$/ } @$names ;

			if(1 == @matches)
				{
				Print Info "\n\n";
				DisplaySwitchHelp(@matches) ;
				
				@matches = map { "--$_" } grep { /$word/ } @$names ;
				print @matches > 1 ? join("\n", @matches) . "\n" : "\n.\n" ;
				}
			else
				{
				print join("\n", map { "--$_" } grep { /$word/ } @$names) . "\n" ;
				}
			}
		else
			{
			my $word =  $word_to_complete =~ s/^-*//r ;

			@matches = grep { /$word/ } sort @$names ;

			print join("\n", map { "--$_" } @matches) . "\n" ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub GetOptionsList
{
my ($options) = GetOptions() ;

my (@slice, @switches) ;
push @switches, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 

print join( "\n", map { ("-" . $_) } @{ Term::Bash::Completion::Generator::de_getop_ify_list(\@switches)} ) . "\n" ;
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::PBSConfigSwitches  -

=head1 DESCRIPTION

I<GetOptions> returns a data structure containing the switches B<PBS> uses and some documentation. That
data structure is processed by I<Get_GetoptLong_Data> to produce a data structure suitable for use I<Getopt::Long::GetoptLong>.

I<DisplaySwitchHelp>, I<DisplayUserHelp> and I<DisplayHelp> also use that structure to display help.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
