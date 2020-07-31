=for test topo sort
my $t0_topo = [gettimeofday];

do 
	{
	my %ba;

	for my $node (keys %$inserted_nodes)
		{
		next unless $inserted_nodes->{$node}{__TRIGGERED} ;

		for my $dep ( grep {0 != index($_, '__')} keys %{$inserted_nodes->{$node}} )
			{
			$ba{$node}{$dep} = 1 ;
			$ba{$dep} ||= {};
			}
		}

	while ( my @afters = sort grep { ! %{ $ba{$_} } } keys %ba )
		{
		print join("\n",@afters) . "\n";
		delete @ba{@afters};
		delete @{$_}{@afters} for values %ba;
		}

	print !!%ba ? "Cycle found! ". join( ' ', sort keys %ba ). "\n" : "";
	} ;

PrintInfo(sprintf("Check: topo sort time: %0.2f s.\n", tv_interval ($t0_topo, [gettimeofday]))) if $pbs_config->{DISPLAY_CHECK_TIME} ;
=cut

