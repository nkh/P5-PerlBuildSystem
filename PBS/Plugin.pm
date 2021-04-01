
package PBS::Plugin;

use v5.10 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(ScanForPlugins RunPluginSubs RunUniquePluginSub LoadPluginFromSubRefs EvalShell) ;
our $VERSION = '0.05' ;

use File::Basename ;
use Getopt::Long ;
use Cwd ;

use PBS::Constants ;
use PBS::PBSConfig ;
use PBS::Output ;

my $grrpc = {TARGET_PATH => '', SHORT_DEPENDENCY_PATH_STRING => '…'} ;

#-------------------------------------------------------------------------------

my %loaded_plugins ;

if($^O eq "MSWin32")
	{
	# remove an annoying warning
	local $SIG{'__WARN__'} = sub {print STDERR $_[0] unless $_[0] =~ /^Subroutine CORE::GLOBAL::glob/} ;

	# the normal 'glob' handles ~ as the home directory even if it is not at the beginning of the path
	eval "use File::DosGlob 'GLOBAL_glob';" ;
	die $@ if $@ ;
	}

#-------------------------------------------------------------------------------

sub GetLoadedPlugins { return(keys %loaded_plugins) }

#-------------------------------------------------------------------------------

sub ScanForPlugins
{
my ($config, $plugin_paths) = @_ ;

for my $plugin_path (@$plugin_paths)
	{
	my $plugins = my @plugins = glob("$plugin_path/*.pm") ;
	
	Say Info "Plugin: found $plugins in $plugin_path" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
	
	LoadPlugin($config, $_) for @plugins ;
	}
}

#-------------------------------------------------------------------------------

sub LoadPlugin
{
my (undef, $file_name, $line) = caller() ;
my ($config, $plugin) = @_;

my ($basename, $path, $ext) = File::Basename::fileparse($plugin, ('\..*')) ;

my $package = PBS::PBS::CanonizePackageName($basename) ;

Say Debug "Plugin: $basename.$ext" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
	
if(exists $loaded_plugins{$plugin})
	{
	Say Warning"Plugin: $plugin already loaded, ignoring plugin @ $file_name:$line\n" 
		if "$file_name:$line" ne $loaded_plugins{$plugin}[1] ;
	
	return ;
	}
	
eval
	{
	PBS::PBS::LoadFileInPackage
		(
		'',
		$plugin,
		"PBS::PLUGIN_$package",
		{},
		"use strict ;\nuse warnings ;\n"
		  . "use PBS::Output ;\n",
		) ;
	} ;
	
do { die ERROR("Plugin: Couldn't load $plugin.$@") . "\n" }  if $@ ;

$loaded_plugins{$plugin} = [$package, "$file_name:$line"] ;
}

#-------------------------------------------------------------------------------

