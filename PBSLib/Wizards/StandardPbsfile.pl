# WIZARD_GROUP PBS
# WIZARD_NAME  Pbsfile
# WIZARD_DESCRIPTION template for a standard Pbsfile
# WIZARD_ON

print "Please give a one line description of this Pbsfile: " ;
my $purpose = <STDIN> ;
chomp($purpose) ;

#print <<EOP ;
=head1 PBSFILE USER HELP

=head2 I<pbsfile.pl>

# documentation displayed when -uh is used

$purpose

=cut 

=head2 Top rules

...

=cut

pbsuse 'Rules/...' ; 
pbsuse 'Configs/...' ; 

#-------------------------------------------------------------------------------

rule [V], 'rule_name', ['dependent' => '', ''], \&BUILDER, [\&node_sub, ...] ;


=head2 Rule 'rule_name'

	normal pod documentation

=cut

rule 'rule_name2', ['*\*.*' => '*.*'], \&BUILDER, [\&node_sub, ...] ;

rule 'rule_name3', ['*\*.*' => '*.*'], "command" ;

rule 'subpbs_name', {NODE_REGEX => '', PBSFILE => './Pbsfile.pl', PACKAGE => ''} ;

subpbs qr/regex/, $pbsfile ;
