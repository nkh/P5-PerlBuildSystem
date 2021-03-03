sources 'source' ;

rule [V], 'x', [x => 'all'], BuildOk ;

rule          'all',        [all => qw/ big1 big2 big3 source/], 'echo hi', 'cat %DEPENDENCIES > %TARGET' ;
rule [MULTI], 'big',        [qr/big/], 'dd if=/dev/zero of=%TARGET bs=10M count=1' ;
rule [BO],    'big_source', [qr/big1/ => 'source'], 'touch %TARGET';
rule [BO],    'big_nop',    [qr/big1/] ,'echo hi', 'cat %DEPENDENCIES > %TARGET' ;

rule [BO, MULTI], 'big3', [qr/big3/],
	[
		'echo hi from ' . __FILE__,
		sub
			{
			use File::Slurp ;
			my ($config, $file_to_build) = @_ ;

			unlink $file_to_build ;
			write_file($file_to_build, {append => 1, err_mode => "carp"}, ("1234567890" x 100_000)) for 1 .. 10 ;

			1, 'ok'
			}
	], 
	# node sub
	sub{} ;

