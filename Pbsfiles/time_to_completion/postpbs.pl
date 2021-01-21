
# show the gant data for gant nodes present in the dependency graph
# if a warp is used, only the necessary nodes are in the graph so there may be no
# gant nodes if they are up to date

traverse_graph($dependency_tree, \&DisplayDeliveryTime) ;

sub traverse_graph
{
my ($node, $callback, @args) = @_ ;

return unless $callback->($node, 'entering', @args) ;

traverse_graph->($node->{$_}, $callback, @args) for (grep {! /^__/} keys %$node) ;

$callback->($node, 'leaving', @args) ;
}

use Data::TreeDumper ;
use File::Slurp ;

sub DisplayDeliveryTime
{
my ($node, $phase) = @_ ;

return 0 unless 'HASH' eq ref $node ; # handle up to date warp  
return 0 unless exists $node->{__NAME} ; # handle up to date warp  

if ('entering' eq $phase)
	{
	return ! exists $node->{__GANT_DELIVERY_TIME_DISPLAYED} ;
	}
else
	{
	my ($name) = ($node->{__NAME}) ;

	if ($name =~ /\.gant$/)
		{
		my $file = $node->{__BUILD_NAME} ;
		my $data ;

		# use serialized nodes delivery time, so warp, parallel build, ... works
		unless ($data = do $file)
			{
			PrintWarning "couldn't parse $file: $@\n" if $@ ;
			PrintWarning "couldn't do $file: $!\n"    unless defined $data ;
			PrintWarning "couldn't run $file\n"       unless $data ;

			$data = {} ;
			}

		#PrintInfo4 DumpTree $data, "GANT: '$name'", DISPLAY_ADDRESS => 0 ;
		PrintInfo4 "GANT: " . read_file($file) ;
		}
	$node->{__GANT_DELIVERY_TIME_DISPLAYED}++ ;
	}
}

# ----------------------------------------------------------------------

1 ;

