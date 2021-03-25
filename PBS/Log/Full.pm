
package PBS::Log::Full ;

use v5.10 ;
use strict ;
use warnings ;

use File::Slurp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateDependFullLog) ;
our $VERSION = '0.01' ;

use PBS::Config ;
use PBS::PBSConfig ;
use PBS::Output ;

sub GenerateDependFullLog
{
my ($pbs_config, $command_line_arguments) = @_ ;

return if $pbs_config->{IN_DFL} ;

my $pbs_config_extra_options = {} ;

$pbs_config_extra_options->{$_}++
	for( qw(
		DEBUG_DISPLAY_DEPENDENCIES 
		DEBUG_DISPLAY_DEPENDENCIES_LONG 
		DISPLAY_DEPENDENCY_MATCHING_RULE 
		DISPLAY_DEPENDENCY_INSERTION_RULE 
		DISPLAY_LINK_MATCHING_RULE
		IN_DFL 
		)) ;

my @full_log_options ;
my $options_file ;
if($pbs_config->{DEPEND_FULL_LOG_OPTIONS})
	{
	$options_file = $pbs_config->{DEPEND_FULL_LOG_OPTIONS} unless $pbs_config->{DEPEND_FULL_LOG_OPTIONS} eq {} ;
	}
elsif( -e 'depend_full_log_options')
	{
	$options_file = 'depend_full_log_options' ;
	}

if(defined $options_file)
	{
	unless (-e $options_file)
		{
		PrintWarning "Depend: not generating full depend log, option file '$options_file' not found.\n" ;
		return ;
		}

	for my $line (read_file $options_file)
		{
		next if $line =~ /^\s*#/ ;
		next if $line =~ /^$/ ;

		my ($option, $argument) = split /\s+/, $line, 2 ;

		push @full_log_options, $option ;
		if (defined $argument && $argument ne q{})
			{
			$argument =~ s/\s+$// ;
			
			push @full_log_options, $argument ;
			}
		}
	my ($options, $config) = PBS::PBSConfigSwitches::GetOptions() ;
	my ($switch_parse_ok, $parse_message) = PBS::PBSConfig::ParseSwitches($options, $config, \@full_log_options) ;

	unless ($switch_parse_ok)
		{
		PrintWarning "Depend: not generating full depend log, option file: '$options_file'\n" ;

		return ;
		}

	#PrintDebug DumpTree \@full_log_options, 'full log options:' ;
	}

#PrintInfo "Depend: creating depend full log.\n" ;

my $pid = fork() ;
if($pid)
	{
	}
else
	{
	# new process if $pid defined
	
	# couldn't fork
	return unless(defined $pid) ;
		
	open STDOUT,  ">/dev/null"  or die "Can't redirect STDOUT to dev/null: $!" ;
	STDOUT->autoflush(1) ;

	open STDERR, '>>&STDOUT' or die "Can't redirect STDERR: $!";

	PBS::FrontEnd::Pbs
		(
		COMMAND_LINE_ARGUMENTS => 
			[
			'--depend_log', '--no_indentation', '--no_build',
			(grep { ! /^--?dfl|depend_full_log$/ } @{$command_line_arguments}),
			@full_log_options
			],

		 PBS_CONFIG => $pbs_config_extra_options
		) ;

	exit 0 ;
	} ;
}

