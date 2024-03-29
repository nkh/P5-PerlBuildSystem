
package PBS::Triggers ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(AddTrigger Trigger trigger ImportTriggers Triggers triggers) ;
our $VERSION = '0.01' ;

use Data::TreeDumper ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
use Text::Balanced qw(extract_codeblock) ;

use PBS::Constants ;
use PBS::Output ;
use PBS::PBSConfig ;
use PBS::Plugin ;
use PBS::Rules ;

#-------------------------------------------------------------------------------

# Triggers let the user insert dependency trees within the current 
# dependency tree, PBS might then have multiple roots to handle

#-------------------------------------------------------------------------------

my %triggers ;

#-------------------------------------------------------------------------------

sub GetTriggerRules
{
my $package = shift ;

return exists $triggers{$package} 
	? @{$triggers{$package}}
	: () 
}

#-------------------------------------------------------------------------------

sub AddTrigger
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my(@trigger_definition) = @_ ;
my $trigger_definition = \@trigger_definition ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
my $config = 
	{
	PBS::Config::ExtractConfig
		(
		PBS::Config::GetPackageConfig($package),
		$pbs_config->{CONFIG_NAMESPACES},
		)
	} ;


my ($name, $triggered_and_triggering) = RunUniquePluginSub($pbs_config, 'AddTrigger', $package, $config, $file_name, $line, $trigger_definition) ;

# the trigger definition is either
#1/ the name of the triggered tree followed by simplified dependency regexes
#2/ a sub that returns (1, 'trigged_node_name') on success or (0, 'error message')

RegisterTrigger
	(
	$file_name, $line,
	$package,
	$name,
	$triggered_and_triggering,
	) ;
}

*Trigger=\&AddTrigger ;
*trigger=\&AddTrigger ;

#-------------------------------------------------------------------------------

sub RegisterTrigger
{
my ($file_name, $line, $package, $name, $trigger_definition) = @_ ;
#~ print "RegisterTrigger $name in package $package.\n" ;

my $depender_sub ;
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

# verify we don't use the same trigger name twice
if(exists $triggers{$package})
	{
	for my $trigger (@{$triggers{$package}})
		{
		if
			(
			$trigger->{NAME} eq $name
			&& 
				(
				   $trigger->{FILE} ne $file_name
				|| $trigger->{LINE} ne $line
				)
			)
			{
			PrintError "Triggers: '$name' already defined\n" ;
			PbsDisplayErrorWithContext $pbs_config, $trigger->{FILE},$trigger->{LINE} ;
			PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
			die "\n" ;
			}
		}
	}
	
my $trigger_sub ;
	
if('ARRAY' eq ref $trigger_definition)
	{
	unless(@$trigger_definition)
		{
		PrintError "Triggers: '$name' invalid definition\n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}

	my($triggered_node, @triggers) = @$trigger_definition;
	
	my @trigger_regexes ;
	
	unless(file_name_is_absolute($triggered_node) || $triggered_node =~ /^\.\//)
		{
		$triggered_node = "./$triggered_node" ;
		}
		
	$trigger_sub = sub 
			{
			my $trigger_to_check = shift ; 
			
			for my $trigger_regex (@triggers)
				{
				if($trigger_to_check =~ $trigger_regex)
					{
					return(1, $triggered_node) ;
					}
				}
				
			return(0, "'$trigger_to_check' didn't match any trigger definition") ;
			}
	}
else
	{
	if('CODE' eq ref $trigger_definition)
		{
		$trigger_sub = $trigger_definition ;
		}
	else
		{
		PrintError "Trigger: invalid definition, expecting an array ref or a code reference\n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}
	}
	
my $origin = ":$package:$file_name:$line" ;
	
my $trigger_rule = 
	{
	NAME                => $name,
	ORIGIN              => $origin,
	FILE                => $file_name,
	LINE                => $line,
	DEPENDER            => $trigger_sub,
	TEXTUAL_DESCRIPTION => $trigger_definition, # keep a visual on how the rule was defined
	} ;

if(defined $pbs_config->{DEBUG_DISPLAY_TRIGGER_RULES})
	{
	PrintInfo("Trigger: Registering $name$origin\n")  ;
	PrintInfo2(DumpTree($trigger_rule, 'trigger rule:')) if defined $pbs_config->{DEBUG_DISPLAY_TRIGGER_RULE_DEFINITION} ;
	}

push @{$triggers{$package}}, $trigger_rule ;
}

#-------------------------------------------------------------------------------

sub DisplayAllTriggers
{
PrintInfo DumpTree(\%triggers, 'Triggers:') ;
}

#-------------------------------------------------------------------------------

my %imported_triggers ; # used to not re-import the same triggers

sub ImportTriggers
{
# this will import the triggers defined in another Pbsfile,
# it allows us to define the rules and the triggers in the same file
# sub defining the triggers must be called 'sub ExportTriggers'

my ($package, $file_name, $line) = caller() ;
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

for my $Pbsfile (@_)
	{
	if(exists $imported_triggers{"$package=>$Pbsfile"})
		{
		PrintWarning
			"At $file_name:$line: Triggers from '$Pbsfile' have already been imported in package '$package'"
				. "@ "
				. $imported_triggers{"$package=>$Pbsfile"}{FILE}
				. ':'
				. $imported_triggers{"$package=>$Pbsfile"}{LINE}
				. ". Ignoring.\n" ;
			
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		PbsDisplayErrorWithContext $pbs_config, $imported_triggers{"$package=>$Pbsfile"}{FILE}, $imported_triggers{"$package=>$Pbsfile"}{LINE} ;
		}
	else
		{
		open TRIGGERS, '<', $Pbsfile or die ERROR "Can't open '$Pbsfile' for Triggers import at $file_name:$line: $!\n" ;
		local $/ = undef ;
		my $pbsfile_code = <TRIGGERS> ;
		
		my ($trigger_exports_definition, undef, $skipped) = extract_codeblock($pbsfile_code,"{", '(?s).*?sub\s+ExportTriggers\s*(?={)');
		
		my $definition_line = $skipped =~ tr[\n][\n];
		
		close(TRIGGERS) ;
	
		if($trigger_exports_definition  eq '')
			{
			PrintWarning "No 'ExportTriggers' sub in '$Pbsfile' at $file_name:$line.\n" ;
			}
		else
			{
			my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
			unless(defined $pbs_config->{NO_TRIGGER_IMPORT_INFO})
				{
				PrintInfo "Trigger: Importing from '$Pbsfile:$definition_line' @ "
						 . GetRunRelativePath($pbs_config, $file_name) . ":$line.\n"  ;
			 	}
			   
			$trigger_exports_definition =~ s/sub\s+ExportTriggers// ;
			
			$definition_line-- ; # reserve room for #line ...
			$trigger_exports_definition = "#line $definition_line $Pbsfile\npackage $package ;\n" . $trigger_exports_definition ;
			
			#~ PrintInfo "$trigger_exports_definition\n" ;
			
			eval $trigger_exports_definition ;
			die $@ if $@ ;
			
			$imported_triggers{"$package=>$Pbsfile"} = {FILE => $file_name, LINE => $line} ;
			}
		}
	}
}

*Triggers=\&ImportTriggers ;
*triggers=\&ImportTriggers ;

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Triggers  -

=head1 SYNOPSIS

	# within a Pbsfile
	AddTrigger 'trigger_name', ['node_to_be triggered' => 'triggering_node_1', 'triggering_node_2'] ;
	
	ImportTriggers('/.../Pbsfile.pl') ; #import triggers from given file

=head1 DESCRIPTION

=head2 EXPORT

	AddTrigger ImportTriggers

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
