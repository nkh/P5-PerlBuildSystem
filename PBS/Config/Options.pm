
package PBS::Config::Options ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw() ;

our $VERSION = '0.02' ;

use PBS::Constants ;

#-------------------------------------------------------------------------------

sub Debug
{
'debug:s',      'Enable debug support, takes an optional breakpoints definition file.', '', '@BREAKPOINTS',
'debug_header', 'Display a message when a breakpoint is run.',                          '', 'DISPLAY_BREAKPOINT_HEADER',
'debug_dump',   'Dump an evaluable tree.',                                              '', 'DUMP',
}

sub Parallel
{
'jobs|j=i',                'Maximum number of build commands run in parallel.',                  '', 'JOBS',
'jobs_parallel|jp=i',      'Maximum number of dependers run in parallel.',                       '', 'PBS_JOBS',
'jobs_check=i',            'Maximum number of checker run in parallel.',                         '', 'CHECK_JOBS',
'jobs_info',               'PBS will display extra information about the parallel build.',       '', 'DISPLAY_JOBS_INFO',
'jobs_running',            'PBS will display which nodes are under build.',                      '', 'DISPLAY_JOBS_RUNNING',
'jobs_no_tally',           'will not display nodes tally.',                                      '', 'DISPLAY_JOBS_NO_TALLY',
'jobs_die_on_errors=i',    '0 (default) finish running jobs. 1 die immediatly. 2 no stop.',      '', 'JOBS_DIE_ON_ERROR',
'jobs_distribute=s',       'File defining the build distribution.',                              '', 'DISTRIBUTE',
'parallel_processes=i',    'Maximum number of depend processes.',                                '', 'DEPEND_PROCESSES',
'parallel_log',            'Creates a log of the parallel depend.',                              '', 'LOG_PARALLEL_DEPEND',
'parallel_log_display',    'Display the parallel depend log when depending ends.',               '', 'DISPLAY_LOG_PARALLEL_DEPEND',
'parallel_depend_start',   'Display a message when a parallel depend starts.',                   '', 'DISPLAY_PARALLEL_DEPEND_START',
'parallel_depend_end',     'Display a message when a parallel depend end.',                      '', 'DISPLAY_PARALLEL_DEPEND_END',
'parallel_node_name',      'Display the node name in parallel depend end messages.',             '', 'DISPLAY_PARALLEL_DEPEND_NODE',
'parallel_no_resource',    'Display a message when no resource is availabed.',                   '', 'DISPLAY_PARALLEL_DEPEND_NO_RESOURCE',
'parallel_link',           'Display parallel depend linking result.',                            '', 'DISPLAY_PARALLEL_DEPEND_LINKING',
'parallel_link_verbose',   'Display a verbose parallel depend linking result.',                  '', 'DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE',
'parallel_tree',           'Display the distributed dependency graph using a text dumper',       '', 'DISPLAY_PARALLEL_DEPEND_TREE',
'parallel_process_tree',   'Display the distributed process graph using a text dumper',          '', 'DISPLAY_PARALLEL_DEPEND_PROCESS_TREE',
'parallel_compression',    'Compress graphs before sending them',                                '', 'DEPEND_PARALLEL_USE_COMPRESSION',
'parallel_no_result',      'Do not display when a parallel pbs has finished building',           '', 'PARALLEL_NO_BUILD_RESULT',
'parallel_build_sequence', '(DF) List the nodes to be build and the pid of their parallel pbs.', '', 'DEBUG_DISPLAY_GLOBAL_BUILD_SEQUENCE',
'parallel_processes_left', 'Display running depend processes after the main depend ends.',       '', 'DISPLAY_DEPEND_REMAINING_PROCESSES',
'parallel_depend_server',  'Use parallel pbs server multiple times.',                            '', 'USE_DEPEND_SERVER',
'parallel_quick_shutdown', 'Kill parallel Pbs processes',                                        '', 'RESOURCE_QUICK_SHUTDOWN',
'parallel_resource_event', 'Display a message on resource events.',                              '', 'DISPLAY_RESOURCE_EVENT',
}

sub Help
{
'version',             'Displays Pbs version.',                                 '', 'DISPLAY_VERSION',

'help',                'Displays this help.',                                   '', 'DISPLAY_HELP',
'help_narrow_display', 'Writes flags and documentation on separate lines.',     '', 'DISPLAY_HELP_NARROW_DISPLAY',
'doc_extract',         'Extracts the pod contained in the Pbsfile.',            '', 'PBS2POD',
'doc_raw',             '-pbsfile_pod or -pbs2pod is dumped in raw pod format.', '', 'RAW_POD',
'doc_interactive:s',   'Interactive PBS documentation display and search.',     '', 'DISPLAY_POD_DOCUMENTATION',
'options_completion',  'return completion list.',                               '', 'GET_BASH_COMPLETION',
'options_list',        'return completion list on stdout.',                     '', 'GET_OPTIONS_LIST',
'wizard:s',            'Starts a wizard.',                                      '', 'WIZARD',
'wizard_info',         'Shows Informatin about the found wizards.',             '', 'DISPLAY_WIZARD_INFO',
'wizard_help',         'Tell the choosen wizards to show help.',                '', 'DISPLAY_WIZARD_HELP',

'help_user',           "Displays a user defined help.",                   <<~'EOH', 'DISPLAY_PBSFILE_POD',
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
}

