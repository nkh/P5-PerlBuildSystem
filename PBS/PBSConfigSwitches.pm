
package PBS::PBSConfigSwitches ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw(GetOptionsElements RegistredFlagsAndHelp) ;

our $VERSION = '0.06' ;

use Carp ;
use List::Util qw(max any);
use Sort::Naturally ;
use File::Slurp ;

use PBS::Constants ;
use PBS::Options::Complete ;
use PBS::Output ;
use PBS::Config::Options ;

#-------------------------------------------------------------------------------

my %registred_flags ;          # plugins won't override flags
my @registred_flags_and_help ; # allow plugins to register their switches

RegisterDefaultPbsFlags() ; # reserve them so plugins can't modify their meaning

#-------------------------------------------------------------------------------

sub GetOptions
{
my $config = shift // {} ;

my @options = 
	(
	PBS::Config::Options::HelpOptions        ($config),
	PBS::Config::Options::WarpOptions        ($config),
	PBS::Config::Options::DigestOptions      ($config),
	PBS::Config::Options::EnvOptions         ($config),
	PBS::Config::Options::PbsSetupOptions    ($config),
	PBS::Config::Options::PluginOptions      ($config),
	PBS::Config::Options::ConfigOptions      ($config),
	PBS::Config::Options::DependOptions      ($config),
	PBS::Config::Options::TriggerOptions     ($config),
	PBS::Config::Options::RulesOptions       ($config),
	PBS::Config::Options::ParallelOptions    ($config),
	PBS::Config::Options::CheckOptions       ($config),
	PBS::Config::Options::PostBuildOptions   ($config),
	PBS::Config::Options::MatchOptions       ($config),
	PBS::Config::Options::HttpOptions        ($config),
	PBS::Config::Options::NodeOptions        ($config),
	PBS::Config::Options::TriggerNodeOptions ($config),
	PBS::Config::Options::OutputOptions      ($config),
	PBS::Config::Options::StatsOptions       ($config),
	PBS::Config::Options::TreeOptions        ($config),
	PBS::Config::Options::GraphOptions       ($config),
	PBS::Config::Options::DebugOptions       ($config),
	PBS::Config::Options::DevelOptions       ($config),
	) ;

$config->{DO_BUILD}                                = 1 ;
$config->{SHORT_DEPENDENCY_PATH_STRING}            = '…' ;
$config->{PBS_QR_OPTIONS}                        //= [] ;

my @rfh = @registred_flags_and_help ;

while( my ($switch, $help1, $help2, $variable) = splice(@rfh, 0, 4))
    {
    if('' eq ref $variable)
        {
        if($variable =~ s/^@//)
            {
            $variable = $config->{$variable} = [] ;
            }
        else
            {
            $variable = \$config->{$variable} ;
            }
        }

    push @options, $switch, $help1, $help2, $variable ;
    }

\@options, $config ;
}

#-------------------------------------------------------------------------------

my $message_displayed = 0 ; # called twice but want a single message

sub LoadConfig
{
my ($switch, $file_name, $pbs_config) = @_ ;

$pbs_config->{LOAD_CONFIG} = $file_name ;

$file_name = "./$file_name" if( $file_name !~ /^\\/ && -e $file_name) ;

my ($loaded_pbs_config, $loaded_config) = do $file_name ;

if(! defined $loaded_config || ! defined $loaded_pbs_config)
	{
	die ERROR("Config: error loading file'$file_name'") . "\n" ;
	}
else
	{
	Say Info "Config: loading '$file_name'" unless $message_displayed ;
	$message_displayed++ ;

	$pbs_config->{LOADED_CONFIG} = $loaded_config ;
	}
}

#-------------------------------------------------------------------------------

sub DisplayHelp { _DisplayHelp($_[0], 0, GetOptionsElements()) }                    

sub DisplaySwitchesHelp
{
my ($switches, $options) = @_ ;

my @matches ;

OPTION:
for my $option (sort { $a->[0] cmp $b->[0] } $options->@*)
	{
	for my $option_element (split /\|/, $option->[0])
		{
		$option_element =~ s/=.*$// ;
		
		if( any { $_ eq $option_element} $switches->@* )
			{
			push @matches, $option ;
			next OPTION ;
			}
		}
	}

_DisplayHelp(0, @matches <= 1, @matches) ;
}

#-------------------------------------------------------------------------------

sub GetOptionsElements
{
my ($options, undef, @t) = GetOptions() ;

push @t, [splice @$options, 0, 4 ] while @$options ;

@t 
}

sub _DisplayHelp
{
my ($narrow_display, $display_long_help, @matches) = @_ ;

my (@short, @long, @options) ;

my $has_long_help ;

return unless @matches ;

for (@matches)
	{
	my ($option_type, $help, $long_help) = @{$_}[0..2] ;
	
	$help //= '' ;
	$long_help //= '' ;
	
	my ($option, $type) = $option_type  =~ m/^([^=]+)(=.*)?$/ ;
	$type //= '' ;
		
	my ($long, $short) =  split(/\|/, ($option =~ s/=.*$//r), 2) ;
	$short //= '' ;
	
	push @short, length($short) ;
	push @long , length($long) ;
	
	$has_long_help++ if length($long_help) ;
	
	push @options, [$long, $short, $type, $help, $long_help] ; 
	}

my $max_short = $narrow_display ? 0 : max(@short) + 2 ;
my $max_long  = $narrow_display ? 0 : max(@long);

for (@options)
	{
	my ($long, $short, $type, $help, $long_help) = @{$_} ;

	my $lht = $has_long_help 
			? $long_help eq ''
				? ' '
				: '*'
			: '' ;

	Say EC sprintf("<I3>--%-${max_long}s <W3>%-${max_short}s<I3>%-2s%1s: ", $long, ($short eq '' ? '' : "--$short"), $type, $lht)
			. ($narrow_display ? "\n" : '')
			. "<I>$help" ;

	Say Info $long_help if $display_long_help && $long_help ne '' ;
	}
}

#-------------------------------------------------------------------------------

sub DisplayUserHelp
{
my ($Pbsfile, $display_pbs_pod, $raw) = @_ ;

eval "use Pod::Select ; use Pod::Text;" ;
die $@ if $@ ;

if(defined $Pbsfile && $Pbsfile ne '')
	{
	open INPUT, '<', $Pbsfile or die "Can't open '$Pbsfile'!\n" ;
	open my $out, '>', \my $all_pod or die "Can't redirect to scalar output: $!\n";
	
	my $parser = new Pod::Select();
	$parser->parse_from_filehandle(\*INPUT, $out);
	
	$all_pod .= '=cut' ; #add the =cut taken away by above parsing
	
	my ($pbs_pod, $other_pod) = ('', '') ;
	my $pbs_pod_level = 1_000_000 ;  #invalid level
	
	while($all_pod =~ /(^=.*?(?=\n=))/smg)
		{
		my $section = $1 ;
		
		my $section_level = $1 if($section =~ /=head([0-9])/) ;
		$section_level ||= 1_000_000 ;
		
		if($section =~ s/^=for PBS STOP\s*//i)
			{
			$pbs_pod_level = 1_000_000 ;
			next ;
			}
				
		if(($pbs_pod_level && $pbs_pod_level < $section_level) || $section =~ /^=for PBS/i)
			{
			$pbs_pod_level = $section_level < $pbs_pod_level ? $section_level : $pbs_pod_level ;
			
			$section =~ s/^=for PBS\s*//i ;
			$pbs_pod .= $section . "\n" ;
			}
		else
			{
			$pbs_pod_level = 1_000_000 ;
			$other_pod .= $section . "\n" ;
			}
		}
		
	my $pod = $display_pbs_pod ? $pbs_pod : $other_pod ;
	
	if($raw)
		{
		print $pod ;
		}
	else
		{
		my $pod_output = '' ;
		open my $input, '<', \$pod or die "Can't redirect from scalar input: $!\n";
		open my $output, '>', \$pod_output  or die "Can't redirect from scalar input: $!\n";
		Pod::Text->new (alt => 1, sentence => 1, width => 78)->parse_from_file ($input, $output) ;

		Print Debug $pod_output ;
		}
	}
else
	{
	print(ERROR("No Pbsfile to extract user information from. For PBS modules, use a pod converter (ie 'pod2html').\n")) ;	
	}
}

#-------------------------------------------------------------------------------

sub GetOptionsList
{
my ($options) = GetOptions() ;

my (@slice, @switches) ;
push @switches, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 

print join( "\n", map { ("-" . $_) } @{ (Term::Bash::Completion::Generator::de_getop_ify_list(\@switches))[0]} ) . "\n" ;
}

#-------------------------------------------------------------------------------

sub GetCompletion
{
my (undef, $command_name, $word_to_complete, $previous_word) = @ARGV ;

my ($pbs_config, $options) = @_ ;

print &PBS::Options::Complete::Complete
	(
	$word_to_complete,
	$previous_word,
	[GetOptionsElements()],
	'pbs_option_aliases',
	\&DisplaySwitchesHelp,
	$pbs_config->{GUIDE_PATH},
	) ;
}

#-------------------------------------------------------------------------------

sub RegisterFlagsAndHelp 
{
my (@options) = @_ ;

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ; $file_name =~ s/'$// ;

my $success = 1 ;

while( my ($switch, $help1, $help2, $variable) = splice(@options, 0, 4))
	{
	for my $switch_unit ( split('\|', ($switch =~ s/(=|:).*$//r)) )
		{
		if(! exists $registred_flags{$switch_unit})
			{
			$registred_flags{$switch_unit} = "$file_name:$line" ;
			}
		else
			{
			$success = 0 ;
			Say Warning "In Plugin '$file_name:$line', switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'. Ignoring." ;
			}
		}
		
	push @registred_flags_and_help, $switch, $help1, $help2, $variable 
		if $success ;
	}

$success ;
}

#-------------------------------------------------------------------------------

sub RegisterDefaultPbsFlags
{
my ($options) = GetOptions() ;

while(my ($switch) = splice(@$options, 0, 4))
	{
	for my $switch_unit ( split('\|', ($switch =~ s/(=|:).*$//r)) )
		{
		if(! exists $registred_flags{$switch_unit})
			{
			$registred_flags{$switch_unit} = "PBS reserved switch " . __PACKAGE__ ;
			}
		else
			{
			die ERROR "Switch '$switch_unit' already registered @ '$registred_flags{$switch_unit}'.\n" ;
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub Get_GetoptLong_Data
{
my ($options, @t) = @_  ;

my @c = @$options ; # don't splice caller's data

push @t, [ splice @c, 0, 4 ] while @c ;

map { $_->[0], $_->[3] } @t
}


#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::PBSConfigSwitches  -

=head1 DESCRIPTION

I<GetOptions> returns a data structure containing the switches B<PBS> uses and some documentation. That
data structure is processed by I<Get_GetoptLong_Data> to produce a data structure suitable for use I<Getopt::Long::GetoptLong>.

I<DisplayUserHelp> and I<DisplayHelp> also use that structure to display help.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
