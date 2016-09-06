
package PBS::Debug ;

use 5.006 ;

use strict ;
use warnings ;
use Data::Dumper ;
use Data::TreeDumper ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(
		pbs_jump_in_debugger p_j
		pbs_no_jump_in_debugger p_nj
		pbs_remove_breakpoints p_B
		pbs_help p_h
		pbs_list_breakpoints p_L
		pbs_activate_breakpoints p_ab
		pbs_deactivate_breakpoints p_db
		pbs_tree p_t
		pbs_dependencies p_d
		pbs_node p_n
		
		EnableDebugger AddBreakpoint RemoveBreakpoints ListBreakpoints
		ActivateBreakpoints DeactivateBreakpoints 
		ActivatePerlDebugger DeactivatePerlDebugger 
		CheckBreakpoint
		) ;

our $VERSION = '0.04' ;

use PBS::PBS ;
use PBS::Output ;
use PBS::Information ; 

#-------------------------------------------------------------------------------

our $debug_enabled = 0 ;

#-------------------------------------------------------------------------------

sub EnableDebugger
{
my $switch = shift ;
my $file= shift ; # can contains breakpoint definitions

if($file ne '')
	{
	unless (my $return = do $file ) 
		{
		die ERROR "couldn't parse '$file ': $@" if $@;
		die ERROR "couldn't do '$file ': $!"    unless defined $return;
		die ERROR "couldn't run '$file '"       unless $return;
		}
	
	$debug_enabled = 1 ;
	}
}

#-------------------------------------------------------------------------------

sub PrintBanner
{
PrintDebug "PBS debugger support version $VERSION available. Type 'pbs_help' for help.\n\n" ;
}

#-------------------------------------------------------------------------------

sub setup_debugger_run
{
my ($pbs_config) = @_ ;

return unless *DB::DB{CODE} ;

PrintBanner() ;

# modify some run time options
undef $pbs_config->{DISPLAY_PROGRESS_BAR} ;
$PBS::Shell::silent_commands= 0 ;
$PBS::Shell::silent_commands_output = 0 ;
undef $pbs_config->{DISPLAY_NO_BUILD_HEADER}  ;
}

#-------------------------------------------------------------------------------

sub pbs_help
{
PrintDebug <<EOH ;
commands: (no argument starts wizard if exists. RX means commands accepts a regex)

pbs_list_breakpoints or p_L           list breakpoints (RX)
pbs_activate_breakpoints or p_ab      activate breakpoints (RX)
pbs_deactivate_breakpoints or p_db    deactivate breakpoints (RX)
pbs_jump_in_debugger or p_j           breakpoints will jump into perl debugger (RX)
pbs_no_jump_in_debugger or p_nj       breakpoints will _not_ jump into perl debugger (RX)
pbs_B                                 remove breakpoints (RX)
pbs_node or p_n                       print node information (RX)
pbs_tree or p_t                       pretty print tree
pbs_dependencies or p_d               lists the dependencies of a node
EOH
}

*p_h = \&pbs_help ;


*p_list_breakpoints = \&ListBreakpoints ;

*p_L = \&ListBreakpoints ;

#-------------------------------------------------------------------------------
*pbs_activate_breakpoints = \&ActivateBreakpoints ;
*p_ab= \&ActivateBreakpoints ;

*pbs_deactivate_breakpoints = \&DeactivateBreakpoints ;
*p_db= \&DeactivateBreakpoints ;

#-------------------------------------------------------------------------------

*pbs_jump_in_debugger= \&ActivatePerlDebugger ;
*p_j = \&ActivatePerlDebugger ;

*pbs_no_jump_in_debugger = \&DeactivatePerlDebugger ;
*p_nj = \&DeactivatePerlDebugger ;

#-------------------------------------------------------------------------------

*pbs_remove_breakpoints = \&RemoveBreakpoints ;
*p_B = \&RemoveBreakpoints ;

#-------------------------------------------------------------------------------

