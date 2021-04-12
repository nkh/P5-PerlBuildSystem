
package PBS::PBSConfigSwitches ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw(RegistredFlagsAndHelp) ;

our $VERSION = '0.05' ;

use Carp ;
use List::Util qw(max any);
use Sort::Naturally ;
use File::Slurp ;

use PBS::Constants ;
use PBS::Output ;

#-------------------------------------------------------------------------------

my %registred_flags ;          # plugins won't override flags
my @registred_flags_and_help ; # allow plugins to register their switches

RegisterDefaultPbsFlags() ; # reserve them so plugins can't modify their meaning

#-------------------------------------------------------------------------------

sub GetOptions
{
my $config = shift // {} ;

=pod
	A
	BuildOptions      

	CheckOptions      
	ConfigOptions     

	DebugOptions      
	DependOptions     
	DevelOptions      
	DigestOptions     

	EnvOptions        
	F
	GraphOptions      

	HelpOptions       
	HttpOptions       
	I 
	J job
	K
	L link
	MatchOptions      
	NodeOptions       
	OutputOptions     

	ParallelOptions   
	PbsSetupOptions   
	PluginOptions     
	PostBuildOptions  

	Q
	RulesOptions      
	StatsOptions      

	TreeOptions       
	TriggerNodeOptions
	TriggerOptions     

	U
	V visualization
	WarpOptions        
	X
	Y
	Z
=cut

my @options = 
	(
	DevelOptions       ($config),
	TriggerNodeOptions ($config),
	HelpOptions        ($config),
	WarpOptions        ($config),
	DigestOptions      ($config),
	EnvOptions         ($config),
	PbsSetupOptions    ($config),
	PluginOptions      ($config),
	ConfigOptions      ($config),
	DependOptions      ($config),
	TriggerOptions     ($config),
	RulesOptions       ($config),
	ParallelOptions    ($config),
	CheckOptions       ($config),
	PostBuildOptions   ($config),
	BuildOptions       ($config),
	MatchOptions       ($config),
	HttpOptions        ($config),
	NodeOptions        ($config),
	OutputOptions      ($config),
	StatsOptions       ($config),
	TreeOptions        ($config),
	GraphOptions       ($config),
	DebugOptions       ($config),
	) ;

$config->{DO_BUILD}                                = 1 ;
$config->{SHORT_DEPENDENCY_PATH_STRING}            = '…' ;
$config->{PBS_QR_OPTIONS}                        //= [] ;

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

OPTION:
for my $option (sort { $a->[0] cmp $b->[0] } GetOptionsElements())
	{
	for my $option_element (split /\|/, $option->[0])
		{
		$option_element =~ s/=.*$// ;
		
		if( any { $_ eq $option_element} @switches )
			{
			push @matches, $option ;
			next OPTION ;
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

	Say EC sprintf( "<I3>--%-${max_long}s <W3>%-${max_short}s<I3>$lht: ", $long, ($short eq '' ? '' : "--$short"))
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

#-------------------------------------------------------------------------------

sub GetCompletion
{
my (undef, $command_name, $word_to_complete, $previous_arguments) = @ARGV ;
my ($options) = @_ ;

print Complete($options, $word_to_complete) ;
}

sub Complete
{
my ($options, $word_to_complete) = @_ ;

if($word_to_complete !~ /^-?-?\s?$/)
	{
	my (@slice, @options) ;
	push @options, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 
	
	my ($names, $option_tuples) = Term::Bash::Completion::Generator::de_getop_ify_list(\@options) ;
	
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
			
			defined $munged ? "-$munged\n": "-$matches[0]\n" ;
			}
		else
			{
			@matches = $matches[$point - 1] if $point and defined $matches[$point - 1] ;
			
			if(@matches < 2)
				{
				join("\n",  @matches) . "\n" ;
				}
			else
				{
				my $counter = 0 ;
				join("\n", map { $counter++ ; "$_₊" . subscript($counter)} @matches) . "\n" ;
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
				@matches > 1 ? join("\n", map { $c++ ; "--$_₊" . subscript($c) } nsort @matches) . "\n" : "\n​\n" ;
				}
			else
				{
				my $c = 0 ;
				join("\n", map { $c++ ; "--$_₊" . subscript($c)} nsort grep { $_ =~ $matcher } @$names) . "\n" ;
				}
			}
		else
			{
			my $word = $word_to_complete =~ s/^-*//r ;
			
			my @matches = nsort grep { /$word/ } @$names ;
			   @matches = $matches[$point - 1] if $point and defined $matches[$point - 1] ;
			
			if(@matches < 2)
				{
				join("\n", map { "--$_" } @matches) . "\n" ;
				}
			else
				{
				my $c = 0 ;
				join("\n", map { $c++ ; "--$_₊" . subscript($c)} @matches) . "\n" ;
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
		
	push @registred_flags_and_help, $switch, $help1, $help2, $variable 
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

sub DebugOptions
{
my ($c) = @_ ;

$c->{BREAKPOINTS} //= [] ;
$c->{POST_PBS}    //= [] ;

'post_pbs=s',                          "Run the given perl script after pbs. Usefull to generate reports, etc.", '', $c->{POST_PBS},
'bp|debug:s',                          'Enable debug support A startup file defining breakpoints can be given.', '', $c->{BREAKPOINTS},
'bph|debug_display_breakpoint_header', 'Display a message when a breakpoint is run.',                            '', \$c->{DISPLAY_BREAKPOINT_HEADER},
'dump',                                'Dump an evaluable tree.',                                                '', \$c->{DUMP},
}

sub ParallelOptions
{
my ($c) = @_ ;
$c->{JOBS_DIE_ON_ERROR} //= 0 ;

'distribute=s',                                 
	'Define where to distribute the build.',
	'The file must return a list of hosts in the format defined by the default distributor or define a distributor.',
	 \$c->{DISTRIBUTE},

'j|jobs=i',                                'Maximum number of build commands run in parallel.',                     '', \$c->{JOBS},
'jdoe|jobs_die_on_errors=i',               '0 (default) finish running jobs. 1 die immediatly. 2 no stop.',         '', \$c->{JOBS_DIE_ON_ERROR},
'pj|pbs_jobs=i',                           'Maximum number of dependers run in parallel.',                          '', \$c->{PBS_JOBS},
'cj|check_jobs=i',                         'Maximum number of checker run in parallel.',                            '', \$c->{CHECK_JOBS},
'dp|depend_processes=i',                   'Maximum number of depend processes.',                                   '', \$c->{DEPEND_PROCESSES},
'dji|display_jobs_info',                   'PBS will display extra information about the parallel build.',          '', \$c->{DISPLAY_JOBS_INFO},
'djr|display_jobs_running',                'PBS will display which nodes are under build.',                         '', \$c->{DISPLAY_JOBS_RUNNING},
'djnt|display_jobs_no_tally',              'will not display nodes tally.',                                         '', \$c->{DISPLAY_JOBS_NO_TALLY},
'ddplg|log_parallel_depend',               'Creates a log of the parallel depend.',                                 '', \$c->{LOG_PARALLEL_DEPEND},
'ddpdlg|display_log_parallel_depend',      'Display the parallel depend log when depending ends.',                  '', \$c->{DISPLAY_LOG_PARALLEL_DEPEND},
'pds|parallel_depend_start',               'Display a message when a parallel depend starts.',                      '', \$c->{DISPLAY_PARALLEL_DEPEND_START},
'pde|parallel_depend_end',                 'Display a message when a parallel depend end.',                         '', \$c->{DISPLAY_PARALLEL_DEPEND_END},
'pdn|parallel_depend_node',                'Display the node name in parallel depend end messages.',                '', \$c->{DISPLAY_PARALLEL_DEPEND_NODE},
'pdnr|parallel_depend_no_resource',        'Display a message when no resource is availabe for a parallel depend.', '', \$c->{DISPLAY_PARALLEL_DEPEND_NO_RESOURCE},
'pdl|parallel_depend_linking',             'Display parallel depend linking result.',                               '', \$c->{DISPLAY_PARALLEL_DEPEND_LINKING},
'dplv|parallel_depend_linking_verbose',    'Display a verbose parallel depend linking result.',                     '', \$c->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE},
'pdt|parallel_depend_tree',                'Display the distributed dependency graph using a text dumper',          '', \$c->{DISPLAY_PARALLEL_DEPEND_TREE},
'dppt|parallel_depend_process_tree',       'Display the distributed process graph using a text dumper',             '', \$c->{DISPLAY_PARALLEL_DEPEND_PROCESS_TREE},
'dpuc|parallel_use_compression',           'Compress graphs before sending them',                                   '', \$c->{DEPEND_PARALLEL_USE_COMPRESSION},
'dgbss|display_global_build_sequence',     '(DF) List the nodes to be build and the pid of their parallel pbs.',    '', \$c->{DEBUG_DISPLAY_GLOBAL_BUILD_SEQUENCE},
'ddrp|display_depend_remaining_processes', 'Display running depend processes after the main depend ends.',          '', \$c->{DISPLAY_DEPEND_REMAINING_PROCESSES},
'dus|use_depend_server',                   'Use parallel pbs server multiple times.',                               '', \$c->{USE_DEPEND_SERVER},
'rqsd|resource_quick_shutdown',            '',                                                                      '', \$c->{RESOURCE_QUICK_SHUTDOWN},
}

sub HelpOptions
{
my ($c) = @_ ;

'hud|help_user_defined',
	 "Displays a user defined help. See 'Online help' in pbs.pod",
	 <<'EOH', \$c->{DISPLAY_PBSFILE_POD},
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

'v|version',                        'Displays Pbs version.',                                          '', \$c->{DISPLAY_VERSION},
'h|help',                           'Displays this help.',                                            '', \$c->{DISPLAY_HELP},
'hs|help_switch=s',                 'Displays help for the given switch.',                            '', \$c->{DISPLAY_SWITCH_HELP},
'hnd|help_narrow_display',          'Writes the flag name and its documentation  on separate lines.', '', \$c->{DISPLAY_HELP_NARROW_DISPLAY},
'pod_extract',                      'Extracts the pod contained in the Pbsfile.',                     '', \$c->{PBS2POD},
'pod_raw',                          '-pbsfile_pod or -pbs2pod is dumped in raw pod format.',          '', \$c->{RAW_POD},
'pod_interactive_documenation:s',   'Interactive PBS documentation display and search.',              '', \$c->{DISPLAY_POD_DOCUMENTATION},
'options_get_completion',           'return completion list.',                                        '', \$c->{GET_BASH_COMPLETION},
'options_list',                     'return completion list on stdout.',                              '', \$c->{GET_OPTIONS_LIST},
'wizard:s',                         'Starts a wizard.',                                               '', \$c->{WIZARD},
'wi|display_wizard_info',           'Shows Informatin about the found wizards.',                      '', \$c->{DISPLAY_WIZARD_INFO},
'wh|display_wizard_help',           'Tell the choosen wizards to show help.',                         '', \$c->{DISPLAY_WIZARD_HELP},
}

sub OutputOptions
{
my ($c) = @_ ;

'nbh|no_build_header',                    "Don't display the name of the node to be build.",       '', \$c->{DISPLAY_NO_BUILD_HEADER},
'bpb0|display_no_progress_bar',           "Display no progress bar.",                              '', \$c->{DISPLAY_NO_PROGRESS_BAR},
'bpb1|display_progress_bar',              "Force silent build mode and displays a progress bar.",  '', \$c->{DISPLAY_PROGRESS_BAR},
'bpb2|display_progress_bar_file',         "Built node names are displayed above the progress bar", '', \$c->{DISPLAY_PROGRESS_BAR_FILE},
'bpb3|display_progress_bar_process',      "Display a progress per build process",                  '', \$c->{DISPLAY_PROGRESS_BAR_PROCESS},
'bn|box_node',                            'Display a colored margin for each node display.',       '', \$c->{BOX_NODE},
'q|quiet',                                'less verbose output.',                                  '', \$c->{QUIET},
'output_info_label=s',                    'Adds a text label to all output.',                      '', \&PBS::Output::InfoLabel,
'output_indentation=s',                   'set the text used to indent the output.',               '', \$PBS::Output::indentation,
'output_indentation_none',                '',                                                      '', \$PBS::Output::no_indentation,
'output_full_path',                       'Display full path for files.',                          '', \$c->{DISPLAY_FULL_DEPENDENCY_PATH},
'output_short_path_glyph=s',              'Replace full dependency_path with argument.',           '', \$c->{SHORT_DEPENDENCY_PATH_STRING},
'OFW|output_from_where',                  '',                                                      '', \$PBS::Output::output_from_where,
'bvm|display_no_progress_bar_minimum',    "Slightly less verbose build mode.",                     '', \$c->{DISPLAY_NO_PROGRESS_BAR_MINIMUM},
'bvmm|display_no_progress_bar_minimum_2', "Definitely less verbose build mode.",                   '', \$c->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2},


'bv|build_verbose',                       "Verbose build mode.",                                <<EOT, \$c->{BUILD_AND_DISPLAY_NODE_INFO},
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

'p|palette_depth=s',                        'Set color depth. Valid values are 2 = black and white, 16, 256', '', \&PBS::Output::SetOutputColorDepth,

'pu|palette_user=s',                        "Set a color. eg: -cs 'user:cyan on_yellow'",                  <<EOT, \&PBS::Output::SetOutputColor,
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
}

sub RulesOptions
{
my ($c)  = @_ ;
$c->{RULE_NAMESPACES} //= [] ;

'ra|rule_all',                 'Display all the rules.',                                          '', \$c->{DISPLAY_ALL_RULES},
'rd|rule_definition',          '(DF) Display the definition of each registrated rule.',           '', \$c->{DEBUG_DISPLAY_RULE_DEFINITION},
'ri|rule_inactive',            'Display rules present i the åbsfile but tagged as NON_ACTIVE.',   '', \$c->{DISPLAY_INACTIVE_RULES},
'rnm|rule_non_matching',       'Display the rules used during the dependency pass.',              '', \$c->{DISPLAY_NON_MATCHING_RULES},
'rns|rule_no_scope',           'Disable rule scope.',                                             '', \$c->{RULE_NO_SCOPE},
'rro|rule_run_once',           'Rules run only once except if they are tagged as MULTI',          '', \$c->{RULE_RUN_ONCE},
'r|rule',                      '(DF) Display registred rules and which package is queried.',      '', \$c->{DEBUG_DISPLAY_RULES},
'rsp|rules_subpbs_definition', 'Display subpbs definition.',                                      '', \$c->{DISPLAY_SUB_PBS_DEFINITION},
'rs|rule_statistics',          '(DF) Display rule statistics after each pbs run.',                '', \$c->{DEBUG_DISPLAY_RULE_STATISTICS},
'rtd|rule_trigger_definition', '(DF) Display the definition of each registrated trigger.',        '', \$c->{DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION},
'rt|rule_trigger',             '(DF) Display which triggers are registred.',                      '', \$c->{DEBUG_DISPLAY_TRIGGER_RULES},
'rule_max_recursion',          'Set the maximum rule recusion before pbs, aborts the build',      '', \$c->{MAXIMUM_RULE_RECURSION},
'rule_namespace=s',            'Rule name space to be used by DefaultBuild()',                    '', $c->{RULE_NAMESPACES},
'rule_order',                  'Display the order rules.',                                        '', \$c->{DISPLAY_RULES_ORDER},
'rule_ordering',               'Display the pbsfile used to order rules and the rules order.',    '', \$c->{DISPLAY_RULES_ORDERING},
'rule_recursion_warning',      'Set the level at which pbs starts warning aabout rule recursion', '', \$c->{RULE_RECURSION_WARNING},
'rule_scope',                  'display scope parsing and generation',                            '', \$c->{DISPLAY_RULE_SCOPE},
'rule_to_order',               'Display that there are rules order.',                             '', \$c->{DISPLAY_RULES_TO_ORDER},
'run|rule_used_name',          'Display the names of the rules used during the dependency pass.', '', \$c->{DISPLAY_USED_RULES_NAME_ONLY},
'ru|rule_used',                'Display the rules used during the dependency pass.',              '', \$c->{DISPLAY_USED_RULES},
}

sub ConfigOptions
{
my ($c) = @_ ;
$c->{CONFIG_NAMESPACES}         //= [];
$c->{DISPLAY_PBS_CONFIGURATION} //= [];

my $load_config_closure = sub { LoadConfig(@_, $c) } ;

'ca|config_all',             '(DF). Display all configurations.',                    '', \$c->{DEBUG_DISPLAY_ALL_CONFIGURATIONS},
'c|config',                  'Display the config used during a Pbs run.',            '', \$c->{DISPLAY_CONFIGURATION},
'cl|config_location',        'Display the pbs configuration location.',              '', \$c->{DISPLAY_PBS_CONFIGURATION_LOCATION},
'cm|config_merge',           '(DF). Display how configurations are merged.',         '', \$c->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE},
'cn|config_namespaces',      'Display the config namespaces used during a Pbs run.', '', \$c->{DISPLAY_CONFIGURATION_NAMESPACES},
'cnu|config_node_usage',     'Display config variables not used by nodes.',          '', \$c->{DISPLAY_NODE_CONFIG_USAGE},
'config_delta',              'Display difference with the parent config',            '', \$c->{DISPLAY_CONFIGURATION_DELTA},
'config_load=s',             'Load the given config before running the Pbsfile.',    '', $load_config_closure,
'config_no_inheritance',     'disable configuration iheritance.',                    '', \$c->{NO_CONFIG_INHERITANCE},
'config_no_silent_override', 'Disabe SILENT_OVERRIDE.',                              '', \$c->{NO_SILENT_OVERRIDE},
'config_package',            'display subpbs package configuration',                 '', \$c->{DISPLAY_PACKAGE_CONFIGURATION},
'config_set_namespace=s',    'Configuration name space to used',                     '', $c->{CONFIG_NAMESPACES},
'config_target_path',        "Don't remove TARGET_PATH from config usage report.",   '', \$c->{DISPLAY_TARGET_PATH_USAGE},
'cpa|config_pbs_all',        'Include undefined keys',                               '', \$c->{DISPLAY_PBS_CONFIGURATION_UNDEFINED_VALUES},
'cp|config_pbs=s',           'Display the pbs configuration matching  the regex.',   '', $c->{DISPLAY_PBS_CONFIGURATION},
'cs|config_start',           'Display the config for a Pbs run pre pbsfile loading', '', \$c->{DISPLAY_CONFIGURATION_START},
'csp|config_subpbs',         'Display subpbs config.',                               '', \$c->{DISPLAY_SUB_PBS_CONFIG},
'cu|config_usage',           'Display config variables not used.',                   '', \$c->{DISPLAY_CONFIG_USAGE},
'config_save=s',             'PBS will save the config used in each PBS run',     <<EOT, \$c->{SAVE_CONFIG},

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

'DNDC|devel_no_distribution_check',
	'A development flag, not for user.',
	<<EOT, \$config->{DEVEL_NO_DISTRIBUTION_CHECK},
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

'tt|text_tree',                     '(DF) Display the dependency tree using a text dumper', '', \$c->{DEBUG_DISPLAY_TEXT_TREE},
'ttmr|text_tree_match_regex:s',     'limits how many trees are displayed.',                 '', $c->{DISPLAY_TEXT_TREE_REGEX},
'ttmm|text_tree_match_max:i',       'limits how many trees are displayed.',                 '', \$c->{DISPLAY_TEXT_TREE_MAX_MATCH},
'ttf|text_tree_filter=s',           '(DF) List the fields to display when -tt is used.',    '', $c->{DISPLAY_TREE_FILTER},
'tta|text_tree_use_ascii',          'Use ASCII characters to draw the tree.',               '', \$c->{DISPLAY_TEXT_TREE_USE_ASCII},
'ttdhtml|text_tree_use_dhtml=s',    'Generate a dhtml dump of the tree.',                   '', \$c->{DISPLAY_TEXT_TREE_USE_DHTML},
'ttmd|text_tree_max_depth=i',       'Limit the depth of the dumped tree.',                  '', \$c->{DISPLAY_TEXT_TREE_MAX_DEPTH},
'tno|tree_name_only',               '(DF) Display the name of the nodes only.',             '', \$c->{DEBUG_DISPLAY_TREE_NAME_ONLY},
'vas|visualize_after_subpbs',       '(DF) run visualization plugins after every subpbs.',   '', \$c->{DEBUG_VISUALIZE_AFTER_SUPBS},
'tda|tree_depended_at',             '(DF) Display the Pbsfile used to depend each node.',   '', \$c->{DEBUG_DISPLAY_TREE_DEPENDED_AT},
'tia|tree_inserted_at',             '(DF) Display where the node was inserted.',            '', \$c->{DEBUG_DISPLAY_TREE_INSERTED_AT},
'tnd|tree_display_no_dependencies', '(DF) Don\'t show child nodes data.',                   '', \$c->{DEBUG_DISPLAY_TREE_NO_DEPENDENCIES},
'tad|tree_display_all_data',        'Forces the display of all data even those not set.',   '', \$c->{DEBUG_DISPLAY_TREE_DISPLAY_ALL_DATA},
'tnb|tree_name_build',              '(DF) Display the build name of the nodes.',            '', \$c->{DEBUG_DISPLAY_TREE_NAME_BUILD},
'tntr|tree_node_triggered_reason',  '(DF) Display why a node is to be rebuild.',            '', \$c->{DEBUG_DISPLAY_TREE_NODE_TRIGGERED_REASON},
'tm|tree_maxdepth=i',               'Maximum depth of the structures displayed by pbs.',    '', \$c->{MAX_DEPTH},
'ti|tree_indentation=i',            'Data dump indent style (0-1-2).',                      '', \$c->{INDENT_STYLE},
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

'no_source_cyclic_warning',        'No warning if a cycle includes a source files.',       '', \$c->{NO_SOURCE_CYCLIC_WARNING},
'die_source_cyclic_warning',       'Die if a cycle includes a source.',                    '', \$c->{DIE_SOURCE_CYCLIC_WARNING},

'f|files|nodes',                   'List all the nodes in the graph.',                     '', \$c->{DISPLAY_FILE_LOCATION},
'fa|files_all|nodes_all',          'List all the nodes in the graph.',                     '', \$c->{DISPLAY_FILE_LOCATION_ALL},

'gtg_cn=s',                        'Display node and dependencies as a single unit.',      '', $c->{GENERATE_TREE_GRAPH_CLUSTER_NODE},
'gtg_cr=s',                        'Display nodes matching the regex in a single node.',   '', $c->{GENERATE_TREE_GRAPH_CLUSTER_REGEX},
'display_cyclic_tree',             '(DF) Display tree cycles',                             '', \$c->{DEBUG_DISPLAY_CYCLIC_TREE},
'gtg|graph_tree=s',                'Generate a graph in the file name given as argument.', '', \$c->{GENERATE_TREE_GRAPH},
'gtg_p|graph_package',             'Groups the node by definition package.',               '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_PACKAGE},
'gtg_canonical=s',                 'Generates a canonical dot file.',                      '', \$c->{GENERATE_TREE_GRAPH_CANONICAL},
'gtg_format=s',                    'Chose graph format: svg (default), ps, png.',          '', \$c->{GENERATE_TREE_GRAPH_FORMAT},
'gtg_html=s',                      'Generates a graph in html format.',                    '', \$c->{GENERATE_TREE_GRAPH_HTML},
'gtg_html_frame',                  'Use frames in the html graph.',                        '', \$c->{GENERATE_TREE_GRAPH_HTML_FRAME},
'gtg_snapshots=s',                 'Generates snapshots of the build.',                    '', \$c->{GENERATE_TREE_GRAPH_SNAPSHOTS},
'gtg_crl=s',                       'Regex list to cluster nodes',                          '', \$c->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST},
'gtg_sd|graph_source_directories', 'Groups nodes by source directories',                   '', \$c->{GENERATE_TREE_GRAPH_CLUSTER_SOURCE_DIRECTORIES},
'gtg_exclude|graph_exclude=s',     "Exclude nodes from the graph.",                        '', $c->{GENERATE_TREE_GRAPH_EXCLUDE},
'gtg_include|graph_include=s',     "Forces nodes back into the graph.",                    '', $c->{GENERATE_TREE_GRAPH_INCLUDE},
'gtg_bd',                          'Display node build directory.',                        '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY},
'gtg_rbd',                         'Display root build directory.',                        '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY},
'gtg_tn',                          'Display Trigger inserted nodes.',                      '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES},
'gtg_config',                      'Display configs.',                                     '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG},
'gtg_config_edge',                 'Display an edge from nodes to their config.',          '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE},
'gtg_pbs_config',                  'Display package configs.',                             '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG},
'gtg_pbs_config_edge',             'Display an edge from nodes to their package.',         '', \$c->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE},
'gtg_gm|group_mode=i',             'Set mode: 0 no grouping, 1,2.',                        '', \$c->{GENERATE_TREE_GRAPH_GROUP_MODE},
'gtg_spacing=f',                   'Multiply node spacing with given coefficient.',        '', \$c->{GENERATE_TREE_GRAPH_SPACING},
'gtg_printer|graph_printer',       'Non triggerring edges as dashed lines.',               '', \$c->{GENERATE_TREE_GRAPH_PRINTER},
'gtg_sn|graph_start_node=s',       'Graph start node.',                                    '', \$c->{GENERATE_TREE_GRAPH_START_NODE},
}

sub PluginOptions
{
my ($c) = @_ ;

$c->{PLUGIN_PATH} //= []  ;

'plugins_path=s',       "The directory must start at '/' (root) or '.'", '', $c->{PLUGIN_PATH},
'plugins_path_display', "Displays PBS plugin paths.",                    '', \$c->{DISPLAY_PLUGIN_PATH},
'plugins_load_info',    "displays which plugins are loaded.",            '', \$c->{DISPLAY_PLUGIN_LOAD_INFO},
'plugins_runs',         "displays which plugins subs are run.",          '', \$c->{DISPLAY_PLUGIN_RUNS},
'plugins_runs_all',     "displays plugins subs are not run.",            '', \$c->{DISPLAY_PLUGIN_RUNS_ALL},
}

sub PbsSetupOptions
{
my ($c) = @_ ;
$c->{EXTERNAL_CHECKERS}  //= [] ;
$c->{LIB_PATH}           //= [] ;
$c->{SOURCE_DIRECTORIES} //= [] ;

'sd|source_directory=s',
	'Directory where source files can be found. Can be used multiple times.',
	<<EOT, $c->{SOURCE_DIRECTORIES},
Source directories are searched in the order they are given. The current 
directory is taken as the source directory if no --SD switch is given on
the command line. 

See also switches: --display_search_info --display_all_alternatives
EOT

'pbsfile=s',                        'Pbsfile use to defines the build.',                      '', \$c->{PBSFILE},
'pfn|pbsfile_names=s',              'space separated file names that can be pbsfiles.',       '', \$c->{PBSFILE_NAMES},
'pfe|pbsfile_extensions=s',         'space separated extensionss that can match a pbsfile.',  '', \$c->{PBSFILE_EXTENSIONS},
'prf=s',                            'File containing switch definitions and targets.',        '', \$c->{PBS_RESPONSE_FILE},
'prfna|prf_no_anonymous',           'Use the given response file or one  named afte user.',   '', \$c->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
'prfn|prf_none',                    'Don\'t use any response file.',                          '', \$c->{NO_PBS_RESPONSE_FILE},
'pbs_options=s',                    'start subpbs options for target matching the regex.',    '', \$c->{PBS_OPTIONS},
'pbs_options_local=s',              'options that only applied at the local subpbs level.',   '', \$c->{PBS_OPTIONS_LOCAL},
'pbs_options_end',                  'ends the list of subpbs optionss.',                      '', \my $not_used,
'path_lib=s',                       "Pbs libs. Multiple directories can be given.",           '', $c->{LIB_PATH},
'path_lib_display',                 "Displays PBS lib paths.",                                '', \$c->{DISPLAY_LIB_PATH},
'path_no_default_warning',          "no warning if using PBS default libs and plugins.",      '', \$c->{NO_DEFAULT_PATH_WARNING},
'dpu|display_pbsuse',               "displays which pbs module is loaded by a 'PbsUse'.",     '', \$c->{DISPLAY_PBSUSE},
'dpuv|display_pbsuse_verbose',      "more verbose --display_pbsuse'",                         '', \$c->{DISPLAY_PBSUSE_VERBOSE},
'build_directory=s',                '',                                                       '', \$c->{BUILD_DIRECTORY},
'mandatory_build_directory',        'Build directory must be given.',                         '', \$c->{MANDATORY_BUILD_DIRECTORY},
'no_build',                         'Only dependen and check.',                               '', \$c->{NO_BUILD},
'fb|force_build',                   'Force build if a debug option was given.',               '', \$c->{FORCE_BUILD},
'ns|no_stop',                       'Continues building in case of errror.',                  '', \$c->{NO_STOP},
'do_immediate_build',               'do [IMMEDIATE_BUILD] even if --no_build is set.',        '', \$c->{DO_IMMEDIATE_BUILD},
'nh|no_header',                     'No header display',                                      '', \$c->{DISPLAY_NO_STEP_HEADER},
'nhc|no_header_counter',            'Hide depend counter',                                    '', \$c->{DISPLAY_NO_STEP_HEADER_COUNTER},
'nhnl|no_header_newline',           'add a new line instead for the counter',                 '', \$c->{DISPLAY_STEP_HEADER_NL},
'dsi|display_subpbs_info',          'Add extra information for nodes matching a subpbs.',     '', \$c->{DISPLAY_SUBPBS_INFO},
'l|log|create_log',                 'Create a log for the build',                             '', \$c->{CREATE_LOG},
'log_tree',                         'Add a graph to the log.',                                '', \$c->{LOG_TREE},
'log_html|create_log_html',         'create a html log for each node, implies --create_log ', '', \$c->{CREATE_LOG_HTML},
'pos|original_pbsfile_source',      'Display original Pbsfile source.',                       '', \$c->{DISPLAY_PBSFILE_ORIGINAL_SOURCE},
'dps|display_pbsfile_source',       'Display Modified Pbsfile source.',                       '', \$c->{DISPLAY_PBSFILE_SOURCE},
'dec|display_error_context',        'Display the error line.',                                '', \$PBS::Output::display_error_context,
'display_no_perl_context',          'Do not parse the perl code to find the error context.',  '', \$c->{DISPLAY_NO_PERL_CONTEXT},
'dpl|display_pbsfile_loading',      'Display which pbsfile is loaded.',                       '', \$c->{DISPLAY_PBSFILE_LOADING},
'dplt|display_pbsfile_load_time',   'Display the load time for a pbsfile.',                   '', \$c->{DISPLAY_PBSFILE_LOAD_TIME},
'display_subpbs_search_info',       'Show how the subpbs files are found.',                   '', \$c->{DISPLAY_SUBPBS_SEARCH_INFO},
'display_all_subpbs_alternatives',  'Display all the subpbs files that could match.',         '', \$c->{DISPLAY_ALL_SUBPBS_ALTERNATIVES},
'dsd|display_source_directory',     'display all the source directories.',                    '', \$c->{DISPLAY_SOURCE_DIRECTORIES},
'allow_virtual_to_match_directory', 'No warning if a virtual node matches a directory.',      '', \$c->{ALLOW_VIRTUAL_TO_MATCH_DIRECTORY},

'ce|external_checker=s',
	'external list of changed nodes',
	'pbs -ce <(git status --short --untracked-files=no | perl -ae "print \"$PWD/\$F[1]\n\"")', $c->{EXTERNAL_CHECKERS},

'display_search_info',
	'Display the files searched in the source directories. See --daa.',
	<<EOT, \$c->{DISPLAY_SEARCH_INFO},
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

'daa|display_all_alternates',
	'Display all the files found in the source directories.',
	<<EOT, \$c->{DISPLAY_SEARCH_ALTERNATES},
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
}

sub TriggerNodeOptions
{
my ($c) = @_ ;
$c->{TRIGGER} //= [] ;

'TN|trigger_none',                '(DF) As if no node triggered, see --trigger',                           '', \$c->{DEBUG_TRIGGER_NONE},
'T|trigger=s',                    '(DF) Force the triggering of a node if you want to check its effects.', '', $c->{TRIGGER},
'TA|trigger_all',                 '(DF) As if all node triggered, see --trigger',                          '', \$c->{DEBUG_TRIGGER_ALL},
'TL|trigger_list=s',              '(DF) Points to a file containing trigers.',                             '', \$c->{DEBUG_TRIGGER_LIST},
'TD|display_trigger',             '(DF) display which files are processed and triggered',                  '', \$c->{DEBUG_DISPLAY_TRIGGER},
'TDM|display_trigger_match_only', '(DF) display only files which are triggered',                           '', \$c->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY},
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

'ni|node_information=s',                    'Display information for nodes matching the regex.',               '', $c->{DISPLAY_NODE_INFO},
'nnr|no_node_build_rule',                   'Rules used to depend a node are not displayed',                   '', \$c->{DISPLAY_NO_NODE_BUILD_RULES},
'nnp|no_node_parents',                      "Don't display the node's parents.",                               '', \$c->{DISPLAY_NO_NODE_PARENTS},
'nonil|no_node_info_links',                 'Disable files links in info_files and logs',                      '', \$c->{NO_NODE_INFO_LINKS},
'nli|log_node_information=s',               'Log nodes information pre build.',                                '', $c->{LOG_NODE_INFO},
'nci|node_cache_information',               'Display if the node is from the cache.',                          '', \$c->{NODE_CACHE_INFORMATION},
'nbn|node_build_name',                      'Display the build name in addition to node name.',                '', \$c->{DISPLAY_NODE_BUILD_NAME},
'no|node_origin',                           'Display where the node has been inserted in the graph.',          '', \$c->{DISPLAY_NODE_ORIGIN},
'np|node_parents',                          "Display the node's parents.",                                     '', \$c->{DISPLAY_NODE_PARENTS},
'nd|node_dependencies',                     'Display the dependencies for a node.',                            '', \$c->{DISPLAY_NODE_DEPENDENCIES},
'ne|node_environment=s',                    'Display the environment variables for nodes matching the regex.', '', $c->{DISPLAY_NODE_ENVIRONMENT},
'ner|node_environment_regex=s',             'Display the environment variables  matching the regex.',          '', $c->{NODE_ENVIRONMENT_REGEX},
'nc|node_build_cause',                      'Display why a node is to be build.',                              '', \$c->{DISPLAY_NODE_BUILD_CAUSE},
'nr|node_build_rule',                       'Display the rules used to depend a node.',                        '', \$c->{DISPLAY_NODE_BUILD_RULES},
'nb|node_builder',                          'Display the rule which defined the Builder and command.',         '', \$c->{DISPLAY_NODE_BUILDER},
'nconf|node_config',                        'Display the config used to build a node.',                        '', \$c->{DISPLAY_NODE_CONFIG},
'npbc|node_build_post_build_commands',      'Display the post build commands for each node.',                  '', \$c->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS},
'a|ancestors=s',                            '(DF) Display the ancestors of a file.',                           '', \$c->{DEBUG_DISPLAY_PARENT},
'sc|silent_commands',                       'shell commands are not echoed to the console.',                   '', \$PBS::Shell::silent_commands,
'sco|silent_commands_output',               'No shell commands except if an error occurs.',                    '', \$PBS::Shell::silent_commands_output,
'display_shell_info',                       'Displays which shell executes a command.',                        '', \$c->{DISPLAY_SHELL_INFO},
'dbi|display_builder_info',                 'Displays if a node builder is a perl sub or shell commands.',     '', \$c->{DISPLAY_BUILDER_INFORMATION},
'time_builders',                            'Displays the total time builders took.',                          '', \$c->{TIME_BUILDERS},
'bre|display_build_result',                 'Display the builder result.',                                     '', \$c->{DISPLAY_BUILD_RESULT},
'bnir|build_and_display_node_regex=s',      'Only display information for matching nodes.',                    '', $c->{BUILD_AND_DISPLAY_NODE_INFO_REGEX},
'bnirn|build_and_display_node_regex_not=s', "Don't display information for matching nodes.",                   '', $c->{BUILD_AND_DISPLAY_NODE_INFO_REGEX_NOT},
'bni_result',                               'display node header and build resultr.',                          '', \$c->{BUILD_DISPLAY_RESULT},
'ppbc|pbs_build_post_build_commands',       'Display the Pbs build post build commands.',                      '', \$c->{DISPLAY_PBS_POST_BUILD_COMMANDS},

'o|origin',
	'PBS will also display the origin of rules in addition to their names.',
	 <<EOT, \$c->{ADD_ORIGIN},
The origin contains the following information:
* Name
* Package
* Namespace
* Definition file
* Definition line
EOT

}

