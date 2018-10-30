
=head1 ColorDefinitions

Set default color definitions and user defined colors

=cut

use Term::ANSIColor qw(:constants) ;

#-------------------------------------------------------------------------------

sub GetColorDefinitions
{
return
	(
	2 => 
		{
		error     => '',
		warning   => '',
		warning_2 => '',
		info      => '',
		info_2    => '',
		info_3    => '',
		user      => '',
		shell     => '',
		debug     => '',
		reset     => '',
		},
	16 => 
		{
		debug     => Term::ANSIColor::color('magenta'),
		error     => Term::ANSIColor::color('red'),
		info      => Term::ANSIColor::color('green'),
		info_2    => Term::ANSIColor::color('bright_blue'),
		info_3    => Term::ANSIColor::color('cyan'),
		shell     => Term::ANSIColor::color('cyan'),
		user      => Term::ANSIColor::color('cyan'),
		warning   => Term::ANSIColor::color('yellow'),
		warning_2 => Term::ANSIColor::color('bright_yellow'),

		no_match  => Term::ANSIColor::color('red'),

		reset     => Term::ANSIColor::color('reset'),
		},
	256 => 
		{
		debug     => Term::ANSIColor::color('magenta'),
		error     => Term::ANSIColor::color('red'),
		info      => Term::ANSIColor::color('green'),
		info_2    => Term::ANSIColor::color('bright_blue'),
		info_3    => Term::ANSIColor::color('cyan'),
		shell     => Term::ANSIColor::color('cyan'),
		user      => Term::ANSIColor::color('cyan'),
		warning   => Term::ANSIColor::color('yellow'),
		warning_2 => Term::ANSIColor::color('bright_yellow'),

		no_match  => Term::ANSIColor::color('RGB200'),

		reset     => Term::ANSIColor::color('reset'),
		},
	) ;
}

#-------------------------------------------------------------------------------

1 ;

