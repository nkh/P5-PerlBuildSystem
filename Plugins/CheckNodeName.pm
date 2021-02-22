
=head1 CheckNodeName

Check node names before it is added to the dependency graph

=cut

#-------------------------------------------------------------------------------

sub CheckNodeName
{
my ($node_name, $rule) = @_ ;

if($node_name =~ /\s/ || $node_name =~ /\\/)
	{
	PrintError "Check : '$node_name' contains spaces and/or backslashes\n" ;
		
	PbsDisplayErrorWithContextr $pbs_config, $rule->{FILE}, $rule->{LINE} ;
	die "\n" ;
	}
}

#-------------------------------------------------------------------------------

1 ;

