package PBS::Rules::Dependers::Subpbs ;

use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::TreeDumper ;
use Carp ;
use File::Spec::Functions qw(:ALL) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateSubpbsDepender) ;
our $VERSION = '0.01' ;

use File::Basename ;

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

return
	(
	sub 
		{
		my $dependent_to_check = shift ; 
		my $config             = shift ;
		my $tree               = shift ;
	
		if($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
			{
			PrintInfo2("${PBS::Output::indentation}$depender_definition->{NODE_REGEX} [$sub_pbs_dependent_regex]. Subpbs rule '$name' @ $file_name:$line.\n") ;
			}
		
		$dependent_to_check =~ /^$sub_pbs_dependent_regex$/ && return ([1, $depender_definition]) ;
		
		return([0, "No Match subpbs '$sub_pbs_dependent_regex'"]) ;
		}
	) ;
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
