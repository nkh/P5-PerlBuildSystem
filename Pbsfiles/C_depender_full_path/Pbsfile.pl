=head1 PBSFILE USER HELP

Test digest and dependency files

=head2 Top rules

=over 2 

=item * 'all'

=item * 'test'

=back

=cut

AddConfig(C_DEPENDER_SYSTEM_INCLUDES => 1) ;

PbsUse('Configs/Compilers/gcc') ;
PbsUse('Rules/C') ;

AddRule [VIRTUAL], 'all', ['all' => 'a.out'], BuildOk('') ;

AddRule 'a.out', ['a.out' => '/home/nadim/nadim/devel/repositories/perl_modules/P5-PerlBuildSystem/Pbsfiles/C_depender_full_path/main.o', 'world.o']
	, "%CC -o %FILE_TO_BUILD %DEPENDENCY_LIST" ;


AddRule [VIRTUAL, FORCED], 'test', ['test' => 'a.out'],
		[
		sub {PrintUser("Running test\n") ; (1, 'test message')}
		#, "%DEPENDENCY_LIST"
		] ;
