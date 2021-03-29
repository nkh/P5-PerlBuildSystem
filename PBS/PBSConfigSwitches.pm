
package PBS::PBSConfigSwitches ;
use PBS::Debug ;

use v5.10 ;

use strict ;
use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(RegistredFlagsAndHelp) ;
our $VERSION = '0.04' ;

#use Data::Dumper ;
use Carp ;
use List::Util qw(max any);
use Sort::Naturally ;
use File::Slurp ;

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

my $success = 1 ;

while( my ($switch, $help1, $help2, $variable) = splice(@options, 0, 4))
	{
	for my $switch_unit ( split('\|', ($switch =~ s/(=|:).*$//r)) )
		{
		if(! exists $registred_flags{$switch_unit})
			{
			$registred_flags{$switch_unit} = "$file_name:$line" ;
			}
		else
			{
			$success = 0 ;
			Say Warning "In Plugin '$file_name:$line', switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'. Ignoring." ;
			}
		}
		
	push @registred_flags_and_help, $switch, $variable, $help1, $help2
		if $success ;
	}

$success ;
}

#-------------------------------------------------------------------------------

sub RegisterDefaultPbsFlags
{
my ($options) = GetOptions() ;

while(my ($switch) = splice(@$options, 0, 4))
	{
	for my $switch_unit ( split('\|', ($switch =~ s/(=|:).*$//r)) )
		{
		if(! exists $registred_flags{$switch_unit})
			{
			$registred_flags{$switch_unit} = "PBS reserved switch " . __PACKAGE__ ;
			}
		else
			{
			die ERROR "Switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'.\n" ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub Get_GetoptLong_Data
{
my ($options, @t) = @_  ;

my @c = @$options ; # don't splice caller's data

push @t, [ splice @c, 0, 4 ] while @c ;

map { $_->[0], $_->[3] } @t
}

#-------------------------------------------------------------------------------

sub GetOptions
{
my $config = shift // {} ;

$config->{BREAKPOINTS}                           //= [] ;
$config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT} //= [] ;
$config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX}     //= [] ;
$config->{COMMAND_LINE_DEFINITIONS}              //= {} ;
$config->{CONFIG_NAMESPACES}                     //= [] ;
$config->{DISPLAY_BUILD_INFO}                    //= [] ;
$config->{DISPLAY_DEPENDENCIES_REGEX_NOT}        //= [] ;
$config->{DISPLAY_DEPENDENCIES_REGEX}            //= [] ;
$config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT}    //= [] ;
$config->{DISPLAY_DEPENDENCIES_RULE_NAME}        //= [] ;
$config->{DISPLAY_NODE_ENVIRONMENT}              //= [] ;
$config->{DISPLAY_NODE_INFO}                     //= [] ;
$config->{DISPLAY_PBS_CONFIGURATION}             //= [] ;
$config->{DISPLAY_TEXT_TREE_REGEX}               //= [] ;
$config->{DISPLAY_TREE_FILTER}                   //= [] ;
$config->{DO_BUILD}                                = 1 ;
$config->{EXTERNAL_CHECKERS}                     //= [] ;
$config->{GENERATE_TREE_GRAPH_CLUSTER_NODE}      //= [] ;
$config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX}     //= [] ;
$config->{GENERATE_TREE_GRAPH_EXCLUDE}           //= [] ;
$config->{GENERATE_TREE_GRAPH_GROUP_MODE}          = GRAPH_GROUP_NONE ;
$config->{GENERATE_TREE_GRAPH_INCLUDE}           //= [] ;
$config->{GENERATE_TREE_GRAPH_SPACING}             = 1 ;
$config->{JOBS_DIE_ON_ERROR}                       = 0 ;
$config->{KEEP_ENVIRONMENT}                      //= [] ;
$config->{LIB_PATH}                              //= [] ;
$config->{LOG_NODE_INFO}                         //= [] ;
$config->{NODE_BUILD_ACTIONS}                    //= [] ;
$config->{NODE_ENVIRONMENT_REGEX}                //= [] ;
$config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX}  //= [] ;
$config->{PBS_QR_OPTIONS}                        //= [] ;
$config->{PLUGIN_PATH}                           //= [] ;
$config->{POST_PBS}                              //= [] ;
$config->{RULE_NAMESPACES}                       //= [] ;
$config->{SHORT_DEPENDENCY_PATH_STRING}            = '…' ;
$config->{SOURCE_DIRECTORIES}                    //= [] ;
$config->{TRIGGER}                                 = [] ;
$config->{USER_OPTIONS}                          //= {} ;
$config->{VERBOSITY}                             //= [] ;

my $load_config_closure = sub {LoadConfig(@_, $config) ;} ;

my @options =
	(
	'v|version', 'Displays Pbs version.', '',
		\$config->{DISPLAY_VERSION},
		
	'h|help', 'Displays this help.', '',
		\$config->{DISPLAY_HELP},
		
	'hs|help_switch=s', 'Displays help for the given switch.', '',
		\$config->{DISPLAY_SWITCH_HELP},
		
	'hnd|help_narrow_display', 'Writes the flag name and its explanation on separate lines.', '',
		\$config->{DISPLAY_HELP_NARROW_DISPLAY},

	'hud|help_user_defined', "Displays a user defined help. See 'Online help' in pbs.pod", <<'EOH', \$config->{DISPLAY_PBSFILE_POD},
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
	
	'pod_extract', 'Extracts the pod contained in the Pbsfile (except user documentation POD).', 'See --help_user_defined.',
		\$config->{PBS2POD},
		
	'pod_raw', '-pbsfile_pod or -pbs2pod is dumped in raw pod format.', '',
		\$config->{RAW_POD},
		
	'pod_interactive_documenation:s', 'Interactive PBS documentation display and search.', '',
		\$config->{DISPLAY_POD_DOCUMENTATION},
		
	'options_generate_bash_completion', 'create a bash completion script and exits.', '',
		\$config->{GENERATE_BASH_COMPLETION_SCRIPT},

	'options_get_completion', 'return completion list.', '',
		\$config->{GET_BASH_COMPLETION},

	'options_list', 'return completion list on stdout.', '',
		\$config->{GET_OPTIONS_LIST},

	'wizard:s', 'Starts a wizard.', '',
		\$config->{WIZARD},
		
	'wi|display_wizard_info', 'Shows Informatin about the found wizards.', '',
		\$config->{DISPLAY_WIZARD_INFO},
		
	'wh|display_wizard_help', 'Tell the choosen wizards to show help.', '',
		\$config->{DISPLAY_WIZARD_HELP},
		
	'c|color_depth=s', 'Set color depth. Valid values are 2 = no_color, 16 = 16 colors, 256 = 256 colors', '', \&PBS::Output::SetOutputColorDepth,

	'cu|color_user=s', "Set a color. Argument is a string with format 'color_name:ansi_code_string; eg: -cs 'user:cyan on_yellow'", <<EOT, \&PBS::Output::SetOutputColor,
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

	'output_info_label=s', 'Adds a text label to all output.', '',
		\&PBS::Output::InfoLabel,
		
	'output_indentation=s', 'set the text used to indent the output. This is repeated "subpbs level" times.', '',
		\$PBS::Output::indentation,

	'output_indentation_none', '', '',
		\$PBS::Output::no_indentation,

	'output_full_path', 'Display full path for files.', '',
		\$config->{DISPLAY_FULL_DEPENDENCY_PATH},
		
	'output_short_path_glyph=s', 'Replace full dependency_path with argument.', '',
		\$config->{SHORT_DEPENDENCY_PATH_STRING},
		
	'OFW|output_from_where', '', '',
		\$PBS::Output::output_from_where,

	'p|pbsfile=s', 'Pbsfile use to defines the build.', '',
		\$config->{PBSFILE},
		
	'pfn|pbsfile_names=s', 'string containing space separated file names that can be pbsfiles.', '',
		\$config->{PBSFILE_NAMES},
		
	'pfe|pbsfile_extensions=s', 'string containing space separated extensionss that can match a pbsfile.', '',
		\$config->{PBSFILE_EXTENSIONS},
		
	'prf|pbs_response_file=s', 'File containing switch definitions and targets.', '',
		\$config->{PBS_RESPONSE_FILE},
		
	'prfna|pbs_response_file_no_anonymous', 'Use only a response file named after the user or the one given on the command line.', '',
		\$config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
 
	'prfn|pbs_response_file_none', 'Don\'t use any response file.', '',
		\$config->{NO_PBS_RESPONSE_FILE},
		
	'pbs_options=s', 'start list subpbs options, argumet is a regex matching the target.', '',
		\$config->{PBS_OPTIONS},

	'pbs_options_local=s', 'as pbs_options but only applied at the local subpbs level.', '',
		\$config->{PBS_OPTIONS_LOCAL},

	'pbs_options_end', 'ends the list of options for specific subpbs.', '',
		\my $not_used,

	'path_lib=s', "Path to the pbs libs. Multiple directories can be given, each directory must start at '/' (root) or '.'", '',
		$config->{LIB_PATH},
	
	'path_lib_display', "Displays PBS lib paths (for the current project) and exits.", '',
		\$config->{DISPLAY_LIB_PATH},
		
	'path_no_default_warning', "When this switch is used, PBS will not display a warning when using the distribution's PBS lib and plugins.", '',
		\$config->{NO_DEFAULT_PATH_WARNING},
	
	'plugins_path=s', "Path to the pbs plugins. The directory must start at '/' (root) or '.' or pbs will display an error message and exit.", '',
		$config->{PLUGIN_PATH},
		
	'plugins_path_display', "Displays PBS plugin paths (for the current project) and exits.", '',
		\$config->{DISPLAY_PLUGIN_PATH},
	
	'plugins_load_info', "displays which plugins are loaded.", '',
		\$config->{DISPLAY_PLUGIN_LOAD_INFO},
	
	'plugins_runs', "displays which plugins subs are run.", '',
		\$config->{DISPLAY_PLUGIN_RUNS},
		
	'plugins_runs_all', "displays plugins subs not run.", '',
		\$config->{DISPLAY_PLUGIN_RUNS_ALL},
		
	'dpt|display_pbs_time', "Display where time is spend in PBS.", '',
		\$config->{DISPLAY_PBS_TIME},
		
	'dmt|display_minimum_time=f', "Don't display time if it is less than this value (in seconds, default 0.5s).", '',
		\$config->{DISPLAY_MINIMUM_TIME},
		
	'dptt|display_pbs_total_time', "Display How much time is spend in PBS.", '',
		\$config->{DISPLAY_PBS_TOTAL_TIME},
		
	'dpu|display_pbsuse', "displays which pbs module is loaded by a 'PbsUse'.", '',
		\$config->{DISPLAY_PBSUSE},
		
	'dpuv|display_pbsuse_verbose', "displays which pbs module is loaded by a 'PbsUse' (full path) and where the the PbsUse call was made.", '',
		\$config->{DISPLAY_PBSUSE_VERBOSE},
		
	'dput|display_pbsuse_time', "displays the time spend in 'PbsUse' for each pbsfile.", '',
		\$config->{DISPLAY_PBSUSE_TIME},
		
	'dputa|display_pbsuse_time_all', "displays the time spend in each pbsuse.", '',
		\$config->{DISPLAY_PBSUSE_TIME_ALL},
		
	'dpus|display_pbsuse_statistic', "displays 'PbsUse' statistic.", '',
		\$config->{DISPLAY_PBSUSE_STATISTIC},
		
	'display_md5_statistic', "displays 'MD5' statistic.", '',
		\$config->{DISPLAY_MD5_STATISTICS},
		
	'display_md5_time', "displays the time it takes to hash each node", '',
		\$PBS::Digest::display_md5_time,
		
	'build_directory=s', 'Directory where the build is to be done.', '',
		\$config->{BUILD_DIRECTORY},
		
	'mandatory_build_directory', 'PBS will not run unless a build directory is given.', '',
		\$config->{MANDATORY_BUILD_DIRECTORY},
		
	'sd|source_directory=s', 'Directory where source files can be found. Can be used multiple times.', <<EOT, $config->{SOURCE_DIRECTORIES},
Source directories are searched in the order they are given. The current 
directory is taken as the source directory if no --SD switch is given on
the command line. 

See also switches: --display_search_info --display_all_alternatives
EOT
	
	'rule_namespace=s', 'Rule name space to be used by DefaultBuild()', '',
		$config->{RULE_NAMESPACES},
		
	'config_namespace=s', 'Configuration name space to be used by DefaultBuild()', '',
		$config->{CONFIG_NAMESPACES},
		
	'save_config=s', 'PBS will save the config, used in each PBS run, in the build directory',
		"Before a subpbs is run, its start config will be saved in a file. PBS will display the filename so you "
		. "can load it later with '--load_config'. When working with a hirarchical build with configuration "
		. "defined at the top level, it may happend that you want to run pbs at lower levels but have no configuration, "
		. "your build will probably fail. Run pbs from the top level with '--save_config', then run the subpbs " 
		. "with the the saved config as argument to the '--load_config' option.",
		\$config->{SAVE_CONFIG},
		
	'load_config=s', 'PBS will load the given config before running the Pbsfile.', 'see --save_config.',
		$load_config_closure,
		
	'no_config_inheritance', 'Configuration variables are not iherited by child nodes/package.', '',
		\$config->{NO_CONFIG_INHERITANCE},
		
	'no_build', 'Cancel the build pass. Only the dependency and check passes are run.', '',
		\$config->{NO_BUILD},

	'fb|force_build', 'Debug flags cancel the build pass, this flag re-enables the build pass.', '',
		\$config->{FORCE_BUILD},
		
	'ns|no_stop', 'Continues building even if a node couldn\'t be buid. See --bi.', '',
		\$config->{NO_STOP},
		
	'do_immediate_build', 'do immediate build even if --no_build is set.', '',
		\$config->{DO_IMMEDIATE_BUILD},

	'cdabt|check_dependencies_at_build_time', 'Skipps the node build if no dependencies have changed or where rebuild to the same state.', '',
		\$config->{CHECK_DEPENDENCIES_AT_BUILD_TIME},

	'hsb|hide_skipped_builds', 'Builds skipped due to -check_dependencies_at_build_time are not displayed.', '',
		\$config->{HIDE_SKIPPED_BUILDS},

	'check_only_terminal_nodes', 'Skipps the checking of generated artefacts.', '',
		\$config->{DEBUG_CHECK_ONLY_TERMINAL_NODES},

	'nba|node_build_actions=s', 'actions that are run on a node at build time.',
		q~example: pbs -ke .  -nba '3::stop' -nba "trigger::priority 4::message '%name'" -trigger '.' -w 0  -fb -dpb0 -j 12 -nh~,
		$config->{NODE_BUILD_ACTIONS},

	'nh|no_header', 'PBS won\'t display the steps it is at. (Depend, Check, Build).', '',
		\$config->{DISPLAY_NO_STEP_HEADER},

	'nhc|no_header_counter', 'Hide depend counter', '',
		\$config->{DISPLAY_NO_STEP_HEADER_COUNTER},

	'nhnl|no_header_newline', 'add a new line instead for the counter', '',
		\$config->{DISPLAY_STEP_HEADER_NL},

	'dsi|display_subpbs_info', 'Display extra information for nodes matching a subpbs rule.', '',
		\$config->{DISPLAY_SUBPBS_INFO},
		
	'allow_virtual_to_match_directory', 'PBS won\'t display any warning if a virtual node matches a directory name.', '',
		\$config->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY},
		
	'link_no_external', 'Dependencies Linking from other Pbsfile stops the build if any local rule can match.', '',
		\$config->{NO_EXTERNAL_LINK},

	'lni|link_no_info', 'PBS won\'t display which dependency node are linked instead for generated.', '',
		\$config->{NO_LINK_INFO},

	'lnli|link_no_local_info', 'PBS won\'t display linking to local nodes.', '',
		\$config->{NO_LOCAL_LINK_INFO},

	'nlmi|no_local_match_info', 'PBS won\'t display a warning message if a linked node matches local rules.', '',
		\$config->{NO_LOCAL_MATCHING_RULES_INFO},
		
	'nwmwzd|no_warning_matching_with_zero_dependencies', 'PBS won\'t warn if a node has no dependencies but a matching rule.', '',
		\$config->{NO_WARNING_MATCHING_WITH_ZERO_DEPENDENCIES},
		
	'display_no_dependencies_ok', 'Display a message if a node was tagged has having no dependencies with HasNoDependencies.',
		"Non source files (nodes with digest) are checked for dependencies since they need to be build from something, "
		. "some nodes are generated from non files or don't always have dependencies as for C cache which dependency file "
		. "is created on the fly if it doens't exist.",
		\$config->{DISPLAY_NO_DEPENDENCIES_OK},

	'display_duplicate_info', 'PBS will display which dependency are duplicated for a node.', '',
		\$config->{DISPLAY_DUPLICATE_INFO},
	
	'ntii|no_trigger_import_info', 'PBS won\'t display which triggers are imported in a package.', '',
		\$config->{NO_TRIGGER_IMPORT_INFO},
	
	'nhnd|no_has_no_dependencies=s', 'PBS won\'t display warning if node does not have dependencies.', '',
		$config->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX},
		
	'q|quiet', 'Reduce the output from the command. See --bdn, --so, --sco.', '',
		\$config->{QUIET},
		
	'sc|silent_commands', 'shell commands are not echoed to the console.', '',
		\$PBS::Shell::silent_commands,
		
	'sco|silent_commands_output', 'shell commands output are not displayed, except if an error occures.', '',
		\$PBS::Shell::silent_commands_output,
		
	'ni|node_information=s', 'Display information about the node matching the given regex before the build.', '',
		$config->{DISPLAY_NODE_INFO},
	
	'nnr|no_node_build_rule', 'Rules used to depend a node are not displayed', '',
		\$config->{DISPLAY_NO_NODE_BUILD_RULES},

	'nnp|no_node_parents', "Don't display the node's parents.", '',
		\$config->{DISPLAY_NO_NODE_PARENTS},

	'nonil|no_node_info_links', 'Pbs inserts node_info files links in info_files and logs, disable it', '',
		\$config->{NO_NODE_INFO_LINKS},
	
	'nli|log_node_information=s', 'Log information about nodes matching the given regex before the build.', '',
		$config->{LOG_NODE_INFO},
		
	'nci|node_cache_information', 'Display if the node is from the cache.', '',
		\$config->{NODE_CACHE_INFORMATION},
		
	'nbn|node_build_name', 'Display the build name in addition to the logical node name.', '',
		\$config->{DISPLAY_NODE_BUILD_NAME},
		
	'no|node_origin', 'Display where the node has been inserted in the dependency tree.', '',
		\$config->{DISPLAY_NODE_ORIGIN},
		
	'np|node_parents', "Display the node's parents.", '',
		\$config->{DISPLAY_NODE_PARENTS},
		
	'nd|node_dependencies', 'Display the dependencies for a node.', '',
		\$config->{DISPLAY_NODE_DEPENDENCIES},
		
	'ne|node_environment=s', 'Display the environment variables for the nodes matching the regex.', '',
		$config->{DISPLAY_NODE_ENVIRONMENT},
		
	'ner|node_environment_regex=s', 'Display the environment variables  matching the regex.', '',
		$config->{NODE_ENVIRONMENT_REGEX},
		
	'nc|node_build_cause', 'Display why a node is to be build.', '',
		\$config->{DISPLAY_NODE_BUILD_CAUSE},
		
	'nr|node_build_rule', 'Display the rules used to depend a node (rule defining a builder ar tagged with [B].', '',
		\$config->{DISPLAY_NODE_BUILD_RULES},
		
	'nb|node_builder', 'Display the rule which defined the Builder and which command is being run.', '',
		\$config->{DISPLAY_NODE_BUILDER},
		
	'nconf|node_config', 'Display the config used to build a node.', '',
		\$config->{DISPLAY_NODE_CONFIG},
		
	'npbc|node_build_post_build_commands', 'Display the post build commands for each node.', '',
		\$config->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS},

	'ppbc|pbs_build_post_build_commands', 'Display the Pbs build post build commands.', '',
		\$config->{DISPLAY_PBS_POST_BUILD_COMMANDS},

	'o|origin', 'PBS will also display the origin of rules in addition to their names.', <<EOT, \$config->{ADD_ORIGIN},
The origin contains the following information:
	* Name
	* Package
	* Namespace
	* Definition file
	* Definition line
EOT

	'j|jobs=i', 'Maximum number of build commands run in parallel.', '',
		\$config->{JOBS},
		
	'jdoe|jobs_die_on_errors=i', '0 (default) finish running jobs. 1 die immediatly. 2 build as much as possible.', '',
		\$config->{JOBS_DIE_ON_ERROR},
		
	'pj|pbs_jobs=i', 'Maximum number of dependers run in parallel.', '',
		\$config->{PBS_JOBS},
		
	'dp|depend_processes=i', 'Maximum number of depend processes.', '',
		\$config->{DEPEND_PROCESSES},
		
	'cj|check_jobs=i', 'Maximum number of checker run in parallel.',
		'Depending on the amount of nodes and their size, running checks in parallel can reduce check time, YMMV.',
		\$config->{CHECK_JOBS},

	'ce|external_checker=s', 'external list of changed nodes',
		'pbs -ce <(git status --short --untracked-files=no | perl -ae "print \"$PWD/\$F[1]\n\"")',
		$config->{EXTERNAL_CHECKERS},

	'distribute=s', 'Define where to distribute the build.',
		'The file should return a list of hosts in the format defined by the default distributor '
		 .'or define a distributor.',
		\$config->{DISTRIBUTE},
		 
	'display_shell_info', 'Displays which shell executes a command.', '',
		\$config->{DISPLAY_SHELL_INFO},
		
	'dbi|display_builder_info', 'Displays if a node is build by a perl sub or shell commands.', '',
		\$config->{DISPLAY_BUILDER_INFORMATION},
		
	'time_builders', 'Displays the total time a builders took to run.', '',
		\$config->{TIME_BUILDERS},
		
	'dji|display_jobs_info', 'PBS will display extra information about the parallel build.', '',
		\$config->{DISPLAY_JOBS_INFO},

	'djr|display_jobs_running', 'PBS will display which nodes are under build.', '',
		\$config->{DISPLAY_JOBS_RUNNING},

	'djnt|display_jobs_no_tally', 'will not display nodes tally.', '',
		\$config->{DISPLAY_JOBS_NO_TALLY},

	'l|log|create_log', 'Create a log for the build',
		'Node build output is always kept in the build directory.',
		\$config->{CREATE_LOG},
		
	'log_tree', 'Add a tree dump to the log, an option as during incremental build this takes most of the time.', '',
		\$config->{LOG_TREE},
		
	'log_html|create_log_html', 'create a html log for each node, implies --create_log ', '',
		\$config->{CREATE_LOG_HTML},
		
	#----------------------------------------------------------------------------------
		
	'dpos|display_original_pbsfile_source', 'Display original Pbsfile source.', '',
		\$config->{DISPLAY_PBSFILE_ORIGINAL_SOURCE},
		
	'dps|display_pbsfile_source', 'Display Modified Pbsfile source.', '',
		\$config->{DISPLAY_PBSFILE_SOURCE},
		
	'dpc|display_pbs_configuration=s', 'Display the pbs configuration matching  the regex.', '',
		$config->{DISPLAY_PBS_CONFIGURATION},
		
	'dpcl|display_configuration_location', 'Display the pbs configuration location.', '',
		\$config->{DISPLAY_PBS_CONFIGURATION_LOCATION},
		
	'dec|display_error_context', 'When set and if an error occures in a Pbsfile, PBS will display the error line.', '',
		\$PBS::Output::display_error_context,
		
	'display_no_perl_context', 'When displaying an error with context, do not parse the perl code to find the context end.', '',
		\$config->{DISPLAY_NO_PERL_CONTEXT},
		
	'dpl|display_pbsfile_loading', 'Display which pbsfile is loaded.', '',
		\$config->{DISPLAY_PBSFILE_LOADING},
		
	'dplt|display_pbsfile_load_time', 'Display the time to load and evaluate a pbsfile.', '',
		\$config->{DISPLAY_PBSFILE_LOAD_TIME},
		
	'dspd|display_subpbs_definition', 'Display subpbs definition.', '',
		\$config->{DISPLAY_SUB_PBS_DEFINITION},
		
	'dspc|display_subpbs_config', 'Display subpbs config.', '',
		\$config->{DISPLAY_SUB_PBS_CONFIG},
		
	'dcu|display_config_usage', 'Display config variables not used.', '',
		\$config->{DISPLAY_CONFIG_USAGE},
		
	'dncu|display_node_config_usage', 'Display config variables not used by nodes.', '',
		\$config->{DISPLAY_NODE_CONFIG_USAGE},
		
	'display_target_path_usage', "Don't remove TARGET_PATH from config usage report.", '',
		\$config->{DISPLAY_TARGET_PATH_USAGE},
		
	'dpn|display_nodes_per_pbsfile', 'Display how many nodes where added by each pbsfile run.', '',
		\$config->{DISPLAY_NODES_PER_PBSFILE},
		
	'dpnn|display_nodes_per_pbsfile_names', 'Display which nodes where added by each pbsfile run.', '',
		\$config->{DISPLAY_NODES_PER_PBSFILE_NAMES},
		
	'dl|depend_log', 'Created a log for each subpbs.', '',
		\$config->{DEPEND_LOG},
		
	'dlm|depend_log_merged', 'Merge children subpbs output in log.', '',
		\$config->{DEPEND_LOG_MERGED},
		
	'dfl|depend_full_log', 'Created a log for each subpbs with extra display options set. Logs are not merged', '',
		\$config->{DEPEND_FULL_LOG},
		
	'dflo|depend_full_log_options=s', 'Set extra display options for full log.', '',
		\$config->{DEPEND_FULL_LOG_OPTIONS},
		
	'ddi|display_depend_indented', 'Add indentation before node.', '',
		\$config->{DISPLAY_DEPEND_INDENTED},
		
	'dds|display_depend_separator=s', 'Display a separator between nodes.', '',
		\$config->{DISPLAY_DEPEND_SEPARATOR},
		
	'ddnl|display_depend_new_line', 'Display an extra blank line araound a depend.', '',
		\$config->{DISPLAY_DEPEND_NEW_LINE},
		
	'dde|display_depend_end', 'Display when a depend ends.', '',
		\$config->{DISPLAY_DEPEND_END},
		
	'ddplg|log_parallel_depend', 'Creates a log of the parallel depend.', '',
		\$config->{LOG_PARALLEL_DEPEND},

	'dpds|display_parallel_depend_start', 'Display a message when a parallel depend starts.', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_START},

	'dpde|display_parallel_depend_end', 'Display a message when a parallel depend end.', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_END},

	'dpdn|display_parallel_depend_node', 'Display the node name in parallel depend end messages.', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_NODE},

	'dpdnr|display_parallel_depend_no_resource', 'Display a message when a parallel depend could be done but no resource is available.', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE},

	'ddpl|display_parallel_depend_linking', 'Display parallel depend linking result.', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_LINKING},

	'ddplv|display_parallel_depend_linking_verbose', 'Display a verbose parallel depend linking result.', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE},

	'ddtt|display_parallel_depend_tree', 'Display the distributed dependency graph using a text dumper', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_TREE},

	'ddttp|display_parallel_depend_process_tree', 'Display the distributed process graph using a text dumper', '',
		\$config->{DISPLAY_PARALLEL_DEPEND_PROCESS_TREE},

	'ddrp|display_depend_remaining_processes', 'Display how many depend processes are running after the main depend process ended.', '',
		\$config->{DISPLAY_DEPEND_REMAINING_PROCESSES},

	'dpuc|depend_parallel_use_compression', 'Compress graphs before sending them', '',
		\$config->{DEPEND_PARALLEL_USE_COMPRESSION},

	'display_too_many_nodes_warning=i', 'Display a warning when a pbsfile adds too many nodes.', '',
		\$config->{DISPLAY_TOO_MANY_NODE_WARNING},

	'display_rule_to_order', 'Display that there are rules order.', '',
		\$config->{DISPLAY_RULES_TO_ORDER},
		
	'display_rule_order', 'Display the order rules.', '',
		\$config->{DISPLAY_RULES_ORDER},
		
	'display_rule_ordering', 'Display the pbsfile used to order rules and the rules order.', '',
		\$config->{DISPLAY_RULES_ORDERING},
		
	'rro|rule_run_once', 'Rules run only once except if they are tagged as MULTI', '',
		\$config->{RULE_RUN_ONCE},
		
	'rns|rule_no_scope', 'Disable rule scope.', '',
		\$config->{RULE_NO_SCOPE},
		
	'display_rule_scope', 'display scope parsing and generation', '',
		\$config->{DISPLAY_RULE_SCOPE},
		
	'maximum_rule_recursion', 'Set the maximum rule recusion before pbs, aborts the build', '',
		\$config->{MAXIMUM_RULE_RECURSION},
		
	'rule_recursion_warning', 'Set the level at which pbs starts warning aabout rule recursion', '',
		\$config->{RULE_RECURSION_WARNING},
		
	'dnmr|display_non_matching_rules', 'Display the rules used during the dependency pass.', '',
		\$config->{DISPLAY_NON_MATCHING_RULES},
		
	'dur|display_used_rules', 'Display the rules used during the dependency pass.', '',
		\$config->{DISPLAY_USED_RULES},
		
	'durno|display_used_rules_name_only', 'Display the names of the rules used during the dependency pass.', '',
		\$config->{DISPLAY_USED_RULES_NAME_ONLY},
		
	'dar|display_all_rules', 'Display all the registred rules.',
		'If you run a hierarchical build, these rules will be dumped every time a package runs a dependency step.',
		\$config->{DISPLAY_ALL_RULES},
		
	'dc|display_config', 'Display the config used during a Pbs run (simplified and from the used config namespaces only).', '',
		\$config->{DISPLAY_CONFIGURATION},
		
	'dcs|display_config_start', 'Display the config to be used in a Pbs run before loading the Pbsfile', '',
		\$config->{DISPLAY_CONFIGURATION_START},
		
        'display_config_delta', 'Display the delta between the parent config and the config after the Pbsfile is run.', '',
		\$config->{DISPLAY_CONFIGURATION_DELTA},
					
	'dcn|display_config_namespaces', 'Display the config namespaces used during a Pbs run (even unused config namspaces).', '',
		\$config->{DISPLAY_CONFIGURATION_NAMESPACES},
		
	'dac|display_all_configs', '(DF). Display all configurations.', '',
		\$config->{DEBUG_DISPLAY_ALL_CONFIGURATIONS},
		
	'dam|display_configs_merge', '(DF). Display how configurations are merged.', '',
		\$config->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE},
		
	'display_package_configuration', 'If PACKAGE_CONFIGURATION for a subpbs exists, it will be displayed if this option is set (also displayed when --dc is set)', '',
		\$config->{DISPLAY_PACKAGE_CONFIGURATION},
		
	'no_silent_override', 'Makes all SILENT_OVERRIDE configuration visible.', '',
		\$config->{NO_SILENT_OVERRIDE},
		
	'display_subpbs_search_info', 'Display information about how the subpbs files are found.', '',
		\$config->{DISPLAY_SUBPBS_SEARCH_INFO},
		
	'display_all_subpbs_alternatives', 'Display all the subpbs files that could match.', '',
		\$config->{DISPLAY_ALL_SUBPBS_ALTERNATIVES},
		
	'dsd|display_source_directory', 'display all the source directories (given through the -sd switch ot the Pebsfile).', '',
		\$config->{DISPLAY_SOURCE_DIRECTORIES},
		
	'display_search_info', 'Display the files searched in the source directories. See --daa.', <<EOT, \$config->{DISPLAY_SEARCH_INFO},
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

	'daa|display_all_alternates', 'Display all the files found in the source directories.', <<EOT, \$config->{DISPLAY_SEARCH_ALTERNATES},
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
	'dr|display_rules', '(DF) Display which rules are registred. and which rule packages are queried.', '',
		\$config->{DEBUG_DISPLAY_RULES},
		
	'dir|display_inactive_rules', 'Display rules present i the åbsfile but tagged as NON_ACTIVE.', '',
		\$config->{DISPLAY_INACTIVE_RULES},
		
	'drd|display_rule_definition', '(DF) Display the definition of each registrated rule.', '',
		\$config->{DEBUG_DISPLAY_RULE_DEFINITION},
		
	'drs|display_rule_statistics', '(DF) Display rule statistics after each pbs run.', '',
		\$config->{DEBUG_DISPLAY_RULE_STATISTICS},
		
	'dtr|display_trigger_rules', '(DF) Display which triggers are registred. and which trigger packages are queried.', '',
		\$config->{DEBUG_DISPLAY_TRIGGER_RULES},
		
	'dtrd|display_trigger_rule_definition', '(DF) Display the definition of each registrated trigger.', '',
		\$config->{DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION},
		
	# -------------------------------------------------------------------------------	
	'dpbcr|display_post_build_commands_registration', '(DF) Display the registration of post build commands.', '',
		\$config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION},
		
	'dpbcd|display_post_build_command_definition', '(DF) Display the definition of post build commands when they are registered.', '',
		\$config->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION},
		
	'dpbc|display_post_build_commands', '(DF) Display which post build command will be run for a node.', '',
		\$config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS},
		
	'dpbcre|display_post_build_result', 'Display the result code and message returned buy post build commands.', '',
		\$config->{DISPLAY_POST_BUILD_RESULT},
		
	#-------------------------------------------------------------------------------	
	'dd|display_dependencies', '(DF) Display the dependencies for each file processed.', '',
		\$config->{DEBUG_DISPLAY_DEPENDENCIES},
		
	'dh|depend_header', "Show depend header.", '',
		\$config->{DISPLAY_DEPEND_HEADER},
		
	'ddl|display_dependencies_long', '(DF) Display one dependency perl line.', '',
		\$config->{DEBUG_DISPLAY_DEPENDENCIES_LONG},
		
	'ddt|display_dependency_time', ' Display the time spend in each Pbsfile.', '',
		\$config->{DISPLAY_DEPENDENCY_TIME},
		
	'dct|display_check_time', ' Display the time spend checking the dependency tree.', '',
		\$config->{DISPLAY_CHECK_TIME},
		
	'dre|dependency_result', 'Display the result of each dependency step.', '',
		\$config->{DISPLAY_DEPENDENCY_RESULT},
		
	'ddrr|display_dependencies_regex=s', 'Node matching the regex are displayed.', '',
		$config->{DISPLAY_DEPENDENCIES_REGEX},
		
	'ddrrn|display_dependencies_regex_not=s', 'Node matching the regex are not displayed.', '',
		$config->{DISPLAY_DEPENDENCIES_REGEX_NOT},
		
	'ddrn|display_dependencies_rule_name=s', 'Node matching rules matching the regex are displayed.', '',
		$config->{DISPLAY_DEPENDENCIES_RULE_NAME},
		
	'ddrnn|display_dependencies_rule_name_not=s', 'Node matching rules matching the regex are not displayed.', '',
		$config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT},
		
	'dnsr|display_node_subs_run', 'Show when a node sub is run.', '',
		\$config->{DISPLAY_NODE_SUBS_RUN},

	'trace_pbs_stack', '(DF) Display the call stack within pbs runs.', '',
		\$config->{DEBUG_TRACE_PBS_STACK},
		
	'ddrd|display_dependency_rule_definition', 'Display the definition of the rule that generates a dependency.', '',
		\$config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION},
		
	'ddr|display_dependency_regex', '(DF) Display the regex used to depend a node.', '',
		\$config->{DEBUG_DISPLAY_DEPENDENCY_REGEX},
		
	'ddmr|display_dependency_matching_rule', 'Display the rule which matched the node.', '',
		\$config->{DISPLAY_DEPENDENCY_MATCHING_RULE},
		
	'ddfp|display_dependency_full_pbsfile', 'in conjonction with --display_dependency_matching_rule, display the fullpbsfile path rather than relative to target.', '',
		\$config->{DISPLAY_DEPENDENCIES_FULL_PBSFILE},
		
	'ddir|display_dependency_insertion_rule', 'Display the rule which added the node.', '',
		\$config->{DISPLAY_DEPENDENCY_INSERTION_RULE},
		
	'dlmr|display_link_matching_rule', 'Display the rule which matched the node that is being linked.', '',
		\$config->{DISPLAY_LINK_MATCHING_RULE},
		
	'dtin|display_trigger_inserted_nodes', '(DF) Display the nodes inserted because of a trigger.', '',
		\$config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES},
		
	'dt|display_triggered', '(DF) Display the files that need to be rebuild and why they need so.', '',
		\$config->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES},
		
	'display_digest_exclusion', 'Display when an exclusion or inclusion rule for a node matches.', '',
		\$config->{DISPLAY_DIGEST_EXCLUSION},
		
	'display_digest', 'Display the expected and the actual digest for each node.', '',
		\$config->{DISPLAY_DIGEST},
		
	'dddo|display_different_digest_only', 'Only display when a digest are diffrent.', '',
		\$config->{DISPLAY_DIFFERENT_DIGEST_ONLY},
		
	'DNDC|devel_no_distribution_check', 'A development flag, not for user.', <<EOT, \$config->{DEVEL_NO_DISTRIBUTION_CHECK},
