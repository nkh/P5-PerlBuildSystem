=head1 PBSFILE USER HELP

Test configuration correctness

=head2 Top rules

=over 2 

=item * '*.o'

=back

=cut

AddConfig 'MULTIPLE_CC' => 'miner_3_multiple_cc' ;

#~ AddRule 'o2c', ['*/*.o' => '*.c'] ;

#~ AddRuleTo 'BuiltIn', 's_objects', [ '*.o' => '*.s' ], "AS ASFLAGS -o FILE_TO_BUILD DEPENDENCY_LIST";
#~ AddRuleTo 'BuiltIn', 'c_objects', [ '*.o' => '*.c' ], "CC CFLAGS -o FILE_TO_BUILD -c DEPENDENCY_LIST" ; 

PbsUse('Rules/C') ;