sub DependOptions
{
my ($c) = @_ ;
$c->{DISPLAY_DEPENDENCIES_REGEX}         //= [] ;
$c->{DISPLAY_DEPENDENCIES_REGEX_NOT}     //= [] ;
$c->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT} //= [] ;
$c->{DISPLAY_DEPENDENCIES_RULE_NAME}     //= [] ;

'dd|display_dependencies',                    '(DF) Display the node dependencies.',                   '', \$c->{DEBUG_DISPLAY_DEPENDENCIES},
'dh|depend_header',                           'Show depend header.',                                   '', \$c->{DISPLAY_DEPEND_HEADER},
'ddl|display_dependencies_long',              '(DF) Display one node dependency perl line.',           '', \$c->{DEBUG_DISPLAY_DEPENDENCIES_LONG},
'ddt|display_dependency_time',                ' Display the time spend in every Pbsfile.',             '', \$c->{DISPLAY_DEPENDENCY_TIME},
'dct|display_check_time',                     ' Display the graph check time.',                        '', \$c->{DISPLAY_CHECK_TIME},
'dre|dependency_result',                      'Display the result of each dependency step.',           '', \$c->{DISPLAY_DEPENDENCY_RESULT},
'ddrr|display_dependencies_regex=s',          'Node matching the regex are displayed.',                '', $c->{DISPLAY_DEPENDENCIES_REGEX},
'ddrrn|display_dependencies_regex_not=s',     'Node matching the regex are not displayed.',            '', $c->{DISPLAY_DEPENDENCIES_REGEX_NOT},
'ddrn|display_dependencies_rule_name=s',      'Node matching rules regex are displayed.',              '', $c->{DISPLAY_DEPENDENCIES_RULE_NAME},
'ddrnn|display_dependencies_rule_name_not=s', 'Node matching rules regex are not displayed.',          '', $c->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT},
'dnsr|display_node_subs_run',                 'Show when a node sub is run.',                          '', \$c->{DISPLAY_NODE_SUBS_RUN},
'trace_pbs_stack',                            '(DF) Display the call stack within pbs runs.',          '', \$c->{DEBUG_TRACE_PBS_STACK},
'ddrd|display_dependency_rule_definition',    'Display the definition of matching rules.',             '', \$c->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION},
'ddr|display_dependency_regex',               '(DF) Display the regex used to depend a node.',         '', \$c->{DEBUG_DISPLAY_DEPENDENCY_REGEX},
'ddmr|display_dependency_matching_rule',      'Display the rule which matched the node.',              '', \$c->{DISPLAY_DEPENDENCY_MATCHING_RULE},
'display_dependency_full_pbsfile',            'Don\'t shorten file paths.',                            '', \$c->{DISPLAY_DEPENDENCIES_FULL_PBSFILE},
'ddir|display_dependency_insertion_rule',     'Display the rule which added the node.',                '', \$c->{DISPLAY_DEPENDENCY_INSERTION_RULE},
'dlmr|display_link_matching_rule',            'Display the rule which matched the node being linked.', '', \$c->{DISPLAY_LINK_MATCHING_RULE},
'dl|depend_log',                              'Created a log for each subpbs.',                        '', \$c->{DEPEND_LOG},
'dlm|depend_log_merged',                      'Merge children subpbs output in log.',                  '', \$c->{DEPEND_LOG_MERGED},
'dfl|depend_full_log',                        'Created a log for each subpbs.',                        '', \$c->{DEPEND_FULL_LOG},
'dflo|depend_full_log_options=s',             'Set extra display options for full log.',               '', \$c->{DEPEND_FULL_LOG_OPTIONS},
'ddi|display_depend_indented',                'Add indentation before node.',                          '', \$c->{DISPLAY_DEPEND_INDENTED},
'dds|display_depend_separator=s',             'Display a separator between nodes.',                    '', \$c->{DISPLAY_DEPEND_SEPARATOR},
'ddnl|display_depend_new_line',               'Display an extra line after a depend.',                 '', \$c->{DISPLAY_DEPEND_NEW_LINE},
'dde|display_depend_end',                     'Display when a depend ends.',                           '', \$c->{DISPLAY_DEPEND_END},
'display_too_many_nodes_warning=i',           'Warn when a pbsfile adds too many nodes.',              '', \$c->{DISPLAY_TOO_MANY_NODE_WARNING},
}

