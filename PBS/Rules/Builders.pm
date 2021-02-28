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
ref $builder eq 'CODE' and                        return GenerateBuilderFromSub(@_) ;
			
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

my $generated_builder = sub { BuilderFromStringOrArray($shell_commands, $shell, $package, $name, $file_name, $line, @_) } ;

return($generated_builder, [], \%rule_type) ;
}

#-------------------------------------------------------------------------------

sub BuilderFromStringOrArray
{
my($shell_commands, $shell, $package, $name, $file_name, $line) = splice(@_, 0, 6) ;

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
		Carp::carp ERROR("Node defined shell override for node '$tree->{__NAME}' exists but is not defined!\n") ;
		die ;
		}
	}
	
$tree->{__SHELL_INFO} = $shell->GetInfo() ; 
if($tree->{__PBS_CONFIG}{DISPLAY_SHELL_INFO})
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
					&& ! $PBS::Shell::silent_commands ;

for my $shell_command (@{[@$shell_commands]}) # use a copy of @shell_commands, perl bug ???
	{
	$command_number++ ;
	print STDERR "\n" if $command_number > 1 ;

	my $command_information = @$shell_commands > 1
					? "Build: command $command_number of " . scalar(@$shell_commands) . "\n"
					: '' ;
	
	if('CODE' eq ref $shell_command)
		{
		my ($perl_sub_name, $file, $line) = (sub_name($shell_command), get_code_location($shell_command)) ;

		$file =~ s/'//g ;
		$file = GetRunRelativePath($tree->{__PBS_CONFIG}, $file) ;

		if($display_command_information)
			{
			if ($perl_sub_name =~/^BuildOk|TouchOk/)
				{
				PrintInfo3 "${command_information}Build: $perl_sub_name\n"
				}
			elsif ($perl_sub_name =~ /__ANON__/) 
				{
				PrintInfo3 "${command_information}Build: sub:$file:$line\n"
				}
			else
				{
				PrintInfo3 "${command_information}Build: sub: $perl_sub_name $file:$line\n"
				}
			}

		return $shell->RunPerlSub($shell_command, @_) ;
		}
	else
		{
		PrintInfo2 $command_information . "Build: shell command: $shell_command\n" if $display_command_information ;

		my $command = EvaluateShellCommandForNode
						(
						$shell_command,
						"rule '$name' @ '$file_name:$line'",
						$tree,
						$dependencies,
						$triggering_dependencies,
						) ;
						
		$shell->RunCommand($command) ;
		}
	}
	
return 1 , "OK" ;
}

#-------------------------------------------------------------------------------

sub GenerateBuilderFromSub
{
my ($pbs_config, $config, $builder, $package, $name, $file_name, $line) = @_ ;

my $shell = new PBS::Shell() ;
 
my $generated_builder = sub { return(BuilderFromSub($shell, $builder, $package, $name, $file_name, $line, @_)) ; } ;

my %rule_type ;

return($generated_builder, undef, \%rule_type) ;
}

#-------------------------------------------------------------------------------

sub BuilderFromSub
{
my ($shell, $builder, $package, $name, $file_name, $line) = splice(@_, 0, 6) ;

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
		Carp::carp ERROR("Node defined shell for node '$tree->{__NAME}' exists but is not defined!\n") ;
		die ;
		}
	}
	
$tree->{__SHELL_INFO} = $shell->GetInfo() ; # :-) doesn't help as this might not be in the root process
	
if($tree->{__PBS_CONFIG}{DISPLAY_SHELL_INFO})
	{
	PrintWarning "Using shell$is_node_local_shell: '$tree->{__SHELL_INFO}' " ;
	
	if(exists $tree->{__SHELL_ORIGIN} && $tree->{__PBS_CONFIG}{ADD_ORIGIN})
		{
		PrintWarning "set @ $tree->{__SHELL_ORIGIN}" ;
		}
		
	print STDERR "\n" ;
	}
	
my $perl_sub_name = sub_name($builder) ;

my ($sub_file, $sub_line) = get_code_location($builder) ;
$perl_sub_name .= " $sub_file:$sub_line" ;

PrintInfo2 "Build: sub: $perl_sub_name\n"
		if $tree->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER}
			&& ! $tree->{__PBS_CONFIG}{DISPLAY_NO_BUILD_HEADER}
			&& ! $PBS::Shell::silent_commands ;

shell->RunPerlSub($builder, @_)
} ;

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
