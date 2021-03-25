
package PBS::PBSConfig ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use File::Spec::Functions qw(:ALL) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GetPbsConfig GetBuildDirectory GetSourceDirectories CollapsePath PARSE_SWITCHES_IGNORE_ERROR PARSE_PRF_SWITCHES_IGNORE_ERROR) ;
our $VERSION = '0.03' ;

use Getopt::Long ;
use Pod::Parser ;
use Cwd ;
use File::Spec;
use File::Slurp ;

use PBS::Output ;
use PBS::Log ;
use PBS::Constants ;
use PBS::Plugin ;
use PBS::PBSConfigSwitches ;

#-------------------------------------------------------------------------------

my %pbs_configuration ;
my %pbs_configuration_options ;

sub RegisterPbsConfig
{
my ($package, $configuration, $options) = @_ ;

$configuration //= (PBS::PBSConfigSwitches::GetOptions())[1] ;

if(ref $configuration eq 'HASH')
	{
	$pbs_configuration{$package} = $configuration;
	}
else
	{
	PrintError("Config: RegisterPbsConfig: switches must be a hash reference.\n") ;
	}

$pbs_configuration_options{$package} = $options if defined $options;

$configuration
}

#-------------------------------------------------------------------------------

sub GetPbsConfig
{
my $package  = shift || caller() ;

if(defined $pbs_configuration{$package})
	{
	return $pbs_configuration{$package} ;
	}
else
	{
	#use Carp ;
	#Say Debug Carp::longmess ;
	Say Error "Config: GetPbsConfig: no configuration for package '$package'. Returning empty set." ;

	return {} ;
	}
}

sub GetPbsConfigAndOptions
{
my $package  = shift || caller() ;

if(defined $pbs_configuration{$package})
	{
	return $pbs_configuration{$package}, $pbs_configuration_options{$package} ;
	}
else
	{
	Say Error "Config: GetPbsConfig: no configuration for package '$package'. Returning empty set." ;

	Carp::confess ;
	return {} ;
	}
}

#-------------------------------------------------------------------------------

sub GetBuildDirectory
{
my $package  = shift || caller() ;

if(defined $pbs_configuration{$package})
	{
	return($pbs_configuration{$package}{BUILD_DIRECTORY}) ;
	}
else
	{
	PrintError("Config: GetBuildDirectory: no configuration for package '$package'. Returning empty string.\n") ;
	Carp::confess ;
	return('') ;
	}
}

#-------------------------------------------------------------------------------

sub GetSourceDirectories
{
my $package  = shift || caller() ;

if(defined $pbs_configuration{$package})
	{
	return([@{$pbs_configuration{$package}{SOURCE_DIRECTORIES}}]) ;
}
else
	{
	PrintError("Config: GetSourceDirectories: no configuration for package '$package'. Returning empty list.\n") ;
	Carp::confess ;
	return([]) ;
	}
}

#-------------------------------------------------------------------------------

use constant PARSE_SWITCHES_IGNORE_ERROR => 1 ;

sub ParseSwitches
{
my ($user_options, $user_config, $switches_to_parse, $ignore_error) = @_ ;

my ($options, $config) = defined $user_options
				? ($user_options, $user_config)
				: (PBS::PBSConfigSwitches::GetOptions()) ;

local @ARGV = @$switches_to_parse ;

local $SIG{__WARN__} 
	= sub 
		{
		Print Warning $_[0] unless $ignore_error ;
		} ;

my @flags = PBS::PBSConfigSwitches::Get_GetoptLong_Data($options) ;

my @targets ; # parse mixed switches and targets

Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case', 'require_order', 'permute', 'pass_through') ;

my $parse_errors = 0 ;
my $catchall =
	sub 
	{
	#Say Info2 "Pbs: option '$_[0]'" ;
	if($ignore_error)
		{
		#Say Warning "Pbs: invalid option '$_[0]' ignoring ..." if $_[0] =~ /^-/ ;
		}
	else
		{
		Say Error "Pbs: invalid option '$_[0]'" if $_[0] =~ /^-/ ;

		$parse_errors++ if $_[0] =~ /^-/ ;

		push @targets, $_[0] if $_[0] !~ /^-/ ;
		}
	} ;

do
	{
	push @targets, shift @ARGV while @ARGV && $ARGV[0] !~ /^-/ ;
	
	unless(GetOptions(@flags, '<>' => $catchall))
		{
		return 0, "PBS: Try perl pbs.pl -h.\n", $config, @ARGV
			unless $ignore_error;
		}
	}
while(@ARGV) ;

my %cc = RunUniquePluginSub({}, 'GetColorDefinitions') ;

PBS::Output::SetDefaultColors(\%cc) ;

push @{$config->{TARGETS}}, @targets ;

die "\n" if $parse_errors ;
 
return 1, '', $config ;
}

