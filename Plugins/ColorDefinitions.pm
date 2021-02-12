
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
		warning_3 => '',
		info      => '',
		info_2    => '',
		info_3    => '',
		info_4    => '',
		info_5    => '',
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
		info_4    => color('bright_green'),
		info_5    => color('bright_green'),
		shell     => color('cyan'),
		user      => color('bright_cyan'),
		warning   => color('yellow'),
		warning_2 => color('bright_yellow'),
		warning_3 => color('bright_yellow'),

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
		error     => color('rgb300'),
		info      => color('rgb020'),
		info_2    => color('rgb013'),
		info_3    => color('rgb023'), 
		info_4    => color('rgb030'),
		info_5    => color('rgb012'),
		shell     => color('rgb023'),
		user      => color('rgb034'),
		warning   => color('rgb320'),
		warning_2 => color('bright_yellow'),
		warning_3 => color('rgb210'),

		no_match  => color('rgb200'),

		box_1_1   => color('on_grey1'),
		box_1_2   => color('on_grey1'),

		box_2_1   => color('on_grey3'),
		box_2_2   => color('on_grey3'),

		test_bg   => color('rgb220 on_rgb101'),

		reset     => color('reset'),
		},

	night => 
		{
		debug     => color('rgb314'),
		error     => color('rgb200'),
		info      => color('rgb020'),
		info_2    => color('rgb013'),
		info_3    => color('rgb023'), 
		info_4    => color('rgb030'),
		info_5    => color('rgb010'),
		shell     => color('rgb023'),
		user      => color('rgb034'),
		warning   => color('rgb320'),
		warning_2 => color('rgb440'),
		warning_3 => color('rgb210'),

		no_match  => color('rgb200'),

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

