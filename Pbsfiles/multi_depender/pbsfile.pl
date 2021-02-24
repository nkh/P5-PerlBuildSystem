target 'all' ;
pbsconfig qw/ -j 1 --ddr -tno -fb / ;

rule [V], 'all', [ 'all' => 'A' , sub{ PrintDebug "1\n"; 1,'./B' }, sub{ PrintDebug "2\n"; 0 }], BuildOk ;
rule      'B'  , ['B'], TouchOk ; 