#-------------------------------------------------------------------------------

sub GetUserName
{
my $user = 'no_user_set' ;

if(defined $ENV{USER} && $ENV{USER} ne '')
	{
	$user = $ENV{USER} ;
	}
elsif(defined $ENV{USERNAME} && $ENV{USERNAME} ne '')
	{
	$user = $ENV{USERNAME} ;
	}
	
return $user ;
}

#-------------------------------------------------------------------------------

sub CheckPbsConfig
{
my $pbs_config = shift ;

my $success_message = '' ;

$pbs_config->{DISPLAY_ENVIRONMENT}++ if $pbs_config->{DISPLAY_ENVIRONMENT_KEPT} ;

#force options
$pbs_config->{DISPLAY_PROGRESS_BAR}++ ;
$pbs_config->{DISPLAY_PROGRESS_BAR}++ if $pbs_config->{DISPLAY_PROGRESS_BAR_FILE} ;
$pbs_config->{DISPLAY_PROGRESS_BAR}++ if $pbs_config->{DISPLAY_PROGRESS_BAR_PROCESS} ;

# check the options

$pbs_config->{DISPLAY_TOO_MANY_NODE_WARNING} //= 250 ;

if($pbs_config->{DEPEND_FULL_LOG})
	{
	undef $pbs_config->{DEPEND_LOG} ;
	}

if($pbs_config->{DISPLAY_PROGRESS_BAR})
	{
	$PBS::Shell::silent_commands++ ;
	$PBS::Shell::silent_commands_output++ ;
	$pbs_config->{DISPLAY_NO_BUILD_HEADER}++ ;
	}

if($pbs_config->{DISPLAY_NO_PROGRESS_BAR} || $pbs_config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM} || $pbs_config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2})
	{
	$pbs_config->{DISPLAY_NO_PROGRESS_BAR}++ ;
	undef $pbs_config->{DISPLAY_PROGRESS_BAR} ;
	}
	
if($pbs_config->{QUIET})
	{
	$PBS::Shell::silent_commands++ ;
	$PBS::Shell::silent_commands_output++ ;
	$pbs_config->{DISPLAY_NO_BUILD_HEADER}++ ;
	$pbs_config->{DISPLAY_PROGRESS_BAR} = 0 ;
	}

$pbs_config->{DISPLAY_BUILD_RESULT}++ if $pbs_config->{BUILD_DISPLAY_RESULT} ;

$pbs_config->{WARP} = 1.5 unless defined $pbs_config->{WARP} ;

