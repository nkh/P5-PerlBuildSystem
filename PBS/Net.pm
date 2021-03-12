
package PBS::Net ;

use 5.006 ;
use strict ;
use warnings ;

#use Time::HiRes qw(gettimeofday tv_interval) ;

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

use Time::HiRes qw(usleep) ;
use Data::Dumper ;
use List::Util qw(first) ;
 
use PBS::Output ;

#-------------------------------------------------------------------------------

sub Post
{
my ($pbs_config, $url, $where, $what, $whom) = @_ ;
$what //= {} ;

my $response = HTTP::Tiny->new->post_form("${url}pbs/$where", $what) ;
 
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
my ($pbs_config, $url, $where, $what, $whom) = @_ ;

SDT $what, "Http: POST to ${url}pbs/$where by $whom" if $pbs_config->{HTTP_DISPLAY_GET} ;

my $HT = HTTP::Tiny->new() ;
my $response = $HT->get("${url}pbs/$where", {content => Dumper $what}) ;

if($response->{success})
	{
	#SDT $response, 'response' ;
	#Say Info2 "$response->{status} $response->{reason}" ;
	 
	#while(my ($k, $v) = each %{$response->{headers}})
	#	{
	#	Say Info2 "$k: $_" for ref $v eq 'ARRAY' ? @$v : $v ;
	#	}

	return $response->{content} ;
	}
else
	{
	Say Error "Http: Failed accessing server @ ${url}pbs/$where" ;
	}
} 

#-------------------------------------------------------------------------------

sub RESPONSE
{
my ($c, $response) = @_ ;

my $r = HTTP::Response->new(RC_ACCEPTED) ;
$r->content($response) ;

$c->send_response($r) ;

1
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
	BecomeServer($pbs_config, 'ressource server', $httpd, []) ;
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

my %resources = map { $_ => 1 } 1 .. $pbs_config->{DEPEND_JOBS} ;
my $allocations = 0 ;

my %parallel_dependers ;

while (my $c = $d->accept) 
	{
	$counter++ ;

	while (my $rq = $c->get_request)
		{
		my $path = $rq->uri->path ;

		SDT $rq, "Http: request: " . $rq->method . " $path" if $pbs_config->{HTTP_DISPLAY_REQUEST} ;

		if ($rq->method eq 'GET')
			{
			'/pbs'  eq $path
				 && RESPONSE($c, "PBS: access: $counter") ;

			'/pbs/get_depend_resource' eq $path
				&& do 
					{
					my $handle = first { $resources{$_} } keys %resources ;
					$resources{$handle} = 0 if $handle ;
					
					RESPONSE($c, $handle) ;
					
					$allocations++ if $handle ;
					my $allocations_text = ", allocations: $allocations" ;
					
					my $status = ', available: ' . scalar( grep { $_ } values %resources) . '/' . $pbs_config->{DEPEND_JOBS} ;
					
					Say Debug "Resource: allocated depend #$handle$status$allocations_text"
						if $handle && $pbs_config->{DISPLAY_RESOURCE_EVENT} ;
					} ;
					
			'/pbs/get_depend_resource_status' eq $path
				&& do
					{
					my @available = grep { $_ } values %resources ;
					
					RESPONSE($c, scalar(@available)) ;
					} ;
					
			'/pbs/get_parallel_dependers' eq $path
				&& do
					{
					my @available = grep { $_ } values %resources ;
					RESPONSE($c, Data::Dumper->Dump([\%parallel_dependers], [qw($dependers)]));
					} ;
			
			#$c->send_error(RC_FORBIDDEN) ;
			#$c->send_file_response("/") ;
			}
		elsif ($rq->method eq 'POST')
			{
			local @ARGV = () ; # weird, otherwise it ends up in the parsed parameters

			my $parser = HTTP::Request::Params->new({req => $rq}) ;
			my $parameters = $parser->params() ;
			
			'/pbs/stop' eq $path
				&& do
					{
					$stop++ ;
					#Say Warning "HTTP: server shutdown '$server_name'" if $pbs_config->{HTTP_DISPLAY_SERVER_SHUTDOWN} ;
					} ;
			
			'/pbs/return_depend_resource' eq $path
				&& do
					{
					my $r = $parameters->{handle} // 0 ;
					
					die "PBS: returned resource $r was not leased\n"
						if $resources{$r} ;
					
					$resources{$r} = 1 ;
					
					my $status = ', available: ' . scalar( grep { $_ } values %resources) . '/' . $pbs_config->{DEPEND_JOBS} ;
					
					Say Debug "Resource: return of depend #$r$status" if $pbs_config->{DISPLAY_RESOURCE_EVENT} ;
					}
				&& $c->send_status_line() ;
				
			
			
			'/pbs/register_parallel_depend' eq $path
				&& do
					{
					my $id = $parameters->{id} ;
					
					die "PBS: parallel depender already registered #$id\n"
						if exists $parallel_dependers{$id} ;
				
					$parallel_dependers{$id} = {} ;
					
					my $waiting = ', waiting: ' . scalar( grep { exists $_->{ADDRESS} } values  %parallel_dependers) ;
					my $registered = ', registered dependers: ' . scalar( keys %parallel_dependers) ;
					my $status = $registered . $waiting ;
					
					Say Debug "Resource: registered depender #$id$status" if $pbs_config->{DISPLAY_RESOURCE_EVENT} ;
					}
				&& $c->send_status_line() ;
			
			'/pbs/parallel_depend_waiting' eq $path
				&& do
					{
					my ($id, $address) = @{$parameters}{'id', 'address'} ;
					
					die "PBS: depender $id was not registered\n"
						unless exists $parallel_dependers{$id} ;
						
					$parallel_dependers{$id}{ADDRESS} = $address ;
				
					my $waiting = ', waiting: ' . scalar( grep { exists $_->{ADDRESS} } values  %parallel_dependers) ;
					my $registered = ', registered dependers: ' . scalar( keys %parallel_dependers) ;
					my $status = $registered . $waiting ;
					
					Say Debug "Resource: got address for depender #$id$status" if $pbs_config->{DISPLAY_RESOURCE_EVENT} ;
					}
				&& $c->send_status_line() ;
			}
		
		$c->force_last_request ;
		}

	$c->close ;

	last if $stop ;
	}

Say Error "HTTP: server shutdown '$server_name'" if $pbs_config->{HTTP_DISPLAY_SERVER_SHUTDOWN} ;
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


