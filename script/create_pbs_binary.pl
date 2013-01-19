#!/usr/bin/perl -w

use strict ;
use warnings ;

my $pbs = `which pbs` ;
chomp $pbs ;

my $pbs_lib_path = `pbs --display_pbs_lib_path` ;
my $pbs_plugins_path = `pbs --display_pbs_plugin_path` ;

my @extra_modules = 
	qw(
	PBS::Watch::Client PBS::Prf PBS::Warp::Warp0 PBS::Warp::Warp1_5 PBS::Warp::Warp1_7 PBS::Warp::Warp1_8 PBS::ProgressBar
	Devel::Depend::Cl 
	Devel::Depend::Cpp 
	Pod::Simple::HTMLBatch 
	Devel::Size 
	File::Slurp 
	) ;

my $extra_modules = '-M ' . join(' -M ', @extra_modules) ;

#~ my $command = "pp -P -d -c -o ./tmp/pbs $pbs -a '$pbs_lib_path/;/PBSLIB/' -a '$pbs_plugins_path/;/PBSPLUGIN/' $extra_modules" ;
my $command = "pp -o ./pbs_binary/pbs $pbs -a '$pbs_lib_path/;/PBSLIB/' -a '$pbs_plugins_path/;/PBSPLUGIN/' $extra_modules" ;
print "Running command: '$command'\n\n" ;
`$command` ;

