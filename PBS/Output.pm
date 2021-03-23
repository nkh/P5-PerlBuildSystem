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

my $cd = 256 ; # color_depth
my %cc ;
my %user_cc ; 
my %color_alias ;

BEGIN
{
	if ($^O eq 'MSWin32')
	{
		eval "use Win32::Console::ANSI;";
	}

} ; #BEGIN

my %registered_colors ;
sub ResetUniqColorNames { %registered_colors = () }

sub GetUniqColorName
{
my ($name) = @_ ;

if(exists $registered_colors{$name})
	{
	my $counter = 1 ;
	my $name_c = "${name}_$counter" ;

	while (exists $registered_colors{$name_c})
		{
		$counter++ ;
		$name_c = "${name}_$counter" ;
		}

	$registered_colors{$name_c}++ ;
	$name = $name_c ;
	}
else
	{
	$registered_colors{$name}++ ;
	}

$name
}

sub CreateColorFunctions
{
use Sub::Install ;

ResetUniqColorNames() ;
my @exports ;

for my $color_name (@_)
	{
	no warnings 'redefine' ;

	my ($initial, $number) = $color_name =~ /^(.).*?(\d+)?$/ ;
	$number //= '' ;

	my $name = uc($initial) . $number ;
	$color_alias{$name} = $color_name unless exists $color_alias{$name} ;

	#---------------------------------------------------------------------
	my $COLOR  = sub { COLOR($color_name, @_) } ;

	$name = GetUniqColorName(uc($color_name)) ;
	push @exports, $name ;
	Sub::Install::reinstall_sub ({ code => $COLOR, as => $name});

	$name =  GetUniqColorName(ucfirst($color_name)) ;
	push @exports, $name ;
	Sub::Install::reinstall_sub ({ code => $COLOR, as => $name });

	#---------------------------------------------------------------------
	my $COLOR_ = sub { COLOR($color_name, @_, 0) } ;

	$name =  GetUniqColorName('_' . uc($color_name) . '_') ;
	push @exports, $name ;
	Sub::Install::reinstall_sub ({ code => $COLOR_, as => $name });

	#---------------------------------------------------------------------
	my $PRINT_COLOR = eval "sub { _print(\\*STDERR, \\&" . uc($color_name) . ", \@_) } " ;

	$name =  GetUniqColorName('Print' . ucfirst($color_name)) ;
	push @exports, $name ;
	Sub::Install::reinstall_sub ({ code => $PRINT_COLOR, as => $name });

	#---------------------------------------------------------------------
	my $ST_COLOR = eval "sub { _ST(\\&" . uc($color_name) . ", [caller(0)], \@_) }" ;

	my $letter = uc(substr $color_name, 0, 1) ;
	($number) = $color_name =~ m/(\d+)$/ ; 
	$number //= '' ;

	my $uname = GetUniqColorName(uc($initial) . $number) ;

	$name =  'S' . $uname . 'T' ;
 
	push @exports, $name ;
	Sub::Install::reinstall_sub ({ code => $ST_COLOR, as => $name });
	}

@exports 
}

use subs qw - Error Color - ;

use vars qw($VERSION @ISA @EXPORT) ;

require Exporter;

my @exports = 
	(
	CreateColorFunctions
		(qw/
		debug   
		debug2  
		debug3  
		error   
		error2   
		error3   
		on_error
		info    
		info2   
		info3   
		info4   
		info5   
		info6
		shell   
		shell2   
		user    
		warning 
		warning2
		warning3
		warning4
		
		box_11  
		box_12  
		box_21  
		box_22  
		
		test_bg 
		test_bg2
		
		ttcl1
		ttcl2
		ttcl3
		ttcl4
		
		dark
		no_match
		ignoring_local_rule
		
		/),
	qw(
		Say Print

		COLOR Color GetColor
		NO_COLOR NoColor _NO_COLOR_
		Colored EC

		PrintColor PrintNoColor PrintVerbatim
		
		GetLineWithContext PrintWithContext PbsDisplayErrorWithContext

		GetRunRelativePath GetTargetRelativePath
	) 
	);

