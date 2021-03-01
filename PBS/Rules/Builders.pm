package PBS::Rules::Builders ;

use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateBuilder RunEvaluatedShellCommand) ;
our $VERSION = '0.01' ;

use File::Basename ;
use Sub::Identify qw< sub_name get_code_location > ;

use PBS::Constants ;
use PBS::Config ;
use PBS::PBSConfig ;
use PBS::Output ;
use PBS::Rules ;
use PBS::Plugin;

use PBS::Shell ;

#-------------------------------------------------------------------------------

sub GenerateBuilder
{
my ($pbs_config, $config, $builder, $package, $name, $file_name, $line) = @_ ;

! defined $builder and                            return () ;
ref $builder eq '' || ref $builder eq 'ARRAY' and return GenerateBuilderFromStringOrArray(@_) ;
ref $builder eq 'CODE' and                        return GenerateBuilderFromStringOrArray([@_]) ;
			
die ERROR ("PBS: invalid builder definition for '$name' @ '$file_name:$line'") . "\n" ;
}

#-------------------------------------------------------------------------------

sub GenerateBuilderFromStringOrArray
{
# generate sub that runs a shell command from the definition given in the Pbsfile

my ($pbs_config, $config, $builder, $package, $name, $file_name, $line) = @_ ;

my $shell = new PBS::Shell() ;
 
my $shell_commands = ref $builder eq '' ? [$builder] : $builder ;

my %rule_type ;

for (@$shell_commands)
	{
	if(ref $_ eq '')
		{
		# record what configs are used, see -dcu
		PBS::Config::EvalConfig($_, $config, "AddRule @ " . GetRunRelativePath($pbs_config, $file_name) . ":$line", $package, $pbs_config, 1) ;
		next ;
		}
		
	if(ref $_ eq 'CODE')
		{
		$rule_type{COMMANDS_RUN_CODE}++ ;
		next ;
		}
		
	die ERROR("Rule: invalid command type for '$name' @ '$file_name:$line', mut be string or code reference.") . "\n" ;
	}

my $generated_builder = sub { BuilderFromStringOrArray($pbs_config, $shell_commands, $shell, $package, $name, $file_name, $line, @_) } ;

return($generated_builder, [], \%rule_type) ;
}

#-------------------------------------------------------------------------------

sub BuilderFromStringOrArray
{
my ($pbs_config, $shell_commands, $shell, $package, $name, $file_name, $line) = splice(@_, 0, 7) ;

my $do_run = shift ;
my @evaluated_commands ;

my ($config, $file_to_build, $dependencies, $triggering_dependencies, $tree, $inserted_nodes) = @_ ;

my $is_node_local_shell = '' ;

if(exists $tree->{__SHELL_OVERRIDE})
	{
	if(defined $tree->{__SHELL_OVERRIDE})
		{
		$shell = $tree->{__SHELL_OVERRIDE} ;
		$is_node_local_shell = ' [O]'
		}
	else
		{
		PrintError "Node defined shell override for node '$tree->{__NAME}' exists but is not defined!\n" ;
		die "\n" ;
		}
	}
	
$tree->{__SHELL_INFO} = $shell->GetInfo() ; 
if($tree->{__PBS_CONFIG}{DISPLAY_SHELL_INFO} && $do_run)
	{
	PrintWarning "Using shell$is_node_local_shell: '$tree->{__SHELL_INFO}' " ;
	
	if(exists $tree->{__SHELL_ORIGIN} && $tree->{__PBS_CONFIG}{ADD_ORIGIN})
		{
		PrintWarning "set @ $tree->{__SHELL_ORIGIN}" ;
		}
		
	print STDERR "\n" ;
	}
	
my $command_number = 0 ;
my $display_command_information = $tree->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER} 
					&& ! $tree->{__PBS_CONFIG}{DISPLAY_NO_BUILD_HEADER} 
					&& ! $PBS::Shell::silent_commands 
					&& $do_run ;

my ($command_return, $command_message) = (1, '') ;