sub Output
{
'output_quiet|q',                  'less verbose output.',                            '', 'QUIET',
'output_header_no|hn',             'No header display',                               '', 'DISPLAY_NO_STEP_HEADER',
'output_header_no_counter|hnc',    'Hide depend counter',                             '', 'DISPLAY_NO_STEP_HEADER_COUNTER',
'output_header_newline|hnl',       'add a new line instead for the counter',          '', 'DISPLAY_STEP_HEADER_NL',
'output_build_verbose|bv',         "Verbose build mode.",                             '', 'BUILD_AND_DISPLAY_NODE_INFO',
'output_build_verbose_2|bv2',      "Less verbose build mode.",                        '', 'DISPLAY_NO_PROGRESS_BAR_MINIMUM',
'output_build_verbose_3|bv3',      "Definitely less verbose build mode.",             '', 'DISPLAY_NO_PROGRESS_BAR_MINIMUM_2',
'output_progress_bar_none|pb0',    "No progress bar.",                                '', 'DISPLAY_NO_PROGRESS_BAR',
'output_progress_bar|pb1',         "Silent build mode and progress bar.",             '', 'DISPLAY_PROGRESS_BAR',
'output_progress_bar_file|pb2',    "Built node names above progress bar",             '', 'DISPLAY_PROGRESS_BAR_FILE',
'output_progress_bar_process|pb3', "One progress per build process",                  '', 'DISPLAY_PROGRESS_BAR_PROCESS',
'output_box_node',                 'Display a colored margin for each node display.', '', 'BOX_NODE',
'output_info_label=s',             'Adds text label to all output.',                  '', \&PBS::Output::InfoLabel,
'output_clock_label',              'Adds timing label to all output.',                '', \$PBS::Output::clock_label,
'output_indentation=s',            'set the text used to indent the output.',         '', \$PBS::Output::indentation,
'output_indentation_none',         '',                                                '', \$PBS::Output::no_indentation,
'output_full_path',                'Display full path for files.',                    '', 'DISPLAY_FULL_DEPENDENCY_PATH',
'output_path_glyph=s',             'Replace full dependency_path with argument.',     '', 'SHORT_DEPENDENCY_PATH_STRING',
'output_from_where',               '',                                                '', \$PBS::Output::output_from_where,
'output_color_depth=s',            'Set color depth; 2 = black and white, 16, 256',   '', \&PBS::Output::SetOutputColorDepth,
'output_color_user=s',             "User color, -cs 'user:cyan on_red'",              '', \&PBS::Output::SetOutputColor,
'output_error_context',            'Display the error line.',                         '', \$PBS::Output::display_error_context,
'output_error_no_perl_context',    'Do not parse the perl code to find context.',     '', 'DISPLAY_NO_PERL_CONTEXT',
}

sub Rules
{
'rule_all',                'Display all the rules.',                                          '', 'DISPLAY_ALL_RULES',
'rule_definition',         '(DF) Display the definition of each registrated rule.',           '', 'DEBUG_DISPLAY_RULE_DEFINITION',
'rule_inactive',           'Display rules present in the pbsfile but tagged as NON_ACTIVE.',  '', 'DISPLAY_INACTIVE_RULES',
'rule_non_matching',       'Display the rules used during the dependency pass.',              '', 'DISPLAY_NON_MATCHING_RULES',
'rule_no_scope',           'Disable rule scope.',                                             '', 'RULE_NO_SCOPE',
'rule_run_once',           'Rules run only once except if they are tagged as MULTI',          '', 'RULE_RUN_ONCE',
'rule',                    '(DF) Display registred rules and which package is queried.',      '', 'DEBUG_DISPLAY_RULES',
'rules_subpbs_definition', 'Display subpbs definition.',                                      '', 'DISPLAY_SUB_PBS_DEFINITIONS',
'rule_statistics',         '(DF) Display rule statistics after each pbs run.',                '', 'DEBUG_DISPLAY_RULE_STATISTICS',
'rule_trigger_definition', '(DF) Display the definition of each registrated trigger.',        '', 'DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION',
'rule_trigger',            '(DF) Display which triggers are registred.',                      '', 'DEBUG_DISPLAY_TRIGGER_RULES',
'rule_max_recursion',      'Set the maximum rule recusion before pbs, aborts the build',      '', 'MAXIMUM_RULE_RECURSION',
'rule_namespace=s',        'Rule name space to be used by DefaultBuild()',                    '', '@RULE_NAMESPACES',
'rule_order',              'Display the order rules.',                                        '', 'DISPLAY_RULES_ORDER',
'rule_ordering',           'Display the pbsfile used to order rules and the rules order.',    '', 'DISPLAY_RULES_ORDERING',
'rule_recursion_warning',  'Set the level at which pbs starts warning aabout rule recursion', '', 'RULE_RECURSION_WARNING',
'rule_scope',              'display scope parsing and generation',                            '', 'DISPLAY_RULE_SCOPE',
'rule_to_order',           'Display that there are rules order.',                             '', 'DISPLAY_RULES_TO_ORDER',
'rule_used_name',          'Display the names of the rules used during the dependency pass.', '', 'DISPLAY_USED_RULES_NAME_ONLY',
'rule_used',               'Display the rules used during the dependency pass.',              '', 'DISPLAY_USED_RULES',

'rule_origin',             'Display the origin of rules in addition to their names.',      <<EOT, 'ADD_ORIGIN',

The origin contains the following information:
	- Name
	- Package
	- Namespace
	- Definition file
	- Definition line
EOT
}

