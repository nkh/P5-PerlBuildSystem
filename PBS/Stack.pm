package PBS::Stack ;

use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GetPbsStack) ;
our $VERSION = '0.01' ;

sub GetPbsStack
{
my ($pbs_config, $tag) = @_ ;

# whichever calls this may not be run inside a PBS:Runs
# IE PBS registers a rule before loading the pbsfile to depend the target

# get stack from our caller back to the last PBS::Runs

my $current_level = 2 ; # skip this function 

my ($seen_pbs_run, @pbs_stack) = (0) ;

while ($current_level < 1_000_000) 
	{
	my  ($package, $filename, $line, $subroutine) = eval " package DB ; caller($current_level) " ;
	    
	last unless defined $package;
	
	$current_level++;

	my $pbs_package = $package =~ /^PBS::Runs/ ;

	$seen_pbs_run++ if $pbs_package ; 
	last if $seen_pbs_run && ! $pbs_package ; # got out of the pbsfile run

	$filename =~ s/^'// ;
	$filename =~ s/'$// ;
 
	unshift @pbs_stack, {PACKAGE => $package, SUB => $subroutine, FILE => $filename, LINE => $line} if $seen_pbs_run ;
	}

\@pbs_stack ;
}

1 ;

