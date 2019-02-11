
=head1 CheckNodeName

Check node names before it is added to the dependency graph

=cut

#-------------------------------------------------------------------------------

sub CheckNodeName
{
my ($node_name, $rule) = @_ ;

if($node_name =~ /\s/ || $node_name =~ /\\/)
	{
	PrintError "Node '$node_name' contains spaces and/or backslashes. rule $rule->{NAME}$rule->{ORIGIN}\n" ;
		
	PbsDisplayErrorWithContext($rule->{FILE}, $rule->{LINE}) ;
	die ;
	}
}

#-------------------------------------------------------------------------------

1 ;

