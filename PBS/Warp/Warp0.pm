
package PBS::Warp::Warp0 ;
use PBS::Debug ;

use strict ;
use warnings ;

use v5.10 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

use PBS::Output ;
use PBS::Log ;
use PBS::Digest ;
use PBS::Constants ;
use PBS::Plugin;
use PBS::Warp;

use Cwd ;
use File::Path;
use Data::Dumper ;
use Data::Compare ;
use Time::HiRes qw(gettimeofday tv_interval) ;

#-------------------------------------------------------------------------------

sub WarpPbs
{
my ($targets, $pbs_config, $parent_config) = @_ ;
	
my $warp_path = $pbs_config->{BUILD_DIRECTORY} . '/.warp0';
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = "${mday}_${mon}_${hour}_${min}_${sec}" ;
my $triggers_file = "$warp_path/Triggers_${now_string}.pl" ;

$pbs_config->{TRIGGERS_FILE} = $triggers_file ;
mkpath($warp_path) unless(-e $warp_path) ;

my ($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;
eval
	{
	local $PBS::Output::indentation_depth = -1 ;

	($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence)
		= PBS::PBS::Pbs
			(
			[$pbs_config->{PBSFILE}],
			'ROOT_WARP_0',
			$pbs_config->{PBSFILE},
			'',    # parent package
			$pbs_config,
			$parent_config,
			$targets,
			undef, # inserted files
			"root_NO_WARP_pbs_$pbs_config->{PBSFILE}", # tree name
			DEPEND_CHECK_AND_BUILD,
			) ;
	} ;

die $@ if $@ ;

return($build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;
}

#-----------------------------------------------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Warp::Warp0  -

=head1 DESCRIPTION

Run PBS without Warp.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

=cut
