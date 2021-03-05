use strict ;
use warnings ;

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
			return if $data{NODE_NAME} =~/^__/ ;

			Say Debug3 "BP: 'post_depend', node: '$data{NODE_NAME}', rule: '$data{RULE_NAME}' " ;
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

			return if $data{NODE_NAME} =~/^__/ ;

			Say Debug3 "BP: 'depend' => '$data{NODE_NAME}' with rule '$data{RULE_NAME}'" ;
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

			Say Debug3 "BP: 'insert3'." ;
			
			SD3T \%data, '', MAX_DEPTH => 1, INDENTATION => "\t" ;
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
			my %data = @_ ;

			Say Debug3 "BP: about to build node '$data{NODE_NAME}'" ;
			SD3T {@_}, '', MAX_DEPTH => 1, INDENTATION => "\t" ;
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

			Say Debug "BP: 'snapshot'" ;
			
			SD3T $data{TREE}, "created tree:'$data{TREE}{__NAME}'", INDENTATION => "\t"
				if $data{TREE}{__NAME} !~ /^__/ && exists $data{TREE}{__INSERTED_AT}{ORIGINAL_INSERTION_DATA} ;
			
			},
		],
	) ;
}

1;

