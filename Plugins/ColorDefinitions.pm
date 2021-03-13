
=head1 ColorDefinitions

Set default color definitions and user defined colors

=cut

use Term::ANSIColor qw(:constants color) ;

#-------------------------------------------------------------------------------

sub GetColorDefinitions
{
return
	(
	256 =>
		{
		debug    => color('rgb314'),
		debug2   => color('rgb304'),
		debug3   => color('rgb102'),
		on_error => color('on_rgb100'),
		error    => color('rgb300'),
		info     => color('rgb020'),
		info2    => color('rgb013'),
		info3    => color('rgb023'),
		info4    => color('rgb030'),
		info5    => color('rgb012'),
		shell    => color('grey7'),
		user     => color('rgb034'),
		warning  => color('rgb320'),
		warning2 => color('bright_yellow'),
		warning3 => color('rgb210'),
		warning4 => color('rgb310'),

		no_match => color('rgb200'),

		box_11   => color('on_grey4'),
		box_12   => color('on_grey4'),

		box_21   => color(''),
		box_22   => color(''),

		test_bg  => color('rgb220 on_rgb101'),
		test_bg2 => color('rgb220 on_rgb003'),
		dark     => color('rgb000'),

		ignoring_local_rule => color('rgb220 on_rgb101'),

		ttcl1    => color('rgb010'),
		ttcl2    => color('rgb012'),
		ttcl3    => color('grey8'),
		ttcl4    => color('rgb101'),

		reset    => color('reset'),
		},
	night =>
		{
		debug    => color('rgb314'),
		debug2   => color('rgb304'),
		debug3   => color('rgb203'),
		on_error => color('on_rgb100'),
		error    => color('rgb200'),
		info     => color('rgb020'),
		info2    => color('rgb013'),
		info3    => color('rgb023'),
		info4    => color('rgb030'),
		info5    => color('rgb010'),
		shell    => color('grey7'),
		user     => color('rgb034'),
		warning  => color('rgb320'),
		warning2 => color('rgb440'),
		warning3 => color('rgb210'),
		warning4 => color('rgb310'),

		no_match => color('rgb200'),

		box_11   => color('on_grey2'),
		box_12   => color('on_grey2'),

		box_21   => color(''),
		box_22   => color(''),

		ignoring_local_rule  => color('rgb220 on_rgb101'),

		ttcl1    => color('rgb010'),
		ttcl2    => color('rgb012'),
		ttcl3    => color('grey8'),
		ttcl4    => color('rgb101'),

		reset    => color('reset'),
		},
	16 =>
		{
		debug    => color('magenta'),
		debug2   => color('magenta'),
		debug3   => color('magenta'),
		error    => color('red'),
		info     => color('green'),
		info2    => color('bright_blue'),
		info3    => color('cyan'),
		info4    => color('bright_green'),
		info5    => color('bright_green'),
		shell    => color('cyan'),
		user     => color('bright_cyan'),
		warning  => color('yellow'),
		warning2 => color('bright_yellow'),
		warning3 => color('bright_yellow'),
		warning4 => color('bright_yellow'),

		no_match => color('red'),

		box_11   => color('on_black'),
		box_12   => color('on_black'),

		box_21   => color('on_bright_black'),
		box_22   => color('on_bright_black'),

		reset    => color('reset'),
		},
	2 =>
		{
		debug    => '',
		debug2   => '',
		debug3   => '',
		error    => '',
		warning  => '',
		warning2 => '',
		warning3 => '',
		warning4 => '',
		info     => '',
		info2    => '',
		info3    => '',
		info4    => '',
		info5    => '',
		user     => '',
		shell    => '',

		no_match => '',

		box_11   => '',
		box_12   => '',

		box_21   => '',
		box_22   => '',

		reset     => '',
		},
	) ;
}

#-------------------------------------------------------------------------------

1 ;

