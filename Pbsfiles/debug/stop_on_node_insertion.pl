AddBreakpoint
	(
	'insertion', 

	NODE_REGEX   => '.', 
	TYPE         => 'INSERT',
	PRE          => 1,
	USE_DEBUGGER => 1,
	ACTIVE       => 1,

	ACTIONS =>
		[
		sub
			{
			my %data = @_ ;
			
			Say User "Debug: Inserted node: '$data{NODE_NAME}'" ;
			my $answer = <STDIN> ;
			},
		],
	) ;
 