sub Config
{
my ($c) = @_ ;
my $load_config_closure = sub { LoadConfig(@_, $c) } ;

'config',                 'Display the config used during a Pbs run.',            '',    'DISPLAY_CONFIGURATION',
'config_all',             '(DF). Display all configurations.',                    '',    'DEBUG_DISPLAY_ALL_CONFIGURATIONS',
'config_location',        'Display the pbs configuration location.',              '',    'DISPLAY_PBS_CONFIGURATION_LOCATION',
'config_merge',           '(DF). Display how configurations are merged.',         '',    'DEBUG_DISPLAY_CONFIGURATIONS_MERGE',
'config_namespaces',      'Display the config namespaces used during a Pbs run.', '',    'DISPLAY_CONFIGURATION_NAMESPACES',
'config_node_usage',      'Display config variables not used by nodes.',          '',    'DISPLAY_NODE_CONFIG_USAGE',
'config_delta',           'Display difference with the parent config',            '',    'DISPLAY_CONFIGURATION_DELTA',
'config_load=s',          'Load the given config before running the Pbsfile.',    '',    $load_config_closure,
'config_no_inheritance',  'disable configuration iheritance.',                    '',    'NO_CONFIG_INHERITANCE',
'config_show_override',   'Disabe SILENT_OVERRIDE.',                              '',    'NO_SILENT_OVERRIDE',
'config_package',         'display subpbs package configuration',                 '',    'DISPLAY_PACKAGE_CONFIGURATION',
'config_set_namespace=s', 'Configuration name space to used',                     '',    '@CONFIG_NAMESPACES',
'config_target_path',     "Don't remove TARGET_PATH from config usage report.",   '',    'DISPLAY_TARGET_PATH_USAGE',
'config_pbs_all',         'Include undefined keys',                               '',    'DISPLAY_PBS_CONFIGURATION_UNDEFINED_VALUES',
'config_match=s',         'Display the pbs configuration matching  the regex.',   '',    '@DISPLAY_PBS_CONFIGURATION',
'config_start',           'Display the config for a Pbs run pre pbsfile loading', '',    'DISPLAY_CONFIGURATION_START',
'config_subpbs',          'Display subpbs config.',                               '',    'DISPLAY_SUB_PBS_CONFIG',
'config_usage',           'Display config variables not used.',                   '',    'DISPLAY_CONFIG_USAGE',
'config_save=s',          'PBS will save the config used in each PBS run',     <<EOT, 'SAVE_CONFIG',

Before a subpbs is run, its start config will be saved in a file. PBS will display the filename so you
can load it later with '--load_config'. When working with a hirarchical build with configuration
defined at the top level, it may happend that you want to run pbs at lower levels but have no configuration,
your build will probably fail. Run pbs from the top level with '--save_config', then run the subpbs
with the the saved config as argument to the '--load_config' option.
EOT
}

sub Devel
{
'devel_no_distribution_check', 'A development flag, not for user.', <<EOT, 'DEVEL_NO_DISTRIBUTION_CHECK',

Pbs checks its distribution when building and rebuilds everything if it has changed.

While developping we are constantly changing the distribution but want to see the effect
of the latest change without rebuilding everything which makes finding the effect of the
latest change more difficult.
EOT
}


sub Tree
{
'nodes_list',            'List all the nodes in the graph.',                     '', 'DISPLAY_FILE_LOCATION',
'nodes_list_all',        'List all the nodes in the graph.',                     '', 'DISPLAY_FILE_LOCATION_ALL',

'tree',                  '(DF) Display the dependency tree using a text dumper', '', 'DEBUG_DISPLAY_TEXT_TREE',
'tree_name_only|tno',    '(DF) Display the name of the nodes only.',             '', 'DEBUG_DISPLAY_TREE_NAME_ONLY',
'tree_after_subpbs|tas', '(DF) run visualization plugins after every subpbs.',   '', 'DEBUG_VISUALIZE_AFTER_SUPBS',
'tree_use_ascii|ta',     'Use ASCII characters to draw the tree.',               '', 'DISPLAY_TEXT_TREE_USE_ASCII',
'tree_build_name|tbn',   '(DF) Display the build name of the nodes.',            '', 'DEBUG_DISPLAY_TREE_NAME_BUILD',
'tree_triggered_reason', '(DF) Display why a node is to be rebuild.',            '', 'DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON',
'tree_match:s',          'limits how many trees are displayed.',                 '', '@DISPLAY_TEXT_TREE_REGEX',
'tree_match_max:i',      'limits how many trees are displayed.',                 '', 'DISPLAY_TEXT_TREE_MAX_MATCH',
'tree_fields=s',         '(DF) List the fields to display when -tt is used.',    '', '@DISPLAY_TREE_FILTER',
'tree_use_dhtml=s',      'Generate a dhtml dump of the tree.',                   '', 'DISPLAY_TEXT_TREE_USE_DHTML',
'tree_depended_at',      '(DF) Display the Pbsfile used to depend each node.',   '', 'DEBUG_DISPLAY_TREE_DEPENDED_AT',
'tree_inserted_at',      '(DF) Display where the node was inserted.',            '', 'DEBUG_DISPLAY_TREE_INSERTED_AT',
'tree_no_dependencies',  '(DF) Don\'t show child nodes data.',                   '', 'DEBUG_DISPLAY_TREE_NO_DEPENDENCIES',
'tree_all_data',         'Forces the display of all data even those not set.',   '', 'DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA',
'tree_maxdepth=i',       'Maximum depth of the structures displayed by pbs.',    '', 'MAX_DEPTH',
'tree_maxdepth_limit=i', 'Limit the depth of the dumped tree.',                  '', 'DISPLAY_TEXT_TREE_MAX_DEPTH',
'tree_indentation=i',    'Data dump indent style (0-1-2).',                      '', 'INDENT_STYLE',
}

