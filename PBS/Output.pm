package PBS::Output ;

use 5.006 ;
use strict ;
use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.03' ;

BEGIN
{
	if ($^O eq 'MSWin32')
	{
		eval "use Win32::Console::ANSI;";
	}
};

use vars qw($VERSION @ISA @EXPORT) ;

require Exporter;

@ISA     = qw(Exporter) ;
@EXPORT  = qw
		(
		Error Warning Warning2 Warning3 Warning4 Info Info2 Info3 Info4 Info5 User Shell Debug
		ERROR WARNING WARNING2 WARNING3 WARNING4 INFO INFO2 INFO3 INFO4 INFO5 USER SHELL DEBUG
		_ERROR_ _WARNING_ _WARNING2_ _WARNING3_ _WARNING4_ _INFO_ _INFO2_ _INFO3_ _INFO4_ _INFO5_ _USER_ _SHELL_ _DEBUG_

		COLOR PrintColor PrintNoColor PrintVerbatim

		PrintError PrintWarning PrintWarning2 PrintWarning3 PrintWarning4 PrintInfo PrintInfo2 PrintInfo3 PrintInfo4 PrintInfo5 PrintUser PrintShell PrintDebug
		
		SDT Say Print

		GetLineWithContext PrintWithContext PbsDisplayErrorWithContext
		GetColor

		GetRunRelativePath GetTargetRelativePath
		) ;
		
$VERSION = '0.06' ;

use subs qw/ Error Warning Warning2 Warning3 Warning4 Info Info2 Info3 Info4 Info5 User Shell Debug / ;

#-------------------------------------------------------------------------------

use Term::ANSIColor qw(:constants) ;
$Term::ANSIColor::AUTORESET = 1 ;

use Term::Size::Any qw(chars) ;

use File::Slurp ;

#-------------------------------------------------------------------------------


our $output_info_label = '' ;
sub InfoLabel
{
$output_info_label = $_[1] ;
}

#-------------------------------------------------------------------------------

our $indentation = '    ' ;
our $indentation_depth = 0 ;
our $display_error_context  = 0 ;
our $no_indentation = 0 ;

my $cd = 256 ; # color_depth
my %cc ;

#-------------------------------------------------------------------------------

