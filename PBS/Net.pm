
package PBS::Net ;

use v5.10 ;
use strict ;
use warnings ;

use Time::HiRes qw(gettimeofday tv_interval) ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

use HTTP::Daemon ;
use HTTP::Status ;
use HTTP::Request::Params ;
use HTTP::Tiny;

use Time::HiRes qw(usleep gettimeofday tv_interval) ;
use Storable qw(freeze) ;
use List::Util qw(all first) ;

use PBS::Output ;
use PBS::PBS::Forked ;

#-------------------------------------------------------------------------------

sub Put
{
my ($pbs_config, $url, $where, $what, $whom) = @_ ;
$what //= {} ;

#my $t0_message = [gettimeofday];

Say Debug "Http: PUT, size: " . length($what) . ", to: ${url}pbs/$where" if $pbs_config->{HTTP_DISPLAY_PUT} ;

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

SDT $what, "Http: POST, to: ${url}pbs/$where" if $pbs_config->{HTTP_DISPLAY_POST} ;

my $response = HTTP::Tiny->new->post_form("${url}pbs/$where", $what) ;

unless ($response->{success})
	{
	#SDT $response ;
	#Say Error "PBS: can't POST" ;
	#die "\n" ;
	}

$response->{success}
}

#-------------------------------------------------------------------------------

sub Get
{
my ($pbs_config, $url, $where, $what, $whom, $raw) = @_ ;

SDT $what, "Http: Get, from: ${url}pbs/$where by $whom" if $pbs_config->{HTTP_DISPLAY_GET} ;

my $HT = HTTP::Tiny->new() ;
my $response = $HT->get("${url}pbs/$where", {content => freeze $what}) ;

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
	Say Error "Http: Failed accessing server @ ${url}pbs/$where" ;
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
		},
		) ;
	
	}