sub Graph
{
'graph_cluster=s',          'Display node and dependencies as a single unit.',      '', '@GENERATE_TREE_GRAPH_CLUSTER_NODE',
'graph_cluster_match=s',    'Display nodes matching the regex in a single node.',   '', '@GENERATE_TREE_GRAPH_CLUSTER_REGEX',
'graph=s',                  'Generate a graph in the file name given as argument.', '', 'GENERATE_TREE_GRAPH',
'graph_package',            'Groups the node by definition package.',               '', 'GENERATE_TREE_GRAPH_DISPLAY_PACKAGE',
'graph_canonical=s',        'Generates a canonical dot file.',                      '', 'GENERATE_TREE_GRAPH_CANONICAL',
'graph_format=s',           'Chose graph format: svg (default), ps, png.',          '', 'GENERATE_TREE_GRAPH_FORMAT',
'graph_html=s',             'Generates a graph in html format.',                    '', 'GENERATE_TREE_GRAPH_HTML',
'graph_html_frame',         'Use frames in the html graph.',                        '', 'GENERATE_TREE_GRAPH_HTML_FRAME',
'graph_snapshots=s',        'Generates snapshots of the build.',                    '', 'GENERATE_TREE_GRAPH_SNAPSHOTS',
'graph_cluster_list=s',     'Regex list to cluster nodes',                          '', 'GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST',
'graph_source_directories', 'Groups nodes by source directories',                   '', 'GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES',
'graph_exclude=s',          "Exclude nodes from the graph.",                        '', '@GENERATE_TREE_GRAPH_EXCLUDE',
'graph_include=s',          "Forces nodes back into the graph.",                    '', '@GENERATE_TREE_GRAPH_INCLUDE',
'graph_build_directory',    'Display node build directory.',                        '', 'GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY',
'graph_root_directory',     'Display root build directory.',                        '', 'GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY',
'graph_triggered_nodes',    'Display Trigger inserted nodes.',                      '', 'GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES',
'graph_config',             'Display configs.',                                     '', 'GENERATE_TREE_GRAPH_DISPLAY_CONFIG',
'graph_config_edge',        'Display an edge from nodes to their config.',          '', 'GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE',
'graph_pbs_config',         'Display package configs.',                             '', 'GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG',
'graph_pbs_config_edge',    'Display an edge from nodes to their package.',         '', 'GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE',
'group_mode=i',             'Set mode: 0 no grouping, 1,2.',                        '', 'GENERATE_TREE_GRAPH_GROUP_MODE',
'graph_spacing=f',          'Multiply node spacing with given coefficient.',        '', 'GENERATE_TREE_GRAPH_SPACING',
'graph_printer',            'Non triggerring edges as dashed lines.',               '', 'GENERATE_TREE_GRAPH_PRINTER',
'graph_start_node=s',       'Graph start node.',                                    '', 'GENERATE_TREE_GRAPH_START_NODE',
}

sub Plugin
{
'plugins_load_info',    "displays which plugins are loaded.",   '', 'DISPLAY_PLUGIN_LOAD_INFO',
'plugins_runs',         "displays which plugins subs are run.", '', 'DISPLAY_PLUGIN_RUNS',
'plugins_runs_all',     "displays plugins subs are not run.",   '', 'DISPLAY_PLUGIN_RUNS_ALL',
}

