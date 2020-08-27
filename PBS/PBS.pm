
package PBS::PBS ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
#$Data::TreeDumper::Displaycallerlocation++ ;
use Carp ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Spec::Functions qw(:ALL) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(PbsUse) ;
our $VERSION = '0.03' ;

use PBS::PBSConfig ;
use PBS::Output ;
use PBS::DefaultBuild ;
use PBS::Config ;
use PBS::Rules ;
use PBS::Depend ;
use PBS::Build ;
use PBS::Shell ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Digest;

use Digest::MD5 qw(md5_hex) ;
use String::Truncate ;

#-------------------------------------------------------------------------------

# a global place to keep timing and other pbs run information
# the idea is to make them available to a post pbs script for processing
# this should of course be passed around not be global, maybe we 
# should package this and the dependency tree, nodes, etc in some structure

our $pbs_run_information = 
	{
	# TIMING => {}
	# CAHE => {MD5_HITS => xxx, C_DEPENDER_HITS => YYY ...
	# BUILDER
	} ;


#-------------------------------------------------------------------------------

our $pbs_runs ;
my %Pbs_runs ;

sub GetPbsRuns
{
return($pbs_runs) ;
}

sub Pbs
{
my $t0 = [gettimeofday];
$PBS::Output::indentation_depth++ ;
$pbs_runs++ ;

my $pbsfile_chain        = shift // [] ;
my $pbsfile_rule_name    = shift ;
my $Pbsfile              = shift ;
my $parent_package       = shift ;
my $pbs_config           = shift ;
my $parent_config        = shift ;
my $package              = CanonizePackageName($pbs_config->{PACKAGE}) ;
my $build_directory      = $pbs_config->{BUILD_DIRECTORY} ;
my $source_directories   = $pbs_config->{SOURCE_DIRECTORIES} ;
my $targets              = shift ;
my $target_names         = join ', ', @$targets ;
my $inserted_nodes       = shift ;
my $dependency_tree_name = shift || die ;
my $depend_and_build     = shift ;


my $original_ENV_size = scalar(keys %ENV) ;

for (sort keys %ENV)
	{
	my $keep ;

	for my $keep_regex ( @{$pbs_config->{KEEP_ENVIRONMENT}})
		{
		if (/$keep_regex/)
			{
			$keep = $keep_regex ; last ;
			}
		}

	if(defined $keep)
		{
		PrintInfo3 "ENV: keeping  '$_' => " . INFO2("'$ENV{$_}'\n") if $pbs_config->{DISPLAY_ENVIRONMENT} && $pbs_runs == 1 ;
		}
	else
		{ 
		PrintWarning "ENV: removing '$_' => '$ENV{$_}'\n" if $pbs_config->{DISPLAY_ENVIRONMENT} && !$pbs_config->{DISPLAY_ENVIRONMENT_KEPT} && $pbs_runs == 1 ;
		delete $ENV{$_} ;
		}
	}

my $ENV_size = scalar(keys %ENV) ;
my $ENV_removed = $original_ENV_size - $ENV_size ;

PrintInfo "ENV: kept: $ENV_size, removed: $ENV_removed\n" if $pbs_config->{DISPLAY_ENVIRONMENT_INFO} && $pbs_runs == 1 ;	

unless('' eq ref $package && '' ne $package)
	{
	PrintError("Invalid 'PACKAGE' at $Pbsfile\n") ;
	die ;
	}

if(defined $pbs_config->{SAVE_CONFIG})
	{
	SaveConfig($targets, $Pbsfile, $pbs_config, $parent_config) ;
	}

undef $pbs_config->{TARGETS} ;
for my $target (@$targets)
	{
	if(file_name_is_absolute($target) || $target =~ /^\.\//)
		{
		push @{$pbs_config->{TARGETS}}, $target ;
		}
	else
		{
		push @{$pbs_config->{TARGETS}}, "./$target" ;
		}
	}

my (undef, $target_path) = File::Basename::fileparse($targets->[0], ('\..*')) ;

$target_path =~ s/^\.\/// ;
$target_path =~ s/\/$// ;

$pbs_config->{TARGET_PATH} = $pbs_config->{SET_PATH_REGEX} || $target_path ;

undef $pbs_config->{SET_PATH_REGEX};

$Pbs_runs{$package} = 1 unless (exists $Pbs_runs{$package}) ;

my $load_package = 'PBS::Runs::' . $package . '_' . $Pbs_runs{$package}++ ;
$pbs_config->{LOAD_PACKAGE} = $load_package ;

$inserted_nodes //= {} ;

my $display_all_pbs_config = 0 ;

for (@{$pbs_config->{DISPLAY_PBS_CONFIGURATION}})
	{
	if('.' eq $_)
		{
		$display_all_pbs_config++ ;
		last ;
		}
	}

if($display_all_pbs_config)
	{
	PrintInfo DumpTree($pbs_config, "Package '$package:$Pbsfile' config:") ;
	}
else
	{
	for my $regex (@{$pbs_config->{DISPLAY_PBS_CONFIGURATION}})
		{
		for my $key ( grep { /$regex/ } keys %{ $pbs_config} )
			{
			if('' eq ref $pbs_config->{$key})
				{
				if(defined $pbs_config->{$key})
					{
					PrintInfo("$key: " . $pbs_config->{$key} . "\n") ;
					}
				else
					{
					PrintInfo("$key: undef\n") ;
					}
				}
			else
				{
				PrintInfo(DumpTree($pbs_config->{$key}, $key, INDENTATION => '    ')) ;
				}
			}
		}
	}
	
# load meso file

$dependency_tree_name =~ s/\//_/g ;
$dependency_tree_name = "__PBS_" . $dependency_tree_name ;

my %tree_hash = 
	(
	__NAME          => $dependency_tree_name,
	__DEPENDENCY_TO => {PBS => "Perl Build System [$PBS::Output::indentation_depth]"},
	__INSERTED_AT   => 
				{
				PBSFILE_CHAIN          => $pbsfile_chain,
				INSERTION_FILE         => $Pbsfile,
				INSERTION_PACKAGE      => 'PBS::PBS::Pbs',
				INSERTION_LOAD_PACKAGE => 'Root load',
				INSERTION_RULE         => 'Root load',
				INSERTION_RULE_NAME    => 'Root load',
				INSERTION_RULE_LINE    => '',
				INSERTION_TIME         => 0,
				INSERTING_NODE         => 'Root load',
				},
	__PBS_CONFIG    => $pbs_config,
	) ;

my $dependency_tree = \%tree_hash ;
my $build_point = '' ;
my ($build_result, $build_message) ;

if(-e $Pbsfile || defined $pbs_config->{PBSFILE_CONTENT})
	{
	# check target names
	for(@$targets)
		{
		if(/@/ > 1)
			{
			PrintError("Invalid composite target definition\n") ;
			die ;
			}
			
		if(/^(.*)@(.*)$/)
			{
			if(@$targets == 1)
				{
				$build_point = $1 ;
				$_ = $2 ;
				}
			else
				{
				PrintError("Only one composite target is supported\n") ;
				die ;
				}
			}
		} 
		
	unless(@{$pbs_config->{RULE_NAMESPACES}})
		{
		push @{$pbs_config->{RULE_NAMESPACES}}, ('BuiltIn', 'User')
		}
	push my @rule_namespaces, @{$pbs_config->{RULE_NAMESPACES}} ;
		
	unless(@{$pbs_config->{CONFIG_NAMESPACES}})
		{
		push @{$pbs_config->{CONFIG_NAMESPACES}}, ('BuiltIn', 'User') ;
		}
	push my @config_namespaces, @{$pbs_config->{CONFIG_NAMESPACES}} ;
	
	my $user_build ;
	PBS::PBSConfig::RegisterPbsConfig($load_package, $pbs_config) ;
	
	#Command defines
	PBS::Config::AddConfigEntry($load_package, 'COMMAND_LINE', '__PBS', 'Command line', %{$pbs_config->{COMMAND_LINE_DEFINITIONS}}) ;
	
	my $sub_config = PBS::Config::GetPackageConfig($load_package) ; 
	
	PBS::Config::AddConfigEntry($load_package, 'PBS_FORCED', '__PBS_FORCED', 'PBS', 'TARGET_PATH' => $pbs_config->{TARGET_PATH}) ;
	
	# merge parent config
	PBS::Config::AddConfigEntry($load_package, 'PARENT', '__PBS', "parent: '$parent_package' [$target_names]", %{$parent_config}) ;
	
	PrintInfo(DumpTree({PBS::Config::ExtractConfig($sub_config)}, "Config: before running '$Pbsfile' in  package '$package':"))
		 if $pbs_config->{DISPLAY_CONFIGURATION_START}  ;
	
	my $add_pbsfile_digest = '' ;
	
	if(defined $pbs_config->{PBSFILE_CONTENT})
		{
		use Digest::MD5 qw(md5_hex) ;
		my $pbsfile_digest = md5_hex($pbs_config->{PBSFILE_CONTENT}) ;
		$add_pbsfile_digest = "PBS::Digest::AddVariableDependencies(PBSFILE => '$pbsfile_digest') ;\n"
		}
		
	LoadFileInPackage
		(
		'Pbsfile',
		$Pbsfile,
		$load_package,
		$pbs_config,
		"use strict ;\n"
		  . "use warnings ;\n"
		  . "use PBS::Constants ;\n"
		  . "use PBS::Shell ;\n"
		  . "use PBS::Output ;\n"
		  . "use PBS::Rules ;\n"
		  . "use PBS::Triggers ;\n"
		  . "use PBS::PostBuild ;\n"
		  . "use PBS::PBSConfig ;\n"
		  . "use PBS::Config ;\n"
		  . "use PBS::Check ;\n"
		  . "use PBS::PBS ;\n"
		  . "use PBS::Digest;\n"
		  . "use PBS::Rules::Creator;\n"
		  . $add_pbsfile_digest,
		  
		"\n# load OK\n1 ;\n",
		) ;
		
	PBS::Rules::RegisterRule
		(
		$pbsfile_rule_name,
		'',
		$load_package,
		'BuiltIn',
		[VIRTUAL, '__INTERNAL'],
		'PBS',
		sub
			{
			my $dependent = shift ;
			
			if($dependent eq $dependency_tree_name)
				{
				my @targets = map 
						{
						if(file_name_is_absolute($_) || /^\.\//)
							{
							"$_" ;
							}
						else
							{
							PrintDebug "Found a target without './' $_\n" if $build_point eq '' ;
							"./$_" ;
							}
						} @$targets ;
				
				return([1, @targets]) ;
				}
			else
				{
				return([0]) ;
				}
			},
		) ;
		
	{
	no warnings ;
	eval "\$user_build = *${load_package}::Build{CODE} ;" ;
	}
		
	my $rules   = PBS::Rules::GetPackageRules($load_package) ; 
	
        my $rules_namespaces = join ', ', @rule_namespaces ;
	my $config_namspaces = join ', ', @config_namespaces ;
	
	if($user_build && (! defined $pbs_config->{NO_USER_BUILD}) )
		{
                unless($pbs_config->{DISPLAY_NO_STEP_HEADER})
                	{
			PrintInfo("User Build(). package: $package, rules $rules_namespaces, config: $config_namspaces.\n") ;
			}
											
		($build_result, $build_message)
			= $user_build->
				(
				$Pbsfile,
				$package,
				$load_package,
				$pbs_config,
				\@rule_namespaces,
				$rules,
				\@config_namespaces,
				$sub_config,
				$targets, # automatically build in rule 'BuiltIn::__ROOT', given as information only
				$inserted_nodes,
				$dependency_tree, # rule 0 dependent name is in $dependency_tree ->{__NAME}
				$build_point,
				$depend_and_build,
				) ;
			
		}
	else
		{
		($build_result, $build_message)
			= PBS::DefaultBuild::DefaultBuild
				(
				$pbsfile_chain,
				$Pbsfile,
				$package,
				$load_package,
				$pbs_config,
				\@rule_namespaces,
				$rules,
				\@config_namespaces,
				$sub_config,
				$targets, # automatically build in rule 'BuiltIn::__ROOT', given as information only
				$inserted_nodes,
				$dependency_tree,
				$build_point,
				$depend_and_build,
				) ;
		
		}
	}
else
	{
	my $error = "PBS: Error: no pbsfile: $Pbsfile" ;
	$error .= ", at: $pbs_config->{SUBPBS_HASH}{ORIGIN}" if defined $pbs_config->{SUBPBS_HASH}{ORIGIN};

	PrintError $error ;

=pod alternative_output
	PrintError DumpTree
			(
			{subpbs => $pbs_config->{SUBPBS_HASH}},
			"Error: no pbsfile: '$Pbsfile', targets: [@$targets], at: $pbs_config->{SUBPBS_HASH}{ORIGIN}" ,
			DISPLAY_ADDRESS => 0
			) ;

=cut
	die "\n";
	}

$PBS::Output::indentation_depth-- ;

if($pbs_config->{DISPLAY_DEPENDENCY_TIME})
	{
	PrintInfo(sprintf("Time in Pbsfile: %0.2f s.\n", tv_interval ($t0, [gettimeofday]))) ;
	}
	
# save  meso file

return($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package) ;
}

#-------------------------------------------------------------------------------

sub SaveConfig
{
my ($targets, $pbsfile, $pbs_config, $parent_config) = @_ ;

my $first_target = $targets->[0] ;

my ($first_target_name, $first_target_path, $sufix) = File::Basename::fileparse($targets->[0], ('\..*')) ;
$first_target_name .= $sufix ;
$first_target_path =~ s [./][];

my $path             = $pbs_config->{BUILD_DIRECTORY} . '/' . $first_target_path ;

my $config_file_name = "${path}parent_config___$pbs_config->{SAVE_CONFIG}.pl" ;
$config_file_name =~ s/[^a-zA-Z0-9\/.\-_]/_/g ;

use File::Path ;
mkpath($pbs_config->{BUILD_DIRECTORY}) unless(-e $pbs_config->{BUILD_DIRECTORY}) ;
mkpath($path) unless(-e $path) ;

PrintInfo "Config: saved in '$config_file_name'\n" ;

open(CONFIG, ">", $config_file_name) or die qq[Can't open '$config_file_name': $!] ;

local $Data::Dumper::Purity = 1 ;
local $Data::Dumper::Indent = 1 ;
local $Data::Dumper::Sortkeys = 
	sub
	{
	my $hash = shift ;
	return [sort keys %{$hash}] ;
	} ;

local $SIG{'__WARN__'} = sub 
	{
	if($_[0] =~ 'Encountered CODE ref')
		{
		# ignore this warning
		}
	else
		{
		print STDERR $_[0] ;
		}
	} ;

print CONFIG PBS::Log::GetHeader('Config', $pbs_config) ;
print CONFIG <<EOI ;
# pbsfile: $pbsfile
# target: $first_target

EOI
print CONFIG Data::Dumper->Dump([$pbs_config], ['pbs_config']) ;
print CONFIG Data::Dumper->Dump([$parent_config], ['parent_config']) ;

print CONFIG 'return($pbs_config, $parent_config);';

close(CONFIG) ;
}

#-------------------------------------------------------------------------------
my %files_loaded_via_PbsUse ;
my $pbs_use_level = -1 ;

sub PbsUse
{
my ($package, $file_name, $line) = caller() ;

for my $source_name (@{[@_]})
	{
	unless(defined $source_name)
		{
		PrintError "PbsUse must be given a name. Called @ $file_name:$line.\n"  ;
		die "\n" ;
		}
		
	if('' ne ref $source_name)
		{
		PrintError "PbsUse only accepts strings as input. Called @ $file_name:$line.\n"  ;
		die "\n" ;
		}
		
	my $t0 = [gettimeofday];
	
	my $global_package_dependency = shift || 1 ; # if set, the used module becomes a dependency for all the package nodes
	
	my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
	my $located_source_name ;
	
	$source_name .= '.pm' unless $source_name =~ /\.pm$/ ;
	
	unless(defined $pbs_config->{LIB_PATH})
		{
		PrintError("Can't search for '$source_name', PBS lib path is not defined (PBS_LIB_PATH)!\n") ;
		die "\n" ;
		}
	
	if(file_name_is_absolute($source_name))
		{
		$located_source_name = $source_name ;
		}
	elsif($source_name =~ m~^./~)
		{
		$located_source_name = $source_name ;
		}
	else
		{
		for my $lib_path (@{$pbs_config->{LIB_PATH}})
			{
			$lib_path .= '/' unless $lib_path =~ /\/$/ ;
			
			if(-e $lib_path . $source_name)
				{
				$located_source_name = $lib_path . $source_name ;
				last ;
				}
			}
		}
	
	unless(defined $located_source_name)
		{
		my $paths = join ', ', @{$pbs_config->{LIB_PATH}} ;
		
		die  ERROR("Can't locate '$source_name' in PBS libs [$paths] @ $file_name:$line.") . "\n" ;
		}
	
	$pbs_use_level++ ; # indent the PbsUse output to make the hierachy more visible
	my $indentation = '   ' x $pbs_use_level ;
	
	PrintInfo2("${indentation}PbsUse: '$located_source_name' called at '$file_name:$line'\n") if(defined $pbs_config->{DISPLAY_PBSUSE_VERBOSE}) ;
	PrintInfo2("${indentation}PbsUse: '$source_name'\n") if(defined $pbs_config->{DISPLAY_PBSUSE}) ;
	
	
	if(exists $files_loaded_via_PbsUse{$package}{$located_source_name})
		{
		my $load_information = join(':', $package, $file_name, $line) ;
		my $previous_load_information = join(':', @{$files_loaded_via_PbsUse{$package}{$located_source_name}}) ;
		PrintWarning(sprintf("PbsUse: '$source_name' load command ignored[$load_information]! Was already loaded at $previous_load_information.\n")) ;
		}
	else
		{
		my $add_as_package_dependency = '' ;
		
		if($global_package_dependency)
			{
			$add_as_package_dependency = "PBS::Digest::AddPbsLibDependencies('$located_source_name', '$source_name') ;\n" ;
			}
			
		eval
			{
			LoadFileInPackage
				(
				'',
				$located_source_name,
				$package,
				$pbs_config,
				"use PBS::Constants ;\n" . $add_as_package_dependency,
				) ;
			} ;

		if($@)
			{
			die ERROR("PbsUse error @ $file_name:$line:\n\n$@\n") . "\n"  ;
			}
			
		$files_loaded_via_PbsUse{$package}{$located_source_name} = [$package, $file_name, $line];
		}
	
	$pbs_use_level-- ;
	
	my $pbsuse_time = tv_interval ($t0, [gettimeofday]) ;
	
	if(defined $pbs_config->{DISPLAY_PBSUSE_TIME})
		{
		if(defined $pbs_config->{DISPLAY_PBSUSE_TIME_ALL})
			{
			PrintInfo(sprintf("${indentation}Time in PbsUse '$source_name': %0.2f s.\n", $pbsuse_time)) ;
			}
		else
			{
			if(-1 == $pbs_use_level)
				{
				PrintInfo(sprintf("${indentation}Time in PbsUse: %0.2f s.\n", $pbsuse_time)) ;
				}
			}
		}
	
	if(defined $pbs_config->{DISPLAY_PBSUSE_STATISTIC})
		{
		$files_loaded_via_PbsUse{__STATISTIC}{$located_source_name}{LOADS}++ ;
		$files_loaded_via_PbsUse{__STATISTIC}{$located_source_name}{TOTAL_TIME} += $pbsuse_time ;
		$files_loaded_via_PbsUse{__STATISTIC}{TOTAL_LOADS}++ ;
		$files_loaded_via_PbsUse{__STATISTIC}{TOTAL_TIME}+= $pbsuse_time ;
		}
	}
}

#-------------------------------------------------------------------------------

sub GetPbsUseStatistic
{
return DumpTree($files_loaded_via_PbsUse{__STATISTIC}, "'PbsUse' statistic:", DISPLAY_ADDRESS => 0) ;
}

#-------------------------------------------------------------------------------
sub CanonizePackageName
{
my $package = shift || die ;
$package =~ s/[^a-zA-Z0-9_:]+/_/g ;

return($package) ;
}

sub LoadFileInPackage
{
my $type       = shift ;
my $file       = shift ;
my $package    = CanonizePackageName(shift) ;
my $pbs_config = shift ;
my $pre_code   = shift || '' ;
my $post_code  = shift || '' ;

my $file_body = '' ; 

if($type eq 'Pbsfile')
	{
	my $available = PBS::Output::GetScreenWidth() ;
	my $em = String::Truncate::elide_with_defaults({ length => $available, truncate => 'left' });

	PrintInfo3("PBS: loading '" . $em->($file) ."'.\n") if (defined $pbs_config->{DISPLAY_PBSFILE_LOADING}) ;
	
	if(defined $pbs_config->{PBSFILE_CONTENT} && -e $file)
		{
		PrintError("PBS: Error: Pbsfile '$file' and PBSFILE_CONTENT can't be used simultaneously.\n") ;
		die ;
		}
	
	if(exists $pbs_config->{PBSFILE_CONTENT})
		{
		$file_body = $pbs_config->{PBSFILE_CONTENT} ;
		}
	}
	
if($file_body eq '')
	{
	open(FILE, '<', $file) or die "LoadFileInPackage: Error opening $file: $!\n" ;
	
	local $/ = undef ;
	$file_body .= <FILE> ;
	close(FILE) ;
	}

PrintDebug <<OPF if defined ($pbs_config->{DISPLAY_PBSFILE_ORIGINAL_SOURCE}) ;
#>>>>> start of original file '$file'
$file_body
#<<<<< end of original file '$file'

OPF

my $source = <<EOS ;
#>>>>> start of file '$file'

#line 0 '$file'
package $package ;
$pre_code

#line 1 '$file' 
$file_body
$post_code
#<<<<< end of file '$file'

EOS

PrintDebug $source if defined ($pbs_config->{DISPLAY_PBSFILE_SOURCE}) ;

my $result = eval $source ;

if($@)
	{
	PrintError "\nException:                    \n\tFile: '$file'\n\tPackage: '$package'\n\tException: $@" ;
	die "\n";
	}
	
$type .= ': ' unless $type eq '' ;

if((!defined $result) || ($result != 1))
	{
	$result ||= 'undef' ;
	die "PBS: Error: $type$file didn't return OK [$result] (did you forget '1 ;' at the last line?)\n"  ;
	}
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::PBS - Perl Build System.

=head1 SYNOPSIS

	# from pbs.pl
	
	use PBS::PBS ;
	PBS::PBS::Pbs
		(
		[$pbs_config->{PBSFILE}],
		'ROOT',
		$pbs_config->{PBSFILE},
		'',    # parent package
		$pbs_config,
		{},    # parent config
		$targets,
		undef, # inserted files
		"root_pbs_$pbs_config->{PBSFILE}", # tree name
		DEPEND_CHECK_AND_BUILD,
		) ;

=head1 DESCRIPTION

Entry point to B<PBS>. Calls PBS::DefaultBuild::DefaultBuild() if no user defined I<build()> exists in the I<Pbsfile>.

=head2 EXPORT

I<PbsUse> imports module within the current package. In B<PBS> case, it imports it in the load package of the I<Pbsfile>.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut

