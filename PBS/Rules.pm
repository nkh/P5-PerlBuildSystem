
package PBS::Rules ;

use 5.006 ;

use strict ;
use warnings ;
use Data::TreeDumper ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(AddRule Rule rule AddRuleTo AddSubpbsRule Subpbs subpbs AddSubpbsRules ReplaceRule ReplaceRuleTo RemoveRule BuildOk TouchOk GetRuleTypes) ;
our $VERSION = '0.09' ;

use File::Basename ;
use Time::HiRes qw( gettimeofday tv_interval ) ;
use List::Util qw( any ) ;

use PBS::Config ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Plugin ;
use PBS::Stack ;
use PBS::Shell ;

use PBS::Rules::Dependers ;
use PBS::Rules::Builders ;

use PBS::Rules::Order ;
use PBS::Rules::Scope ;

#-------------------------------------------------------------------------------

our %package_rules ;

#-------------------------------------------------------------------------------

sub GetPackageRules
{
my $package = shift ;
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

my @rules_names = @_ ;
my @all_rules   = () ;

PrintInfo("PBS: Get package rules: $package\n") if defined $pbs_config->{DEBUG_DISPLAY_RULES} ;

if(exists $package_rules{$package})
	{
	return($package_rules{$package}) ;
	}
else
	{
	return({}) ;
	}
}

#-------------------------------------------------------------------------------

sub ExtractRules
{
# extracts out the rules named in @rule_names from the rules definitions $rules

#todo: slave rules should be kept separately say in %slave_rules
#todo: rules should be kept in sorted order
#	this sub could be 1 line long => retun $rules->{@rules_namespace} ;
	
my ($pbs_config, $pbsfile, $rules, @rules_namespaces) = @_ ;

my @dependency_rules ;

for my $rules_namespace (@rules_namespaces)
	{
	if(exists $rules->{$rules_namespace})
		{
		for my $rule (@{$rules->{$rules_namespace}})
			{
			push @dependency_rules, $rule ;
			}
		}
	}

@dependency_rules = PBS::Rules::Order::OrderRules($pbs_config, $pbsfile, @dependency_rules) ;

return(@dependency_rules) ;
}

#-------------------------------------------------------------------------------

sub AddRule
{
# Depender build from the rules will return an array reference containing:
# - the value 0 and a text message if no dependencies where found
# or 
# - the value 1 and a list of dependency names

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = 'User' ;

my @rule_definition = @_ ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $config = 
	{
	PBS::Config::ExtractConfig
		(
		PBS::Config::GetPackageConfig($package),
		$pbs_config->{CONFIG_NAMESPACES},
		)
	} ;

RunUniquePluginSub($pbs_config, 'AddRule', $package, $config, $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition ;
my ($name, $rule_type) ;

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		PrintError "Rules: '$name' invalid rule, expecting a name string, or a list of types, as first argument" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		die "\n" ;
		}
	}

my($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RegisterRule
	(
	$pbs_config, $config,
	$file_name, $line,
	$package, $class,
	$rule_type, $name, $depender_definition, $builder_sub, $node_subs,
	) ;
}

*Rule=\&AddRule ;
*rule=\&AddRule ;

#-------------------------------------------------------------------------------

sub AddRuleTo
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $config = 
	{
	PBS::Config::ExtractConfig
		(
		PBS::Config::GetPackageConfig($package),
		$pbs_config->{CONFIG_NAMESPACES},
		)
	} ;

my $class = shift ;
unless('' eq ref $class)
	{
	PrintError "Rules: class name expected as first argument\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	die "\n" ;
	}

my @rule_definition = @_ ;

RunUniquePluginSub($pbs_config, 'AddRule', $package, $config, $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition;
my ($name, $rule_type) ;

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		PrintError "Rules: '$name' expecting a string or an array ref" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}
	}

my ($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RegisterRule
	(
	$pbs_config, $config,
	$file_name, $line,
	$package, $class,
	$rule_type, $name, $depender_definition, $builder_sub, $node_subs,
	) ;
}

#-------------------------------------------------------------------------------

sub ReplaceRule
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = 'User' ;

my @rule_definition = @_ ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $config = 
	{
	PBS::Config::ExtractConfig
		(
		PBS::Config::GetPackageConfig($package),
		$pbs_config->{CONFIG_NAMESPACES},
		)
	} ;

RunUniquePluginSub($pbs_config, 'AddRule', $package, $config, $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition ;

my ($name, $rule_type) ;

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		PrintError "Rules: '$name' expecting a string or an array ref" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}
	}

my($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RemoveRule($package, $class, $name) ;

RegisterRule
	(
	$pbs_config, $config,
	$file_name, $line,
	$package, $class,
	$rule_type, $name, $depender_definition, $builder_sub, $node_subs,
	) ;
}

#-------------------------------------------------------------------------------

sub ReplaceRuleTo
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = shift ;

my @rule_definition = @_ ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $config = 
	{
	PBS::Config::ExtractConfig
		(
		PBS::Config::GetPackageConfig($package),
		$pbs_config->{CONFIG_NAMESPACES},
		)
	} ;

RunUniquePluginSub($pbs_config, 'AddRule', $package, $config, $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition ;
my ($name, $rule_type) ;

unless('' eq ref $class)
	{
	PrintError "Rules: '$name' class name expected as first argument\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	die "\n" ;
	}

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		PrintError "Rules: '$name' expecting a string or an array ref" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}
	}

my ($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RemoveRule($package,$class, $name) ;
RegisterRule
	(
	$pbs_config, $config,
	$file_name, $line,
	$package, $class,
	$rule_type, $name, $depender_definition, $builder_sub, $node_subs,
	) ;
}

#-------------------------------------------------------------------------------

