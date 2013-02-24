AddConfig 'OPTIMIZE_FLAG_1::OVERRIDE_PARENT' => 'child_override' ;
AddConfig 'OPTIMIZE_FLAG_2::LOCAL' => 'child_local' ;
AddConfig 'OPTIMIZE_FLAG_3' => 'child_no_override' ;
AddConfig UNDEF_FLAG => undef ;

AddRule '1', [ 'child' => qw(childs_wife grand_daughter grand_son)] ;

AddRule 'grand_son',
	{
	NODE_REGEX => 'grand_son',
	PBSFILE => './grand_son.pl',
	PACKAGE => 'grand_son',
	} ;
	

AddRule 'grand_daughter',
	{
	NODE_REGEX => 'grand_daughter',
	PBSFILE => './grand_daughter.pl',
	PACKAGE => 'grand_daughter',
	} ;

