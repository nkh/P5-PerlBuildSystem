
=head1 What 'Rules/C.pm' does.

=cut

use strict ;
use warnings ;

# ------
# Config 
# ------

PbsUse('Rules/C_EvalShellCommand') ; 

# todo: remove from C_FLAGS_INCLUDE all the repository directories,
# it's is not a mistake to leave them but it look awkward
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
	
AddConfigTo('BuiltIn', 'CFLAGS_INCLUDE:LOCAL' => '') unless(GetConfig('CFLAGS_INCLUDE:SILENT_NOT_EXISTS')) ;
	
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

PbsUse('Rules/Object_rules_utils') ;  

#todo: add C Checking if ( GetConfig('CHECK_C_FILES:SILENT_NOT_EXISTS') || 0 )

AddRuleTo 'BuiltIn', 'c_objects', [ '*/*.o' => '*.c' , \&exists_on_disk],
	GetConfig('CC_SYNTAX') . ' -MD -MP -MF %FILE_TO_BUILD.dependencies' ;

AddRuleTo 'BuiltIn', 'cpp_objects', [ '*/*.o' => '*.cpp' , \&exists_on_disk],
	GetConfig('CXX_SYNTAX') ;

AddRuleTo 'BuiltIn', 's_objects', [ '*/*.o' => '*.s', \&exists_on_disk ],
	GetConfig('AS_SYNTAX') ;

AddRuleTo 'BuiltIn', 'check object file dependencies', [ '*/*.o' => \&OnlyOneDependency] ;

# has to be last as previous rules check for single dependency 
AddRuleTo 'BuiltIn', 'h_dpendencies', [ '*/*.o' =>  \&read_dependencies_cache] ;

AddRuleTo 'BuiltIn', 'h_dpendencies_cache', [ '*/*.dependencies'], 'echo will be generate by compiler > %FILE_TO_BUILD' ;



1 ;

