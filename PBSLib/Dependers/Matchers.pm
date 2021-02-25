
use Carp ;

#-------------------------------------------------------------------------------

sub AnyMatch
{
my @regexes = @_ ;

sub
	{
	for my $regex (@regexes)
		{
		$regex =~ s/\%TARGET_PATH\//$_[1]/ ;
		return $_[1] =~ $regex ;
		}
		
	0 ;
	}
}

#-------------------------------------------------------------------------------

sub NoMatch
{
my @regexes = @_ ;

sub
	{
	my $matched = 0 ;
	
	for my $regex (@regexes)
		{
		$regex =~ s/\%TARGET_PATH\//$_[1]/ ;
		$matched++ if $_[1] =~ $regex ;
		}
		
	return ! $matched ;
	}
}

#-------------------------------------------------------------------------------

sub AndMatch
{
my @dependent_regex = @_ ;

sub
	{
	for my $dependent_regex (@dependent_regex)
		{
		if('Regexp' eq ref $dependent_regex)
			{
			$dependent_regex =~ s/\%TARGET_PATH\//$_[2]/ ;
			
			return 0 unless $_[1] =~ $dependent_regex ;
			}
		elsif('CODE' eq ref $dependent_regex)
			{
			return 0 unless $dependent_regex->(@_) ;
			}
		else
			{
			confess() ;
			}
		}
		
	1 ;
	}
}

#-------------------------------------------------------------------------------

1 ;
