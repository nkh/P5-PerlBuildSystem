rule '2>3', [ 2 => qw- 3 5 -] ;
rule '2>4', [ 2 => '4'] ;

subpbs '3' => './3.pl' ;
subpbs '4' => './3.pl' ;

