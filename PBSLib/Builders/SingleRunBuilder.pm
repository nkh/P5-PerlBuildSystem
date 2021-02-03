
my %single_run_builder ; 

sub SingleRunBuilder_node_sub
{
# wrap the builder so it runs only once

# usage
#AddRule "files to build together", [qr/A|A_B|A_C|A_D/],
#	=>  [
#		"touch  %FILE_TO_BUILD_PATH/A %FILE_TO_BUILD_PATH/A_B %FILE_TO_BUILD_PATH/A_C",
#	    	"echo another command",
#	    	sub {PrintDebug "third build_command\n"},
#	    ],
#	\&SingleRunBuilder_node_sub ; # uses the builder defined above


my ($dependent_to_check, $config, $tree, $inserted_nodesi, $rule) = @_ ;

#my ($builder, $file_name, $line) = @{$rule}{qr( BUILDER FILE LINE )} ;
my ($builder, $file_name, $line) = ($rule->{BUILDER}, $rule->{FILE}, $rule->{LINE}) ;

return if exists $single_run_builder{$builder} ;

my @already_built ; # this works only if only one build process is used

PrintInfo "Rule: Generating single builder at '$rule->{NAME}:$file_name:$line'\n" ;
$rule->{BUILDER} = 
	sub
		{
		my (undef, $file_to_build) = @_ ;

		# this mechanism doesn't work when building nodes in parallel
		# each build process has it's own @already_built and it is unlikely that
		# all the nodes to build will end up in the same build process
		#
		# forcing the nodes matching the same rule to be build in the same process is bad design
		# the solution would be to have a shared @already_build we can access from all processes
		# the @already build can be kept in the main process and manipulated via a protocol over
		# the socket pair already setup for the forked builder
		#
		# unless(PBS::RPC::request($pbs_config, 'already_run', $rule_name) ;
		# PBS::RPC::request($pbs_config, 'already_run_add', $rule_name, $file_to_build) ;
		#
		# we can hide them in a wrapper
		# unless(AlreadyRun($pbs_config, $rule_name))
		# AddAlreadyRun($pbs_config, $rule_name, $file_name) ;
		# GetAlreadyRun($pbs_config, $rule_name) ;
		#
		# RPC handlers must be registered when pbs-main starts
		#
		# as long as the rules are run in the main process we can register the handlers when the 
		# rules are loaded
		#
		# if rules are run in different processes, the RPC handler may not be registered in the 
		# main process as it hasn't loaded the rules that the other process have loaded
		# 
		# one way to handle it is to have the RPC handler defined at the same time as the rule
		# and if the main process doesn't have a handler it can ask the requester to run the handler
		# when other processes ask for that RPC handler, the main process proxies them to the first
		# requestor who has the handler. One problem is how often a process that is building can 
		# answer RPC requests? the main process doesn't build, it simply synchs builds thus is better
		# at handling RPC requests
		#
		# another way is for the main process to load RPC handler dynamically
		# the RPC handler can be defined in the rule file which can be loaded in a separate package 
		# we can then use the RPC handler in that package


		unless(@already_built)
			{
			PrintUser "Build: SingleRunBuilder" . INFO2(" @ '$file_name:$line'\n\n") ;

			push @already_built, $file_to_build ;
			return($builder->(@_)) ;
			}
		else
			{
			PrintUser "Build: SingleRunBuilder" . INFO2(" @ '$file_name:$line'\n") ;
			PrintInfo2 "\talready run for '$_'\n" for @already_built  ;
			PrintInfo2 "\n" ;

			push @already_built, $file_to_build ;
			return(1, "SingleRunBuilder @ '$file_name:$line' was already run") ;
			}
		} ;

# node_sub is called for all matching nodes
# make sub we apply this wrapper only once

$single_run_builder{$rule->{BUILDER}}++ ;
}

#----------------------------------------------------------------------------------------------------------

1 ; 
