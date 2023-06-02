config  OEMS => 'OEM1,OEM2', LIBRARIES => 'lib1,lib2' ;
sources qw- ./repo ./resources - ;

target 'release' ;
rule   'release', [ release => glob config '{%OEMS}/{%LIBRARIES}/encrypted.mol' ], touch_ok ;

rule 'mol', [ '*/*.mol' => './$path1/pt::PT', '$path/css' ], '%PT %TARGET' ;
rule 'pt',  [ '*/pt'    => './repo/$path1/pt::PT'         ], 'cp %PT %TARGET' ;
rule 'css', [ '*/css'   => './resources/css::CSS'         ], 'cp %CSS %TARGET' ;

