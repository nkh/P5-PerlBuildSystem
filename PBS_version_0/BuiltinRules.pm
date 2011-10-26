
use strict ;
use warnings ;
use Data::Dumper ;

package BuiltinRules ;

my @lots_of_files = qw(1 2 3 4) ;

#-------------------------------------------------------------------------------
sub GetRules
{
my $file_name = shift ;

return
	(
		[
		  [sub {$_ = shift ; /^all$/i   && return (1, ('exe')); }]
		, [sub {$_ = shift ; /^exe$/i   && return (1) ; }, \&BuiltinRules::BuildAnExe]
		, [sub {$_ = shift ; /(.*)\.o$/ && return (1, ("$1.c")); }]
		, [sub {$_ = shift ; /(.*)\.c$/ && return (1, ("$1.h")); }]
		, [sub {$_ = shift ; /(.*)\.h$/ && return (1, qw(x.z3)); }]
		, [sub {$_ = shift ; /x\.z3$/   && return (1, @lots_of_files); }]
		]
	) ;
}

#-------------------------------------------------------------------------------
sub BuildAnExe
{
my $file_to_build           = shift ;
my @dependencies            = split /\s+/, shift() ;
my @triggering_dependencies = split /\s+/, shift() ;


print "\t\t=> ho, ho, ho let santa build $file_to_build [with @dependencies], because of @triggering_dependencies.\n" ;
}

#-------------------------------------------------------------------------------
1 ;

