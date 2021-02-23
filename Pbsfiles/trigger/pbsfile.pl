
rule [V], 'all', [ all => qw- all_d1 subdir/all_d2 all_d3 -], BuildOk ;
rule     'link', [ link => 'all_d3'], 'touch %TARGET' ;
rule    'build', [ qr/all_/ => undef], 'touch %TARGET' ;

rule       'T1', [ T1 => 'all_d3'], "touch %TARGET" ;
trigger    'T1', [ T1 => 'all_d3'] ;

triggers './trigger.pl' ;
