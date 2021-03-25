
package PBS::Net ;

use 5.006 ;
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

#-------------------------------------------------------------------------------

sub Put
{
my ($pbs_config, $url, $where, $what, $whom) = @_ ;
$what //= {} ;

#my $t0_message = [gettimeofday];

my $response = HTTP::Tiny->new->put("${url}pbs/$where", {content => $what}) ;

#SDT $what, sprintf("Http: POST to ${url}pbs/$where, time: %0.4f s.", tv_interval ($t0_message, [gettimeofday])) if $pbs_config->{HTTP_DISPLAY_POST} ;
SDT $what, "Http: PUT to ${url}pbs/$where" if $pbs_config->{HTTP_DISPLAY_POST} ;

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

my $response = HTTP::Tiny->new->post_form("${url}pbs/$where", $what) ;

#SDT $what, sprintf("Http: POST to ${url}pbs/$where, time: %0.4f s.", tv_interval ($t0_message, [gettimeofday])) if $pbs_config->{HTTP_DISPLAY_POST} ;
SDT $what, "Http: POST to ${url}pbs/$where" if $pbs_config->{HTTP_DISPLAY_POST} ;

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

SDT $what, "Http: POST to ${url}pbs/$where by $whom" if $pbs_config->{HTTP_DISPLAY_GET} ;

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
$r->content
	(
	join '&',  map { $_ . '=' . ($response->{$_} // 'undef') } keys %$response
	) ;

$response_connection->send_response($r) ;
}
}

sub StartResourceServer
{
my ($pbs_config) = @_ ;

# register so master can find us

my $httpd = StartHttpDeamon($pbs_config) ;
my $url = $httpd->url ;

my $pid = fork() ;
if($pid)
	{
	return $url ;
	}
else
	{
	BecomeServer($pbs_config, 'ressource server', $httpd, {}) ;
	exit 0 ;
	}
}

sub StartHttpDeamon
{
my ($pbs_config) = @_ ;
HTTP::Daemon->new(LocalAddr => 'localhost') or die ERROR("Http: can't start server") . "\n" ;
}

sub BecomeServer
{
my ($pbs_config, $server_name, $d, $data) = @_ ;

my $url = $d->url ;

Say Debug "Http: starting $server_name <$url>, pid: $$" if $pbs_config->{HTTP_DISPLAY_SERVER_START} ;

my $stop ;
my $counter = 0 ;

my %resources = map { $_ => 1 } 1 .. $pbs_config->{PBS_JOBS} ;
my $allocated = 0 ;
my $reused = 0 ;

my %parallel_dependers ;

my $status = sub
{
if ($pbs_config->{DISPLAY_RESOURCE_EVENT})
	{
	Say Debug "Depend∥ : " . $_[0]
			. _INFO2_
				  ', dependers: ' . scalar( keys %parallel_dependers)
				. ', idling: ' . scalar( grep { exists $_->{ADDRESS} && $_->{IDLE} } values %parallel_dependers)
				. ', reused: ' . $reused
				. ', leases: ' . scalar( grep { $_ } values %resources) . '/' . $pbs_config->{PBS_JOBS}
				. ', leased: ' . $allocated
	}
} ; 

while (my $c = $d->accept) 
	{
	RESPONSE_REGISTER $c ;

	$counter++ ;
	
	while (my $rq = $c->get_request)
		{
		my $path = $rq->uri->path ;
		
		SDT $rq, "Http: request: " . $rq->method . " $path" if $pbs_config->{HTTP_DISPLAY_REQUEST} ;
		
		if ($rq->method eq 'GET')
			{
			'/pbs/counter' eq $path && RESPONSE { TEXT => "counter: $counter" }  ;
			
			'/pbs/get_depend_resource' eq $path
				&& do 
					{
					my $dependers = keys %parallel_dependers ;
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
							|| (keys %parallel_dependers < $pbs_config->{DEPEND_PROCESSES})
							)
						)
						{
						RESPONSE { ID => $id } ;
						$resources{$id} = 0 ;
						$allocated++ ;
					
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
					my $idle_depender = first { exists $_->{ADDRESS} && $_->{IDLE} } values %parallel_dependers ;
					
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
					ALL_DEPENDERS_DONE  => all { exists $_->{ADDRESS} && $_->{IDLE} } values %parallel_dependers
					} ;
					
			'/pbs/get_parallel_dependers' eq $path
				&& RESPONSE { SERIALIZED_DEPENDERS => freeze \%parallel_dependers }  ;
			
			#  below depender urls
			
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
					
					my $depender = first { $_->{PID} == $pid } values  %parallel_dependers ;
					
					die ERROR("PBS: returned depended, pid: $pid, wasn't allocated") . "\n" unless $depender ;
					
					$depender->{IDLE}++ ;
					
					} ;
			
			'/pbs/register_parallel_depend' eq $path
				&& do
					{
					my $pid = $parameters->{pid} ;
					
					die ERROR("PBS: parallel depender already registered pid: $pid") . "\n" if exists $parallel_dependers{$pid} ;
					
					$c->send_status_line ;
					$parallel_dependers{$pid} = {PID => $pid} ;
					$status->("active, pid: $pid") ;
					} ;
			
			'/pbs/parallel_depend_idling' eq $path
				&& do
					{
					my ($pid, $address) = @{$parameters}{'pid', 'address'} ;
					
					die ERROR("PBS: depender $pid wasn't registered") . "\n" unless exists $parallel_dependers{$pid} ;
						
					$c->send_status_line ;
					$parallel_dependers{$pid}{IDLE}++ ;
					$parallel_dependers{$pid}{ADDRESS} = $address ;
					$status->("idling, pid: $pid") ;
					} ;
			}
		elsif ($rq->method eq 'PUT')
			{
			local @ARGV = () ; # weird, otherwise it ends up in the parsed parameters
			
			'/pbs/link' eq $path and PBS::PBS::Forked::Link($pbs_config, $data, $rq->content ) ;
			}
		
		$c->force_last_request ;
		}

	$c->close ;
	last if $stop ;
	}

Say Info "HTTP: server shutdown '$server_name'" if $pbs_config->{HTTP_DISPLAY_SERVER_SHUTDOWN} ;
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