else
	{
	Say Info "PBS: run in parallel depend mode"  ;
	my $depender = PBS::PBS::Forked::GetParallelDepender
			(
			$pbs_config,
			{__NAME => $targets->[0] // 'no target'},
			\&PBS::FrontEnd::StartPbs,
			[$targets, $pbs_config, $parent_config],
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

sub StartHttpDeamon { HTTP::Daemon->new(LocalAddr => 'localhost') or die ERROR("Http: can't start server") . "\n" }

sub BecomeServer
{
my ($pbs_config, $server_name, $daemon, $data) = @_ ;

Say EC "<D>Http: <I>start : $server_name - $$ <I2><" . $daemon->url . ">" if $pbs_config->{HTTP_DISPLAY_SERVER_START} ;

my ($counter, $allocated, $reused) = (0, 0, 0) ;

my %dependers ;
my %resources = map { $_ => 1 } 1 .. $pbs_config->{PBS_JOBS} ;

my $status = sub
{
if ($pbs_config->{DISPLAY_RESOURCE_EVENT})
	{
	Say Debug "Depend∥ : " . $_[0]
			. _INFO2_
				  ', dependers: ' . scalar( keys %dependers)
				. ', idling: '    . scalar( grep { exists $_->{ADDRESS} && $_->{IDLE} } values %dependers)
				. ', reused: '    . $reused
				. ', leases: '    . scalar( grep { $_ } values %resources) . '/' . $pbs_config->{PBS_JOBS}
				. ', leased: '    . $allocated
	}
} ; 

my $started_depending ;

my $stop ;
while (my $c = $daemon->accept) 
	{
	RESPONSE_REGISTER $c ;

	$counter++ ;
	
	while (my $rq = $c->get_request)
		{
		my $path = $rq->uri->path ;
		
		Say Debug "Http: server: $server_name - $$, request: " . $rq->method . " $path" if $pbs_config->{HTTP_DISPLAY_REQUEST} ;
		
		if ($rq->method eq 'GET')
			{
			'/pbs/counter' eq $path && RESPONSE { TEXT => "counter: $counter" }  ;
			
			'/pbs/get_depend_resource' eq $path
				&& do 
					{
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
							|| (keys %dependers < $pbs_config->{DEPEND_PROCESSES})
							)
						)
						{
						RESPONSE { ID => $id } ;
						$resources{$id} = 0 ;
						$allocated++ ;
						$started_depending++ ;
						$status->("leased, res: $id      ") ;
						}
					else
						{
						RESPONSE {} ;
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
						
						$status->("reused, dep: $idle_depender->{PID}, id: $id") ;
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
			
			'/pbs/stop' eq $path && do { $stop++ } ;
			
			'/pbs/return_depend_resource' eq $path
				&& do
					{
					my $id = $parameters->{id} ;
					
					die ERROR("PBS: returned resource $id, wasn't allocated") . "\n" if $resources{$id} ;
					
					$c->send_status_line ;
					$resources{$id} = 1 ;
					$status->("return, res: $id      ") ;
					} ;
			
			# reuse parallel depend for depending another node
			'/pbs/depend_node' eq $path 
				&& do
					{
					my ($id, $node, $resource_server) = @{$parameters}{'id', 'node', 'resource_server'} ;
					
					# send some id for the current node depend
					$c->send_status_line ;
					
					$status->("depend, pid: $$, node: $node") ;
					
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
					
					die ERROR("PBS: returned resource $id, wasn't allocated") . "\n" if $resources{$id} ;
					
					$c->send_status_line ;
					
					$resources{$id} = 1 ;
					$status->("return, res: $id      ") ;
					
					my $depender = first { $_->{PID} == $pid } values  %dependers ;
					
					die ERROR("PBS: returned depended, pid: $pid, wasn't allocated") . "\n" unless $depender ;
					
					$depender->{IDLE}++ ;
					} ;
			
			'/pbs/register_parallel_depend' eq $path
				&& do
					{
					my $pid = $parameters->{pid} ;
					
					die ERROR("PBS: parallel depender already registered pid: $pid") . "\n" if exists $dependers{$pid} ;
					
					$c->send_status_line ;
					$dependers{$pid} = {PID => $pid} ;
					$status->("active, pid: $pid") ;
					} ;
			
			'/pbs/parallel_depend_idling' eq $path
				&& do
					{
					my ($pid, $log, $address) = @{$parameters}{qw. pid log address .} ;
					
					die ERROR("PBS: depender $pid wasn't registered") . "\n" unless exists $dependers{$pid} ;
						
					$c->send_status_line ;
					$dependers{$pid}{IDLE}++ ;
					$dependers{$pid}{LOG} = $log ;
					$dependers{$pid}{ADDRESS} = $address ;
					
					if($pbs_config->{DISPLAY_LOG_PARALLEL_DEPEND})
						{
						open my $f, '<', $log ;
						print STDERR while <$f> ;
						
						Say Info2 "Depend∥ : server: <$address>, pid: $pid\n\n" ;
						}
					
					$status->("idling, pid: $pid") ;
					} ;
			
			}
		elsif ($rq->method eq 'PUT')
			{
			local @ARGV = () ; # weird, otherwise it ends up in the parsed parameters
			'/pbs/link' eq $path and PBS::PBS::Forked::Link($pbs_config, $data, $rq->content ) ;
			
			'/pbs/detrigger' eq $path && PBS::PBS::Forked::Detrigger($pbs_config, $data, $rq->content) ;
			}
		
		$c->force_last_request ;
		}
	
	if
		(
		exists $data->{PBS_SERVER} && $started_depending
		&& (all { $resources{$_} } keys %resources)
		&& all { $dependers{$_}{IDLE} } keys %dependers
		)
		{
		Say Info "Depend∥ : done, allocated depend resources: $allocated" ;
		$stop++ ;
		}
	
	$c->close ;
	last if $stop ;
	}

if(exists $data->{PBS_SERVER})
	{
	my ($graphs, $nodes, $order, $parallel_pbs_to_run) = 
		PBS::PBS::Forked::LinkMainGraph($pbs_config, {}, $data->{TARGETS}, $data->{TIME}, \%dependers) ;

	PBS::PBS::Forked::Build($graphs, $nodes, $order, $parallel_pbs_to_run) ;

	Say Info "HTTP: server shutdown '$server_name'" if $pbs_config->{HTTP_DISPLAY_SERVER_SHUTDOWN} ;

	# return to FrontEnd
	# $build_success, $build_result, $build_message, $dependency_tree, $inserted_nodes, $load_package, $build_sequence
	 1,            , 1            , 'parallel pbs', {},             , {}             , 'PBS',         []  
	}
else
	{
	Say Info "HTTP: server shutdown '$server_name'" if $pbs_config->{HTTP_DISPLAY_SERVER_SHUTDOWN} ;
	exit 0 ;
	}
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


