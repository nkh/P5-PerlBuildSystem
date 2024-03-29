
package PBS::Config ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(
		AddConfig       AddConfigTo
		GetConfig       GetConfigFrom
		GetConfigAsList GetConfigFromAsList
		GetConfigKeys

		AddCompositeDefine
		
		AddConditionalConfig
		AddConditionalConfigTo
			ConfigVariableNotDefined
			ConfigVariableEmpty
			ConfigVariableNotDefinedOrEmpty

		Config config
		) ;
		
our $VERSION = '0.04' ;

use Carp ;
use Data::Compare;
use Data::TreeDumper ;
 
use PBS::Debug ;
use PBS::Output ;

our $debug_display_all_configurations ;

#-------------------------------------------------------------------------------

my %configs ;

#-------------------------------------------------------------------------------

sub GetPackageConfig
{
my ($package, $config) = @_ ;

my (undef, $file_name, $line) = caller() ;

if(defined $package && $package ne '')
	{
	if (exists $configs{$package})
		{
		if(defined $config)
			{
			Say Warning "Config: overriding '$package' config @ '$file_name:$line'" ;

			$configs{$package} = $config ; 
			}
		}
	else
		{
		$configs{$package} = defined $config ? $config : {} ;
		}

	return $configs{$package} ;
	}
else
	{
	die ERROR("Config: unknown package @ '$file_name:$line'\n") . "\n" ;
	}
}

#-------------------------------------------------------------------------------

sub GetConfigFrom
{
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $from = shift ; # namespace

unless(defined $from)
	{
	Say Warning "Config: 'GetConfigFrom' no argument, returning nothing @ '$file_name:$line'" ;
	#~ PbsDisplayErrorWithContext$pbs_config, $file_name,$line ;
	return () ;
	}

my %user_config = ExtractConfig($configs{$package}, [$from]) ;

__GetConfig
	(
	$package, $file_name, $line,
	wantarray,
	\%user_config,
	@_,
	)
}

#-------------------------------------------------------------------------------

sub ClonePackageConfig
{
my ($source_package, $destination_package) = @_ ;
my (undef, $file_name, $line) = caller() ;

use Clone ;
$configs{$destination_package} = Clone::clone($configs{$source_package}) ;
}

sub GetClone
{
my (undef, $file_name, $line) = caller() ;

my ($config) = @_ ;

if(exists $configs{$config})
	{
	Clone::clone $configs{$config} ;
	}
else
	{
	Print Error "Config: can't clone unexisting '$config' @ $file_name:$line" ;
	die "\n" ;
	}
}


#-------------------------------------------------------------------------------

sub GetConfig
{
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my %user_config = ExtractConfig($configs{$package}, $pbs_config->{CONFIG_NAMESPACES}) ;

__GetConfig
	(
	$package, $file_name, $line,
	wantarray,
	\%user_config,
	@_,
	)
}

#-------------------------------------------------------------------------------

sub GetConfigKeys
{
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my %user_config = ExtractConfig($configs{$package}, $pbs_config->{CONFIG_NAMESPACES}) ;

keys %user_config ;
}

#-------------------------------------------------------------------------------

my %config_access ;

sub GetConfigAccess
{
my ($package) = @_ ;

$config_access{$package}
}

sub __GetConfig
{
my 
	(
	$package, $file_name, $line,
	$wantarray,
	$user_config,
	@config_variables,
	) = @_ ;
	
$file_name =~ s/^'// ; $file_name =~ s/'$// ;
my $origin = "$file_name:$line" ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

if ($pbs_config->{DEBUG_TRACE_PBS_STACK})
	{
	my @traces = @{PBS::Stack::GetPbsStack($pbs_config, "GetConfig")} ;

	if (@traces > 1)
		{
		$origin .= INFO2(", " . GetRunRelativePath($pbs_config, $_->{FILE}) . ":$_->{LINE}") for (@traces) ;
		}
	}

my @user_config ;
if(@config_variables == 0)
	{
	Say Warning "Config: 'GetConfig' is returning the whole config but it was not called in list context @ '$file_name:$line'"
		unless($wantarray) ;
		
	push @{$config_access{$package}{$_}}, $origin for keys %$user_config ;

	return %$user_config ;
	}
	
if(@config_variables > 1 && !$wantarray)
	{
	Say Warning "Config: 'GetConfig' is asked for multiple values but it was not called in list context @ '$file_name:$line'" ;
	}

for my $config_variable (@config_variables)
	{
	push @{$config_access{$package}{$config_variable}}, $origin ;

	my $silent_not_exists = $config_variable =~ s/:SILENT_NOT_EXISTS$// ;
	
	if(exists $user_config->{$config_variable})
		{
		push @user_config, $user_config->{$config_variable} ;
		}
	else
		{
		if($pbs_config->{NO_SILENT_OVERRIDE} || ! $silent_not_exists)
			{
			Say Warning "Config: User config variable '$config_variable' doesn't exist @ '$file_name:$line'; returning undef" ;
			}
			
		#~ PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		push @user_config, undef ;
		}
	}

$wantarray ? @user_config : $user_config[0] ;
}

#-------------------------------------------------------------------------------

