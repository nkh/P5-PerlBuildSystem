
package PBS::Config::Options ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw() ;

our $VERSION = '0.01' ;

use PBS::Constants ;

#-------------------------------------------------------------------------------

sub DebugOptions
{
my ($c) = @_ ;

$c->{BREAKPOINTS} //= [] ;

'debug:s',      'Enable debug support, takes an optional breakpoints definition file.', '', $c->{BREAKPOINTS},
'debug_header', 'Display a message when a breakpoint is run.',                          '', \$c->{DISPLAY_BREAKPOINT_HEADER},
'debug_dump',   'Dump an evaluable tree.',                                              '', \$c->{DUMP},
}

sub ParallelOptions
{
my ($c) = @_ ;
$c->{JOBS_DIE_ON_ERROR} //= 0 ;

'jobs|j=i',                   'Maximum number of build commands run in parallel.',                  '', \$c->{JOBS},
'jobs_parallel|jp=i',         'Maximum number of dependers run in parallel.',                       '', \$c->{PBS_JOBS},
'jobs_check=i',               'Maximum number of checker run in parallel.',                         '', \$c->{CHECK_JOBS},
'jobs_info',                  'PBS will display extra information about the parallel build.',       '', \$c->{DISPLAY_JOBS_INFO},
'jobs_running',               'PBS will display which nodes are under build.',                      '', \$c->{DISPLAY_JOBS_RUNNING},
'jobs_no_tally',              'will not display nodes tally.',                                      '', \$c->{DISPLAY_JOBS_NO_TALLY},
'jobs_die_on_errors=i',       '0 (default) finish running jobs. 1 die immediatly. 2 no stop.',      '', \$c->{JOBS_DIE_ON_ERROR},
'jobs_distribute=s',          'File defining the build distribution.',                              '', \$c->{DISTRIBUTE},
'parallel_processes|pdp=i',   'Maximum number of depend processes.',                                '', \$c->{DEPEND_PROCESSES},
'parallel_log|pl',            'Creates a log of the parallel depend.',                              '', \$c->{LOG_PARALLEL_DEPEND},
'parallel_log_display|pld',   'Display the parallel depend log when depending ends.',               '', \$c->{DISPLAY_LOG_PARALLEL_DEPEND},
'parallel_depend_start|pds',  'Display a message when a parallel depend starts.',                   '', \$c->{DISPLAY_PARALLEL_DEPEND_START},
'parallel_depend_end',        'Display a message when a parallel depend end.',                      '', \$c->{DISPLAY_PARALLEL_DEPEND_END},
'parallel_node_name',         'Display the node name in parallel depend end messages.',             '', \$c->{DISPLAY_PARALLEL_DEPEND_NODE},
'parallel_no_resource',       'Display a message when no resource is availabed.',                   '', \$c->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE},
'parallel_link',              'Display parallel depend linking result.',                            '', \$c->{DISPLAY_PARALLEL_DEPEND_LINKING},
'parallel_link_verbose',      'Display a verbose parallel depend linking result.',                  '', \$c->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE},
'parallel_tree|pt',           'Display the distributed dependency graph using a text dumper',       '', \$c->{DISPLAY_PARALLEL_DEPEND_TREE},
'parallel_process_tree|ppt',  'Display the distributed process graph using a text dumper',          '', \$c->{DISPLAY_PARALLEL_DEPEND_PROCESS_TREE},
'parallel_compression|puc',   'Compress graphs before sending them',                                '', \$c->{DEPEND_PARALLEL_USE_COMPRESSION},
'parallel_no_result|pnr',     'Do not display when a parallel pbs has finished building',           '', \$c->{PARALLEL_NO_BUILD_RESULT},
'parallel_build_sequence',    '(DF) List the nodes to be build and the pid of their parallel pbs.', '', \$c->{DEBUG_DISPLAY_GLOBAL_BUILD_SEQUENCE},
'parallel_processes_left',    'Display running depend processes after the main depend ends.',       '', \$c->{DISPLAY_DEPEND_REMAINING_PROCESSES},
'parallel_depend_server',     'Use parallel pbs server multiple times.',                            '', \$c->{USE_DEPEND_SERVER},
'parallel_quick_shutdown',    'Kill parallel Pbs processes',                                        '', \$c->{RESOURCE_QUICK_SHUTDOWN},
'parallel_resource_event',    'Display a message on resource events.',                              '', \$c->{DISPLAY_RESOURCE_EVENT},
}

