
package PBS::Rules ;

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
our @EXPORT = qw(AddRule Rule rule AddRuleTo AddSubpbsRule AddSubpbsRules ReplaceRule ReplaceRuleTo RemoveRule BuildOk) ;
our $VERSION = '0.09' ;

use File::Basename ;

use PBS::Rules::Dependers ;
use PBS::Rules::Builders ;

use PBS::Shell ;
use PBS::PBSConfig ;
use PBS::Output ;
use PBS::Constants ;
use PBS::Plugin ;
use PBS::Rules::Creator ;

#-------------------------------------------------------------------------------

our %package_rules ;

#-------------------------------------------------------------------------------

sub GetPackageRules
{
my $package = shift ;
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

my @rules_names = @_ ;
my @all_rules   = () ;

PrintInfo("PBS: Get package rules: $package\n") if defined $pbs_config->{DEBUG_DISPLAY_RULES} ;

if(exists $package_rules{$package})
	{
	return($package_rules{$package}) ;
	}
else
	{
	return({}) ;
	}
}

#-------------------------------------------------------------------------------

sub ExtractRules
{
# extracts out the rules named in @rule_names from the rules definitions $rules

#todo: slave rules should be kept separately say in %slave_rules
#todo: rules should be kept in sorted order
#	this sub could be 1 line long => retun $rules->{@rules_namespace} ;
	
my ($pbs_config, $pbsfile, $rules, @rules_namespaces) = @_ ;

my (@creator_rules, @dependency_rules, @post_dependency_rules) ;

for my $rules_namespace (@rules_namespaces)
	{
	if(exists $rules->{$rules_namespace})
		{
		for my $rule (@{$rules->{$rules_namespace}})
			{
			my ($post_depend, $creator) ;
			
			for my $rule_type (@{$rule->{TYPE}})
				{
				$post_depend++ if $rule_type eq POST_DEPEND ;
				$creator++ if $rule_type eq CREATOR ;
				}
				
			if($creator)
				{
				push @creator_rules, $rule ;
				}
			else
				{
				if($post_depend)
					{
					push @post_dependency_rules, $rule ;
					}
				else
					{
					push @dependency_rules, $rule ;
					}
				}
			}
		}
	}

# reorder @dependency rules based on user defined rule order
# add the rules in a mini build system as defined by the user

my %rule_lookup ;

my ($rules_to_sort, $rule_to_sort_index, $sort_rules) = ({}, 0, 0) ;
for my $rule (@dependency_rules)
	{
	$rule_lookup{$rule->{NAME}} = $rule ;

	if( grep { $_ eq '__INTERNAL' } @{$rule->{TYPE}} )
		{
		# add once and leave as it doesn't get any order from user
		add_rule_to_order($rules_to_sort, \$rule_to_sort_index, $rule->{NAME}) ;
		next ;
		}

	my $matches_order = 0 ;
	for my $rule_type (@{$rule->{TYPE}})
		{
		if 
			(
			   $rule_type eq FIRST
			|| $rule_type eq LAST
			|| $rule_type =~ /^\s*before\s(.*)/i
			|| $rule_type =~ /^\s*first_plus\s(.*)/i
			|| $rule_type =~ /^\s*after\s(.*)/i
			|| $rule_type =~ /^\s*last_minus\s(.*)/i
			)
			{
			add_rule_to_order($rules_to_sort, \$rule_to_sort_index, $rule->{NAME}, split(/\s/, $rule_type)) ;
			$matches_order++;
			}

		}

	# rule with no order
	add_rule_to_order($rules_to_sort, \$rule_to_sort_index, $rule->{NAME}) unless $matches_order ;
	$sort_rules += $matches_order ;
	}

if($sort_rules)
	{
	PrintInfo "PBS: ordering rules, pbsfile: '$pbsfile'.\n" ;

	my ($order_pbsfile, $target) = order_rules($rules_to_sort, $rule_to_sort_index, $pbs_config->{DISPLAY_RULES_ORDERING}) ;

	my ($build_success, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) =
		PBS::FrontEnd::Pbs
			(
			COMMAND_LINE_ARGUMENTS => 
				[
				qw(--no_warning_matching_with_zero_dependencies -q -nh -w 0 --no_default_path_warning),
				qw(--no_pbs_response_file),
				$target
				],
			  
			PBS_CONFIG => {DEPEND_AND_CHECK => 1},
			PBSFILE_CONTENT => $order_pbsfile,
			) ;

	die ERROR("PBS: error ordering rules") . "\n" unless $build_success ;

	my @rules_order = map { $_->{__NAME} =~ m/\.\/(.*)/ ; $1 } grep { $_->{__NAME} !~ /^__/ } @$build_sequence ;
	PrintInfo3 DumpTree \@rules_order, 'Rules: ordered', DISPLAY_ADDRESS => 0 if $pbs_config->{DISPLAY_RULES_ORDERING} ;

	# re-order rules
	@dependency_rules = map{ $rule_lookup{$_} } grep { ! /^__/ } @rules_order ;
	}

return(@creator_rules, @dependency_rules, @post_dependency_rules) ;
}

