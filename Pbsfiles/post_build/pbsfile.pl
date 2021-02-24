
#$Data::TreeDumper::Displaycallerlocation = 1 ;

target 'all' ;

rule [V], 'all',  ['all' => 'a'], BuildOk ;
rule 'a', ['a' => 'b'], "false" ;
rule 'b', ['b'], TouchOk ;

AddPostBuildCommand 'post build', ['a', 'b'], \&PostBuildCommandTest, 'hi' ;

sub PostBuildCommandTest
{
my ($config, $names, $dependencies, $triggered_dependencies, $argument, $node, $inserted_nodes) = @_ ;

use Data::TreeDumper ;
PrintUser DumpTree [$config, $names, $dependencies, $triggered_dependencies, $argument], 'post build', USE_ASCII => 1 ;

return(1, "PostBuildCommandTest OK.") ;
}
