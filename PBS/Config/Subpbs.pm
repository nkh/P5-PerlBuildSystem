
package PBS::Config::Subpbs ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

use Data::Compare;

use PBS::Config ;
use PBS::PBSConfig ;

sub RemoveSubpbsOptions
{
# remove subppbs_options from the command line

my ($command_line_arguments) = @_ ;

my @unchecked_subpbs_options ;
my @new_argv ;
my @options ;
my $in_options = 0;
my $options_qr ;
my $local_option = 1 ;

for my $arg (@$command_line_arguments)
	{
	if ($arg =~ /^--?pbs_options_end$/)
		{
		push @unchecked_subpbs_options, {QR => $options_qr, OPTIONS => [@options], LOCAL => $local_option} if $in_options > 2 ;
		@options = () ;
		$in_options = 0 ;
		}
	elsif ($arg =~ /^--?pbs_options(_local)?$/)
		{
		push @unchecked_subpbs_options, {QR => $options_qr, OPTIONS => [@options], LOCAL => $local_option} if $in_options > 2 ;

		@options = () ;
		$in_options = 1 ;
		$local_option = defined $1 ;
		}
	elsif ($in_options)
		{
		$options_qr = $arg if $in_options == 1 ;
		push @options, $arg if $in_options > 1;

		$in_options++
		}
	else
		{
		push @new_argv, $arg ;
		}
	}

push @unchecked_subpbs_options, {QR => $options_qr, OPTIONS => [@options], LOCAL => $local_option } if $in_options > 2 ;

\@unchecked_subpbs_options, \@new_argv
}

sub ParseSubpbsOptions
{
my ($unchecked_subpbs_options, $new_argv, $ignore_error) = @_ ;

my ($subpbs_switch_parse_ok, $subpbs_parse_message) = (1, '') ;
my @subpbs_options ;

my ($options, $config_no_options) = PBS::PBSConfigSwitches::GetOptions() ;

my $package = 'SUPBS_NO_OPTIONS' ;
PBS::PBSConfig::RegisterPbsConfig($package, $config_no_options) ;
$config_no_options->{PBSFILE} = $package ;
use PBS::Output ;

my ($switch_parse_ok_no_options, $parse_message_no_options) = PBS::PBSConfig::ParseSwitches($options, $config_no_options, $new_argv, $ignore_error) ;
PBS::PBSConfig::CheckPbsConfig($config_no_options) ;

return 0, $parse_message_no_options, \@subpbs_options unless $switch_parse_ok_no_options ;

my $counter = 0 ;

for my $subpbs_option (@$unchecked_subpbs_options)
	{
	$counter++ ;
	
	my ($options, $config) = PBS::PBSConfigSwitches::GetOptions() ;
	
	my $package = "SUBPBS_OPTIONS_$counter" ;
	PBS::PBSConfig::RegisterPbsConfig($package, $config) ;
	$config->{PBSFILE} = $package ;
	
	my ($switch_parse_ok, $parse_message) = PBS::PBSConfig::ParseSwitches($options, $config, [@$new_argv, @{$subpbs_option->{OPTIONS}}]) ;
	PBS::PBSConfig::CheckPbsConfig($config) ;
	
	unless ($switch_parse_ok)
		{
		$subpbs_switch_parse_ok = 0 ;
		$subpbs_parse_message = $parse_message ;
		last ;
		}
	
	delete $config->{NO_BUILD} ;
	delete $config->{DO_BUILD} ;
	delete $config->{TARGETS} ;
	
	# keep added or modified options
	for my $config_key (keys %$config)
		{
		delete $config->{$config_key} if Compare($config->{$config_key}, $config_no_options->{$config_key}) ;
		}
	
	push @subpbs_options, {QR => $subpbs_option->{QR}, OPTIONS => $config, LOCAL => $subpbs_option->{LOCAL}} ;
	}

$subpbs_switch_parse_ok, $subpbs_parse_message,  \@subpbs_options ;
}

