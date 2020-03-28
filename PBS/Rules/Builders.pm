package PBS::Rules::Builders ;

use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::TreeDumper ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateBuilder) ;
our $VERSION = '0.01' ;

use File::Basename ;
use Sub::Identify qw< sub_name get_code_location > ;

use PBS::Shell ;
use PBS::PBSConfig ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Rules ;
use PBS::Plugin;

#-------------------------------------------------------------------------------

sub GenerateBuilder
{
my ($shell, $builder, $package, $name, $file_name, $line) = @_ ;

my @builder_node_subs_and_type ;

if(defined $builder)
	{
	for (ref $builder)
		{
		($_ eq '' || $_ eq 'ARRAY') and do
			{
			@builder_node_subs_and_type = GenerateBuilderFromStringOrArray(@_) ;
			last ;
			} ;
			
		($_ eq 'CODE') and do
			{
			@builder_node_subs_and_type = GenerateBuilderFromSub(@_) ;
			last ;
			} ;
			
		die ERROR "Invalid Builder definition for '$name' at '$file_name:$line'\n" ;
		}
	}
	
	
return(@builder_node_subs_and_type) ;
}

#-------------------------------------------------------------------------------

sub GenerateBuilderFromStringOrArray
{
# generate sub that runs a shell command from the definition given in the Pbsfile

my ($shell, $builder, $package, $name, $file_name, $line) = @_ ;

$shell = new PBS::Shell() unless defined $shell ;
 
my $shell_commands = ref $builder eq '' ? [$builder] : $builder ;

my $builder_uses_perl_sub ;

for (@$shell_commands)
	{
	if(ref $_ eq '')
		{
		next ;
		}
		
	if(ref $_ eq 'CODE')
		{
		$builder_uses_perl_sub++ ;
		next ;
		}
		
	die ERROR "Invalid command for '$name' at '$file_name:$line'\n" ;
	}

my @node_subs_from_builder_generator ;

my %rule_type ;
unless($builder_uses_perl_sub)
	{
	my $shell_command_generator =
		sub 
		{
		return
			(
			ShellCommandGenerator
				(
				$shell_commands, $name, $file_name, $line,
				@_,
				)
			) ;
		} ;
			
	$rule_type{SHELL_COMMANDS_GENERATOR} = $shell_command_generator ;
	
	push @node_subs_from_builder_generator,
		sub # node_sub
		{
		my ($dependent_to_check, $config, $tree, $inserted_nodes) = @_ ;
		
		$tree->{__SHELL_COMMANDS_GENERATOR} = $shell_command_generator ;
		push @{$tree->{__SHELL_COMMANDS_GENERATOR_HISTORY}}, "rule '$name' @ '$file_name:$line'";
		} ;
	}
	
my $generated_builder = 
	sub 
	{
	return
		(
		BuilderFromStringOrArray
			(
			$shell_commands, $shell, $package, $name, $file_name, $line
			, @_
			)
		) ;
	} ;

return($generated_builder, \@node_subs_from_builder_generator, \%rule_type) ;
}

#-------------------------------------------------------------------------------

sub ShellCommandGenerator
{
my ($shell_commands, $name, $file_name, $line, $tree) = @_;

my @evaluated_shell_commands ;
for my $shell_command (@{[@$shell_commands]}) # use a copy of @shell_commands, perl bug ???
	{
	push @evaluated_shell_commands, EvaluateShellCommandForNode
						(
						$shell_command,
						"rule '$name' at '$file_name:$line'",
						$tree,
						) ;
	}
	
return(@evaluated_shell_commands) ;
}

#-------------------------------------------------------------------------------

sub BuilderFromStringOrArray
{
my($shell_commands, $shell, $package, $name, $file_name, $line) = splice(@_, 0, 6) ;

my ($config, $file_to_build, $dependencies, $triggering_dependencies, $tree, $inserted_nodes) = @_ ;

my $node_shell = $shell ;
my $is_node_local_shell = '' ;

if(exists $tree->{__SHELL_OVERRIDE})
	{
	if(defined $tree->{__SHELL_OVERRIDE})
		{
		$node_shell = $tree->{__SHELL_OVERRIDE} ;
		$is_node_local_shell = ' [N]'
		}
	else
		{
		Carp::carp ERROR("Node defined shell override for node '$tree->{__NAME}' exists but is not defined!\n") ;
		die ;
		}
	}
	
$tree->{__SHELL_INFO} = $node_shell->GetInfo() ; 
if($tree->{__PBS_CONFIG}{DISPLAY_SHELL_INFO})
	{
	PrintWarning "Using shell$is_node_local_shell: '$tree->{__SHELL_INFO}' " ;
	
	if(exists $tree->{__SHELL_ORIGIN} && $tree->{__PBS_CONFIG}{ADD_ORIGIN})
		{
		PrintWarning "set at $tree->{__SHELL_ORIGIN}" ;
		}
		
	print STDERR "\n" ;
	}
	
my $command_index = 0 ;
my $display_command_information = $tree->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER} 
					&& ! $tree->{__PBS_CONFIG}{DISPLAY_NO_BUILD_HEADER} 
					&& ! $PBS::Shell::silent_commands ;

