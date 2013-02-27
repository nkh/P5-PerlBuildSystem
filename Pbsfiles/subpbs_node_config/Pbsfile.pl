=head1 

This example shows how to use PACKAGE_CONFIG in a sub pbs definition.

It will also explains the handling of the configuration and show how to make the nodes trigger on 
configuration changes.

The tree below shows what packages the nodes are dependedn in and what file was used to process them.  The
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

Normally configuration is inherited by sub packages directly. The sub package Pbsfile may then manipulate the sub configuration
via calls to AddRule. Using PACKAGE_CONFIG in a sub pbs rule changes the inheritance process. Remember that a package is an
instanciatiion of a pbsfile for a specific node; it means that multiple packages can be created for different nodes from the same pbsfile

  .--------------------------------.
  |           parent pbs           |
  |--------------------------------|
  | sub pbs with PACKAGE_CONFIG    |
  |    PACKAGE_CONFIG data  --------------.
  |                                |      |
  | sub pbs without PACKAGE_CONFIG |      |
  |                                |      |
  '--------------------------------'      |
          .---------------.               |  mergin in a temporary namespace
  .-------| configuration |-----------.   |  get all the warnings and error 
  |       '---------------'           |   |  of a configuration manipulation
  | I                                 v   v
  | n                              .-------------------------.
  | h                              | with PACKAGE_CONFIG     |
  | e                              | configuration merging   |----.
  | r                              '-------------------------'    |
  | i                                                             |
  | t     .-----------------.        .---------------------.      |
  | a     |     without     |        | with PACKAGE_CONFIG |      |
  | n     | PACKAGE_CONFIG  |        |---------------------|      |
  | c     |-----------------|        |                     |      |
  | e     |                 |        |                     |      |
  |       |                 |        |                     |      |
  |       '-----------------'        '---------------------'      |
  |        .---------------.            .---------------.         |
  '------->| configuration |            | configuration |<--------'
           '---------------'            '---------------'


Run with : pbs -no_warp -display_no_progress_bar -dpl -no_warp -tno -dd -fb -tree_node_triggered_reason -dddo

Check xx.pl for an *important* explaination for how to be dependent of the configuration variables

=cut

AddRule [VIRTUAL], 'all', ['all' => 'xx', 'yy', 'zz'], BuildOk ;

AddConfig 
	AR => 'ABC',
	# 'locked' variables have to be overriden even in sub pbs PACKAGE_CONFIG
	'AR:locked' => 'from_top_pbsfile',
	AR2 => 'ABCD' ;


AddRule 'xx',
	{
	NODE_REGEX => 'xx',
	PBSFILE  => './xx.pl',
	PACKAGE => 'xx',
	PACKAGE_CONFIG =>
		{
		# without 'force' pbs would detect this as an error and stop
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
		# AR would is inherited from this package
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
		# the only configuration variable present at the begining of the pbsfile run
		AR2 => 'the_only_configuration_variable',
		},
	} ;

