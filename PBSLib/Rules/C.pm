
=head1 Synopsis

This is a B<PBS> (Perl Build System) module.

=head1 When is 'Rules/BuildSystem.pm' used?

=head1 What 'Rules/C.pm' does.

=cut

use strict ;
use warnings ;

use PBS::PBS ;
use PBS::Rules ;

#-------------------------------------------------------------------------------

PbsUse('Rules/C_depender') ;

use PBS::Plugin ;
sub IncludeSourceDirectoriesInIncludePath
{
my ($shell_command_ref, $tree, $dependencies, $triggered_dependencies) = @_ ;

if($$shell_command_ref =~ /%CFLAGS_INCLUDE/)
	{
	my $cflags_include = GetCFileIncludePaths($tree);
	
	$$shell_command_ref =~ s/%CFLAGS_INCLUDE/$cflags_include/ ;
	}
} ;

my $pbs_config = GetPbsConfig() ;
PBS::Plugin::LoadPluginFromSubRefs($pbs_config, '+001C.pm', 'EvaluateShellCommand' =>
	\&IncludeSourceDirectoriesInIncludePath) ;

# todo
# remove from C_FLAGS_INCLUDE all the repository directories, it's is not a mistake to leave them but it look awkward
# to have the some include path twice on the command line

unless(GetConfig('CDEFINES'))
	{
	my @defines = %{GetPbsConfig()->{COMMAND_LINE_DEFINITIONS}} ;
	if(@defines)
		{
		AddCompositeDefine('CDEFINES', @defines) ;
		}
	else
		{
		AddConfig('CDEFINES', '') ;
		}
	}
	
#-------------------------------------------------------------------------------

my %config = GetConfig() ; # remove a few hundred function call by using a hash

my $c_defines = $config{CDEFINES} ;
AddNodeVariableDependencies(qr/\.o$/, CDEFINES => $c_defines) ;

AddConfigTo('BuiltIn', 'CFLAGS_INCLUDE:LOCAL' => '') unless($config{CFLAGS_INCLUDE}) ;
	
#-------------------------------------------------------------------------------

ExcludeFromDigestGeneration( 'cpp_files' => qr/\.cpp$/) ;
ExcludeFromDigestGeneration( 'c_files'   => qr/\.c$/) ;
ExcludeFromDigestGeneration( 's_files'   => qr/\.s$/) ;
ExcludeFromDigestGeneration( 'h_files'   => qr/\.h$/) ;
ExcludeFromDigestGeneration( 'libs'      => qr/\.a$/) ;
ExcludeFromDigestGeneration( 'inc files' => qr/\.inc$/ ) ;
ExcludeFromDigestGeneration( 'msxml.tli' => qr/msxml\.tli$/ ) ;
ExcludeFromDigestGeneration( 'msxml.tlh' => qr/msxml\.tlh$/ ) ;

#-------------------------------------------------------------------------------

# we want the system to find source code for object files
# the source code can be C, C++, or Assembler

# we define rules for each of  those languages and add a test to the dependers
# the depender triggers only when a physical source file is found. 

# we also add a rule to make sure only of the language rules has triggered

