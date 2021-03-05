
AddBreakpoint
	(
	'ls', 
	ACTIVE  => 1,
	TYPE    => 'USER_LS',
	ACTIONS => [ sub { my %data = @_ ; Say Debug2 scalar(qx'ls -lsa') } ],
	) ;
