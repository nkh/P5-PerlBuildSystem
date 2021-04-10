
package PBS::Caller ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(CC CCP) ;
our $VERSION = '0.01' ;

#-----------------------------------------------------------------------------------------------------------------------------------

my @routes ;

#-----------------------------------------------------------------------------------------------------------------------------------
sub CC
{
my ($fence, $cc, $package, $at) = @_ ;

my ($p, $f, $l) = caller ;

push @routes, { at => $at // "$p:$f:$l", cc  => $cc // [$p, $f,  $l], p => $package // $p } ;

$routes[-1]{fence}++ if $fence ;

my $h ;
bless \$h, __PACKAGE__ ;
}

sub CCP
{
my ($fence) = @_ ;
my ($p, $f, $l) = caller(1) ;

$f =~ s/^'// ; $f =~ s/'$// ;

CC $fence, [$p, $f,  $l], $p, "$p:$f:$l"
}


sub caller
{
my ($p, $f, $l) = caller(1) ;
#say "caller() called  at $p $f $l ". scalar(@routes) . "\n" ;

return ($p, $f, $l) unless @routes ;

return caller(1) if $routes[-1]{p} ne $p ;

my $r ;
for (reverse 0 .. @routes - 1)
	{
	$r = $routes[$_] ;
	
	# crawl up the stack while package is $p and we meet a fence
	last if $r->{p} ne $p || $r->{fence} ;
	}

#SDT $r, "caller @ $p:$f:$l" ;

@{$r->{cc}}
}
 
sub DESTROY { pop @routes }

my $packagename = CORE::caller ;
no strict 'refs' ;
*{"$packagename\::caller"} = \&caller ;


#-----------------------------------------------------------------------------------------------------------------------------------

1 ;

__END__

=head1 NAME

Caller -

=head1 SYNOPSIS

=head1 DESCRIPTION

Override caller to set skip points in the call stack

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda

=head1 SEE ALSO

Sub::Caller
Caller::Easy
Safe::Caller
Call::From
Import::Into
Eval::Quosure

=cut
