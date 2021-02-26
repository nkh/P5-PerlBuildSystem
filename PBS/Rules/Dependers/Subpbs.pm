package PBS::Rules::Dependers::Subpbs ;

use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateSubpbsDepender) ;
our $VERSION = '0.01' ;

use File::Basename ;
use File::Spec::Functions qw(:ALL) ;
use List::Util qw(any) ;

use Data::TreeDumper ;

use PBS::PBSConfig ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Rules ;

#-------------------------------------------------------------------------------

sub GenerateSubpbsDepender
{
my ($pbs_config, $config, $file_name, $line, $package, $class, $rule_types, $name, $depender_definition, $builder_sub) = @_ ;

# sub pbs definition
for my $key (keys %$depender_definition)
	{
	if($key !~ /^[A-Z_]+$/)
		{
		PrintError "Rules: '$name' keys must be upper case: '$key'\n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		die "\n" ;
		}
	}
	
unless(exists $depender_definition->{NODE_REGEX})
	{
	PrintError "'$name' no 'NODE_REGEX'\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
	die "\n" ;
	}
	
unless(exists $depender_definition->{PBSFILE})
	{
	PrintError "'$name' no PBSFILE\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
	die "\n" ;
	}
	
unless
	(
	   exists $depender_definition->{PACKAGE}
	&& defined $depender_definition->{PACKAGE} 
	&& '' eq ref $depender_definition->{PACKAGE}
	&& '' ne $depender_definition->{PACKAGE}
	)
	{
	PrintError "Rules: '$name' Invalid or missing 'PACKAGE'\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
	die "\n" ;
	}
	
if(exists $depender_definition->{ALIAS})
	{
	if($depender_definition->{ALIAS} eq '')
		{
		PrintError "Rules: '$name' Empty alias\n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		die "\n" ;
		}
	
	unless(file_name_is_absolute($depender_definition->{ALIAS}) || $depender_definition->{ALIAS} =~ /^\.\//)
		{
		$depender_definition->{ALIAS} = './' . $depender_definition->{ALIAS} ;
		}
	}
	
$pbs_config = GetPbsConfig($package) ;

if(exists $depender_definition->{BUILD_DIRECTORY} && !file_name_is_absolute($depender_definition->{BUILD_DIRECTORY}))
	{
	$depender_definition->{BUILD_DIRECTORY} =~ s/^\.\/// ;
	$depender_definition->{BUILD_DIRECTORY} = $pbs_config->{BUILD_DIRECTORY} . '/' . $depender_definition->{BUILD_DIRECTORY} ;
	}
	
my $sub_pbs_dependent_regex ;

if(ref $depender_definition->{NODE_REGEX} eq 'Regexp')
	{
	$sub_pbs_dependent_regex = $depender_definition->{NODE_REGEX} ;
	}
else
	{
	PrintError "Rules: '$name' NODE_REGEX is not a perl regex\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	die "\n" ;
	}

PBS::PBSConfig::CheckPackageDirectories($depender_definition) ;

sub 
	{
	my ($dependent, $config, $tree) = @_ ;

	my $node_name_matches_ddrr = 0 ;
	if ($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
		{
		$node_name_matches_ddrr = any { $dependent =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}} ;
		$node_name_matches_ddrr = 0 if any { $dependent =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX_NOT}} ;
		$node_name_matches_ddrr = 1 if any { $name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_RULE_NAME}} ;
		$node_name_matches_ddrr = 0 if any { $name =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT}} ;
		}

	PrintInfo2 "${PBS::Output::indentation}$depender_definition->{NODE_REGEX} [$sub_pbs_dependent_regex]. Subpbs rule '$name' @ $file_name:$line.\n"
		if $node_name_matches_ddrr ;
	
	return $dependent =~ /^$sub_pbs_dependent_regex$/
		? (1, $depender_definition) 
		: (0, "No Match subpbs '$sub_pbs_dependent_regex'") ;
	}
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Rules::Dependers::Subpbs -

=head1 DESCRIPTION

This package provides support function for B<PBS::Rules::Rules>

=head2 EXPORT

Nothing.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
