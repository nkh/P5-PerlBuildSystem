use Time::HiRes qw(tv_interval gettimeofday) ;

my $t0_topo = [gettimeofday];


my %ba;

sub add_deps
{
my ($node, @deps) = @_ ;

for my $dep (@deps)
	{
	$ba{$node}{$dep} = 1 ;
	$ba{$dep} ||= {};
	}
}

add_deps qw(A  a aa aaa aa aa aa) ;
add_deps qw(B  b bb bbb b bb bbbbbb) ;
add_deps qw(B a) ;
add_deps qw(b aaa) ;
add_deps qw(bb aaa) ;
add_deps qw(aaa bbb) ;

while ( my @afters = sort grep { ! %{ $ba{$_} } } keys %ba )
	{
	print join("\n",@afters) . "\n";
	delete @ba{@afters};
	delete @{$_}{@afters} for values %ba;
	}

print %ba ? "Cycle found! ". join( ' ', sort keys %ba ). "\n" : "" ;

print sprintf("topo sort time: %0.6f s.\n", tv_interval ($t0_topo, [gettimeofday])) ;

