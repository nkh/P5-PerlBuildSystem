

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
	PrintInfo "Depend: source directories:\n"
			. DumpTree
				(
				$source_directories,
				'',
				DISPLAY_ADDRESS => 0,
				INDENTATION => ($PBS::Output::indentation x 2),
				) ;
	}

if($pbs_config->{DISPLAY_CONFIGURATION})
		{
		PrintInfo "Config: package '$package_alias':\n"
				. DumpTree
					(
					$config,
					'',
					DISPLAY_ADDRESS => 0,
					INDENTATION => ($PBS::Output::indentation x 2),
					) ;
		}
		
if($pbs_config->{DISPLAY_CONFIGURATION_NAMESPACES})
		{
		PrintInfo "Depend: config namespaces for '$package_alias':\n"
				. DumpTree
					(
					$config_snapshot,
					'',
					DISPLAY_ADDRESS => 0,
					INDENTATION => ($PBS::Output::indentation x 2),
					) ;
		}
		
if(defined $pbs_config->{DISPLAY_USED_RULES}) #only the rules configured in
	{
	if(defined $pbs_config->{DISPLAY_USED_RULES_NAME_ONLY})
		{
		PrintInfo "Rules: package '$package_alias':\n"
				. DumpTree
					(
					[map{"'$_->{NAME}'$_->{ORIGIN}"} @{$dependency_rules}],
					'',
					DISPLAY_ADDRESS => 0,
					INDENTATION => ($PBS::Output::indentation x 2),
					) ;
		}
	else
		{
		PrintInfo "Rules: package '$package_alias':\n"
				. DumpTree
					(
					$dependency_rules,
					'',
					DISPLAY_ADDRESS => 0,
					INDENTATION => ($PBS::Output::indentation x 2),
					) ;
		}
	}
}

#-------------------------------------------------------------------------------

1 ;
