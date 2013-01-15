
=pod

This package gets some configuration variables set from its parent package via PACKAGE_CONFIG.

General discussion about digest:

PBS generates a digest for each nodes that gets created. PBS puts in the digest the elements it has 
control over. When adding rules for a specific type of nodes, the burden of valid digest elements is 
on the build system owner, not on PBS. It's easy and PBS provides a rich API 

	AddFileDependencies           AddNodeFileDependencies
	AddEnvironmentDependencies    AddNodeEnvironmentDependencies
	AddVariableDependencies       AddNodeVariableDependencies
	AddConfigVariableDependencies AddNodeConfigVariableDependencies
	AddSwitchDependencies         AddNodeSwitchDependencies
	
	ExcludeFromDigestGeneration   ForceDigestGeneration 

Normally , for a configuration variable,  you would add a configuration variable dependency with
AddConfigVariableDependencies, if you want all the nodes belonging in this package to depend on
the configuration variable or with AddNodeConfigVariableDependencies, if you want only specific 
nodes to be dependent.

in your pbsfile:

	AddConfigVariableDependencies('title' => 'THE_VARIABLE_NAME') ;
	AddRule 'name', ['xx'], ..... # xx digest will have a THE_VARIABLE_NAME entry

But the argument to AddConfigVariableDependencies must be known beforehand because PBS
needs to know the entries of a digest before computing the digest for a node since it uses it to
decide if the node should be rebuild or not.

What if we want to be dependent on all the whole configuration? What if the digest elements
are only knows at run time and can't be written statically as above?

The first solution is to dynamically call AddConfigVariableDependencies in your pbsfile code:

	my %configuration_data = GetConfig() ; # returns a copy of the package configuration
	
	for my $variable_name (%configuration_data)
		{
		AddConfigVariableDependencies(...)
		}
		
There is another solution, a more advanced solution that you might prefer. The digest entries must 
be known to PBS before it decides if a node has to be rebuild or not. The generql principle is to add
the digest entries as in the examples above, directly in your pbsfile or in PBS libraries like C.pm does.

It is also possible to let rules add digest entries at depend time via node-subs. The example below uses
such a mechanism. Read 'depend_on_all_configs.pm' for details.

=cut

PbsUse('Configs/Compilers/gcc') ;
PbsUse('./depend_on_all_configs') ;

AddRule 'xx', ['xx'], \&Builder, \&special_run_time_variable_dependency ;