sub PbsSetup
{
'pbsfile=s',              'Pbsfile use to defines the build.',                      '', 'PBSFILE',
'pbsfile_loading',        'Display which pbsfile is loaded.',                       '', 'DISPLAY_PBSFILE_LOADING',
'pbsfile_load_time',      'Display the load time for a pbsfile.',                   '', 'DISPLAY_PBSFILE_LOAD_TIME',
'pbsfile_origin',         'Display original Pbsfile source.',                       '', 'DISPLAY_PBSFILE_ORIGINAL_SOURCE',
'pbsfile_use',            "displays which file is loaded by a 'PbsUse'.",           '', 'DISPLAY_PBSUSE',
'pbsfile_use_verbose',    "more verbose --pbsfile_use",                             '', 'DISPLAY_PBSUSE_VERBOSE',
'pbsfile_used',           'Display Modified Pbsfile source.',                       '', 'DISPLAY_PBSFILE_SOURCE',
'pbsfile_names=s',        'space separated file names that can be pbsfiles.',       '', 'PBSFILE_NAMES',
'pbsfile_extensions=s',   'space separated extensionss that can match a pbsfile.',  '', 'PBSFILE_EXTENSIONS',

'prf=s',                  'File containing switch definitions and targets.',        '', 'PBS_RESPONSE_FILE',
'prf_no_anonymous',       'Use the given response file or one  named afte user.',   '', 'NO_ANONYMOUS_PBS_RESPONSE_FILE',
'prf_none',               'Don\'t use any response file.',                          '', 'NO_PBS_RESPONSE_FILE',

'pbs_options=s',          'start subpbs options for target matching the regex.',    '', 'PBS_OPTIONS',
'pbs_options_local=s',    'options that only applied at the local subpbs level.',   '', 'PBS_OPTIONS_LOCAL',
'pbs_options_end',        'ends the list of subpbs optionss.',                      '', \my $not_used,

'pbs_node_actions=s',     'actions that are run on a node at build time.',       <<EOC, '@NODE_BUILD_ACTIONS',

q~example: pbs -ke .  -nba '3::stop' -nba "trigger::priority 4::message '%name'" -trigger '.' -w 0  -fb -dpb0 -j 12 -nh~,
EOC

'path_source=s',          'Source files location, can be used multiple times.',     '', '@SOURCE_DIRECTORIES',
'path_source_display',    'display all the source directories.',                    '', 'DISPLAY_SOURCE_DIRECTORIES',
'path_build=s',           'Build directory',                                        '', 'BUILD_DIRECTORY',
'path_lib=s',             "Pbs libs. Multiple directories can be given.",           '', '@LIB_PATH',
'path_lib_display',       "Displays PBS lib paths.",                                '', 'DISPLAY_LIB_PATH',
'path_lib_no_warning',    "no warning if using PBS default libs and plugins.",      '', 'NO_DEFAULT_PATH_WARNING',
'path_search_info',       'Show searches',                                          '', 'DISPLAY_SEARCH_INFO',
'path_search_subpbs',     'Show how the subpbs files are found.',                   '', 'DISPLAY_SUBPBS_SEARCH_INFO',
'path_search_subpbs_all', 'Display all the subpbs files that could match.',         '', 'DISPLAY_ALL_SUBPBS_ALTERNATIVES',
'path_guide=s',           "Directories containing guides.",                         '', '@GUIDE_PATH',
'path_plugins=s',         "The directory must start at '/' (root) or '.'",          '', '@PLUGIN_PATH',
'path_plugins_display',   "Displays PBS plugin paths.",                             '', 'DISPLAY_PLUGIN_PATH',

'build_no',               'Only dependen and check.',                               '', 'NO_BUILD',
'build_immediate_build',  'do [IMMEDIATE_BUILD] even if --no_build is set.',        '', 'DO_IMMEDIATE_BUILD',
'build_force|bf',         'Force build if a debug option was given.',               '', 'FORCE_BUILD',
'build_no_stop',          'Continues building in case of errror.',                  '', 'NO_STOP',
'build_pbs_post_display', 'Display the Pbs build post build commands.',             '', 'DISPLAY_PBS_POST_BUILD_COMMANDS',
'post_pbs=s',             'Run the given perl script after pbs.',                   '', '@POST_PBS',

'log',                    'Create a log for the build',                             '', 'CREATE_LOG',
'log_tree',               'Add a graph to the log.',                                '', 'LOG_TREE',
'log_html',               'create a html log for each node, implies --create_log ', '', 'CREATE_LOG_HTML',
}

sub TriggerNode
{
'trigger|T=s',    '(DF) Force the triggering of a node if you want to check its effects.', '', '@TRIGGER',
'trigger_all',    '(DF) As if all node triggered, see --trigger',                          '', 'DEBUG_TRIGGER_ALL',
'trigger_none',   '(DF) As if no node triggered, see --trigger',                           '', 'DEBUG_TRIGGER_NONE',
'trigger_list=s', '(DF) Points to a file containing trigers.',                             '', 'DEBUG_TRIGGER_LIST',
'trigger_show',   '(DF) display which files are processed and triggered',                  '', 'DEBUG_DISPLAY_TRIGGER',
'trigger_match',  '(DF) display only files which are triggered',                           '', 'DEBUG_DISPLAY_TRIGGER_MATCH_ONLY',
}

