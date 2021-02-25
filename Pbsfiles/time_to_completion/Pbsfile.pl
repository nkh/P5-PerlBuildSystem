# compute gant timeline

# nodes are given start time, duration, and dependencies
# 	gant information is saved in the node's config and serialized to in a .gant file

# note: source nodes have no rules run on them and can't get start time and duration set

pbsuse './gant' ;

rule 'all',	['all' => 'a', 'b'],	["touch %TARGET"], GantTime(5, 3) ;
rule 'a',	['a' => 'c'],		["touch %TARGET"], GantTime(1, 2) ;
rule 'b',	['b' => 'c'],		["touch %TARGET"], GantTime(3, 1) ;
rule 'c',	['c'],			["touch %TARGET"], GantTime(4, 3) ;