sub HelpOptions
{
my ($c) = @_ ;

'version|v',           'Displays Pbs version.',                                 '', \$c->{DISPLAY_VERSION},

'help|h',              'Displays this help.',                                   '', \$c->{DISPLAY_HELP},
'help_narrow_display', 'Writes flags and documentation on separate lines.',     '', \$c->{DISPLAY_HELP_NARROW_DISPLAY},
'doc_extract',         'Extracts the pod contained in the Pbsfile.',            '', \$c->{PBS2POD},
'doc_raw',             '-pbsfile_pod or -pbs2pod is dumped in raw pod format.', '', \$c->{RAW_POD},
'doc_interactive:s',   'Interactive PBS documentation display and search.',     '', \$c->{DISPLAY_POD_DOCUMENTATION},
'options_completion',  'return completion list.',                               '', \$c->{GET_BASH_COMPLETION},
'options_list',        'return completion list on stdout.',                     '', \$c->{GET_OPTIONS_LIST},
'wizard:s',            'Starts a wizard.',                                      '', \$c->{WIZARD},
'wizard_info',         'Shows Informatin about the found wizards.',             '', \$c->{DISPLAY_WIZARD_INFO},
'wizard_help',         'Tell the choosen wizards to show help.',                '', \$c->{DISPLAY_WIZARD_HELP},

'help_user|hu',        "Displays a user defined help.",                   <<~'EOH', \$c->{DISPLAY_PBSFILE_POD},
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

sub OutputOptions
{
my ($c) = @_ ;

'output_quiet|q',                  'less verbose output.',                            '', \$c->{QUIET},
'output_header_no|hn',             'No header display',                               '', \$c->{DISPLAY_NO_STEP_HEADER},
'output_header_no_counter|hnc',    'Hide depend counter',                             '', \$c->{DISPLAY_NO_STEP_HEADER_COUNTER},
'output_header_newline|hnl',       'add a new line instead for the counter',          '', \$c->{DISPLAY_STEP_HEADER_NL},
'output_build_verbose|bv',         "Verbose build mode.",                             '', \$c->{BUILD_AND_DISPLAY_NODE_INFO},
'output_build_verbose_2|bv2',      "Less verbose build mode.",                        '', \$c->{DISPLAY_NO_PROGRESS_BAR_MINIMUM},
'output_build_verbose_3|bv3',      "Definitely less verbose build mode.",             '', \$c->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2},
'output_progress_bar_none|pb0',    "No progress bar.",                                '', \$c->{DISPLAY_NO_PROGRESS_BAR},
'output_progress_bar|pb1',         "Silent build mode and progress bar.",             '', \$c->{DISPLAY_PROGRESS_BAR},
'output_progress_bar_file|pb2',    "Built node names above progress bar",             '', \$c->{DISPLAY_PROGRESS_BAR_FILE},
'output_progress_bar_process|pb3', "One progress per build process",                  '', \$c->{DISPLAY_PROGRESS_BAR_PROCESS},
'output_box_node',                 'Display a colored margin for each node display.', '', \$c->{BOX_NODE},
'output_info_label=s',             'Adds text label to all output.',                  '', \&PBS::Output::InfoLabel,
'output_clock_label',              'Adds timing label to all output.',                '', \$PBS::Output::clock_label,
'output_indentation=s',            'set the text used to indent the output.',         '', \$PBS::Output::indentation,
'output_indentation_none',         '',                                                '', \$PBS::Output::no_indentation,
'output_full_path',                'Display full path for files.',                    '', \$c->{DISPLAY_FULL_DEPENDENCY_PATH},
'output_path_glyph=s',             'Replace full dependency_path with argument.',     '', \$c->{SHORT_DEPENDENCY_PATH_STRING},
'output_from_where',               '',                                                '', \$PBS::Output::output_from_where,
'output_color_depth=s',            'Set color depth; 2 = black and white, 16, 256',   '', \&PBS::Output::SetOutputColorDepth,
'output_color_user|ocu=s',         "User color, -cs 'user:cyan on_red'",              '', \&PBS::Output::SetOutputColor,
'output_error_context',            'Display the error line.',                         '', \$PBS::Output::display_error_context,
'output_error_no_perl_context',    'Do not parse the perl code to find context.',     '', \$c->{DISPLAY_NO_PERL_CONTEXT},
}

sub RulesOptions
{
my ($c)  = @_ ;
$c->{RULE_NAMESPACES} //= [] ;

'rule_all|ra',             'Display all the rules.',                                          '', \$c->{DISPLAY_ALL_RULES},
'rule_definition|rd',      '(DF) Display the definition of each registrated rule.',           '', \$c->{DEBUG_DISPLAY_RULE_DEFINITION},
'rule_inactive|ri',        'Display rules present in the pbsfile but tagged as NON_ACTIVE.',  '', \$c->{DISPLAY_INACTIVE_RULES},
'rule_non_matching|rnm',   'Display the rules used during the dependency pass.',              '', \$c->{DISPLAY_NON_MATCHING_RULES},
'rule_no_scope|rns',       'Disable rule scope.',                                             '', \$c->{RULE_NO_SCOPE},
'rule_run_once|rro',       'Rules run only once except if they are tagged as MULTI',          '', \$c->{RULE_RUN_ONCE},
'rule|r',                  '(DF) Display registred rules and which package is queried.',      '', \$c->{DEBUG_DISPLAY_RULES},
'rules_subpbs_definition', 'Display subpbs definition.',                                      '', \$c->{DISPLAY_SUB_PBS_DEFINITION},
'rule_statistics|rs',      '(DF) Display rule statistics after each pbs run.',                '', \$c->{DEBUG_DISPLAY_RULE_STATISTICS},
'rule_trigger_definition', '(DF) Display the definition of each registrated trigger.',        '', \$c->{DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION},
'rule_trigger|rt',         '(DF) Display which triggers are registred.',                      '', \$c->{DEBUG_DISPLAY_TRIGGER_RULES},
'rule_max_recursion',      'Set the maximum rule recusion before pbs, aborts the build',      '', \$c->{MAXIMUM_RULE_RECURSION},
'rule_namespace=s',        'Rule name space to be used by DefaultBuild()',                    '', $c->{RULE_NAMESPACES},
'rule_order',              'Display the order rules.',                                        '', \$c->{DISPLAY_RULES_ORDER},
'rule_ordering',           'Display the pbsfile used to order rules and the rules order.',    '', \$c->{DISPLAY_RULES_ORDERING},
'rule_recursion_warning',  'Set the level at which pbs starts warning aabout rule recursion', '', \$c->{RULE_RECURSION_WARNING},
'rule_scope',              'display scope parsing and generation',                            '', \$c->{DISPLAY_RULE_SCOPE},
'rule_to_order',           'Display that there are rules order.',                             '', \$c->{DISPLAY_RULES_TO_ORDER},
'rule_used_name|run',      'Display the names of the rules used during the dependency pass.', '', \$c->{DISPLAY_USED_RULES_NAME_ONLY},
'rule_used|ru',            'Display the rules used during the dependency pass.',              '', \$c->{DISPLAY_USED_RULES},
'rule_origin',             'Display the origin of rules in addition to their names.',     <<~EOT, \$c->{ADD_ORIGIN},
				The origin contains the following information:
					- Name
					- Package
					- Namespace
					- Definition file
					- Definition line
				EOT

}

