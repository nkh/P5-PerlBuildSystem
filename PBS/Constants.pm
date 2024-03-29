package PBS::Constants ;

use v5.10 ; use strict ; use warnings ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
use vars qw($VERSION @ISA @EXPORT) ;

@ISA     = qw(Exporter) ;
@EXPORT  = qw(
		PBSFILE
		USER_BUILD_FUNCTION
		
		NEED_REBUILD
		
		DEPENDER
		DEPENDER_FILE_NAME
		DEPENDER_PACKAGE
		
		DEPEND_ONLY
		DEPEND_AND_CHECK
		DEPEND_CHECK_AND_BUILD
		
		TRIGGER_INSERTED
		
		UNTYPED untyped
		NOT_ACTIVE not_active NA
		VIRTUAL V virtual
		FORCED forced
		IMMEDIATE_BUILD immediate_build I
		BUILDER_OVERRIDE builder_override BO
		
		LOCAL
		
		MULTI multi
		FIRST first
		LAST last
		
		BUILD_SUCCESS
		BUILD_FAILED
		
		GET_DEPENDER_POSITION_INFO
		
		GRAPH_GROUP_NONE
		GRAPH_GROUP_PRIMARY
		GRAPH_GROUP_SECONDARY
		
		NOT_A_PACKAGE_DEPENDENCY
		
		CONFIG_PRF_SUCCESS
		CONFIG_PRF_ERROR
		CONFIG_PRF_FLAG_ERROR
		
		CONFIG_ENVIRONEMENT_VARIABLE_FLAG_ERROR
		CONFIG_ENVIRONEMENT_VARIABLE_FLAG_SUCCESS
		
		WATCH_TYPE_SEPARATOR
		WATCH_TYPE_FILE
		WATCH_TYPE_DIRECTORY
		) ;

$VERSION = '0.08' ;

# indexes for data stored in %loaded_packages in PBS.pm
use constant PBSFILE            => 0 ;
use constant USER_BUILD_FUNCTION=> 1 ;

#
use constant DEPENDER           => 1 ;
use constant DEPENDER_FILE_NAME => 0 ;
use constant DEPENDER_PACKAGE   => 1 ;

# node types --------------------------------------------------------
use constant TRIGGER_INSERTED   => '__TRIGGER_INSERTED' ;

# rule types --------------------------------------------------------
use constant UNTYPED            => '__UNTYPED' ;
use constant untyped            => '__UNTYPED' ;
use constant NOT_ACTIVE         => '__NOT_ACTIVE' ;
use constant not_active         => '__NOT_ACTIVE' ;
use constant NA                 => '__NOT_ACTIVE' ;
use constant VIRTUAL            => '__VIRTUAL' ;
use constant V                  => '__VIRTUAL' ;
use constant virtual            => '__VIRTUAL' ;
use constant LOCAL              => '__LOCAL' ;
use constant FORCED             => '__FORCED' ;
use constant forced             => '__FORCED' ;
use constant IMMEDIATE_BUILD    => '__IMMEDIATE_BUILD' ;
use constant I                  => '__IMMEDIATE_BUILD' ;
use constant immediate_build    => '__IMMEDIATE_BUILD' ;
use constant BUILDER_OVERRIDE   => '__BUILDER_OVERRIDE' ;
use constant builder_override   => '__BUILDER_OVERRIDE' ;
use constant BO                 => '__BUILDER_OVERRIDE' ;

use constant MULTI              => '__MULTI' ;
use constant multi              => '__MULTI' ;

use constant FIRST              => '__FIRST' ;
use constant first              => '__FIRST' ;
use constant LAST               => '__LAST' ;
use constant last               => '__LAST' ;

#builders results ---------------------------------------------------------------------

use constant BUILD_SUCCESS => 1 ;
use constant BUILD_FAILED  => 0 ;

# command types for PBS
use constant DEPEND_ONLY            => 0 ;
use constant DEPEND_AND_CHECK       => 1 ;
use constant DEPEND_CHECK_AND_BUILD => 2 ;

#
use constant GET_DEPENDER_POSITION_INFO => -12345 ;

# graph-------------------------------------------------------------------------------
use constant GRAPH_GROUP_NONE      => 0 ;
use constant GRAPH_GROUP_PRIMARY   => 1 ;
use constant GRAPH_GROUP_SECONDARY => 2 ;


# PbsUse -------------------------------------------------------------------------------
use constant NOT_A_PACKAGE_DEPENDENCY => 0 ;

#config -------------------------------------------------------------------------------
use constant CONFIG_PRF_SUCCESS    => 1 ;
use constant CONFIG_PRF_ERROR      => 2 ;
use constant CONFIG_PRF_FLAG_ERROR => 3 ;

use constant CONFIG_ENVIRONEMENT_VARIABLE_FLAG_ERROR   => 0 ;
use constant CONFIG_ENVIRONEMENT_VARIABLE_FLAG_SUCCESS => 1 ;

#file watcher -------------------------------------------------------------------------------
use constant WATCH_TYPE_SEPARATOR => '__PBS__WATCH_TYPE__' ;
use constant WATCH_TYPE_FILE      => 1 ; # system is able to watch individual files, typically linux with inotify
use constant WATCH_TYPE_DIRECTORY => 2 ; # system can only watch directories, typically windows

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Constants - definition of constants use within PBS

=head1 SYNOPSIS

  use PBS::Constants
  ...
  return(BUILD_OK, 'message) ;

=head1 DESCRIPTION

=head2 EXPORT

None by default.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO


=cut
