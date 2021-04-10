
package PBS::Warp::Warp0 ;
use PBS::Debug ;

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
use PBS::Digest ;
use PBS::Log ;
use PBS::Output ;
use PBS::Plugin;
use PBS::Warp;

#-------------------------------------------------------------------------------

sub Warp
{
my ($targets, $pbs_config) = @_ ;
	
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/.warp0';
my ($sec,$min,$hour,$mday,$mon) = localtime(time);
my $now_string                  = "${mday}_${mon}_${hour}_${min}_${sec}" ;
$pbs_config->{TRIGGERS_FILE}    = "$warp_path/Triggers_${now_string}.pl" ;

mkpath($warp_path) unless(-e $warp_path) ;

{}, 1, sub {}
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Warp::Warp0  -

=head1 DESCRIPTION

Run PBS without Warp.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

=cut