sub GetScreenWidth { (chars() // 10_000) - ( length($indentation x ($indentation_depth + 3)) + length($output_info_label)) }

#-------------------------------------------------------------------------------

sub SetDefaultColors
{
my ($default_colors) = @_ ;
$default_colors //= {} ;

for my $depth (keys %$default_colors)
	{
	$cc{$depth} = { %{$default_colors->{$depth} // {}}, %{$cc{$depth} // {}} } ;
	}
}

sub GetColor
{
$cc{$cd}{$_[0]} // '' ; 
}

#-------------------------------------------------------------------------------

sub SetOutputColorDepth { $cd = $_[1] }

sub SetOutputColor
{
return if $cd == 2 ;

my ($color_name, $color) = split(':', $_[1]) ;

my $escape_code = '' ;

eval {$escape_code = Term::ANSIColor::color($color) ;} ;

if($@)
	{
	print STDERR "PBS config: invalid color definition '$color_name: $color'.\n" ;
	}
else
	{
	$cc{$cd}{$color_name} = $escape_code ; 
	}
}

#-------------------------------------------------------------------------------

sub COLOR
{
#use Carp ;
#print Carp::longmess() ;

my ($color_name, $string, $indent, $no_indent_color, $continuation_color) = @_ ;

$string //= 'undef' ;
$indent //= 1 ;
$no_indent_color //= 0 ; 
#print STDERR " ($color_name, $string, $indent, $no_indent_color) \n" ;

my $depth  = $PBS::Output::indentation_depth ; $depth = 0 if $depth < 0 ;
my $indentation = $indent && ! $PBS::Output::no_indentation ? ($PBS::Output::indentation x $depth) : '' ;

my $color = $cc{$cd}{$color_name} // '' ;
my $reset = defined $continuation_color ? $cc{$cd}{$continuation_color} // '' : $cc{$cd}{reset} // '' ;

my $string_indent = $PBS::Output::indentation ne q{} && $string =~ s/^($PBS::Output::indentation+)// ? $1 : '' ; # works for first line only

$indentation = $no_indent_color ? $indentation . $string_indent . $color : $color . $indentation . $string_indent ;
my $indentation2 = $no_indent_color ? $indentation . $color : $color . $indentation ;

$string =~ s/\n(.)/\n$indentation2$1/g ;

return $indentation . $color . $string . $reset ;
}

sub ERROR    { return COLOR('error', @_) }        sub _ERROR_    { return COLOR('error', @_, 0) }
sub WARNING  { return COLOR('warning', @_) }      sub _WARNING_  { return COLOR('warning', @_, 0) }
sub WARNING2 { return COLOR('warning_2', @_) }    sub _WARNING2_ { return COLOR('warning_2', @_, 0) }
sub WARNING3 { return COLOR('warning_3', @_) }    sub _WARNING3_ { return COLOR('warning_3', @_, 0) }
sub WARNING4 { return COLOR('warning_4', @_) }    sub _WARNING4_ { return COLOR('warning_4', @_, 0) }
sub INFO     { return COLOR('info', @_) }         sub _INFO_     { return COLOR('info', @_, 0) }
sub INFO2    { return COLOR('info_2', @_) }       sub _INFO2_    { return COLOR('info_2', @_, 0) }
sub INFO3    { return COLOR('info_3', @_) }       sub _INFO3_    { return COLOR('info_3', @_, 0) }
sub INFO4    { return COLOR('info_4', @_) }       sub _INFO4_    { return COLOR('info_4', @_, 0) }
sub INFO5    { return COLOR('info_5', @_) }       sub _INFO5_    { return COLOR('info_5', @_, 0) }
sub USER     { return COLOR('user', @_) }         sub _USER_     { return COLOR('user', @_, 0) }
sub SHELL    { return COLOR('shell', @_) }        sub _SHELL_    { return COLOR('shell', @_, 0) }
sub DEBUG    { return COLOR('debug', @_) }        sub _DEBUG_    { return COLOR('debug', @_, 0) }

sub NO_COLOR{ return COLOR('reset', @_) }

*Error=\&ERROR ;
*Warning=\&WARNING ;
*Warning2=\&WARNING2 ;
*Warning3=\&WARNING3 ;
*Warning4=\&WARNING4 ;
*Info=\&INFO ;
*Info2=\&INFO2 ;
*Info3=\&INFO3 ;
*Info4=\&INFO4 ;
*Info5=\&INFO5 ;
*User=\&USER ;
*Shell=\&SHELL ;
*Debug=\&DEBUG ;

#-------------------------------------------------------------------------------

sub _print
{
#use Carp qw(cluck longmess shortmess);
#cluck "This is how we got here!"; 

my ($glob, $color_and_depth, $data, $indent, $color_indent) = @_ ;

return unless defined $data ;

$data =~ s/\t/$indentation/gm ;

my $reset = $cc{$cd}{reset} // '' ;
my ($ends_with_newline) = $data =~ /(\n+(?:\Q$reset\E)?)$/ ;
$ends_with_newline //= '' ;

my $lines =  join
		(
		"\n$output_info_label",
		map { $_ ne "\e[K\e[K" ? $color_and_depth->($_, $indent, $color_indent) : q{} }
			split /\n(?:\Q$reset\E)?/, $data
		)
		. $ends_with_newline ;

print $glob "$output_info_label$lines" ;
}

sub PrintStdOut {_print(\*STDOUT, \&NO_COLOR, @_)}
sub PrintStdErr {_print(\*STDERR, \&NO_COLOR, @_)}

sub PrintStdOutColor {_print(\*STDOUT, @_)} # pass a color handler as first argument
sub PrintStdErrColor {_print(\*STDERR, @_)} # pass a color handler as first argument

sub PrintNoColor  {_print(\*STDERR, \&NO_COLOR, @_)}
sub PrintVerbatim {print STDERR  @_} # used to print build process output which already has used _print 
sub PrintColor    {my $color = shift; _print(\*STDERR, sub {COLOR($color, @_)}, @_)}

sub PrintError   {_print(\*STDERR, \&ERROR, @_)}
sub PrintWarning {_print(\*STDERR, \&WARNING, @_)}
sub PrintWarning2{_print(\*STDERR, \&WARNING2, @_)}
sub PrintWarning3{_print(\*STDERR, \&WARNING3, @_)}
sub PrintWarning4{_print(\*STDERR, \&WARNING4, @_)}
sub PrintInfo    {_print(\*STDERR, \&INFO, @_ )}
sub PrintInfo2   {_print(\*STDERR, \&INFO2, @_)}
sub PrintInfo3   {_print(\*STDERR, \&INFO3, @_)}
sub PrintInfo4   {_print(\*STDERR, \&INFO4, @_)}
sub PrintInfo5   {_print(\*STDERR, \&INFO5, @_)}
sub PrintUser    {_print(\*STDERR, \&USER, @_)}
sub PrintShell   {_print(\*STDERR, \&SHELL, @_)}
sub PrintDebug   {_print(\*STDERR, \&DEBUG, @_)}

sub Print      {_print(\*STDERR, \&NO_COLOR, @_)}
sub Say        {_print(\*STDERR, \&NO_COLOR, (shift . "\n"), @_)}

sub SDT 
{
my ($p, $f, $l) = caller (0) ;
$f = GetRunRelativePath({TARGET_PATH => '', SHORT_DEPENDENCY_PATH_STRING => '…'}, $f) ;

eval
	{
	if (@_ == 0) {}
	if (@_ == 1) { PrintDebug Data::TreeDumper::DumpTree(@_, '', DUMPER_NAME => "SDT $f:$l") }
	    else     { PrintDebug Data::TreeDumper::DumpTree(@_, DUMPER_NAME => "SDT $f:$l") }
	} ;

Say Error "SDT: error: Odd number of arguments @ $f:$l" if $@ ;
}

#-------------------------------------------------------------------------------

sub GetLineWithContext
{
my ($pbs_config) = @_ ;

if($pbs_config->{PBSFILE_CONTENT})
	{
	my @pbsfile_contents = map {" $_\n" } split(/\n/, $pbs_config->{PBSFILE_CONTENT}) ;

	$_[1] = "Virtual pbsfile: $pbs_config->{VIRTUAL_PBSFILE_NAME}" ;

	GetLineWithContextFromList(\@pbsfile_contents, @_) ;
	}
else
	{
	my (undef, $file_name) = @_ ;

	$_[1] = "file: $file_name" ; # change title

	if (-e $file_name)
		{
		GetLineWithContextFromList([read_file($file_name)], @_) ;
		}
	else
		{
		die ERROR("PBS: file not found '$file_name") . "\n" ;
		}
	}
}

#-------------------------------------------------------------------------------

sub GetLineWithContextFromList
{
my 
	(
	$list,
	$pbs_config,
	$title,
	$blank_lines, $context_lines_before, $context_lines_after,
	$center_line_index, $number_of_center_lines,
	$center_line_colorizing_sub, $context_colorizing_sub,
	$indent_title, $indent,
	$no_title,
	$shorten_title,
	$title_colorizing_sub
	) = @_ ;

$number_of_center_lines //= 1 ;
$center_line_colorizing_sub //= sub{ COLOR('reset', @_) } ;
$context_colorizing_sub     //= sub{ COLOR('reset', @_) } ;
$indent_title //='' ;
$indent //='' ;
$title_colorizing_sub   //= \&INFO2 ;

my $line_number = 0 ;
my $number_of_lines_skip = ($center_line_index - $context_lines_before) - 1 ;

my $top_context = $context_lines_before ;
$top_context += $number_of_lines_skip if $number_of_lines_skip < 0 ;

my $line_with_context = '' ;

$line_with_context.= "\n" x $blank_lines ;

do { shift @$list ; $line_number++ } for (1 .. $number_of_lines_skip) ;

my $t = $PBS::Output::indentation;

my $title_indent = $indent_title ? $t : '' ;
my $short_title = $shorten_title ? GetRunRelativePath($pbs_config, $title) : $title ;
$line_with_context .= $title_colorizing_sub->("$title_indent$indent$short_title\n", 0) unless $no_title ;

for(1 .. $top_context)
	{
	my $text = shift @$list ; $line_number++ ;

	next unless defined $text ;

	$line_with_context .=  $context_colorizing_sub->("$t$indent$line_number $text", 0) ;
	}
		

unless($pbs_config->{DISPLAY_NO_PERL_CONTEXT})
	{
	use PPR ;

	my $source_code = join '', @$list ;

	if ($source_code =~ m{\s*((?&PerlTerm)) $PPR::GRAMMAR }x)
		{
		my $term = "$1\n" ;
		$number_of_center_lines = $term =~ tr[\n][\n] ;

		$number_of_center_lines = 1 if $number_of_center_lines < 1 ; 
		$number_of_center_lines = 25 if $number_of_center_lines > 25 ; 
		}
	}


for(1 .. $number_of_center_lines)
	{
	my $center_line_text = shift @$list ; $line_number++ ;
	$line_with_context .= $center_line_colorizing_sub->("$t$indent$line_number $center_line_text", 0) if defined $center_line_text ;
	} ;

for(1 .. $context_lines_after)
	{
	my $text = shift @$list ; $line_number++ ;

	next unless defined $text ;
	
	$line_with_context .= $context_colorizing_sub->("$t$indent$line_number $text", 0) ;
	}

$line_with_context .= "\n" x ($blank_lines + 1) ;

return($line_with_context) ;
}

#-------------------------------------------------------------------------------

sub PrintWithContext
{
_print(\*STDERR, \&ERROR, GetLineWithContext(@_)) ;
}

#-------------------------------------------------------------------------------

sub PbsDisplayErrorWithContext
{
my ($pbs_config, $file, $line) = @_ ;

PrintWithContext
	(
	$pbs_config,
	$file,
	1, 1, 3, # $blank_lines, $context_lines_before, $context_lines_after,
	$line, 1, # $center_line_index, $number_of_center_lines,
	\&ERROR, \&INFO2, #$center_line_colorizing_sub, $context_colorizing_sub,
	undef, $PBS::Output::indentation, # $indent_title, $indent,
	0, # $no_title,
	1, # $shorten_title,
	undef, # $title_colorizing_sub
	) if defined $PBS::Output::display_error_context ;
}

#-------------------------------------------------------------------------------

use Cwd ;
sub GetRunRelativePath
{
my ($pbs_config, $file, $no_target_path) = @_ ;

unless($pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH})
	{
	my $cwd = Cwd::getcwd() ;
	$file =~ s/$cwd/$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}/g ;

	$file =~ s~$pbs_config->{TARGET_PATH}~$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}~g unless $no_target_path ;
	$file =~ s~^\./$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}~~ ;

	$file =~ s/$_/PBS_LIB\//g for (@{$pbs_config->{LIB_PATH}}) ;
	}
$file
}

sub GetTargetRelativePath
{
my ($pbs_config, $name) = @_ ;

my $no_short_name = $pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH} ;
my $short_name = $name ;
my $glyph = '' eq $pbs_config->{TARGET_PATH}
		? "./"
		: $pbs_config->{SHORT_DEPENDENCY_PATH_STRING} ;

$short_name =~ s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $no_short_name ;

$short_name
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Output -

=head1 SYNOPSIS

  use PBS::Information ;
  PrintUser("Hello user\n") ;

=head1 DESCRIPTION

if B<Term::ANSIColor> is installed in your system, the output generated by B<PBS::Output> functions will be colored.
the colors are controlled through I<SetOutputColor> which is itself (in B<PBS> case) controled through command
line switches.

I<GetLineWithContext> will return a line, from a file, with its context. Not unlike grep -Cn.

=head2 EXPORT

	ERROR WARNING WARNING2 INFO INFO2 USER SHELL DEBUG
	PrintError PrintWarning PrintWarning2 PrintInfo PrintInfo2 PrintUser PrintShell PrintDebug

	GetLineWithContext PrintWithContext PbsDisplayErrorWithContext

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO


=cut