sub Node
{
'node_header_none',         "Don't display the name of the node to be build.",                 '', 'DISPLAY_NO_BUILD_HEADER',
'node_match=s',             'Display information for nodes matching the regex.',               '', '@DISPLAY_NODE_INFO',
'node_no_build_rule',       'Rules used to depend a node are not displayed',                   '', 'DISPLAY_NO_NODE_BUILD_RULES',
'node_no_parents',          "Don't display the node's parents.",                               '', 'DISPLAY_NO_NODE_PARENTS',
'node_no_info_links',       'Disable files links in info_files and logs',                      '', 'NO_NODE_INFO_LINKS',
'node_log_info=s',          'Log nodes information pre build.',                                '', '@LOG_NODE_INFO',
'node_cache_info',          'Display if the node is from the cache.',                          '', 'NODE_CACHE_INFORMATION',
'node_build_name',          'Display the build name in addition to node name.',                '', 'DISPLAY_NODE_BUILD_NAME',
'node_origin',              'Display where the node has been inserted in the graph.',          '', 'DISPLAY_NODE_ORIGIN',
'node_parents',             "Display the node's parents.",                                     '', 'DISPLAY_NODE_PARENTS',
'node_dependencies',        'Display the dependencies for a node.',                            '', 'DISPLAY_NODE_DEPENDENCIES',
'node_environment=s',       'Display the environment variables for nodes matching the regex.', '', '@DISPLAY_NODE_ENVIRONMENT',
'node_environment_match=s', 'Display the environment variables matching the regex.',           '', '@NODE_ENVIRONMENT_REGEX',
'node_build_reason',        'Display why a node is to be build.',                              '', 'DISPLAY_NODE_BUILD_CAUSE',
'node_build_rule',          'Display the rules used to depend a node.',                        '', 'DISPLAY_NODE_BUILD_RULES',
'node_builder',             'Display the rule which defined the Builder and command.',         '', 'DISPLAY_NODE_BUILDER',
'node_config',              'Display the config used to build a node.',                        '', 'DISPLAY_NODE_CONFIG',
'node_post_build',          'Display the post build commands for each node.',                  '', 'DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS',
'node_ancestors=s',         '(DF) Display node ancestors.',                                    '', 'DEBUG_DISPLAY_PARENT',
'node_no_commands',         'shell commands are not echoed to the console.',                   '', \$PBS::Shell::silent_commands,
'node_no_commands_output',  'No shell commands except if an error occurs.',                    '', \$PBS::Shell::silent_commands_output,
'node_shell_info',          'Displays which shell executes a command.',                        '', 'DISPLAY_SHELL_INFO',
'node_builder_info',        'Displays if a node builder is a perl sub or shell commands.',     '', 'DISPLAY_BUILDER_INFORMATION',
'node_builder_time',        'Displays the total time builders took.',                          '', 'TIME_BUILDERS',
'node_build_result',        'Display the builder result.',                                     '', 'DISPLAY_BUILD_RESULT',
'node_info_match=s',        'Only display information for matching nodes.',                    '', '@BUILD_AND_DISPLAY_NODE_INFO_REGEX',
'node_no_match=s',          "Don't display information for matching nodes.",                   '', '@BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT',
'node_result',              'display node header and build result.',                           '', 'BUILD_DISPLAY_RESULT',
'node_subs_run',            'Show when a node sub is run.',                                    '', 'DISPLAY_NODE_SUBS_RUN',
}

sub Depend
{
'depend_header',              'Show depend header.',                                       '', 'DISPLAY_DEPEND_HEADER',
'depend_subpbs_info',         'Add extra information for nodes matching a subpbs.',        '', 'DISPLAY_SUBPBS_INFO',
'depend_log',                 'Created a log for each subpbs.',                            '', 'DEPEND_LOG',
'depend_full_log',            'Created a log for each subpbs.',                            '', 'DEPEND_FULL_LOG',
'depend_log_merged',          'Merge children subpbs output in log.',                      '', 'DEPEND_LOG_MERGED',
'depend_full_log_options=s',  'Set extra display options for full log.',                   '', 'DEPEND_FULL_LOG_OPTIONS',
'depend_result',              'Display the result of each dependency step.',               '', 'DISPLAY_DEPENDENCY_RESULT',
'depend_indented',            'Add indentation before node.',                              '', 'DISPLAY_DEPEND_INDENTED',
'depend_separator=s',         'Display a separator between nodes.',                        '', 'DISPLAY_DEPEND_SEPARATOR',
'depend_new_line',            'Display an extra line after a depend.',                     '', 'DISPLAY_DEPEND_NEW_LINE',
'depend_end',                 'Display when a depend ends.',                               '', 'DISPLAY_DEPEND_END',
'depend_time',                'Display the time spend in every Pbsfile.',                  '', 'DISPLAY_DEPENDENCY_TIME',
'depend_link_rule',           'Display the rule which matched the node being linked.',     '', 'DISPLAY_LINK_MATCHING_RULE',
'depend_check_time',          'Display the graph check time.',                             '', 'DISPLAY_CHECK_TIME',
'depend_too_many_nodes=i',    'Warn when a pbsfile adds too many nodes.',                  '', 'DISPLAY_TOO_MANY_NODE_WARNING',
'depend_match=s',             'Node matching the regex are displayed.',                    '', '@DISPLAY_DEPENDENCIES_REGEX',
'depend_no_match=s',          'Node matching the regex are not displayed.',                '', '@DISPLAY_DEPENDENCIES_REGEX_NOT',
'depend_virtual_match_ok',    'No warning if a virtual node matches a directory.',         '', 'ALLOW_VIRTUAL_TO_MATCH_DIRECTORY',

'dependencies|d',             '(DF) Display node dependencies.',                           '', 'DEBUG_DISPLAY_DEPENDENCIES',
'dependencies_long|dl',       '(DF) Display one node dependency perl line.',               '', 'DEBUG_DISPLAY_DEPENDENCIES_LONG',
'dependencies_regex|dr',      '(DF) Display the regex used to depend a node.',             '', 'DEBUG_DISPLAY_DEPENDENCY_REGEX',
'dependencies_rule|dmr',      'Display the rule matching the node.',                       '', 'DISPLAY_DEPENDENCY_MATCHING_RULE',
'dependencies_insertion|dir', 'Display the rule adding the node.',                         '', 'DISPLAY_DEPENDENCY_INSERTION_RULE',
'dependencies_match=s',       'Display node matching rules regex.',                        '', '@DISPLAY_DEPENDENCIES_RULE_NAME',
'dependencies_match_not=s',   "Don't display nodes matchin rules regex.",                  '', '@DISPLAY_DEPENDENCIES_RULE_NAME_NOT',
'dependencies_definition',    'Display matching rules definitions.',                       '', 'DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION',
'dependencies_full_path',     'Don\'t shorten file paths.',                                '', 'DISPLAY_DEPENDENCIES_FULL_PBSFILE',
'dependencies_pbs_stack',     '(DF) Display pbs call stack.',                              '', 'DEBUG_TRACE_PBS_STACK',
'dependencies_duplicate',     'Display duplicate dependencies.',                           '', 'DISPLAY_DUPLICATE_INFO',
'dependencies_zero_ok',       'No warning if node matches rules but has no dependencies.', '', 'NO_WARNING_ZERO_DEPENDENCIES',
'dependencies_none_ok',       'Show nodes tagged with HasNoDependencies.',              <<EOC, 'DISPLAY_NO_DEPENDENCIES_OK',

Generated nodes are checked for dependenciesg. 
	some nodes are generated from non files or don't always have dependencies as for C cache which
	dependency file is created on the fly if it doens't exist.
EOC
}

