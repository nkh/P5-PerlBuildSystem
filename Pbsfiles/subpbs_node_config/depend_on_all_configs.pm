
=pod

This PBS library implements a node-sub and a node builder. they are used like this:

	PbsUse('./depend_on_all_configs') ;
	AddRule 'xx', ['xx'], \&Builder, \&special_run_time_variable_dependency ;

Note that there is nothing special about the builder except the fact that it is a Perl sub. We want to create (build)
a file that contains all the configuration variable at the moment the node is build. This would not be possible using
shell commands.

The interesting part is the node-sub. It is called after the node is inserted in the dependency graph but before the
node is build.

=cut

use Carp ;
use Data::TreeDumper ;

#----------------------------------------------------------------------

sub special_run_time_variable_dependency
{
my ( $dependent_to_check, $config, $tree) = @_ ;

#create a textual description for the whole configuration this node has
my $whole_config = DumpTree($config, "configuration", USE_ASCII => 1) ;

# Direct PBS to add it in the digest
AddNodeVariableDependencies($tree->{__NAME}, 'WHOLE_CONFIG' => $whole_config) ;
}

#----------------------------------------------------------------------

sub Builder
{
my ($config, $file_to_build) = @_ ;

my $whole_config = DumpTree($config, "configuration", USE_ASCII => 1) ;

open my $fh, '>', $file_to_build or croak "can't open file '$file_to_build': $?\n" ;
print $fh $whole_config ;
close $fh ;

return(1, "OK Builder") ;
}

1 ;