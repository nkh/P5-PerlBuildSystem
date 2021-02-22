
package PBS::Rules::Order ;

use 5.006 ;

use strict ;
use warnings ;
use Data::TreeDumper ;
use Carp ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

use Time::HiRes qw(gettimeofday tv_interval) ;

use PBS::Output ;
use PBS::Constants ;

sub OrderRules
{
# reorder @dependency rules based on user defined rule order
# add the rules in a mini build system as defined by the user

my ($pbs_config, $pbsfile, @dependency_rules) = @_ ;

my %rule_lookup ;

my ($rules_to_sort, $rule_to_sort_index, $sort_rules, @rule_invalid_name) = ({}, 0, 0) ;
for my $rule (@dependency_rules)
	{
	$rule_lookup{$rule->{NAME}} = $rule ;

	if( grep { $_ eq '__INTERNAL' } @{$rule->{TYPE}} )
		{
		# add once and leave as it doesn't get any order from user
		add_rule_to_order($rules_to_sort, \$rule_to_sort_index, $rule->{NAME}, $rule->{LINE}) ;
		next ;
		}

	my $matches_order = 0 ;
	for my $rule_type (@{$rule->{TYPE}}, map { "match_after $_" } PBS::Rules::Scope::GetRuleBefore($rule->{PACKAGE}, $rule->{NAME}))
		{
		my $order_regex = join '|', qw(indexed before first_plus after match_after last_minus) ;
	
		if ( $rule_type eq FIRST || $rule_type eq LAST || $rule_type =~ /^\s*$order_regex\s+.*/i)
			{
			add_rule_to_order($rules_to_sort, \$rule_to_sort_index, $rule->{NAME}, $rule->{LINE}, split(/\s/, $rule_type)) ;
			$matches_order++;

			push @{$rule->{BEFORE}}, split(/\s/, $1) if ($rule_type =~ /^\s*match_after\s+(.*)/i)
			}
		elsif( $rule_type eq MULTI )
			{
			$rule->{MULTI}++ ;
			}
		}

	# rule with no order
	add_rule_to_order($rules_to_sort, \$rule_to_sort_index, $rule->{NAME}, $rule->{LINE} // '?') unless $matches_order ;
	$sort_rules += $matches_order ;

	push @rule_invalid_name, $rule if $rule->{NAME} !~ /^[0-9a-zA-Z_]+$/ ;
	}

if($sort_rules)
	{
	my $short_pbsfile = GetRunRelativePath($pbs_config, $pbsfile) ;

	if(@rule_invalid_name)
		{
		PrintError "Rules: error ordering '$short_pbsfile', found rule names not matching /[0-9a-zA-Z_]+/:\n" ;

		PbsDisplayErrorWithContext $pbs_config, $pbsfile, $_->{LINE} for @rule_invalid_name ;
		die "\n" ;
		}

	my $t0_order = [gettimeofday] ;

	my ($order_pbsfile, $target, $topo_rules) = order_rules($rules_to_sort, $rule_to_sort_index, $pbs_config) ;
	my $generation_time = tv_interval ($t0_order, [gettimeofday]) ;

	my ($build_success, @rules_order) = topo_sort($topo_rules) ;

	my $t = $PBS::Output::indentation;
	my $virtual_pbsfile_name = "$t${t}virtual pbsfile: 'rule_ordering'\n$t$t${t} rules from '$pbs_config->{PBSFILE}'\n" ;

	unless($build_success)
		{
		my ($build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) ;

		($build_success, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence) =
		PBS::FrontEnd::Pbs
			(
			COMMAND_LINE_ARGUMENTS => [ $target , '--no_pbs_response_file', '--no_default_path_warning' ],
			  
			PBS_CONFIG => 
				{
				VIRTUAL_PBSFILE_TARGET => 'rule_ordering',
				VIRTUAL_PBSFILE_NAME => $virtual_pbsfile_name,
				WARP => 0,
				DEPEND_AND_CHECK => 1,
				QUIET => 1,
				#DISPLAY_NO_STEP_HEADER => 1,
				NO_WARNING_MATCHING_WITH_ZERO_DEPENDENCIES => 1,
				},

			PBSFILE_CONTENT => $order_pbsfile,
			) ;

		@rules_order = map { $_->{__NAME} =~ m/\.\/(.*)/ ; $1 } grep { $_->{__NAME} !~ /^__/ } @$build_sequence
			if $build_success ;
		}

	die ERROR("Rule: error ordering for '$short_pbsfile'.") . "\n" unless $build_success ;

	PrintInfo(sprintf("Rule: '$short_pbsfile' ordering time: %0.4f, generation: %0.4f\n", tv_interval ($t0_order, [gettimeofday]), $generation_time))
		 if $pbs_config->{DISPLAY_RULES_TO_ORDER} ;

	PrintInfo3 DumpTree \@rules_order, "Rules: ordered for '$short_pbsfile'", DISPLAY_ADDRESS => 0 if $pbs_config->{DISPLAY_RULES_ORDER} ;

	# re-order rules
	@dependency_rules = map{ $rule_lookup{$_} } grep { ! /^__/ } @rules_order ;
	}

@dependency_rules ;
}

sub order_rules
{
my ($rules, $rule_index, $pbs_config) = @_ ;
my $show_rules = $pbs_config->{DISPLAY_RULES_ORDERING} ;

use Data::TreeDumper ;
PrintInfo3 DumpTree $rules, 'rules', DISPLAY_ADDRESS => 0 if $show_rules ;

my ($first_constant, $last_constant) = (FIRST, LAST) ; # can't use constant as hash key directly
die ERROR(DumpTree($rules->{$first_constant}, "Rule: multiple first")) ."\n" if exists $rules->{$first_constant} && @{ $rules->{$first_constant}{rules} } > 1 ;
die ERROR(DumpTree($rules->{$last_constant}, "Rule: multiple last")) ."\n" if exists $rules->{$last_constant} && @{ $rules->{$last_constant}{rules} } > 1 ;

my $first_rule = $rules->{$first_constant}{rules}[0] // FIRST;
my $first_rule_line = (keys %{ $rules->{$first_constant}{lines}})[0] // '?' ;

my $last_rule = $rules->{$last_constant}{rules}[0] // LAST ;
my $last_rule_line = (keys %{$rules->{$last_constant}{lines}})[0] // '?' ;

my $pbsfile = '' ;
my $added_rule = 0 ;
my %dependents ;
my %one_rule ;

#last has no dependencies
$pbsfile .= "Rule $added_rule, ['$last_rule'] ; # last rule @ $last_rule_line\n" if $show_rules ;
$dependents{$last_rule}++ ;
$added_rule++ ;

$one_rule{$last_rule} = [] ;

# indexed rules
if ($rule_index > 0) # we have at least one indexed rule
	{
	my $target = $rules->{0}{rule} ;
	my $target_line = $rules->{0}{line} ;

	$pbsfile .= "Rule $added_rule, ['$target' => '$last_rule'] ; # indexed rule 1 @ $target_line\n" if $show_rules ;
	$dependents{$target}++ ;
	$added_rule++ ;

	push @{$one_rule{$target}}, {dependency =>$last_rule, line => $target_line} ;
	}

for (reverse 1 .. $rule_index - 1)
	{
	my $target_line = $rules->{$_}{line} ;
	my $target = $rules->{$_}{rule} ;
	my $dependency = $rules->{$_ - 1}{rule} ;

	$pbsfile .= "Rule $added_rule, ['$target' => '$dependency'] ; # indexed rule 2 @ $target_line\n" if $show_rules ;
	$dependents{$target}++ ;
	$added_rule++ ;

	push @{$one_rule{$target}}, {dependency => $dependency, line => $target_line} ;
	}

# first rule
for (0 .. $rule_index - 1)
	{
	my $target_line = $rules->{$_}{line} ;
	my $dependency = $rules->{$_}{rule} ;

	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$dependency'] ; # first rule (indexed) 1 @ $target_line\n" if $show_rules ;
	$dependents{$first_rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, {dependency => $dependency, line => $target_line} ;
	}

$pbsfile .= "Rule $added_rule, ['$first_rule' => '$last_rule'] ; # first rule (last) 2 @ $first_rule_line\n" if $show_rules ;
$dependents{$first_rule}++ ;
$added_rule++ ;

push @{$one_rule{$first_rule}}, {dependency => $last_rule, line => $first_rule_line} ;

for my $rule (keys %{ $rules->{after} })
	{
	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$rule'] ; # first rule (after) 3 @ $first_rule_line\n" if $show_rules ;
	$dependents{$first_rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, {dependency => $rule, line => $first_rule_line} ;

	for (grep { $_ ne LAST} @{ $rules->{after}{$rule}{rules} })
		{
		my $target_line = join (', ', sort keys %{ $rules->{after}{$rule}{lines} }) ;

		$pbsfile .= "Rule $added_rule, ['$first_rule' => '$_'] ; # first rule (after) 4 @ $target_line\n" if $show_rules ;
		$dependents{$first_rule}++ ;
		$added_rule++ ;

		push @{$one_rule{$first_rule}}, {dependency => $_, line => $target_line} ;
		}
	}

for my $rule (keys %{ $rules->{before} })
	{
	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$rule'] ; # first rule (before) 5 $first_rule_line\n" if $show_rules ;
	$dependents{$first_rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, {dependency => $rule, line => $first_rule_line} ;

	for (@{ $rules->{before}{$rule}{rules} })
		{
		if ($first_rule ne $_)
			{
			my $target_line = join (', ', sort keys %{ $rules->{before}{$rule}{lines} }) ;

			$pbsfile .= "Rule $added_rule, ['$first_rule' => '$_'] ; # first rule (before) 6 @ $target_line\n" if $show_rules ;
			$dependents{$first_rule}++ ;
			$added_rule++ ;

			push @{$one_rule{$first_rule}}, {dependency => $_, line => $target_line} ;
			}
		}
	}

# after rules
for my $rule (keys %{ $rules->{after} })
	{
	my $target_line = join (', ', sort keys %{ $rules->{after}{$rule}{lines} }) ;

	for (@{ $rules->{after}{$rule}{rules} })
		{
		die ERROR("Rule: rule '$rule' can't be run after first rule '$first_rule'") . "\n" if $_ eq $first_rule ;
		die ERROR("Rule: rule '$rule' can't be run after first rule '$_'" ) . "\n" if $_ eq FIRST ;

		if ($_ eq LAST)
			{
			$pbsfile .= "Rule $added_rule, ['$rule' => '$last_rule'] ; # after rule 1 @ $target_line\n" if $show_rules ;
			$dependents{$rule}++ ;
			$added_rule++ ;

			push @{$one_rule{$rule}}, {dependency => $last_rule, line => $target_line} ;
			}
		else
			{
			$pbsfile .= "Rule $added_rule, ['$rule' => '$_'] ; # after rule 1 @ $target_line\n" if $show_rules ;
			$dependents{$rule}++ ;
			$added_rule++ ;

			push @{$one_rule{$rule}}, {dependency => $_, line => $target_line} ;

			$pbsfile .= "Rule $added_rule, ['$_' => '$last_rule'] ; # after rule 2 @ $target_line\n" if $show_rules ;
			$dependents{$_}++ ;
			$added_rule++ ;

			push @{$one_rule{$_}}, {dependency => $last_rule, line => $target_line} ;
			}
		}

	$pbsfile .= "Rule $added_rule, ['$rule' => '$last_rule'] ; # after rule 3 @ $target_line\n" if $show_rules ;
	$dependents{$rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$rule}}, {dependency => $last_rule, line => $target_line} ;
	}

# before rules
for my $rule (keys %{ $rules->{before} })
	{
	my $target_line = join (', ', sort keys %{ $rules->{before}{$rule}{lines} }) ;

	for (@{ $rules->{before}{$rule}{rules} })
		{
		die ERROR("Rule: rule '$rule' can't be run before last rule '$last_rule'") . "\n" if $_ eq $last_rule ;
		die ERROR("Rule: rule '$rule' can't be run before last rule '$_'") . "\n" if $_ eq LAST ;

		$_ = $first_rule if $_ eq FIRST ;

		$pbsfile .= "Rule $added_rule, ['$_' => '$rule'] ; # before rule 1 @ $target_line\n" if $show_rules ;
		$dependents{$_}++ ;
		$added_rule++ ;

		push @{$one_rule{$_}}, {dependency => $rule, line => $target_line} ;

		$pbsfile .= "Rule $added_rule, ['$_' => '$last_rule'] ; # before rule 2 @ $target_line\n" if $show_rules ;
		$dependents{$_}++ ;
		$added_rule++ ;

		push @{$one_rule{$_}}, {dependency => $last_rule, line => $target_line} ;
		}

	$pbsfile .= "Rule $added_rule, ['$rule' => '$last_rule'] ; # before rule 3 @ $target_line\n" if $show_rules ;
	$dependents{$rule}++ ;
	$added_rule++ ;

	push @{$one_rule{$rule}}, {dependency => $last_rule, line => $target_line} ;
	}

# first_plus rules
for (sort {$a <=> $b } keys %{$rules->{first_plus}{rules}})
	{
	die ERROR(DumpTree($rules->{first_plus}{rules}{$_}, "Rule: multiple entries at first plus index $_\n"))
		if @{ $rules->{first_plus}{rules}{$_ } } > 1 ;
	}

my @first_plus_indexes = sort {$a <=> $b } keys %{$rules->{first_plus}{rules}} ;
for (0 .. $#first_plus_indexes - 1)
	{
	my $rule_index = $first_plus_indexes[$_] ;
	my $next_rule_index = $first_plus_indexes[$_ + 1] ;

	my $target_line = join (', ', sort keys %{ $rules->{first_plus}{lines}{$rule_index} }) ;
	my $target = $rules->{first_plus}{rules}{$rule_index}[0] ;
	my $dependency = $rules->{first_plus}{rules}{$next_rule_index}[0] ;

	# depend on each other
	$pbsfile .= "Rule $added_rule, ['$target' => '$dependency'] ; # first_plus rule 1 @ $target_line\n" if $show_rules ;
	$added_rule++ ;

	push @{$one_rule{$target}}, {dependency => $dependency, line => $target_line} ;
	}

if (@first_plus_indexes)
	{
	my $target_line = join (', ', sort keys %{ $rules->{first_plus}{lines}{$rule_index} }) ;
	my $rule_index = $first_plus_indexes[0] ;
	my $dependency = $rules->{first_plus}{rules}{$rule_index}[0] ;

	$pbsfile .= "Rule $added_rule, ['$first_rule' => '$dependency'] ; # first_plus rule 2 @ $target_line\n" if $show_rules ;
	$added_rule++ ;

	push @{$one_rule{$first_rule}}, {dependency => $dependency, line => $target_line} ;

	my $last_rule_in_list = $rules->{first_plus}{rules}{$first_plus_indexes[$#first_plus_indexes]}[0] ;

	#all nodes except those in list and first are dependencies to last in list
	for (grep {$_ ne $first_rule } keys %dependents)
		{
		$pbsfile .= "Rule $added_rule, ['$last_rule_in_list' => '$_'] ; # first_plus rule 3 @ $target_line\n" if $show_rules ;
		$added_rule++ ;

		push @{$one_rule{$last_rule_in_list}}, {dependency => $_, line => $target_line} ;
		}

	# add rules to dependents
	$dependents{$_}++ for (map{ $_->[0] } values %{$rules->{first_plus}{rules}}) ;
	}

# last_minus rules
for (sort {$a <=> $b } keys %{$rules->{last_minus}{rules}})
	{
	die ERROR(DumpTree($rules->{last_minus}{rules}{$_}, "Rule: multiple entries at last minus index $_\n"))
		if @{ $rules->{last_minus}{rules}{$_ } } > 1 ;
	}

my @last_minus_indexes = sort {$a <=> $b } keys %{$rules->{last_minus}{rules}} ;
for (reverse 1 .. $#last_minus_indexes)
	{
	my $rule_index = $last_minus_indexes[$_] ;
	my $previous_rule_index = $last_minus_indexes[$_ - 1] ;

	my $target_line = join (', ', sort keys %{ $rules->{last_minus}{lines}{$rule_index} }) ;
	my $target = $rules->{last_minus}{rules}{$rule_index}[0] ;
	my $dependency = $rules->{last_minus}{rules}{$previous_rule_index}[0] ;

	# depend on each other
	$pbsfile .= "Rule $added_rule, ['$target' => '$dependency'] ; # last_minus rule 1 @ $target_line\n" if $show_rules ;
	$added_rule++ ;

	push @{$one_rule{$target}}, {dependency => $dependency, line => $target_line} ;
	}

if (@last_minus_indexes)
	{
	# first rule in list depends on "last"
	my $rule_index = $last_minus_indexes[0] ;

	my $target_line = join (', ', sort keys %{ $rules->{last_minus}{lines}{$rule_index} }) ;
	my $target = $rules->{last_minus}{rules}{$rule_index}[0] ;

	$pbsfile .= "Rule $added_rule, ['$target' => '$last_rule'] ; # last_minus rule 2 @ $target_line\n" if $show_rules ;
	$added_rule++ ;

	push @{$one_rule{$target}}, {dependency => $last_rule, line => $target_line} ;

	#all other rules depend on first in this list
	my $first_rule_in_list = $rules->{last_minus}{rules}{$last_minus_indexes[$#last_minus_indexes]}[0] ;
	$target_line = join (', ', sort keys %{ $rules->{last_minus}{lines}{$last_minus_indexes[$#last_minus_indexes]} }) ;

	for (grep {$_ ne $last_rule } keys %dependents)
		{
		$pbsfile .= "Rule $added_rule, ['$_' => '$first_rule_in_list'] ; # last_minus rule 3 @ $target_line\n" if $show_rules ;
		$added_rule++ ;

		push @{$one_rule{$_}}, {dependency => $first_rule_in_list, line => $target_line} ;
		}

	# add rules to dependents
	$dependents{$_}++ for (map{ $_->[0] } values %{$rules->{last_minus}{rules}}) ;
	}

PrintInfo3 DumpTree \%dependents, "dependents:", DISPLAY_ADDRESS => 0 if $show_rules ;

PrintInfo3 "pbsfile, rules: $added_rule\n$pbsfile\n" if $show_rules ;

my @topo_rules ;
my $merged_pbsfile = '' ;
for (sort keys %one_rule)
	{
	my %dependencies = map {$_->{dependency}, 1} @{ $one_rule{$_} } ;
	my @dependencies = sort keys %dependencies ;

	my %lines = map {$_->{line}, 1} @{ $one_rule{$_}} ;
	my $lines = keys %lines > 1 ? "lines: " : "line: " ;
	$lines .= join(', ',  sort keys %lines) ;

	push @topo_rules, [$_ , @dependencies] ;
	$merged_pbsfile .= "rule $added_rule, ['$_' => " . join(', ', map { "'$_'" } @dependencies). "] ; # $lines\n" ;
	$added_rule++ ;
	}

PrintInfo3 "merged pbsfile, rules: " . scalar(keys %one_rule) . "\n$merged_pbsfile\n" if $show_rules ;

return $merged_pbsfile, $first_rule, \@topo_rules ; 
}

sub add_rule_to_order
{
my ($rules, $rule_index, $rule, $rule_line, $order, @rest) = @_ ;
$order //= 'indexed' ;

#PrintDebug "Rule: adding sort order: $rule, $order, @rest\n" ;

if (@_ == 4)
	{
	# added in rule order
	$rules->{$$rule_index}{line} = $rule_line ;
	$rules->{$$rule_index++}{rule} = $rule ;
	}
elsif (@_ == 5)
	{
	# first or last, we can check later if multiple are defined

	unless ( $order eq FIRST or $order eq LAST)
		{
		PrintError DumpTree(\@_, "Rule: wrong order '$order' at rule:", MAX_DEPTH => 2) ;
		die "\n" ;
		}

	$rules->{$order}{lines}{$rule_line}++ ;
	push @{$rules->{$order}{rule}}, $rule ;
	}
elsif (@_ == 6)
	{
	# before or after or match_after

	unless
		(
		   $order eq 'before'
		or $order eq 'match_after'
		or $order eq 'after'
		or $order eq 'last_minus'
		or $order eq 'first_plus'
		)
		{
		PrintError DumpTree(\@_, "Rule: wrong order '$order' at rule:", MAX_DEPTH => 2) ;
		die "\n" ;
		}

	if ($order eq 'before' or $order eq 'after' or $order eq 'match_after')
		{
		$order = 'after' if $order eq 'match_after' ; # handle them equally

		$rules->{$order}{$rule}{lines}{$rule_line}++ ;
		push @{$rules->{$order}{$rule}{rules}}, @rest ;
		}
	else
		{
		if(@rest > 1)
			{
			PrintError(DumpTree(\@_, "Rule: only one index allowed at rule:", MAX_DEPTH => 2)) ;
			die "\n" ;
			}

		$rules->{$order}{lines}{$rest[0]}{$rule_line}++ ;
		push @{$rules->{$order}{rules}{$rest[0]}}, $rule ;
		}
	}
else
	{
	die ERROR DumpTree \@_, "Rule: wrong number of arguments to rule order function" ;
	}
}

sub topo_sort
{
my ($rules) = @_ ;

my %ba;

for my $rule (@{$rules})
	{
	my ($node, @deps) = @{$rule} ;

	for my $dep (@deps)
		{
		$ba{$node}{$dep}++ ;
		$ba{$dep} ||= {};
		}
	}

my @ordered ;

while ( my @afters = sort grep { ! %{ $ba{$_} } } keys %ba )
	{
	push @ordered, @afters;

	delete @ba{@afters};
	delete @{$_}{@afters} for values %ba;
	}

return !scalar(%ba), @ordered
}