sub ConfigOptions
{
my ($c) = @_ ;
$c->{CONFIG_NAMESPACES}         //= [];
$c->{DISPLAY_PBS_CONFIGURATION} //= [];

my $load_config_closure = sub { LoadConfig(@_, $c) } ;

'config|c',               'Display the config used during a Pbs run.',            '',    \$c->{DISPLAY_CONFIGURATION},
'config_all|ca',          '(DF). Display all configurations.',                    '',    \$c->{DEBUG_DISPLAY_ALL_CONFIGURATIONS},
'config_location|cl',     'Display the pbs configuration location.',              '',    \$c->{DISPLAY_PBS_CONFIGURATION_LOCATION},
'config_merge|cm',        '(DF). Display how configurations are merged.',         '',    \$c->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE},
'config_namespaces|cn',   'Display the config namespaces used during a Pbs run.', '',    \$c->{DISPLAY_CONFIGURATION_NAMESPACES},
'config_node_usage|cnu',  'Display config variables not used by nodes.',          '',    \$c->{DISPLAY_NODE_CONFIG_USAGE},
'config_delta',           'Display difference with the parent config',            '',    \$c->{DISPLAY_CONFIGURATION_DELTA},
'config_load=s',          'Load the given config before running the Pbsfile.',    '',    $load_config_closure,
'config_no_inheritance',  'disable configuration iheritance.',                    '',    \$c->{NO_CONFIG_INHERITANCE},
'config_show_override',   'Disabe SILENT_OVERRIDE.',                              '',    \$c->{NO_SILENT_OVERRIDE},
'config_package',         'display subpbs package configuration',                 '',    \$c->{DISPLAY_PACKAGE_CONFIGURATION},
'config_set_namespace=s', 'Configuration name space to used',                     '',    $c->{CONFIG_NAMESPACES},
'config_target_path',     "Don't remove TARGET_PATH from config usage report.",   '',    \$c->{DISPLAY_TARGET_PATH_USAGE},
'config_pbs_all|cpa',     'Include undefined keys',                               '',    \$c->{DISPLAY_PBS_CONFIGURATION_UNDEFINED_VALUES},
'config_match|cp=s',      'Display the pbs configuration matching  the regex.',   '',    $c->{DISPLAY_PBS_CONFIGURATION},
'config_start|cs',        'Display the config for a Pbs run pre pbsfile loading', '',    \$c->{DISPLAY_CONFIGURATION_START},
'config_subpbs|csp',      'Display subpbs config.',                               '',    \$c->{DISPLAY_SUB_PBS_CONFIG},
'config_usage|cu',        'Display config variables not used.',                   '',    \$c->{DISPLAY_CONFIG_USAGE},
'config_save=s',          'PBS will save the config used in each PBS run',        <<EOT, \$c->{SAVE_CONFIG},

Before a subpbs is run, its start config will be saved in a file. PBS will display the filename so you
can load it later with '--load_config'. When working with a hirarchical build with configuration
defined at the top level, it may happend that you want to run pbs at lower levels but have no configuration,
your build will probably fail. Run pbs from the top level with '--save_config', then run the subpbs
with the the saved config as argument to the '--load_config' option.
EOT
}

sub DevelOptions
{
my ($config) = @_ ;

'devel_no_distribution_check|DNDC', 'A development flag, not for user.', <<EOT, \$config->{DEVEL_NO_DISTRIBUTION_CHECK},

Pbs checks its distribution when building and rebuilds everything if it has changed.

While developping we are constantly changing the distribution but want to see the effect
of the latest change without rebuilding everything which makes finding the effect of the
latest change more difficult.
EOT
}


sub TreeOptions
{
my ($c) = @_ ;
$c->{DISPLAY_TEXT_TREE_REGEX} //= [];
$c->{DISPLAY_TREE_FILTER}     //= [];

'nodes_list|n',          'List all the nodes in the graph.',                     '', \$c->{DISPLAY_FILE_LOCATION},
'nodes_list_all|na',     'List all the nodes in the graph.',                     '', \$c->{DISPLAY_FILE_LOCATION_ALL},

'tree',                  '(DF) Display the dependency tree using a text dumper', '', \$c->{DEBUG_DISPLAY_TEXT_TREE},
'tree_name_only|tno',    '(DF) Display the name of the nodes only.',             '', \$c->{DEBUG_DISPLAY_TREE_NAME_ONLY},
'tree_after_subpbs|tas', '(DF) run visualization plugins after every subpbs.',   '', \$c->{DEBUG_VISUALIZE_AFTER_SUPBS},
'tree_use_ascii|ta',     'Use ASCII characters to draw the tree.',               '', \$c->{DISPLAY_TEXT_TREE_USE_ASCII},
'tree_build_name|tbn',   '(DF) Display the build name of the nodes.',            '', \$c->{DEBUG_DISPLAY_TREE_NAME_BUILD},
'tree_triggered_reason', '(DF) Display why a node is to be rebuild.',            '', \$c->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON},
'tree_match:s',          'limits how many trees are displayed.',                 '', $c->{DISPLAY_TEXT_TREE_REGEX},
'tree_match_max:i',      'limits how many trees are displayed.',                 '', \$c->{DISPLAY_TEXT_TREE_MAX_MATCH},
'tree_fields=s',         '(DF) List the fields to display when -tt is used.',    '', $c->{DISPLAY_TREE_FILTER},
'tree_use_dhtml=s',      'Generate a dhtml dump of the tree.',                   '', \$c->{DISPLAY_TEXT_TREE_USE_DHTML},
'tree_depended_at',      '(DF) Display the Pbsfile used to depend each node.',   '', \$c->{DEBUG_DISPLAY_TREE_DEPENDED_AT},
'tree_inserted_at',      '(DF) Display where the node was inserted.',            '', \$c->{DEBUG_DISPLAY_TREE_INSERTED_AT},
'tree_no_dependencies',  '(DF) Don\'t show child nodes data.',                   '', \$c->{DEBUG_DISPLAY_TREE_NO_DEPENDENCIES},
'tree_all_data',         'Forces the display of all data even those not set.',   '', \$c->{DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA},
'tree_maxdepth=i',       'Maximum depth of the structures displayed by pbs.',    '', \$c->{MAX_DEPTH},
'tree_maxdepth_limit=i', 'Limit the depth of the dumped tree.',                  '', \$c->{DISPLAY_TEXT_TREE_MAX_DEPTH},
'tree_indentation=i',    'Data dump indent style (0-1-2).',                      '', \$c->{INDENT_STYLE},
}