sub WarpOptions
{
my ($c) = @_ ;

'dwfn|display_warp_file_name',          "Display the warp file name.",                '', \$c->{DISPLAY_WARP_FILE_NAME},
'display_warp_time',                    "Display warp creation time.",                '', \$c->{DISPLAY_WARP_TIME},
'w|warp=s',                             "specify which warp to use.",                 '', \$c->{WARP},
'warp_human_format',                    "Generate warp file in a readable format.",   '', \$c->{WARP_HUMAN_FORMAT},
'no_pre_build_warp',                    "no pre-build warp will be generated.",       '', \$c->{NO_PRE_BUILD_WARP},
'no_post_build_warp',                   "no post-build warp will be generated.",      '', \$c->{NO_POST_BUILD_WARP},
'display_warp_checked_nodes',           "Display nodes contained in the warp graph.", '', \$c->{DISPLAY_WARP_CHECKED_NODES},
'display_warp_checked_nodes_fail_only', "Display nodes with different hash.",         '', \$c->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY},
'display_warp_removed_nodes',           "Display nodes removed during warp.",         '', \$c->{DISPLAY_WARP_REMOVED_NODES},
'display_warp_triggered_nodes',         "Display nodes removed during warp and why.", '', \$c->{DISPLAY_WARP_TRIGGERED_NODES},
}