for my $shell_command (@{[@$shell_commands]}) # use a copy of @shell_commands, perl bug ???
	{
	$command_index++ ;
	print STDERR "\n" if $command_index > 1 ;

	my $command_information = '' ;
	$command_information = "Running command $command_index of " . scalar(@$shell_commands) . "\n" if @$shell_commands > 1 ;
	
	if('CODE' eq ref $shell_command)
		{
		my $perl_sub_name = sub_name($shell_command) ;

		my ($file, $line) = get_code_location($shell_command) ;
		$perl_sub_name .= " $file:$line" if $tree->{__PBS_CONFIG}{DISPLAY_SUB_BUILDER} ;

		PrintInfo2 $command_information . "sub: $perl_sub_name\n"
			if $display_command_information || ($tree->{__PBS_CONFIG}{DISPLAY_SUB_BUILDER} && ! $PBS::Shell::silent_commands) ;
		
		my @result = $node_shell->RunPerlSub($shell_command, @_) ;
		
		if($result[0] == 0)
			{
			# command failed
			return(@result) ;
			}
			
		}
	else
		{
		PrintInfo2 $command_information . "command: $shell_command\n" if $display_command_information ;

		my $command = EvaluateShellCommandForNode
						(
						$shell_command,
						"rule '$name' at '$file_name:$line'",
						$tree,
						$dependencies,
						$triggering_dependencies,
						) ;
						
		PrintUser "$command\n\n" if $display_command_information ;

		$node_shell->RunCommand($command) ;
		}
	}
	
return(1 , "OK Building $file_to_build") ;
}

#-------------------------------------------------------------------------------

sub GenerateBuilderFromSub
{
my ($shell, $builder, $package, $name, $file_name, $line) = @_ ;

$shell = new PBS::Shell() unless defined $shell ;
 
my $generated_builder = 
	sub
	{ 
	return(BuilderFromSub($shell, $builder, $package, $name, $file_name, $line, @_)) ;
	} ;

my %rule_type ;

return($generated_builder, undef, \%rule_type) ;
}

#-------------------------------------------------------------------------------

sub BuilderFromSub
{
my ($shell, $builder, $package, $name, $file_name, $line) = splice(@_, 0, 6) ;

my ($config, $file_to_build, $dependencies, $triggering_dependencies, $tree, $inserted_nodes) = @_ ;

my $node_shell = $shell ;
my $is_node_local_shell = '' ;

if(exists $tree->{__SHELL_OVERRIDE})
	{
	if(defined $tree->{__SHELL_OVERRIDE})
		{
		$node_shell = $tree->{__SHELL_OVERRIDE} ;
		$is_node_local_shell = ' [N]'
		}
	else
		{
		Carp::carp ERROR("Node defined shell for node '$tree->{__NAME}' exists but is not defined!\n") ;
		die ;
		}
	}
	
$tree->{__SHELL_INFO} = $node_shell->GetInfo() ; # :-) doesn't help as this might not be in the root process
	
if($tree->{__PBS_CONFIG}{DISPLAY_SHELL_INFO})
	{
	PrintWarning "Using shell$is_node_local_shell: '$tree->{__SHELL_INFO}' " ;
	
	if(exists $tree->{__SHELL_ORIGIN} && $tree->{__PBS_CONFIG}{ADD_ORIGIN})
		{
		PrintWarning "set at $tree->{__SHELL_ORIGIN}" ;
		}
		
	print STDERR "\n" ;
	}
	
my $perl_sub_name = sub_name($builder) ;

my ($sub_file, $sub_line) = get_code_location($builder) ;
$perl_sub_name .= " $sub_file:$sub_line" if $tree->{__PBS_CONFIG}{DISPLAY_SUB_BUILDER} ;

PrintInfo2 "Running sub: $perl_sub_name\n"
	if ($tree->{__PBS_CONFIG}{DISPLAY_SUB_BUILDER} 
		|| ($tree->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER} && ! $tree->{__PBS_CONFIG}{DISPLAY_NO_BUILD_HEADER})) 
		&& ! $PBS::Shell::silent_commands ;

return
	(
	$node_shell->RunPerlSub($builder, @_)
	) ;
} ;

#-------------------------------------------------------------------------------

sub EvaluateShellCommandForNode
{
my($shell_command, $shell_command_info, $tree, $dependencies, $triggered_dependencies) = @_ ;

RunPluginSubs($tree->{__PBS_CONFIG}, 'EvaluateShellCommand', \$shell_command, $tree, $dependencies, $triggered_dependencies) ;

$shell_command = PBS::Config::EvalConfig($shell_command, $tree->{__CONFIG}, "Shell command", $shell_command_info, $tree) ;

return($shell_command) ;
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
