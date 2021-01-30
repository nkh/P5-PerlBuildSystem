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

PrintDebug "Generating single builder\n" ;
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
		die ERROR "Error: SingleRunBuilder only accepts a single sub ref or string argument at '$file_name:$line'." ;
		}
	}
else
	{
	die ERROR "Error: SingleRunBuilder only accepts a single argument at '$file_name:$line'." ;
	}

my @already_built ;

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

$rule->{BUILDER} = 
	sub
		{
		my (undef, $file_to_build) = @_ ;

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

# node_dub is called for all matching nodes
# make sub we apply this wrapper only once

$single_run_builder{$rule->{BUILDER}}++ ;
}

#----------------------------------------------------------------------------------------------------------

1; 