sub exists_on_disk
{
my
	(
	$dependent_to_check,
	$config,
	$tree,
	$inserted_nodes,
	$dependencies,         # rule local
	$builder_override,     # rule local
	$rule_definition,      # for introspection
	) = @_ ;


my $build_directory    = $tree->{__PBS_CONFIG}{BUILD_DIRECTORY} ;
my $source_directories = $tree->{__PBS_CONFIG}{SOURCE_DIRECTORIES} ;

my ($triggered, @my_dependencies) ;

shift @$dependencies ; # previous trigger state

for my $source (@$dependencies)
	{
	my ($build_name, $is_alternative_source, $other_source_index) 
		= PBS::Check::LocateSource($source, $build_directory, $source_directories, $tree->{__PBS_CONFIG}{DISPLAY_SEARCH_INFO}) ;

	if( -e $build_name)
		{
		push @my_dependencies, $source ;
		$triggered = 1 ;
		}
	else
		{
		if($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
			{
			print WARNING 
				$PBS::Output::indentation
				. "Additional 'exists_on_disk' for rule: $rule_definition->{NAME}\n"
					 # "@ $rule_definition->{FILE}:$rule_definition->{LINE}\n" 
				. $PBS::Output::indentation x 2
				. "dependency '$source' not found on disk as '$build_name'.\n" ;
			}

		# all listed dependencies in the must exist
		@my_dependencies = () ;
		$triggered = 0 ;
		last ;
		}
	}

unshift @my_dependencies, $triggered ;

return(\@my_dependencies, $builder_override) ;
}

#-------------------------------------------------------------------------------

my $c_compiler_host = $config{C_COMPILER_HOST} ;

my $check_c_files = GetConfig('CHECK_C_FILES:SILENT_NOT_EXISTS') || 0 ;

if ($check_c_files)
	{
	AddRuleTo 'BuiltIn', 'c_objects', 
		#depender
		[ '*/*.o' => '*.c' , \&exists_on_disk],
		#builder
		[
		GetConfig('CC_SYNTAX'),
		"rsm %DEPENDENCY_LIST",
		"splint %CFLAGS_INCLUDE -I%PBS_REPOSITORIES %DEPENDENCY_LIST || true" 
		];
	}
else
	{
	AddRuleTo 'BuiltIn', 'c_objects', [ '*/*.o' => '*.c' , \&exists_on_disk],
	GetConfig('CC_SYNTAX') ;
	}

	
#-------------------------------------------------------------------------------

AddRuleTo 'BuiltIn', 'cpp_objects', [ '*/*.o' => '*.cpp' , \&exists_on_disk],
	GetConfig('CXX_SYNTAX') ;

#-------------------------------------------------------------------------------

my $as_compiler_host = $config{AS_COMPILER_HOST} ;

AddRuleTo 'BuiltIn', 's_objects', [ '*/*.o' => '*.s', \&exists_on_disk ],
	GetConfig('AS_SYNTAX') ;

#-------------------------------------------------------------------------------

# dynamic depender that checks that a node only has one dependency
# we use this, for example, in the rule set that automatically finds
# the dependency for object files from different possible language implementations
sub OnlyOneDependency
{
my
        (
        $dependent_to_check,
        $config,
        $tree,
        $inserted_nodes,
        $dependencies,         # rule local
        $builder_override,     # rule local
        $rule_definition,      # for introspection
        ) = @_ ;


# nodes starting with '__' are private to pbs and should not be depended (ex virtual root)
return([0], $builder_override) if $dependent_to_check =~ /^__/ ;

my @dependencies = grep {! /^__/ } keys %$tree ;

if($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
	{
	print WARNING 
		$PBS::Output::indentation
		. "Additional 'only_one_dependency' for rule: $rule_definition->{NAME}\n" ;
	}

if (@dependencies > 1)
	{
	PrintError "Error: multiple dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n"
			. $PBS::Output::indentation . "Rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
			. $PBS::Output::indentation . "(try pbs options: -dpl -ddl  --display_dependency_regex --display_search_info)\n" ; 	

	for (@dependencies)
		{
		my $rule = $tree->{__MATCHING_RULES}[0]{RULE}{DEFINITIONS}[$tree->{$_}{RULE_INDEX}] ;

		PrintError "\t$_ rule " . $tree->{$_}{RULE_INDEX} . ' @ ' . $rule->{NAME} . ':' . $rule->{FILE} . ':' . $rule->{LINE} . "\n" ;
		}
	die "\n";
	}
elsif (0 == @dependencies)
	{
	PrintWarning "Warning: no dependencies for '$dependent_to_check' inserted at ". $tree->{__INSERTED_AT}{INSERTION_RULE} ." :\n" 
			. $PBS::Output::indentation . "Rule: '$rule_definition->{NAME} @ $rule_definition->{FILE}:$rule_definition->{LINE}\n"
			. $PBS::Output::indentation . "(try pbs options: -dpl -ddl --display_dependency_regex  --display_search_info)\n" ; 	

	}

return [0] ;
}

AddRuleTo 'BuiltIn', 'check object file dependencies', [ '*/*.o' => \&OnlyOneDependency] ;

#~ PbsUse 'Rules/C_DependAndBuild' ;

#-------------------------------------------------------------------------------

1 ;