sub RegisterRule
{
my 
	(
	$pbs_config, $config,
	$file_name, $line,
	$package, $class,
	$rule_types, $name, $depender_definition, $builder_definition, $node_subs
	) = @_ ;

my %rule_type = map { $_ => 1 } @$rule_types ;

if (exists $rule_type{__NOT_ACTIVE})
	{
	PrintWarning "Depend: rule '$name' is not active @ $file_name:$line\n" if $pbs_config->{DISPLAY_INACTIVE_RULES} ;
	return ;
	}

# this test is mainly to catch the error when the user forgot to write the rule name.
my %valid_types = map{ ("__$_", 1)} qw(FIRST LAST MULTI UNTYPED NOT_ACTIVE VIRTUAL LOCAL FORCED INTERNAL IMMEDIATE_BUILD BUILDER_OVERRIDE) ;
for my $rule_type (@$rule_types)
	{
	my $order_regex = join '|', qw(indexed before first_plus after match_after last_minus) ;

	unless (exists $valid_types{$rule_type} || $rule_type =~ /^\s*$order_regex\s/i)
		{
		PrintError "Rules: '$name' invalid type '$rule_type'\n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		die "\n" ;
		}
	}
	
if(exists $package_rules{$package}{$class})
	{
	for my $rule (@{$package_rules{$package}{$class}})
		{
		if($rule->{NAME} eq $name)
			{
			PrintError "Rules: '$name' already registered\n" ;
			PbsDisplayErrorWithContext $pbs_config, $rule->{FILE}, $rule->{LINE} ;
			PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;

			die "\n" ;
			}
		}
	}

my ($builder_sub, $node_subs1, $builder_generated_types) = GenerateBuilder($pbs_config, $config, $builder_definition, $package, $name, $file_name, $line) ;
$builder_generated_types ||= {} ;

my ($depender_sub, $node_subs2, $depender_generated_types) = GenerateDepender($pbs_config, $config, $file_name, $line, $package, $class, $rule_types, $name, $depender_definition) ;
$depender_generated_types  ||= [] ; 

my $origin = ":$package:$class:$file_name:$line";
	
for my $rule_type (@$rule_types)
	{
	$rule_type{$rule_type}++
	}
	
if($rule_type{__VIRTUAL} && $rule_type{__LOCAL})
	{
	PrintError "Rules 'VIRTUAL' and 'LOCAL' are not compatible\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	die "\n" ;
	}
	
my $rule_definition = 
	{
	TYPE                => $rule_types,
	NAME                => $name,
	ORIGIN              => $origin,
	PACKAGE             => $package,
	FILE                => $file_name,
	LINE                => $line,
	DEPENDER            => $depender_sub,
	TEXTUAL_DESCRIPTION => $depender_definition, # keep a visual on how the rule was defined,
	BUILDER             => $builder_sub,
	NODE_SUBS           => $node_subs,
	%$builder_generated_types,
	} ;

$rule_definition->{PBS_STACK} = GetPbsStack($pbs_config, "RegisterRule $name") if ($pbs_config->{DEBUG_TRACE_PBS_STACK}) ;

if(defined $node_subs)
	{
	if('ARRAY' eq ref $node_subs)
		{
		for my $node_sub (@$node_subs)
			{
			if('CODE' ne ref $node_sub)
				{
				PrintDebug DumpTree($rule_definition, "Rule: definition") ;
				PrintError "Rules: '$name' invalid node sub, expecting a sub or a sub array\n" ;
				PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
				die "\n" ;
				}
			}
		}
	elsif('CODE' eq ref $node_subs)
		{
		$node_subs = [$node_subs] ;
		}
	else
		{
		PrintDebug DumpTree \@_, "Rules: RegisterRule" ;
		PrintError "Rules: '$name' invalid node sub, expecting a sub or a sub array\n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}
	}
else
	{
	$node_subs = [] ;
	}
	
push @$node_subs, @$node_subs1 if $node_subs1 ;
push @$node_subs, @$node_subs2 if $node_subs2 ;

$rule_definition->{NODE_SUBS} = $node_subs if @$node_subs ;

if(defined $pbs_config->{DEBUG_DISPLAY_RULES})
	{
	my $class_info = "[$class" ;
	#$class_info .= ' ' if $rule_type{};
	$class_info .= ']' ;
		
	if('HASH' eq ref $depender_definition)
		{
		PrintInfo("PBS: Adding subpbs rule: '$name' $class_info")  ;
		}
	else
		{
		PrintInfo("PBS: Adding rule: '$name' $class_info")  ;
		}
		
	PrintInfo(DumpTree($rule_definition)) if defined $pbs_config->{DEBUG_DISPLAY_RULE_DEFINITION} ;
	PrintInfo("\n")  ;
	}

push @{$package_rules{$package}{$class}}, $rule_definition ;

return($rule_definition) ;
}

#-------------------------------------------------------------------------------

sub RemoveRule
{
# if no name is given, all the rules in the package-class are removed.

my ($package, $class, $name) = @_ ;

if(defined $name)
	{
	if(exists $package_rules{$package}{$class})
		{
		my $rules = $package_rules{$package}{$class} ;
		
		my @new_rules;
		
		for my $rule (@$rules)
			{
			if($rule->{NAME} !~ /^$name($|(\s+:))/)
				{
				push @new_rules, $rule ;
				}
			else
				{
				#~print "Removing rule: '$rule->{NAME}'\n" ; 
				}
			}
			
		$package_rules{$package}{$class} = \@new_rules ;
		}
	}
else
	{
	delete $package_rules{$package}{$class} ;
	}
	
$name ||= 'NO_NAME!' ;	

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
PrintInfo("PBS: Removing Rule: ${package}::${class}::${name}\n") if defined $pbs_config->{DEBUG_DISPLAY_RULES} ;
}

#-------------------------------------------------------------------------------

sub DisplayAllRules
{
PrintInfo(DumpTree(\%package_rules, 'PBS: All rules:')) ;
}

#-------------------------------------------------------------------------------

use Sub::Name ;

sub BuildOk
{
# Syntactic sugar, this function can be called instead for 
# defining a closure or giving a sub ref

my $message = shift ;
my $print   = shift ; 

my ($package, $file_name, $line) = caller() ;

return subname BuildOk => sub
	{
	PrintInfo3("BuildOk: $message\n") if defined $message ;
	return(1, $message // 'BuildOk: no message') ;
	} ;
}

sub TouchOk
{
#builder
subname TouchOk => sub
	{
	my (undef, $file_to_build) = @_ ;

	local $PBS::Shell::silent_commands = 1 ;

	RunShellCommands "touch $file_to_build" ;
	} ;
}

#-------------------------------------------------------------------------------

sub AddSubpbsRules
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

for(@_)
	{
	__AddSubpbsRule($package, $file_name, $line, $_) ;
	}
}

sub AddSubpbsRule
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

__AddSubpbsRule($package, $file_name, $line, \@_) ;
}