sub GraphOptions
{
my ($c) = @_ ;

$c->{GENERATE_TREE_GRAPH_CLUSTER_NODE}  //= [] ;
$c->{GENERATE_TREE_GRAPH_CLUSTER_REGEX} //= [] ;
$c->{GENERATE_TREE_GRAPH_EXCLUDE}       //= [] ;
$c->{GENERATE_TREE_GRAPH_GROUP_MODE}    //= GRAPH_GROUP_NONE ;
$c->{GENERATE_TREE_GRAPH_INCLUDE}       //= [] ;
$c->{GENERATE_TREE_GRAPH_SPACING}       //= 1 ;

'graph_cluster=s',          'Display node and dependencies as a single unit.',      '', $c->{GENERATE_TREE_GRAPH_CLUSTER_NODE},
'graph_cluster_match=s',    'Display nodes matching the regex in a single node.',   '', $c->{GENERATE_TREE_GRAPH_CLUSTER_REGEX},
'graph=s',                  'Generate a graph in the file name given as argument.', '', \$c->{GENERATE_TREE_GRAPH},
'graph_package',            'Groups the node by definition package.',               '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE},
'graph_canonical=s',        'Generates a canonical dot file.',                      '', \$c->{GENERATE_TREE_GRAPH_CANONICAL},
'graph_format=s',           'Chose graph format: svg (default), ps, png.',          '', \$c->{GENERATE_TREE_GRAPH_FORMAT},
'graph_html=s',             'Generates a graph in html format.',                    '', \$c->{GENERATE_TREE_GRAPH_HTML},
'graph_html_frame',         'Use frames in the html graph.',                        '', \$c->{GENERATE_TREE_GRAPH_HTML_FRAME},
'graph_snapshots=s',        'Generates snapshots of the build.',                    '', \$c->{GENERATE_TREE_GRAPH_SNAPSHOTS},
'graph_cluster_list=s',     'Regex list to cluster nodes',                          '', \$c->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST},
'graph_source_directories', 'Groups nodes by source directories',                   '', \$c->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES},
'graph_exclude=s',          "Exclude nodes from the graph.",                        '', $c->{GENERATE_TREE_GRAPH_EXCLUDE},
'graph_include=s',          "Forces nodes back into the graph.",                    '', $c->{GENERATE_TREE_GRAPH_INCLUDE},
'graph_build_directory',    'Display node build directory.',                        '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY},
'graph_root_directory',     'Display root build directory.',                        '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY},
'graph_triggered_nodes',    'Display Trigger inserted nodes.',                      '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES},
'graph_config',             'Display configs.',                                     '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG},
'graph_config_edge',        'Display an edge from nodes to their config.',          '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE},
'graph_pbs_config',         'Display package configs.',                             '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG},
'graph_pbs_config_edge',    'Display an edge from nodes to their package.',         '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE},
'group_mode=i',             'Set mode: 0 no grouping, 1,2.',                        '', \$c->{GENERATE_TREE_GRAPH_GROUP_MODE},
'graph_spacing=f',          'Multiply node spacing with given coefficient.',        '', \$c->{GENERATE_TREE_GRAPH_SPACING},
'graph_printer',            'Non triggerring edges as dashed lines.',               '', \$c->{GENERATE_TREE_GRAPH_PRINTER},
'graph_start_node=s',       'Graph start node.',                                    '', \$c->{GENERATE_TREE_GRAPH_START_NODE},
}

sub PluginOptions
{
my ($c) = @_ ;

'plugins_load_info',    "displays which plugins are loaded.",   '', \$c->{DISPLAY_PLUGIN_LOAD_INFO},
'plugins_runs',         "displays which plugins subs are run.", '', \$c->{DISPLAY_PLUGIN_RUNS},
'plugins_runs_all',     "displays plugins subs are not run.",   '', \$c->{DISPLAY_PLUGIN_RUNS_ALL},
}

