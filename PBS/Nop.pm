
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
our @EXPORT = qw(AddRule Rule rule AddRuleTo AddSubpbsRule Subpbs subpbs AddSubpbsRules ReplaceRule ReplaceRuleTo RemoveRule BuildOk TouchOk) ;
our $VERSION = '0.01' ;

sub AddRule {}
sub Rule {}
sub rule {}
sub AddRuleTo {}
sub AddSubpbsRule {}
sub Subpbs {}
sub subpbs {}
sub AddSubpbsRules {}
sub ReplaceRule {}
sub ReplaceRuleTo {}
sub RemoveRule {}
sub BuildOk {}
sub TouchOk {}

1 ;