sub pbs_node
{
my ($nodes, $node_regex) = @_ ;
$node_regex ||= '.*' ;

if(defined $nodes && ref $nodes eq 'HASH')
	{
	NodeChoice($nodes, $node_regex) ;
	}
else
	{
	use PadWalker qw(peek_my peek_our peek_sub closed_over);
	my $mys = peek_my(3);
	my $ours = peek_our(3);

	my $possible_nodes = $mys->{'$inserted_nodes'} || $ours->{'$inserted_nodes'};

	if(defined $possible_nodes)
		{
		PrintDebug "pbs_list is expecting a reference to \$inserted_nodes. Using the one found in your stack!\n" ;
		if(defined $nodes)
			{
			NodeChoice(${$possible_nodes}, $nodes) ;
			}
		else
			{
			NodeChoice(${$possible_nodes}, $node_regex) ;
			}
		}
	else
		{
		PrintDebug "pbs_list is expecting a reference to \$inserted_nodes\n" ;
		}
	}
}

*p_n = \&pbs_node ;

#----------------------------------------------------------------------

sub pbs_tree
{
my $tree = shift ;
my $indentation = shift || '' ;

unless(ref $tree eq 'HASH')
	{
	PrintDebug "pbs_tree is expecting a reference to a tree\n" ;
	return() ;
	}

PrintDebug
	(
	DumpTree($tree, "Tree '$tree->{__NAME}': ", INDENTATION => $indentation	)
	) ;
}

*p_t = \&pbs_tree ;

#----------------------------------------------------------------------

sub pbs_dependencies
{
my $tree = shift ;
my $GetDependenciesOnly = sub
			{
			my $tree = shift ;
			
			if('HASH' eq ref $tree)
				{
				return( 'HASH', undef, sort grep {! /^__/} keys %$tree) ;
				}
			} ;
			
p_tree($tree, $GetDependenciesOnly, '    ') ;
}

*p_d = \&pbs_dependencies ;

#----------------------------------------------------------------------

sub NodeChoice
{
my ($tree, $node_regex) = @_ ;
$node_regex ||= '.*' ;

my %nodes ;
my $index = 0 ;

for(sort keys %{$tree})
	{
	next if /^__/ ;
	next unless /$node_regex/ ;
	
	PrintDebug "$index/ '$_'\n" ;
	$nodes{$index} = $tree->{$_} ;
	$index++ ;
	}

if(0 == $index)
	{
	PrintDebug "No node to display.\n" ;
	return ;
	}
	
if(1 == $index)
	{
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_ORIGIN} = 1 ;
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_DEPENDENCIES} = 1 ;
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_CAUSE} = 1 ;
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_RULES} = 1 ;
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_CONFIG} = 1 ;
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER} = 1 ;
	local $nodes{0}->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS} = 1 ;
	
	PBS::Information::DisplayNodeInformation($nodes{0}, $nodes{0}->{__PBS_CONFIG}) ;
	return ;
	}

while(1)
	{
	PrintDebug "PBS: Choose a node in the above list> " ;
	my $user_choice = <STDIN> ;
	chomp $user_choice;
	
	if(exists $nodes{$user_choice})
		{
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_ORIGIN} = 1 ;
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_DEPENDENCIES} = 1 ;
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_CAUSE} = 1 ;
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_RULES} = 1 ;
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_CONFIG} = 1 ;
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_BUILDER} = 1 ;
		local $nodes{$user_choice}->{__PBS_CONFIG}{DISPLAY_NODE_BUILD_POST_BUILD_COMMANDS} = 1 ;
		PBS::Information::DisplayNodeInformation($nodes{$user_choice}, $nodes{$user_choice}->{__PBS_CONFIG}) ;
		}

	return ;
	}
}

#----------------------------------------------------------------------

my %breakpoints ;

sub AddBreakpoint
{
my $breakpoint_name = shift ;

PrintWarning("Redefining breakpoint '$breakpoint_name'.\n") if(exists $breakpoints{$breakpoint_name}) ;

$breakpoints{$breakpoint_name} = {@_} ;
}

#----------------------------------------------------------------------

sub RemoveBreakpoints
{
my $breakpoint_regex = shift || '.*';

for my $breakpoint_name (sort keys %breakpoints)
	{
	next unless $breakpoint_name =~ $breakpoint_regex ;
	
	PrintDebug("Breakpoint '$breakpoint_name' removed. \n") ;
	delete $breakpoints{$breakpoint_name} ;
	}
}

#----------------------------------------------------------------------

sub ListBreakpoints
{
my $breakpoint_regex = shift || '.*';

my $found_breakpoint = 0 ;

for my $breakpoint_name (sort keys %breakpoints)
	{
	next unless $breakpoint_name =~ $breakpoint_regex ;
	
	$found_breakpoint++ ;
	PrintDebug(DumpTree($breakpoints{$breakpoint_name}, "$breakpoint_name:")) ;
	}

PrintDebug "pbs_list_breakpoints: No Breakpoint matching regex '$breakpoint_regex'.\n" unless $found_breakpoint ;
}