sub HttpOptions
{
my ($c) = @_ ;

'hdp|http_display_post',          'Display a message when a POST is send.',        '', \$c->{HTTP_DISPLAY_POST},
'hdput|http_display_put',         'Display a message when a PUT is send.',         '', \$c->{HTTP_DISPLAY_PUT},
'hdg|http_display_get',           'Display a message when a GET is send.',         '', \$c->{HTTP_DISPLAY_GET},
'hdss|http_display_server_start', 'Display a message when a server is started.',   '', \$c->{HTTP_DISPLAY_SERVER_START},
'hdssd|http_display_server_stop', 'Display a message when a server is sshutdown.', '', \$c->{HTTP_DISPLAY_SERVER_STOP},
'hdr|http_display_request',       'Display a message when a request is received.', '', \$c->{HTTP_DISPLAY_REQUEST},
'rde|resource_display_event',     'Display a message on resource events.',         '', \$c->{DISPLAY_RESOURCE_EVENT},
}

sub StatsOptions
{
my ($c) = @_ ;

'dpn|display_nodes_per_pbsfile',        'Display how many nodes where added by each pbsfile run.', '', \$c->{DISPLAY_NODES_PER_PBSFILE},
'dpnn|display_nodes_per_pbsfile_names', 'Display which nodes where added by each pbsfile run.',    '', \$c->{DISPLAY_NODES_PER_PBSFILE_NAMES},
'dpt|display_pbs_time',                 "Display where time is spend in PBS.",                     '', \$c->{DISPLAY_PBS_TIME},
'dmt|display_minimum_time=f',           "Display time if it is more than  value (default 0.5s).",  '', \$c->{DISPLAY_MINIMUM_TIME},
'dptt|display_pbs_total_time',          "Display How much time is spend in PBS.",                  '', \$c->{DISPLAY_PBS_TOTAL_TIME},
'dput|display_pbsuse_time',             "displays the time spend in 'PbsUse' for each pbsfile.",   '', \$c->{DISPLAY_PBSUSE_TIME},
'dputa|display_pbsuse_time_all',        "displays the time spend in each pbsuse.",                 '', \$c->{DISPLAY_PBSUSE_TIME_ALL},
'dpus|display_pbsuse_statistic',        "displays 'PbsUse' statistic.",                            '', \$c->{DISPLAY_PBSUSE_STATISTIC},
'display_md5_statistic',                "displays 'MD5' statistic.",                               '', \$c->{DISPLAY_MD5_STATISTICS},
'display_md5_time',                     "displays the time it takes to hash each node",            '', \$PBS::Digest::display_md5_time,
}

