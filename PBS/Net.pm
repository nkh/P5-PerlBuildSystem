
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
#use Data::Dumper ;
 
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

SDT $what, "Http: POST to ${url}pbs/$where" if $pbs_config->{HTTP_DISPLAY_GET} ;

my $HT = HTTP::Tiny->new() ;
my $response = $HT->get("${url}pbs/$where") ;
 
if($response->{success})
	{
	#SDT $response, 'response' ;
	#Say Info2 "$response->{status} $response->{reason}" ;
	 
	#while(my ($k, $v) = each %{$response->{headers}})
	#	{
	#	Say Info2 "$k: $_" for ref $v eq 'ARRAY' ? @$v : $v ;
	#	}

	return length $response->{content} ? $response->{content} : undef ;
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

sub BecomeDependServer
{
my ($pbs_config, $data) = @_ ;

BecomeServer($pbs_config, 'depend server', StartHttpDeamon($pbs_config), $data) ;
}

sub StartHttpDeamon
{
my ($pbs_config) = @_ ;
HTTP::Daemon->new(LocalAddr => 'localhost') or die ERROR("Http: can't start server") . "\n" ;
}

sub BecomeServer
{
my ($pbs_config, $name, $d, $data) = @_ ;

my $url = $d->url ;

Say Debug "Http: starting $name <$url>" if $pbs_config->{HTTP_DISPLAY_SERVER_START} ;

my $stop ;
my $counter = 0 ;
my $available_resources = $pbs_config->{DEPEND_JOBS} // 0 ;

while (my $c = $d->accept) 
	{
	$counter++ ;

	while (my $rq = $c->get_request)
		{
		my $path = $rq->uri->path ;

		Say Debug "Http: request: " . $rq->method . " $path" if $pbs_config->{HTTP_DISPLAY_REQUEST} ;

		if ($rq->method eq 'GET')
			{
			'/pbs'                     eq $path && RESPONSE($c, "PBS: access: $counter") ;
			'/pbs/get_resource'        eq $path && do 
								{
								RESPONSE($c, $available_resources) ;
								$available_resources-- if $available_resources > 0 ;
								} ;

			'/pbs/get_resource_status' eq $path && RESPONSE($c, $available_resources) ;

			#$c->send_error(RC_FORBIDDEN) ;
			#$c->send_file_response("/") ;
			}
		elsif ($rq->method eq 'POST')
			{
			local @ARGV = () ; # weird, otherwise it ends up in the parsed parameters

			my $parser = HTTP::Request::Params->new({req => $rq}) ;

			'/pbs/return_resource' eq $path && $available_resources++ && $c->send_status_line() ;

			$stop++ if $path eq '/pbs/stop' ;
			}
		
		$c->force_last_request ;
		}

	$c->close ;

	last if $stop ;
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


