
package PBS::Node;

use v5.10 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GetInsertionFile GetInsertionRule GetNodeBuildName GetBuildName) ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

sub GetInsertionRule
{
my ($tree) = @_ ;

exists $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
	? $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_RULE}
	: $tree->{__INSERTED_AT}{INSERTION_RULE}
}

#-------------------------------------------------------------------------------

sub GetInsertionFile
{
my ($tree) = @_ ;

exists $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}
	? $tree->{__INSERTED_AT}{ORIGINAL_INSERTION_DATA}{INSERTION_FILE}
	: $tree->{__INSERTED_AT}{INSERTION_FILE}
}

#-------------------------------------------------------------------------------

sub GetNodeBuildName
{
my ($tree) = @_ ;

my($full_name, $is_alternative_source, $alternative_index) = 
	GetBuildName($tree->{__NAME}, $tree->{__PBS_CONFIG}) ;

if ($is_alternative_source)
	{
	$tree->{__ALTERNATE_SOURCE_DIRECTORY} =  $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES}[$alternative_index] ;
	}
else
	{
	$tree->{__SOURCE_IN_BUILD_DIRECTORY} = 1 ;
	}

$full_name = $tree->{__FIXED_BUILD_NAME} if exists $tree->{__FIXED_BUILD_NAME} ;

$full_name
}

#-------------------------------------------------------------------------------

sub GetBuildName
{
my ($name, $pbs_config) = @_ ;

LocateSource
	$name,
	$pbs_config->{BUILD_DIRECTORY},
	$pbs_config->{SOURCE_DIRECTORIES},
	$pbs_config->{DISPLAY_SEARCH_INFO},
	$pbs_config->{DISPLAY_SEARCH_ALTERNATES},
}

#-------------------------------------------------------------------------------
1 ;

