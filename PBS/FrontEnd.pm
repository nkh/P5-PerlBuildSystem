
package PBS::FrontEnd ;

use v5.10 ;
use strict ;
use warnings ;

#use Data::Dumper ;
use Data::TreeDumper ;
#use Carp ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use Module::Util qw(find_installed) ;
use File::Spec::Functions qw(:ALL) ;
use File::Slurp ;
use File::HomeDir;
use List::Util qw(uniq) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.49' ;

#use PBS::Debug ;
use PBS::Config ;
use PBS::Config::Subpbs ;
use PBS::PBSConfig ;
use PBS::PBS ;
use PBS::Log::Full ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Documentation ;
use PBS::Plugin ;
use PBS::Warp ;

#-------------------------------------------------------------------------------

sub Pbs
{
my $t0 = [gettimeofday];
my (%pbs_arguments) = @_ ;

if(($pbs_arguments{COMMAND_LINE_ARGUMENTS}[0] // '')  eq '--options_get_completion')
	{
	my ($options, $pbs_config) = PBS::PBSConfigSwitches::GetOptions() ;

	ParseSwitchesAndLoadPlugins($options, $pbs_config, []) ; #load plugins options
	
	($options, $pbs_config) = PBS::PBSConfigSwitches::GetOptions($pbs_config) ; # add new options
	PBS::PBSConfigSwitches::GetCompletion($options) ;

	return 1 ;
	}

PBS::PBSConfigSwitches::AliasOptions($pbs_arguments{COMMAND_LINE_ARGUMENTS}) ;

my ($options, $pbs_config) = PBS::PBSConfigSwitches::GetOptions() ;
PBS::PBSConfig::RegisterPbsConfig('PBS', $pbs_config, $options) ;

$pbs_config->{ORIGINAL_ARGV} = join(' ', @ARGV) ;

# two phase parsing of subpbs options to allow for plugin options loading
my ($unchecked_subpbs_options, $command_line_arguments) = PBS::Config::Subpbs::RemoveSubpbsOptions($pbs_arguments{COMMAND_LINE_ARGUMENTS}) ;

my ($switch_parse_ok, $parse_message) = ParseSwitchesAndLoadPlugins($options, $pbs_config, $command_line_arguments) ;

# two phase parsing of subpbs options to allow for plugin options loading
my ($switch_parse_ok_subpbs_options, $parse_message_subpbs_options, $subpbs_options)
	= PBS::Config::Subpbs::ParseSubpbsOptions($unchecked_subpbs_options, $command_line_arguments, PARSE_SWITCHES_IGNORE_ERROR) ;

# update the options list
($options, $pbs_config) = PBS::PBSConfigSwitches::GetOptions($pbs_config) ;
PBS::PBSConfig::ParseSwitches($options, $pbs_config, $command_line_arguments) ;

$pbs_config->{PBS_QR_OPTIONS} = $subpbs_options ;

for ( uniq @{$pbs_config->{BREAKPOINTS}} ) { EnableDebugger($pbs_config, $_) }
  
if($pbs_config->{DISPLAY_LIB_PATH})
	{
	print 'PBS: lib paths:' . join(':', @{$pbs_config->{LIB_PATH}}) . "\n" ;
	return(1) ;
	}

if($pbs_config->{DISPLAY_PLUGIN_PATH})
	{
	print 'PBS: plugin paths: ' . join(':', @{$pbs_config->{PLUGIN_PATH}}) . "\n" ;
	return(1) ;
	}

if($pbs_config->{GET_OPTIONS_LIST})
	{
	PBS::PBSConfigSwitches::GetOptionsList() ;
	return(1) ;
	}

if($pbs_config->{GENERATE_BASH_COMPLETION_SCRIPT})
	{
	PBS::PBSConfigSwitches::GenerateBashCompletionScript() ;
	return(1) ;
	}

if($pbs_config->{DEBUG_CHECK_ONLY_TERMINAL_NODES})
	{
	PrintWarning "PBS: warning --check_only_terminal_nodes is set.\n" ;
	}

# override with callers pbs_config
if(exists $pbs_arguments{PBS_CONFIG})
	{
	$pbs_config = {%$pbs_config, %{$pbs_arguments{PBS_CONFIG}} } ;
	}

$pbs_config->{PBSFILE_CONTENT} = $pbs_arguments{PBSFILE_CONTENT} if exists $pbs_arguments{PBSFILE_CONTENT} ;

my $display_help              = $pbs_config->{DISPLAY_HELP} ;
my $display_switch_help       = $pbs_config->{DISPLAY_SWITCH_HELP} ;
my $display_help_narrow       = $pbs_config->{DISPLAY_HELP_NARROW_DISPLAY} || 0 ;
my $display_version           = $pbs_config->{DISPLAY_VERSION} ;
my $display_pod_documentation = $pbs_config->{DISPLAY_POD_DOCUMENTATION} ;

if($display_help || $display_switch_help || $display_version || defined $display_pod_documentation)
	{
	PBS::PBSConfigSwitches::DisplayHelp($display_help_narrow) if $display_help ;
	PBS::PBSConfigSwitches::DisplaySwitchHelp($display_switch_help) if $display_switch_help ;
	DisplayVersion() if $display_version ;
	
	PBS::Documentation::DisplayPodDocumentation($pbs_config, $display_pod_documentation) if defined $display_pod_documentation ;
	
	return(1) ;
	}
	
if(defined $pbs_config->{WIZARD})
	{
	eval "use PBS::Wizard;" ;
	die $@ if $@ ;

	PBS::Wizard::RunWizard
		(
		$pbs_config->{LIB_PATH},
		undef,
		$pbs_config->{WIZARD},
		$pbs_config->{DISPLAY_WIZARD_INFO},
		$pbs_config->{DISPLAY_WIZARD_HELP},
		) ;
		
	return(1) ;
	}

my $display_user_help        = $pbs_config->{DISPLAY_PBSFILE_POD} ;
my $extract_pod_from_pbsfile = $pbs_config->{PBS2POD} ;

if($display_user_help || $extract_pod_from_pbsfile)
	{
	my ($pbsfile, $error_message) = PBS::PBSConfig::GetPbsfileName($pbs_config) ;
	PrintError $error_message unless defined $pbsfile && $pbsfile ne '' ;
	
	PBS::PBSConfigSwitches::DisplayUserHelp($pbsfile, $display_user_help, $pbs_config->{RAW_POD}) ;
	return(1) ;
	}

#-------------------------------------------------------------------------------------------
# run PBS rule engine
#-------------------------------------------------------------------------------------------

# verify config first
my ($pbs_config_ok, $pbs_config_message) = PBS::PBSConfig::CheckPbsConfig($pbs_config) ;
return(0, $pbs_config_message) unless $pbs_config_ok ;

# compute distribution digest
PBS::Digest::GetPbsDigest($pbs_config) ;

unless($switch_parse_ok && $switch_parse_ok_subpbs_options)
	{
	# deferred to get a chance to display PBS help
	return(0, $parse_message . ' ' . $parse_message_subpbs_options);
	}
	
GenerateDependFullLog($pbs_config, $pbs_arguments{COMMAND_LINE_ARGUMENTS}) if $pbs_config->{DEPEND_FULL_LOG} ;

my $targets = $pbs_config->{TARGETS} ;

unless(@$targets)
	{
	# try to get them from the pbsfile
	my $load_package = 'PBS_GET_TARGET_AND_OPTIONS_FROM_PBSFILE' ;

	my $targets_pbs_config = PBS::PBSConfig::RegisterPbsConfig
				(
				$load_package,
				{
					PBSFILE => $pbs_config->{PBSFILE},
					TARGET_PATH => '',
					SHORT_DEPENDENCY_PATH_STRING => $pbs_config->{SHORT_DEPENDENCY_PATH_STRING} // '…',
					LIB_PATH => $pbs_config->{LIB_PATH},
					PLUGIN_PATH => $pbs_config->{PLUGIN_PATH},
					CONFIG_NAMESPACES => ['BuiltIn', 'User'],
				},
				) ;
	eval 
		{
		PBS::PBS::LoadFileInPackage
			(
			'', # $type
			$pbs_config->{PBSFILE},
			$load_package,
			$targets_pbs_config,
			"use strict ;\n"
			  . "use warnings ;\n"
			  . "use PBS::Output ;\n"
			  . "use Data::TreeDumper;\n"
			  . "use PBS::Prf ;\n" # target and pbs options functions
			  . "use PBS::Constants ;\n"
			  . "use PBS::Rules ;\n"
			  . "use PBS::Rules::Scope ;\n"
			  . "use PBS::Triggers ;\n"
			  . "use PBS::PostBuild ;\n"
			  . "use PBS::Config ;\n"
			  . "use PBS::PBSConfig ;\n"
			  . "use PBS::PBS ;\n"
			  . "use PBS::Digest;\n",
			'1 ;', #$post_code
			) ;

		die "$@\n" if $@ ;
		
		$targets = [ uniq @{$targets_pbs_config->{TARGETS} // []} ] ;
		
		for (sort keys %$targets_pbs_config)
			{
			$pbs_config->{$_} = $targets_pbs_config->{$_} if defined $targets_pbs_config->{$_} ;
			}

		# CheckPbsConfig would override this on second run
		local $pbs_config->{DISPLAY_DEPENDENCIES_REGEX} = [];

		PBS::PBSConfig::CheckPbsConfig($pbs_config) ;
		} ;
	}

$targets =
	[
	uniq map
		{
		my $target = $_ ;
		
		if($target =~ /^\@/ || $target =~ /\@$/ || $target =~ /\@/ > 1)
			{
			die ERROR "PBS: invalid composite target definition\n" ;
			}

		if($target =~ /@/)
			{
			die ERROR "PBS: only one composite target allowed\n" if @$targets > 1 ;
			}

		$target = $_ if file_name_is_absolute($_) ; # full path
		$target = $_ if /^.\// ; # current dir (that's the build dir)
		$target = "./$_" unless /^[.\/]/ ;
		
		$target ;
		} @$targets
	] ;

$pbs_config->{PACKAGE} = "PBS" ; # should be unique
$pbs_config->{TARGET_PATH} = '' ;

# make the variables below accessible from a post pbs script
my $build_success = 1 ;
my ($buil_success, $build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence)
	 = (BUILD_FAILED, 'no_message', {}, {}, '', {}) ;

my $parent_config = $pbs_config->{LOADED_CONFIG} || {} ;

if(@$targets)
	{
	PBS::Debug::setup_debugger_run($pbs_config) ;
	$DB::single = 1 ;

	my $StartPbs = $pbs_config->{PBS_JOBS} ? \&PBS::Net::StartPbsServer : \&StartPbs ;

	($build_success, $build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) =
			$StartPbs->($targets, $pbs_config, $parent_config) ;
	
	my $total_time_in_pbs = tv_interval ($t0, [gettimeofday]) ;
	
	# move all stat into the nodes as they are build in different process
	# the stat displaying would need to traverse the tree, after synchronizing from the build processes

	if($pbs_config->{DISPLAY_NODES_PER_PBSFILE} ||$pbs_config->{DISPLAY_NODES_PER_PBSFILE_NAMES})
		{
		my $nodes_per_pbsfile = PBS::Depend::GetNodesPerPbsRun() ;
		if($pbs_config->{DISPLAY_NODES_PER_PBSFILE_NAMES})
			{
			PrintInfo "PBS: nodes added per pbsfile run:\n"
					 . DumpTree
						(
						$nodes_per_pbsfile, '',
						DISPLAY_ADDRESS => 0,
						INDENTATION => $PBS::Output::indentation x 2,
						ELEMENT => 'node',
						) ;
			}
		else
			{
			PrintInfo "PBS: nodes added per pbsfile run:\n"
					 . DumpTree
						(
						$nodes_per_pbsfile, '',
						DISPLAY_ADDRESS => 0,
						INDENTATION => $PBS::Output::indentation x 2,
						ELEMENT => 'node',
						DISPLAY_NUMBER_OF_ELEMENTS_OVER_MAX_DEPTH => 1,
						MAX_DEPTH => 1
						) ;
			}
		}

	if($pbs_config->{DISPLAY_MD5_STATISTICS})
		{
		my $md5_statistics = PBS::Digest::Get_MD5_Statistics() ;

		PrintInfo "Digest: hash requests: $md5_statistics->{TOTAL_MD5_REQUESTS}"
			. ", non cached: $md5_statistics->{NON_CACHED_REQUESTS} " 
			. ", cache hits: $md5_statistics->{CACHE_HITS} ($md5_statistics->{MD5_CACHE_HIT_RATIO}%), time: $md5_statistics->{MD5_TIME}\n" ;
			
		$PBS::pbs_run_information->{MD5_STATISTICS} = $md5_statistics ;
		}

	RunPluginSubs($pbs_config, 'PostPbs', $build_success, $pbs_config, $dependency_tree, $inserted_nodes) ;

	my $run = 0 ;
	for my $post_pbs (@{$pbs_config->{POST_PBS}})
		{
		$run++ ;
		
		our $x_build_success = $build_success ;
		our $x_dependency_tree = $dependency_tree ;
		our $inserted_nodes = $inserted_nodes ;
		
		eval
			{
			PBS::PBS::LoadFileInPackage
				(
				'',
				$post_pbs,
				"PBS::POST_PBS_$run",
				$pbs_config,
				"use strict ;\nuse warnings ;\n"
				  . "use PBS::Output ;\n"
				  . "my \$pbs_config = \$pbs_config ;\n"
				  . "my \$build_success = \$PBS::FrontEnd::x_build_success ;\n"
				  . "my \$dependency_tree = \$PBS::FrontEnd::x_dependency_tree ;\n"
				  . "my \$inserted_nodes = \$PBS::FrontEnd::x_inserted_nodes ; \n"
				  . "my \$pbs_run_information = \$PBS::pbs_run_information ; \n",
				) ;
			} ;
		
		PrintError("PBS: couldn't run post pbs script '$post_pbs':\n   $@") if $@ ;
		}
	
	if ($total_time_in_pbs > $pbs_config->{DISPLAY_MINIMUM_TIME})
		{
		$PBS::pbs_run_information->{TOTAL_TIME_IN_PBS} = $total_time_in_pbs ;
		PrintInfo(sprintf("PBS: time: %0.2f s.\n", $total_time_in_pbs)) if ($pbs_config->{DISPLAY_PBS_TOTAL_TIME} && ! $pbs_config->{QUIET}) ;
		}
	
	}
else
	{
	PrintError("PBS: no targets to build\n") ;
	PBS::PBSConfigSwitches::DisplayUserHelp($pbs_config->{PBSFILE}, 1, 0) ;
		
	$build_success = 0 ;
	}

my $short_pbsfile = GetRunRelativePath($pbs_config, $pbs_config->{PBSFILE}) ;

return($build_success, "PBS: targets: [@$targets], pbsfile: $short_pbsfile\n", $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;
}

sub StartPbs
{
my ($targets, $pbs_config, $parent_config) = @_ ;

my ($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;

eval
	{
	($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence)
		= PBS::Warp::WarpPbs($targets, $pbs_config, $parent_config) ;
	
	# parallel pbs start nodes are tagged and trigger
	# the target nodes go through StartPbs, and warp checking, instead for Subpbs
	# tag them the same way 
 	if($pbs_config->{PBS_JOBS})
		{
 		for ($targets->@*)
			{
			$inserted_nodes->{$_}{__PARALLEL_DEPEND}++ ;
			push $inserted_nodes->{$_}{__TRIGGERED}->@*, {NAME => '__SELF', REASON => '__PARALLEL_DEPEND'} ;
			}
		}
	} ;
	
print STDERR $@ if $@ ;
	
$build_result = BUILD_FAILED unless defined $build_result;

my $build_success = (! $@) && $build_result == BUILD_SUCCESS ;

$build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence
}

#-------------------------------------------------------------------------------

sub ParseSwitchesAndLoadPlugins
{
# This is a bit hairy since plugins might add switches that are accepted on the command line and in a prf and
# the plugin path can be defined on the command line and in a prf!
# We load the pbs config twice. Once to handle the paths and the switches pertinent to plugin loading
# and once to "really" load the config. We also loade the global config pbs.prf

my ($options, $pbs_config, $command_line_arguments) = @_ ;
my $parse_message = '' ;

# get the PBS_PLUGIN_PATH and PBS_LIB_PATH from the command line or the prf
# handle -plp and -ppp on the command line (get a separate config)

my ($command_line_switch_parse_ok, $command_line_parse_message, $command_line_config)
	= PBS::PBSConfig::ParseSwitches(undef, undef, $command_line_arguments, PARSE_SWITCHES_IGNORE_ERROR) ;

$pbs_config->{PLUGIN_PATH}              = $command_line_config->{PLUGIN_PATH} if @{$command_line_config->{PLUGIN_PATH}} ;
$pbs_config->{DISPLAY_PLUGIN_RUNS}      = $command_line_config->{DISPLAY_PLUGIN_RUNS};
$pbs_config->{DISPLAY_PLUGIN_LOAD_INFO} = $command_line_config->{DISPLAY_PLUGIN_LOAD_INFO} ;
$pbs_config->{NO_DEFAULT_PATH_WARNING}  = $command_line_config->{NO_DEFAULT_PATH_WARNING} ;
$pbs_config->{LIB_PATH}                 = $command_line_config->{LIB_PATH} if @{$command_line_config->{LIB_PATH}} ;

$pbs_config->{DISPLAY_PBS_CONFIGURATION_LOCATION} = $command_line_config->{DISPLAY_PBS_CONFIGURATION_LOCATION} ;

#  handle -plp && -ppp in a prf
unless(defined $command_line_config->{NO_PBS_RESPONSE_FILE})
	{
	if(defined $command_line_config->{PBS_RESPONSE_FILE})
		{
		my ($pbs_response_file, $prf_config) 
			= PBS::PBSConfig::ParsePrfSwitches
				(
				$command_line_config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
				$command_line_config->{PBS_RESPONSE_FILE},
				PARSE_PRF_SWITCHES_IGNORE_ERROR,
				) ;
				
		push @{$pbs_config->{PLUGIN_PATH}},       @{$prf_config->{PLUGIN_PATH}} unless (@{$pbs_config->{PLUGIN_PATH}}) ;
		$pbs_config->{DISPLAY_PLUGIN_RUNS}++      if $prf_config->{DISPLAY_PLUGIN_RUNS};
		$pbs_config->{DISPLAY_PLUGIN_LOAD_INFO}++ if $prf_config->{DISPLAY_PLUGIN_LOAD_INFO} ;
		$pbs_config->{NO_DEFAULT_PATH_WARNING}++  if $prf_config->{NO_DEFAULT_PATH_WARNING} ;
		
		push @{$pbs_config->{LIB_PATH}},          @{$prf_config->{LIB_PATH}} unless (@{$pbs_config->{LIB_PATH}}) ;
		}

	my $dist_data = File::HomeDir->my_dist_data( 'PBS' ) ;
	my $pbs_response_file = File::HomeDir->my_dist_data( 'PBS') . "/pbs.prf" ;

	if(-e $dist_data && -e $pbs_response_file)
		{
		($pbs_response_file, my $prf_config) 
			= PBS::PBSConfig::ParsePrfSwitches
				(
				$command_line_config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
				$pbs_response_file,
				PARSE_PRF_SWITCHES_IGNORE_ERROR,
				) ;
				
		push @{$pbs_config->{PLUGIN_PATH}},       @{$prf_config->{PLUGIN_PATH}} unless (@{$pbs_config->{PLUGIN_PATH}}) ;
		$pbs_config->{DISPLAY_PLUGIN_RUNS}++      if $prf_config->{DISPLAY_PLUGIN_RUNS};
		$pbs_config->{DISPLAY_PLUGIN_LOAD_INFO}++ if $prf_config->{DISPLAY_PLUGIN_LOAD_INFO} ;
		$pbs_config->{NO_DEFAULT_PATH_WARNING}++  if $prf_config->{NO_DEFAULT_PATH_WARNING} ;
		
		push @{$pbs_config->{LIB_PATH}},          @{$prf_config->{LIB_PATH}} unless (@{$pbs_config->{LIB_PATH}}) ;
		}
	else
		{
		PrintInfo "PBS: creating empty default config '$pbs_response_file'\n" ; 
		write_file $pbs_response_file, "# pbs default config\n#pbsconfig qw/ --dd -j 12 / ;\n\n1 ;\n"
		}
	}
# nothing defined on the command line and in a prf, last resort, use the distribution files
my $plugin_path_is_default ;

my ($basename, $path, $ext) = File::Basename::fileparse(find_installed('PBS::PBS'), ('\..*')) ;
my $distribution_plugin_path = $path . 'Plugins' ;
	
if(!exists $pbs_config->{PLUGIN_PATH} || ! @{$pbs_config->{PLUGIN_PATH}})
	{
	if(-e $distribution_plugin_path)
		{
		$pbs_config->{PLUGIN_PATH} = [$distribution_plugin_path] ;
		$plugin_path_is_default++ ;
		}
	else
		{
		die ERROR "PBS: no plugin path set and couldn't found any in the distribution, see --ppp.\n" ;
		}
	}
else
	{
	push @{$pbs_config->{PLUGIN_PATH}}, $distribution_plugin_path ;

	$parse_message .= "PBS: using plugins from: " . (join ', ', @{$pbs_config->{PLUGIN_PATH}}) . "\n" ;
	}

my $lib_path_is_default ;
my $distribution_library_path = $path . 'PBSLib/' ;

if(!exists $pbs_config->{LIB_PATH} || ! @{$pbs_config->{LIB_PATH}})
	{
	if(-e $distribution_library_path )
		{
		$pbs_config->{LIB_PATH} = [$distribution_library_path] ;
		$lib_path_is_default++ ;
		}
	else
		{
		die ERROR "PBS: no library path set and couldn't found any in the distribution, see --plp.\n" ;
		}
	}
else
	{
	push @{$pbs_config->{LIB_PATH}}, $distribution_library_path ;

	$parse_message .= "PBS: using libs from: " . (join ', ', @{$pbs_config->{LIB_PATH}}) . "\n" ;
	}
	
# load the plugins
PBS::Plugin::ScanForPlugins($pbs_config, $pbs_config->{PLUGIN_PATH}) ; # plugins might add switches

($options, $pbs_config) = PBS::PBSConfigSwitches::GetOptions($pbs_config) ; # add new options

# reparse the command line switches merging to PBS config
$pbs_config->{PLUGIN_PATH} = [] unless $plugin_path_is_default ;
$pbs_config->{LIB_PATH} = [] unless $lib_path_is_default ;

my ($switch_parse_ok, $parse_switches_message) = PBS::PBSConfig::ParseSwitches($options, $pbs_config, $command_line_arguments, PARSE_SWITCHES_IGNORE_ERROR) ;
$parse_message .= $parse_switches_message ;
# testing of parse result is handled by caller
# reparse the prf 
unless(defined $pbs_config->{NO_PBS_RESPONSE_FILE})
	{
	my ($pbs_response_file, $prf_config) 
		= PBS::PBSConfig::ParsePrfSwitches
			(
			$pbs_config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
			$pbs_config->{PBS_RESPONSE_FILE},
			0,
			$pbs_config->{DISPLAY_PBS_CONFIGURATION_LOCATION},
			) ;
			
	#merging to PBS config, CLI has higher priority
	for my $key (keys %$prf_config)
		{
		if('ARRAY' eq ref $prf_config->{$key})
			{
			if(! exists $pbs_config->{$key} || 0 == @{$pbs_config->{$key}})
				{
				$pbs_config->{$key} = $prf_config->{$key}
				}
			}
		elsif('HASH' eq ref $prf_config->{$key})
			{
			# commandline definitions and user definitions
			if(! exists $pbs_config->{$key} || 0 == keys(%{$pbs_config->{$key}}))
				{
				$pbs_config->{$key} = $prf_config->{$key}
				}
			}
		else
			{
			if(! exists $pbs_config->{$key} || ! defined $pbs_config->{$key})
				{
				$pbs_config->{$key} = $prf_config->{$key}
				}
			}
		}

	$pbs_response_file = File::HomeDir->my_dist_data('PBS') . "/pbs.prf" ;

	($pbs_response_file, $prf_config) 
		= PBS::PBSConfig::ParsePrfSwitches
			(
			$command_line_config->{NO_ANONYMOUS_PBS_RESPONSE_FILE},
			$pbs_response_file,
			0,
			$pbs_config->{DISPLAY_PBS_CONFIGURATION_LOCATION},
			) ;

	# merging to PBS config, 
	for my $key (keys %$prf_config)
		{
		if('ARRAY' eq ref $prf_config->{$key})
			{
			if(! exists $pbs_config->{$key} || 0 == @{$pbs_config->{$key}})
				{
				$pbs_config->{$key} = $prf_config->{$key}
				}
			}
		elsif('HASH' eq ref $prf_config->{$key})
			{
			if(! exists $pbs_config->{$key} || 0 == keys(%{$pbs_config->{$key}}))
				{
				$pbs_config->{$key} = $prf_config->{$key}
				}
			}
		else
			{
			if(! exists $pbs_config->{$key} || ! defined $pbs_config->{$key})
				{
				$pbs_config->{$key} = $prf_config->{$key}
				}
			}
		}
	}

return($switch_parse_ok, $parse_message) ;
}

#-------------------------------------------------------------------------------

sub DisplayVersion
{

use PBS::Version ;
my $version = PBS::Version::GetVersion() ;

print <<EOH ;

PBS version $version

Copyright 2002-2021, Nadim Khemir

Send suggestions and inqueries to <nadim.khemir\@gmail.com>.

EOH
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::FrontEnd  -

=head1 SYNOPSIS

  use PBS::FrontEnd ;
  PBS::FrontEnd::Pbs(@ARGV) ;

=head1 DESCRIPTION

Entry point into B<PBS>.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut

