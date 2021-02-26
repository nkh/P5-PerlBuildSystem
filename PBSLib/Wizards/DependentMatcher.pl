# WIZARD_GROUP PBS
# WIZARD_NAME  dependent matcher
# WIZARD_DESCRIPTION template for a dependent matcher
# WIZARD_ON

print <<'EOP' ;

sub
{
my ($pbs_config, $dependent_to_check, $target_path, $display_regex) = @_ ;

if( $dependent_to_check !~ /__PBS/ )
	{
	PrintInfo2
		"${PBS::Output::indentation}<< sub >>:"
		. GetRunRelativePath($pbs_config, __FILE__)
		. ":" . __LINE__ . "\n" 
			
			if $display_regex ;
		
	return $dependent_regex_definition->(@_) ;
	}
else
	{
	return 0 ;
	}
}

# example
rule 'gant_dependency', [ sub{ $_[1] !~ qr/__PBS/ && $_[1] !~ qr/\.gant$/} => '$path/$basename.gant'] ;

# dependency_evaluator

sub 
{
my ($dependent, $config, $tree, $inserted_nodes, $rule_definition) = @_ ;

return ($match, @dependencies) ;
}

EOP