sub CheckOptions
{
my ($c) = @_ ;
$c->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX} //= [] ;

'cdabt|check_dependencies_at_build_time', 'Skips node build if dependencies rebuild identically.',     '', \$c->{CHECK_DEPENDENCIES_AT_BUILD_TIME},
'hsb|hide_skipped_builds',                'Hide builds skipped by -check_dependencies_at_build_time.', '', \$c->{HIDE_SKIPPED_BUILDS},
'check_only_terminal_nodes',              'Skips the checking of generated artefacts.',                '', \$c->{DEBUG_CHECK_ONLY_TERMINAL_NODES},
'nhnd|no_has_no_dependencies=s',          'No warning if node has no dependencies.',                   '', $c->{NO_DISPLAY_HAS_NO_DEPENDENCIES_REGEX},
}

sub BuildOptions
{
my ($c) = @_ ;
$c->{NODE_BUILD_ACTIONS} //= [] ;

'nba|node_build_actions=s',
	'actions that are run on a node at build time.',
	q~example: pbs -ke .  -nba '3::stop' -nba "trigger::priority 4::message '%name'" -trigger '.' -w 0  -fb -dpb0 -j 12 -nh~,
	$c->{NODE_BUILD_ACTIONS},
}

sub MatchOptions
{
my ($c) = @_ ;
$c->{DISPLAY_BUILD_INFO} //= [] ;

'display_no_dependencies_ok',
	'Display a message if a node was tagged has having no dependencies with HasNoDependencies.',
	
	"Non source files (nodes with digest) are checked for dependencies since they need to be build from something, "
	. "some nodes are generated from non files or don't always have dependencies as for C cache which dependency file "
	. "is created on the fly if it doens't exist.",
	
	\$c->{DISPLAY_NO_DEPENDENCIES_OK},

'nwwzd|no_warning_zero_dependencies', 'PBS won\'t warn if a node has no dependencies but a matching rule.',    '', \$c->{NO_WARNING_ZERO_DEPENDENCIES},
'dbsi|display_build_sequencer_info',  'Display information about which node is build.',                        '', \$c->{DISPLAY_BUILD_SEQUENCER_INFO},
'dbs|display_build_sequence',         '(DF) Dumps the build sequence data.',                                   '', \$c->{DEBUG_DISPLAY_BUILD_SEQUENCE},
'dbss|display_build_sequence_simple', '(DF) List the nodes to be build.',                                      '', \$c->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE},
'dbsss|display_build_sequence_stats', '(DF) display number of nodes to be build.',                             '', \$c->{DEBUG_DISPLAY_BUILD_SEQUENCE_STATS},
'save_build_sequence_simple=s',       'Save a list of nodes to be build to a file.',                           '', \$c->{SAVE_BUILD_SEQUENCE_SIMPLE},
'bi|build_info=s',                    'Set options: -b -d, ... ; a file or \'*\' can be specified. No Build.', '', $c->{DISPLAY_BUILD_INFO},
'nlmi|no_local_match_info',           'No warning message if a linked node matches local rules.',              '', \$c->{NO_LOCAL_MATCHING_RULES_INFO},
'display_duplicate_info',             'PBS will display which dependency are duplicated for a node.',          '', \$c->{DISPLAY_DUPLICATE_INFO},
'link_no_external',                   'Linking from other Pbsfile stops the build if a local rule matches.',   '', \$c->{NO_EXTERNAL_LINK},
'lni|link_no_info',                   'PBS won\'t display which nodes are linked.',                            '', \$c->{NO_LINK_INFO},
'lnli|link_no_local_info',            'PBS won\'t display linking to local nodes.',                            '', \$c->{NO_LOCAL_LINK_INFO},
}

