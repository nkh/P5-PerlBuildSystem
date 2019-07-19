
=head1 ColorDefinitions

Set default color definitions and user defined colors

=cut

use Term::ANSIColor qw(:constants color) ;

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

		no_match  => '',

		box_1_1   => '',
		box_1_2   => '',

		box_2_1   => '',
		box_2_2   => '',

		reset     => '',
		},
	16 => 
		{
		debug     => color('magenta'),
		error     => color('red'),
		info      => color('green'),
		info_2    => color('bright_blue'),
		info_3    => color('cyan'),
		shell     => color('cyan'),
		user      => color('bright_cyan'),
		warning   => color('yellow'),
		warning_2 => color('bright_yellow'),

		no_match  => color('red'),

		box_1_1   => color('on_black'),
		box_1_2   => color('on_black'),

		box_2_1   => color('on_bright_black'),
		box_2_2   => color('on_bright_black'),

		reset     => color('reset'),
		},
	256 => 
		{
		debug     => color('rgb314'),
		error     => color('rgb300'), #red
		info      => color('rgb020'), #green
		info_2    => color('rgb013'), #bright_blue
		info_3    => color('rgb023'), #cyan
		shell     => color('rgb023'),
		user      => color('cyan'),
		warning   => color('rgb320'),
		warning_2 => color('bright_yellow'),

		no_match  => color('RGB200'),

		box_1_1   => color('on_grey1'),
		box_1_2   => color('on_grey1'),

		box_2_1   => color('on_grey3'),
		box_2_2   => color('on_grey3'),

		reset     => color('reset'),
		},
	) ;
}

#-------------------------------------------------------------------------------

1 ;

