
=head1 PBSFILE USER HELP


pbs -p parent.pl parent -dpl -dc -D OPTIMIZE_FLAG_1='from_command_line'

=head2 Top rules

=over 2 

=item * parent

=back

=cut

AddConfig OPTIMIZE_FLAG_1 => 'first_value_parent';
AddConfig OPTIMIZE_FLAG_1 => 'second_value_parent' ; 
AddConfig OPTIMIZE_FLAG_2 => 'first_value_parent' ;
AddConfig OPTIMIZE_FLAG_3 => 'first_value_parent' ;
AddConfig UNDEF_FLAG => undef ;

AddRule '1', [ 'parent' => 'child'] ;

AddRule 'child',
	{
	NODE_REGEX => 'child',
	PBSFILE => './child.pl',
	PACKAGE => 'child',
	#~ COMMAND_LINE_DEFINITIONS => { OPTIMIZE_FLAG_3 => 'zzz'},
	} ;