sub Warp
{
'warp|w=s',                "Specify which warp to use.",                 '', 'WARP',
'warp_file_name',          "Display the warp file name.",                '', 'DISPLAY_WARP_FILE_NAME',
'warp_time',               "Display warp creation time.",                '', 'DISPLAY_WARP_TIME',
'warp_human_format',       "Generate warp file in a readable format.",   '', 'WARP_HUMAN_FORMAT',
'warp_no_pre_cache',       "no pre-build warp will be generated.",       '', 'NO_PRE_BUILD_WARP',
'warp_no_cache',           "no post-build warp will be generated.",      '', 'NO_POST_BUILD_WARP',
'warp_checked_nodes',      "Display nodes contained in the warp graph.", '', 'DISPLAY_WARP_CHECKED_NODES',
'warp_checked_nodes_fail', "Display nodes with different hash.",         '', 'DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY',
'warp_removed_nodes',      "Display nodes removed during warp.",         '', 'DISPLAY_WARP_REMOVED_NODES',
'warp_triggered_nodes',    "Display nodes removed during warp and why.", '', 'DISPLAY_WARP_TRIGGERED_NODES',
}

sub Http
{
'http_post',    'Display a message when a POST is send.',        '', 'HTTP_DISPLAY_POST',
'http_put',     'Display a message when a PUT is send.',         '', 'HTTP_DISPLAY_PUT',
'http_get',     'Display a message when a GET is send.',         '', 'HTTP_DISPLAY_GET',
'http_start',   'Display a message when a server is started.',   '', 'HTTP_DISPLAY_SERVER_START',
'http_stop',    'Display a message when a server is sshutdown.', '', 'HTTP_DISPLAY_SERVER_STOP',
'http_request', 'Display a message when a request is received.', '', 'HTTP_DISPLAY_REQUEST',
}

sub Stats
{
'time_pbs',                "Display where time is spend in PBS.",                     '', 'DISPLAY_PBS_TIME',
'time_minimum=f',          "Display time if it is more than  value (default 0.5s).",  '', 'DISPLAY_MINIMUM_TIME',
'time_total',              "Display How much time is spend in PBS.",                  '', 'DISPLAY_PBS_TOTAL_TIME',
'time_pbsuse',             "displays the time spend in 'PbsUse' for each pbsfile.",   '', 'DISPLAY_PBSUSE_TIME',
'time_pbsuse_all',         "displays the time spend in each pbsuse.",                 '', 'DISPLAY_PBSUSE_TIME_ALL',
'time_md5',                "displays the time it takes to hash each node",            '', \$PBS::Digest::display_md5_time,

'stat_md5',                "displays 'MD5' statistic.",                               '', 'DISPLAY_MD5_STATISTICS',
'stat_pbsuse',             "displays 'PbsUse' statistic.",                            '', 'DISPLAY_PBSUSE_STATISTIC',
'stat_pbsfile_nodes',      'Display how many nodes where added by each pbsfile run.', '', 'DISPLAY_NODES_PER_PBSFILE',
'stat_pbsfile_nodes_name', 'Display which nodes where added by each pbsfile run.',    '', 'DISPLAY_NODES_PER_PBSFILE_NAMES',
}