for my $actions (grep { '' eq ref $_ } @{$pbs_config->{NODE_BUILD_ACTIONS}})
	{
	$actions = [ map { s/^\s+// ; s/\s+$// ; $_ } split /::/, $actions ] ;
	}

$pbs_config->{CHECK_JOBS} //= 4 ;
$pbs_config->{CHECK_JOBS} = 4 if $pbs_config->{CHECK_JOBS} < 0 ;

$pbs_config->{DISPLAY_WARP_CHECKED_NODES}++ if $pbs_config->{DISPLAY_WARP_CHECKED_NODES_FAIL_ONLY} ;

$pbs_config->{DISPLAY_MINIMUM_TIME} //= 0.5 ;

if($pbs_config->{DISPLAY_PBS_TIME})
	{
	$pbs_config->{DISPLAY_PBS_TOTAL_TIME}++ ;
	$pbs_config->{DISPLAY_TOTAL_BUILD_TIME}++ ;
	$pbs_config->{DISPLAY_TOTAL_DEPENDENCY_TIME}++ ;
	$pbs_config->{DISPLAY_CHECK_TIME}++ ;
	$pbs_config->{DISPLAY_WARP_TIME}++ ;
	}

if($pbs_config->{DISPLAY_DEPENDENCY_TIME})
	{
	$pbs_config->{DISPLAY_TOTAL_DEPENDENCY_TIME}++ ;
	}

if($pbs_config->{TIME_BUILDERS})
	{
	$pbs_config->{DISPLAY_TOTAL_BUILD_TIME}++ ;
	}

$pbs_config->{DISPLAY_PBSUSE_TIME}++ if $pbs_config->{DISPLAY_PBSUSE_TIME_ALL} ;

$pbs_config->{DISPLAY_HELP}++ if $pbs_config->{DISPLAY_HELP_NARROW_DISPLAY} ;

$pbs_config->{DEBUG_DISPLAY_RULES}++ if $pbs_config->{DEBUG_DISPLAY_RULE_DEFINITION} ;

$pbs_config->{DISPLAY_USED_RULES}++ if $pbs_config->{DISPLAY_USED_RULES_NAME_ONLY} ;

$pbs_config->{DISPLAY_RULES_ORDER}++ if $pbs_config->{DISPLAY_RULES_ORDERING} ;

$pbs_config->{MAXIMUM_RULE_RECURSION} //= 15 ;
$pbs_config->{RULE_RECURSION_WARNING} //= 5 ;

$pbs_config->{SHORT_DEPENDENCY_PATH_STRING} //= '…' ;

$pbs_config->{DEBUG_DISPLAY_TRIGGER}++ if $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY} ;

$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES}++ if $pbs_config->{DEBUG_DISPLAY_DEPENDENCY_RULE_DEFINITION} ;
$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG}++ if $pbs_config->{DEBUG_DISPLAY_DEPENDENCY_REGEX} ;
$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES}++ if $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES_LONG} ;

$pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING}++ if $pbs_config->{DISPLAY_PARALLEL_DEPEND_LINKING_VERBOSE} ;

$pbs_config->{DISPLAY_NO_STEP_HEADER} = 0 if $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} ;

if($pbs_config->{DISPLAY_NO_STEP_HEADER})
	{
	undef $pbs_config->{DISPLAY_DEPEND_NEW_LINE} ;
	undef $pbs_config->{DISPLAY_DEPENDENCY_TIME} ;
	}

$pbs_config->{DISPLAY_NO_STEP_HEADER_COUNTER}++ if $pbs_config->{DISPLAY_STEP_HEADER_NL} ;
$pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE}++ if $pbs_config->{DEBUG_DISPLAY_BUILD_SEQUENCE_SIMPLE_STATS_ONLY} ;

if(@{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}})
	{
	$pbs_config->{DEBUG_DISPLAY_DEPENDENCIES}++ ;
	}
else
	{
	push @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}}, '.' ;
	}

push @{$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX}}, '.'
	unless @{$pbs_config->{BUILD_AND_DISPLAY_NODE_INFO_REGEX}} ;

undef $pbs_config->{DEBUG_DISPLAY_TRIGGER_INSERTED_NODES} if $pbs_config->{DEBUG_DISPLAY_DEPENDENCIES} ;

$pbs_config->{DISPLAY_DIGEST}++ if $pbs_config->{DISPLAY_DIFFERENT_DIGEST_ONLY} ;

$pbs_config->{DISPLAY_SEARCH_INFO}++ if $pbs_config->{DISPLAY_SEARCH_ALTERNATES} ;

