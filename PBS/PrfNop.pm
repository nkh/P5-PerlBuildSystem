
package PBS::PrfNop ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(AddTargets target AddCommandLineSwitches pbsconfig) ;
our $VERSION = '0.01' ;

use Data::TreeDumper ;

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

