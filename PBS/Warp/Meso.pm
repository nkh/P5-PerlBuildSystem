
package PBS::Warp::Meso ;

use v5.10 ; use strict ; use warnings ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

use Cwd ;
use Data::Compare ;
use Data::Dumper ;
use File::Path;
use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Constants ;
use PBS::Debug ;
use PBS::Digest ;
use PBS::Log ;
use PBS::Output ;
use PBS::Plugin;
use PBS::Warp;

#-------------------------------------------------------------------------------

sub GenerateMeso 
{
my ($targets, $pbs_config, $parent_config) = @_ ;
	
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Warp::Meso  - 

=head1 DESCRIPTION

Generate a meso warp 

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

=cut