sub PbsSetupOptions
{
my ($c) = @_ ;
$c->{LIB_PATH}           //= [] ;
$c->{SOURCE_DIRECTORIES} //= [] ;
$c->{POST_PBS}           //= [] ;
$c->{GUIDE_PATH}         //= [] ;
$c->{PLUGIN_PATH}        //= []  ;
$c->{NODE_BUILD_ACTIONS} //= [] ;

'pbsfile=s',              'Pbsfile use to defines the build.',                      '', \$c->{PBSFILE},
'pbsfile_loading',        'Display which pbsfile is loaded.',                       '', \$c->{DISPLAY_PBSFILE_LOADING},
'pbsfile_load_time',      'Display the load time for a pbsfile.',                   '', \$c->{DISPLAY_PBSFILE_LOAD_TIME},
'pbsfile_origin',         'Display original Pbsfile source.',                       '', \$c->{DISPLAY_PBSFILE_ORIGINAL_SOURCE},
'pbsfile_use',            "displays which file is loaded by a 'PbsUse'.",           '', \$c->{DISPLAY_PBSUSE},
'pbsfile_use_verbose',    "more verbose --pbsfile_use",                             '', \$c->{DISPLAY_PBSUSE_VERBOSE},
'pbsfile_used',           'Display Modified Pbsfile source.',                       '', \$c->{DISPLAY_PBSFILE_SOURCE},
'pbsfile_names=s',        'space separated file names that can be pbsfiles.',       '', \$c->{PBSFILE_NAMES},
'pbsfile_extensions=s',   'space separated extensionss that can match a pbsfile.',  '', \$c->{PBSFILE_EXTENSIONS},

'prf=s',                  'File containing switch definitions and targets.',        '', \$c->{PBS_RESPONSE_FILE},
'prf_no_anonymous',       'Use the given response file or one  named afte user.',   '', \$c->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
'prf_none',               'Don\'t use any response file.',                          '', \$c->{NO_PBS_RESPONSE_FILE},

'pbs_options=s',       'start subpbs options for target matching the regex.',  '', \$c->{PBS_OPTIONS},
'pbs_options_local=s', 'options that only applied at the local subpbs level.', '', \$c->{PBS_OPTIONS_LOCAL},
'pbs_options_end',     'ends the list of subpbs optionss.',                    '', \my $not_used,
'pbs_node_actions=s',  'actions that are run on a node at build time.',     <<EOC, $c->{NODE_BUILD_ACTIONS},

q~example: pbs -ke .  -nba '3::stop' -nba "trigger::priority 4::message '%name'" -trigger '.' -w 0  -fb -dpb0 -j 12 -nh~,
EOC


'path_source=s',          'Source files location, can be used multiple times.', '', $c->{SOURCE_DIRECTORIES},
'path_source_display',    'display all the source directories.',                '', \$c->{DISPLAY_SOURCE_DIRECTORIES},
'path_buildy=s',          'Build directory',                                    '', \$c->{BUILD_DIRECTORY},
'path_lib=s',             "Pbs libs. Multiple directories can be given.",       '', $c->{LIB_PATH},
'path_lib_display',       "Displays PBS lib paths.",                            '', \$c->{DISPLAY_LIB_PATH},
'path_lib_no_warning',    "no warning if using PBS default libs and plugins.",  '', \$c->{NO_DEFAULT_PATH_WARNING},
'path_search_info',       'Show searches',                                      '', \$c->{DISPLAY_SEARCH_INFO},
'path_search_subpbs',     'Show how the subpbs files are found.',               '', \$c->{DISPLAY_SUBPBS_SEARCH_INFO},
'path_search_subpbs_all', 'Display all the subpbs files that could match.',     '', \$c->{DISPLAY_ALL_SUBPBS_ALTERNATIVES},
'path_guide=s',           "Directories containing guides.",                     '', $c->{GUIDE_PATH},
'path_plugins=s',         "The directory must start at '/' (root) or '.'",      '', $c->{PLUGIN_PATH},
'path_plugins_display',   "Displays PBS plugin paths.",                         '', \$c->{DISPLAY_PLUGIN_PATH},

'build_no',               'Only dependen and check.',                               '', \$c->{NO_BUILD},
'build_immediate_build',  'do [IMMEDIATE_BUILD] even if --no_build is set.',        '', \$c->{DO_IMMEDIATE_BUILD},
'build_force|bf',         'Force build if a debug option was given.',               '', \$c->{FORCE_BUILD},
'build_no_stop',          'Continues building in case of errror.',                  '', \$c->{NO_STOP},
'build_pbs_post_display', 'Display the Pbs build post build commands.',             '', \$c->{DISPLAY_PBS_POST_BUILD_COMMANDS},
'post_pbs=s',             'Run the given perl script after pbs.',                   '', $c->{POST_PBS},

'log',                    'Create a log for the build',                             '', \$c->{CREATE_LOG},
'log_tree',               'Add a graph to the log.',                                '', \$c->{LOG_TREE},
'log_html',               'create a html log for each node, implies --create_log ', '', \$c->{CREATE_LOG_HTML},

}

sub TriggerNodeOptions
{
my ($c) = @_ ;
$c->{TRIGGER} //= [] ;

'trigger|T=s',    '(DF) Force the triggering of a node if you want to check its effects.', '', $c->{TRIGGER},
'trigger_all',    '(DF) As if all node triggered, see --trigger',                          '', \$c->{DEBUG_TRIGGER_ALL},
'trigger_none',   '(DF) As if no node triggered, see --trigger',                           '', \$c->{DEBUG_TRIGGER_NONE},
'trigger_list=s', '(DF) Points to a file containing trigers.',                             '', \$c->{DEBUG_TRIGGER_LIST},
'trigger_show',   '(DF) display which files are processed and triggered',                  '', \$c->{DEBUG_DISPLAY_TRIGGER},
'trigger_match',  '(DF) display only files which are triggered',                           '', \$c->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY},
}

sub NodeOptions
{
my ($c) = @_ ;
$c->{DISPLAY_NODE_INFO}        //= [] ;
$c->{DISPLAY_NODE_ENVIRONMENT} //= [] ;
$c->{NODE_ENVIRONMENT_REGEX}   //= [] ;
$c->{LOG_NODE_INFO}            //= [] ;
$c->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT} //= [] ;
$c->{BUILD_AND_DISPLAY_NODE_INFO_REGEX}     //= [] ;

