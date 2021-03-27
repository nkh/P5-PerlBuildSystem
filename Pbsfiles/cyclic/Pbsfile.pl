
=for PBS =head1 Top rules

=over 2

=item * all, tests an include file dependency

=item * a1, test node dependencies with 1 cycle

=item * a3, test node dependencies with 3 cycles

=back

=cut

=head1 SYNOPSIS

2 c files including 2 header files but in a different order the header files include each other

This leads to a dependency when the tree is merged though it is not an error when compiling each file
individually

=cut

pbsuse 'Configs/Compilers/gcc' ;
pbsuse 'Builders/Objects' ; 
pbsuse 'Rules/C' ; 

#-------------------------------------------------------------------------------

my @sources = qw/ a.c b.c / ;

rule [V], 'all',         [ all     => 'cyclic_test' ],              build_ok ;
rule [V], 'cyclic_test', [ cyclic_test => 'cyclic_test.objects' ],  build_ok ;
rule      'objects',     [ 'cyclic_test.objects' => @sources ], \&CreateObjectsFile ;


#-------------------------------------------------------------------------------

rule 'a1', [ a1 => 'b1' ] ; # single cycle
rule 'b1', [ b1 => qw. a1 a b c . ] ;

rule 'a3', [ a3 => qw. b3 . ] ; # three cycles
rule 'b3', [ b3 => qw. c3 a b c . ] ;
rule 'c3', [ c3 => 'a3'  ] ;


