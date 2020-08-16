

=head1 Plugin PackageVisualisation

This plugin handles the following PBS defined switches:

=over 2

=item  --dc

=item --dca

=item --dur

=item --dsd

=item --dbs

=back

=cut

use PBS::PBSConfigSwitches ;
use PBS::Information ;
use Data::TreeDumper ;

#-------------------------------------------------------------------------------

sub PreDepend
{
my ($pbs_config, $package_alias, $config_snapshot, $config, $source_directories, $dependency_rules) = @_ ;

if(defined $pbs_config->{DISPLAY_SOURCE_DIRECTORIES})
	{
	PrintInfo(DumpTree($source_directories, "Depend: source directories:")) ;
	}
if($pbs_config->{DISPLAY_CONFIGURATION})
		{
		PrintInfo(DumpTree($config, "Depend: config for package '$package_alias' before rules are run:", DISPLAY_ADDRESS => 0));
		}
		
if($pbs_config->{DISPLAY_CONFIGURATION_NAMESPACES})
		{
		PrintInfo(DumpTree($config_snapshot, "Depend: config namespaces for '$package_alias':", DISPLAY_ADDRESS => 0)) ;
		}
		
if(defined $pbs_config->{DISPLAY_USED_RULES}) #only the rules configured in
	{
	my $title =  "Depend: dependency rules for package '$package_alias':" ;

	if(defined $pbs_config->{DISPLAY_USED_RULES_NAME_ONLY})
		{
		PrintInfo(DumpTree([map{"'$_->{NAME}'$_->{ORIGIN}"} @{$dependency_rules}], $title, DISPLAY_ADDRESS => 0)) ;
		}
	else
		{
		PrintInfo(DumpTree($dependency_rules, $title, DISPLAY_ADDRESS => 0)) ;
		}
	}
}

#-------------------------------------------------------------------------------

1 ;