Pbs checks its distribution when building and rebuilds everything if it has changed.

While developping we are constantly changing the distribution but want to see the effect
of the latest change without rebuilding everything which makes finding the effect of the
latest change more difficult.
EOT

	'wnmw|warp_no_md5_warning', 'Do not display a warning if the file to compute hash for does not exist during warp verification.', '',
		\$config->{WARP_NO_DISPLAY_DIGEST_FILE_NOT_FOUND},
		
	'dfc|display_file_check', 'Display hash checking for individual files.', '',
		\$config->{DISPLAY_FILE_CHECK},
		
	'display_cyclic_tree', '(DF) Display the portion of the dependency tree that is cyclic', '',
		\$config->{DEBUG_DISPLAY_CYCLIC_TREE},
		
	'no_source_cyclic_warning', 'No warning is displayed if a cycle involving source files is found.', '',
		\$config->{NO_SOURCE_CYCLIC_WARNING},
		
	'die_source_cyclic_warning', 'Die if a cycle involving source files is found (default is warn).', '',
		\$config->{DIE_SOURCE_CYCLIC_WARNING},
		
	'tt|text_tree', '(DF) Display the dependency tree using a text dumper', '',
		\$config->{DEBUG_DISPLAY_TEXT_TREE},
		
	'ttmr|text_tree_match_regex:s', 'limits how many trees are displayed.', '',
		$config->{DISPLAY_TEXT_TREE_REGEX},
		
	'ttmm|text_tree_match_max:i', 'limits how many trees are displayed.', '',
		\$config->{DISPLAY_TEXT_TREE_MAX_MATCH},
		
	'ttf|text_tree_filter=s', '(DF) List the fields that are to be displayed when -tt is active. The switch can be used multiple times.', '',
		$config->{DISPLAY_TREE_FILTER},
		
	'tta|text_tree_use_ascii', 'Use ASCII characters instead for Ansi escape codes to draw the tree.', '',
		\$config->{DISPLAY_TEXT_TREE_USE_ASCII},
		
	'ttdhtml|text_tree_use_dhtml=s', 'Generate a dhtml dump of the tree in the specified file.', '',
		\$config->{DISPLAY_TEXT_TREE_USE_DHTML},
		
	'ttmd|text_tree_max_depth=i', 'Limit the depth of the dumped tree.', '',
		\$config->{DISPLAY_TEXT_TREE_MAX_DEPTH},
		
	'tno|tree_name_only', '(DF) Display the name of the nodes only.', '',
		\$config->{DEBUG_DISPLAY_TREE_NAME_ONLY},
		
	'vas|visualize_after_subpbs', '(DF) visualization plugins run after every subpbs.', '',
		\$config->{DEBUG_VISUALIZE_AFTER_SUPBS},
		
	'tda|tree_depended_at', '(DF) Display which Pbsfile was used to depend each node.', '',
		\$config->{DEBUG_DISPLAY_TREE_DEPENDED_AT},
		
	'tia|tree_inserted_at', '(DF) Display where the node was inserted.', '',
		\$config->{DEBUG_DISPLAY_TREE_INSERTED_AT},
		
	'tnd|tree_display_no_dependencies', '(DF) Don\'t show child nodes data.', '',
		\$config->{DEBUG_DISPLAY_TREE_NO_DEPENDENCIES},
		
	'tad|tree_display_all_data', 'Unset data within the tree are normally not displayed. This switch forces the display of all data.', '',
		\$config->{DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA},
		
	'tnb|tree_name_build', '(DF) Display the build name of the nodes. Must be used with --tno', '',
		\$config->{DEBUG_DISPLAY_TREE_NAME_BUILD},
		
	'tntr|tree_node_triggered_reason', '(DF) Display why a node is to be rebuild.', '',
		\$config->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON},
		
	'tm|tree_maxdepth=i', 'Maximum depth of the structures displayed by pbs.', '',
		\$config->{MAX_DEPTH},
		
	'ti|tree_indentation=i', 'Data dump indent style (0-1-2).', '',
		\$config->{INDENT_STYLE},
		
	#-------------------------------------------------------------------------------	

	'TN|trigger_none', '(DF) As if no node triggered, see --trigger', '',
		\$config->{DEBUG_TRIGGER_NONE},
		
	'T|trigger=s', '(DF) Force the triggering of a node if you want to check its effects.', '',
		$config->{TRIGGER},
		
	'TA|trigger_all', '(DF) As if all node triggered, see --trigger', '',
		\$config->{DEBUG_TRIGGER_ALL},
		
	'TL|trigger_list=s', '(DF) Points to a file containing trigers.', '',
		\$config->{DEBUG_TRIGGER_LIST},

	'TD|display_trigger', '(DF) display which files are processed and triggered', '',
		\$config->{DEBUG_DISPLAY_TRIGGER},

	'TDM|display_trigger_match_only', '(DF) display only files which are triggered', '',
		\$config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY},

	#-------------------------------------------------------------------------------	

	'gtg|generate_tree_graph=s', 'Generate a graph for the dependency tree. Give the file name as argument.', '',
		\$config->{GENERATE_TREE_GRAPH},
		
	'gtg_p|generate_tree_graph_package', 'Groups the node by definition package.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE},
		
	'gtg_canonical=s', 'Generates a canonical dot file.', '',
		\$config->{GENERATE_TREE_GRAPH_CANONICAL},
		
	'gtg_format=s', 'chose graph format between: svg (default), ps, png.', '',
		\$config->{GENERATE_TREE_GRAPH_FORMAT},
		
	'gtg_html=s', 'Generates a set of html files describing the build tree.', '',
		\$config->{GENERATE_TREE_GRAPH_HTML},
		
	'gtg_html_frame', 'The use a frame in the graph html.', '',
		\$config->{GENERATE_TREE_GRAPH_HTML_FRAME},
		
	'gtg_snapshots=s', 'Generates a serie of snapshots from the build.', '',
		\$config->{GENERATE_TREE_GRAPH_SNAPSHOTS},
		
	'gtg_cn=s', 'The node given as argument and its dependencies will be displayed as a single unit. Multiple gtg_cn allowed.', '',
		$config->{GENERATE_TREE_GRAPH_CLUSTER_NODE},
		
	'gtg_cr=s', 'Put nodes matching the given regex in a node named as the regx. Multiple gtg_cr allowed.', <<'EOT', $config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX},
