
package PBS::Cyclic ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.03' ;

#-------------------------------------------------------------------------------

sub GetUserCyclicText
{
my ($cyclic_tree_root, $inserted_nodes, $pbs_config, $trail) = @_ ;

my $cycles = '' ;
my $indent = '' ;

shift @$trail ;

for my $node (@$trail)
	{
	$cycles .= GetRunRelativePath
			(
			$pbs_config,
			 "$indent$node->{__NAME} "
			. "inserted at $node->{__INSERTED_AT}{INSERTION_RULE_FILE}:$node->{__INSERTED_AT}{INSERTION_RULE_LINE}\n"
			) ;

	$indent .= "\t" ;
	}

return $cycles
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
