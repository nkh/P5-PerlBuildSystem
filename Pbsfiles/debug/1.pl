use subs qw/ BP_ls / ;

target 1 ;

rule '1', [ 1 ], => [ BP_ls, 'touch %TARGET',];

rule [NA], '1>2', [ 1 => '2'] ;

subpbs '2' => './2.pl' ;


sub BP_ls
{
my @p = @_ ;
	
sub
	{
	my ($config, $file_to_build, $dependencies, $triggering_dependencies, $node, $inserted_nodes) = @_ ;
	PBS::Debug::CheckBreakpoint $node->{__PBS_CONFIG}, TYPE => 'USER_LS', @p ;
	1, ''
	}

}


