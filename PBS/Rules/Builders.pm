package PBS::Rules::Builders ;

use PBS::Debug ;

use v5.10 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateBuilder RunEvaluatedShellCommand) ;
our $VERSION = '0.02' ;

use File::Basename ;
use Sub::Identify qw< sub_name get_code_location > ;
use List::Util qw( none) ;

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

! defined $builder and return () ;

die ERROR("PBS: invalid builder definition for '$name' @ '$file_name:$line'") . "\n"
	if none { ref $builder eq $_ } '', 'ARRAY', 'CODE'  ;

my %rule_type ;
my $commands = ref $builder eq 'ARRAY' ? $builder : [$builder] ;

for my $command (@$commands)
	{
	# record what configs are used, see -dcu
	PBS::Config::EvalConfig($_, $config, "AddRule @ " . GetRunRelativePath($pbs_config, $file_name) . ":$line", $package, $pbs_config, 1)
		if ref $_ eq '' ;

	$rule_type{COMMANDS_RUN_CODE}++ if ref $_ eq 'CODE' ;
		
	die ERROR("Rule: invalid command type for '$name' @ '$file_name:$line', expecting string or code ref") . "\n"
		if none { ref $command eq $_ } '', 'CODE'  ;
	}

return 
	sub { NodeBuilder($pbs_config, $commands, new PBS::Shell(), $package, $name, $file_name, $line, @_) },
	[],
	\%rule_type
}

#-------------------------------------------------------------------------------

sub NodeBuilder
{
my ($pbs_config, $commands, $shell, $package, $name, $file_name, $line) = splice(@_, 0, 7) ;

my $do_run = shift ;
my @evaluated_commands ;

my ($config, $file_to_build, $dependencies, $triggering_dependencies, $tree, $inserted_nodes) = @_ ;

my $shell_override = '' ;
if(exists $tree->{__SHELL_OVERRIDE})
	{
	if(defined $tree->{__SHELL_OVERRIDE})
		{
		$shell = $tree->{__SHELL_OVERRIDE} ;
		$shell_override = '[O]' ;
		}
	else
		{
		die Error("Node defined shell override for node '$tree->{__NAME}' exists but is not defined!") . "\n" ;
		}
	}
	
$tree->{__SHELL_INFO} = $shell->GetInfo() ; 
if($tree->{__PBS_CONFIG}{DISPLAY_SHELL_INFO} && $do_run)
	{
	PrintWarning "Using shell$shell_override: '$tree->{__SHELL_INFO}' "
			. (exists $tree->{__SHELL_ORIGIN} && $tree->{__PBS_CONFIG}{ADD_ORIGIN}
				? "set @ $tree->{__SHELL_ORIGIN}"
				: '')
			. "\n" ;
	}
	
my $display_command_information = $tree->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER} 
					&& ! $PBS::Shell::silent_commands 
					&& $do_run ;

my ($command_returns_ok, $command_message, $command_number) = (1, '', 0) ;

for my $command (@$commands)
	{
	$command_number++ ;

	my $command_information = @$commands > 1
					? "Build: command $command_number of " . scalar(@$commands) . "\n"
					: '' ;
	if('CODE' eq ref $command)
		{
		my ($perl_sub_name, $file, $line) = (sub_name($command), get_code_location($command)) ;
		
		$file =~ s/'//g ;
		$file = GetRunRelativePath($tree->{__PBS_CONFIG}, $file) ;
		
		push @evaluated_commands, [$command, "rule '$name' @ '" . GetRunRelativePath($pbs_config, $file_name) . ":$line'"] ;

		if($do_run)
			{
			my $command_description = $perl_sub_name =~/^BuildOk|TouchOk/
						? $perl_sub_name
						: $perl_sub_name =~ /__ANON__/
							? "sub:$file:$line"
							: "sub: $perl_sub_name $file:$line" ;

			PrintInfo2 $command_information . "Build: $command_description\n" if $display_command_information ;
		
			($command_returns_ok, $command_message) = $shell->RunPerlSub($command, @_) ;
			}
		}
	else
		{
		PrintInfo2 $command_information . "Build: shell command: $command\n" if $display_command_information ;
		
		my $shell_command = EvaluateShellCommandForNode
					(
					$command,
					"rule '$name' @ '$file_name:$line'",
					$tree,
					$dependencies,
					$triggering_dependencies,
					) ;

		push @evaluated_commands, [$shell_command, "rule '$name' @ '" . GetRunRelativePath($pbs_config, $file_name) . ":$line'"] ;

		if($do_run)
			{
			$command_message = '' ; # shell commands don't return, they die
			($command_returns_ok) = $shell->RunCommand($shell_command) ;
			}
		}
	
	last unless $command_returns_ok ;
	}

if($do_run)
	{
	# will be added to digest
	$tree->{__RUN_COMMANDS} = \@evaluated_commands ;

	return $command_returns_ok, $command_message ;
	}
else
	{
	return @evaluated_commands ;
	}
}

#-------------------------------------------------------------------------------

sub EvaluateShellCommandForNode
{
my ($shell_command, $shell_command_info, $tree, $dependencies, $triggered_dependencies) = @_ ;

RunPluginSubs($tree->{__PBS_CONFIG}, 'EvaluateShellCommand', \$shell_command, $tree, $dependencies, $triggered_dependencies) ;

$shell_command = PBS::Config::EvalConfig($shell_command, $tree->{__CONFIG}, $shell_command_info, $tree->{__LOAD_PACKAGE}, $tree->{__PBS_CONFIG}) ;

return $shell_command  ;
}

#-------------------------------------------------------------------------------

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

return $full_name ;
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Rules::Builders -

=head1 DESCRIPTION

Generate a builder from a user definition

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
