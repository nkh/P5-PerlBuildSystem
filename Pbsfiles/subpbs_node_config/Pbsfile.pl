=head1 

This example shows how to use PACKAGE_CONFIG in a sub pbs definition.

It will also explains the handling of the configuration and show how to make the nodes trigger on 
configuration changes.

The tree below shows what packages the nodes are depended in and what file was used to process them.  The
node's package contains the configuration and each node refers to its package configuration. Thus we have three
nodes and three package configurations.

Tree for '__PBS_root_NO_WARP_pbs_._Pbsfile.pl':
`- ./all  [H9]
   |- __INSERTED_AT  [H10]
   |  |- INSERTION_LOAD_PACKAGE = PBS::Runs::PBS_1  [S13]
   |- __DEPENDED_AT = ./Pbsfile.pl  [S17]
   |- ./xx  [H18]
   |  |- __INSERTED_AT  [H19]
   |  |  |- INSERTION_LOAD_PACKAGE = PBS::Runs::xx_1  [S22]
   |  `- __DEPENDED_AT = /devel/perl_modules/PerlBuildSystem/Pbsfiles/subpbs_node_config/xx.pl  [S33]
   `- ./yy  [H34]
      |- __INSERTED_AT  [H35]
      |  |- INSERTION_LOAD_PACKAGE = PBS::Runs::yy_1  [S38]
      `- __DEPENDED_AT = /devel/perl_modules/PerlBuildSystem/Pbsfiles/subpbs_node_config/yy.pl  [S49]

Normally configuration is inherited by sub pbs. Controlling the configuration inheritance is done in
via option '--no_config_inheritance' or PACKAGE_CONFIG_NO_INHERITANCE in a sub pbs definition.

A package is an instanciation of a pbsfile for a specific node; multiple packages are created for different target
even if they use the same pbsfile. So we can have one sub pbs inherit the parent configuration and another not. 

parent config
	[parent] 

	supbpbs definition:
		[]		[PACKAGE_CONFIG]	[PACKAGE_CONFIG_NO_INHERITANCE]		[PACKAGE_CONFIG_NO_INHERITANCE]
							or --no_config_inheritance		or --no_config_inheritance
												+ [PACKAGE_CONFIG]

pbs config	[parent]	[parent] +		[]					[PACKAGE_CONFIG]
				[PACKAGE_CONFIG] 


Run with : pbs -tno -ddl -w 0 -dddo --dpl --display_configs_merge  --durno --display_pbsfile_loading
Check xx.pl for an *important* explanation for how to dependent on the configuration variables

=cut

AddRule [VIRTUAL], 'all', ['all' => 'xx', 'yy', 'zz'], BuildOk ;

AddConfig 
	AR => 'ABC',
	'AR:locked' => 'from_top_pbsfile',
	AR2 => 'ABCD' ;

AddRule 'xx',
	{
	NODE_REGEX => 'xx',
	PBSFILE  => './xx.pl',
	PACKAGE => 'xx',
	PACKAGE_CONFIG =>
		{
		# without 'force' pbs would detect this as an error (locked in parent config) and stop
		'AR:force' => 'from_package_config_xx',
		AR2 => 'from_package_config_xx',
		},
	} ;

AddRule 'yy',
	{
	NODE_REGEX => 'yy',
	PBSFILE  => './yy.pl',
	PACKAGE => 'yy',
	PACKAGE_CONFIG =>
		{
		# AR is inherited from parent package
		AR2 => 'from_package_config_yy',
		},
	} ;

AddRule 'zz',
	{
	NODE_REGEX => 'zz',
	PBSFILE  => './zz.pl',
	PACKAGE => 'zz',
	PACKAGE_CONFIG_NO_INHERITANCE => 1,
	PACKAGE_CONFIG =>
		{
		# the only configuration variable in the sub pbs
		AR2 => 'the_only_configuration_variable',
		},
	} ;

