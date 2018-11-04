=test

change the created node
change one of the dependencies
remove one of the dependencies
change the PbsUse
change the Pbsfile
remove the creator digest
change a md5 in the creator digest
modify the digest so it is not valid perl
change the version, is it needed? isn't the creator link to the pbsfile enough?

Creator rule with builder
Extra builder for node with creator
composite of above two

=cut

use Data::TreeDumper ;

PbsUse('Configs/Compilers/gcc') ; # this should also trigger the re-creation of the node

# example Pbsfile using [CREATOR]

ExcludeFromDigestGeneration('source' => 'dependency') ;
AddRule [VIRTUAL], 'all', [ 'all' => 'A', 'B'], BuildOk("All finished.") ;

AddRule [CREATOR], 'objects', ['A' => 'dependency_to_A', 'dependency_2_to_A'] =>
	"echo 123 > %FILE_TO_BUILD" ;

AddRule 'B', ['B'], sub { PrintDebug "Building B\n" ; return(1, "OK") } ;

