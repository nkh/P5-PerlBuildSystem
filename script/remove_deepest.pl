
use v5.10 ; use strict ; use warnings ;

use File::Find;
use Tie::Array::Sorted ;

my $regex = $ARGV[0] or die "Missing regex";
my $n = $ARGV[1] || 1 ;


tie my @found_files, 'Tie::Array::Sorted', sub {$_[0][0] <=> $_[1][0]} ;

finddepth(\&wanted, '.');

unlink  $_->[1] for @found_files ;

#-------------------------------------------------------------------

sub wanted 
{

if($File::Find::name =~ /$regex/o)
	{
	my $depth = $File::Find::name =~ tr[/][/] ;
	push @found_files, [$depth, $File::Find::name] ;  
	
	shift @found_files if @found_files > $n ;
	}
}
	    
