target 'all' ;

rule [V], 'all'    , [ 'all' => 'A' ], BuildOk ;
rule [I], 'objects', [ 'A' => 'B'] => TouchOk ;
rule      'B'      , ['B'], TouchOk ; 