'node_header_none',         "Don't display the name of the node to be build.",                 '', \$c->{DISPLAY_NO_BUILD_HEADER},
'node_match=s',             'Display information for nodes matching the regex.',               '', $c->{DISPLAY_NODE_INFO},
'node_no_build_rule',       'Rules used to depend a node are not displayed',                   '', \$c->{DISPLAY_NO_NODE_BUILD_RULES},
'node_no_parents',          "Don't display the node's parents.",                               '', \$c->{DISPLAY_NO_NODE_PARENTS},
'node_no_info_links',       'Disable files links in info_files and logs',                      '', \$c->{NO_NODE_INFO_LINKS},
'node_log_info=s',          'Log nodes information pre build.',                                '', $c->{LOG_NODE_INFO},
'node_cache_info',          'Display if the node is from the cache.',                          '', \$c->{NODE_CACHE_INFORMATION},
'node_build_name',          'Display the build name in addition to node name.',                '', \$c->{DISPLAY_NODE_BUILD_NAME},
'node_origin',              'Display where the node has been inserted in the graph.',          '', \$c->{DISPLAY_NODE_ORIGIN},
'node_parents',             "Display the node's parents.",                                     '', \$c->{DISPLAY_NODE_PARENTS},
'node_dependencies',        'Display the dependencies for a node.',                            '', \$c->{DISPLAY_NODE_DEPENDENCIES},
'node_environment=s',       'Display the environment variables for nodes matching the regex.', '', $c->{DISPLAY_NODE_ENVIRONMENT},
'node_environment_match=s', 'Display the environment variables matching the regex.',           '', $c->{NODE_ENVIRONMENT_REGEX},
'node_build_reason',        'Display why a node is to be build.',                              '', \$c->{DISPLAY_NODE_BUILD_CAUSE},
'node_build_rule',          'Display the rules used to depend a node.',                        '', \$c->{DISPLAY_NODE_BUILD_RULES},
'node_builder',             'Display the rule which defined the Builder and command.',         '', \$c->{DISPLAY_NODE_BUILDER},
'node_config',              'Display the config used to build a node.',                        '', \$c->{DISPLAY_NODE_CONFIG},
'node_post_build',          'Display the post build commands for each node.',                  '', \$c->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS},
'node_ancestors=s',         '(DF) Display node ancestors.',                                    '', \$c->{DEBUG_DISPLAY_PARENT},
'node_no_commands',         'shell commands are not echoed to the console.',                   '', \$PBS::Shell::silent_commands,
'node_no_commands_output',  'No shell commands except if an error occurs.',                    '', \$PBS::Shell::silent_commands_output,
'node_shell_info',          'Displays which shell executes a command.',                        '', \$c->{DISPLAY_SHELL_INFO},
'node_builder_info',        'Displays if a node builder is a perl sub or shell commands.',     '', \$c->{DISPLAY_BUILDER_INFORMATION},
'node_builder_time',        'Displays the total time builders took.',                          '', \$c->{TIME_BUILDERS},
'node_build_result',        'Display the builder result.',                                     '', \$c->{DISPLAY_BUILD_RESULT},
'node_info_match=s',        'Only display information for matching nodes.',                    '', $c->{BUILD_AND_DISPLAY_NODE_INFO_REGEX},
'node_no_match=s',          "Don't display information for matching nodes.",                   '', $c->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT},
'node_result',              'display node header and build result.',                           '', \$c->{BUILD_DISPLAY_RESULT},
'node_subs_run',            'Show when a node sub is run.',                                    '', \$c->{DISPLAY_NODE_SUBS_RUN},
}

sub DependOptions
{
my ($c) = @_ ;
$c->{DISPLAY_DEPENDENCIES_REGEX}         //= [] ;
$c->{DISPLAY_DEPENDENCIES_REGEX_NOT}     //= [] ;
$c->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT} //= [] ;
$c->{DISPLAY_DEPENDENCIES_RULE_NAME}     //= [] ;

'depend_header',             'Show depend header.',                                   '', \$c->{DISPLAY_DEPEND_HEADER},
'depend_subpbs_info',        'Add extra information for nodes matching a subpbs.',    '', \$c->{DISPLAY_SUBPBS_INFO},
'depend_log',                'Created a log for each subpbs.',                        '', \$c->{DEPEND_LOG},
'depend_full_log',           'Created a log for each subpbs.',                        '', \$c->{DEPEND_FULL_LOG},
'depend_log_merged',         'Merge children subpbs output in log.',                  '', \$c->{DEPEND_LOG_MERGED},
'depend_full_log_options=s', 'Set extra display options for full log.',               '', \$c->{DEPEND_FULL_LOG_OPTIONS},
'depend_result',             'Display the result of each dependency step.',           '', \$c->{DISPLAY_DEPENDENCY_RESULT},
'depend_indented',           'Add indentation before node.',                          '', \$c->{DISPLAY_DEPEND_INDENTED},
'depend_separator=s',        'Display a separator between nodes.',                    '', \$c->{DISPLAY_DEPEND_SEPARATOR},
'depend_new_line',           'Display an extra line after a depend.',                 '', \$c->{DISPLAY_DEPEND_NEW_LINE},
'depend_end',                'Display when a depend ends.',                           '', \$c->{DISPLAY_DEPEND_END},
'depend_time',               'Display the time spend in every Pbsfile.',              '', \$c->{DISPLAY_DEPENDENCY_TIME},
'depend_link_rule',          'Display the rule which matched the node being linked.', '', \$c->{DISPLAY_LINK_MATCHING_RULE},
'depend_check_time',         'Display the graph check time.',                         '', \$c->{DISPLAY_CHECK_TIME},
'depend_too_many_nodes=i',   'Warn when a pbsfile adds too many nodes.',              '', \$c->{DISPLAY_TOO_MANY_NODE_WARNING},
'depend_match=s',            'Node matching the regex are displayed.',                '', $c->{DISPLAY_DEPENDENCIES_REGEX},
'depend_no_match=s',         'Node matching the regex are not displayed.',            '', $c->{DISPLAY_DEPENDENCIES_REGEX_NOT},
'depend_virtual_match_ok',   'No warning if a virtual node matches a directory.',     '', \$c->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY},

