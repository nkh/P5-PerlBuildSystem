use Data::TreeDumper ;

$pbs_config ||= '' ;
$dependency_tree->{__BUILD_SEQUENCE} ||= 'no_build_sequence' ;

my $pbs_run_information_dump = DumpTree $pbs_run_information, 'pbs_run_information:' ;

PrintInfo <<EOPP ;

=========================== Run Information ===========================

pbs_config          => $pbs_config
build_success       => $build_success
dependency_tree     => $dependency_tree
build_sequence      => $dependency_tree->{__BUILD_SEQUENCE}
inserted_nodes      => $inserted_nodes

$pbs_run_information_dump

============================== POST PBS ==============================

EOPP


1;
