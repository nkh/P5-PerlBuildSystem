# WIZARD_GROUP PBS
# WIZARD_NAME  node_sub
# WIZARD_DESCRIPTION template for a node sub
# WIZARD_ON

print <<'EOT' ;
sub NodeSub
{
my 
(
$dependent_to_check,
$config,
$tree,
$inserted_nodes,
) = @_ ;

tree->{__PBS_CONFIG} = {%{$tree->{__PBS_CONFIG}}} ; # config is share get our own copy (note! this is not deep)

use Data::TreeDumper ;
PrintDebug DumpTree $tree->{__CONFIG} ;

}

EOT

# ------------------------------------------------------------------
1;

