
package PBS::Log ;
use PBS::Debug ;

use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

use Data::TreeDumper;
use Time::HiRes qw(gettimeofday tv_interval) ;
use File::MkTemp;
use File::Path;
use FileHandle;
use Cwd ;
use Term::ANSIColor qw(:constants) ;

use PBS::Log::Html ;
use PBS::Output ;
use PBS::PBSConfig ;


#-------------------------------------------------------------------------------


sub GetHeader
{
my $title = shift ;
my $pbs_config = shift ;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = "${mday}_${mon}_${hour}_${min}_${sec}" ;
my $pbs_lib_path = join(', ', @{$pbs_config->{LIB_PATH}}) ;

my $current_directory = cwd() ;
my $user = PBS::PBSConfig::GetUserName() ;
my $host = defined $ENV{HOSTNAME} ? $ENV{HOSTNAME} : '' ;

my $pbs_response_file = $pbs_config->{PBS_RESPONSE_FILE} || '' ;
my $pbs_response_file_switches = '' ;
if(exists $pbs_config->{PBS_RESPONSE_FILE_SWITCHES})
	{
	$pbs_response_file_switches =  join(' ', @{$pbs_config->{PBS_RESPONSE_FILE_SWITCHES}}) ;
	}

my $pbs_response_file_targets = '' ;
if(exists $pbs_config->{PBS_RESPONSE_FILE_TARGETS})
	{
	$pbs_response_file_targets = join(' ', @{$pbs_config->{PBS_RESPONSE_FILE_TARGETS}}) ;
	}

<<EOD ;
#
# $title generated by PBS (Perl Build System) on $now_string.
# Directory: $current_directory
# User: $user @ $host
# PBS_LIB_PATH: $pbs_lib_path
# Command line: pbs $pbs_config->{ORIGINAL_ARGV}
# PBS Response file: $pbs_response_file
# Response file switches: $pbs_response_file_switches
# Response file targets : $pbs_response_file_targets
#

EOD

}

#-------------------------------------------------------------------------------

sub CreatePbsLog
{
my $pbs_config = shift ;

my $log_path = $pbs_config->{BUILD_DIRECTORY} . '/_PBS_LOG/' ;

mkpath($log_path) unless(-e $log_path) ;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = "${mday}_${mon}_${hour}_${min}_${sec}" ;

$pbs_config->{LOG_NAME} = $log_path . mktemp("${now_string}_PBS_LOG_XXXXXXX", $log_path) ;

my $lh = new FileHandle "> $pbs_config->{LOG_NAME}" || die "Can't create log file! $@.\n" ;
$pbs_config->{LOG_FH} = $lh ;

PrintInfo("Log: file: '$pbs_config->{LOG_NAME}'.\n") unless $pbs_config->{QUIET} ;

print $lh GetHeader('Log', $pbs_config) ;
}

#-------------------------------------------------------------------------------

sub LogTreeData
{
my $pbs_config      = shift ;
my $dependency_tree = shift ;
my $inserted_nodes  = shift ;
my $build_sequence  = shift ;

if(defined (my $lh = $pbs_config->{LOG_FH}) && $pbs_config->{LOG_TREE})
	{
	PrintInfo("Log: generation ...") ;
	my $t0 = [gettimeofday];
	
	print $lh INFO "\n" ;
	
	# Build sequence.
	my $GetBuildNames = sub
				{
				my $tree = shift ;
				return ('HASH', undef, grep { /^(__NAME|__BUILD_NAME)/} keys %$tree) if('HASH' eq ref $tree) ;	
				return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
				} ;
			
	print $lh INFO( DumpTree
			(
			$build_sequence,
			"\nBuildSequence:",
			FILTER => $GetBuildNames,
			USE_ASCII => 1,
			)) ;
	
	# files in the dependency tree.
	
	print $lh "\n\n" ;
	
	my $number_of_nodes_in_the_dependency_tree = 0 ;
	my $node_counter_and_lister = sub 
				{
				my $tree = shift ;
				if('HASH' eq ref $tree && exists $tree->{__NAME})
					{
					if($tree->{__NAME} !~ /^__/)
						{
						$number_of_nodes_in_the_dependency_tree++ ;
						
						print $lh INFO $tree->{__NAME} ;
						print $lh INFO " => $tree->{__BUILD_NAME}" if exists $tree->{__BUILD_NAME} and $tree->{__BUILD_NAME} ne $tree->{__NAME} ;
						print $lh "\n" ;
						}
						
					return('HASH', $tree, grep {! /^__/} keys %$tree) ; # tweak to run faster
					}
				else
					{
					return('SCALAR', 1) ; # prune
					}
				} ;
			
	DumpTree($dependency_tree, '', NO_OUTPUT => 1, FILTER => $node_counter_and_lister) ;
		
	# Dependency tree.
	my $MarkNodesToRebuild = sub 
		{
		my $s = shift ;
		
		if('HASH' eq ref $s)
			{
			my @keys =  grep {! /^__/} keys %$s ;
			
			for my $node_name (@keys)
				{
				my $node = $s->{$node_name} ;
				
				unless(exists $node->{__TRIGGERED})
					{
					$node_name = [$node_name, "$node_name"] ;
					}
				else
					{
					$node_name = [$node_name, ERROR("* $node_name")] ;
					}
				}
			
			return('HASH', undef, @keys) ;
			}
		
		return(Data::TreeDumper::DefaultNodesToDisplay($s)) ;
		} ;
		
					
	print $lh "\n\nNumber of nodes in the dependency tree: $number_of_nodes_in_the_dependency_tree.\n" ;

	print $lh DumpTree
			(
			$dependency_tree,
			"\nDependency tree:",
			FILTER => $MarkNodesToRebuild,
			USE_ASCII => 1,
			) ;

	my $generation_time = tv_interval ($t0, [gettimeofday]) ;

	PrintInfo sprintf(" (%0.2f sec.)\n",$generation_time) ;
	}
}

