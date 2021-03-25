
package PBS::Warp ;
use PBS::Debug ;

use strict ;
use warnings ;

use v5.10 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.02' ;

#-------------------------------------------------------------------------------

use PBS::Output ;

use Cwd ;
use Data::Dump qw/ dump / ;
use Data::TreeDumper ;
use Digest::MD5 qw(md5_hex) ;

#-------------------------------------------------------------------------------

sub WarpPbs
{
my ($targets, $pbs_config, $parent_config) = @_ ;

my $warp_module = $pbs_config->{WARP} ;
$warp_module =~ s/[^0-9a-zA-Z]/_/g ;
$warp_module = "PBS::Warp::Warp" . $warp_module ;

my @warp_results ;

eval <<EOE ;

use $warp_module ;
\@warp_results = ${warp_module}::WarpPbs(\$targets, \$pbs_config, \$parent_config) ;

EOE

die $@ if $@ ;
return(@warp_results) ;
}

#-------------------------------------------------------------------------------

sub GetWarpSignature
{
my ($targets, $pbs_config) = @_ ;

#construct a file name depends on targets and -D and -u switches, etc ...
my $pbs_prf = $pbs_config->{PBS_RESPONSE_FILE} || '' ;
my $pbs_lib_path = $pbs_config->{LIB_PATH} || '' ;

my $warp_signature_source =
		(
		  join('_', @$targets) 
		
		. $pbs_config->{PBSFILE}
		
		. dump($pbs_config->{COMMAND_LINE_DEFINITIONS})
		. dump($pbs_config->{USER_OPTIONS}) 
		
		. $pbs_prf
		. dump($pbs_lib_path)
		) ;

my $warp_signature = md5_hex($warp_signature_source) ;

return($warp_signature, $warp_signature_source) ;
}

#--------------------------------------------------------------------------------------------------

sub GetWarpConfiguration
{
my $pbs_config = shift ;
my $warp_configuration = {} ;

my $pbs_prf = $pbs_config->{PBS_RESPONSE_FILE} ;

if(defined $pbs_prf)
	{
	my $pbs_prf_md5 = PBS::Digest::GetFileMD5($pbs_prf) ; 
	
	if(defined $pbs_prf_md5)
		{
		$warp_configuration->{$pbs_prf} = $pbs_prf_md5 ;
		}
	else
		{
		PrintError("Warp file generation aborted: Can't compute MD5 for prf file '$pbs_prf'!") ;
		return ;
		}
	}

return($warp_configuration) ;
}

#--------------------------------------------------------------------------------------------------

sub GenerateWarpInfoFile
{
my ($warp_type, $warp_path, $warp_signature, $targets, $pbs_config) = @_ ;

(my $original_arguments = $pbs_config->{ORIGINAL_ARGV}) =~ s/[^0-9a-zA-Z_-]/_/g ;
my $warp_info_file= "$warp_path/pbsfile_${warp_signature}_${original_arguments}" ;

# limit length
if(length($warp_info_file) > 240)
	{
	$warp_info_file = substr $warp_info_file, 0, 239 ;
	$warp_info_file .= '_continued' ;
	}

open(WARP_INFO, ">", $warp_info_file) or die qq[Can't open $warp_info_file: $!] ;

my $header = PBS::Log::GetHeader('Warp information', $pbs_config) ;
my $target_text = join ' ', @{$targets} ;
my $pbs_config_text = DumpTree $pbs_config, 'pbs_config:', USE_ASCII => 1 ;

print WARP_INFO <<EOWI ;

$header 
warp_type: $warp_type
warp_path: $warp_path
warp signature: $warp_signature

targets: $target_text


$pbs_config_text

EOWI

close(WARP_INFO) ;
}

#-------------------------------------------------------------------------------

1;

__END__
=head1 NAME

PBS::Warp  -

=head1 DESCRIPTION

front end to the warp system. Defines base warp functionality.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