*Subpbs=\&AddSubpbsRule ;
*subpbs=\&AddSubpbsRule ;

sub __AddSubpbsRule
{
# Syntactic sugar, this function can be called instead for 
# AddRule .. { subpbs_definition}
# the compulsory arguments come first, then one can pass 
# key-value pairs as in a normal subpbs definition

my ($package, $file_name, $line, $rule_definition) = @_ ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $config = 
	{
	PBS::Config::ExtractConfig
		(
		PBS::Config::GetPackageConfig($package),
		$pbs_config->{CONFIG_NAMESPACES},
		)
	} ;

my ($rule_name, $node_regex, $Pbsfile, $pbs_package, @other_setup_data) 
	= RunUniquePluginSub($pbs_config, 'AddSubpbsRule', $package, $config, $file_name, $line, $rule_definition) ;

RegisterRule
	(
	$pbs_config, $config,
	$file_name, $line, $package,
	'User',
	[UNTYPED],
	$rule_name,
	{
	  NODE_REGEX         => $node_regex,
	  PBSFILE            => $Pbsfile,
	  PACKAGE            => $pbs_package,
	  @other_setup_data,
	  },
	undef,
	undef,
	) ;
}

#-------------------------------------------------------------------------------

sub GetRuleTypes
{
my ($rule) = @_ ;

my @rule_types ;

push @rule_types, 'V'  if any { VIRTUAL eq $_ } @{$rule->{TYPE}} ;
push @rule_types, 'M'  if defined $rule->{MULTI} ;

push @rule_types, (any { BUILDER_OVERRIDE eq $_ } @{$rule->{TYPE}}) 
			? 'BO'
			: defined $rule->{BUILDER}
				? 'B'
				: () ;

push @rule_types, 'F'  if any { FORCED eq $_ } @{$rule->{TYPE}} ;
push @rule_types, 'S'  if defined $rule->{NODE_SUBS} ;
push @rule_types, 'L'  if any { LOCAL eq $_ } @{$rule->{TYPE}} ;

my $rule_type = @rule_types ? ' [' . join(', ', @rule_types) . ']' : '' ;

}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Rules - Manipulate PBS rules

=head1 SYNOPSIS

	# within a Pbsfile
	AddRule 'all_lib', ['all' => qw(lib.lib)], BuildOk() ;
	AddRule 'test', ['test' => 'all', 'test1', 'test2'] ;
	

=head1 DESCRIPTION

This modules defines a set of functions to add, remove and replace B<PBS> rules. B<PBS> rules can be written
in pure perl code or with a syntax ressembling that of I<make>. I<RegisterRule> converts the I<make> like 
definitions to perl code when needed.

=head2 EXPORT

	AddRule AddRuleTo 
	AddSubpbsRule 
	RemoveRule 
	ReplaceRule ReplaceRuleTo 
	BuildOk

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
