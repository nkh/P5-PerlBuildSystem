
my @config_keys = GetConfigKeys() ;

if(2 != @config_keys)
	{
	my %config = (map {$_ => GetConfig($_)} @config_keys) ;

	use Data::TreeDumper ;
	PrintInfo DumpTree(\%config, 'Package config') ;

	# TARGET_PATH is always added by PBS
	die "more than one entry in config!" ;
	}

AddRule 'yy', ['yy'], BuildOk() ;
