
use lib qw(.) ;

use strict ;
use warnings ;
use Data::Dumper ;

use Dependency ;
use Build ;
use BuiltinRules ;

main(@ARGV) ;

#-------------------------------------------------------------------------------
sub main
{
my $target = shift || '' ;
die "What should I build?" if $target eq '' ;

my $dependency_rules = BuiltinRules::GetRules() ;

# find all c sources
my @all_source_files = qw(a.c b.c) ;

# compute the o files
my @all_object_files = map{ s/\.c/\.o/ && $_ ; } @all_source_files ;

# add rule (dynamically)
push @{$dependency_rules}, [sub {$_ = shift ; /^exe$/i   && return (1, @all_object_files); }] ;

my %dependency_tree = ($target => undef) ;
my %inserted_files ;

Dependency::BuildDependencyTree
	(
	  'Root'
	, \%dependency_tree
	, \%inserted_files
	, $dependency_rules
	) ;
							
print "BuildDependencyTree calls: $Dependency::global_BuildDependencyTree_calls\n" ;
#$Data::Dumper::Indent = 1 ;
#print Data::Dumper->Dump([\%dependency_tree], ['dependency_tree']) ;
#print Data::Dumper->Dump([\%inserted_files], ['inserted_files']) ;

my @build_sequence ;
my %trigged_files ;

Dependency::CheckDependencyTree
	(
	  'Root'
	, \%dependency_tree
	, \&Dependency::CheckTimeStamp
	, \@build_sequence
	, \%trigged_files
	) ;
	
print Data::Dumper->Dump([\%dependency_tree], ['trigged_tree']) ;
#print Data::Dumper->Dump([\@build_sequence], ['build_sequence']) ;
#print Data::Dumper->Dump([\%trigged_files], ['trigged_files']) ;

Build::Build(\@build_sequence, $dependency_rules) ;
}