sub order_rules
{
my ($rules, $rule_index, $show_rules) = @_ ;

use Data::TreeDumper ;
PrintInfo3 DumpTree $rules, 'rules' if $show_rules ;

my ($first_constant, $last_constant) = (FIRST, LAST) ; # can't use constant as hash key directly
die ERROR(DumpTree($rules->{$first_constant}, "Rule: multiple first")) ."\n" if exists $rules->{$first_constant} && @{ $rules->{$first_constant} } > 1 ;
die ERROR(DumpTree($rules->{$last_constant}, "Rule: multiple last")) ."\n" if exists $rules->{$last_constant} && @{ $rules->{$last_constant} } > 1 ;

my $first_rule = $rules->{$first_constant}[0] // FIRST;
my $last_rule = $rules->{$last_constant}[0] // LAST ;

my $pbsfile = '' ;
my $added_rule = 0 ;
my %dependents ;
my %one_rule ;

#last has no dependencies
$pbsfile .= "Rule $added_rule, ['$last_rule'] ; # last rule \n" ;
$dependents{$last_rule}++ ;
$added_rule++ ;

$one_rule{$last_rule} = [] ;

# indexed rules
if ($rule_index > 0) # we have at least one indexed rule
	{
	my $target = $rules->{0} ;
 	$pbsfile .= "Rule $added_rule, ['$target' => '$last_rule'] ; # indexed rule 1\n" ;
	$dependents{$target}++ ;
	$added_rule++ ;

	push @{$one_rule{$target}}, $last_rule ;
	}

for (reverse 1 .. $rule_index - 1)
	{
	$pbsfile .= "Rule $added_rule, ['$rules->{$_}' => '" . $rules->{$_ - 1} ."'] ; # indexed rule 2\n" ;
	$dependents{$rules->{$_}}++ ;
	$added_rule++ ;

	push @{$one_rule{$rules->{$_}}}, $rules->{$_ - 1} ;
	}

# first rule
for (0 .. $rule_index - 1)
	{
	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$rules->{$_}'] ; # first rule (indexed) 1\n" ;
	$dependents{$first_rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, $rules->{$_} ;
	}

$pbsfile .= "Rule $added_rule, ['$first_rule' => '$last_rule'] ; # first rule (last) 2\n" ;
$dependents{$first_rule}++ ;
$added_rule++ ;

push @{$one_rule{$first_rule}}, $last_rule ;

for my $rule (keys %{ $rules->{after} })
	{
	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$rule'] ; # first rule (after) 3\n" ;
	$dependents{$first_rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, $rule ;

	for (grep { $_ ne LAST} @{ $rules->{after}{$rule} })
		{
		$pbsfile .= "Rule $added_rule, ['$first_rule' => '$_'] ; # first rule (after) 4\n" ;
		$dependents{$first_rule}++ ;
		$added_rule++ ;

		push @{$one_rule{$first_rule}}, $_ ;
		}
	}

for my $rule (keys %{ $rules->{before} })
	{
	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$rule'] ; # first rule (before) 5\n" ;
	$dependents{$first_rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, $rule ;

	for (@{ $rules->{before}{$rule} })
		{
		if ($first_rule ne $_)
			{
			$pbsfile .= "Rule $added_rule, ['$first_rule' => '$_'] ; # first rule (before) 6\n" ;
			$dependents{$first_rule}++ ;
			$added_rule++ ;

			push @{$one_rule{$first_rule}}, $_ ;
			}
		}
	}

# after rules
for my $rule (keys %{ $rules->{after} })
	{
	for (@{ $rules->{after}{$rule} })
		{
		die ERROR("Rule: rule '$rule' can't be run after first rule '$first_rule'") . "\n" if $_ eq $first_rule ;
		die ERROR("Rule: rule '$rule' can't be run after first rule '$_'" ) . "\n" if $_ eq FIRST ;

		if ($_ eq LAST)
			{
			$pbsfile .= "Rule $added_rule, ['$rule' => '$last_rule'] ; # after rule 1\n" ;
			$dependents{$rule}++ ;
			$added_rule++ ;

			push @{$one_rule{$rule}}, $last_rule ;
			}
		else
			{
			$pbsfile .= "Rule $added_rule, ['$rule' => '$_'] ; # after rule 1\n" ;
			$dependents{$rule}++ ;
			$added_rule++ ;

			push @{$one_rule{$rule}}, $_ ;

			$pbsfile .= "Rule $added_rule, ['$_' => '$last_rule'] ; # after rule 2\n" ;
			$dependents{$_}++ ;
			$added_rule++ ;

			push @{$one_rule{$_}}, $last_rule ;
			}
		}

	$pbsfile .= "Rule $added_rule, ['$rule' => '$last_rule'] ; # after rule 3\n" ;
	$dependents{$rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$rule}}, $last_rule ;
	}

# before rules
for my $rule (keys %{ $rules->{before} })
	{
	for (@{ $rules->{before}{$rule} })
		{
		die ERROR("Rule: rule '$rule' can't be run before last rule '$last_rule'") . "\n" if $_ eq $last_rule ;
		die ERROR("Rule: rule '$rule' can't be run before last rule '$_'") . "\n" if $_ eq LAST ;

		$_ = $first_rule if $_ eq FIRST ;

		$pbsfile .= "Rule $added_rule, ['$_' => '$rule'] ; # before rule 1\n" ;
		$dependents{$_}++ ;
		$added_rule++ ;

		push @{$one_rule{$_}}, $rule ;

		$pbsfile .= "Rule $added_rule, ['$_' => '$last_rule'] ; # before rule 2\n" ;
		$dependents{$_}++ ;
		$added_rule++ ;

		push @{$one_rule{$_}}, $last_rule ;
		}

	$pbsfile .= "Rule $added_rule, ['$rule' => '$last_rule'] ; # before rule 3\n" ;
	$dependents{$rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$rule}}, $last_rule ;
	}

# first_plus rules
my @first_plus_indexes = sort {$a <=> $b } keys %{$rules->{first_plus}} ;
for (0 .. $#first_plus_indexes)
	{
	my $rule_index = $first_plus_indexes[$_] ;
	die ERROR(DumpTree($rules->{first_plus}{$rule_index}, "Rule: multiple entries at first plus index $rule_index")) . "\n" if @{ $rules->{first_plus}{$rule_index } } > 1 ;
	}

for (0 .. $#first_plus_indexes - 1)
	{
	my $rule_index = $first_plus_indexes[$_] ;
	my $next_rule_index = $first_plus_indexes[$_ + 1] ;

	# depend on each other
	$pbsfile .= "Rule $added_rule, ['$rules->{first_plus}{$rule_index}[0]' => '$rules->{first_plus}{$next_rule_index}[0]'] ; # first_plus rule 1\n" ;
	$added_rule++ ;

	push @{$one_rule{$rules->{first_plus}{$rule_index}[0]}}, $rules->{first_plus}{$next_rule_index}[0] ;
	}

if (@first_plus_indexes)
	{
	my $rule_index = $first_plus_indexes[0] ;

	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$rules->{first_plus}{$rule_index}[0]'] ; # first_plus rule 2\n" ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, $rules->{first_plus}{$rule_index}[0] ;

	my $last_rule_in_list = $rules->{first_plus}{$first_plus_indexes[$#first_plus_indexes]}[0] ;

	#all nodes except those in list and first are dependencies to last in list
	for (grep {$_ ne $first_rule } keys %dependents)
		{
		$pbsfile .= "Rule $added_rule, ['$last_rule_in_list' => '$_'] ; # first_plus rule 3\n" ;
		$added_rule++ ;

		push @{$one_rule{$last_rule_in_list}}, $_ ;
		}

	# add rules to dependents
	$dependents{$_}++ for (map{ @$_[0] } values %{$rules->{first_plus}}) ;
	}

# last_minus rules
my @last_minus_indexes = sort {$a <=> $b } keys %{$rules->{last_minus}} ;
for (0 .. $#last_minus_indexes)
	{
	my $rule_index = $last_minus_indexes[$_] ;
	die ERROR(DumpTree($rules->{last_minus}{$rule_index}, "Rule: multiple entries at last minus index $rule_index")) . "\n" if @{ $rules->{last_minus}{$rule_index } } > 1 ;
	}

for (reverse 1 .. $#last_minus_indexes)
	{
	my $rule_index = $last_minus_indexes[$_] ;
	my $previous_rule_index = $last_minus_indexes[$_ - 1] ;

	# depend on each other
	$pbsfile .= "Rule $added_rule, ['$rules->{last_minus}{$rule_index}[0]' => '$rules->{last_minus}{$previous_rule_index}[0]'] ; # last_minus rule 1\n" ;
	$added_rule++ ;

	push @{$one_rule{$rules->{last_minus}{$rule_index}[0]}}, $rules->{last_minus}{$previous_rule_index}[0] ;
	}

if (@last_minus_indexes)
	{
	# first rule in list depends on "last"
	my $rule_index = $last_minus_indexes[0] ;

	$pbsfile .= "Rule $added_rule, ['$rules->{last_minus}{$rule_index}[0]' => '$last_rule'] ; # last_minus rule 2\n" ;
	$added_rule++ ;

	push @{$one_rule{$rules->{last_minus}{$rule_index}[0]}}, $last_rule ;

	#all other rules depend on first in this list
	my $first_rule_in_list = $rules->{last_minus}{$last_minus_indexes[$#last_minus_indexes]}[0] ;

	for (grep {$_ ne $last_rule } keys %dependents)
		{
		$pbsfile .= "Rule $added_rule, ['$_' => '$first_rule_in_list'] ; # last_minus rule 3\n" ;
		$added_rule++ ;

		push @{$one_rule{$_}}, $first_rule_in_list ;
		}

	# add rules to dependents
	$dependents{$_}++ for (map{ @$_[0] } values %{$rules->{last_minus}}) ;
	}

PrintInfo3 DumpTree \%dependents, "dependents:", DISPLAY_ADDRESS => 0 if $show_rules ;

PrintInfo3 "pbsfile, rules: $added_rule\n$pbsfile\n" if $show_rules ;

my $merged_pbsfile = '' ;
for (sort keys %one_rule)
	{
	my %dependencies = map {$_, 1} @{$one_rule{$_}} ;
	my @dependencies = sort keys %dependencies ;

	$merged_pbsfile .= "rule $added_rule, ['$_' => " . join(', ', map { "'$_'" } @dependencies). "] ;\n" ;
	$added_rule++ ;
	}

PrintInfo3 "merged pbsfile, rules: " . scalar(keys %one_rule) . "\n$merged_pbsfile\n" if $show_rules ;

return $merged_pbsfile, $first_rule ; 
}

sub add_rule_to_order
{
my ($rules, $rule_index, $rule, $order, @rest) = @_ ;
$order //= 'indexed' ;

#PrintDebug "Rule: adding sort order: $rule, $order, @rest\n" ;

if (@_ == 3)
	{
	# added in rule order
	$rules->{$$rule_index++} = $rule ;
	}
elsif (@_ == 4)
	{
	# first or last, we can check later if multiple are defined

	die ERROR "Rule: wrong order '$order' at rule: @_\n" unless $order eq FIRST or $order eq LAST ;
	push @{$rules->{$order}}, $rule ;
	}
elsif (@_ == 5)
	{
	# before or after

	die ERROR "Rule: wrong order '$order' at rule: @_\n" unless $order eq 'before' or $order eq 'after' or $order eq 'last_minus' or $order eq 'first_plus' ;

	if ($order eq 'before' or $order eq 'after')
		{
		push @{$rules->{$order}{$rule}}, @rest ;
		}
	else
		{
		die ERROR "Rule: only one index allowed at rule: @_\n" if @rest > 1 ;

		push @{$rules->{$order}{$rest[0]}}, $rule ;
		}
	}
else
	{
	die ERROR DumpTree \@_, "Rule: wrong number of arguments to rule order function" ;
	}
}

#-------------------------------------------------------------------------------

sub AddRule
{
# Depender build from the rules will return an array reference containing:
# - the value 0 and a text message if no dependencies where found
# or 
# - the value 1 and a list of dependency names

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = 'User' ;

my @rule_definition = @_ ;

my $pbs_config = GetPbsConfig($package) ;
RunUniquePluginSub($pbs_config, 'AddRule', $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition ;
my ($name, $rule_type) ;

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		Carp::carp ERROR("Invalid rule at '$file_name:$line'. Expecting a name string, or an array ref containing types, as first argument.") ;
		PbsDisplayErrorWithContext($file_name,$line) ;
		die ;
		}
	}

my($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RegisterRule
	(
	$file_name, $line,
	$package, $class,
	$rule_type,
	$name,
	$depender_definition, $builder_sub, $node_subs,
	) ;
}

*Rule=\&AddRule ;
*rule=\&AddRule ;

#-------------------------------------------------------------------------------

sub AddRuleTo
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = shift ;
unless('' eq ref $class)
	{
	Carp::carp ERROR("Class name expected as first argument at '$file_name:$line'") ;
	PbsDisplayErrorWithContext($file_name,$line) ;
	die ;
	}

my @rule_definition = @_ ;

my $pbs_config = GetPbsConfig($package) ;
RunUniquePluginSub($pbs_config, 'AddRule', $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition;
my ($name, $rule_type) ;

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		Carp::carp ERROR("Invalid rule at: '$name'. Expecting a string or an array ref.") ;
		PbsDisplayErrorWithContext($file_name,$line) ;
		die ;
		}
	}

my ($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RegisterRule
	(
	$file_name, $line,
	$package, $class,
	$rule_type,
	$name,
	$depender_definition, $builder_sub, $node_subs,
	) ;
}

#-------------------------------------------------------------------------------

sub ReplaceRule
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = 'User' ;

my @rule_definition = @_ ;
my $pbs_config = GetPbsConfig($package) ;
RunUniquePluginSub($pbs_config, 'AddRule', $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition ;

my ($name, $rule_type) ;

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		Carp::carp ERROR("Invalid rule at: '$name'. Expecting a string or an array ref.") ;
		PbsDisplayErrorWithContext($file_name,$line) ;
		die ;
		}
	}

my($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RemoveRule($package, $class, $name) ;

RegisterRule
	(
	$file_name, $line,
	$package, $class,
	$rule_type,
	$name,
	$depender_definition, $builder_sub, $node_subs,
	) ;
}

#-------------------------------------------------------------------------------

sub ReplaceRuleTo
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

my $class = shift ;

my @rule_definition = @_ ;
my $pbs_config = GetPbsConfig($package) ;
RunUniquePluginSub($pbs_config, 'AddRule', $file_name, $line, \@rule_definition) ;

my $first_argument = shift @rule_definition ;
my ($name, $rule_type) ;

unless('' eq ref $class)
	{
	Carp::carp ERROR("Class name expected as first argument at: $name") ;
	PbsDisplayErrorWithContext($file_name,$line) ;
	die ;
	}

if('ARRAY' eq ref $first_argument)
	{
	$rule_type = $first_argument ;
	$name = shift @rule_definition ;
	}
else
	{
	if('' eq ref $first_argument)
		{
		$name = $first_argument ;
		$rule_type = [UNTYPED] ;
		}
	else
		{
		Carp::carp ERROR("Invalid rule at: '$name'. Expecting a string or an array ref.") ;
		PbsDisplayErrorWithContext($file_name,$line) ;
		die ;
		}
	}

my ($depender_definition, $builder_sub, $node_subs) = @rule_definition ;

RemoveRule($package,$class, $name) ;
RegisterRule
	(
	$file_name, $line,
	$package, $class,
	$rule_type,
	$name,
	$depender_definition, $builder_sub, $node_subs,
	) ;
}

#-------------------------------------------------------------------------------

sub RegisterRule
{
my ($file_name, $line, $package, $class, $rule_types, $name, $depender_definition, $builder_definition, $node_subs) = @_ ;

# this test is mainly to catch the error when the user forgot to write the rule name.
my %valid_types = map{ ("__$_", 1)} qw(FIRST LAST UNTYPED VIRTUAL LOCAL FORCED POST_DEPEND CREATOR INTERNAL IMMEDIATE_BUILD) ;
for my $rule_type (@$rule_types)
	{
	next if $rule_type =~ /^\s*indexed\s/i ;
	next if $rule_type =~ /^\s*before\s/i ;
	next if $rule_type =~ /^\s*first_plus\s/i ;
	next if $rule_type =~ /^\s*after\s/i ;
	next if $rule_type =~ /^\s*last_minus\s/i ;

	unless(exists $valid_types{$rule_type})
		{
		PrintError "Rule: invalid type '$rule_type' at rule '$name' at '$file_name:$line'\n" ;
		PbsDisplayErrorWithContext($file_name, $line) ;
		die ;
		}
	}
	
my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

if(exists $package_rules{$package}{$class})
	{
	#todo: replace loop below by hash lookup
	for my $rule (@{$package_rules{$package}{$class}})
		{
		if($rule->{NAME} eq $name)
			{
			Carp::carp ERROR("Rule: '$name' name is already used for for rule defined at $rule->{FILE}:$rule->{LINE}:$package\n") ;
			PbsDisplayErrorWithContext($file_name,$line) ;
			PbsDisplayErrorWithContext($rule->{FILE},$rule->{LINE}) ;
			die ;
			}
		}
	}

my %rule_type ;
for my $rule_type (@$rule_types)
	{
	$rule_type{$rule_type}++
	}

#>>>>>>>>>>>>>
# special handling for CREATOR  rules
# if a rule is [CREATOR] and no creator was defined in the depender definition,
# we put a creator in the depender definition and give the builder as argument to the creator

# this lets us write :
# AddRule [CREATOR], [ 'a' =>' b'], 'touch %FILE_TO_BUILD' ;
# and have the creator handle the digest part and call the builder to create the node

if($rule_type{__CREATOR})
	{
	if('ARRAY' eq ref $depender_definition)
		{
		if('ARRAY' eq ref $depender_definition->[0])
			{
			die ERROR "[CREATOR] rules can't have a creator defined within depender!\n" ;
			}
			
		if(defined $builder_definition)
			{
			#Let there be magic!
			unshift @$depender_definition, [GenerateCreator($builder_definition)] ;
			$builder_definition = undef ;
			}
		else
			{
			die ERROR "[CREATOR] rules must have a builder!\n" ;
			}
		}
	else
		{
		die ERROR "[CREATOR] rules must have depender in form ['object_to_create => dependencies]!\n" ;
		}
	}
#<<<<<<<<<<<<<<<<<<<<<<

my ($builder_sub, $node_subs1, $builder_generated_types) = GenerateBuilder(undef, $builder_definition, $package, $name, $file_name, $line) ;
$builder_generated_types ||= {} ;

my ($depender_sub, $node_subs2, $depender_generated_types) = GenerateDepender($file_name, $line, $package, $class, $rule_types, $name, $depender_definition) ;
$depender_generated_types  ||= [] ; 

my $origin = ":$package:$class:$file_name:$line";
	
for my $rule_type (@$rule_types)
	{
	$rule_type{$rule_type}++
	}
	
if($rule_type{__VIRTUAL} && $rule_type{__LOCAL})
	{
	PrintError("Rule can't be 'VIRTUAL' and 'LOCAL'.") ;
	PbsDisplayErrorWithContext($file_name,$line) ;
	die ;
	}
	
if($rule_type{__POST_DEPEND} && $rule_type{__CREATOR})
	{
	PrintError("Rule can't be 'POST_DEPEND' and 'CREATOR'.") ;
	PbsDisplayErrorWithContext($file_name,$line) ;
	die ;
	}

if($rule_type{__VIRTUAL} && $rule_type{__CREATOR})
	{
	PrintError("Rule can't be 'VIRTUAL' and 'CREATOR'.") ;
	PbsDisplayErrorWithContext($file_name,$line) ;
	die "\n" ;
	}
	
my $rule_definition = 
	{
	TYPE                => $rule_types,
	NAME                => $name,
	ORIGIN              => $origin,
	FILE                => $file_name,
	LINE                => $line,
	DEPENDER            => $depender_sub,
	TEXTUAL_DESCRIPTION => $depender_definition, # keep a visual on how the rule was defined,
	BUILDER             => $builder_sub,
	NODE_SUBS	    => $node_subs,
	%$builder_generated_types,
	} ;


if(defined $node_subs)
	{
	if('ARRAY' eq ref $node_subs)
		{
		for my $node_sub (@$node_subs)
			{
			if('CODE' ne ref $node_sub)
				{
				PrintDebug DumpTree $rule_definition, "Rule: definition" ;
				PrintError("Invalid node sub at rule '$name' @ '$file_name:$line'. Expecting a sub or a sub array.\n") ;
				PbsDisplayErrorWithContext($file_name,$line) ;
				die ;
				}
			}
		}
	elsif('CODE' eq ref $node_subs)
		{
		$node_subs = [$node_subs] ;
		}
	else
		{
		PrintDebug DumpTree \@_, "Rule: RegisterRule" ;
		PrintError("Invalid node sub at rule '$name' @ '$file_name:$line'. Expecting a sub or a sub array.\n") ;
		PbsDisplayErrorWithContext($file_name,$line) ;
		die ;
		}
	}
else
	{
	$node_subs = [] ;
	}
	
push @$node_subs, @$node_subs1 if $node_subs1 ;
push @$node_subs, @$node_subs2 if $node_subs2 ;

$rule_definition->{NODE_SUBS} = $node_subs if @$node_subs ;

if(defined $pbs_config->{DEBUG_DISPLAY_RULES})
	{
	my $class_info = "[$class" ;
	$class_info .= ' POST_DEPEND' if $rule_type{__POST_DEPEND} ;
	$class_info .= ' CREATOR'     if $rule_type{__CREATOR};
	$class_info .= ']' ;
		
	if('HASH' eq ref $depender_definition)
		{
		PrintInfo("PBS: Adding subpbs rule: '$name' $class_info")  ;
		}
	else
		{
		PrintInfo("PBS: Adding rule: '$name' $class_info")  ;
		}
		
	PrintInfo(DumpTree($rule_definition)) if defined $pbs_config->{DEBUG_DISPLAY_RULE_DEFINITION} ;
	PrintInfo("\n")  ;
	}

push @{$package_rules{$package}{$class}}, $rule_definition ;

return($rule_definition) ;
}

#-------------------------------------------------------------------------------

sub RemoveRule
{
# if no name is given, all the rules in the package-class are removed.

my $package = shift ;
my $class   = shift ;
my $name    = shift ;

if(defined $name)
	{
	if(exists $package_rules{$package}{$class})
		{
		my $rules = $package_rules{$package}{$class} ;
		
		my @new_rules;
		
		for my $rule (@$rules)
			{
			if($rule->{NAME} !~ /^$name($|(\s+:))/)
				{
				push @new_rules, $rule ;
				}
			else
				{
				#~print "Removing rule: '$rule->{NAME}'\n" ; 
				}
			}
			
		$package_rules{$package}{$class} = \@new_rules ;
		}
	}
else
	{
	delete $package_rules{$package}{$class} ;
	}
	
$name ||= 'NO_NAME!' ;	

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;
PrintInfo("PBS: Removing Rule: ${package}::${class}::${name}\n") if defined $pbs_config->{DEBUG_DISPLAY_RULES} ;
}

#-------------------------------------------------------------------------------

sub DisplayAllRules
{
PrintInfo(DumpTree(\%package_rules, 'PBS: All rules:')) ;
}

#-------------------------------------------------------------------------------

use Sub::Name ;

sub BuildOk
{
# Syntactic sugar, this function can be called instead for 
# defining a closure or giving a sub ref

my $message = shift ;
my $print   = shift ; 

my ($package, $file_name, $line) = caller() ;

return subname BuildOk => sub
	{
	#my ($config, $file_to_build, $dependencies, $triggering_dependencies, $file_tree, $inserted_nodes) = @_ ;
	
	PrintInfo3("BuildOk: $message\n") if defined $message ;
	return(1, $message // 'BuildOk: no message') ;
	} ;
}

#-------------------------------------------------------------------------------
sub AddSubpbsRules
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

for(@_)
	{
	__AddSubpbsRule($package, $file_name, $line, $_) ;
	}
}

sub AddSubpbsRule
{
my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

__AddSubpbsRule($package, $file_name, $line, \@_) ;
}

sub __AddSubpbsRule
{
# Syntactic sugar, this function can be called instead for 
# AddRule .. { subpbs_definition}
# the compulsory arguments come first, then one can pass 
# key-value pairs as in a normal subpbs definition

my ($package, $file_name, $line, $rule_definition) = @_ ;

my $pbs_config = GetPbsConfig($package) ;

my ($rule_name, $node_regex, $Pbsfile, $pbs_package, @other_setup_data) 
	= RunUniquePluginSub($pbs_config, 'AddSubpbsRule', $file_name, $line, $rule_definition) ;

RegisterRule
	(
	$file_name, $line, $package,
	'User',
	[UNTYPED],
	$rule_name,
	{
	  NODE_REGEX         => $node_regex,
	  PBSFILE            => $Pbsfile,
	  PACKAGE            => $pbs_package,
	  @other_setup_data,
	  },
	undef,
	undef,
	) ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Rules - Manipulate PBS rules

=head1 SYNOPSIS

	# within a Pbsfile
	AddRule 'all_lib', ['all' => qw(lib.lib)], BuildOk() ;
	AddRule 'test', ['test' => 'all', 'test1', 'test2'] ;
	

=head1 DESCRIPTION

This modules defines a set of functions to add, remove and replace B<PBS> rules. B<PBS> rules can be written
in pure perl code or with a syntax ressembling that of I<make>. I<RegisterRule> converts the I<make> like 
definitions to perl code when needed.

=head2 EXPORT

	AddRule AddRuleTo 
	AddSubpbsRule 
	RemoveRule 
	ReplaceRule ReplaceRuleTo 
	BuildOk

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut
