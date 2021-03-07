
package PBS::PBS ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
#$Data::TreeDumper::Displaycallerlocation++ ;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Spec::Functions qw(:ALL) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(PbsUse pbsuse Use) ;
our $VERSION = '0.03' ;

use PBS::PBSConfig ;
use PBS::Output ;
use PBS::DefaultBuild ;
use PBS::Config ;
use PBS::Constants ;

use Digest::MD5 qw(md5_hex) ;
use String::Truncate ;
use File::Slurp ;
use File::Basename ;
use File::Path ;
use List::Util qw(any) ;

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
my (undef, undef, undef, undef, $pbs_config) = @_ ;

if(!$pbs_config->{DEPEND_LOG})
	{
	_Pbs(@_) ;
	}
else
	{
	my ($pbsfile_chain, $pbsfile_rule_name, $Pbsfile, $parent_package, $pbs_config, $parent_config, $targets, $inserted_nodes, $dependency_tree_name, $depend_and_build) = @_ ;

	my $package = CanonizePackageName($pbs_config->{PACKAGE}) ;
	my $redirection_file = $pbs_config->{BUILD_DIRECTORY} . "/$targets->[0]" ; 
	$redirection_file =~ s/\/\.\//\//g ;

	my ($basename, $path, $ext) = File::Basename::fileparse($redirection_file, ('\..*')) ;

	mkpath($path) unless(-e $path) ;

	$redirection_file = $path . '/.' . $basename . $ext . ".$package.pbs_depend_log" ;

	open my $OLDOUT, ">&STDOUT" ;

	local *STDOUT unless $pbs_config->{DEPEND_LOG_MERGED} ;

	open STDOUT,  "|-", " tee $redirection_file" or die "Can't redirect STDOUT to '$redirection_file': $!";
	STDOUT->autoflush(1) ;

	open my $OLDERR, ">&STDERR" ;
	open STDERR, '>>&STDOUT' ;

	my @result ;

	eval { @result = _Pbs(@_) } ;

	open STDERR, '>&' . fileno($OLDERR) or die "Can't restore STDERR: $!";
	open STDOUT, '>&' . fileno($OLDOUT) or die "Can't restore STDOUT: $!";

	die $@ if $@ ;
	return @result ;
	}
}

