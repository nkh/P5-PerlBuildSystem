
use strict ;
use warnings ;

use File::Find;

my $regex = $ARGV[0] or die "Missing regex";
my $n = $ARGV[1] || 1 ;

for (1 .. $n)
	{
	my $deepest = find_deepest($regex) ;
	print "$deepest\n" ;
	unlink $deepest or die "Can't unlink\n"
	}

# Euuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuurk!

my $deepest_path = '' ;
my $deepest = -1 ;
my $filter = '' ;

sub find_deepest
{
($filter) = @_ ;

$deepest_path = '' ;
$deepest = -1 ;

finddepth(\&wanted, '.');

return $deepest_path ;
}

sub wanted 
{
my $depth = $File::Find::name =~ tr[/][/] ;

if($File::Find::name =~ /$filter/o  && $depth > $deepest)
	{
	$deepest = $depth ;
	$deepest_path = $File::Find::name ;
	}
}
	    
