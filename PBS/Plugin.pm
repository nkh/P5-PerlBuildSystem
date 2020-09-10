
package PBS::Plugin;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(ScanForPlugins RunPluginSubs RunUniquePluginSub LoadPluginFromSubRefs EvalShell) ;
our $VERSION = '0.04' ;

use File::Basename ;
use Getopt::Long ;
use Cwd ;

use PBS::Constants ;
use PBS::PBSConfig ;
use PBS::Output ;

#-------------------------------------------------------------------------------

my $plugin_load_package = 0 ;
my %loaded_plugins ;

if($^O eq "MSWin32")
	{
	# remove an annoying warning
	local $SIG{'__WARN__'} = sub {print STDERR $_[0] unless $_[0] =~ /^Subroutine CORE::GLOBAL::glob/} ;

	# the normal 'glob' handles ~ as the home directory even if it is not at the begining of the path
	eval "use File::DosGlob 'GLOBAL_glob';" ;
	die $@ if $@ ;
	}

#-------------------------------------------------------------------------------

sub GetLoadedPlugins { return(keys %loaded_plugins) }

#-------------------------------------------------------------------------------

sub LoadPlugin
{
my ($package, $file_name, $line) = caller() ;
my ($config, $plugin) = @_;

if($config->{DISPLAY_PLUGIN_LOAD_INFO})
	{
	my ($basename, $path, $ext) = File::Basename::fileparse($plugin, ('\..*')) ;
	PrintInfo "Plugin: loading: '$basename$ext'\n" ;
	}
	
if(exists $loaded_plugins{$plugin})
	{
	PrintWarning"Plugin: '$plugin' already loaded, ignoring plugin @ '$file_name:$line'\n" 
		if ("$file_name:$line" ne $loaded_plugins{$plugin}[1]) || $config->{DISPLAY_PLUGIN_LOAD_INFO} ;

	return ;
	}
	
eval
	{
	PBS::PBS::LoadFileInPackage
		(
		'',
		$plugin,
		"PBS::PLUGIN_$plugin_load_package",
		{},
		"use strict ;\nuse warnings ;\n"
		  . "use PBS::Output ;\n",
		) ;
	} ;
	
do { PrintError("Plugin: Couldn't load plugin from '$plugin'.$@") ; die "\n" }  if $@ ;

$loaded_plugins{$plugin} = [$plugin_load_package, "$file_name:$line"];
$plugin_load_package++ ;
}

#-------------------------------------------------------------------------------

sub LoadPluginFromSubRefs
{
my ($package, $file_name, $line) = caller() ;
my ($config, $plugin, %subs) = @_;

PrintInfo "Plugin: loading: '$plugin' from '$file_name:$line':\n" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;

if(exists $loaded_plugins{$plugin})
	{
	PrintWarning"Plugin: '$plugin' already loaded, ignoring plugin @ '$file_name:$line'\n"
		if ("$file_name:$line" ne $loaded_plugins{$plugin}[1]) || $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
	}
else
	{
	
	while (my($sub_name, $sub_ref) = each %subs)
		{
		PrintInfo "Plugin: name: '$sub_name'\n" if($config->{DISPLAY_PLUGIN_LOAD_INFO}) ;
			
		eval "* PBS::PLUGIN_${plugin_load_package}::$sub_name = \$sub_ref ;" ;

		if ($@)
			{
			PrintError "Plugin: Error: can't load sub ref '$sub_name'\n" ;
			die $@ ;
			}
		}
	
	$loaded_plugins{$plugin} = [$plugin_load_package, "$file_name:$line"];
	$plugin_load_package++ ;
	}
}

#-------------------------------------------------------------------------------

my $eval_shell_counter= 0 ; # make plugins uniq
sub EvalShell($)
{
# syntactic sugar which wraps LoadPluginFromSubRefs and allows us to write
# shorter code in pbsfilee:
#	EvalShell q~ s<%OEM><(split('/',$node_ndsadfme ed))[1]>eg ~ ;

my ($package, $file_name, $line) = caller() ;
my ($substitution) = @_ ;
$eval_shell_counter++ ;

LoadPluginFromSubRefs PBS::PBSConfig::GetPbsConfig($package), "$file_name:$line:$eval_shell_counter",
	'EvaluateShellCommand' =>
		sub 
		{ 
		my ($shell_command_ref, $node, $dependencies) = @_ ;

		my $node_name = $node->{__NAME} ;

		PrintInfo2 "Eval: $substitution @ '$file_name'\n"
			 if $node->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
	
		eval "\$\$shell_command_ref =~ $substitution" ;

		if ($@)
			{
			PrintError "EvalShell: Error in substitution code: $substitution\n" ;
			die $@ ;
			}
		} ;
}