for my $shell_command (@$shell_commands) # use a copy of @shell_commands, perl bug ???
	{
	$command_number++ ;

	my $command_information = @$shell_commands > 1
					? "Build: command $command_number of " . scalar(@$shell_commands) . "\n"
					: '' ;
	
	my $command ;

	if('CODE' eq ref $shell_command)
		{
		my ($perl_sub_name, $file, $line) = (sub_name($shell_command), get_code_location($shell_command)) ;
		
		$file =~ s/'//g ;
		$file = GetRunRelativePath($tree->{__PBS_CONFIG}, $file) ;
		
		if ($perl_sub_name =~/^BuildOk|TouchOk/)
			{
			$command = "${command_information}Build: $perl_sub_name"
			}
		elsif ($perl_sub_name =~ /__ANON__/) 
			{
			$command = "${command_information}Build: sub:$file:$line"
			}
		else
			{
			$command = "${command_information}Build: sub: $perl_sub_name $file:$line"
			}
		
		push @evaluated_commands, [$shell_command, "rule '$name' @ '" . GetRunRelativePath($pbs_config, $file_name) . ":$line'"] ;

		if($do_run)
			{
			PrintInfo2 "Build: $command\n" if $display_command_information ;
		
			($command_return, $command_message) = $shell->RunPerlSub($shell_command, @_) ;
			}
		else
			{
			$command_return++ ;
			}
		}
	else
		{
		PrintInfo2 $command_information . "Build: shell command: $shell_command\n" if $display_command_information ;

		$command = EvaluateShellCommandForNode
						(
						$shell_command,
						"rule '$name' @ '$file_name:$line'",
						$tree,
						$dependencies,
						$triggering_dependencies,
						) ;

		push @evaluated_commands, [$command, "rule '$name' @ '" . GetRunRelativePath($pbs_config, $file_name) . ":$line'"] ;

		if($do_run)
			{
			$command_message = '' ; # shell commands don't return, they die
			($command_return) = $shell->RunCommand($command) ;
			}
		else
			{
			$command_return++ ;
			}
		}
	
	last unless $command_return ;
	}
	
if($do_run)
	{
	# will be added to digest
	$tree->{__RUN_COMMANDS} = \@evaluated_commands ;

	return $command_return, $command_message ;
	}
else
	{
	return @evaluated_commands ;
	}
}

#-------------------------------------------------------------------------------

sub EvaluateShellCommandForNode
{
my($shell_command, $shell_command_info, $tree, $dependencies, $triggered_dependencies) = @_ ;

RunPluginSubs($tree->{__PBS_CONFIG}, 'EvaluateShellCommand', \$shell_command, $tree, $dependencies, $triggered_dependencies) ;

$shell_command = PBS::Config::EvalConfig($shell_command, $tree->{__CONFIG}, $shell_command_info, $tree->{__LOAD_PACKAGE}, $tree->{__PBS_CONFIG}) ;

return($shell_command) ;
}

sub RunEvaluatedShellCommand
{
my($shell_command, $shell_command_info, $tree, $dependencies, $triggered_dependencies) = @_ ;

RunPluginSubs($tree->{__PBS_CONFIG}, 'EvaluateShellCommand', \$shell_command, $tree, $dependencies, $triggered_dependencies) ;

$shell_command = PBS::Config::EvalConfig($shell_command, $tree->{__CONFIG}, $shell_command_info, $tree->{__LOAD_PACKAGE}, $tree->{__PBS_CONFIG}) ;

RunShellCommands $shell_command ;
}

#-------------------------------------------------------------------------------

sub GetBuildName
{
my ($dependent, $file_tree) = @_ ;

my $build_directory    = $file_tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $file_tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ;

my ($full_name, $is_alternative_source, $other_source_index) = PBS::Check::LocateSource($dependent, $build_directory, $source_directories) ;

return($full_name) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Rules::Builders -

=head1 DESCRIPTION

This package provides support function for B<PBS::Rules::Rules>

=head2 EXPORT

Nothing.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
