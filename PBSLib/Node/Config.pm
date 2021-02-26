
sub ExportConfig { my @r = @_ ; sub { push @{$_[2]->{__EXPORT_CONFIG}}, @r ? @r : '.' } }

sub NodeConfig
{
my @c = @_ ;

sub 
	{
	my ($node_name, $config, $tree, $inserted_nodes,) = @_ ;

	# update node's package config, this goes through all the config tests
	Config GetNodeConfig($tree), @c ;

	# update node config
	%{$tree->{__CONFIG}} = ( %{$tree->{__CONFIG}}, @c ) ;
	}
}

sub GetNodeConfig
{
my ($tree) = @_ ;

unless (exists $tree->{__PACKAGE_CONFIG})
	{
	PBS::Config::GetPackageConfig $tree->{__NAME}, PBS::Config::GetClone($tree->{__INSERTED_AT}{INSERTION_LOAD_PACKAGE}) ;

	$tree->{__PACKAGE_CONFIG} = $tree->{__CONFIG} ;
	$tree->{__CONFIG} = { %{$tree->{__CONFIG}} } ;


	$tree->{__PACKAGE_PBS_CONFIG} = $tree->{__PBS_CONFIG} ;
	$tree->{__PBS_CONFIG} = PBS::PBSConfig::RegisterPbsConfig $tree->{__NAME}, $tree->{__PBS_CONFIG} ;
	}

$tree->{__NAME} ;
}

sub GetNodePbsConfig {}

1 ;
