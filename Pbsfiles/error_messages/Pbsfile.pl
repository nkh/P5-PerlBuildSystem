# this file is used to test the correct display of error message

#Test1: fails because BuildOk does not create node '2'
AddRule 'test1_1', ['1' => '2'], "touch %FILE_TO_BUILD" ;
AddRule 'test1_2', ['2' => '3'], BuildOk() ;
AddRule 'test1_3', ['3'], "touch %FILE_TO_BUILD" ;

#test2: Add this line only, fails because node '4' has no matching rule to build it
AddRule 'test2_3', ['3' => 4], "touch %FILE_TO_BUILD" ;

# Adding this line generrates and error as the depender is 'undef'
#AddSubpbsRule('test2_4', undef, "X.pl", "X") ;

# test 3: error as subpbs 'X.pl' doesn't exist 
#AddSubpbsRule('test3_4', '4', "X.pl", "X") ;

# test 4: multiple subpbs for node '4' will generate an error
#AddSubpbsRule('test4_4 again', '4', "X.pl", "X") ;