sub Check
{
'check_at_build_time',        'Skips node build if dependencies rebuild identically.',                 '', 'CHECK_DEPENDENCIES_AT_BUILD_TIME',
'check_hide_skipped_builds',  'Hide builds skipped by -check_dependencies_at_build_time.',             '', 'HIDE_SKIPPED_BUILDS',
'check_terminal_nodes',       'Skips the checking of generated artefacts.',                            '', 'DEBUG_CHECK_ONLY_TERMINAL_NODES',
'check_no_dependencies_ok=s', 'No warning if node has no dependencies.',                               '', 'NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX',
'check_external=s',           q{pbs -ce <(git status -s --uno | perl -ae \"say $PWD . '/' . $F[1]\")}, '', '@EXTERNAL_CHECKERS',
'check_cyclic_source_ok',     'No warning if a cycle includes a source files.',                        '', 'NO_SOURCE_CYCLIC_WARNING',
'check_cyclic_source_die',    'Die if a cycle includes a source.',                                     '', 'DIE_SOURCE_CYCLIC_WARNING',
'check_cyclic_tree',          '(DF) Display tree cycles',                                              '', 'DEBUG_DISPLAY_CYCLIC_TREE',
}

sub Match
{
'build_sequence',          '(DF) Dumps the build sequence data.',                         '', 'DEBUG_DISPLAY_BUILD_SEQUENCE',
'build_sequence_simple',   '(DF) List the nodes to be build.',                            '', 'DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE',
'build_sequence_stats',    '(DF) display number of nodes to be build.',                   '', 'DEBUG_DISPLAY_BUILD_SEQUENCE_STATS',
'build_sequence_save=s',   'Save a list of nodes to be build to a file.',                 '', 'SAVE_BUILD_SEQUENCE_SIMPLE',
'build_sequence_info',     'Display information about which node is build.',              '', 'DISPLAY_BUILD_SEQUENCER_INFO',
'build_info=s',            'Set options: -b -d, ... ; a file or \'*\' can be specified.', '', '@DISPLAY_BUILD_INFO',

'link_no_external',        'Fail if linking from other Pbsfile and local rule matches.',  '', 'NO_EXTERNAL_LINK',
'link_no_info|lni',        'No linking message.',                                         '', 'NO_LINK_INFO',
'link_no_local_info|lnli', 'No message when linking to local nodes.',                     '', 'NO_LOCAL_LINK_INFO',
'link_local_rule_ok',      'No message if a linked node matches local rules.',            '', 'NO_LOCAL_MATCHING_RULES_INFO',
}

sub PostBuild
{
'post_build_registration', '(DF) Display post build commands registration.', '', 'DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION',
'post_build_definition',   '(DF) Display post build commands definition.',   '', 'DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION',
'post_build_commands',     '(DF) Display which post build command is run.',  '', 'DEBUG_DISPLAY_POST_BUILD_COMMANDS',
'post_build_result',       'Display post build commands result.',            '', 'DISPLAY_POST_BUILD_RESULT',
}

sub Trigger
{
'trigger_no_import_info', 'Don\'t display triggers imports.',           '', 'NO_TRIGGER_IMPORT_INFO',
'trigger_inserted_nodes', '(DF) Display nodes inserted by a trigger.',  '', 'DEBUG_DISPLAY_TRIGGER_INSERTED_NODES',
'triggered',              '(DF) Display why files need to be rebuild.', '', 'DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES',
}

sub Env
{
'environment_keep|ek=s',      "%ENV isemptied, --ke 'regex' keeps matching variables.", '', '@KEEP_ENVIRONMENT',
'environment',                "Display which environment variables are kept",           '', 'DISPLAY_ENVIRONMENT',
'environment_only_kept',      "Only display the evironment variables kept",             '', 'DISPLAY_ENVIRONMENT_KEPT',
'environment_statistic',      "Display a statistics about environment variables",       '', 'DISPLAY_ENVIRONMENT_STAT',
'environment_user_option=s',  'options to be passed to the build sub.',                 '', '%USER_OPTIONS',
'environment_definition|D=s', 'Command line definitions.',                              '', '%COMMAND_LINE_DEFINITIONS',

'verbosity=s',                'Used in user defined modules.',                       <<EOT, '@VERBOSITY',
-- verbose is not used by PBS. It is intended for user defined modules.

recommended settings:

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
}

sub Digest
{
'digest',               'Display expected and actual digest.',                 '', 'DISPLAY_DIGEST',
'digest_different',     'Only display when a digest are diffrent.',            '', 'DISPLAY_DIFFERENT_DIGEST_ONLY',
'digest_exclusion',     'Display node exclusion or inclusion.',                '', 'DISPLAY_DIGEST_EXCLUSION',
'digest_warp_warnings', 'Warn if the file to compute hash for does\'t exist.', '', 'WARP_DISPLAY_DIGEST_FILE_NOT_FOUND',
'digest_file_check',    'Display hash checking for individual files.',         '', 'DISPLAY_FILE_CHECK',
}  

#-------------------------------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Config::Options  -

=head1 SYNOPSIS

=head1 DESCRIPTION

Definition of command line options

=cut