sub LoadPluginFromSubRefs
{
my ($package, $file_name, $line) = caller() ;
my ($config, $plugin, %subs) = @_;

Say Debug "Plugin: $plugin @ " . GetRunRelativePath($grrpc, $file_name) . ":$line" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;

if(exists $loaded_plugins{$plugin})
	{
	Say Warning "Plugin: $plugin already loaded, ignoring plugin @ $file_name:$line"
		if "$file_name:$line" ne $loaded_plugins{$plugin}[1] ;
	}
else
	{
	while (my($sub_name, $sub_ref) = each %subs)
		{
		#Say Info "Plugin: name: $sub_name" if $config->{DISPLAY_PLUGIN_LOAD_INFO} ;
			
		eval "*PBS::PLUGIN_${plugin}::$sub_name = \$sub_ref ;" ;
		
		if ($@)
			{
			die ERROR("Plugin: Error: can't load sub ref $sub_name:\n$@") . "\n" ;
			}
		}
	
	$loaded_plugins{$plugin} = [$plugin, "$file_name:$line"] ;
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

LoadPluginFromSubRefs PBS::PBSConfig::GetPbsConfig($package), "${file_name}_${line}_$eval_shell_counter",
	'EvaluateShellCommand' =>
		sub 
		{ 
		my ($shell_command_ref, $node, $dependencies) = @_ ;

		my $node_name = $node->{__NAME} ;
		
		Say Info2 "EvalShell: $substitution @ $file_name:$line"
			 if $node->{__PBS_CONFIG}{EVALUATE_SHELL_COMMAND_VERBOSE} ;
	
		eval "\$\$shell_command_ref =~ $substitution" ;
		
		if ($@)
			{
			die ERROR("EvalShell: Error in substitution code: $substitution\n$@") . "\n" ;
			}
		} ;
}

#-------------------------------------------------------------------------------

my %found_subs ;

sub RunPluginSubs
{
# run multiple subs, don't return anything

my ($config, $plugin_sub_name, @plugin_arguments) = @_ ;

my (undef, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my @plugins = exists $found_subs{$plugin_sub_name} ? keys $found_subs{$plugin_sub_name}->%* : keys %loaded_plugins ;

for my $plugin (sort @plugins)
	{
	no warnings ;
	
	my $package = PBS::PBS::CanonizePackageName($loaded_plugins{$plugin}[0]) ;
	my $plugin_sub ;
	
	eval "\$plugin_sub = *PBS::PLUGIN_${package}::${plugin_sub_name}{CODE} ;" ;
	
	if($plugin_sub)
		{
		
		Say EC "<D3>Plugin: <D>$plugin_sub_name<D3> in " . GetRunRelativePath($grrpc, $plugin)
				." @ ". GetRunRelativePath($grrpc, $file_name) . ":$line"
			 if $config->{DISPLAY_PLUGIN_RUNS} ;
		
		eval {$plugin_sub->(@plugin_arguments)} ;
		
		$found_subs{$plugin_sub_name}{$plugin}++ ;
		
		die ERROR("Plugin: error running $plugin_sub_name:\n$@") . "\n" if $@ ;
		}
	else
		{
		Say EC "<D3>Plugin: $plugin_sub_name not in $plugin" if $config->{DISPLAY_PLUGIN_RUNS} && $config->{DISPLAY_PLUGIN_RUNS_ALL} ;
		}
	}
}

#-------------------------------------------------------------------------------

my %found_uniq_subs ;

sub RunUniquePluginSub
{
# run a single sub and returns

my ($config, $plugin_sub_name, @plugin_arguments) = @_ ;

unshift @plugin_arguments, $config ;

my (undef, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my (@found_plugin, $plugin_sub) ;
my ($plugin_sub_to_run, $plugin_to_run_path) ;

my @plugins = exists $found_uniq_subs{$plugin_sub_name} ? keys $found_uniq_subs{$plugin_sub_name}->%* : keys %loaded_plugins ;

for my $plugin (sort @plugins)
	{
	no warnings ;
	
	my $package = PBS::PBS::CanonizePackageName($loaded_plugins{$plugin}[0]) ;
	
	eval "\$plugin_sub = *PBS::PLUGIN_${package}::${plugin_sub_name}{CODE} ;" ;
	
	push @found_plugin, $plugin if($plugin_sub) ;
	
	if($plugin_sub)
		{
		$plugin_sub_to_run = $plugin_sub ;
		$plugin_to_run_path = $plugin ;
		
		$found_uniq_subs{$plugin_sub_name}{$plugin}++ ;
		}
	else
		{
		Say EC "<D3>Plugin: $plugin_sub_name not in $plugin" if $config->{DISPLAY_PLUGIN_RUNS} && $config->{DISPLAY_PLUGIN_RUNS_ALL} ;
		}
	}
	
if(@found_plugin > 1)
	{
	die ERROR "Plugin: error, found more than one plugin for unique $plugin_sub_name\n" . join("\n", @found_plugin) . "\n" ;
	}

if($plugin_sub_to_run)
	{
	Say EC "<D3>Plugin: <D>$plugin_sub_name<D3> in " . GetRunRelativePath($grrpc, $plugin_to_run_path)
			." @ ". GetRunRelativePath($grrpc, $file_name) . ":$line"
		 if $config->{DISPLAY_PLUGIN_RUNS} ;
	
	if(! defined wantarray)
		{
		eval { $plugin_sub_to_run->(@plugin_arguments) } ;
		
		die ERROR("Plugin: error running $plugin_sub_name:\n$@") . "\n" if $@ ;
		}
	else
		{
		if(wantarray)
			{
			my @results ;
			
			eval { @results = $plugin_sub_to_run->(@plugin_arguments) } ;
			
			die ERROR("Plugin: error running $plugin_sub_name:\n$@") . "\n" if $@ ;
			
			return @results ;
			}
		else
			{
			my $result ;
			
			eval { $result = $plugin_sub_to_run->(@plugin_arguments) } ;
			
			die ERROR("Plugin: error running $plugin_sub_name:\n$@") . "\n" if $@ ;
			
			return $result ;
			}
		}
	}
else
	{
	Say Warning "Plugin: couldn't find $plugin_sub_name, @ " . GetRunRelativePath($grrpc, $file_name) . ":$line" if $config->{DISPLAY_PLUGIN_RUNS} ;
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
