
use File::Slurp ;

#----------------------------------------------------------------------------------------------------

sub AddConfigDependentRule
{
my ($name, $depender, $builder) = @_ ;

my ($dependent, $filter) = @{$depender} ; # more checking of $depender here

my $dependent_cache = $dependent . '_config_and_filter_cache' ;

AddRule $name, [$dependent => $dependent_cache] =>  $builder ;
AddRule $dependent_cache, [$dependent_cache => $filter,  \&matcher] => \&cache_generator ;
}

#----------------------------------------------------------------------------------------------------

sub cache_generator
{
my ($config, $file_to_build, $dependencies) = @_ ;

my $filter = $dependencies->[0] ;

write_file($file_to_build, GetFilteredConfig($config, $filter)) ;

return(1, "OK Builder") ;
}
	
#----------------------------------------------------------------------------------------------------

sub GetFilteredConfig
{
my ($config, $filter) = @_ ;

my $filtered_config ;
	
for (do $filter)
	{
	my $config_value = $config->{$_} ;
	$config_value = 'undef' unless defined $config_value ;
	
	$filtered_config .= "$_ = $config_value\n" ;
	}

$filtered_config ;
}

#----------------------------------------------------------------------------------------------------

sub matcher
{
my ($dependent_to_check, $config, $tree, undef, $dependencies) = @_ ;

die 'Only one filter dependency allowed' unless @$dependencies == 2 ; # only the filter is accepted as a dependency

my $triggered       = shift @{$dependencies} ;
my @my_dependencies = @{$dependencies} ;

my $filter = $dependencies->[0] ;

my ($dependent_full_name) 
	= PBS::Check::LocateSource
		(
		$dependent_to_check,
		$tree->{__PBS_CONFIG}{BUILD_DIRECTORY},
		$tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES},
		) ;

my $previous_config = -e $dependent_full_name ? read_file($dependent_full_name): '' ;

if($previous_config ne GetFilteredConfig($config, $filter))
	{
	push @my_dependencies, PBS::Depend::FORCE_TRIGGER('config + filter changed.') ;
	$triggered = 1 ;
	}

unshift @my_dependencies, $triggered ;

return(\@my_dependencies) ;
}

#----------------------------------------------------------------------------------------------------

1 ;
