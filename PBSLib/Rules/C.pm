
use strict ;
use warnings ;

PbsUse('Rules/C_EvalShellCommand') ; # add %C_FILE ...

# ------------------- Check Configuration -------------------

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
	
AddConfigTo('BuiltIn', 'CFLAGS_INCLUDE:LOCAL' => '') unless(GetConfig('CFLAGS_INCLUDE:SILENT_NOT_EXISTS')) ;
	
# make all object files depend on CDEFINES, it will be added to the digest
AddNodeVariableDependencies(qr/\.o$/, CDEFINES => GetConfig('CDEFINES')) ;
# above needs to be completed! also note that .o can be have multiple source type
# CC_SYNTAX => "%%CC  %%CFLAGS   %%CDEFINES  %%CFLAGS_INCLUDE  -I%%PBS_REPOSITORIES -o %%FILE_TO_BUILD -c %%C_SOURCE %%C_DEPENDER",

# ------------------------- declare source file types -------------------------

for
	(
	[ 'cpp_files' => qr/\.cpp$/ ],
	[ 'c_files'   => qr/\.c$/   ], 
	[ 's_files'   => qr/\.s$/   ], 
	[ 'h_files'   => qr/\.h$/   ], 
	[ 'libs'      => qr/\.a$/   ], 
	)
	{
	ExcludeFromDigestGeneration( @{$_} ) ;
	}

# ---------- rules ----------

PbsUse('Rules/Object_rules_utils') ; # for object dependencies cache generation 

AddRule [MULTI], 'c_objects',   [ '*/*.o' => '*.c', \&exists_on_disk],  GetConfig('CC_SYNTAX') ;

# or set of rules to pick a source file for object files
# comment out if you have object files generated from different sources
#AddRule 'cpp_objects', [ '*/*.o' => '*.cpp' , \&exists_on_disk],  GetConfig('CXX_SYNTAX') ;
#AddRule 's_objects',   [ '*/*.o' => '*.s'   , \&exists_on_disk ], GetConfig('AS_SYNTAX') ;
# make sure we only have one source
#AddRule 'one source', [ '*/*.o' => \&OnlyOneDependency] ;

# object dependencies cache rules, has to be last as 'one_source' check for single dependency 
PbsUse('Rules/C_depender') ;

AddRule [MULTI], 'o_dependencies', [ qr<\.o$> => '$path/$name.trigger_dependencies', \&GetObjectDependencies] ;
AddRule [VIRTUAL, MULTI], 'o_dependencies_trigger', ['*/*.trigger_dependencies'], BuildOk() ;
# GetObjecDependencies handles it's how dependencies (the dependency cache) which is build dynamically by the compiler 

use PBS::Depend ;
PBS::Depend::HasNoDependencies 'dependency cache', qr/\.trigger_dependencies$/ ;

# merge the dependencies generated by compiler 

AddPostBuildCommand 'o_local_dependency_merge', ['*/*.o'], 
	sub 
	{
	my
		(
		$node_build_result,
		$node_build_message,
		$config,
		$names,
		$dependencies,
		$triggered_dependencies,
		$arguments,
		$node,
		$inserted_nodes,
		) = @_ ;

	# merge dependencies in local process graph, end up in digest
	InsertDependencyNodes($node, $inserted_nodes) ;

	return $node_build_result, $node_build_message ;
	} ;

AddRule [MULTI], 'o_global_dependency_merge', ['*/*.o'],
	undef,
	[
	sub 
		{
		my ($node_name, $config, $tree, $inserted_nodes) = @_ ;

		# merge dependencies in main process graph, end up in the warp file
		$tree->{__PBS_POST_BUILD} = \&InsertDependencyNodes ;
		
		return 'setting __POST_PBS_BUILD to insert dependencies in the graph'
		}
	] ;
1 ;