#----------------------------------------------------------------------

sub ActivateBreakpoints
{
my @breakpoint_regexes = @_ ;

for my $breakpoint_name (sort keys %breakpoints)
	{
	for my $breakpoint_regex (@breakpoint_regexes)
		{
		next unless $breakpoint_name =~ $breakpoint_regex ;
		
		$breakpoints{$breakpoint_name}{ACTIVE} = 1 ;
		PrintDebug("Breakpoint '$breakpoint_name' activated. \n") ;
		}
	}
}

#----------------------------------------------------------------------

sub DeactivateBreakpoints
{
my @breakpoint_regexes = @_ ;

for my $breakpoint_name (sort keys %breakpoints)
	{
	for my $breakpoint_regex (@breakpoint_regexes)
		{
		next unless $breakpoint_name =~ $breakpoint_regex ;
		
		$breakpoints{$breakpoint_name}{ACTIVE} = 0 ;
		PrintDebug("Breakpoint '$breakpoint_name' deactivated. \n") ;
		}
	}
}

#----------------------------------------------------------------------

sub ActivatePerlDebugger
{
my @breakpoint_regexes = @_ ;

for my $breakpoint_name (sort keys %breakpoints)
	{
	for my $breakpoint_regex (@breakpoint_regexes)
		{
		next unless $breakpoint_name =~ $breakpoint_regex ;
		
		$breakpoints{$breakpoint_name}{USE_DEBUGGER} = 1 ;
		PrintDebug("Breakpoint '$breakpoint_name' will activate the perl debugger. \n") ;
		}
	}
}

#----------------------------------------------------------------------

sub DeactivatePerlDebugger
{
my @breakpoint_regexes = @_ ;

for my $breakpoint_name (sort keys %breakpoints)
	{
	for my $breakpoint_regex (@breakpoint_regexes)
		{
		next unless $breakpoint_name =~ $breakpoint_regex ;
		
		$breakpoints{$breakpoint_name}{USE_DEBUGGER} = 0 ;
		PrintDebug("Breakpoint '$breakpoint_name' will NOT activate the perl debugger. \n") ;
		}
	}
}

#----------------------------------------------------------------------

sub CheckBreakpoint
{
my %point = @_ ;

return(0) unless $debug_enabled ;

my $use_debugger = 0 ;

for my $breakpoint_name (keys %breakpoints)
	{
	my $breakpoint = $breakpoints{$breakpoint_name} ;
	
	next unless $breakpoint->{ACTIVE} ;
	
	if(uc $breakpoint->{TYPE} eq 'BUILD')
		{
		next unless $point{TYPE} eq 'BUILD' ;
		}
		
	if(uc $breakpoint->{TYPE} eq 'POST_BUILD')
		{
		next unless $point{TYPE} eq 'POST_BUILD' ;
		}
		
	if(uc $breakpoint->{TYPE} eq 'TREE')
		{
		next unless $point{TYPE} eq 'TREE' ;
		}
	
	if(uc $breakpoint->{TYPE} eq 'INSERT')
		{
		next unless $point{TYPE} eq 'INSERT' ;
		}
	
	if(uc $breakpoint->{TYPE} eq 'VARIABLE')
		{
		next unless $point{TYPE} eq 'VARIABLE' ;
		}
	
	if(uc $breakpoint->{TYPE} eq 'DEPEND')
		{
		next unless $point{TYPE} eq 'DEPEND' ;
		}
		
	if(defined $breakpoint->{RULE_REGEX})
		{
		next unless $point{RULE_NAME} =~ /$breakpoint->{RULE_REGEX}/ ;
		}
	
	if(defined $breakpoint->{NODE_REGEX})
		{
		next unless $point{NODE_NAME} =~ /$breakpoint->{NODE_REGEX}/ ;
		}
		
	if(defined $breakpoint->{PACKAGE_REGEX})
		{
		next unless $point{PACKAGE_NAME} =~ /$breakpoint->{PACKAGE_REGEX}/ ;
		}
	
	if(defined $breakpoint->{PBSFILE_REGEX})
		{
		next unless $point{PBSFILE} =~ /$breakpoint->{PBSFILE_REGEX}/ ;
		}
		
	if($point{PRE})
		{
		next unless $breakpoint->{PRE} ;
		}
		
	if($point{POST})
		{
		next unless $breakpoint->{POST} ;
		}
		
	if($breakpoint->{TRIGGERED})
		{
		next unless $point{TRIGGERED} ;
		}

	for my $action (@{$breakpoint->{ACTIONS}})
		{
		$action->(%point, BREAKPOINT_NAME => $breakpoint_name) ;
		}
		
	if($breakpoint->{USE_DEBUGGER})
		{
		$use_debugger++  ;
		}
	}
	

return($use_debugger) ;
}

