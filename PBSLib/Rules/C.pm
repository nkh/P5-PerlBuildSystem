
use strict ;
use warnings ;

PbsUse('Rules/C_EvalShellCommand') ; # add %C_FILE ...

# -------------------
# Check Configuration 
# -------------------

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

# -------------------------
# declare source file types
# -------------------------

for
	(
	[ 'cpp_files'        => qr/\.cpp$/          ],
	[ 'c_files'          => qr/\.c$/            ], 
	[ 'o_dependencies'   => qr/\.dependencies$/ ], 
	[ 's_files'          => qr/\.s$/            ], 
	[ 'h_files'          => qr/\.h$/            ], 
	[ 'libs'             => qr/\.a$/            ], 
	[ 'inc files'        => qr/\.inc$/          ],  
	[ 'msxml.tli'        => qr/msxml\.tli$/     ],  
	[ 'msxml.tlh'        => qr/msxml\.tlh$/     ],  
	)
	{
	ExcludeFromDigestGeneration( @{$_} ) ;
	}

# -----
# rules
# -----

PbsUse('Rules/Object_rules_utils') ; # for object dependencies cache generation 

# set of rules to pick a source file for object files

# note the generation of the dependency cache for object files in the rule
AddRuleTo 'BuiltIn', 'c_objects', [ '*/*.o' => '*.c' , \&exists_on_disk],
	GetConfig('CC_SYNTAX') . ' -MD -MP -MF %FILE_TO_BUILD.dependencies' ;

AddRuleTo 'BuiltIn', 'cpp_objects', [ '*/*.o' => '*.cpp' , \&exists_on_disk],
	GetConfig('CXX_SYNTAX') ;

AddRuleTo 'BuiltIn', 's_objects', [ '*/*.o' => '*.s', \&exists_on_disk ],
	GetConfig('AS_SYNTAX') ;

# make sure we only have one source
AddRuleTo 'BuiltIn', 'one source', [ '*/*.o' => \&OnlyOneDependency] ;

# object cache rules
# has to be last as previous rules check for single dependency 

PbsUse('Rules/C_depender') ; # for object dependencies cache generation 

AddRuleTo 'BuiltIn', 'h_dpendencies', [ '*/*.o' =>  \&read_dependencies_cache] ;
AddRuleTo 'BuiltIn', 'h_dpendencies_cache', [ '*/*.dependencies'], 'echo will be generate by compiler > %FILE_TO_BUILD' ;

1 ;

