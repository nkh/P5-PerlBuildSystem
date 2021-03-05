
use PBS::Debug ;

AddProjectBreakpoints() ; 
ActivateBreakpoints qw/ trigger_info depend / ;

#~ ActivateBreakpoints('insert3') ;
#~ ActivateBreakpoints('build') ;
#~ ActivateBreakpoints('snapshot') ;

#-----------------------------------------------------------------------------------------

sub AddProjectBreakpoints
{
AddBreakpoint
	(
	'post_depend',

	TYPE         => 'DEPEND',
	TRIGGERED    => 1,
	POST         => 1,
	USE_DEBUGGER => 1,
	#ACTIVE       => 1,

	ACTIONS =>
		[
		sub
			{
			my %data = @_ ;
			Say Debug "Debug: 'post_depend', node: '$data{NODE_NAME}', rule: '$data{RULE_NAME}' " ;
			#SDT {@_}, '', MAX_DEPTH => 1, INDENTATION => "\t" ;
			},
		],
	) ;

AddBreakpoint
	(
	'depend',

	TYPE         => 'DEPEND',
	PRE          => 1,
	#ACTIVE       => 1,
	ACTIONS =>
		[
		sub
			{
			my %data = @_ ;

			Say Debug "Debug: 'depend' => '$data{NODE_NAME}'" ;
			#SDT {@_}, '', MAX_DEPTH => 1, INDENTATION => "\t" ;
			},
		],
	) ;

AddBreakpoint
	(
	'insert3',

	NODE_REGEX   => '3',
	TYPE         => 'INSERT',
	POST         => 1,
	USE_DEBUGGER => 1,
	#ACTIVE       => 1,

	ACTIONS =>
		[
		sub
			{
			my %data = @_ ;

			Say Debug "Debug: 'insert3'." ;
			
			SDT \%data, '', MAX_DEPTH => 1, INDENTATION => "\t" ;
			},
		],
	) ;

AddBreakpoint
	(
	'build',

	TYPE         => 'BUILD',
	USE_DEBUGGER => 1,
	ACTIVE       => 1,
	PRE          => 1,
	ACTIONS =>
		[
		sub
			{
			Say Debug "Debug: about to build node '$data{NODE_NAME}'" ;
			
			SDT {@_}, '', MAX_DEPTH => 1, INDENTATION => "\t" ;
			},
		],
	) ;

AddBreakpoint
	(
	'snapshot',

	TYPE          => 'TREE',
	POST          => 1,
	# USE_DEBUGGER => 1,

	ACTIONS =>,
		[
		sub
			{
			my %data = @_ ;

			Say Debug "Debug: 'snapshot'" ;
			
			next if $data{TREE}{__NAME} =~ /^__/ ;
			next if exists $data{TREE}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} ;
			
			SDT $data{TREE}, "created tree:'$data{TREE}{__NAME}'", INDENTATION => "\t" ;
			},
		],
	) ;
}

1;

