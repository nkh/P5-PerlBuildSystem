package PBS::Rules::Dependers ;

use PBS::Debug ;

use v5.10 ;

use strict ;
use warnings ;
use Data::TreeDumper ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(GenerateDepender GenerateDependerFromArray BuildDependentRegex) ;
our $VERSION = '0.01' ;

use File::Basename ;
use List::Util qw(any) ;

use PBS::PBSConfig ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Rules ;

use PBS::Rules::Dependers::Subpbs ;

#-------------------------------------------------------------------------------

sub GenerateDepender
{
my ($pbs_config, $config, $file_name, $line, $package, $class, $rule_types, $name, $depender_definition) =  @_ ;

my @depender_node_subs_and_types ; # types are a special case to display info about dependers

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
		PrintError "Rules: '$name' Invalid depender definition \n" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		die "\n" ;
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
			
			return  $code_reference->
					(
					$dependent,
					$config,
					$tree,
					$inserted_nodes,
					$rule_definition,
					) ;
			} ;
	
return($depender_sub) ;
}

#-------------------------------------------------------------------------------

sub GenerateDependerFromArray
{
# the returned depender calls 2 subs (also generated in this code)
# $dependent_matcher matches the dependent
# $dependencies_evaluator is to ,ie, replace $name by the node name ... it  is only called if the above sub matches.

my ($pbs_config, $config, $file_name, $line, $package, $class, $rule_types, $name, $depender_definition) = @_ ;

unless(@$depender_definition)
	{
	PrintError "Rules: '$name' has empty definition" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;

	die "\n" ;
	}

my @types ;
my ($depender_sub, $node_subs) ;

my($dependent_regex_definition, @dependencies) = @$depender_definition ;

# remove spurious undefs. those are allowed so one can write [ 'x' => undef ]
@dependencies = grep {defined $_} @dependencies ;

my $dependent_matcher ;

if('' eq ref $dependent_regex_definition)
	{
	PrintError "Depend: '$name' unexpected non regex or sub matcher definition\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	die "\n" ;
	}
elsif('Regexp' eq ref $dependent_regex_definition)
	{
	$dependent_matcher = sub
				{
				my ($pbs_config, $dependent_to_check, $target_path, $display_regex) = @_ ;
				
				$target_path =~ s[/$][] ;
				
				$dependent_regex_definition=~ s/\%TARGET_PATH/$target_path/ ;
			
				if( $dependent_to_check !~ /__PBS/ )
					{
					PrintInfo2
						"${PBS::Output::indentation}$dependent_regex_definition $name:"
						. GetRunRelativePath($pbs_config, $file_name)
						. ":$line\n" 
							if $display_regex ;
						
					return $dependent_to_check =~ $dependent_regex_definition ;
					}
				else
					{
					return 0 ;
					}
				} ;
	}
elsif('CODE' eq ref $dependent_regex_definition)
	{
	$dependent_matcher =  sub
				{
				my ($pbs_config, $dependent_to_check, $target_path, $display_regex) = @_ ;
				
				if( $dependent_to_check !~ /__PBS/ )
					{
					PrintInfo2
						"${PBS::Output::indentation}<< sub >> $name:"
						. GetRunRelativePath($pbs_config, $file_name)
						. ":$line\n" 
							if $display_regex ;
						
					return $dependent_regex_definition->(@_) ;
					}
				else
					{
					return 0 ;
					}
				} ;
	}
else
	{
	PrintError "Depend: '$name' unexpected non regex or sub matcher definition\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
	die "\n" ;
	}
	
my $dependencies_evaluator = GenerateDependenciesEvaluator(\@dependencies, $name, $file_name, $line) ;

#----------------------------------------
# depend subs
#----------------------------------------
my @depender_subs ;

for my $dependency (@dependencies)
	{
	if('CODE' eq ref $dependency)
		{
		push @depender_subs, $dependency ;
		}
	elsif('' eq ref $dependency)
		{
		# normal text dependency, skip it.
		}
	else
		{
		PrintError "Rules: '$name' invalid dependency definition" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
		die "\n" ;
		}
	
	}
#----------------------------------------
	
my @dependers = ($dependencies_evaluator, @depender_subs) ;

$depender_sub = 
	sub 
		{
		my ($dependent, $config, $tree, $inserted_nodes, $rule_definition) = @_ ;
		
		my $node_name_matches_ddrr = 0 ; 

		if ($tree->{__PBS_CONFIG}{DEBUG_DISPLAY_DEPENDENCY_REGEX})
			{
			$node_name_matches_ddrr = any { $dependent =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX}} ;
			$node_name_matches_ddrr = 0 if any { $dependent =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_REGEX_NOT}} ;
			$node_name_matches_ddrr = 1 if any { $rule_definition->{NAME} =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_RULE_NAME}} ;
			$node_name_matches_ddrr = 0 if any { $rule_definition->{NAME} =~ $_ } @{$pbs_config->{DISPLAY_DEPENDENCIES_RULE_NAME_NOT}} ;
			}

		if($dependent_matcher->($tree->{__PBS_CONFIG}, $dependent, $config->{TARGET_PATH}, $node_name_matches_ddrr))
			{
			my ($has_matched, @all_dependencies) ;

			for my $depender (@dependers)
				{
				my ($match, @dependencies) = $depender->
								(
								$dependent,
								$config,
								$tree,
								$inserted_nodes,
								$rule_definition,
								) ;
				
				$has_matched += $match ;
				push @all_dependencies, @dependencies if $match ;
				}

			return $has_matched, @all_dependencies ;
			}
		else
			{
			return 0, 'No match' ;
			}
		} ;

return($depender_sub, $node_subs, \@types) ;
}

#----------------------------------------------------------------

sub GenerateDependenciesEvaluator
{
my ($dependencies, $rule_name, $file_name, $line) = @_ ;

sub
	{
	my ($dependent, $config, $tree, $inserted_nodes) = @_ ;
	
	my ($basename, $path, $ext) = File::Basename::fileparse($dependent, ('\..*')) ;
	my $name = $basename . $ext ;
	$path =~ s/\/$// ;
	
	my @path_elements = split('/',$path) ;
	my @dependencies ;
	
	for my $ref (@$dependencies)
		{
		my $dependency = $ref ;
		if('' eq ref $dependency)
			{
			$dependency =~ s/\$name/$name/g ;
			$dependency =~ s/\$basename/$basename/g ;

			$dependency =~ s/\$path$_/$path_elements[$_]/eg for (0 .. $#path_elements) ;
			$dependency =~ s/\$path/$path/g ;

			$dependency =~ s/\$ext/$ext/g ;

			my $path_no_dot = $path ;
			$path_no_dot =~ s/^\.\/// ;

			$dependency =~ s/\$file_no_ext/$path_no_dot\/$basename/g ;
			
			push @dependencies, $dependency ;
			}
		}
	
	return 1, @dependencies ;
	}
}

#-------------------------------------------------------------------------------

sub BuildDependentRegex
{
# Given a simplified dependent definition, this sub creates a perl regex

my ($dependent_regex_definition) = @_ ;
my $error_message   = '' ;

return(0, 'Empty Regex definition') if $dependent_regex_definition eq '' ;

my ($dependent_name, $dependent_path, $dependent_ext) = File::Basename::fileparse($dependent_regex_definition,('\..*')) ;
$dependent_path =~ s|\\|/|g;

my $dependent_regex = $dependent_name . $dependent_ext ;
unless(defined $dependent_regex)
	{
	$error_message = "invalid dependency definition" ;
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
