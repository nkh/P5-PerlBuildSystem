# Http: 318333 failed accessing server @ http://127.0.0.1:60179/pbs/get_depend_resource, status: 599, reason: Internal Exception

package PBS::Net ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw() ;
our $VERSION     = '0.01' ;

use HTTP::Daemon ;
use HTTP::Request::Params ;
use HTTP::Status ;
use HTTP::Tiny;

use List::Util qw(all first) ;
use Storable qw(freeze thaw) ;
use Time::HiRes qw(usleep gettimeofday tv_interval) ;
use Data::TreeDumper ;

use PBS::Output ;
use PBS::PBS::Forked ;

#-------------------------------------------------------------------------------

sub Put
{
my ($pbs_config, $url, $where, $what, $whom) = @_ ;
$what //= {} ;

#my $t0_message = [gettimeofday];

Say EC "<D>Http: <I> PUT  ${url}pbs/$where<I2>, size: " . length($what) . ", $whom" if $pbs_config->{HTTP_DISPLAY_PUT} ;

my $response = HTTP::Tiny->new->put("${url}pbs/$where", {content => $what}) ;

unless ($response->{success})
	{
	#SDT $response ;
	#Say Error "PBS: can't PUT" ;
	#die "\n" ;
	}

$response->{success}
}

#-------------------------------------------------------------------------------

sub Post
{
my ($pbs_config, $url, $where, $what, $whom) = @_ ;
$what //= {} ;

#my $t0_message = [gettimeofday];

Say EC "<D>Http: <I> POST  ${url}pbs/$where<I2>, $whom" if $pbs_config->{HTTP_DISPLAY_POST} ;
SIT $what, '', INDENTATION => "\t", DISPLAY_ADDRESS => 0 if $pbs_config->{HTTP_DISPLAY_POST} ;

my $response = HTTP::Tiny->new->post_form("${url}pbs/$where", $what) ;

for (0.05, 0.10, 0.20)
	{
	if(!$response->{success})
		{
		Say EC "<W>Http: $whom retrying <I2>@ ${url}pbs/$where, status: $response->{status}, delay: $_"
			unless $pbs_config->{HTTP_TIMEOUT_HIDE} ;
		
		select(undef, undef, undef, 0.1) ;
		$response = $HT->get("${url}pbs/$where", {content => freeze $what}) ;
		}
	}

unless ($response->{success})
	{
	Say Error "Http: $whom failed accessing server @ ${url}pbs/$where, status: $response->{status}, reason: $response->{reason}" ;
	return {}
	}

$response->{success}
}

#-------------------------------------------------------------------------------

sub Get
{
my ($pbs_config, $url, $where, $what, $whom, $raw) = @_ ;

Say EC "<D>Http: <I>  GET  ${url}pbs/$where<I2>, $whom" if $pbs_config->{HTTP_DISPLAY_GET} ;

my $HT = HTTP::Tiny->new() ;
my $response = $HT->get("${url}pbs/$where", {content => freeze $what}) ;

for (0.05, 0.10, 0.20)
	{
	if(!$response->{success})
		{
		Say EC "<W>Http: $whom retrying <I2>@ ${url}pbs/$where, status: $response->{status}, delay: $_"
			unless $pbs_config->{HTTP_TIMEOUT_HIDE} ;
		
		select(undef, undef, undef, 0.1) ;
		$response = $HT->get("${url}pbs/$where", {content => freeze $what}) ;
		}
	}

if($response->{success})
	{
	#SDT $response, 'response' ;
	#Say Info2 "$response->{status} $response->{reason}" ;
	 
	#while(my ($k, $v) = each %{$response->{headers}})
	#	{
	#	Say Info2 "$k: $_" for ref $v eq 'ARRAY' ? @$v : $v ;
	#	}
	
	return $response->{content} if $raw ;
	
	return
		{
		map { $_ eq 'undef' ? undef : $_ } map { split '=', $_, 2  } split '&', $response->{content}
		}
	}
else
	{
	Say Error "Http: $whom failed accessing server @ ${url}pbs/$where, status: $response->{status}, reason: $response->{reason}" ;
	return {}
	}
} 

#-------------------------------------------------------------------------------

{
my $response_connection ;
sub RESPONSE_REGISTER { ($response_connection) = @_ }

sub RESPONSE_RAW
{
my ($response) = @_ ;

my $r = HTTP::Response->new(RC_ACCEPTED) ;
$r->content($response) ;

$response_connection->send_response($r) ;
}

sub RESPONSE
{
my ($response) = @_ ;

my $r = HTTP::Response->new(RC_ACCEPTED) ;
$r->content( join '&',  map { $_ . '=' . ($response->{$_} // 'undef') } keys %$response ) ;

$response_connection->send_response($r) ;
}
}

#-------------------------------------------------------------------------------------------------------

sub StartPbsServer
{
my ($targets, $pbs_config, $parent_config) = @_ ;

my $daemon = StartHttpDeamon($pbs_config) ;
$pbs_config->{RESOURCE_SERVER} = $daemon->url ;
$pbs_config->{DEPEND_AND_CHECK}++ ;

my ($nodes, $removed_nodes, $GenerateWarpFile) = PBS::Warp::Warp($targets, $pbs_config) ;

unless ($removed_nodes)
	{
	Say EC "<W>PBS: <I>up to date" ;
	
	use constant BUILD_SUCCESS => 1 ;
	
	return BUILD_SUCCESS, "Warp: up to date", {READ_ME => "up to date"}, $nodes, 'up to date', [] 
	}

my $pid = fork() ;

if($pid)
	{
	BecomeServer
		(
		$pbs_config, 'PBS server', $daemon,
		{
			PBS_SERVER => 1,
			TARGETS    => $targets,
			TIME       => [gettimeofday],
			WARP       => { NODES => $nodes, REMOVED_NODES => $removed_nodes, GENERATOR => $GenerateWarpFile },
		},
		) ;
	
	}
else
	{
	Say EC "<W>PBS<I>: start"  ;
	
	delete $pbs_config->{INTERMEDIATE_WARP_WRITE} ;
	local $PBS::Output::indentation_depth = -1 ;
	
	my $depender = PBS::PBS::Forked::GetParallelDepender
			(
			$pbs_config,
			{__NAME => $targets->[0] // 'no target'},
			\&PBS::FrontEnd::StartPbs,
			[$targets, $pbs_config, $parent_config, $nodes, $removed_nodes, sub {}],
			[ #fake depender call arguments
				[],                     # PBSFILE_CHAIN  => 0,
				'ROOT',                 # INSERTED_AT    => 1,
				$pbs_config->{PBSFILE}, # SUBPBS_NAME    => 2,
				'ROOT',                 # LOAD_PACKAGE   => 3,
				$pbs_config,            # PBS_CONFIG     => 4,
				{},                     # CONFIG         => 5,
				$targets,               # TARGETS        => 6,
				{},                     # INSERTED_NODES => 7,
				'ROOT',                 # TREE_NAME      => 8,
				1,                      # BUILD_TYPE     => 9, DEPEND_AND_CHECK
			]
			) ;
	
	$depender->() ; #forks and never comes back, will register itself when finished so we can halt it
	
	exit 0 ;
	}
}

#-------------------------------------------------------------------------------------------------------

sub StartHttpDeamon { HTTP::Daemon->new(LocalAddr => 'localhost') or die ERROR("Server: Error: can't start server") . "\n" }

sub BecomeServer
{
my ($pbs_config, $server_name, $daemon, $data) = @_ ;

Say EC "<I>Server: START, $server_name - $$ <I2><" . $daemon->url . ">" if $pbs_config->{HTTP_DISPLAY_SERVER_START} ;

my ($counter, $allocated, $reused, $used_e_leases) = (0, 0, 0, 0) ;

my %dependers ;
my %resources = map { $_ => 1 } 1 .. $pbs_config->{PBS_JOBS} ;
my %extra_resources ; # request from a build to schedule a dependency

# work around PUT being received twice
my %build_done ;
my $detriggered ;

my $status = sub
{
if ($pbs_config->{DISPLAY_RESOURCE_EVENT})
	{
	my $glyph = ' ' . join'', map { $resources{$_} ? '◼' : ' ' } 1 .. $pbs_config->{PBS_JOBS} ;

	Say EC "<I>Server: " . $_[0]
		. '<I2>, dependers: '. scalar( keys %dependers)
		. ', idling: '       . scalar( grep { exists $_->{ADDRESS} && $_->{IDLE} } values %dependers)
		. ', reused: '       . $reused
		. ', leases: '       . scalar( grep { $_ } values %resources) . '/' . $pbs_config->{PBS_JOBS}
		. "<W3>$glyph<I2>"
		. ', leased: '       . $allocated
		. ', E-leases: '     . scalar( keys  %extra_resources)
		. ', used E-leased: '. $used_e_leases
	}
} ; 

my ($state_depending, $state_building) ;

my $stop ;
while (my $c = $daemon->accept) 
	{
	RESPONSE_REGISTER $c ;

	$counter++ ;
	
	while (my $rq = $c->get_request)
		{
		my $path = $rq->uri->path ;
		
		Say EC "<D>Http: <I><" . $rq->method . '> ' . $daemon->url . "$path<I2>, count: $counter, $server_name - $$"
			if $pbs_config->{HTTP_DISPLAY_REQUEST} ;
		
		if ($rq->method eq 'GET')
			{
			'/pbs/counter' eq $path && RESPONSE { TEXT => "counter: $counter" }  ;
			
			'/pbs/get_depend_resource' eq $path
				&& do 
					{
					my $content = thaw $rq->content ; 
					my $pid = $content->{pid} ;
					
					my $dependers = keys %dependers ;
					my $id = first { $resources{$_} } keys %resources ;
					
					if
						(
							(
							   (  $pbs_config->{USE_DEPEND_SERVER} && $id && $dependers < $pbs_config->{PBS_JOBS} )
							|| (! $pbs_config->{USE_DEPEND_SERVER} && $id )
							)
						
						&&
							(
							! defined $pbs_config->{DEPEND_PROCESSES}
							|| ($dependers < $pbs_config->{DEPEND_PROCESSES})
							)
						)
						{
						$resources{$id} = 0 ;
						$allocated++ ;
						$state_depending++ ;
						
						delete $extra_resources{$pid} ;
						#delete $dependers{$pid}{IDLE} ;
						
						RESPONSE { ID => $id } ;
						
						$id = sprintf '%7d', $id ;
						$status->("leased: $id - $pid") ;
						}
					else
						{
						if(exists $extra_resources{$pid})
							{
							#delete $dependers{$pid}{IDLE} ;
							$extra_resources{$pid} = {BUILDING => 1} ;
							
							$used_e_leases++ ;
							
							RESPONSE { ID => $pid } ;
							
							my $pid_aligned = sprintf '%7d', $pid ;
							$status->(_WARNING_ "leased: $pid_aligned - $pid") ;
							}
						else
							{
							RESPONSE { } ;
							#$status->("lease status") ;
							}
						}
					} ;
					
			'/pbs/get_idle_depender' eq $path
				&& do 
					{
					my $id = first { $resources{$_} } keys %resources ;
					my $idle_depender = first { exists $_->{ADDRESS} && $_->{IDLE} } values %dependers ;
					
					if ($id && $idle_depender)
						{
						$resources{$id} = 0 ;
						$allocated++ ;
						$reused++ ;
						$idle_depender->{IDLE} = 0 ;
						
						RESPONSE { ID => $id, PID => $idle_depender->{PID}, ADDRESS => $idle_depender->{ADDRESS} } ;
						
						$status->("reused: dep: $idle_depender->{PID}, id: $id") ;
						}
					else
						{
						RESPONSE {} ;
						}
					} ;
					
			'/pbs/get_depend_resource_status' eq $path
				&& RESPONSE
					{
					AVAILABLE_RESOURCES => scalar(grep { $_ } values %resources),
					ALL_DEPENDERS_DONE  => all { exists $_->{ADDRESS} && $_->{IDLE} } values %dependers
					} ;
					
			#  above resource server urls, below depender urls
			
			'/pbs/get_graph' eq $path && RESPONSE_RAW $data->{GRAPH} ; 
			
			#$c->send_error(RC_FORBIDDEN) ;
			#$c->send_file_response("/") ;
			}
		elsif ($rq->method eq 'POST')
			{
			local @ARGV = () ; # weird, otherwise it ends up in the parsed parameters
			
			my $parser = HTTP::Request::Params->new({req => $rq}) ;
			my $parameters = $parser->params() ;
			
			'/pbs/stop' eq $path && do { $c->send_status_line ; $stop++ } ;
			
			'/pbs/allocate_extra_resource' eq $path
				&& do
					{
					my ($pid, $extra_pid) = @{$parameters}{qw. pid extra_pid .} ;
					
					$extra_resources{$extra_pid}++ ;
					
					$pid = sprintf '%7d', $pid ;
					$status->(_WARNING_ "extra : $pid - $extra_pid") ;
					} ;
				
			'/pbs/return_depend_resource' eq $path
				&& do
					{
					my ($id, $pid) = @{$parameters}{qw. id pid .} ;
					
					$c->send_status_line ;
					
					die ERROR("PBS: Error: returned depend resource $id from $pid, wasn't allocated") . "\n" if $resources{$id} ;
					
					$resources{$id} = 1 ;
					
					$id = sprintf '%7d', $id ;
					$status->(_INFO2_ "return: $id - $pid") ;
					} ;
			
			# reuse parallel depend for depending another node
			'/pbs/depend_node' eq $path 
				&& do
					{
					my ($id, $node, $resource_server) = @{$parameters}{'id', 'node', 'resource_server'} ;
					
					# send some id for the current node depend
					$c->send_status_line ;
					$c->force_last_request ;
					$c->close ;
					
					$status->("depend: pid: $$, node: $node") ;
					
					PBS::PBS::Forked::Pbs($data, $parameters) ;
					
					Post
						(
						$pbs_config, $resource_server,
						'return_depender',
						{ id => $id, pid => $$},
						$$
						) ;
					} ;
			
			'/pbs/return_depender' eq $path
				&& do
					{
					my ($id, $pid) = @{$parameters}{'id', 'pid'} ;
					
					die ERROR("PBS: Error: returned depender $id, wasn't allocated") . "\n" if $resources{$id} ;
					
					$c->send_status_line ;
					$c->force_last_request ;
					$c->close ;
					
					$resources{$id} = 1 ;
					
					my $depender = first { $_->{PID} == $pid } values  %dependers ;
					
					die ERROR("PBS: Error: returned depended, pid: $pid, wasn't allocated") . "\n" unless $depender ;
					
					$depender->{IDLE}++ ;
					
					$status->("return: res: $id      ") ;
					} ;
			
			'/pbs/register_parallel_depend' eq $path
				&& do
					{
					my $pid = $parameters->{pid} ;
					
					die ERROR("PBS: Error: parallel depender already registered pid: $pid") . "\n" if exists $dependers{$pid} ;
					
					$c->send_status_line ;
					$c->force_last_request ;
					$c->close ;
					$dependers{$pid} = {PID => $pid} ;
					$status->("active:         - $pid") ;
					} ;
			
			'/pbs/parallel_depend_idling' eq $path
				&& do
					{
					my ($pid, $log, $address, $target) = @{$parameters}{qw. pid log address target .} ;
					
					die ERROR("PBS: Error: depender $pid wasn't registered") . "\n" unless exists $dependers{$pid} ;
						
					$c->send_status_line ;
					$c->force_last_request ;
					$c->close ;
					$dependers{$pid}{IDLE}++ ;
					$dependers{$pid}{LOG} = $log ;
					$dependers{$pid}{ADDRESS} = $address ;
					
					if($pbs_config->{DISPLAY_LOG_PARALLEL_DEPEND})
						{
						open my $f, '<', $log ;
						print STDERR while <$f> ;
						
						Say Info2 "Server: done <$address>, pid: $pid" ;
						Say ' ' if $. > 1 ;
						}
					
					$status->("idling:         - $pid") ;
					} ;
			
			'/pbs/build' eq $path
				and do
					{
					$c->send_status_line ;
					$c->force_last_request ;
					$c->close ;
					
					# update md5 in cache and nodes
					# insert post build nodes, best would be calling the post pbs functions
					
					PBS::PBS::Forked::BuildSubGraph($data) ;
					} ;
			
			}
		elsif ($rq->method eq 'PUT')
			{
			local @ARGV = () ; # otherwise it ends up in the parsed parameters
			
			'/pbs/link'       eq $path and PBS::PBS::Forked::Link($pbs_config, $data, $rq->content ) ;
			
			'/pbs/detrigger'  eq $path and PBS::PBS::Forked::Detrigger($pbs_config, $data, $rq->content) ;
			
			'/pbs/build_done' eq $path
				&& do
					{
					$c->send_status_line ;
					
					my $content = thaw $rq->content ; 
					my ($id, $pid, $target, $nodes, $updates) = @{$content}{qw. id pid target nodes updates.} ;
					
					my $used_extra_resource ;
					
					if(exists $extra_resources{$pid} && 'HASH' eq ref $extra_resources{$pid})
						{
						$used_extra_resource++ ;
						}
					else
						{
						#die ERROR("PBS: Error: returned build resource $id from $pid, wasn't allocated") . "\n" if $resources{$id} ;
						
						$resources{$id} = 1 ;
						}
					
					delete $extra_resources{$pid} ;
					$dependers{$pid}{BUILD_DONE}++ ;
					
					for ($updates->@*)
						{
						my ($name, $field, $value) = $_->@* ;
						#SDT {$field => $value}, $name ;
						
						$data->{INSERTED_NODES}{$name}{$field} = $value ;
						}
					
					$id = sprintf '%7d', $id ;
					$status->(($used_extra_resource ? \&_WARNING_ : \&_INFO2_)->("return: $id - $pid")) ;
					} ;
			}
		
		$c->force_last_request ;
		}
	
	$c->close ;
	
	if
		(
		exists $data->{PBS_SERVER} && $state_building
		&& (all { $resources{$_} } keys %resources)
		&& 0 == scalar(keys %extra_resources)
		&& all { $dependers{$_}{BUILD_DONE} } keys %dependers
		)
		{
		my $exception = '' ;
		my $target = $data->{TARGETS}[0] ;
		my $node   = $data->{INSERTED_NODES}{$target} ;
		$data->{WARP}{GENERATOR}->($node, $data->{INSERTED_NODES}, $exception) ;
		
		Shutdown($pbs_config, \%dependers, \$stop, $data->{TIME}) ;
		}
	
	if
		(
		exists $data->{PBS_SERVER} && $state_depending && ! $state_building
		&& (all { $resources{$_} } keys %resources)
		&& all { $dependers{$_}{IDLE} } keys %dependers
		)
		{
		my ($graphs, $nodes, $inserted_nodes, $order, $parallel_pbs_to_run) = 
			PBS::PBS::Forked::LinkMainGraph($pbs_config, {}, $data->{TARGETS}, \%dependers) ;
		
		$data->{INSERTED_NODES} = $inserted_nodes ;
		
		if(keys $parallel_pbs_to_run->%*)
			{
			my $build = PBS::PBS::Forked::Build($pbs_config, $graphs, $nodes, $order, $parallel_pbs_to_run, \%dependers) ;
			
			if($build)
				{
				$state_depending = 0 ;
				$state_building++ ;
				}
			else
				{
				my $exception = '' ;
				my $target  = $data->{TARGETS}[0] ;
				my $node = $data->{INSERTED_NODES}{$target} ;
				$data->{WARP}{GENERATOR}->($node, $data->{INSERTED_NODES}, $exception) ;
				
				Shutdown($pbs_config, \%dependers, \$stop, $data->{TIME}) ;
				}
			}
		else
			{
			my $exception = '' ;
			my $target  = $data->{TARGETS}[0] ;
			my $node = $data->{INSERTED_NODES}{$target} ;
			$data->{WARP}{GENERATOR}->($node, $data->{INSERTED_NODES}, $exception) ;
			
			Shutdown($pbs_config, \%dependers, \$stop, $data->{TIME}) ;
			}
		}
	
	last if $stop ;
	}

Say EC "<I>Server: STOP, $server_name - $$ <I2><" . $daemon->url . ">" if $pbs_config->{HTTP_DISPLAY_SERVER_STOP} ;

if(exists $data->{PBS_SERVER})
	{
	# return to FrontEnd
	# $build_success, $build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence
	1               , 1            , 'parallel pbs', {}              , {}             , 'PBS'        , []  
	}
else
	{
	exit 0 ;
	}
}

#-------------------------------------------------------------------------------

sub Shutdown
{
my ($pbs_config, $dependers, $stop, $start_time) = @_ ;

my $t0 = [gettimeofday];

if($pbs_config->{RESOURCE_QUICK_SHUTDOWN})
	{
	kill 'KILL',  $_->{PID}  for values %$dependers ;
	}
else
	{
	PBS::Net::Post($pbs_config, $_->{ADDRESS}, 'stop', {}, $$) for values %$dependers ;
	}

Say sprintf EC("<W>PBS<I>: time: %0.2f s., shutdown: %0.2f s.\n"), tv_interval ($start_time, [gettimeofday]), tv_interval ($t0, [gettimeofday])
		if $pbs_config->{DISPLAY_PBS_TOTAL_TIME} ;

$$stop++ ;
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Net -

=head1 SYNOPSIS

=head1 DESCRIPTION

Network related utilities.

=head2 EXPORT

None.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

=cut


