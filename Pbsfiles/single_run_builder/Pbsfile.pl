
# This example shows how to generate multiple node with a single command.

# note (July 2019): this doesn't work in -j builds as each process has its own sentinel
# wrap the builder so it needs to synch with the main process


AddRule [VIRTUAL], "all", ['all' => 'A', 'A_B', 'A_C', 'A_D'], BuildOk() ;

PbsUse 'Builders/SingleRunBuilder' ;
AddRule [V], "x", [qr/A_D/ => 'dependency', '__PBS_FORCE_TRIGGER'] ;
AddRule "dependency", ['dependency'] , 'touch %FILE_TO_BUILD' ;

AddRule "files to build together", [qr/A|A_B|A_C|A_D/],
	=>  [
		"touch  %FILE_TO_BUILD_PATH/A %FILE_TO_BUILD_PATH/A_B %FILE_TO_BUILD_PATH/A_C %FILE_TO_BUILD_PATH/A_D",
	    	"echo another command",
	    	sub {PrintDebug "third build_command\n"},
	    ],
	#using a node_sub
	\&SingleRunBuilder_node_sub ;

