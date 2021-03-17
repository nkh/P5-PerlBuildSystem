config  OEMS => 'OEM1,OEM2', LIBRARIES => 'aaa,xxx' ;
sources qw- ./repo ./resources/css - ;

target 'release' ;
rule   'release', [ release => glob config '{%OEMS}/{%LIBRARIES}/encrypted.mol' ], touch_ok ;

rule 'mol', [ qr/encrypted\.mol$/ => './$path1/pt::PT', '$path/css' ], '%PT %TARGET' ;
rule 'pt',  [ qr<pt$>             => './repo/$path1/pt::PT'         ], 'cp -r %PT %TARGET_DIR' ;
rule 'css', [ qr<css$>            => './resources/css::CSS'         ], 'cp %CSS %TARGET' ;