#----------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::Debug  - debugger support for PBS

=head1 SYNOPSIS

	use PBS::Debug ;
	
	AddBreakpoint
		(
		'breakpoint name',
		DEPEND => 1,
		PRE => 1,
		ACTIONS =>
			[
			sub
				{
				PrintDebug "Hi there.\n" ;
				},
			],
		) ;
		
	ActivateBreakpoints('hi') ;

=head1 DESCRIPTION

This module defines subs that manipulate PBS breakpoints (explained in B<PBS> reference manual).

Subs to manipulate breakpoints:

sub AddBreakpoint           add a PBS breakpoint
sub RemoveBreakpoints       remove one or more PBS breakpoint according to the name regex passed as argument
sub ListBreakpoints         list all the breakpoints defined within PBS
sub ActivateBreakpoints     activates one or more PBS breakpoints
sub DeactivateBreakpoints   does the opposite of the above
sub ActivatePerlDebugger    activates wether a breakpoint (or breapoints) jumps to the perl debbugger
sub DeactivatePerlDebugger  does the opposite of the above
sub CheckBreakpoint

Debugger commands:

pbs_list_breakpoints or p_L           list breakpoints (RX)
pbs_activate_breakpoints or p_ab      activate breakpoints (RX)
pbs_deactivate_breakpoints or p_db    deactivate breakpoints (RX)
pbs_jump_in_debugger or p_j           breakpoints will jump into perl debugger (RX)
pbs_no_jump_in_debugger or p_nj       opposit of p_j
pbs_B                                 Remove breakpoints (RX)
pbs_node or p_n                       print node information (RX)
pbs_tree or p_t                       pretty print tree
pbs_dependencies or p_d               lists the dependencies of a node

=head2 EXPORT

EnableDebugger AddBreakpoint RemoveBreakpoints ListBreakpoints
ActivateBreakpoints DeactivateBreakpoints 
ActivatePerlDebugger DeactivatePerlDebugger 
CheckBreakpoint

and their aliases

=head1 BREAKPOINTs

	AddBreakpoint
		(
		'brealpoint name',
		DEPEND => 1,
		PRE => 1,
		ACTIONS =>
			[
			sub
				{
				PrintDebug "Hi there.\n" ;
				},
			],
		) ;
		

=head2 Breakpoint position

Some breakpoints cab be triggered before or after (or both) something happends in the system.

if PRE is set, the breakpoints triggers before the action takes place. The breakpoint is triggered after the action takes
place if after the action if POST is set. This allows you to take a snapshot before something happends and compare after it has happened.

=head2 Types

B<BUILD> (PRE/POST): when building a node.

B<POST_BUILD> (PRE/POST): when a post build action is to be performed

B<TREE>: when a tree (or sub tree) is finished depending

B<INSERT> When a node is inserted in the dependency tree.

B<VARIABLE>: when a variable is set.

B<DEPEND> (PRE/POST) when depending a node. B<DEPEND+TRIGGERED+POST> can be used to trigger a breakpoint only when a rule has matched the node.

=head2 Breakpoint filtering

You can set any of the  following to a qr// or string. Only actions matching all the regexes you set will trigger a breakpoint.

=over 2

=item * RULE_REGEX

=item * NODE_REGEX

=item * PACKAGE_REGEX

=item * PBSFILE_REGEX

=back

=head2 Actions

=head3 ACTIONS

B<ACTIONS> is an array reference containing sub references. All the subs are run. All debugging functionality (ie activating or adding breakpoints)
are available within the subs.

=head3 USE_DEBUGGER

B<USE_DEBUGGER> if running under the perl debugger and B<USE_DEBUGGER> is set, PBS will jump into the debugger after the breakpoint.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual / debug section.

=cut

