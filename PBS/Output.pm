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
		ERROR WARNING WARNING2 INFO INFO2 INFO3 USER SHELL DEBUG COLOR
		PrintError PrintWarning PrintWarning2 PrintInfo PrintInfo2 PrintInfo3 PrintUser PrintShell PrintDebug
		GetLineWithContext PrintWithContext PbsDisplayErrorWithContext PrintNoColor 
		GetColor
		) ;
		
$VERSION = '0.06' ;

#-------------------------------------------------------------------------------

use Term::ANSIColor qw(:constants) ;
$Term::ANSIColor::AUTORESET = 1 ;

use Term::Size::Any qw(chars) ;

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
use Carp ;
#print Carp::longmess() ;
my $depth  = $PBS::Output::indentation_depth ; $depth = 0 if $depth < 0 ;
my $indent = defined $_[2] && $_[2] == 0 ? '' : ($PBS::Output::indentation x $depth) ;

my $color = $cc{$cd}{$_[0]} // '' ;
my $reset = $cc{$cd}{reset} // '' ;

my $string = $indent . ($_[1] // 'undef') ;
$string =~ s/\n(.)/$reset\n$color$indent$1/g ;

return $color. $string . $reset ;
}
#sub RESET { return COLOR('reset', @_) }
sub ERROR { return COLOR('error', @_) }
sub WARNING  { return COLOR('warning', @_) }
sub WARNING2 { return COLOR('warning_2', @_) }
sub INFO { return COLOR('info', @_) }
sub INFO2 { return COLOR('info_2', @_) }
sub INFO3 { return COLOR('info_3', @_) }
sub USER { return COLOR('user', @_) }
sub SHELL { return COLOR('shell', @_) }
sub DEBUG { return COLOR('debug', @_) }


#-------------------------------------------------------------------------------

sub _print
{
#use Carp qw(cluck longmess shortmess);
#cluck "This is how we got here!"; 


my ($glob, $color_and_depth, $data, $indent) = @_ ;

$_ //= '' ;

$data =~ s/^(\t+)/$indentation x length($1)/gsme if $indent ;

my $reset = $cc{$cd}{reset} // '' ;
my ($ends_with_newline) = $data =~ /(\n+(?:\Q$reset\E)?)$/ ;

print $glob $output_info_label, 
	join
		(
		"\n$output_info_label",
		map { $color_and_depth->($_) }
			split /\n(?:\Q$reset\E)?/, $data
		) ;

$ends_with_newline && print $glob $ends_with_newline ;
}

sub PrintStdOut {_print(\*STDOUT, \&RESET, @_);}
sub PrintStdErr {_print(\*STDERR, \&RESET, @_);}

sub PrintStdOutColor {_print(\*STDOUT, @_);} # pass a color handler as first argument
sub PrintStdErrColor {_print(\*STDERR, @_);} # pass a color handler as first argument

sub PrintNoColor {_print(\*STDERR, \&RESET, @_);}
sub PrintColor {my $color = shift; _print(\*STDERR, sub {COLOR($color, @_)}, @_);}

sub PrintError {_print(\*STDERR, \&ERROR, @_);}
sub PrintWarning {_print(\*STDERR, \&WARNING, @_) ;}
sub PrintWarning2{_print(\*STDERR, \&WARNING2, @_) ;}
sub PrintInfo{_print(\*STDERR, \&INFO, @_ );}
sub PrintInfo2{_print(\*STDERR, \&INFO2, @_) ;}
sub PrintInfo3{_print(\*STDERR, \&INFO3, @_) ;}
sub PrintUser{_print(\*STDERR, \&USER, @_) ;}
sub PrintShell {_print(\*STDERR, \&SHELL, @_) ;}
sub PrintDebug{_print(\*STDERR, \&DEBUG, @_) ;}

#-------------------------------------------------------------------------------

sub GetLineWithContext
{
my $file_name                   = shift ;
my $number_of_blank_lines       = shift ;
my $number_of_context_lines     = shift ;
my $center_line_index           = shift ;
my $center_line_colorizing_sub  = shift || sub{ COLOR('reset', @_) } ;
my $context_colorizing_sub      = shift || sub{ COLOR('reset', @_) } ;

open(FILE, '<', $file_name) or die ERROR(qq[Can't open $file_name for context display: $!]), "\n" ;

my $number_of_lines_skip = ($center_line_index - $number_of_context_lines) - 1 ;

my $top_context = $number_of_context_lines ;
$top_context += $number_of_lines_skip if $number_of_lines_skip < 0 ;

my $line_with_context = '' ;

$line_with_context.= "\n" for (1 .. $number_of_blank_lines) ;

<FILE> for (1 .. $number_of_lines_skip) ;

my $t = $PBS::Output::indentation;

$line_with_context .= INFO2("$t${t}File: '$file_name'\n", 0) ;

for(1 .. $top_context)
	{
	my $text = <FILE> ;
	next unless defined $text ;

	$line_with_context .=  $context_colorizing_sub->("$t$t$. $text", 0) ;
	}
		
my $center_line_text = <FILE> ;
$line_with_context .= $center_line_colorizing_sub->("$t$t$. $center_line_text", 0) if defined $center_line_text ;

for(1 .. $number_of_context_lines)
	{
	my $text = <FILE> ;
	next unless defined $text ;
	
	$line_with_context .= $context_colorizing_sub->("$t$t$. $text", 0) ;
	}

$line_with_context .= "\n" for (1 .. $number_of_blank_lines) ;

close(FILE) ;

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
PrintWithContext($_[0], 1, 4, $_[1], \&ERROR, \&INFO) if defined $PBS::Output::display_error_context ;
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
