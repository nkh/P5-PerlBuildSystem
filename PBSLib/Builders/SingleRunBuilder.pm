sub SingleRunBuilder
{
# this can be used when a single command builds multiple nodes and
# we don't want the command to be run multiple times
# an example is generating a swig wrapper and swig perl module

# usage:
#PbsUse 'Builders/SingleRunBuilder' ;
#AddRule "A_or_B", [qr/A/]
#	=> SingleRunBuilder("touch  %FILE_TO_BUILD_PATH/A %FILE_TO_BUILD_PATH/A_B %FILE_TO_BUILD_PATH/A_C") ;

my ($package, $file_name, $line) = caller() ;

my $builder ;

if(@_ == 1)
	{
	if('CODE' eq ref $_[0])
		{
		$builder = $_[0] ;
		}
	elsif('' eq ref $_[0])
		{
		my $command = $_[0] ;
		
		$builder = 
			sub
			{
			my ($config, $file_to_build, $dependencies, $triggering_dependencies, $file_tree) = @_ ;
			my ($package, $file_name, $line) = caller() ;
			
			use PBS::Rules::Builders ;
			RunShellCommands
				(
				PBS::Rules::Builders::EvaluateShellCommandForNode
					(
					$command,
					"SingleRunBuilder called at '$file_name:$line'",
					$file_tree,
					$dependencies,
					$triggering_dependencies,
					)
				) ;
			}
		}
	else
		{
		die ERROR "Rule: Error: SingleRunBuilder only accepts a single sub ref or string argument at '$file_name:$line'." ;
		}
	}
else
	{
	die ERROR "Rule: Error: SingleRunBuilder only accepts a single argument at '$file_name:$line'." ;
	}

my @already_built ; # see node sub below for limitation in parallel builds

PrintInfo "Rule: Generating single builder at '$file_name:$line'\n" ;

return
	(
	sub
		{
		my ($config, $file_to_build, $dependencies) = @_ ;

		
		unless(@already_built)
			{
			PrintUser "Build: SingleRunBuilder'\n" ;

			push @already_built, $file_to_build ;
			return($builder->(@_)) ;
			}
		else
			{
			PrintUser "Build: SingleRunBuilder\n" ;
			PrintUser "\talready run for '$_'\n" for @already_built  ;

			push @already_built, $file_to_build ;
			return(1, "SingleRunBuilder @ '$file_name:$line' was already run") ;
			}
		}
	) ;
}

#----------------------------------------------------------------------------------------------------------

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

my @already_built ;

PrintInfo "Rule: Generating single builder at '$file_name:$line'\n" ;
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
		# $result = send_command($file_to_build->{SOCKET}, 'already_build', 'rule', $file_to_build) ;

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