'dependencies|d',             '(DF) Display node dependencies.',                           '',    \$c->{DEBUG_DISPLAY_DEPENDENCIES},
'dependencies_long|dl',       '(DF) Display one node dependency perl line.',               '',    \$c->{DEBUG_DISPLAY_DEPENDENCIES_LONG},
'dependencies_regex|dr',      '(DF) Display the regex used to depend a node.',             '',    \$c->{DEBUG_DISPLAY_DEPENDENCY_REGEX},
'dependencies_rule|dmr',      'Display the rule matching the node.',                       '',    \$c->{DISPLAY_DEPENDENCY_MATCHING_RULE},
'dependencies_insertion|dir', 'Display the rule adding the node.',                         '',    \$c->{DISPLAY_DEPENDENCY_INSERTION_RULE},
'dependencies_match=s',       'Display node matching rules regex.',                        '',    $c->{DISPLAY_DEPENDENCIES_RULE_NAME},
'dependencies_match_not=s',   "Don't display nodes matchin rules regex.",                  '',    $c->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT},
'dependencies_definition',    'Display matching rules definitions.',                       '',    \$c->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION},
'dependencies_full_path',     'Don\'t shorten file paths.',                                '',    \$c->{DISPLAY_DEPENDENCIES_FULL_PBSFILE},
'dependencies_pbs_stack',     '(DF) Display pbs call stack.',                              '',    \$c->{DEBUG_TRACE_PBS_STACK},
'dependencies_duplicate',     'Display duplicate dependencies.',                           '',    \$c->{DISPLAY_DUPLICATE_INFO},
'dependencies_zero_ok',       'No warning if node matches rules but has no dependencies.', '',    \$c->{NO_WARNING_ZERO_DEPENDENCIES},
'dependencies_none_ok',       'Show nodes tagged with HasNoDependencies.',                 <<EOC, \$c->{DISPLAY_NO_DEPENDENCIES_OK},

Generated nodes are checked for dependenciesg. 
	some nodes are generated from non files or don't always have dependencies as for C cache which
	dependency file is created on the fly if it doens't exist.
EOC

}

sub WarpOptions
{
my ($c) = @_ ;

'warp|w=s',                "Specify which warp to use.",                 '', \$c->{WARP},
'warp_file_name',          "Display the warp file name.",                '', \$c->{DISPLAY_WARP_FILE_NAME},
'warp_time',               "Display warp creation time.",                '', \$c->{DISPLAY_WARP_TIME},
'warp_human_format',       "Generate warp file in a readable format.",   '', \$c->{WARP_HUMAN_FORMAT},
'warp_no_pre_cache',       "no pre-build warp will be generated.",       '', \$c->{NO_PRE_BUILD_WARP},
'warp_no_cache',           "no post-build warp will be generated.",      '', \$c->{NO_POST_BUILD_WARP},
'warp_checked_nodes',      "Display nodes contained in the warp graph.", '', \$c->{DISPLAY_WARP_CHECKED_NODES},
'warp_checked_nodes_fail', "Display nodes with different hash.",         '', \$c->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY},
'warp_removed_nodes',      "Display nodes removed during warp.",         '', \$c->{DISPLAY_WARP_REMOVED_NODES},
'warp_triggered_nodes',    "Display nodes removed during warp and why.", '', \$c->{DISPLAY_WARP_TRIGGERED_NODES},
}

sub HttpOptions
{
my ($c) = @_ ;

'http_post',    'Display a message when a POST is send.',        '', \$c->{HTTP_DISPLAY_POST},
'http_put',     'Display a message when a PUT is send.',         '', \$c->{HTTP_DISPLAY_PUT},
'http_get',     'Display a message when a GET is send.',         '', \$c->{HTTP_DISPLAY_GET},
'http_start',   'Display a message when a server is started.',   '', \$c->{HTTP_DISPLAY_SERVER_START},
'http_stop',    'Display a message when a server is sshutdown.', '', \$c->{HTTP_DISPLAY_SERVER_STOP},
'http_request', 'Display a message when a request is received.', '', \$c->{HTTP_DISPLAY_REQUEST},
}

sub StatsOptions
{
my ($c) = @_ ;

'time_pbs',        "Display where time is spend in PBS.",                    '', \$c->{DISPLAY_PBS_TIME},
'time_minimum',    "Display time if it is more than  value (default 0.5s).", '', \$c->{DISPLAY_MINIMUM_TIME},
'time_total',      "Display How much time is spend in PBS.",                 '', \$c->{DISPLAY_PBS_TOTAL_TIME},
'time_pbsuse',     "displays the time spend in 'PbsUse' for each pbsfile.",  '', \$c->{DISPLAY_PBSUSE_TIME},
'time_pbsuse_all', "displays the time spend in each pbsuse.",                '', \$c->{DISPLAY_PBSUSE_TIME_ALL},
'time_md5',        "displays the time it takes to hash each node",           '', \$PBS::Digest::display_md5_time,

'stat_md5',                "displays 'MD5' statistic.",                               '', \$c->{DISPLAY_MD5_STATISTICS},
'stat_pbsuse',             "displays 'PbsUse' statistic.",                            '', \$c->{DISPLAY_PBSUSE_STATISTIC},
'stat_pbsfile_nodes',      'Display how many nodes where added by each pbsfile run.', '', \$c->{DISPLAY_NODES_PER_PBSFILE},
'stat_pbsfile_nodes_name', 'Display which nodes where added by each pbsfile run.',    '', \$c->{DISPLAY_NODES_PER_PBSFILE_NAMES},
}

sub CheckOptions
{
my ($c) = @_ ;
$c->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX} //= [] ;
$c->{EXTERNAL_CHECKERS}  //= [] ;

