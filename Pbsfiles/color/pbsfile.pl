
Print Info6        "Info6\n" ;
Print Info         "Info\n" ;
Print Info4        "Info4\n" ;
Print Info2        "Info2\n" ;
Print Info3        "Info3\n" ;
Print Info5        "Info5\n" ;
Say User           "User" ;
Print Warning3     "Warning3\n" ;
Print Warning      "Warning\n" ;
Print Warning2     "Warning2\n" ;

Say Error2         "Error2" ;
Say Error          "Error" ;
Say Error3         "Error3" ;
Say On_error       "On_error" ;
Say Debug3         "Debug3" ;
Say Debug2         "Debug2" ;
Say Debug          "Debug" ;

Say Color 'dark',  'dark' ;
Say Shell          "Shell" ;
Say Shell2         "Shell2" ;
Say NoColor        "no color" ;

Say Color 'test_bg',  'test_bg' ;
Say Color 'test_bg2',  'test_bg2' ;
Say Color 'ignoring_local_rule',  'ignoring_local_rule' ;

Say Color 'ttcl1',  'ttcl1' ;
Say Color 'ttcl2',  'ttcl2' ;
Say Color 'ttcl3',  'ttcl3' ;
Say Color 'ttcl4',  'ttcl4' ;
 
 Say '-' x 10 ;
 Print Color 'info2', "Info2\n" ;
Say Color 'info2', "Info2" ;

rule [V], 'all', ['all'], BuildOk ;