$> pbs -gtg_cr '\.c$' --gtg

create a graph where all the .c files are clustered in a single node named '.c$'
EOT
	'gtg_crl=s', 'List of regexes, as if you gave multiple --gtg_cr, one per line', '',
		\$config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST},
		
	'gtg_sd|generate_tree_graph_source_directories', 'As generate_tree_graph but groups the node by source directories, uncompatible with --generate_tree_graph_package.', '',
		\$config->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES},
		
	'gtg_exclude|generate_tree_graph_exclude=s', "Exclude nodes and their dependenies from the graph.", '',
		$config->{GENERATE_TREE_GRAPH_EXCLUDE},
		
	'gtg_include|generate_tree_graph_include=s', "Forces nodes and their dependencies back into the graph.",
		'Ex: pbs -gtg tree -gtg_exclude "*.c" - gtg_include "name.c".',
		$config->{GENERATE_TREE_GRAPH_INCLUDE},
		
	'gtg_bd', 'The build directory for each node is displayed.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY},
		
	'gtg_rbd', 'The build directory for the root is displayed.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY},
		
	'gtg_tn', 'Node inserted by Triggerring are also displayed.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES},
		
	'gtg_config', 'Configs are also displayed.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG},
		
	'gtg_config_edge', 'Configs are displayed as well as an edge from the nodes using it.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE},
		
	'gtg_pbs_config', 'Package configs are also displayed.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG},
		
	'gtg_pbs_config_edge', 'Package configs are displayed as well as an edge from the nodes using it.', '',
		\$config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE},
		
	'gtg_gm|generate_tree_graph_group_mode=i', 'Set the grouping mode.0 no grouping, 1 main tree is grouped (default), 2 each tree is grouped.', '',
		\$config->{GENERATE_TREE_GRAPH_GROUP_MODE},
		
	'gtg_spacing=f', 'Multiply node spacing with given coefficient.', '',
		\$config->{GENERATE_TREE_GRAPH_SPACING},
		
	'gtg_printer|generate_tree_graph_printer', 'Non triggerring edges are displayed as dashed lines.', '',
		\$config->{GENERATE_TREE_GRAPH_PRINTER},
		
	'gtg_sn|generate_tree_graph_start_node=s', 'Generate a graph from the given node.', '',
		\$config->{GENERATE_TREE_GRAPH_START_NODE},
		
	#-------------------------------------------------------------------------------	

	'a|ancestors=s', '(DF) Display the ancestors of a file and the rules that inserted them.', '',
		\$config->{DEBUG_DISPLAY_PARENT},
		
	'dbsi|display_build_sequencer_info', 'Display information about which node is build.', '',
		\$config->{DISPLAY_BUILD_SEQUENCER_INFO},

	'dbs|display_build_sequence', '(DF) Dumps the build sequence data.', '',
		\$config->{DEBUG_DISPLAY_BUILD_SEQUENCE},
		
	'dbss|display_build_sequence_simple', '(DF) List the nodes to be build.', '',
		\$config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE},
		

	'dbsss|display_build_sequence_simple_stats', '(DF) display number of nodes to be build.', '',
		\$config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE_STATS_ONLY},
		
	'save_build_sequence_simple=s', 'Save a list of nodes to be build to a file.', '',
		\$config->{SAVE_BUILD_SEQUENCE_SIMPLE},
		
	'f|files|nodes', 'Show all the nodes in the current_dependency tree and their final location.',
		'In warp only shows the nodes that have triggered, see option nodes_all for all nodes',
		\$config->{DISPLAY_FILE_LOCATION},

	'fa|files_all|nodes_all', 'Show all the nodes in the current_dependency tree and their final location.', '',
		\$config->{DISPLAY_FILE_LOCATION_ALL},

	'bi|build_info=s', 'Options: --b --d --bc --br. A file or \'*\' can be specified. No Build is done.', '',
		$config->{DISPLAY_BUILD_INFO},
		
	'nbh|no_build_header', "Don't display the name of the node to be build.", '',
		\$config->{DISPLAY_NO_BUILD_HEADER},
		
	'bpb0|display_no_progress_bar', "Display no progress bar.", '',
		\$config->{DISPLAY_NO_PROGRESS_BAR},

	'bpb1|display_progress_bar', "Force silent build mode and displays a progress bar. This is Pbs default, see --build_verbose.", '',
		\$config->{DISPLAY_PROGRESS_BAR},

	'bpb2|display_progress_bar_file', "Built node names are displayed above the progress bar", '',
		\$config->{DISPLAY_PROGRESS_BAR_FILE},

	'bpb3|display_progress_bar_process', "A progress per build process is displayed above the progress bar", '',
		\$config->{DISPLAY_PROGRESS_BAR_PROCESS},

	'bv|build_verbose', "Verbose build mode.", <<EOT, \$config->{BUILD_AND_DISPLAY_NODE_INFO},
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

	'bvm|display_no_progress_bar_minimum', "Slightly less verbose build mode.", '',
		\$config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM},
	
	'bvmm|display_no_progress_bar_minimum_minimum', "Definitely less verbose build mode.", '',
		\$config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2},

	'bre|display_build_result', 'Shows the result returned by the builder.', '',
		\$config->{DISPLAY_BUILD_RESULT},
		
	'bn|box_node', 'Display a colored margin for each node display.', '',
		\$config->{BOX_NODE},

	'bnir|build_and_display_node_information_regex=s', 'Only display information for matching nodes.', '',
		$config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX},

	'bnirn|build_and_display_node_information_regex_not=s', "Don't  display information for matching nodes.", '',
		$config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT},

	'bni_result', 'display node header and build result even if not matched by --bnir.', '',
		\$config->{BUILD_DISPLAY_RESULT},

	'verbosity=s', 'Used in user defined modules.', <<EOT, $config->{VERBOSITY},
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

	'u|user_option=s', 'options to be passed to the Build sub.', '',
		$config->{USER_OPTIONS},
		
	'D=s', 'Command line definitions.', '',
		$config->{COMMAND_LINE_DEFINITIONS},

	#----------------------------------------------------------------------------------

	'ek|keep_environment=s', "Pbs empties %ENV, user --ke 'regex' to keep specific variables.", '',
		$config->{KEEP_ENVIRONMENT},

	'ed|display_environment', "Display which environment variables are kept and discarded", '',
		\$config->{DISPLAY_ENVIRONMENT},

	'edk|display_environment_kept', "Only display the evironment variables kept", '',
		\$config->{DISPLAY_ENVIRONMENT_KEPT},

	'es|display_environment_statistic', "Display a statistics about environment variables", '',
		\$config->{DISPLAY_ENVIRONMENT_STAT},

	#----------------------------------------------------------------------------------

	'hdp|http_display_post', 'Display a message when a POST is send.', '',
		\$config->{HTTP_DISPLAY_POST},

	'hdg|http_display_get', 'Display a message when a GET is send.', '',
		\$config->{HTTP_DISPLAY_GET},

	'hdss|http_display_server_start', 'Display a message when a server is started.', '',
		\$config->{HTTP_DISPLAY_SERVER_START},

	'hdssd|http_display_server_shutdown', 'Display a message when a server is sshutdown.', '',
		\$config->{HTTP_DISPLAY_SERVER_SHUTDOWN},

	'hdr|http_display_request', 'Display a message when a request is received.', '',
		\$config->{HTTP_DISPLAY_REQUEST},

	'dus|use_depend_server', 'Display a message on resource events.', '',
		\$config->{USE_DEPEND_SERVER},

	'rde|resource_display_event', 'Display a message on resource events.', '',
		\$config->{DISPLAY_RESOURCE_EVENT},

	'rqsd|resource_quick_shutdown', '', '',
		\$config->{RESOURCE_QUICK_SHUTDOWN},

	#----------------------------------------------------------------------------------
	
	'bp|debug:s', 'Enable debug support A startup file defining breakpoints can be given.', '',
		$config->{BREAKPOINTS},

	'bph|debug_display_breakpoint_header', 'Display a message when a breakpoint is run.', '',
		\$config->{DISPLAY_BREAKPOINT_HEADER},

	'dump', 'Dump an evaluable tree.', '',
		\$config->{DUMP},
		
	#----------------------------------------------------------------------------------
	
	'dwfn|display_warp_file_name', "Display the name of the warp file on creation or use.", '',
		\$config->{DISPLAY_WARP_FILE_NAME},
		
	'display_warp_time', "Display the time spend in warp creation or use.", '',
		\$config->{DISPLAY_WARP_TIME},
		
	'w|warp=s', "specify which warp to use.", '',
		\$config->{WARP},
		
	'warp_human_format', "Generate warp file in a readable format.", '',
		\$config->{WARP_HUMAN_FORMAT},
		
	'no_pre_build_warp', "no pre-build warp will be generated.", '',
		\$config->{NO_PRE_BUILD_WARP},
		
	'no_post_build_warp', "no post-build warp will be generated.", '',
		\$config->{NO_POST_BUILD_WARP},
		
	'display_warp_checked_nodes', "Display which nodes are contained in the warp tree and their status.", '',
		\$config->{DISPLAY_WARP_CHECKED_NODES},
			
	'display_warp_checked_nodes_fail_only', "Display which nodes, in the warp tree, has a different MD5.", '',
		\$config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY},
			
	'display_warp_removed_nodes', "Display which nodes are removed during warp.", '',
		\$config->{DISPLAY_WARP_REMOVED_NODES},
			
	'display_warp_triggered_nodes', "Display which nodes are removed from the warp tree and why.", '',
		\$config->{DISPLAY_WARP_TRIGGERED_NODES},

	#----------------------------------------------------------------------------------
	
	'post_pbs=s', "Run the given perl script after pbs. Usefull to generate reports, etc.", '',
		$config->{POST_PBS},
		
	) ;

