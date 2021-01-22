sub SetTime 
{
my ($start_time, $build_time, $verbose) = @_ ;
sub 
	{
	my ($dependent_to_check, $config, $node, $inserted_nodes) = @_ ;

	PrintInfo4 "GANT: setting $node->{__NAME}, start_time: $start_time, build_time: $build_time\n" if $verbose;
	$node->{__CONFIG} = { %{$node->{__CONFIG}}, _GANT_START_TIME => $start_time, _GANT_BUILD_TIME => $build_time } ;
	}
}

#--------------------------------------------------
1 ;
