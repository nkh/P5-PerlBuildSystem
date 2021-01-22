
package PBS::Cyclic ;
use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
#~ use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.03' ;

use PBS::Output ;
use Devel::Cycle ;

#-------------------------------------------------------------------------------

sub GetUserCyclicText
{
my ($cyclic_tree_root, $inserted_nodes, $pbs_config, $traversal) = @_ ;

my $cycles = '' ;
my $indent = '' ;

shift @$traversal ;

for my $node (@$traversal)
	{
	$cycles .= "$indent'$node->{__NAME}' inserted at '$node->{__INSERTED_AT}{INSERTION_RULE_FILE}':$node->{__INSERTED_AT}{INSERTION_RULE_LINE}\n" ;
	$indent .= "\t" ;
	}

return(1, $cycles) ;
}

sub GetAllUserCyclicText
{
my ($cyclic_tree_root, $inserted_nodes, $pbs_config, $traversal) = @_ ;

my $number_of_cycles = 0 ;
my $all_cycles = '' ;

my $cycle_display_sub = sub
	{
	my $cycles = shift ;
	
	my $indent = '' ;
	my $cycle = '' ;

	my $root_node ;

	for my $node (@$cycles)
		{
		if($node->[0] eq 'HASH' && exists $node->[2]{__NAME})
			{
			my $name = $node->[2]{__NAME} ;
			
			$cycle .= "$indent'$name' " 
				."inserted at rule: '$inserted_nodes->{$name}{__INSERTED_AT}{INSERTION_RULE}'\n" ;

			$indent .= '   ' ;
			$root_node = $cycle unless defined $root_node ;
			}
		else
			{
			return ; # uninteresting
			}
		}
		
	$all_cycles .= $cycle . $indent . $root_node ;
	$number_of_cycles++ ;
	} ;
	
local $SIG{'__WARN__'} = sub {} ;
#find_cycle($cyclic_tree_root, $cycle_display_sub);
find_cycle($cyclic_tree_root);

return($number_of_cycles, $all_cycles) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Cyclic  -

=head1 SYNOPSIS

  use PBS::Cyclic ;
  my $description_text = GetUserCyclicText($cyclic_tree, $inserted_nodes) ;

=head1 DESCRIPTION

Given a cyclic tree, GetUserCyclicText returns a description text:

	Cyclic dependency detected on './cyclic', induced by './cyclic3'.
	'./cyclic' inserted at rule: 'all:PBS::Runs::PBS_1:User:./cyclic_legend.pl:4'.
	  './cyclic2' inserted at rule: 'cyclic:PBS::Runs::PBS_1:User:./cyclic_legend.pl:6'.
	    './cyclic3' inserted at rule: 'cyclic2:PBS::Runs::PBS_1:User:./cyclic_legend.pl:7'.

=head2 EXPORT

Nothing.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

I<--origin> switch in B<PBS> reference manual.

=cut