if($pbs_config->{BUILD_AND_DISPLAY_NODE_INFO} || @{$pbs_config->{DISPLAY_NODE_INFO}})
	{
	$pbs_config->{DISPLAY_NO_PROGRESS_BAR}++ ;
	undef $pbs_config->{DISPLAY_PROGRESS_BAR} ;

	$pbs_config->{DISPLAY_NO_BUILD_HEADER} = 0 ;
	$PBS::Shell::silent_commands           = 0 ;
	$PBS::Shell::silent_commands_output    = 0 ;

	$pbs_config->{DISPLAY_NODE_BUILD_NAME}++ ; 

	unless ($pbs_config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM} || $pbs_config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2})
		{
		$pbs_config->{DISPLAY_NODE_ORIGIN}++ ;
		$pbs_config->{DISPLAY_NODE_PARENTS}++ ;
		$pbs_config->{DISPLAY_NODE_DEPENDENCIES}++ ;
		$pbs_config->{DISPLAY_NODE_BUILD_CAUSE}++ ;
		$pbs_config->{DISPLAY_NODE_BUILD_RULES}++ ;
		$pbs_config->{DISPLAY_NODE_CONFIG}++ ;
		}
	
	if($pbs_config->{DISPLAY_NO_PROGRESS_BAR_MINIMUM_2})
		{
		$pbs_config->{DISPLAY_NODE_ORIGIN} = 0 ;
		$pbs_config->{DISPLAY_NO_NODE_BUILD_RULES}++ ;
		$pbs_config->{DISPLAY_NODE_BUILD_NAME} = 0 ;
		}

	$pbs_config->{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS}++ ;
	}
	
$pbs_config->{DISPLAY_NODE_ORIGIN}++ if $pbs_config->{DISPLAY_NODE_PARENTS} ;

push @{$pbs_config->{NODE_ENVIRONMENT_REGEX}}, '.'
	if @{$pbs_config->{DISPLAY_NODE_ENVIRONMENT}} && ! @{$pbs_config->{NODE_ENVIRONMENT_REGEX} } ;

# ------------------------------------------------------------------------------

$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_ROOT_BUILD_DIRECTORY} = undef if $pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY} ;

$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG}++ if $pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE} ;
$pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG}++ if $pbs_config->{GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG_EDGE} ;

for my $cluster_node_regex (@{$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_NODE}})
	{
	$cluster_node_regex = './' . $cluster_node_regex unless $cluster_node_regex =~ /^\.|\// ;
	$cluster_node_regex =~ s/\./\\./g ;
	$cluster_node_regex =~ s/\*/.*/g ;
	$cluster_node_regex = '^' . $cluster_node_regex . '$' ;
	}

if(defined $pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST})
	{
	if( -e $pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST})
		{
		push @{$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX}}, 
			grep { $_ ne '' && $_ !~ /^\s*#/ }
				read_file($pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST}, chomp => 1) ;
		}
	else
		{
 		die ERROR("Graph: cluster list '$pbs_config->{GENERATE_TREE_GRAPH_CLUSTER_REGEX_LIST}' not found"), "\n" ;
		}
	}

for my $exclude_node_regex (@{$pbs_config->{GENERATE_TREE_GRAPH_EXCLUDE}})
	{
	$exclude_node_regex =~ s/\./\\./g ;
	$exclude_node_regex =~ s/\*/.\*/g ;
	}

for my $include_node_regex (@{$pbs_config->{GENERATE_TREE_GRAPH_INCLUDE}})
	{
	$include_node_regex =~ s/\./\\./g ;
	$include_node_regex =~ s/\*/.\*/g ;
	}
	
#-------------------------------------------------------------------------------

$pbs_config->{DISPLAY_DIGEST}++ if $pbs_config->{DISPLAY_DIFFERENT_DIGEST_ONLY} ;

$Data::Dumper::Maxdepth = $pbs_config->{MAX_DEPTH} if $pbs_config->{MAX_DEPTH} ;
$Data::Dumper::Indent   = $pbs_config->{INDENT_STYLE} if $pbs_config->{INDENT_STYLE} ;

if($pbs_config->{DISTRIBUTE})
	{
	$pbs_config->{JOBS} = 0 unless $pbs_config->{JOBS} ; # let distributor determine how many jobs
	}
else
	{
	if(! $pbs_config->{JOBS} || $pbs_config->{JOBS} < 0)
		{
		$pbs_config->{JOBS} = 8 ; 
		}
	}

if($pbs_config->{DEBUG_TRIGGER_ALL})
	{
	push @{$pbs_config->{TRIGGER}}, '.' ;
	}

