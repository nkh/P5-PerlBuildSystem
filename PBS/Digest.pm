
package PBS::Digest;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Carp ;
use Data::Compare;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::Spec::Functions qw(:ALL) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(
		AddPbsLibDependencies
		AddFileDependencies           AddNodeFileDependencies
		AddEnvironmentDependencies    AddNodeEnvironmentDependencies
		AddVariableDependencies       AddNodeVariableDependencies
		AddConfigVariableDependencies AddNodeConfigVariableDependencies
		AddSwitchDependencies         AddNodeSwitchDependencies
		
		ExcludeFromDigestGeneration   NoDigest
		ForceDigestGeneration         GenerateNodeDigest
		GetDigest
		
		GetFileMD5
		) ;
					
our $VERSION = '0.06' ;
our $display_md5_flush = 0 ;
our $display_md5_compute = 0 ;
our $display_md5_time = 0 ;

use PBS::PBSConfig ;
use PBS::Output ;

#-------------------------------------------------------------------------------

my %package_dependencies ;
my %package_config_variable_dependencies ;

my %node_digest_rules ;
my %node_config_variable_dependencies ;

my %exclude_from_digest ;
my %force_digest ;

#-------------------------------------------------------------------------------
# cached MD5 functions
#-------------------------------------------------------------------------------

my %md5_cache ;
my $cache_hits = 0 ;
my $md5_requests = 0 ;
my $md5_time = 0 ;
my $non_cached_md5_request = 0 ;

sub Get_MD5_Statistics
{
my $md5_cache_hit_ratio = 'N/A' ;

if($md5_requests)
	{
	$md5_cache_hit_ratio = int(($cache_hits * 100) / $md5_requests) ;
	}
	
return
	{
	TOTAL_MD5_REQUESTS  => $md5_requests,
	NON_CACHED_REQUESTS => $non_cached_md5_request,
	CACHE_HITS          => $cache_hits,
	MD5_CACHE_HIT_RATIO => $md5_cache_hit_ratio,
	MD5_TIME            => $md5_time,
	} ;
}

sub FlushMd5Cache
{
my $file = shift ;

if(defined $file)
	{
	delete $md5_cache{$file} ;
	PrintWarning sprintf "Digest: hash cache flush: $file\n" if $display_md5_flush ;
	}
else
	{
	%md5_cache = () ;
	PrintError  "Digest: hash cache flush all.\n" if $display_md5_flush ;
	}
}

sub FlushMd5CacheMulti
{
my $files = shift ;

for my $file (@$files)
	{
	if(defined $file)
		{
		FlushMd5Cache($file) ;
		}
	}
}

sub GetMd5Cache
{
return \%md5_cache ;
}

sub PopulateMd5Cache
{
my $hash = shift ;
%md5_cache = (%md5_cache, %$hash) ;
}

sub ClearMd5Cache
{
%md5_cache = () ;
}

#-------------------------------------------------------------------------------

sub GetFileMD5
{
#  this one caching too.
my $file = shift or carp ERROR "GetFileMD5: Called without argument!\n" ;
my $warn = shift // 1 ;

my $md5 = 'invalid md5' ;
my $t0_md5 = [gettimeofday] ;

$md5_requests++ ;
if(exists $md5_cache{$file})
	{
	$md5 = $md5_cache{$file}  ;
	$cache_hits++ ;
	}
else
	{
	if(defined ($md5 = NonCached_GetFileMD5($file)) && $md5 ne 'invalid md5')
		{
		$md5_cache{$file} = $md5 ;

		my $time = tv_interval($t0_md5, [gettimeofday]) ;
		PrintInfo2(sprintf "Digest: [" . (scalar(keys %md5_cache)) . "] %.6f s., $md5, $file\n", $time) if $display_md5_time ;

		my $md5_time += $time ;
		}
	else
		{
		PrintWarning  "Digest: Warning: can't read file '$file' to generate MD5\n" if $warn ;
		}
	}

return($md5) ;
}

#-------------------------------------------------------------------------------
# non cached MD5 functions
#-------------------------------------------------------------------------------

sub NonCached_GetFileMD5
{

$non_cached_md5_request++ ;

if($ENV{PBS_USE_XX_HASH})
	{
	xx_NonCached_GetFileMD5(@_) ;
	}
else
	{
	md5_NonCached_GetFileMD5(@_) ;
	}
}


sub md5_NonCached_GetFileMD5
{
my $file_name = shift or carp ERROR "GetFileMD5: Called without argument!\n" ;

use IO::File ;
my $fh = new IO::File ;

my $t0_md5 = [gettimeofday] ;

if(-f $file_name && $fh->open($file_name))
	{
	$fh->binmode();
	my $md5sum = Digest::MD5->new->addfile($fh)->hexdigest ;
	undef $fh ;
	
	my $time = tv_interval($t0_md5, [gettimeofday]) ;
	PrintUser(sprintf "Digest: compute MD5, time: %.6f, hash: $md5sum, file: $file_name\n", $time) if $display_md5_compute ;

	return $md5sum // 'invalid md5' ;
	}
else
	{
	return 'invalid md5' ;
	}
}

