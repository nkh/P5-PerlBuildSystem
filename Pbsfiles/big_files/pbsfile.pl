sources 'source' ;

rule 'all', [all => qw/ big1 big2 big3 big4 source/], "cat %DEPENDENCIES > %TARGET" ;

rule [MULTI], 'big', [qr/big/], 
	sub
	{
	use File::Slurp ;
	my (undef, $file_to_build) = @_ ;

	unlink $file_to_build ;
	write_file($file_to_build, {append => 1, err_mode => "carp"}, ("1234567890" x 100_000)) for 1 .. 10 ;

	1, 'ok'
	} ;

rule [BO], 'big_source', [qr/big1/ => 'source'], "touch %TARGET", [sub{}] ;
rule 'big_nop', [qr/big1/] ;