push @{$pbs_config->{TRIGGER}}, 
	grep { $_ ne '' && $_ !~ /^\s*#/ }
		read_file($pbs_config->{DEBUG_TRIGGER_LIST}, chomp => 1)
			if $pbs_config->{DEBUG_TRIGGER_LIST} ;

$pbs_config->{DEBUG_TRIGGER}++ if @{$pbs_config->{TRIGGER}} ; # force stop on this option

if($pbs_config->{DEBUG_TRIGGER_NONE} && $pbs_config->{DEBUG_TRIGGER_ALL})
	{
	PrintWarning "Config: --trigger_none and --trigger_all  switch are given, --trigger_all takes precedence.\n" ;
	delete $pbs_config->{DEBUG_TRIGGER_NONE} ;
	}

if($pbs_config->{DEBUG_DISPLAY_TREE_NAME_ONLY})
	{
	$pbs_config->{DEBUG_DISPLAY_TEXT_TREE}++ ;
	}
	
if(@{$pbs_config->{DISPLAY_TREE_FILTER} // []})
	{
	$pbs_config->{DISPLAY_TREE_FILTER} =  {map {$_ => 1} @{$pbs_config->{DISPLAY_TREE_FILTER}}} ;
	}
else
	{
	undef $pbs_config->{DISPLAY_TREE_FILTER} ;
	}

$pbs_config->{DISPLAY_TEXT_TREE_USE_ASCII} //= 0 ;

$pbs_config->{DISPLAY_TEXT_TREE_MAX_DEPTH} = -1 unless $pbs_config->{DISPLAY_TEXT_TREE_MAX_DEPTH} ;
$pbs_config->{DISPLAY_TEXT_TREE_MAX_MATCH} //= 3 ;

#-------------------------------------------------------------------------------
# build or not switches
if($pbs_config->{NO_BUILD} && $pbs_config->{FORCE_BUILD})
	{
	PrintWarning "Config: --force_build and --no_build switch are given, --no_build takes precedence.\n" ;
	$pbs_config->{FORCE_BUILD} = 0 ;
	}
	
$pbs_config->{DO_BUILD} = 0 if $pbs_config->{NO_BUILD} ;

unless($pbs_config->{FORCE_BUILD})
	{
	while(my ($debug_flag, $value) = each %$pbs_config) 
		{
		if($debug_flag =~ /^DEBUG/ && defined $value)
			{
			$pbs_config->{DO_BUILD} = 0 ;
			keys %$pbs_config;
			last ;
			}
		}
	}

PrintInfo4 "Config: --no_config_inheritance\n" if $pbs_config->{NO_CONFIG_INHERITANCE} ;

#--------------------------------------------------------------------------------

$Data::TreeDumper::Startlevel = 1 ;
$Data::TreeDumper::Useascii   = $pbs_config->{DISPLAY_TEXT_TREE_USE_ASCII} ;
$Data::TreeDumper::Maxdepth   = $pbs_config->{DISPLAY_TEXT_TREE_MAX_DEPTH} ;

#--------------------------------------------------------------------------------

my ($pbsfile, $error_message) = GetPbsfileName($pbs_config) ;

return(0, $error_message) unless defined $pbsfile ;

$pbs_config->{PBSFILE} = $pbsfile ;
$pbs_config->{PBSFILE} = './' . $pbs_config->{PBSFILE} unless $pbs_config->{PBSFILE}=~ /^\.|\// ;

#--------------------------------------------------------------------------------

my $cwd = getcwd() ;
if(0 == @{$pbs_config->{SOURCE_DIRECTORIES}})
	{
	push @{$pbs_config->{SOURCE_DIRECTORIES}}, $cwd ;
	}

for my $plugin_path (@{$pbs_config->{PLUGIN_PATH}})
	{
	unless(file_name_is_absolute($plugin_path))
		{
		$plugin_path = catdir($cwd, $plugin_path)  ;
		}
		
	$plugin_path = CollapsePath($plugin_path ) ;
	}
	
unless($pbs_config->{BUILD_DIRECTORY})
	{
	if($pbs_config->{MANDATORY_BUILD_DIRECTORY})
		{
		return(0, "No Build directory given and --mandatory_build_directory set.\n") ;
		}
	else
		{
		$pbs_config->{BUILD_DIRECTORY} = $cwd . "/_out_" . GetUserName() ;
		}
	}

if(defined $pbs_config->{LIB_PATH})
	{
	for my $lib_path (@{$pbs_config->{LIB_PATH}})
		{
		$lib_path .= '/' unless $lib_path =~ /\/$/ ;
		}
	}

# compute a signature for the current PBS run
# check if a signature exists in the output directory
# OK if the signatures match
# on mismatch, ask for another output directory or force override

CheckPackageDirectories($pbs_config) ;

#----------------------------------------- Log -----------------------------------------

if($pbs_config->{CREATE_LOG_HTML})
	{
	$pbs_config->{CREATE_LOG}++ ;
	}

PBS::Log::CreatePbsLog($pbs_config) if defined $pbs_config->{CREATE_LOG} ;

#----------------------------------------- HOSTNAME  -----------------------------------------
$ENV{HOSTNAME} //= qx"hostname" // 'no_host' ;

return 1, $success_message ;
}

#-------------------------------------------------------------------------------

my $parse_prf_switches_run = 0 ; # guaranty we load stuff in a uniq package

use constant PARSE_PRF_SWITCHES_IGNORE_ERROR => 1 ;

sub ParsePrfSwitches
{
my ($no_anonymous_pbs_response_file, $pbs_response_file_to_use, $ignore_error, $display_location) = @_ ;

my $package = caller() ;
my $prf_load_package = 'PBS_PRF_SWITCHES_' . $package . '_' . $parse_prf_switches_run ;
$parse_prf_switches_run++ ;

my $pbs_response_file ;
unless($no_anonymous_pbs_response_file)
	{
	$pbs_response_file = 'pbs.prf' if -e 'pbs.prf' ;
	}

my $user = GetUserName() ;

$pbs_response_file = "$user.prf" if -e "$user.prf" ;
$pbs_response_file =  $pbs_response_file_to_use if defined $pbs_response_file_to_use ;

if($pbs_response_file)
	{
	PrintInfo "PBS: loading prf '$pbs_response_file'\n" if $display_location ;

	unless(-e $pbs_response_file)
		{
		PrintError "PBS: can't find prf '$pbs_response_file'" ;
		die "\n" ;
		}
		
	# we load the prf in its own namespace
	my ($options, $config) = PBS::PBSConfigSwitches::GetOptions() ;
	RegisterPbsConfig($prf_load_package, $config, $options) ;

 	$config->{PRF_IGNORE_ERROR} = $ignore_error ;
	
	use PBS::PBS;
	PBS::PBS::LoadFileInPackage
		(
		'Pbsfile', # $type
		$pbs_response_file,
		$prf_load_package,
		$config,
		"use PBS::Prf ;\n" #$pre_code
		 ."use PBS::Output ;\n",
		'', #$post_code
		) ;

	return $pbs_response_file, $config ;
	}
else
	{
	return 'no prf defined', {} ;
	}
}

#-------------------------------------------------------------------------------

sub GetPbsfileName
{
my $pbs_config = shift ;

my $pbsfile ;
my $error_message = '' ;

if($pbs_config->{PBSFILE})
	{
	$pbsfile = $pbs_config->{PBSFILE} ;
	
	if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
		{
		PrintInfo "Config: Using pbsfile '$pbsfile' (given as argument).\n" ;
		}
	}
else
	{
	my @pbsfile_names = split /\s+/, ($pbs_config->{PBSFILE_NAMES} // '') ;
	my @pbsfile_extensions =  split /\s+/, ($pbs_config->{PBSFILE_EXTENSIONS} // '') ;

	@pbsfile_extensions = qw(*.pl *.pbs) unless @pbsfile_extensions ;

	if($^O eq 'MSWin32')
		{
		@pbsfile_names = qw(pbsfile.pl pbsfile) unless @pbsfile_names;
		}
	else
		{
		@pbsfile_names = qw(Pbsfile.pl pbsfile.pl Pbsfile pbsfile) unless @pbsfile_names ;
		}

	my %existing_pbsfile = map{( $_ => 1)} grep { -e "./$_"} @pbsfile_names ;
	
	if(keys %existing_pbsfile)
		{
		if(keys %existing_pbsfile == 1)
			{
			($pbsfile) = keys %existing_pbsfile ;
			if($pbs_config->{DISPLAY_SUBPBS_SEARCH_INFO})
				{
				PrintInfo "PBS: Using pbsfile '$pbsfile'.\n" ;
				}
			}
		else
			{
			$error_message = "PBS: found the following files as pbsfiles candidates:\n" ;
			
			for my $found_pbsfile (keys %existing_pbsfile)
				{
				$error_message .= "\t$found_pbsfile\n" ;
				}
			}
		}
	else
		{
		use File::Find::Rule;

		my @files = File::Find::Rule->file()
				->name( @pbsfile_extensions, @pbsfile_names )
				->maxdepth(1)
				->in( '.' ) ;

		if (0 == @files)
			{
			$error_message = "PBS: no 'pbsfile' to define build.\n" ;
			}
		elsif (1 == @files)
			{
			$pbsfile = $files[0] ;
			PrintWarning "PBS: using '$pbsfile' as pbsfile\n" ;
			}
		else
			{
			PrintWarning "PBS: found the following  files as pbsfile candidates:\n" ;
			PrintWarning DumpTree \@files, '', DISPLAY_ADDRESS => 0 ;

			$error_message = "PBS: no 'pbsfile' to define build.\n" ;
			}
		}
	}

if (defined $pbsfile)
	{
	unless(File::Spec->file_name_is_absolute($pbsfile))
		{
		# found in current directory or expected to be in the current directory
		my $cwd = getcwd() ;
		$pbsfile = "$cwd/$pbsfile" ;
		}
	}
return($pbsfile, $error_message) ;
}

#-------------------------------------------------------------------------------

sub CollapsePath
{
#remove '.' and '..' from a path

my $collapsed_path = shift ;

#~ PrintDebug $collapsed_path  ;

$collapsed_path =~ s~(?<!\.)\./~~g ;
$collapsed_path =~ s~/\.$~~ ;

1 while($collapsed_path =~ s~[^/]+/\.\./~~) ;
$collapsed_path =~ s~[^/]+/\.\.$~~ ;

# remove double separators
$collapsed_path =~ s~\/+~\/~g ;

# collaps to root
$collapsed_path =~ s~^/(\.\./)+~/~ ;

#remove trailing '/'
$collapsed_path =~ s~/$~~ unless $collapsed_path eq '/' ;

#~ PrintDebug " => $collapsed_path\n"  ;

return($collapsed_path) ;
}

#-------------------------------------------------------------------------------

sub CheckPackageDirectories
{
my $pbs_config = shift ;

my $cwd = getcwd() ;

if(defined $pbs_config->{SOURCE_DIRECTORIES})
	{
	for my $source_directory (@{$pbs_config->{SOURCE_DIRECTORIES}})
		{
		unless(file_name_is_absolute($source_directory))
			{
			$source_directory = catdir($cwd, $source_directory) ;
			}
			
		$source_directory = CollapsePath($source_directory) ;
		}
	}
	
if($pbs_config->{BUILD_DIRECTORY})
	{
	unless(file_name_is_absolute($pbs_config->{BUILD_DIRECTORY}))
		{
		$pbs_config->{BUILD_DIRECTORY} = catdir($cwd, $pbs_config->{BUILD_DIRECTORY}) ;
		}
		
	$pbs_config->{BUILD_DIRECTORY} = CollapsePath($pbs_config->{BUILD_DIRECTORY}) ;
	}
}

#-------------------------------------------------------------------------------

1 ;

#-------------------------------------------------------------------------------

__END__
=head1 NAME

PBS::PBSConfig - Handles PBS configuration

=head1 DESCRIPTION

Every loaded package has a configuration. The first configuration, loaded
through the I<pbs> utility is stored in the 'PBS' package and is influenced by I<pbs> command line switches.
Subsequent configurations are loaded when a subpbs is run. The configuration name and contents reflect the loaded package parents
and the subpbs configuration.

I<GetPbsConfig> can be used (though not recommended), in Pbsfiles, to get the current pbs configuration. The configuration name is __PACKAGE__.
The returned scalaris a reference to the configuration hash.

	# in a Pbsfile
	use Data::TreeDumper ;
	
	my $pbs_config = GetPbsConfig(__PACKAGE__) ;
	PrintInfo(DumpTree( $pbs_config->{SOURCE_DIRECTORIES}, "Source directories")) ;

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
