
use strict ;
use warnings ;
use Data::Dumper ;

package Build ;

use constant BUILDER => 1 ;

#-------------------------------------------------------------------------------
sub Build
{
my $build_sequence = shift ;
my $dependencies_and_build_rules = shift ;

for my $actions (@$build_sequence)
	{
	my $name         = $actions->[0]{__NAME} ;
	my $dependencies = $actions->[0]{__DEPENDENCIES} ;
	my $triggered_dependencies = '' ;
	
	for my $action (@$actions)
		{
		$triggered_dependencies .= ' ' . $action->{__TRIGGERED_DEPENDENCIES} ;
		}
		
	print "Building $name : (dep: $dependencies trig: $triggered_dependencies)\n" ;
	
	for my $action (@$actions)
		{
		my $rule = $action->{__RULE} ;
		my $why  = $action->{__WHY} ;
		print "\t$why\n" ;

		for (@$rule)
			{
			my $dependencies = join ' ', @{$_->[1]} ;
			print "\t\t$_->[0] -> $dependencies\n" ;
			
			# how do we merge rules?
			if(defined $dependencies_and_build_rules->[$_->[0]][BUILDER])
				{
				$dependencies_and_build_rules->[$_->[0]][BUILDER]($name, $dependencies, $triggered_dependencies) ;
				}
		 	}
		
		}
	}
}

#-------------------------------------------------------------------------------

1 ;

