target 'release' ;

sources qw- ./repo ./resources/css - ;
config  OEMS => 'OEM1,OEM2', LIBRARIES => 'aaa,xxx' ;

rule 'release', ['release'            => glob '{'. config('OEMS') .'}/{'. config('LIBRARIES') .'}/encrypted.mol' ], 'echo %DEPENDENCIES > %TARGET' ;
rule 'mol',     [ qr/encrypted\.mol$/ => './$path1/pt::PT', '$path/css'], '%PT %TARGET' ;
rule 'pt',      [ qr<pt$>             => './repo/$path1/pt::OEM_PT'    ], 'cp -r %OEM_PT %TARGET_DIR' ;
rule 'css',     [ qr<css$>            => './resources/css::CSS'        ], 'cp %CSS %TARGET' ;

