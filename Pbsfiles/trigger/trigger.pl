
rule 'T2',  ['T2' => qw- T2_d1 subdir/all_d2 link -], 'touch %TARGET' ;

sub ExportTriggers
	{
	trigger 'T2', ['T2' => '*/all_d2'] ;

	rule 'trigger_T2',
		{
		NODE_REGEX => 'T2',
		PBSFILE => './trigger.pl',
		PACKAGE => 'T2',
		BUILD_DIRECTORY => 'somwhere/',
		} ;
	}