@ISA     = qw(Exporter) ;
@EXPORT  = @exports ;
		
$VERSION = '0.09' ;

#-------------------------------------------------------------------------------

use Module::Util qw(find_installed) ;

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
our $output_from_where = 0 ;

#-------------------------------------------------------------------------------

sub GetScreenWidth { (chars() // 10_000) - ( length($indentation x ($indentation_depth + 3)) + length($output_info_label)) }

#-------------------------------------------------------------------------------

sub SetDefaultColors
{
my ($colors) = @_ ;
my @colors ;

use Data::TreeDumper ;
#print DumpTree $colors, 'colors' ;

for my $class (keys %$colors)
	{
	for (my $i = 0 ; $i < $#{$colors->{$class}} ; $i += 2)
		{
		push @colors, [ $colors->{$class}[$i] => $colors->{$class}[$i +1] ] ;
		}

	push @colors, { [ $colors->{$class}[$_] => $user_cc{$class}{$_} ] } for keys %{$user_cc{$class}} ;
		 
	$cc{$class}{$_->[0]} = $_->[1] for @colors ;
	}

#print DumpTree \%cc ;

CreateColorFunctions(map { $_->[0] } @colors) ;
}


sub GetColor
{
$cc{$cd}{$_[0]} // '' ; 
}

#-------------------------------------------------------------------------------

sub SetOutputColorDepth { $cd = $_[1] }

sub SetOutputColor
{
my ($color_name, $color) = split(':', $_[1]) ;

unless(defined $color)
	{
	print STDERR "Colors: invalid definition for '$color_name'\n" ;
	return ;
	}

return if $cd == 2 ;

my $escape_code = '' ;
eval {$escape_code = Term::ANSIColor::color($color) ;} ;

if($@)
	{
	print STDERR "PBS config: invalid color definition '$color_name: $color'.\n" ;
	}
else
	{
	$user_cc{$cd}{$color_name} = $escape_code ; 
	CreateColorFunctions $color_name ;
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

my $depth = $PBS::Output::indentation_depth ; $depth = 0 if $depth < 0 ;
my $indentation = $indent && ! $PBS::Output::no_indentation ? ($PBS::Output::indentation x $depth) : '' ;

my $color = $cc{$cd}{$color_name} // '' ;
my $reset = defined $continuation_color ? $cc{$cd}{$continuation_color} // '' : $cc{$cd}{reset} // '' ;

my $string_indent = $PBS::Output::indentation ne q{} && $string =~ s/^($PBS::Output::indentation+)// ? $1 : '' ; # works for first line only

my $indentation1 = $no_indent_color ? $indentation . $string_indent : $color . $indentation . $string_indent ;

my $indentation2 = $no_indent_color ? $indentation : $color . $indentation ;
$string =~ s/\n(.)/\n$indentation2$1/g ;

return $indentation1 . $color . $string . $reset ;
}

*Color=\&COLOR ;

sub _NO_COLOR_ { return COLOR('reset',  @_, 0) }
sub NO_COLOR { return COLOR('reset', @_) }
*NoColor  =\&NO_COLOR ;

#-------------------------------------------------------------------------------

sub Colored
{
my ($string, $indent, $no_indent_color, $continuation_color) = @_ ;

$string =~ s~(?<!\\)<([[:alnum:]_]+)>~(exists $color_alias{$1} and $cc{$cd}{$color_alias{$1}})//$cc{$cd}{$1}//"<$1>"~ge ;
$string =~ s~\\(<([[:alnum:]_]+)>)~$1~g ;

COLOR('', $string, $indent, $no_indent_color, $continuation_color) ;
}

*EC=\&Colored ;


#-------------------------------------------------------------------------------

sub _print
{
#use Carp qw(cluck longmess shortmess);
#cluck "This is how we got here!"; 

print STDERR join ':', (caller(1))[1, 2] if $output_from_where ;

my ($glob, $color, $data, $indent, $color_indent) = @_ ;

return unless defined $data ;

$data =~ s/\t/$indentation/gm ;

my $reset = $cc{$cd}{reset} // '' ;
my ($ends_with_newline) = $data =~ /(\n+(?:\Q$reset\E)?)$/ ;
$ends_with_newline //= '' ;

my $lines =  join
		(
		"\n$output_info_label",
		map 	
			{ 
			$_ ne "\e[K\e[K" 
				? $color
					? $color->($_, $indent, $color_indent)
					: $_
				: q{} 
			}
			split /\n(?:\Q$reset\E)?/, $data
		)
		. $ends_with_newline ;

print $glob "$output_info_label$lines" ;
}

sub PrintStdOut {_print(\*STDOUT, \&NO_COLOR, @_)}
sub PrintStdErr {_print(\*STDERR, \&NO_COLOR, @_)}

sub PrintStdOutColor {_print(\*STDOUT, @_)} # pass a color handler as first argument
sub PrintStdErrColor {_print(\*STDERR, @_)} # pass a color handler as first argument

sub PrintColor    {my $color = shift; _print(\*STDERR, sub {COLOR($color, @_)}, @_)}
sub PrintNoColor  {_print(\*STDERR, \&NO_COLOR, @_)}
sub PrintVerbatim {print STDERR  @_} # used to print build process output which already has used _print 

sub Print        {_print(\*STDERR, undef, @_)}
sub Say          {_print(\*STDERR, undef, (shift . "\n"), @_)}

sub _ST 
{
my ($color, $caller) = splice @_, 0, 2 ;

print STDERR join ':', (caller(1))[1, 2] if $output_from_where ;

my ($f, $l) = @{$caller}[1, 2] ;
$f = GetRunRelativePath({TARGET_PATH => '', SHORT_DEPENDENCY_PATH_STRING => '…'}, $f, 1) ;

eval
	{
	if (@_ == 0) {}
	if (@_ == 1) { print STDERR $color->(Data::TreeDumper::DumpTree(@_, '', DUMPER_NAME => "SDT $f:$l")) }
	    else     { print STDERR $color->(Data::TreeDumper::DumpTree(@_, DUMPER_NAME => "SDT $f:$l")) }
	} ;

Say Error "SxT: error: Odd number of arguments @ $f:$l $@" if $@ ;
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
my $cwd = Cwd::getcwd() ;

my %GRRP ; # cache access, memoize?

sub GetRunRelativePath
{
my ($pbs_config, $file, $no_target_path) = @_ ;
$no_target_path //= 0 ;

unless($pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH})
	{
	if(exists $GRRP{"$file$no_target_path"})
		{
		$file = $GRRP{"$file$no_target_path"} ;
		}
	else
		{
		$file =~ s/$cwd/$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}/g ;
		$file =~ s~$pbs_config->{TARGET_PATH}~$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}~g unless $no_target_path || $pbs_config->{TARGET_PATH} eq '' ;
		$file =~ s~^\./$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}~~ ;

		$file =~ s/$_/PBS_LIB\//g for @{$pbs_config->{LIB_PATH}} ;

		my ($basename, $path, $ext) = File::Basename::fileparse(find_installed('PBS::PBS'), ('\..*')) ;
		$file =~ s/$path/$pbs_config->{SHORT_DEPENDENCY_PATH_STRING}\//g ;
		
		$GRRP{"$file$no_target_path"} = $file ;
		}
	}
$file
}

my %GTRP ; # cache access, memoize?

sub GetTargetRelativePath
{
my ($pbs_config, $name) = @_ ;

unless(exists $GTRP{$name}) 
	{
	my $glyph = '' eq $pbs_config->{TARGET_PATH} ? "./" : $pbs_config->{SHORT_DEPENDENCY_PATH_STRING} ;
	
	my $short_name = $name ;
	   $short_name =~ s/^.\/$pbs_config->{TARGET_PATH}/$glyph/ unless $pbs_config->{DISPLAY_FULL_DEPENDENCY_PATH} ;
	
	$GTRP{$name} = $short_name ;
	}

$GTRP{$name} ; 
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
