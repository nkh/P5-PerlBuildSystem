=head1 

pbs -no_warp -display_no_progress_bar -dpl -no_warp -tno -dd

=cut

AddRule [VIRTUAL], 'all', ['all' => 'xx', 'yy'], BuildOk ;

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
		'AR:FORCE' => 'from_package_config_xx',
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
		AR2 => 'from_package_config_yy',
		},
	} ;

