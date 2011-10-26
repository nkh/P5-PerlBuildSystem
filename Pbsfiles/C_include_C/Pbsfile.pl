=head1 Comments

When C files include C files, the C depender, which merged the include C file in the graph,
is called again to depend the merged C file.

Here is an attempt to understand what's going opn and how to avoid the problem

=cut

PbsUse('Configs/Compilers/gcc') ;
PbsUse('Rules/C') ;

AddRule [VIRTUAL], 'all', ['all' => 'a.out'], BuildOk('') ;

AddRule 'a.out', ['a.out' => 'main.o', 'world.o']
	, "%CC -o %FILE_TO_BUILD %DEPENDENCY_LIST" ;
