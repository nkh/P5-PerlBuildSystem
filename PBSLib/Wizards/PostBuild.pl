# WIZARD_GROUP PBS
# WIZARD_NAME  post_build
# WIZARD_DESCRIPTION template for a post build rule
# WIZARD_ON

print <<'EOT' ;

sub 
	{
	my
		(
		$node_build_result,
		$node_build_message,
		$config,
		$names,
		$dependencies,
		$triggered_dependencies,
		$arguments,
		$node,
		$inserted_nodes,
		) ;

	$node_build_result, $node_build_message,
	} ;

EOT

# ------------------------------------------------------------------
1;