#-------------------------------------------------------------------------------

sub GeneratePbsDump
{
my ($dependency_tree, $inserted_nodes, $pbs_config) = @_ ;

my $log_path = $pbs_config->{BUILD_DIRECTORY} . '/PBS_LOG/' ;
mkpath($log_path) unless(-e $log_path) ;

$pbs_config->{LOG_NAME} ||= $log_path . mktemp('PBS_LOG_XXXXXXX', $log_path) ;

my $file_name = $pbs_config->{LOG_NAME} . '.tree.pl' ;

PrintInfo("Generating tree dump (Code references are not valid!) in '$file_name'.\n") ;

open(DUMP, ">>", $file_name) or die qq[Can't open $file_name : $!] ;

$Data::Dumper::Purity = 1 ;

my $warned_about_code = 0 ;

local $SIG{'__WARN__'} = sub 
	{
	if($_[0] =~ 'Encountered CODE ref')
		{
		#~ unless($warned_about_code)
			#~ {
			#~ PrintWarning "Code references in the tree dump are not valid.\n" ;
			#~ $warned_about_code ++ ;
			#~ }
		}
	else
		{
		print STDERR $_[0] ;
		}
	} ;

print DUMP GetHeader('Tree dump', $pbs_config) ;
print DUMP Data::Dumper->Dump([$dependency_tree], ['dependency_tree']) ;
print DUMP "\n" ;
print DUMP Data::Dumper->Dump([$inserted_nodes], ['inserted_nodes']) ;
print DUMP "\n" ;

print DUMP <<'EOC' ;

my @trigger_inserted_roots ;

for my $node_name (keys %$inserted_nodes)
	{
	if(exists $inserted_nodes->{$node_name}{__TRIGGER_INSERTED})
		{
		push @trigger_inserted_roots, $inserted_nodes->{$node_name} ;
		}
	}
	
EOC

print DUMP <<EOC ;
use PBS::Graph ;
PBS::Graph::GenerateTreeGraphFile
	(
	[\$dependency_tree, \@trigger_inserted_roots], \$inserted_nodes,
	'' #title,
	{
		\%\$pbs_config,
		GENERATE_TREE_GRAPH => 1,
		GENERATE_TREE_GRAPH_DISPLAY_TRIGGERED_NODES => 1,
		GENERATE_TREE_GRAPH_GROUP_MODE => 0,
		GENERATE_TREE_GRAPH_SPACING => 1,
		GENERATE_TREE_GRAPH_DISPLAY_CONFIG => 0,
		GENERATE_TREE_GRAPH_DISPLAY_CONFIG_EDGE => 0,
		GENERATE_TREE_GRAPH_DISPLAY_PBS_CONFIG => 0,
		GENERATE_TREE_GRAPH_DISPLAY_CPBS_ONFIG_EDGE => 0,
		GENERATE_TREE_GRAPH_DISPLAY_BUILD_DIRECTORY => 0,
		GENERATE_TREE_GRAPH_CANONICAL => 0,
		GENERATE_TREE_GRAPH_POSTSCRIPT => 0,
		GENERATE_TREE_GRAPH_HTML => undef # 'html_directory_name',
		GENERATE_TREE_GRAPH_SNAPSHOTS => undef # 'snapshots_directory_name',
	},
	) ;

EOC

close(DUMP) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Log  -

=head1 DESCRIPTION

I<LogTreeData> prints information about the build to the file handle stored $pbs_config->{LOG_FH}. it is
used in conjuction with I<PBS::Information::DisplayNodeInformation> to create a the B<PBS> log file.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS::Information>.

=cut
