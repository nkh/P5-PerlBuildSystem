

use Carp ;
use Data::TreeDumper ;

sub special_run_time_variable_dependency
{
my
        (
          $dependent_to_check
        , $config
        , $tree
        , $inserted_nodes
        ) = @_ ;

my $whole_config = DumpTree($config, "configuration", USE_ASCII => 1) ;
AddNodeVariableDependencies($tree->{__NAME}, 'WHOLE_CONFIG' => $whole_config) ;
}

sub Builder
{
my ($config, $file_to_build, $dependencies, $triggering_dependencies, $file_tree, $inserted_nodes) = @_ ;

my $whole_config = DumpTree($config, "configuration", USE_ASCII => 1) ;

open my $fh, '>', $file_to_build or croak "can't open file '$file_to_build': $?\n" ;
print $fh $whole_config ;
close $fh ;

return(1, "OK Builder") ;
}

1 ;