sub GetConfigFromAsList
{
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $from = shift ; # from namespace

unless(defined $from)
	{
	Say Warning "Config: 'GetConfigFromAsList' mandatory argument missing @ '$file_name:$line'" ;
	#~ PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	return () ;
	}

my %user_config = ExtractConfig($configs{$package}, [$from]) ;

__GetConfigAsList
	(
	$package, $file_name, $line,
	wantarray,
	\%user_config,
	@_,
	)
}

#-------------------------------------------------------------------------------

sub GetConfigAsList
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ; $file_name =~ s/'$// ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my %user_config = ExtractConfig($configs{$package}, $pbs_config->{CONFIG_NAMESPACES}) ;

__GetConfigAsList
	(
	$package, $file_name, $line,
	wantarray,
	\%user_config,
	@_,
	)
}

#-------------------------------------------------------------------------------

sub __GetConfigAsList
{
my 
	(
	$package, $file_name, $line,
	$wantarray,
	$user_config,
	@config_variables,
	) = @_ ;

my $caller_location = "at '$file_name:$line'" ;
my @user_config ;

unless($wantarray)
	{
	Print Error "Config: GetConfigAsList: not called in list context $caller_location" ;
	die "\n" ;
	}

if(@config_variables == 0)
	{
	Print Error "Config: GetConfigAsList: called without arguments $caller_location'" ;
	die "\n" ;
	}
	
for my $config_variable (@config_variables)
	{
	if(exists $user_config->{$config_variable})
		{
		my $config_data = $user_config->{$config_variable} ;
		
		for my $data_type (ref $config_data)
			{
			'ARRAY' eq $data_type && do
				{
				my $array_element_index = 0 ;
				for my $array_element (@$config_data)
					{
					Say Warning "Config: GetConfigAsList: Element $array_element_index of array '$config_variable', $caller_location, is not defined"
						unless defined $array_element  ;

					$array_element_index++ ;
					}
				
				push @user_config, @$config_data ;
				last ;
				} ;
				
			'' eq $data_type && do
				{
				Say Warning "Config: GetConfigAsList: '$config_variable', $caller_location, is not defined"
					unless defined $config_data ;
				
				push @user_config, $config_data ;
				last ;
				} ;
				
			Print Error "Config: GetConfigAsList: Unhandled type '$data_type' for '$config_variable' $caller_location" ;
			die "\n" ;
			}
		
		}
	else
		{
		Say Warning "Config: GetConfigAsList:variable '$config_variable' doesn't exist $caller_location; ignoring request" ;
		#~ PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		}
	}

@user_config ;
}

#-------------------------------------------------------------------------------

sub ExtractConfig
{
my ($config, $config_class_names, $config_types) = @_ ;

#SUT $config_class_names, 'namespaces' ;

$config_types //= ['CURRENT', 'PARENT', 'LOCAL', 'COMMAND_LINE', 'PBS_FORCED'] ;
my %all_configs ;

for my $type (@$config_types)
	{
	for my $config_class_name (@$config_class_names, '__PBS', '__PBS_FORCED')
		{
		if(exists $config->{$type}{$config_class_name})
			{
			my $current_config = $config->{$type}{$config_class_name} ;
			
			for my $key (keys %$current_config)
				{
				next if $key =~ /^__/ ;
				$all_configs{$key} =  $current_config->{$key}{VALUE} ;
				}
			}
		}
	}

%all_configs
}

#-------------------------------------------------------------------------------

sub Config
{
# available within Pbsfiles
# with only one element gets the elements config
# with more than one element, set the config

my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

if(@_ > 1)
	{
	AddConfigEntry($package, 'CURRENT', 'User', "$package:$file_name:$line", @_) ;
	}
elsif(@_ == 1)
	{
	my $config_variable = $_[0] ;

	my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
	my %user_config = ExtractConfig($configs{$package}, $pbs_config->{CONFIG_NAMESPACES}) ;

	if($config_variable =~ '%')
		{
		my $config = GetPackageConfig($package) ;
		   $config = { ExtractConfig($config, ['User']) } ;

		EvalConfig
			(
			$config_variable,
			$config,
			"$file_name:$line",
			$package, # to record config  access
			{}, #to display extra info if option is set
			) ;
		}
	else
		{
		__GetConfig
			(
			$package, $file_name, $line,
			wantarray,
			\%user_config,
			$config_variable,
			)
		}
	}
}

*config=\&Config ;

sub AddConfig
{
# available within Pbsfiles
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

AddConfigEntry($package, 'CURRENT', 'User', "$package:$file_name:$line", @_) ;
}

#-------------------------------------------------------------------------------

sub ConfigVariableNotDefined
{
return ! defined $_[1] ;
}

sub ConfigVariableEmpty
{
if(defined $_[1])
	{
	return $_[1] eq '' ;
	}
else
	{
	Say Warning croak "Config: variable '$_[0]' is not defined" ;
	return 0 ;
	}
}

sub ConfigVariableNotDefinedOrEmpty
{
ConfigVariableNotDefined(@_) || ConfigVariableEmpty(@_) ;
}

#-------------------------------------------------------------------------------

sub AddConditionalConfig
{
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

_AddConditionalConfig($package, $file_name, $line, 'USER', @_) ;
}

sub AddConditionalConfigTo
{
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $class = shift ;

_AddConditionalConfig($package, $file_name, $line, $class, @_) ;
}

sub _AddConditionalConfig
{
my ($package, $file_name, $line, $class) = splice(@_, 0, 4) ;

while(@_)
	{
	my ($variable, $value, $test) = splice(@_, 0, 3) ;
	
	my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
	my %user_config = ExtractConfig($configs{$package}, $pbs_config->{CONFIG_NAMESPACES}) ;
	
	my $current_value ;
	$current_value = $user_config{$variable} if exists $user_config{$variable};
	
	#~ PrintDebug "$variable: $current_value\n" ;
	
	if($test->($variable, $current_value))
		{
		#~ PrintDebug "Adding '$variable' in 'AddConditionalConfig'\n" ;
		
		AddConfigEntry($package, 'CURRENT', $class, "$package:$file_name:$line", $variable, $value) ;
		}
	}
}

#-------------------------------------------------------------------------------

sub AddConfigTo
{
# available within Pbsfiles
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

my $class = shift ;

AddConfigEntry($package, 'CURRENT', $class, "$package:$file_name:$line", @_) ;
}

#-------------------------------------------------------------------------------

sub AddConfigEntry
{
my $package = shift ;
my $type    = shift ; # CURRENT | PARENT | COMMAND_LINE
my $class   = shift ;
my $origin  = shift ;

#~ my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

MergeConfig($package, $type, $class, $origin, @_) ;
}

#-------------------------------------------------------------------------------

sub DisplayAllConfigs
{
SIT \%configs, 'All configurations:' ;
}

#------------------------------------------------------------------------------------------

my %valid_attributes = map {$_ => 1} qw(FORCE LOCKED UNLOCKED OVERRIDE_PARENT LOCAL SILENT_OVERRIDE) ;
	
sub MergeConfig
{
my $package            = shift ; # name of the packages and eventual command flags
my $original_type      = shift ;
my $original_class     = shift ;
my $origin             = shift ;

# @_ now contains the configuration variable to merge  (name => value, name => value ...)

# check if we have any command global flags
my $global_flags ;
($original_class, $global_flags) = $original_class =~ /^([^:]+)(.*)/ ;

my %global_attributes ;
if(defined $global_flags)
	{
	$global_flags =~ s/^:+// ;
	
	for my $attribute (split /:+/, $global_flags)
		{
		$global_attributes{uc($attribute)}++ ;
		}
		
	if($global_attributes{LOCKED} && $global_attributes{UNLOCKED})
		{
		Print Error "Config: Global configuration flag defined @ '$origin', is declared as LOCKED and UNLOCKED" ;
		die "\n";
		}
		
	if($global_attributes{OVERRIDE_PARENT} && $global_attributes{LOCAL})
		{
		Print Error "Config: Global configuration flag defined @ '$origin', is declared as OVERRIDE_PARENT and LOCAL" ;
		die "\n";
		}
	}
		
# Get the config and extract what we need from it
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

#my $header_text = "Config: merging to configuration: '${package}::${original_type}::$original_class' @ '$origin'\n" ;
my $header_text = "Config: merging to configuration: '${package}' @ '$origin'\n" ;

my $header_displayed = 0 ;

if(defined $pbs_config->{DEBUG_DISPLAY_ALL_CONFIGURATIONS} || defined $pbs_config->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE})
	{
	Print Info $header_text ;
	$header_displayed++ ;
	}

my $config_to_merge_to = GetPackageConfig($package) ;
my $config_to_merge_to_cache = { ExtractConfig($config_to_merge_to, [$original_class]) } ;

# handle the config values and their flags
for(my $i = 0 ; $i < @_ ; $i += 2)
	{
	my ($type, $class) = ($original_type, $original_class) ; #sometimes overridden by flags
	
	my ($key, $value) = ($_[$i], $_[$i +1]) ;
	my ($local, $force, $override_parent, $locked, $unlocked, $silent_override) ;
		
	my $flags ;
	($key, $flags) = $key =~ /^([^:]+)(.*)/ ;
	
	my %attributes ;
	if(defined $flags)
		{
		$flags =~ s/^:+// ;
		
		my @found_invalid_attribute ;
		
		for my $attribute (split /:+/, $flags)
			{
			$attribute = uc $attribute ;
			
			if(! exists $valid_attributes{$attribute})
				{
				push @found_invalid_attribute, $attribute ;
				}
			else
				{
				$attributes{uc($attribute)}++ ;
				}
			}
	
		if(@found_invalid_attribute)
			{
			Print Error
				"Config: variable '$key' with attributes '$flags' defined @ '$origin', has invalid attribute: " . join (', ', @found_invalid_attribute) . "\n"
				. "Valid attributes are: " . join( ', ',  sort keys %valid_attributes) ;
				
			die "\n" ;
			}
			
		$force           = $attributes{FORCE}           || $global_attributes{FORCE}           || '' ;
		$locked          = $attributes{LOCKED}          || $global_attributes{LOCKED}          || '' ;
		$unlocked        = $attributes{UNLOCKED}        || $global_attributes{UNLOCKED}        || '' ;
		$override_parent = $attributes{OVERRIDE_PARENT} || $global_attributes{OVERRIDE_PARENT} || '' ;
		$local           = $attributes{LOCAL}           || $global_attributes{LOCAL}           || '' ;
		
		$silent_override = $attributes{SILENT_OVERRIDE} || $global_attributes{SILENT_OVERRIDE} || '' ;
		$silent_override = 0 if $pbs_config->{NO_SILENT_OVERRIDE} ;
		
		if($locked && $unlocked)
			{
			Print Error "Config: variable '$key' defined @ '$origin', is declared as LOCKED and UNLOCKED" ;
			die  "\n" ;
			}
			
		if($override_parent && $local)
			{
			Print Error "Config: variable '$key' defined @ '$origin', is declared as OVERRIDE_PARENT and LOCAL" ;
			die "\n" ;
			}
		}
		
	if('' eq ref $value && $type ne 'PARENT')
		{
		# PARENT variables was evaluated while adding them, we don't want to re-evaluate it 
		$value = EvalConfig
				(
				$value,
				$config_to_merge_to_cache,
				"Merge config, origin: $origin",
				$package,
				$pbs_config,
				) ;
		}
		
	if(defined $pbs_config->{DEBUG_DISPLAY_CONFIGURATIONS_MERGE})
		{
		if($flags ne '')
			{
			my $indent = "\t" x ($PBS::Output::indentation_depth + 1) ;
				
			my %attributes ;
			$attributes{force} = $force if $force ;
			$attributes{locked} = $locked if $locked ;
			$attributes{unlocked} = $unlocked if $unlocked ;
			$attributes{override_parent} = $override_parent if $override_parent, ;
			$attributes{local} = $local if $local ;
			$attributes{silent_override} = $silent_override if $silent_override ;

			SIT \%attributes, "$key => $value", DISPLAY_ADDRESS => 0, INDENTATION => $indent ;
			}
		else
			{
			Say Info "\t$key => $value" ;
			}
		}
		
	#DEBUG	
	my %debug_data = 
		(
		TYPE                => 'VARIABLE',
		  
		VARIABLE_NAME       => $key,
		VARIABLE_VALUE      => $value,
		VARIABLE_ATTRIBUTES => \%attributes,
		
		CONFIG_TO_MERGE_TO  => $config_to_merge_to,
		MERGE_TYPE          => $type,
		CLASS               => $class,
		ORIGIN              => $origin,
		
		PACKAGE_NAME        => $package,
		NODE_NAME           => 'not available',
		PBSFILE             => 'not available',
		RULE_NAME           => 'not available',
		) ;
	
	#DEBUG	
	$DB::single++ if PBS::Debug::CheckBreakpoint($pbs_config, %debug_data) ;

	# Always merge variables of class PBS_FORCED, regardless of parent config/locked etc.
	if($class eq '__PBS_FORCED')
		{
		# warning: this adds a single entry
		$config_to_merge_to->{$type}{$class}{$key}{VALUE} = $value ;
		$config_to_merge_to_cache->{$key} = $value ;
		
		my $value_txt = defined $value ? $value : 'undef' ;
		push @{$config_to_merge_to->{$type}{$class}{$key}{ORIGIN}}, "$origin => $value_txt" ;
		
		return ;
		}
	
	if($override_parent)
		{
		$type = 'PARENT' ;
		$class = '__PBS' ;
		}
		
	if($local)
		{
		$type = 'LOCAL' ;
		}
		
	if(exists $config_to_merge_to->{$type}{$class}{$key})
		{
		if($config_to_merge_to->{$type}{$class}{$key}{LOCKED} && (! $force))
			{
			Print Warning3 $header_text unless $header_displayed++ ;
			Print Error
				(
				<<EOH .
	You want to override a locked configuration variable!
		Your failed override:
			key: '$key'
			attempted new value: '$value'
			at: '$origin'
			class '$class'
			type: '$type'
			package: '$package'
		
		The locked variable
EOH
				DumpTree
					(
					$config_to_merge_to->{$type}{$class}{$key}{ORIGIN},
					'history:',
					INDENTATION => "\t\t\t",
					)
				) ;
				
			die "\n" ;
			}
		
		$config_to_merge_to->{$type}{$class}{$key}{LOCKED} = 1 if $locked ;
		$config_to_merge_to->{$type}{$class}{$key}{LOCKED} = 0 if $unlocked ;
		
		# note that we do a deep compare not an 'ne'
		if(! Compare($config_to_merge_to->{$type}{$class}{$key}{VALUE},$value))
			{
			# not equal
			$config_to_merge_to->{$type}{$class}{$key}{VALUE} = $value ;
			$config_to_merge_to_cache->{$key} = $value ;
			
			my $value_txt = defined $value ? $value : 'undef' ;
			
			# just show where the override happens to avoid cluttering the display
			push @{$config_to_merge_to->{$type}{$class}{$key}{ORIGIN}},  "this Override @ '$origin'" ;
			
			unless($silent_override)
				{
				my ($locked_message,$warn_sub) = ('') ;
				
				if($force && $config_to_merge_to->{$type}{$class}{$key}{LOCKED})
					{
					$locked_message = 'locked ' ;
					$warn_sub = \&PrintWarning3 ;
					}
				else
					{
					$warn_sub = \&PrintWarning ;
					}
				
				Print Warning3 $header_text unless $header_displayed++ ;
				Print Warning3 <<EOH
		variable:  '$key', Overriding ${locked_message}
		new value: '$value'
EOH
#other possible data to display
#package: '$package'
#class '$class'
#type: '$type'

					. DumpTree
						(
						$config_to_merge_to->{$type}{$class}{$key}{ORIGIN},
						'history',
						INDENTATION => "\t\t",
						)
				}
				
			# now remember the origin and the value
			pop @{$config_to_merge_to->{$type}{$class}{$key}{ORIGIN}} ;
			push @{$config_to_merge_to->{$type}{$class}{$key}{ORIGIN}},  "$origin => $value_txt" ;
			
			$config_to_merge_to->{$type}{__PBS}{__OVERRIDE}{VALUE} = 1 ;
			push @{$config_to_merge_to->{$type}{__PBS}{__OVERRIDE}{ORIGIN}}, "$key @ $origin" ;
			}
		else
			{
			$config_to_merge_to->{$type}{$class}{$key}{VALUE} = $value ;
			$config_to_merge_to_cache->{$key} = $value ;
			
			my $value_txt = defined $value ? $value : 'undef' ;
			push @{$config_to_merge_to->{$type}{$class}{$key}{ORIGIN}}, "$origin => $value_txt" ;
			}
		}
	else
		{
		$config_to_merge_to->{$type}{$class}{$key}{LOCKED} = 1 if $locked ;
		$config_to_merge_to->{$type}{$class}{$key}{LOCKED} = 0 if $unlocked ;
		
		$config_to_merge_to->{$type}{$class}{$key}{VALUE} = $value ;
		$config_to_merge_to_cache->{$key} = $value ;
			
		my $value_txt = defined $value ? $value : 'undef' ;
		push @{$config_to_merge_to->{$type}{$class}{$key}{ORIGIN}}, "$origin => $value_txt" ;
		}
		
	# let the user know if it's configuration will not be used because of higer order classes
	if($type eq 'CURRENT')
		{
		if
		(
		   exists $config_to_merge_to->{PARENT}
		&& exists $config_to_merge_to->{PARENT}{__PBS}{$key} 
		&& ! Compare($value, $config_to_merge_to->{PARENT}{__PBS}{$key}{VALUE})
		)
			{
			Print Warning3 $header_text unless $header_displayed++ ;
			Print Warning3
				(
				<<EOH,
	Configuration variable will be ignored as type 'PARENT' has higher precedence
		key: '$key'
		attempted new value: '$value'
		type: 'CURRENT'
		at: '$origin'
		parent value: '$config_to_merge_to->{'PARENT'}{__PBS}{$key}{VALUE}'
EOH
				) ;
			}
		
		if
		(
		   exists $config_to_merge_to->{COMMAND_LINE}
		&& exists $config_to_merge_to->{COMMAND_LINE}{__PBS}{$key} 
		&& ! Compare($value, $config_to_merge_to->{COMMAND_LINE}{__PBS}{$key}{VALUE})
		)
			{
			Print Warning3 $header_text unless $header_displayed++ ;
			Print Warning3
				(
				<<EOH
	Configuration variable will be ignored as type 'COMMAND_LINE' has higher precedence
		key: '$key'
		attempted new value: '$value'
		type: 'CURRENT'
		at: '$origin'
		command line value: '$config_to_merge_to->{'COMMAND_LINE'}{__PBS}{$key}{VALUE}'
EOH
				) ;
			}
		}
		
	if($type eq 'PARENT')
		{
		if
		(
		   exists $config_to_merge_to->{COMMAND_LINE}
		&& exists $config_to_merge_to->{COMMAND_LINE}{__PBS}{$key} 
		&& ! Compare($value, $config_to_merge_to->{COMMAND_LINE}{__PBS}{$key}{VALUE})
		)
			{
			Print Warning3 $header_text unless $header_displayed++ ;
			Print Warning3
				(
				<<EOH
	Configuration variable will be ignored as type 'COMMAND_LINE' has higher precedence
		key: '$key'
		attempted new value: '$value'
		type: 'PARENT'
		at: '$origin'
		command line value: '$config_to_merge_to->{'COMMAND_LINE'}{__PBS}{$key}{VALUE}'
EOH
				) ;
			}
		}
		
	if($type eq 'LOCAL')
		{
		if
		(
		   exists $config_to_merge_to->{COMMAND_LINE}
		&& exists $config_to_merge_to->{COMMAND_LINE}{__PBS}{$key} 
		&& ! Compare($value, $config_to_merge_to->{COMMAND_LINE}{__PBS}{$key}{VALUE})
		)
			{
			Print Warning3 $header_text unless $header_displayed++ ;
			Print Warning3
				(
				<<EOH
	Configuration variable will be ignored as type 'COMMAND_LINE' has higher precedence
		key: '$key'
		attempted new value: '$value'
		type: 'PARENT'
		at: '$origin'
		command line value: '$config_to_merge_to->{'COMMAND_LINE'}{__PBS}{$key}{VALUE}'
EOH
				) ;
			}

		if
		(
		   exists $config_to_merge_to->{PARENT}
		&& exists $config_to_merge_to->{PARENT}{__PBS}{$key} 
		&& ! Compare($value, $config_to_merge_to->{PARENT}{__PBS}{$key}{VALUE})
		)
			{
			Print Warning3 $header_text unless $header_displayed++ ;
			Print Warning3
				(
				<<EOH
	Configuration variable of type 'LOCAL' has higher precedence than 'PARENT'
		key: '$key'
		new value: '$value'
		type: 'LOCAL'
		at: '$origin'
		
		Overridden value from PARENT: '$config_to_merge_to->{'PARENT'}{__PBS}{$key}{VALUE}'
EOH
				) ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

#$shell_command = PBS::Config::EvalConfig($shell_command, $tree->{__CONFIG}, $shell_command_info, $tree->{__LOAD_PACKAGE}, $tree->{__PBS_CONFIG}) ;
sub EvalConfig 
{
my ($entry, $config, $origin, $package, $pbs_config, $no_warnings) = @_ ;

return $entry unless defined $entry ;
return $entry unless $entry =~ /%/ ;

my $source_entry = $entry ;

my $undefined_config = 0 ;

#%% entries are not evaluated
$entry =~ s/\%\%/__PBS__PERCENT__/g ;

# replace config names with their values
while($entry =~ /\$config->\{('*[^}]+)'*}/g)
	{
	my $element = $1 ; $element =~ s/^'// ; $element =~ s/'$// ;

	unless(exists $config->{$element})
		{
		Say Warning "Config: $config->{$1} doesn't exist @ $origin" unless $no_warnings ;
		$undefined_config++ ;
		next ;
		}
		
	unless(defined $config->{$element})
		{
		Say Warning" Config: $config->{$1} isn't defined @ $origin" unless $no_warnings ;
		$undefined_config++ ;
		}

	Say Info2 "Config: $element => " . ($config->{$element} // 'undef') . " @ $origin"
		if $pbs_config->{EVALUATE_SHELL_COMMAND_VERBOSE}
	}

return $entry if $undefined_config ;

$entry =~ s|\\|\\\\|g ;

# replace uppercase words by their values within the config
while($entry =~ /\%([_a-zA-Z0-9]+)/g)
	{
	my $element = $1 ;
	
	unless(exists $config->{$element})
		{
		Say Warning "Config: config '$element' doesn't exist @ $origin" unless $no_warnings ;
		$undefined_config++ ;
		next ;
		}
		
	unless(defined $config->{$element})
		{
		Say Warning "Config: config '$element' isn't defined @ $origin" unless $no_warnings ;
		$undefined_config++ ;
		}

	Say Info2 "Config: '$element' => "
			. (exists $config->{$element} && defined $config->{$element} ? $config->{$element} : 'undef')
			. " @ $origin"
		if $pbs_config->{EVALUATE_SHELL_COMMAND_VERBOSE} ;

	push @{$config_access{$package}{$element}}, "$origin" ;
	}

$entry =~ s/\%([_a-zA-Z0-9]+)/
	if(exists $config->{$1} && defined $config->{$1})
		{
		my $v = $config->{$1} ;

		if('' eq ref $v)
			{
			$v
			}
		else
			{
			DumpTree $v, $1, DISPLAY_ADDRESS => 0 ;
			}
		}
	else
		{
		"%$1"
		}
	/eg ;
$entry =~ s/__PBS__PERCENT__/\%/g ;

$entry
}

#-------------------------------------------------------------------------------

sub AddCompositeDefine
{
my ($variable_name, %defines) = @_;
my ($package, $file_name, $line) = caller() ;

my ($source_package) = @_ ;
do { $package = $source_package ; shift } if exists $configs{$source_package} ;

if(keys %defines)
	{
	my @defines = map { "$_=$defines{$_}" } sort keys %defines ;
	my $defines = ' -D' . join ' -D', @defines;
	
	AddConfigEntry($package, 'CURRENT', 'User', "$package:$file_name:$line", $variable_name => $defines) ;
	}
}

#-------------------------------------------------------------------------------

sub get_subps_configuration
{
# create the sup pbs package configuration from the configuration of the parent package plus any sub pbs {PACKAGE_CONFIG} if any
# note that we must run multiple subs in a special perl package as the configuration engine uses the current package to separate pbs runs

my
	(
	$sub_pbs_hash,
	$sub_pbs,
	$tree,
	$sub_node_name,
	$pbs_config,
	$load_package,
	) = @_ ;
	
# although the creation of the subpbs configuration is done in the parent, it is easier
# for the user to see it indented at the same level as the subpbs
	
local $PBS::Output::indentation_depth ;
$PBS::Output::indentation_depth++ ;

my %sub_config ;

if(defined $sub_pbs_hash->{PACKAGE_CONFIG_NO_INHERITANCE} || $pbs_config->{NO_CONFIG_INHERITANCE})
	{
	my $warning = "Config:" ;
	$warning .= " PACKAGE_CONFIG_NO_INHERITANCE" if $sub_pbs_hash->{PACKAGE_CONFIG_NO_INHERITANCE} ;
	$warning .= " --no_config_inheritance" if $pbs_config->{NO_CONFIG_INHERITANCE} ;
	$warning .= " for '$sub_node_name' defined @ '$sub_pbs->[0]{RULE}{FILE}:$sub_pbs->[0]{RULE}{LINE}' " ;

	Say Warning "$warning" if($pbs_config->{DISPLAY_CONFIGURATION} ||  $pbs_config->{DISPLAY_PACKAGE_CONFIGURATION}) ;

	if(defined $sub_pbs_hash->{PACKAGE_CONFIG})
		{
		%sub_config = %{$sub_pbs_hash->{PACKAGE_CONFIG}} ;

		my $title = "Config: PACKAGE_CONFIG for '$sub_node_name' defined @ '$sub_pbs->[0]{RULE}{FILE}:$sub_pbs->[0]{RULE}{LINE}'" ;

		if($pbs_config->{DISPLAY_CONFIGURATION} ||  $pbs_config->{DISPLAY_PACKAGE_CONFIGURATION})
	        	{
        		SWT $sub_pbs_hash->{PACKAGE_CONFIG}, "$title:" ;
		        }
		}
	}
else
	{
	if(defined $sub_pbs_hash->{PACKAGE_CONFIG}  ||  $pbs_config->{DISPLAY_PACKAGE_CONFIGURATION})
		{
		my $subpbs_package_node_config = "__SUBPS_CONFIG_FOR_NODE_$sub_node_name" ;
		$subpbs_package_node_config =~ s/[^[:alnum:]]/_/g ;
		
		my $code_string = <<"EOE" ;
			package $subpbs_package_node_config
			{
			use PBS::Output ;
			use Data::TreeDumper ;
			
			PBS::Config::create_subpbs_node_config
				(
				\$sub_pbs,
				\$subpbs_package_node_config,
				\$tree->{__PBS_CONFIG}{CONFIG_NAMESPACES},
				\$sub_node_name,
				\$pbs_config,
				\$load_package,
				) ;
			} ;
EOE
		%sub_config = eval $code_string ;
		die $@ if $@ ;
		}
	else
		{
		%sub_config = PBS::Config::ExtractConfig
				(
				PBS::Config::GetPackageConfig($load_package),
				$tree->{__PBS_CONFIG}{CONFIG_NAMESPACES},
				['CURRENT', 'PARENT', 'COMMAND_LINE', 'PBS_FORCED'], # LOCAL REMOVED!
				) ;
		}
	}

\%sub_config ;
}

#-------------------------------------------------------------------------------

sub create_subpbs_node_config
{
# the node config is first merged in a copy of the local config. This gives us all the warnings
# that we normally get when manipulating a configuration
# we also display the node configuration if DISPLAY_CONFIGURATION is set

my($sub_pbs, $subpbs_package_node_config, $config_namespaces, $sub_node_name, $pbs_config,$load_package) = @_ ;

my $rule = $sub_pbs->[0]{RULE} ;
my $sub_pbs_package_config = $rule->{TEXTUAL_DESCRIPTION}{PACKAGE_CONFIG} ;

my $subpbd_definition_location = "#line " . $sub_pbs->[0]{RULE}{LINE} . " " . $sub_pbs->[0]{RULE}{FILE} ;
	
PBS::PBSConfig::RegisterPbsConfig($subpbs_package_node_config, $pbs_config) ;
ClonePackageConfig($load_package, $subpbs_package_node_config) ;

# check the $sub_pbs_package_config for type validity
if('HASH' ne ref $sub_pbs_package_config)
	{
	Print Error 
		DumpTree 
			$rule->{TEXTUAL_DESCRIPTION},
			"Config: section PACKAGE_CONFIG in sub pbs definition is not a hash, '$rule->{NAME}:$rule->{FILE}:$rule->{LINE}'" 
			. "(type is '" . ref($sub_pbs_package_config) . "')",
			DISPLAY_ADDRESS => 0 ;
	die "\n" ;
	}
	
my $title = "Config: PACKAGE_CONFIG for '$sub_node_name' defined @ '$sub_pbs->[0]{RULE}{FILE}:$sub_pbs->[0]{RULE}{LINE}'" ;

if($pbs_config->{DISPLAY_CONFIGURATION})
	{
	SWT $sub_pbs_package_config, "$title:" ;
	}
else
	{
	Say Warning "$title" ;
	}

eval <<"EOE" ;
package $subpbs_package_node_config ;
#line $rule->{LINE} $rule->{FILE}
PBS::Config::AddConfig(%{\$sub_pbs_package_config}) ;
EOE
die $@ if $@ ;

PBS::Config::ExtractConfig
	(
	PBS::Config::GetPackageConfig($subpbs_package_node_config),
	$config_namespaces,
	['CURRENT', 'PARENT', 'COMMAND_LINE', 'PBS_FORCED'], # LOCAL REMOVED!
	) ;
} ;

#-------------------------------------------------------------------------------

1 ;

__END__

=head1 NAME

PBS::Config  -

=head1 SYNOPSIS

	use PBS::Config;
	AddConfig( CC => 'gcc', PROJECT => 'NAILARA') ;
	
	if(GetConfig('DEBUG_FLAGS'))
		{
		....

=head1 DESCRIPTION

PBS::Config exports functions that let the user add configuration variable.
The configuration are kept sorted on 5 different hierarchical levels.

=over 2

=item 1 Package name

=item 2 Class ('CURRENT', 'PARENT', 'LOCAL', 'COMMAND_LINE', 'PBS_FORCED')

=item 3 User defined namespaces

=back

The package name is automatically set by PBS and is used to keep all the subpbs configuration separate.
The classes are also set by PBS. They are used to define a precedence hierachy.
The precedence order is  B<CURRENT> < B<PARENT> < B<LOCAL> < B<COMMAND_LINE> < B<PBS_FORCED>.

I<AddConfig> uses the 'CURRENT' class, namespace 'User' by default. It's behaviour can be changed with argument attributes (see below).
If a variable exists in multiple classes, the one defined in the higher order class will be 
returned by I<GetConfig>.

=head2 Argument attributes

The variables passed to I<AddConfig> can have attributes that modify the lock attribute
of the variable or it's class. The attributes can be any of the following.

=over 2

=item LOCKED

=item UNLOCKED

=item FORCE

=item OVERRIDE_PARENT

=item LOCAL

=back

An attribute is passed by appending a ':' and the attribute to the variable name.

=head3 LOCKED and UNLOCKED

Within the class where the variable will be stored, the variable will be locked or not.
When run with the following example:

	AddConfig 'a' => 1 ;
	AddConfig 'a' => 2 ;
	
	AddConfig 'b:locked' => 1 ;
	AddConfig 'b' => 2 ;

Pbs generates a warning message for the first ovverride and an error message for
the attempt to override a locked variable:

	Overriding config 'PBS::Runs::PBS_1::CURRENT::User::a' it is now:
	+- ORIGIN [A1]
	�  +- 0 = PBS::Runs::PBS_1:'Pbsfiles/config/lock.pl':14 => 1
	�  +- 1 = PBS::Runs::PBS_1:'Pbsfiles/config/lock.pl':15 => 2
	+- VALUE = 2
	
	Configuration variable 'b' defined at PBS::Runs::PBS_1:'Pbsfiles/config/lock.pl':18,
	wants to override locked variable:PBS::Runs::PBS_1::CURRENT::User::b:
	+- LOCKED = 1
	+- ORIGIN [A1]FORCE
	�  +- 0 = PBS::Runs::PBS_1:'Pbsfiles/config/lock.pl':17 => 1
	+- VALUE = 1

=head3 FORCE

Within the same class, a configuration can override a locked variable.
	AddConfig 'b:locked' => 1 ;
	AddConfig 'b:force' => 2 ;

	Overriding config 'PBS::Runs::PBS_1::CURRENT::User::b' it is now:
	+- LOCKED = 1
	+- ORIGIN [A1]
	�  +- 0 = PBS::Runs::PBS_1:'Pbsfiles/config/force.pl':14 => 1
	�  +- 1 = PBS::Runs::PBS_1:'Pbsfiles/config/force.pl':15 => 2
	+- VALUE = 2

=head3 OVERRIDE_PARENT

Pbsfile should always be written without knowledge of being a subbs or not. In some exceptional circumstenses,
you can override a parent variable with the 'OVERRIDE_PARENT' attribute. The configuration variable is changed
in the 'PARENT' class directly.

	AddConfig 'b:OVERRIDE_PARENT' => 42 ;

=head3 LOCAL

Configuration variable inheritence is present in PBS to insure that the top level Pbsfile can force it's configuration
over sub Pbsfiles. This is normaly what you want to do. Top level Pbsfile should know how child Pbsfiles work and what 
variables it utilizes. In normal cicumstences, the top Pbsfile sets configuration variables for the whole build 
(debug vs dev vs release for example). Child Pbsfiles sometimes know better than their parents what configuration is best.

Let's take an example whith 3 Pbsfile: B<parent.pl> uses B<child.pl> which in turn uses B<grand_child.pl>. B<Parent.pl> sets the optimization 
flags with the following I<AddConfig> call:

	AddConfig OPTIMIZE_FLAG => '04' ;

The configuration variable 'OPTIMIZE_FLAG' is passed to B<parent.pl> children. This is what we normaly want but we might know that
the code build by B<child.pl> can not be optimized with something other than 'O2' because of a compiler bug. We could use the B<OVVERIDE_PARENT>
attribute within B<child.pl>:

	AddConfig 'OPTIMIZE_FLAG:OVERRIDE_PARENT' => 'O2' ;

This would generate the right code but B<grand_child.pl> would receive the value 'O2' within the OPTIMIZE_FLAG variable. It is possible
to define local variable that override parent variable but let children get their grand parent configuration.

	AddConfig 'OPTIMIZE_FLAG:LOCAL' => 'O2' ;

Here is the output from the config example found in the distribution:

	[nadim@khemir PBS]$ pbs -p Pbsfiles/config/parent.pl -dc -nh -tta -nsi parent
	Config for 'PBS':
	|- OPTIMIZE_FLAG_1 = O3
	|- OPTIMIZE_FLAG_2 = O3
	`- TARGET_PATH =
	Overriding config 'PBS::Runs::child_1::PARENT::__PBS::OPTIMIZE_FLAG_1' it is now:
	|- ORIGIN [A1]
	|  |- 0 = parent: 'PBS' [./child] => O3
	|  `- 1 = PBS::Runs::child_1:'./Pbsfiles/config/child.pl':1 => O2
	`- VALUE = O2
	Config for 'child':
	|- OPTIMIZE_FLAG_1 = O2
	|- OPTIMIZE_FLAG_2 = O2
	`- TARGET_PATH =
	Config for 'grand_child':
	|- OPTIMIZE_FLAG_1 = O2
	|- OPTIMIZE_FLAG_2 = O3
	`- TARGET_PATH =
	...

=head2 EXPORT

	AddConfig AddConfigTo
	GetConfig GetConfigFrom
	GetConfigAsList GetConfigFromAsList
	
=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

--no_silent_override

=cut