#-------------------------------------------------------------------------------

use Digest::xxHash qw[xxhash32 xxhash32_hex xxhash64 xxhash64_hex];
use File::Slurp ;

sub xx_NonCached_GetFileMD5
{
my $file_name = shift or carp ERROR "GetFileMD5: Called without argument!\n" ;

my $t0_md5 = [gettimeofday] ;

if(-f $file_name)
	{
	my $bin = read_file( $file_name, { binmode => ':raw' } ) ;

	my $md5sum = xxhash32_hex($bin, 'PBS_xxHash') ;
	
	my $time = tv_interval($t0_md5, [gettimeofday]) ;
	PrintUser(sprintf "Digest: compute XXHash, time: %.6f, hash: $md5sum, file: $file_name\n", $time) if $display_md5_compute ;

	return $md5sum // 'invalid md5' ;
	}
else
	{
	return 'invalid md5' ;
	}
}

#-------------------------------------------------------------------------------

sub GetPackageDigest
{
my $package = shift || caller() ;

my %config_variables ;

if (exists $package_config_variable_dependencies{$package})
	{
	my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
	my %config = PBS::Config::ExtractConfig
			(
			PBS::Config::GetPackageConfig($package),
			$pbs_config->{CONFIG_NAMESPACES},
			) ;

	#~ PrintDebug DumpTree(\%config, "config for package '$package':") ;
	
	for my $key (keys %{$package_config_variable_dependencies{$package}})
		{
		$config_variables{"__CONFIG_VARIABLE:$key"} = $config{$key} ;
		}
	}
	
if(exists $package_dependencies{$package})
	{
	return({ %{$package_dependencies{$package}}, %config_variables}) ;
	}
else
	{
	return( {%config_variables} );
	}
}

#-------------------------------------------------------------------------------

sub AddFileDependencies
{
my @files = @_ ;

my $package = caller() ;

for (@files)
	{
	my $file_name = $_ ;
	
	$file_name = "__FILE:$file_name" ;
		
	$package_dependencies{$package}{$file_name} = GetFileMD5($_) ;
	}
}

#-------------------------------------------------------------------------------

sub AddPbsLibDependencies
{
my ($file_name,	$lib_name) = @_ ;

my $package = caller() ;

$lib_name = "__PBS_LIB_PATH/$lib_name" ;

$package_dependencies{$package}{$lib_name} = GetFileMD5($file_name) ;
}

#-------------------------------------------------------------------------------

sub AddVariableDependencies 
{
my $package = caller() ;
while(my ($variable_name, $value) = splice(@_, 0, 2))
      {
      $package_dependencies{$package}{"__VARIABLE:$variable_name"} = $value ;
      }
}

#-------------------------------------------------------------------------------

sub AddEnvironmentDependencies 
{
my $package = caller() ;

for (@_)
	{
	if(exists $ENV{$_})
		{
		$package_dependencies{$package}{"__ENV:$_"} = $ENV{$_} ;
		}
	else
		{
		$package_dependencies{$package}{"__ENV:$_"} = '' ;
		}
	}
}

#-------------------------------------------------------------------------------

