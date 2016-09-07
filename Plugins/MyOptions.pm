
=head1 Plugin MyOptions 

Define options that are made available in the pbs configuration and accessible 
throught the normal command line option mechanism

name
name@
name=s
name=s@
name=i
name=i@

=over 2

=item  --evaluate_shell_command_verbose

=back

=cut

use PBS::PBSConfigSwitches ;
use PBS::PBSConfig ;
use PBS::Information ;
use Data::TreeDumper ;

#-------------------------------------------------------------------------------

my $comment = <<EOF ;

PBS::PBSConfigSwitches::RegisterFlagsAndHelp
	(
	'my_flag',
	'MY_FLAG',
	'',
	'',

	'my_flag_string=s',
	'MY_FLAG_STRING',
	'',
	'',

	'my_flag_string_list=s@',
	'MY_FLAG_STRING_LIST',
	'',
	'',

	'my_flag_integer=i',
	'MY_FLAG_INTEGER',
	'',
	'',

	'my_flag_integer_list=i@',
	'MY_FLAG_INTEGER_LIST',
	'',
	'',
	
	'my_flag_integer_hash=i%',
	'MY_FLAG_INTEGER_HASH',
	'',
	'',
	) ;
EOF
	
