target 'all' ;

rule [V], 'all', [ 'all' => 'A' , sub{ PrintDebug "1\n"; 1,'./B' }, sub{ PrintDebug "2\n"; 0 }], BuildOk ;
rule      'B'  , ['B'], TouchOk ; 