'check_at_build_time',        'Skips node build if dependencies rebuild identically.',               '', \$c->{CHECK_DEPENDENCIES_AT_BUILD_TIME},
'check_hide_skipped_builds',  'Hide builds skipped by -check_dependencies_at_build_time.',           '', \$c->{HIDE_SKIPPED_BUILDS},
'check_terminal_nodes',       'Skips the checking of generated artefacts.',                          '', \$c->{DEBUG_CHECK_ONLY_TERMINAL_NODES},
'check_no_dependencies_ok=s', 'No warning if node has no dependencies.',                             '', $c->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX},
'check_external=s',           q{pbs -ce <(git status -s --uno | perl -ae \"say $PWD . '/' . $F[1]\")}, '', $c->{EXTERNAL_CHECKERS},
'check_cyclic_source_ok',     'No warning if a cycle includes a source files.',                      '', \$c->{NO_SOURCE_CYCLIC_WARNING},
'check_cyclic_source_die',    'Die if a cycle includes a source.',                                   '', \$c->{DIE_SOURCE_CYCLIC_WARNING},
'check_cyclic_tree',          '(DF) Display tree cycles',                                            '', \$c->{DEBUG_DISPLAY_CYCLIC_TREE},
}

sub MatchOptions
{
my ($c) = @_ ;
$c->{DISPLAY_BUILD_INFO} //= [] ;

'build_sequence',        '(DF) Dumps the build sequence data.',                         '', \$c->{DEBUG_DISPLAY_BUILD_SEQUENCE},
'build_sequence_simple', '(DF) List the nodes to be build.',                            '', \$c->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE},
'build_sequence_stats',  '(DF) display number of nodes to be build.',                   '', \$c->{DEBUG_DISPLAY_BUILD_SEQUENCE_STATS},
'build_sequence_save=s', 'Save a list of nodes to be build to a file.',                 '', \$c->{SAVE_BUILD_SEQUENCE_SIMPLE},
'build_sequence_info',   'Display information about which node is build.',              '', \$c->{DISPLAY_BUILD_SEQUENCER_INFO},
'build_info=s',          'Set options: -b -d, ... ; a file or \'*\' can be specified.', '', $c->{DISPLAY_BUILD_INFO},

'link_no_external',      'Stop if Linking from other Pbsfile and local rule matches.',  '', \$c->{NO_EXTERNAL_LINK},
'link_no_info|lni',      'PBS won\'t display which nodes are linked.',                  '', \$c->{NO_LINK_INFO},
'link_local_ok|lnli',    'PBS won\'t display linking to local nodes.',                  '', \$c->{NO_LOCAL_LINK_INFO},
'link_local_rule_ok',    'No warning message if a linked node matches local rules.',    '', \$c->{NO_LOCAL_MATCHING_RULES_INFO},
}

sub PostBuildOptions
{
my ($c) = @_ ;

'post_build_registration', '(DF) Display post build commands registration.', '', \$c->{DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION},
'post_build_definition',   '(DF) Display post build commands definition.',   '', \$c->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION},
'post_build_commands',     '(DF) Display which post build command is run.',  '', \$c->{DEBUG_DISPLAY_POST_BUILD_COMMANDS},
'post_build_result',       'Display post build commands result.',            '', \$c->{DISPLAY_POST_BUILD_RESULT},
}

sub TriggerOptions
{
my ($c) = @_ ;

'trigger_no_import_info', 'Don\'t display triggers imports.',           '', \$c->{NO_TRIGGER_IMPORT_INFO},
'trigger_inserted_nodes', '(DF) Display nodes inserted by a trigger.',  '', \$c->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES},
'triggered',              '(DF) Display why files need to be rebuild.', '', \$c->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES},
}

sub EnvOptions
{
my ($c) = @_ ;
$c->{COMMAND_LINE_DEFINITIONS} //= {} ;
$c->{KEEP_ENVIRONMENT}         //= [] ;
$c->{USER_OPTIONS}             //= {} ;
$c->{VERBOSITY}                //= [] ;

'environment_keep|ek=s',      "%ENV isemptied, --ke 'regex' keeps matching variables.", '', $c->{KEEP_ENVIRONMENT},
'environment',                "Display which environment variables are kept",           '', \$c->{DISPLAY_ENVIRONMENT},
'environment_only_kept',      "Only display the evironment variables kept",             '', \$c->{DISPLAY_ENVIRONMENT_KEPT},
'environment_statistic',      "Display a statistics about environment variables",       '', \$c->{DISPLAY_ENVIRONMENT_STAT},
'environment_user_option=s',  'options to be passed to the build sub.',                 '', $c->{USER_OPTIONS},
'environment_definition|D=s', 'Command line definitions.',                              '', $c->{COMMAND_LINE_DEFINITIONS},

'verbosity=s',
	'Used in user defined modules.',
	 <<EOT, $c->{VERBOSITY},
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

sub DigestOptions
{
my ($c) = @_ ;

'digest',               'Display expected and actual digest.',                 '', \$c->{DISPLAY_DIGEST},
'digest_different',     'Only display when a digest are diffrent.',            '', \$c->{DISPLAY_DIFFERENT_DIGEST_ONLY},
'digest_exclusion',     'Display node exclusion or inclusion.',                '', \$c->{DISPLAY_DIGEST_EXCLUSION},
'digest_warp_warnings', 'Warn if the file to compute hash for does\'t exist.', '', \$c->{WARP_DISPLAY_DIGEST_FILE_NOT_FOUND},
'digest_file_check',    'Display hash checking for individual files.',         '', \$c->{DISPLAY_FILE_CHECK},
}  

#-------------------------------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Config::Options  -

=head1 SYNOPSIS

=head1 DESCRIPTION

Definition of commandline options

=cut



