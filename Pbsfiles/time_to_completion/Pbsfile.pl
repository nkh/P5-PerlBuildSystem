# compute gant timeline

# nodes are given start time, duration, and dependencies
# 	gant information is saved in the node's config and serialized to in a .gant file

# note: source nodes have no rules run on them and can't get start time and duration set

PbsUse './gant_settime' ;

rule 'all',	['all' => 'a', 'b'],	["touch %TARGET"], SetTime(5, 3) ;
rule 'a',	['a' => 'c'],		["touch %TARGET"], SetTime(1, 2) ;
rule 'b',	['b' => 'c'],		["touch %TARGET"], SetTime(3, 1) ;
rule 'c',	['c'],			["touch %TARGET"], SetTime(4, 3) ;

# insert gant nodes in the graph, normal dependencies must be defined first
PbsUse './gant_nodes' ;

