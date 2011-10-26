
use strict ;
use warnings ;
use Data::Dumper ;

package Dependency ;

our $global_BuildDependencyTree_calls = 0 ;

#-------------------------------------------------------------------------------
sub BuildDependencyTree
{
my $parent_name      = shift ;
my $tree             = shift ;
my $inserted_files   = shift ;
my $dependency_rules = shift ;

$global_BuildDependencyTree_calls++ ;

# check cyclic graph
$tree->{__LOCK}++ ;

# depend sub tree once only flag
$tree->{__DEPENDED}++ ;

my %entries_with_dependencies ;

for my $dependent_file (keys %$tree)
	{
	next if $dependent_file =~ /^__/ ; # eliminate private data
	
	for(my $rule_index = 0 ; $rule_index < @$dependency_rules ; $rule_index++)
		{
		my ($triggered, @dependency_files) = $dependency_rules->[$rule_index][0]->($dependent_file) ;
		
		if($triggered)
			{
			if(exists $tree->{$dependent_file}{__LOCK})
				{
				warn "Cyclic dependency detected!\n\n" ;
				#$Data::Dumper::Indent = 1 ;
				warn Data::Dumper->Dump([$tree->{$dependent_file}], ['Cyclic dependency']) ;
				exit(1) ;
				}
				
			next if exists $tree->{$dependent_file}{__DEPENDED} ;
				
			push @{$tree->{$dependent_file}{__RULE}}, [$rule_index => [@dependency_files] || '__No_dependencies'] ;
			
			for (@dependency_files)
				{      	
				if($dependent_file eq $_)
					{
					my $dependencies = join ' ', @dependency_files ;
					warn "Self referencial rule $rule_index for $dependencies.\n" ;
					exit(1) ;
					next ;
					}
					
				$inserted_files->{$_} = {__RULE => []} unless exists $inserted_files->{$_} ;
				$tree->{$dependent_file}{$_} = $inserted_files->{$_} ;
				}
				
			$entries_with_dependencies{$dependent_file}++ ;
			}
		}
	}
	
for my $entry (keys %entries_with_dependencies)
	{
	BuildDependencyTree($entry, $tree->{$entry}, $inserted_files, $dependency_rules) ;
	}

delete($tree->{__LOCK}) ;
return($tree) ;
}	

#-------------------------------------------------------------------------------
sub CheckDependencyTree
{
my $parent_name    = shift ;
my $tree           = shift ;
my $trigger_rule   = shift ;
my $build_sequence = shift ; #output
my $trigged_files  = shift ; #output

my $any_triggered = 0 ;

$tree->{__BUILD_SEQUENCE}++ ;
for my $dependent_file (keys %$tree)
	{
	my $triggered                 = 0 ;
	my $trigger_list              = '' ;
	my $triggered_dependency_list = '' ; # $?
	my $dependency_list           = '' ; # all dependencies
	
	next if $dependent_file =~ /^__/ ; # eliminate private data
		
	push @{$tree->{$dependent_file}{__DEPENDENT}}, $parent_name ;

	# optimize tree traversal. Remove branches that have a build sequence.
	if(exists $tree->{$dependent_file}{__BUILD_SEQUENCE})
		{
		$tree->{$dependent_file}{__BUILD_SEQUENCE}++ ;
		next ;
		}
	
	# check dependencies sub trees
	if(CheckDependencyTree($dependent_file, $tree->{$dependent_file}, $trigger_rule, $build_sequence, $trigged_files))
		{
		push @{$tree->{$dependent_file}{__TRIGGERED}}, "__Subdependency" ;
		
		$trigger_list .= " __Subdependency " ;
		$triggered_dependency_list .= " __Subdependency " ;
		$triggered++ ;
		$any_triggered++ ;
		}
	
	for my $dependency (keys %{$tree->{$dependent_file}})
		{
		next if $dependency =~ /^__/ ; # eliminate private data
		
		$dependency_list .= "$dependency " ; # $<
		
		if(-e $dependency)
			{
			my ($build, $why) = $trigger_rule->($dependent_file, $dependency) ;
			if($build)
				{
				push @{$tree->{$dependent_file}{__TRIGGERED}}, $dependency ;
				
				$trigger_list .= " $why" ;
				$triggered_dependency_list .= " $dependency " ;
				$triggered++ ;
				$any_triggered++ ;
				}
			}
		else
			{
			next if exists $tree->{$dependent_file}{$dependency}{__DOESN_T_EXIST} ;
			$tree->{$dependent_file}{$dependency}{__DOESN_T_EXIST}++ ;
			
			push @{$tree->{$dependent_file}{$dependency}{__TRIGGERED}}, " Doesn't exist " ;
			
			# following data is for the non existing _dependency_!!!
			my $data =
				{
				  __NAME                   => $dependency
				, __RULE                   => $tree->{$dependent_file}{$dependency}{__RULE}
				, __WHY                    => "__Doesn_t_exist"
				, __DEPENDENCIES           => ''
				, __TRIGGERED_DEPENDENCIES => '__self'
				, __DEPENDENCY_TO          => $dependent_file
				} ;
				
			if(exists $trigged_files->{$dependency})
				{
				push @{$trigged_files->{$dependency}}, $data ;
				}
			else
				{
				$trigged_files->{$dependency} = [$data] ;
				push @$build_sequence, $trigged_files->{$dependency} ;
				}
			
			$trigger_list .= " $dependency doesn't exist " ;
			$triggered_dependency_list .= " $dependency" ;
			$triggered++ ;
			$any_triggered++ ;
			}
		}
		
	if($triggered)
		{
		my $data =
			{
			  __NAME                    => $dependent_file
			, __RULE                    => $tree->{$dependent_file}{__RULE}
			, __WHY                     => $trigger_list
			, __TRIGGERED_DEPENDENCIES  => $triggered_dependency_list
			, __DEPENDENCIES            => $dependency_list
			} ;
			
		if(exists $trigged_files->{$dependent_file})
			{
			push @{$trigged_files->{$dependent_file}}, $data ;
			}
		else
			{
			$trigged_files->{$dependent_file} = [$data] ;
			push @$build_sequence, $trigged_files->{$dependent_file}  ;
			}
		}
	else
		{
		#! want dependencies even if not triggered
		}
	}
	
return($any_triggered) ;
}

#-------------------------------------------------------------------------------
sub CheckTimeStamp
{
my $dependent  = shift ;
my $dependency = shift ;

if(-e $dependent)
	{
	my $dependent_time = (stat($dependent))[9] ;
	
	if((stat($dependency))[9] > $dependent_time)
		{
		return(1, "$dependency newer than $dependent") ;
		}
	}
}

#-------------------------------------------------------------------------------

1 ;

