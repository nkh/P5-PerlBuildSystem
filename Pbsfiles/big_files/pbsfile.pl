use File::Slurp ;

rule 'all', [all => qw/ big1 big2 big3 big4 /], "cat %DEPENDENCIES > %TARGET" ;

rule 'big', [qr/big/], 
	sub
	{
	my (undef, $file_to_build) = @_ ;

	unlink $file_to_build ;
	write_file($file_to_build, {append => 1, err_mode => "carp"}, ("1234567890" x 100_000)) for 1 .. 100 ;

	1, 'ok'
	} ;
