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
		PrintError PrintWarning PrintWarning2 PrintInfo PrintInfo2 PrintUser PrintShell PrintDebug
		GetLineWithContext PrintWithContext PbsDisplayErrorWithContext
		) ;
		
$VERSION = '0.06' ;

#-------------------------------------------------------------------------------

use Term::ANSIColor qw(:constants) ;
$Term::ANSIColor::AUTORESET = 1 ;


#-------------------------------------------------------------------------------

our $indentation = '   ' ;
our $indentation_depth = 0 ;
our $display_error_context  = 0 ;

my $cd = 16 ; # color_depth
my %cc ;

sub SetDefaultColors
{
my ($default_colors) = @_ ;
$default_colors //= {} ;

for my $depth (keys %$default_colors)
	{
	$cc{$depth} = { %{$default_colors->{$depth} // {}}, %{$cc{$depth} // {}} } ;
	}
}

#-------------------------------------------------------------------------------

sub InfoLabel
{
for my $color (keys %{$cc{$cd}})
	{
	next if $color eq 'reset' ;

	$cc{$cd}{$color} .= '[' . ucfirst($color) . '] ' ; 
	}
}


#-------------------------------------------------------------------------------

sub SetOutputColorDepth { $cd = $_[1] if $_[1] == 2 || $_[1] == 16 || $_[1] == 256 }

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
die $@ if $@ ;

my $depth  = $PBS::Output::indentation_depth ; $depth = 0 if $depth < 0 ;
my $indent = defined $_[2] && $_[2] == 0 ? '' : ($PBS::Output::indentation x $depth) ;

my $string = $indent . ($_[1] // 'undef') ;
$string =~ s/\n(.)/\n$indent$1/g ;

return ($cc{$cd}{$_[0]} // '') . $string . ($cc{$cd}{reset} // '') ;
}

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
my ($glob, $color_and_depth, @data) = @_ ;

for (@data)
	{
	$_ //= '' ;
	
	s/^(\t+)/$indentation x length($1)/gsme ;
	
	print $glob $color_and_depth->($_) ;
	
	}
}

sub PrintError {_print(\*STDERR, \&ERROR, @_);}
sub PrintWarning {_print(\*STDERR, \&WARNING, @_) ;}
sub PrintWarning2{_print(\*STDERR, \&WARNING2, @_) ;}
sub PrintInfo{_print(\*STDERR, \&INFO, @_ );}
sub PrintInfo2{_print(\*STDERR, \&INFO2, @_) ;}
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
my $center_line_colorizing_sub  = shift || sub{$_[0]} ;
my $context_colorizing_sub      = shift || sub{$_[0]} ;

open(FILE, '<', $file_name) or die ERROR(qq[Can't open $file_name for context display: $!]), "\n" ;

my $number_of_lines_skip = ($center_line_index - $number_of_context_lines) - 1 ;

my $top_context = $number_of_context_lines ;
$top_context += $number_of_lines_skip if $number_of_lines_skip < 0 ;

my $line_with_context = '' ;

$line_with_context.= "\n" for (1 .. $number_of_blank_lines) ;

<FILE> for (1 .. $number_of_lines_skip) ;

$line_with_context .= INFO("File: '$file_name'\n") ;

for(1 .. $top_context)
	{
	my $text = <FILE> ;
	next unless defined $text ;

	$line_with_context .=  $context_colorizing_sub->("$.- $text") ;
	}
		
my $center_line_text = <FILE> ;
$line_with_context .= $center_line_colorizing_sub->("$.> $center_line_text") if defined $center_line_text ;

for(1 .. $number_of_context_lines)
	{
	my $text = <FILE> ;
	next unless defined $text ;
	
	$line_with_context .= $context_colorizing_sub->("$.- $text") ;
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
