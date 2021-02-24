
package PBS::PrfNop ;

use 5.006 ;
use strict ;
use warnings ;
use Data::TreeDumper ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(AddTargets target AddCommandLineSwitches pbsconfig) ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

sub AddTargets {}
*target=\&AddTargets ;

sub AddCommandLineSwitches {}
*pbsconfig=\&AddCommandLineSwitches ;

1 ;

#-------------------------------------------------------------------------------

__END__
=head1 NAME

PBS::PrfNop - NOP prf function


=head1 DESCRIPTION


=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut

