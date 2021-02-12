package PBS::Rules::Dependers ;

use PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::TreeDumper ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateDepender GenerateDependerFromArray GenerateSubpbsDepender BuildDependentRegex) ;
our $VERSION = '0.01' ;

use File::Basename ;

use PBS::PBSConfig ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Rules ;

use PBS::Rules::Dependers::Subpbs ;

#-------------------------------------------------------------------------------

sub GenerateDepender
{
my ($pbs_config, $file_name, $line, $package, $class, $rule_types, $name, $depender_definition) =  @_ ;

my @depender_node_subs_and_types ; # types is a special case to display info about dependers that are also creators

for (ref $depender_definition)
	{
	/^ARRAY$/ and do
		{
		@depender_node_subs_and_types = GenerateDependerFromArray(@_) ;
		last ;
		} ;
		
	/^HASH$/ and do
		{
		@depender_node_subs_and_types = GenerateSubpbsDepender(@_) ;
		last ;
		} ;
	
	/^CODE$/ and do
		{
		@depender_node_subs_and_types = GenerateDependerFromCode($depender_definition) ;
		last ;
		} ;
		
	# DEFAULT
		print STDERR ERROR("Invalid depender definition '$depender_definition' at rule '$name' at '$file_name:$line'.\n") ;
		PbsDisplayErrorWithContext($pbs_config, $file_name, $line) ;
		die ;
	}
	
return(@depender_node_subs_and_types) ;
}

#-------------------------------------------------------------------------------

sub GenerateDependerFromCode
{
	
# this code does almost nothing but rearrange the argument list so code dependers and
# simplified dependers get their arguments in the same order

my ($code_reference) = @_ ;

my $depender_sub = 
		sub 
			{
			my ($dependent, $config, $tree, $inserted_nodes, $rule_definition) = @_ ;
			
			my ($dependencies, $builder_override) ;
			
			($dependencies, $builder_override) = $code_reference->
									(
									$dependent,
									$config,
									$tree,
									$inserted_nodes,
									undef, # rule local
									undef, # rule local
									$rule_definition,
									) ;
			return($dependencies, $builder_override) ;
			} ;
	
return($depender_sub) ;
}

#-------------------------------------------------------------------------------

sub GenerateDependerFromArray
{
# the returned depender calls 2 subs (also generated in this code)
# $dependent_matcher matches the dependent
# $dependencies_evaluator is to ,ie, replace $name by the node name ... it  is only called if the above sub matches.

my ($pbs_config, $file_name, $line, $package, $class, $rule_types, $name, $depender_definition) = @_ ;

unless(@$depender_definition)
	{
	Carp::carp ERROR("Depend: Nothing defined in rule definition at: $name at '$file_name:$line'") ;
	PbsDisplayErrorWithContext($pbs_config, $file_name,$line) ;
	die ;
	}

my @types ;
my ($depender_sub, $node_subs) ;

my($dependent_regex_definition, @dependencies) = @$depender_definition ;

#----------------------------------------
# creator definition, if any
#----------------------------------------
my $creator_sub ;

if('ARRAY' eq ref $dependent_regex_definition)
	{
	if('CODE' eq ref $dependent_regex_definition->[0])
		{
		my $creator_definition = $dependent_regex_definition ;
		my $creator            = shift @$creator_definition ;
		my @creator_args       = @$creator_definition ;
		
		# the creator sub receives the same arguments as a depender sub
		# note that the dependers sub is run before the creator sub
		$creator_sub = sub {$creator->(@_, @creator_args) ;} ;
		push @types, CREATOR ;
		
		$dependent_regex_definition = shift @dependencies ;
		}
	else
		{
		Carp::carp ERROR("Invalid creator definition, first element must be a creator sub reference at rule '$name' at '$file_name:$line'.") ;
		PbsDisplayErrorWithContext($pbs_config, $file_name,$line) ;
		die ;
		}
	}
	
# remove spurious undefs. those are allowed so one can write [ 'x' => undef]
@dependencies = grep {defined $_} @dependencies ;

my ($dependencies_evaluator, $dependent_matcher) ;

if('' eq ref $dependent_regex_definition)
	{
	PrintError "Depend: Unexpected non regex or sub matcher definition at file '$name' at '$file_name:$line'\n" ;
	PbsDisplayErrorWithContext($pbs_config, $file_name,$line) ;
	die ;
	}
elsif('Regexp' eq ref $dependent_regex_definition)
	{
	$dependent_matcher = sub
				{
				my ($dependent_to_check, $target_path, $display_regex) = @_ ;
				
				$target_path =~ s[/$][] ;
				
				$dependent_regex_definition=~ s/\%TARGET_PATH/$target_path/ ;
			
use Carp qw(cluck) ;
#print STDERR cluck ;
				if($display_regex && $dependent_to_check !~ /^__/)
					{
					PrintInfo2("${PBS::Output::indentation}$dependent_regex_definition $name:$file_name:$line\n") ;
					}
					
				return($dependent_to_check =~ $dependent_regex_definition) ;
				} ;
				
	$dependencies_evaluator = GenerateDependenciesEvaluator(\@dependencies, $name, $file_name, $line) ;
	}
elsif('CODE' eq ref $dependent_regex_definition)
	{
	$dependent_matcher =  sub
				{
				my ($dependent_to_check, $target_path, $display_regex) = @_ ;
				
				if($display_regex && $dependent_to_check !~ /^__/)
					{
					PrintInfo2("${PBS::Output::indentation}perl sub $name:$file_name:$line\n") ;
					}
					
				return($dependent_regex_definition->(@_)) ;
				} ;			
				
	$dependencies_evaluator = GenerateDependenciesEvaluator(\@dependencies, $name, $file_name, $line) ;
	}
else
	{
	PrintError "Depend: Unexpected matcher definition at file '$name' at '$file_name:$line'\n" ;
	PbsDisplayErrorWithContext($pbs_config, $file_name,$line) ;
	die ;
	}
	
#----------------------------------------
# depend subs
#----------------------------------------
my @depender_subs ;
my @post_depender_subs ;

for my $dependency (@dependencies)
	{
	if('ARRAY' eq ref $dependency)
		{
		#----------------------------------------
		# post dependency generator
		#----------------------------------------
		if('CODE' eq ref $dependency->[0])
			{
			my ($depender_sub, @depender_args)  = @$dependency ;
			
			push @post_depender_subs, sub {return ($depender_sub->(@_, @depender_args)) ;} ;
			}
		else
			{
			Carp::carp ERROR("Invalid depender definition, first element must be a depender sub reference at rule '$name' at '$file_name:$line'.") ;
			PbsDisplayErrorWithContext($pbs_config, $file_name,$line) ;
			die ;
			}
		}
	elsif('CODE' eq ref $dependency)
		{
		push @depender_subs, $dependency ;
		}
	elsif('' eq ref $dependency)
		{
		# normal text dependency, skip it.
		}
	else
		{
		Carp::carp ERROR("Invalid dependency definition at rule '$name' at '$file_name:$line'.") ;
		PbsDisplayErrorWithContext($pbs_config, $file_name,$line) ;
		die ;
		}
	
	}
#----------------------------------------
	
my @dependers ;
push @dependers, $dependencies_evaluator ; # dependers matching dependencies defined with strings (could contain $name ...)
push @dependers, @depender_subs ;
push @dependers, @post_depender_subs ;
push @dependers, $creator_sub if defined $creator_sub ;

$depender_sub = 
	sub 
		{
		my ($dependent, $config, $tree, $inserted_nodes, $rule_definition) = @_ ;
		
		my ($dependencies, $builder_override) ;

		my $node_name_matches_ddrr = 0 ;
		if ($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
			{
			for my $regex (@{$tree->{__PBS_CONFIG}{DISPLAY_DEPENDENCIES_REGEX}})
				{
				if($dependent =~ /$regex/)
					{
					$node_name_matches_ddrr = 1 ;
					last ;
					}
				}
			}
		
		if($dependent_matcher->($dependent, $config->{TARGET_PATH}, $node_name_matches_ddrr))
			{
			for my $depender (@dependers)
				{
				($dependencies, $builder_override) = $depender->
									(
									$dependent,
									$config,
									$tree,
									$inserted_nodes,
									$dependencies,
									$builder_override,
									$rule_definition,
									) ;
				}
				
			return($dependencies, $builder_override) ;
			}
		else
			{
			return([0, 'No match']) ;
			}
		} ;

return($depender_sub, $node_subs, \@types) ;
}

#----------------------------------------------------------------

sub GenerateDependenciesEvaluator
{
my ($rule_definition, $rule_name, $file_name, $line) = @_ ;

my $dependencies_evaluator = sub
	{
	my ($dependent, $config, $tree, $inserted_nodes, $dependencies, $builder_override) = @_ ;
	
	my ($basename, $path, $ext) = File::Basename::fileparse($dependent, ('\..*')) ;
	my $name = $basename . $ext ;
	$path =~ s/\/$// ;
	
	my @path_elements = split('/',$path) ;

	my @all_dependencies ;
	my $matched_perl_regex = 0 ;
	
	for my $dependency_definition (@$rule_definition)
		{
		if('' eq ref $dependency_definition)
			{
			my $dependency = $dependency_definition ;
			$dependency =~ s/\$name/$name/g ;
			$dependency =~ s/\$basename/$basename/g ;

			$dependency =~ s/\$path$_/$path_elements[$_]/eg for (0 .. $#path_elements) ;
			$dependency =~ s/\$path/$path/g ;

			$dependency =~ s/\$ext/$ext/g ;

			my $path_no_dot = $path ;
			$path_no_dot =~ s/^\.\/// ;

			$dependency =~ s/\$file_no_ext/$path_no_dot\/$basename/g ;
			
			push @all_dependencies, $dependency ;
			}
		}
	
	if(defined $dependencies && @$dependencies && $dependencies->[0] == 1 && @$dependencies > 1)
		{
		unshift @all_dependencies,	$dependencies->[1 .. (@{$dependencies} - 1)] ;
		}
	
	unshift @all_dependencies, 1 ; # this depender matched
	
	return(\@all_dependencies, $builder_override) ;
	} ;
	
return($dependencies_evaluator) ;
}

#-------------------------------------------------------------------------------

sub BuildDependentRegex
{
# Given a simplified dependent definition, this sub creates a perl regex

my $dependent_regex_definition = shift ;
my $error_message   = '' ;

return(0, 'Empty Regex definition') if $dependent_regex_definition eq '' ;

my ($dependent_name, $dependent_path, $dependent_ext) = File::Basename::fileparse($dependent_regex_definition,('\..*')) ;
$dependent_path =~ s|\\|/|g;

my $dependent_regex = $dependent_name . $dependent_ext ;
unless(defined $dependent_regex)
	{
	$error_message = "Invalid dependency definition" ;
	}
	
my $dependent_path_regex = $dependent_path ;
$dependent_path_regex =~ s/(?<!\\)\./\\./g ;

if($dependent_path_regex =~ tr/\*/\*/ > 1)
	{
	$error_message = "Error: only one '*' allowed in path specification $dependent_regex." ;
	}
	
$dependent_path_regex =~ s/\*/.*/ ;
$dependent_path_regex = '\./(?:.*/)*' if $dependent_path_regex eq '\./.*/' ;

if(!File::Spec->file_name_is_absolute($dependent_path_regex) && $dependent_path_regex !~ /^\\\.\// && $dependent_path_regex !~ /^\.\*/)
	{
	$dependent_path_regex = './' . $dependent_path_regex ;
	}
	
if($dependent_regex =~ /^.[^\*]*\*/)
	{
	$error_message = "Error: '*' only allowed at first position in dependent specification '$dependent_regex'." ;
	}
	
my $dependent_prefix_regex = '' ;
if($dependent_regex =~ s/^\*//)
	{
	$dependent_prefix_regex = '[^/]*' ;
	}
	
# finaly escape special characters
# $dependent_path_regex is a regex with *, we don't want to escape it.
# $dependent_prefix_regex is a regex with *, we don't want to escape it.
$dependent_regex = quotemeta($dependent_regex) ;

return
	(
	$error_message eq '',
	$error_message,
	$dependent_path_regex,
	$dependent_prefix_regex,
	$dependent_regex,
	) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Rules::Dependers -

=head1 DESCRIPTION

This package provides support function for B<PBS::Rules::Rules>

=head2 EXPORT

Nothing.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