sub _Pbs
{
my $t0 = [gettimeofday];
$PBS::Output::indentation_depth++ ;
$pbs_runs++ ;

my 	
	(
	$pbsfile_chain, $pbsfile_rule_name, $Pbsfile, $parent_package, $pbs_config,
	$parent_config, $targets, $inserted_nodes, $dependency_tree_name, $depend_and_build,
	) = @_ ;

$pbsfile_chain //= [] ;

#remove local changes from previous level
$pbs_config = $pbs_config->{GLOBAL_PBS_CONFIG} if exists $pbs_config->{GLOBAL_PBS_CONFIG} ;
delete $pbs_config->{GLOBAL_PBS_CONFIG} ;

# target specific options
my (%pbs_options_local, %pbs_options_global) ;
for my $pbs_option (@{$pbs_config->{PBS_QR_OPTIONS}})
	{
	for my $target (@{$targets})
		{
		if ($target =~ $pbs_option->{QR})
			{
			if($pbs_option->{LOCAL})
				{
				%pbs_options_local = ( %pbs_options_local, %{$pbs_option->{OPTIONS}} ) ;
				}
			else
				{
				%pbs_options_global = ( %pbs_options_global, %{$pbs_option->{OPTIONS}} ) ;
				}
			}
		}
	}

$pbs_config = { %$pbs_config, %pbs_options_global } if %pbs_options_global ;

if(%pbs_options_local)
	{
	$pbs_config->{GLOBAL_PBS_CONFIG} = $pbs_config ;
	$pbs_config = { %$pbs_config, %pbs_options_local }
	}
# << target specific options

my $package            = CanonizePackageName($pbs_config->{PACKAGE}) ;
my $build_directory    = $pbs_config->{BUILD_DIRECTORY} ;
my $source_directories = $pbs_config->{SOURCE_DIRECTORIES} ;
my $target_names       = join ', ', @$targets ;

# ENV
my $original_ENV_size = scalar(keys %ENV) ;

my $display_env = $pbs_config->{DISPLAY_ENVIRONMENT} && $pbs_runs == 1 ;

Say Warning3 "ENV: removing all variable except those matching: " . join( ', ', map { "'$_'" } @{$pbs_config->{KEEP_ENVIRONMENT}})
	if $pbs_config->{DISPLAY_ENVIRONMENT_KEPT} && $display_env ;

for my $variable (sort keys %ENV)
	{
	if(any { $variable =~ $_ } @{$pbs_config->{KEEP_ENVIRONMENT}})
		{
		Say Info2 "ENV: keeping '$variable' => '$ENV{$variable}'" if  $display_env ;
		}
	else
		{ 
		Say Warning3 "ENV: removing '$variable' => '$ENV{$variable}'" if !$pbs_config->{DISPLAY_ENVIRONMENT_KEPT} && $display_env ;
		delete $ENV{$variable} ;
		}
	}

my $ENV_size = scalar(keys %ENV) ;
my $ENV_removed = $original_ENV_size - $ENV_size ;

Say Info2 "ENV: kept: $ENV_size, removed: $ENV_removed" if $pbs_config->{DISPLAY_ENVIRONMENT_STAT} && $pbs_runs == 1 ;	

SaveConfig($targets, $Pbsfile, $pbs_config, $parent_config) if defined $pbs_config->{SAVE_CONFIG} ;

$pbs_config->{TARGETS} = [ map { file_name_is_absolute($_) || /^\.\// ? $_ : "./$_" } @$targets ] ;

my (undef, $target_path) = File::Basename::fileparse($targets->[0], ('\..*')) ;

$target_path =~ s/^\.\/// ; $target_path =~ s/\/$// ;

$pbs_config->{TARGET_PATH} = $pbs_config->{SET_PATH_REGEX} || $target_path ;

undef $pbs_config->{SET_PATH_REGEX};

$Pbs_runs{$package} //= 1  ;

my $load_package = $pbs_config->{LOAD_PACKAGE} = 'PBS::Runs::' . $package . '_' . $Pbs_runs{$package}++ ;

$inserted_nodes //= {} ;

if( any { $_ eq '.' } @{$pbs_config->{DISPLAY_PBS_CONFIGURATION}} )
	{
	SIT $pbs_config, "Package '$package:$Pbsfile' config:" ;
	}
else
	{
	for my $regex (@{$pbs_config->{DISPLAY_PBS_CONFIGURATION}})
		{
		for my $key ( grep { /$regex/ } sort keys %{ $pbs_config} )
			{
			if('' eq ref $pbs_config->{$key})
				{
				if(defined $pbs_config->{$key})
					{
					Say Info "$key: " . $pbs_config->{$key} ;
					}
				else
					{
					Say Info "$key: undef" ;
					}
				}
			else
				{
				SIT $pbs_config->{$key}, $key ;
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
my ($build_result, $build_message, $build_sequence) ;

if(-e $Pbsfile || defined $pbs_config->{PBSFILE_CONTENT})
	{
	# check target names
	for(@$targets)
		{
		if(/@/ > 1)
			{
			Say Error "PBS: Invalid composite target definition" ;
			die ;
			}
			
		if(/^(.*)@(.*)$/)
			{
			if(@$targets == 1)
				{
				$build_point = $1 ;
				}
			else
				{
				Say Error "PBS: Only one composite target is supported" ;
				die "\n" ;
				}
			}
		} 
		
	push @{$pbs_config->{RULE_NAMESPACES}}, ('BuiltIn', 'User') unless @{$pbs_config->{RULE_NAMESPACES}} ;
	push @{$pbs_config->{CONFIG_NAMESPACES}}, ('BuiltIn', 'User') unless @{$pbs_config->{CONFIG_NAMESPACES}} ;

	push my @rule_namespaces, @{$pbs_config->{RULE_NAMESPACES}} ;
	push my @config_namespaces, @{$pbs_config->{CONFIG_NAMESPACES}} ;
	
	PBS::PBSConfig::RegisterPbsConfig($load_package, $pbs_config) ;
	
	#Command defines
	PBS::Config::AddConfigEntry($load_package, 'COMMAND_LINE', '__PBS', 'Command line', %{$pbs_config->{COMMAND_LINE_DEFINITIONS}}) ;
	
	my $sub_config = PBS::Config::GetPackageConfig($load_package) ; # config with all layer
	
	PBS::Config::AddConfigEntry($load_package, 'PBS_FORCED', '__PBS_FORCED', 'PBS', 'TARGET_PATH' => $pbs_config->{TARGET_PATH}) ;
	
	# merge parent config
	PBS::Config::AddConfigEntry($load_package, 'PARENT', '__PBS', "parent: '$parent_package' [$target_names]", %{$parent_config}) ;
	
	my $config = ExtractConfig($sub_config, $pbs_config->{CONFIG_NAMESPACES}) ;

	SIT {$config}, "Config: before running '$Pbsfile' in  package '$package':"
		 if $pbs_config->{DISPLAY_CONFIGURATION_START}  ;
	
	my $add_pbsfile_digest = '' ;
	
	if(defined $pbs_config->{PBSFILE_CONTENT})
		{
		use Digest::MD5 qw(md5_hex) ;
		my $pbsfile_digest = md5_hex($pbs_config->{PBSFILE_CONTENT}) ;
		$add_pbsfile_digest = "PBS::Digest::AddVariableDependencies(PBSFILE => '$pbsfile_digest') ;\n"
		}
	
	eval 
		{
		LoadFileInPackage
			(
			'Pbsfile',
			$Pbsfile,
			$load_package,
			$pbs_config,
			"use strict ;\n"
			  . "use warnings ;\n"
			  . "use Data::TreeDumper;\n"
		  	  . "use PBS::PrfNop ;\n" # for sub AddTargets
			  . "use PBS::Constants ;\n"
			  . "use PBS::Output ;\n"
			  . "use PBS::Rules ;\n"
			  . "use PBS::Rules::Scope ;\n"
			  . "use PBS::Triggers ;\n"
			  . "use PBS::PostBuild ;\n"
			  . "use PBS::Config ;\n"
			  . "use PBS::PBS ;\n"
			  . "use PBS::Caller ;\n"
			  . "use PBS::Digest;\n"
			  . "use PBS::PBSConfig ;\n"
			  . $add_pbsfile_digest,
			  
			"1 ;\n",
			) ;
		} ;

	die "\n" if $@ ;
	
	my @targets = map { file_name_is_absolute($_) || /^\.\// ? $_ : "./$_" } @$targets ;

	{
	use PBS::Caller ;
	my $c = CC 0, [$load_package, 'TARGET', '' ] ;

	PBS::Rules::RegisterRule
		(
		$pbs_config,
		$config,
		'BuiltIn',
		[VIRTUAL, '__INTERNAL'],
		$pbs_runs < 2 ? 'PBS' : 'SUBPBS',
		sub { $_[0] eq $dependency_tree_name ? (1, @targets) : 0 },
		) ;
	}

	($build_result, $build_message, $build_sequence)
		= PBS::DefaultBuild::DefaultBuild
			(
			$pbsfile_chain,
			$Pbsfile,
			$package,
			$load_package,
			$pbs_config,
			\@rule_namespaces,
			PBS::Rules::GetPackageRules($load_package),
			\@config_namespaces,
			$sub_config,
			$targets, # automatically build in rule 'BuiltIn::__ROOT', given as information only
			$inserted_nodes,
			$dependency_tree,
			$build_point,
			$depend_and_build,
			) ;
		
	$PBS::Output::indentation_depth-- ;

	# save meso file here
	}
else
	{
	my $error = "PBS: error: no pbsfile: $Pbsfile" ;
	$error .= "\n\t@ $pbs_config->{SUBPBS_HASH}{ORIGIN}" if defined $pbs_config->{SUBPBS_HASH}{ORIGIN};

	Print Error $error ;
	die "\n";
	}

return($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;
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

Say Info "Config: saved in '$config_file_name'" ;

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

my ($source_name, $global_package_dependency) = @_ ;
$global_package_dependency //= 1 ;

if (! defined $source_name || '' ne ref $source_name)
	{
	Say Error "PbsUse: Invalid call @ $file_name:$line"  ;
	die "\n" ;
	}
	
my $t0 = [gettimeofday];

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $located_source_name ;

$source_name .= '.pm' unless $source_name =~ /\.pm$/ ;

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
	unless(defined $pbs_config->{LIB_PATH})
		{
		Say Error "PBS: Can't search for '$source_name', PBS lib path is not defined" ;
		die "\n" ;
		}

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
	
	die ERROR("PBS: Can't locate '$source_name' in PBS libs [$paths] @ $file_name:$line.") . "\n" ;
	}

$pbs_use_level++ ; # indent the PbsUse output to make the hierarchy more visible
my $indentation = '   ' x $pbs_use_level ;

Say Info2 "${indentation}PbsUse: '$located_source_name' called at '$file_name:$line'" if defined $pbs_config->{DISPLAY_PBSUSE_VERBOSE} ;
Say Info2 "${indentation}PbsUse: '$source_name'" if defined $pbs_config->{DISPLAY_PBSUSE} ;

if(exists $files_loaded_via_PbsUse{$package}{$located_source_name})
	{
	my $load_information = join(':', $package, $file_name, $line) ;
	my $previous_load_information = join(':', @{$files_loaded_via_PbsUse{$package}{$located_source_name}}) ;


	Say Warning sprintf("PbsUse: '$source_name' load command ignored[$load_information]! Was already loaded at $previous_load_information") ;
	}
else
	{
	my $add_as_package_dependency = '' ;
	
	$add_as_package_dependency = "PBS::Digest::AddPbsLibDependencies('$located_source_name', '$source_name') ;\n"
		if $global_package_dependency ;
		
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

	die ERROR("PBS: pbsUse error @ $file_name:$line:\n\n$@\n") . "\n"
		if $@ ;

	$files_loaded_via_PbsUse{$package}{$located_source_name} = [$package, $file_name, $line];
	}

$pbs_use_level-- ;

my $pbsuse_time = tv_interval($t0, [gettimeofday]) ;

if(defined $pbs_config->{DISPLAY_PBSUSE_TIME})
	{
	if(defined $pbs_config->{DISPLAY_PBSUSE_TIME_ALL})
		{
		Say Info sprintf("${indentation}Time in PbsUse '$source_name': %0.2f s.", $pbsuse_time) ;
		}
	else
		{
		if(-1 == $pbs_use_level)
			{
			Say Info sprintf("${indentation}Time in PbsUse: %0.2f s.\n", $pbsuse_time) ;
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

*pbsuse = \&PbsUse ;
*Use = \&PbsUse ;

#-------------------------------------------------------------------------------

sub GetPbsUseStatistic
{
return defined $files_loaded_via_PbsUse{__STATISTIC}
	? DumpTree($files_loaded_via_PbsUse{__STATISTIC}, "PBS: 'PbsUse' statistic:", DISPLAY_ADDRESS => 0)
	: "PBS: 'PbsUse' statistic: not used\n" ;
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

my $t0 = [gettimeofday];

if($type eq 'Pbsfile')
	{
	my $available = PBS::Output::GetScreenWidth() ;
	my $em = String::Truncate::elide_with_defaults({ length => ($available - 12 < 3 ? 3 : $available - 12), truncate => 'left' });

	Print Info "\n" if $pbs_config->{DISPLAY_DEPEND_NEW_LINE} ;
	Say Info2 "PBS: loading '" . $em->($file) if defined $pbs_config->{DISPLAY_PBSFILE_LOADING} ;
	
	Say Warning "PBS: using virtual pbsfile"
		if defined $pbs_config->{PBSFILE_CONTENT} && -e $file ;
	
	$file_body = $pbs_config->{PBSFILE_CONTENT}
		if exists $pbs_config->{PBSFILE_CONTENT} ;
	}
	
if($file_body eq '')
	{
	if(defined $file)
		{
		open(FILE, '<', $file) or die ERROR("PBS: error opening '$file': $!") . "\n" ;
		
		local $/ = undef ;
		$file_body .= <FILE> ;
		close(FILE) ;
		}
	else
		{
		die  ERROR("LoadFileInPackage: no file name") . "\n" ;
		}
	}

$pbs_config->{SHORT_DEPENDENCY_PATH_STRING} //= '' ;
$pbs_config->{TARGET_PATH} //= '' ;

Print Debug <<OPF if defined ($pbs_config->{DISPLAY_PBSFILE_ORIGINAL_SOURCE}) ;
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

Print Debug $source if defined ($pbs_config->{DISPLAY_PBSFILE_SOURCE}) ;

my @warnings ;
local $SIG{__WARN__} = sub { push @warnings, $_[0] } ;

my $result = eval $source ;

if($@)
	{
	# recompile with short name to get a more compact display
	my $short_file = GetRunRelativePath($pbs_config, $file) ;

	my $indent = $PBS::Output::indentation ;

	Print Error "\nPBS: error loading '" . GetRunRelativePath($pbs_config, $file)
			. "\n\n"
			. (join '', map { s/$file/$short_file/g ;  "$indent$_\n" } map{ split(/\n/, $_) } @warnings)
			. (join '', map {s/$file/$short_file/g ; "$indent$_\n" } split(/\n/, $@)) ;
	die "\n";
	}
	
Say Info2 sprintf("PBS: load time: %0.4f.s", tv_interval ($t0, [gettimeofday]))
	if $pbs_config->{DISPLAY_PBSFILE_LOAD_TIME} && $type eq 'Pbsfile' ;

$type .= ': ' unless $type eq '' ;

if((!defined $result) || ($result != 1))
	{
	$result ||= 'undef' ;
	die ERROR("PBS: $type$file didn't return OK [$result]") . "\n"  ;
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