sub AddSwitchDependencies
{
my $package = caller() ;
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

for (@_)
	{
	if(/^\s*-D\s*(\w+)/)
		{
		if(exists $pbs_config->{COMMAND_LINE_DEFINITIONS}{$1})
			{
			$package_dependencies{$package}{"__SWITCH:$1"} = $pbs_config->{COMMAND_LINE_DEFINITIONS}{$1} ;
			}
		else
			{
			$package_dependencies{$package}{"__SWITCH:$1"} = '' ;
			}
		}

	if(/^\s*-D\s*\*/)
		{
		for (keys %{$pbs_config->{COMMAND_LINE_DEFINITIONS}})
			{
			$package_dependencies{$package}{"__SWITCH:$_"} = $pbs_config->{COMMAND_LINE_DEFINITIONS}{$_} ;
			}
		}

	if(/^\s*-u\s*(\w+)/)
		{
		if(exists $pbs_config->{USER_OPTIONS}{$1})
			{
			$package_dependencies{$package}{"__SWITCH:$1"} = $pbs_config->{USER_OPTIONS}{$1} ;
			}
		else
			{
			$package_dependencies{$package}{"__SWITCH:$1"} = '' ;
			}
		}

	if(/^\s*-u\s*\*/)
		{
		for (keys %{$pbs_config->{USER_OPTIONS}})
			{
			$package_dependencies{$package}{"__SWITCH:$_"} = $pbs_config->{USER_OPTIONS}{$_} ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub AddConfigVariableDependencies 
{
my $package = caller() ;

for my $config_variable (@_)
	{
	$package_config_variable_dependencies{$package}{$config_variable}++ ; 
	}
}

#-------------------------------------------------------------------------------

sub GetNodeDigestNoChildren
{
my ($node) = @_ ;

my $node_name = $node->{__NAME} ;
my $node_package = $node->{__LOAD_PACKAGE} // '?' ;
my %node_config = %{$node->{__CONFIG} // {}} ;

my %node_dependencies ;
for my $rule (@{$node_digest_rules{$node_package}})
	{
	$node_dependencies{$rule->{NAME}} = $rule->{VALUE}
		if($node_name =~ $rule->{REGEX}) ;
	}

if(exists $node_config_variable_dependencies{$node_package})
	{
	for (@{$node_config_variable_dependencies{$node_package}})
		{
		$node_dependencies{"__NODE_CONFIG_VARIABLE:$_->{CONFIG_VARIABLE}"} = $node_config{$_->{CONFIG_VARIABLE}}
			if($node_name =~ $_->{REGEX}) ;
		}
	}

return \%node_dependencies ;
}
	
sub GetNodeDigest
{
my ($node) = @_ ;

my %node_dependencies = %{GetNodeDigestNoChildren($node)} ;

# add node children to digest
for my $entry (values %$node)
	{
	next unless 'HASH' eq ref $entry ;
	next unless exists $entry->{__NAME} ;

	my $dependency = $entry ;
	my $dependency_name = $dependency->{__NAME} ;

	next if $dependency_name =~ /^__/ ;

	if(exists $dependency->{__VIRTUAL})
		{
		$node_dependencies{$dependency_name} = 'VIRTUAL' ;
		}
	else
		{
		$node_dependencies{$dependency_name} = GetFileMD5($dependency->{__BUILD_NAME}) ;
		}
	}

my $pbsfile = $node->{__INSERTED_AT}{INSERTION_FILE} ;
$node_dependencies{$pbsfile} = GetFileMD5($pbsfile) ;

return(\%node_dependencies) ;
}

#-------------------------------------------------------------------------------

sub AddNodeFileDependencies
{
my $node_regex = shift ;
my @files      = @_ ;

my $package = caller() ;

for my $file_name (@files)
	{
	push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_FILE:$file_name", VALUE => GetFileMD5($file_name)} ;
	}
}

#-------------------------------------------------------------------------------

sub AddNodeEnvironmentDependencies
{
my $node_regex = shift ;
my $package = caller() ;

for (@_)
	{
	if(exists $ENV{$_})
		{
		push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_ENV:$_", VALUE => $ENV{$_}} ;
		}
	else
		{
		push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_ENV:$_", VALUE => ''} ;
		}
	}
}

#-------------------------------------------------------------------------------

sub AddNodeSwitchDependencies
{
my $node_regex = shift ;

my $package    = caller() ;
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

for (@_)
	{
	if(/^\s*-D\s*(\w+)/)
		{
		if(exists $pbs_config->{COMMAND_LINE_DEFINITIONS}{$1})
			{
			push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_SWITCH:$1", VALUE => $pbs_config->{COMMAND_LINE_DEFINITIONS}{$1}} ;
			}
		else
			{
			push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_SWITCH:$1", VALUE => ''} ;
			}
		}

	if(/^\s*-D\s*\*/)
		{
		for (keys %{$pbs_config->{COMMAND_LINE_DEFINITIONS}})
			{
			push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_SWITCH:$_", VALUE => $pbs_config->{COMMAND_LINE_DEFINITIONS}{$_}} ;
			}
		}

	if(/^\s*-u\s*(\w+)/)
		{
		if(exists $pbs_config->{USER_OPTIONS}{$1})
			{
			push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_SWITCH:$1", VALUE => $pbs_config->{USER_OPTIONS}{$1}} ;
			}
		else
			{
			push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_SWITCH:$1", VALUE => ''} ;
			}
		}

	if(/^\s*-u\s*\*/)
		{
		for (keys %{$pbs_config->{USER_OPTIONS}})
			{
			push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_SWITCH:$_", VALUE => $pbs_config->{USER_OPTIONS}{$_}} ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub AddNodeConfigVariableDependencies
{
my $node_regex = shift ;
my $package    = caller() ;

for my $config_variable_name (@_)
	{
	push @{$node_config_variable_dependencies{$package}}, {REGEX => $node_regex, CONFIG_VARIABLE => $config_variable_name} ;
	}
}

#-------------------------------------------------------------------------------

sub AddNodeVariableDependencies 
{
my $node_regex = shift ;
my $package    = caller() ;

while(my ($variable_name, $value) = splice(@_, 0, 2))
	{
	push @{$node_digest_rules{$package}}, {REGEX => $node_regex, NAME => "__NODE_VARIABLE:$variable_name", VALUE => $value} ;
	}
}

#-------------------------------------------------------------------------------

sub NoDigest
{
my ($package, $file_name, $line) = caller() ;

_ExcludeFromDigestGeneration($package, $file_name, $line, map { ; "$_" => $_ } @_ ) ;
}

sub ExcludeFromDigestGeneration
{
my ($package, $file_name, $line) = caller() ;

die ERROR "Invalid 'ExcludeFromDigestGeneration' arguments at $file_name:$line\n" if @_ % 2 ;

_ExcludeFromDigestGeneration($package, $file_name, $line, @_) ;
}

sub _ExcludeFromDigestGeneration
{
my ($package, $file_name, $line, %exclusion_patterns) = @_ ;
 
for my $name (keys %exclusion_patterns)
	{
	if(exists $exclude_from_digest{$package}{$name})
		{
		PrintWarning
			(
			"Digest: overriding ExcludeFromDigest entry '$name' defined at $exclude_from_digest{$package}{$name}{ORIGIN}:\n"
			. "\t$exclude_from_digest{$package}{$name}{PATTERN} "
			. "with $exclusion_patterns{$name} defined at $file_name:$line\n"
			) ;
		}
		
	$exclude_from_digest{$package}{$name} = {PATTERN => $exclusion_patterns{$name}, ORIGIN => "$file_name:$line"} ;
	}
}

#-------------------------------------------------------------------------------

sub ForceDigestGeneration
{
my ($package, $file_name, $line) = caller() ;

die ERROR "Invalid 'ForceDigestGeneration' arguments at $file_name:$line\n" if @_ % 2 ;

my %force_patterns = @_ ;
for my $name (keys %force_patterns)
	{
	if(exists $force_digest{$package}{$name})
		{
		PrintWarning
			(
			"Digest: overriding ForceDigestGeneration entry '$name' defined at $force_digest{$package}{$name}{ORIGIN}:\n"
			. "\t$force_digest{$package}{$name}{PATTERN} "
			. "with $force_patterns{$name} defined at $file_name:$line\n"
			) ;
		}
		
	$force_digest{$package}{$name} = {PATTERN => $force_patterns{$name}, ORIGIN => "$file_name:$line"} ;
	}
}

#-------------------------------------------------------------------------------

sub IsDigestToBeGenerated
{
my ($package, $node) = @_ ;

my $node_name  = $node->{__NAME} ;
my $pbs_config = $node->{__PBS_CONFIG} ;

my $generate_digest = 1 ;

for my $name (keys %{$exclude_from_digest{$package}})
	{
	if($node_name =~ $exclude_from_digest{$package}{$name}{PATTERN})
		{
		if(defined $pbs_config->{DISPLAY_DIGEST_EXCLUSION})
			{
			PrintWarning "Digest: '$node_name' no digest, rule: '$name', pattern: '$exclude_from_digest{$package}{$name}{PATTERN}'"
					. INFO2(", file: $exclude_from_digest{$package}{$name}{ORIGIN}\n", 0)  ;
			}
			
		$generate_digest = 0 ;
		last ;
		}
	}

for my $name (keys %{$force_digest{$package}})
	{
	if($node_name =~ $force_digest{$package}{$name}{PATTERN})
		{
		if(defined $pbs_config->{DISPLAY_DIGEST_EXCLUSION})
			{
			PrintWarning "Digest: '$node_name' forced digest, rule: '$name', pattern: '$force_digest{$package}{$name}{PATTERN}'"
					. INFO2(", file: $force_digest{$package}{$name}{ORIGIN}\n", 0) ;
			}
			
		$generate_digest = 1 ;
		last ;
		}
	}

return($generate_digest) ;
}

#-------------------------------------------------------------------------------

sub DisplayAllPackageDigests
{
warn DumpTree(\%package_dependencies, "All package digests:") ;
}

#-------------------------------------------------------------------------------

sub GetAllPackageDigests
{
return(\%package_dependencies) ;
}

#-------------------------------------------------------------------------------

sub IsNodeDigestDifferent
{
my $node = shift ;

return
	(
	CompareExpectedDigestWithDigestFile($node, \&CompareDigests)
	) ;
}

#-------------------------------------------------------------------------------

sub IsNodeDigestIncluded
{
my $node = shift ;

return
	(
	CompareExpectedDigestWithDigestFile($node, \&DigestIsIncluded)
	) ;
}

#-------------------------------------------------------------------------------

sub CompareExpectedDigestWithDigestFile
{
my $node = shift ;
my $comparator = shift ;

my $digest_file_name = GetDigestFileName($node) ;

my $pbs_config = $node->{__PBS_CONFIG} ;
my $package = $node->{__LOAD_PACKAGE} ;

my ($rebuild_because_of_digest, $result_message, $number_of_differences) = (0, 'digest OK', 0) ;

if(IsDigestToBeGenerated($package, $node))
	{
	if(-e $digest_file_name)
		{
		my $current_md5 ;
		
		unless(defined ($current_md5 = GetFileMD5($node->{__BUILD_NAME})))
			{
			$current_md5 = "Can't open '$node->{__BUILD_NAME}' to compute MD5 digest: $!" ;
			}
			
		my $node_digest = 
			{
			%{GetPackageDigest($node->{__LOAD_PACKAGE})},
			%{GetNodeDigest($node)},
			$node->{__NAME} => $current_md5,
			__DEPENDING_PBSFILE => $node->{__DEPENDING_PBSFILE},
			} ;
			
		my $digest ;
		unless (($digest) = do $digest_file_name) 
			{
			warn "couldn't parse '$digest_file_name': $@" if $@;
			}
			
		if('HASH' eq ref $digest)
			{
			my ($digest_is_different, $why) =
				$comparator->
					(
					$pbs_config,
					$node->{__BUILD_NAME},
					$node_digest,
					$digest,
					) ;
					
			if($digest_is_different)
				{
				($rebuild_because_of_digest, $result_message, $number_of_differences) = (1, $why, scalar @{$why} ) ;
				}
			}
		else
			{
			($rebuild_because_of_digest, $result_message, $number_of_differences) = (1, ['Empty digest'], 1) ;
			}
		}
	else
		{
		PrintWarning("Digest: file '$digest_file_name' not found.\n") if(defined $pbs_config->{DISPLAY_DIGEST}) ;
		($rebuild_because_of_digest, $result_message, $number_of_differences) = (1, ["Digest file '$digest_file_name' not found"], 1) ;
		}
	
	}
else
	{
	($rebuild_because_of_digest, $result_message) = (0, ['Excluded from digest'], 0) ;
	}
	
return($rebuild_because_of_digest, $result_message, $number_of_differences) ;
}

#-------------------------------------------------------------------------------

sub IsFileModified
{
my ($pbs_config, $file, $md5) = @_ ;
$md5 //= "undefined" ;

my $file_is_modified = 0;

if(defined $pbs_config->{DEBUG_TRIGGER_NONE})
	{
	my $trigger_match = 0 ;
	for my $trigger_regex (@{$pbs_config->{TRIGGER}})
		{
		if($file =~ /$trigger_regex/)
			{
			PrintUser "Trigger: '$file' matches /$trigger_regex/ (digest)\n" if $pbs_config->{DEBUG_DISPLAY_TRIGGER} ;
			$trigger_match++ ;
			$file_is_modified++ ;

			PrintDebug "\nCheck: --triger match: $file\n" if $pbs_config->{DISPLAY_FILE_CHECK} ;

			last ;
			}
		}

	PrintInfo2 "Trigger: '$file' not triggered (digest check)\n" if ! $trigger_match && $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY};
	}
else
	{
	if(defined (my $current_md5 = GetFileMD5($file, ! $pbs_config->{WARP_NO_DISPLAY_DIGEST_FILE_NOT_FOUND} )))
		{
		unless($current_md5 eq $md5)
			{
			PrintDebug "\nDigest: check hash, got '$current_md5', expected '$md5' for '$file'\n"
				if $pbs_config->{DISPLAY_FILE_CHECK} ;
				
			$file_is_modified++ ;
			}
		}
	else
		{
		PrintDebug "\nDigest: no such file '$file'\n"  if $pbs_config->{DISPLAY_FILE_CHECK} ;
		
		$file_is_modified++ ;
		}

	my $trigger_match = 0 ;
	for my $trigger_regex (@{$pbs_config->{TRIGGER}})
		{
		if($file =~ /$trigger_regex/)
			{
			PrintUser "Trigger: '$file' matches /$trigger_regex/ (digest)\n" if $pbs_config->{DEBUG_DISPLAY_TRIGGER} ;
			$trigger_match++ ;

			$file_is_modified++ ;

			PrintDebug "\nDigest: --triger match: $file\n"
				if $pbs_config->{DISPLAY_FILE_CHECK} ;

			last ;
			}
		}
	
	PrintInfo2 "Trigger: '$file' not trigger (digest check)\n" if ! $trigger_match && $pbs_config->{DEBUG_DISPLAY_TRIGGER} && ! $pbs_config->{DEBUG_DISPLAY_TRIGGER_MATCH_ONLY};
	}

return($file_is_modified) ;
}

#-------------------------------------------------------------------------------

sub CompareDigests
{
my ($pbs_config, $name, $expected_digest, $digest) = @_ ;

my ($display_digest, $display_different_digest_only) 
	= ($pbs_config->{DISPLAY_DIGEST}, $pbs_config->{DISPLAY_DIFFERENT_DIGEST_ONLY}) ;

my $digest_is_different = 0 ;

my @in_expected_digest_but_not_file_digest ;
my @in_file_digest_but_not_expected_digest ;
my @different_in_file_digest ;

for my $key( keys %$expected_digest)
	{
	if(exists $digest->{$key})
		{
		for my $trigger_regex (@{$pbs_config->{TRIGGER}})
			{
			if($key =~ /$trigger_regex/)
				{
				PrintUser "Trigger (digest_md5): $key =~ '$trigger_regex'\n" if $pbs_config->{DEBUG_DISPLAY_TRIGGER} ;
				$digest->{$key} = "--trigger match  '$trigger_regex'" ;

				last ;
				}
			}

		if
			(
			   (defined $digest->{$key} && ! defined $expected_digest->{$key})
			|| (! defined $digest->{$key} && defined $expected_digest->{$key})
			|| (
				   defined $digest->{$key} && defined $expected_digest->{$key} 
				&& (!Compare($digest->{$key}, $expected_digest->{$key}))
			   )
			)
			{
			push @different_in_file_digest, $key ;
			$digest_is_different++ ;
			}
		}
	else
		{
		push @in_expected_digest_but_not_file_digest, $key ;
		$digest_is_different++ ;
		}
	}
	
for my $key( keys %$digest)
	{
	unless(exists $expected_digest->{$key})
		{
		push @in_file_digest_but_not_expected_digest, $key ;
		$digest_is_different++ ;
		}
	}
	
my @digest_different_text ;

if($digest_is_different)
	{
	PrintWarning("Digest: file: $name differences [$digest_is_different]:\n") if($display_digest) ;
	
	for my $key (@in_file_digest_but_not_expected_digest)
		{
		my $digest_value = $digest->{$key} || 'undef' ;
		
		my $only_in_file_digest_text = "key '$key' exists only in old digest" ;
		push @digest_different_text, $only_in_file_digest_text ;
		
		PrintWarning("\t$only_in_file_digest_text.\n") if($display_digest) ;
		}
		
	for my $key (@different_in_file_digest)
		{
		my $digest_value = $digest->{$key} || 'undef' ;
		my $expected_digest_value = $expected_digest->{$key} || 'undef' ;
		
		my $different_digest_text = "$key: $digest_value != $expected_digest_value" ;
		push @digest_different_text, $different_digest_text ;
		
		PrintError("\t$different_digest_text\n") if($display_digest) ;
		}
		
	for my $key (@in_expected_digest_but_not_file_digest)
		{
		my $expected_digest_value = $expected_digest->{$key} || 'undef' ;
		
		my $only_in_expected_digest_text = "key '$key' exists only in expected digest" ;
		push @digest_different_text, $only_in_expected_digest_text ;
		
		PrintError("\t$only_in_expected_digest_text\n") if($display_digest) ;
		}
	}
else
	{
	my $digest_is_identical = "Digest: file '$name' no difference" ;
	push @digest_different_text, $digest_is_identical ;
	
	PrintInfo("$digest_is_identical\n") if($display_digest && ! $display_different_digest_only ) ;
	}

return($digest_is_different, \@digest_different_text);
}

#-------------------------------------------------------------------------------

sub DigestIsIncluded
{
my ($pbs_config, $name, $expected_digest, $digest) = @_ ;

my ($display_digest, $display_different_digest_only) 
	= ($pbs_config->{DISPLAY_DIGEST}, $pbs_config->{DISPLAY_DIFFERENT_DIGEST_ONLY}) ;

my $digest_is_different = 0 ;

my @in_expected_digest_but_not_file_digest ;
my @in_file_digest_but_not_expected_digest ;
my @different_in_file_digest ;

for my $key( keys %$expected_digest)
	{
	if(exists $digest->{$key})
		{
		if
			(
			   (defined $digest->{$key} && ! defined $expected_digest->{$key})
			|| (! defined $digest->{$key} && defined $expected_digest->{$key})
			|| (
				   defined $digest->{$key} && defined $expected_digest->{$key} 
				&& !Compare($digest->{$key}, $expected_digest->{$key})
			   )
			)
			{
			push @different_in_file_digest, $key ;
			$digest_is_different++ ;
			}
		}
	else
		{
		push @in_expected_digest_but_not_file_digest, $key ;
		$digest_is_different++ ;
		}
	}
	
my @digest_different_text ;

if($digest_is_different)
	{
	PrintWarning("Digest: file $name differences [$digest_is_different]:\n") if($display_digest) ;
	
	for my $key (@in_file_digest_but_not_expected_digest)
		{
		my $digest_value = $digest->{$key} || 'undef' ;
		
		my $only_in_file_digest_text = "key '$key' exists only in file digest" ;
		push @digest_different_text, $only_in_file_digest_text ;
		
		PrintWarning("\t$only_in_file_digest_text.\n") if($display_digest) ;
		}
		
	for my $key (@different_in_file_digest)
		{
		my $digest_value = $digest->{$key} || 'undef' ;
		my $expected_digest_value = $expected_digest->{$key} || 'undef' ;
		
		my $different_digest_text = "$key: $digest_value != $expected_digest_value" ;
		push @digest_different_text, $different_digest_text ;
		
		PrintError("\t$different_digest_text\n") if($display_digest) ;
		}
		
	for my $key (@in_expected_digest_but_not_file_digest)
		{
		my $expected_digest_value = $expected_digest->{$key} || 'undef' ;
		
		my $only_in_expected_digest_text = "key '$key' exists only in expected digest" ;
		push @digest_different_text, $only_in_expected_digest_text ;
		
		PrintError("\t$only_in_expected_digest_text\n") if($display_digest) ;
		}
	}
else
	{
	my $digest_is_identical = "Digests: file '$name' no differences" ;
	push @digest_different_text, $digest_is_identical ;
		
	PrintInfo("$digest_is_identical.\n") if($display_digest && ! $display_different_digest_only) ;
	}

return(!$digest_is_different, \@digest_different_text) ;
}

#-------------------------------------------------------------------------------

sub GetDigestFileName
{
my ($node) = @_ ;

my $file_name = $node->{__BUILD_NAME} // (PBS::Check::LocateSource($node->{__NAME}, $node->{__PBS_CONFIG}{BUILD_DIRECTORY}))[0] ;

my $digest_file_name = '' ;

my ($volume,$directories,$file) = splitpath($file_name);

if(file_name_is_absolute($node->{__NAME}))
	{
	my $build_directory = $node->{__PBS_CONFIG}{BUILD_DIRECTORY} ;

	$digest_file_name = "$build_directory/ROOT${directories}.$file.pbs_md5" ;
	}
else
	{
	$digest_file_name = "${directories}.$file.pbs_md5" ;
	}

return($digest_file_name) ;
}

#-------------------------------------------------------------------------------

my $generate_digest_time  = 0 ;
my $generate_digest_calls = 0 ;
my $generate_digest_write = 0 ;
my $generate_digest_get   = 0 ;
my $generate_digest_dump  = 0 ;


sub GetDigestGenerationStats
{
"Digest generation calls: $generate_digest_calls total: $generate_digest_time write: $generate_digest_write get:$generate_digest_get dumper:$generate_digest_dump\n" ;
}

sub GenerateNodeDigest
{
$generate_digest_calls++ ;
my $t0_generate_digest = [gettimeofday] ;
my $node = shift ;

my $digest_file_name = GetDigestFileName($node) ;

if(exists $node->{__VIRTUAL} && $node->{__VIRTUAL} == 1)
	{
	if(-e $digest_file_name)
		{
		PrintInfo("Digest: removing digest file: '$digest_file_name', node is virtual.\n") ;
		unlink($digest_file_name) ;
		}
		
	return() ;
	}

my $package = $node->{__LOAD_PACKAGE} ;

if(IsDigestToBeGenerated($package, $node))
	{
	my $t0_generate_write = [gettimeofday] ;

	my $sources = "my \$sources = {\n" ;

	for my $dependency (grep { ! /^__/ } keys %$node)
		{
		$sources .= "\t'$dependency' => 1,\n" unless IsDigestToBeGenerated($node->{__LOAD_PACKAGE}, $node->{$dependency}) ;
		}

	$sources .= "\t} ;\n" ;
	
	WriteDigest
		(
		$digest_file_name,
		"Pbsfile: $node->{__PBS_CONFIG}{PBSFILE}",
		GetDigest($node),
		$sources, # caller data to be added to digest
		1, # create path
		'return $digest, $sources ;' # postamble
		) ;

	$generate_digest_write += tv_interval($t0_generate_write, [gettimeofday]) ;
	}

$generate_digest_time += tv_interval($t0_generate_digest, [gettimeofday]) ;
}

#-------------------------------------------------------------------------------

sub GetDigest
{
my $t0_generate_digest_get = [gettimeofday] ;
my $node = shift ;

PrintDebug "Digest: node $node->{__NAME} doesn't have __DEPENDING_PBSFILE\n" unless exists $node->{__DEPENDING_PBSFILE} ;

# TODO: Add plugins to digest  map {$_ => GetFileMD5($_)} PBS::Plugin::GetLoadedPlugins(),
# TODO: Add pbs install to digest

my $package_digest = GetPackageDigest($node->{__LOAD_PACKAGE}) ;
my $node_digest = GetNodeDigest($node) ;
my $node_md5 = GetFileMD5($node->{__BUILD_NAME}) ;

my $d = { %$package_digest, %$node_digest, $node->{__NAME} => $node_md5, __DEPENDING_PBSFILE =>  $node->{__DEPENDING_PBSFILE}, } ;

$generate_digest_get += tv_interval($t0_generate_digest_get, [gettimeofday]) ;

return $d ;
}

#-------------------------------------------------------------------------------

use File::Path ;

sub WriteDigest
{
my ($digest_file_name, $caller_information, $digest, $caller_data, $create_path, $postamble) = @_ ;

$postamble //= '' ;

my $t0_generate_dump = [gettimeofday] ;
if($create_path)
	{
	my ($basename, $path, $ext) = File::Basename::fileparse($digest_file_name, ('\..*')) ;
	
	mkpath($path) unless(-e $path) ;
	}
	
open NODE_DIGEST, ">", $digest_file_name  or die ERROR("Can't open '$digest_file_name' for writting: $!") . "\n" ;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = "${mday}_${mon}_${hour}_${min}_${sec}" ;

my $HOSTNAME = $ENV{HOSTNAME} // 'no_host' ;
my $user = PBS::PBSConfig::GetUserName() ;

$caller_information = '' unless defined $caller_information ;
$caller_information =~ s/^/# /g ;

use PBS::Output ;
print NODE_DIGEST "\"\n" ;
print NODE_DIGEST INFO <<EOH ;
This file is automatically generated by PBS (Perl Build System).
Digest.pm version $VERSION

File: $digest_file_name
Date: $now_string 
User: $user @ $HOSTNAME
$caller_information
EOH
print NODE_DIGEST "\";\n\n" ;

print NODE_DIGEST "$caller_data\n" if defined $caller_data ;

$Data::Dumper::Sortkeys = 1 ;

print NODE_DIGEST Data::Dumper->Dump([$digest], ['digest']) ;
print NODE_DIGEST $postamble ;
$generate_digest_dump += tv_interval($t0_generate_dump, [gettimeofday]) ;
close(NODE_DIGEST) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Digest  -

=head1 SYNOPSIS

	#within a Pbsfile
	
	AddFileDependencies('/usr/bin/gcc') ;
	AddEnvironmentDependencies('PROJECT') ;
	AddSwitchDependencies('-D*', '-u*') ;
	AddVariableDependencies('gcc_version' => GetGccVersion()) ;
	AddNodeFileDependencies(qr/^.\/file_name$/, 'pbs.html') ;
	
=head1 DESCRIPTION

This module handle s all the digest functionality of PBS. It also make available, to the user,  a set of functions
that can be used in I<Pbsfiles> to add information to the node digest generated by B<PBS>

=head2 EXPORT

All the node specific functions take a regular expression (string or qr) as a first argument.
only nodes matching that regex will be dependent on the rest of the arguments.

	# make all the nodes dependent on the compiler
	# including documentation, libraries, text files and whatnot
	AddVariableDependencies(compiler => GetCompilerInfo()) ;


	# c files only depend on the compiler
	AddNodeVariableDependencies(qr/\.c$/, compiler => GetCompilerInfo()) ;
	
AddFileDependencies, AddNodeFileDependencies: this function is given a list of file names. 

AddEnvironmentDependencies, AddNodeEnvironmentDependencies: takes a list of environnement variables.

AddVariableDependencies, AddNodeVariableDependency: takes a list of tuples (variable_name => value).

AddConfigVariableDependencies AddNodeConfigVariableDependencies: takes a list of tuples (variable_name).
	the variable's value is extracted from the node's config when generating the digest.

AddSwitchDependencies, AddNodeSwitchDependencies: handles command line switches B<-D> and B<-u>.
	AddNodeSwitchDependencies('node_which_uses_my_user_switch_regex' => '-u my_user_switch) ;
	AddSwitchDependencies('-D gcc'); # all node depend on the '-D gcc' switch.
	AddSwitchDependencies('-D*') ; # all nodes depend on all'-D' switches.


ExcludeFromDigestGeneration('rule_name', $regex): the nodes matching $regex will not have any digest attached. Digests are 
for nodes that B<PBS> can build. Source files should not have any digest. 'rule_name' is displayed by PBS for your information.
	# extracted from the 'Rules/C' module
	ExcludeFromDigestGeneration( 'c_files' => qr/\.c$/) ;
	ExcludeFromDigestGeneration( 's_files' => qr/\.s$/) ;
	ExcludeFromDigestGeneration( 'h_files' => qr/\.h$/) ;
	ExcludeFromDigestGeneration( 'libs'    => qr/\.a$/) ;

ForceDigestGeneration('rule_name', $regex): forces the generation of a digest for nodes matching the regex. This is 
usefull if you generate a node that has been excluded via I<ExcludeFromDigestGeneration>.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