sub PostBuildOptions
{
my ($c) = @_ ;

'dpbcr|display_post_build_registration', '(DF) Display post build commands registration.', '', \$c->{DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION},
'dpbcd|display_post_build_definition',   '(DF) Display post build commands definition.',   '', \$c->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION},
'dpbc|display_post_build_commands',      '(DF) Display which post build command is run.',  '', \$c->{DEBUG_DISPLAY_POST_BUILD_COMMANDS},
'dpbcre|display_post_build_result',      'Display post build commands result.',            '', \$c->{DISPLAY_POST_BUILD_RESULT},
}

sub TriggerOptions
{
my ($c) = @_ ;

'ntii|no_trigger_import_info',         'Don\'t display triggers imports.',           '', \$c->{NO_TRIGGER_IMPORT_INFO},
'dtin|display_trigger_inserted_nodes', '(DF) Display nodes inserted by a trigger.',  '', \$c->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES},
'dt|display_triggered',                '(DF) Display why files need to be rebuild.', '', \$c->{DEBUG_DISPLAY_TRIGGERED_DEPENDENCIES},
}

sub EnvOptions
{
my ($c) = @_ ;
$c->{COMMAND_LINE_DEFINITIONS} //= {} ;
$c->{KEEP_ENVIRONMENT}         //= [] ;
$c->{USER_OPTIONS}             //= {} ;
$c->{VERBOSITY}                //= [] ;

'ek|keep_environment=s',            "%ENV isemptied, --ke 'regex' keeps matching variables.", '', $c->{KEEP_ENVIRONMENT},
'ed|display_environment',           "Display which environment variables are kept",           '', \$c->{DISPLAY_ENVIRONMENT},
'edk|display_environment_kept',     "Only display the evironment variables kept",             '', \$c->{DISPLAY_ENVIRONMENT_KEPT},
'es|display_environment_statistic', "Display a statistics about environment variables",       '', \$c->{DISPLAY_ENVIRONMENT_STAT},
'u|user_option=s',                  'options to be passed to the Build sub.',                 '', $c->{USER_OPTIONS},
'D=s',                              'Command line definitions.',                              '', $c->{COMMAND_LINE_DEFINITIONS},

'verbosity=s',
	'Used in user defined modules.',
	 <<EOT, $c->{VERBOSITY},
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

}

sub DigestOptions
{
my ($c) = @_ ;

'digest_exclusion',         'Display node exclusion or inclusion.',                 '', \$c->{DISPLAY_DIGEST_EXCLUSION},
'digest',                   'Display expected and actual digest.',                  '', \$c->{DISPLAY_DIGEST},
'ddd|digest_different',     'Only display when a digest are diffrent.',             '', \$c->{DISPLAY_DIFFERENT_DIGEST_ONLY},
'dmw|digest_warp_warnings', 'Warng if the file to compute hash for does\'t exist.', '', \$c->{WARP_DISPLAY_DIGEST_FILE_NOT_FOUND},
'dfc|digest_file_check',    'Display hash checking for individual files.',          '', \$c->{DISPLAY_FILE_CHECK},
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
