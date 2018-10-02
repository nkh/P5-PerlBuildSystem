
=head1 GNU toolchain configuration

=cut

#-------------------------------------------------------------------------------

#PBS::Config::AddConfigTo 'BuiltIn',
AddConfigTo 'BuiltIn',
	(
	# tools 
	CC      => 'gcc',
	LD      => 'ld',
	LDFLAGS => '-lm',
	CPP     => 'cpp',
	CXX     => 'g++',
	AR      => 'ar',
	AS      => 'as',
	OBJDUMP => 'objdump -h',
	
	# extensions
	EXE_EXT => '',
	O_EXT   => '.o',
	A_EXT   => '.a',
	SO_EXT  => '.so',

	ARFLAGS  => 'cru', # Flags to the archiver command when creating link libraries.
	
	# C compiler flags
	OPTIMIZE_CFLAGS => '-O2', # Optimization options to the C compiler.
	DEBUG_CFLAGS    => '-g',
	SPECIAL_CFLAGS  => '-g -ffunction-sections' . (GetConfig('GENERATE_COVERAGE:SILENT_NOT_EXISTS') 
							? ' -ftest-coverage -fprofile-arcs' 
							: ''), 

	WFLAGS  => # C compiler warning flags
		'-Wall -Wshadow -Wpointer-arith -Wcast-qual -Wcast-align '
		. '-Wwrite-strings -Wstrict-prototypes -Wmissing-prototypes '
		. '-fdiagnostics-color=always '
		. '-Wmissing-declarations -Wredundant-decls -Wnested-externs -Winline',
								

	CFLAGS  => # all C compiler flags
		'%WFLAGS %SPECIAL_CFLAGS -fPIC ' . ( GetConfig('COMPILER_DEBUG:SILENT_NOT_EXISTS') 
							? '%DEBUG_CFLAGS' 
							: '%OPTIMIZE_CFLAGS'
							),
	CXXFLAGS => '%%CFLAGS',
	
	# defines
	OPTIMIZE_CDEFINES => '-DNDEBUG',
	DEBUG_CDEFINES    => '',
	CDEFINES          => GetConfig('COMPILER_DEBUG:SILENT_NOT_EXISTS')
						? '%DEBUG_CDEFINES' 
						: '%OPTIMIZE_CDEFINES',
	
	C_DEPENDER => GetConfig('C_DEPENDER_SYSTEM_INCLUDES:SILENT_NOT_EXISTS')
			? '-MD  -MP -MF %%FILE_TO_BUILD.dependencies'
			: '-MMD -MP -MF %%FILE_TO_BUILD.dependencies',

	# command syntax
	CC_SYNTAX  => "%%CC  %%CFLAGS   %%CDEFINES  %%CFLAGS_INCLUDE  -I%%PBS_REPOSITORIES -o %%FILE_TO_BUILD -c %%C_SOURCE %%C_DEPENDER",
	CXX_SYNTAX => "%%CXX %%CXXFLAGS %%CDEFINES  %%CFLAGS_INCLUDE  -I%%PBS_REPOSITORIES -o %%FILE_TO_BUILD -c %%C_SOURCE",
	AS_SYNTAX  => "%%AS  %%ASFLAGS  %%ASDEFINES %%ASFLAGS_INCLUDE -I%%PBS_REPOSITORIES -o %%FILE_TO_BUILD %%DEPENDENCY_LIST",
	) ;

#-------------------------------------------------------------------------------
1 ;

