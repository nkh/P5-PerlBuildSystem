
# test link warnings

AddRule [VIRTUAL], 'all_lib',['all' => 'something', 'something2'], BuildOk() ;

# fail if local and subpbs  rules match the same node
#AddRule 'something',['something'], BuildOk() ;

AddSubpbsRule 'sub_pbsfile', 'something', './subpbs.pl', 'package' ;
AddSubpbsRule 'sub_pbsfile2', 'something2', './subpbs2.pl', 'package2' ;
