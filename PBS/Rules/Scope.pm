
package PBS::Rules::Scope;

use 5.006 ;

use strict ;
use warnings ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(Scope) ;
our $VERSION = '0.01' ;

#-------------------------------------------------------------------------------

use PBS::PBSConfig ;
use PBS::Output ;

#---------------------------------------------------------------------------------------

my %scope_per_package ;

sub GetRuleBefore
{
my ($package, $rule_name) = @_ ;
my $pbs_config = GetPbsConfig($package) ;

return if $pbs_config->{RULE_NO_SCOPE} ;

if(exists $scope_per_package{$package} && exists $scope_per_package{$package}{$rule_name})
	{
	if($pbs_config->{DISPLAY_RULE_SCOPE})
		{
		PrintDebug "Scope: rule '$rule_name' scoped after:\n" ;
		PrintDebug "\t\t$_\n" for (@{$scope_per_package{$package}{$rule_name}}) ;
		}

	return @{$scope_per_package{$package}{$rule_name}}
	}
	{
	PrintDebug "Scope: rule '$package:$rule_name':\n\t\tno scope\n" if $pbs_config->{DISPLAY_RULE_SCOPE} ;
	return ()
	}
}

sub Scope
{
my($scope) = @_ ;

my ($package, $file_name, $caller_line) = caller() ;
my $pbs_config = GetPbsConfig($package) ;

my $line = 0 ;
my @stack = [ -1, ''] ;

for my $rule_scope (split "\n", $scope)
	{
	$line++ ;

	my ($rule) = $rule_scope =~ /^\t*([0-9a-zA-z_]+)$/ ;

	if (defined $rule)
		{
		my $rule_depth = $rule_scope =~ tr/\t/\t/ ;

		my ($stack_depth, $before)  = ($stack[-1][0], $stack[-1][1]) ;
		my $previous_top = $stack_depth ;
		my $operation = '' ;

		if ($rule_depth == $stack_depth)
			{
			$operation = "$rule_depth = $previous_top" ;

			pop @stack ;
			($stack_depth, $before)  = ($stack[-1][0], $stack[-1][1]) ;
			}
		elsif ($rule_depth > $stack_depth)
			{
			$operation = "$rule_depth > $stack_depth" ;
			}
		else
			{
			$operation = " $rule_depth < $previous_top" ;

			do
				{
				pop @stack ;
				($stack_depth, $before)  = ($stack[-1][0], $stack[-1][1]) ;
				#PrintDebug "Scope: < pop '$before', stack_depth: $stack_depth\n" ;
				}
			while ($stack_depth >= $rule_depth) ;
			}

		PrintDebug "Scope:" . "\t" x $rule_depth . "$rule => $before, $operation\n" if $pbs_config->{DISPLAY_RULE_SCOPE} ;

		push @stack, [$rule_depth, $rule] ;
		push @{$scope_per_package{$package}{$rule}}, $before if $before ne '' ;
		}
	else
		{
		if($rule_scope =~ /^\s*$/)
			{
			PrintDebug "Scope:\n" if $pbs_config->{DISPLAY_RULE_SCOPE},
			}
		else
			{
			PrintWarning "Scope: Error on line $line: '$rule_scope, ignoring Scope definition\n" ;
			PrintWarning "\tfound spaces in scope definition\n" if $rule_scope =~ /\ / ; 
			return ; 
			}
		}
	}
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Rules::Scope - Gives rules a scope

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 EXPORT

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