#-------------------------------------------------------------------------------

sub ScanForPlugins
{
my ($config, $plugin_paths) = @_ ;

for my $plugin_path (@$plugin_paths)
	{
	PrintInfo "Plugin: scanning directory '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
	
	for my $plugin (glob("$plugin_path/*.pm"))
		{
		LoadPlugin($config, $plugin) ;
		}
	}
}

#-------------------------------------------------------------------------------

sub RunPluginSubs
{
# run multiple subs, don't return anything

my ($config, $plugin_sub_name, @plugin_arguments) = @_ ;

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

PrintInfo "Plugin: '$plugin_sub_name' called at '$file_name:$line':\n" if $config->{DISPLAY_PLUGIN_RUNS} ;

for my $plugin_path (sort keys %loaded_plugins)
	{
	no warnings ;

	my $plugin_load_package = $loaded_plugins{$plugin_path}[0] ;
	
	my $plugin_sub ;
	
	eval "\$plugin_sub = *PBS::PLUGIN_${plugin_load_package}::${plugin_sub_name}{CODE} ;" ;
	
	if($plugin_sub)
		{
		PrintInfo "\trunning in '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		
		eval {$plugin_sub->(@plugin_arguments)} ;
		die ERROR "Plugin: error running '$plugin_sub_name':\n$@" if $@ ;
		}
	else
		{
		PrintWarning "\tnot in '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		}
	}
}

#-------------------------------------------------------------------------------

sub RunUniquePluginSub
{
# run a single sub and returns

my ($config, $plugin_sub_name, @plugin_arguments) = @_ ;

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

PrintInfo "Plugin: '$plugin_sub_name' called at '$file_name:$line':\n" if $config->{DISPLAY_PLUGIN_RUNS} ;

my (@found_plugin, $plugin_path, $plugin_sub) ;
my ($plugin_sub_to_run, $plugin_to_run_path) ;

for $plugin_path (sort keys %loaded_plugins)
	{
	no warnings ;

	my $plugin_load_package = $loaded_plugins{$plugin_path}[0] ;
	
	eval "\$plugin_sub = *PBS::PLUGIN_${plugin_load_package}::${plugin_sub_name}{CODE} ;" ;
	push @found_plugin, $plugin_path if($plugin_sub) ;

	if($plugin_sub)
		{
		$plugin_sub_to_run = $plugin_sub ;
		$plugin_to_run_path = $plugin_path ;
		PrintInfo "\tfound in '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		}
	else
		{
		PrintWarning "\tnot in '$plugin_path'\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
		}
	}
	
if(@found_plugin > 1)
	{
	die ERROR "Plugin: error, found more than one plugin for unique '$plugin_sub_name'\n" . join("\n", @found_plugin) . "\n" ;
	}

if($plugin_sub_to_run)
	{
	PrintInfo "Plugin: running '$plugin_sub_name''\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
	
	if(! defined wantarray)
		{
		eval {$plugin_sub_to_run->(@plugin_arguments)} ;
		die ERROR "Plugin: error running '$plugin_sub_name':\n$@" if $@ ;
		}
	else
		{
		if(wantarray)
			{
			my @results ;
			eval {@results = $plugin_sub_to_run->(@plugin_arguments)} ;
			die ERROR "Plugin: error running '$plugin_sub_name':\n$@" if $@ ;
			
			return(@results) ;
			}
		else
			{
			my $result ;
			eval {$result = $plugin_sub_to_run->(@plugin_arguments)} ;
			die ERROR "Plugin: error running '$plugin_sub_name':\n$@" if $@ ;
			
			return($result) ;
			}
		}
	}
else
	{
	PrintWarning "Plugin: couldn't find '$plugin_sub_name'.\n" if $config->{DISPLAY_PLUGIN_RUNS} ;
	return ;
	}
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Plugin  - Handle Plugins in PBS

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 LIMITATIONS

plugins can't hadle the same switch (switch registred by a plugin, pbs switches OK when passed to plugin)

=head2 EXPORT

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