my @rfh = @registred_flags_and_help ;

while( my ($switch, $help1, $help2, $variable) = splice(@rfh, 0, 4))
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

    push @options, $switch, $help1, $help2, $variable ;
    }

\@options, $config ;
}

#-------------------------------------------------------------------------------

sub AliasOptions
{
my ($arguments) = @_ ;

my ($alias_file, %aliases) = ('pbs_option_aliases') ;

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


@{$arguments} = map { /^-+/ && exists $aliases{s/^-+//r} ? @{$aliases{s/^-+//r}} : $_ } @$arguments ;

\%aliases
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
	die ERROR("Config: error loading file'$file_name'") . "\n" ;
	}
else
	{
	Say Info "Config: loading '$file_name'" unless $message_displayed ;
	$message_displayed++ ;

	$pbs_config->{LOADED_CONFIG} = $loaded_config ;
	}
}

#-------------------------------------------------------------------------------

sub DisplayHelp { _DisplayHelp($_[0], 0, GetOptionsElements()) }                    

sub DisplaySwitchHelp
{
my ($switch) = @_ ;

my (@t, @matches) = (GetOptionsElements()) ;

HELP:
for my $option (@t)
	{
	my $name = $option->[0] ;
	
	for my $element (split /\|/, $name)
		{
		if( $element =~ /^$switch\s*(=*.)*$/ )
			{
			push @matches, $option ;
			last HELP ;
			}
		}
	}

_DisplayHelp(0, 1, @matches) ;
}

sub DisplaySwitchesHelp
{
my (@switches) = @_ ;

my @matches ;

for my $option (sort { $a->[0] cmp $b->[0] } GetOptionsElements())
	{
	for my $option_element (split /\|/, $option->[0])
		{
		$option_element =~ s/=.*$// ;

		if( any { $_ eq $option_element} @switches )
			{
			push @matches, $option ;
			}
		}
	}

_DisplayHelp(0, @matches <= 1, @matches) ;
}

#-------------------------------------------------------------------------------

sub GetOptionsElements
{
my ($options, undef, @t) = GetOptions() ;

push @t, [splice @$options, 0, 4 ] while @$options ;

@t 
}

sub _DisplayHelp
{
my ($narrow_display, $display_long_help, @matches) = @_ ;

my (@short, @long, @options) ;

for (@matches)
	{
	my ($option, $help, $long_help) = @{$_}[0..2] ;
	
	my ($short, $long) =  split(/\|/, ($option =~ s/=.*$//r), 2) ;
	
	($short, $long) = ('', $short) unless defined $long ;
	
	push @short, length($short) ;
	push @long , length($long) ;
	
	push @options, [$short, $long, $help, $long_help] ; 
	}

my $max_short = $narrow_display ? 0 : max(@short) + 2 ;
my $max_long  = $narrow_display ? 0 : max(@long);

for (@options)
	{
	my ($short, $long, $help, $long_help) = @{$_} ;

	my $lht = $long_help eq '' ? ' ' : '*' ;

	Say Info3 sprintf( "--%-${max_long}s %-${max_short}s$lht: ", $long, ($short eq '' ? '' : "--$short"))
			. ($narrow_display ? "\n" : '')
			. _INFO_($help) ;

	Say Info  "$long_help" if $display_long_help && $long_help ne '' ;
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

my ($completion_list, $option_tuples) = Term::Bash::Completion::Generator::de_getop_ify_list(\@switches) ;

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

if($word_to_complete !~ /^-?-?\s?$/)
	{
	my (@slice, @options) ;
	push @options, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 
	
	my ($names, $option_tuples )= Term::Bash::Completion::Generator::de_getop_ify_list(\@options) ;
	
	my $aliases = AliasOptions([]) ;
	push @$names, keys %$aliases ;
	
	@$names = sort @$names ;
	
	$word_to_complete =~ s/(\+)(\d+)$// ;
	my $point = $2 ;
	
	my $reduce  = $word_to_complete =~ s/-$// ;
	my $expand  = $word_to_complete =~ s/\+$// ;
	
	use Tree::Trie ;
	my $trie = new Tree::Trie ;
	$trie->add( map { ("-" . $_) , ("--" . $_) }  @{$names } ) ;
	
	my @matches = nsort $trie->lookup($word_to_complete) ;
	
	if(@matches)
		{
		if($reduce || $expand)
			{
			my $munged ;
			
			for  my $tuple (@$option_tuples)
				{
				if (any { $word_to_complete =~ /^-*$_$/ } @$tuple)
					{
					$munged = $reduce ?  $tuple->[0] : defined $tuple->[1] ? $tuple->[1] : $tuple->[0] ;
					last ;
					}
				}
			
			print defined $munged ? "-$munged\n": "-$matches[0]\n" ;
			}
		else
			{
			@matches = $matches[$point - 1] if $point and defined $matches[$point - 1] ;
			
			if(@matches < 2)
				{
				print join("\n",  @matches) . "\n" ;
				}
			else
				{
				my $counter = 0 ;
				print join("\n", map { $counter++ ; "$_₊" . subscript($counter)} @matches) . "\n" ;
				}
			}
		}
	elsif($word_to_complete =~ /[^\?\-\+]+/)
		{
		if($word_to_complete =~ /\?$/)
			{
			my ($whole_option, $word) = $word_to_complete =~ /^(-*)(.+?)\?$/ ;
			
			my $matcher = $whole_option eq '' ? $word : "^$word" ;
			
			@matches = grep { $_ =~ $matcher } @$names ;
			
			if(@matches)
				{
				Print Info "\n\n" ;
				
				DisplaySwitchesHelp(@matches) ;
				
				my $c = 0 ;
				print @matches > 1 ? join("\n", map { $c++ ; "--$_₊" . subscript($c) } nsort @matches) . "\n" : "\n​\n" ;
				}
			else
				{
				my $c = 0 ;
				print join("\n", map { $c++ ; "--$_₊" . subscript($c)} nsort grep { $_ =~ $matcher } @$names) . "\n" ;
				}
			}
		else
			{
			my $word = $word_to_complete =~ s/^-*//r ;
			
			my @matches = nsort grep { /$word/ } @$names ;
			   @matches = $matches[$point - 1] if $point and defined $matches[$point - 1] ;
			
			if(@matches < 2)
				{
				print join("\n", map { "--$_" } @matches) . "\n" ;
				}
			else
				{
				my $c = 0 ;
				print join("\n", map { $c++ ; "--$_₊" . subscript($c)} @matches) . "\n" ;
				}
			}
		}
	}
}

sub subscript { join '', map { qw / ₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ /[$_] } split '', $_[0] ; } 

#-------------------------------------------------------------------------------

sub GetOptionsList
{
my ($options) = GetOptions() ;

my (@slice, @switches) ;
push @switches, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 

print join( "\n", map { ("-" . $_) } @{ (Term::Bash::Completion::Generator::de_getop_ify_list(\@switches))[0]} ) . "\n" ;
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
