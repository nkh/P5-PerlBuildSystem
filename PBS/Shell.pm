
package PBS::Shell ;
use PBS::Debug ;

use 5.006 ;
use strict ;
use warnings ;
use Data::Dumper ;
use Carp ;

require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(RunCommand RunShellCommands RunHostedShellCommands) ;
our $VERSION = '0.02' ;

our $silent_commands = 0 ;
our $silent_commands_output = 0 ;

use PBS::Output ;

#-------------------------------------------------------------------------------

sub new
{
my $class = shift ;
return(bless {@_}, __PACKAGE__) ;
}

#-----------------------------------------------------------------------------

sub GetInfo
{
my $self = shift ;

if(exists $self->{USER_INFO} && $self->{USER_INFO} ne '')
	{
	return(__PACKAGE__ . " " . $self->{USER_INFO}) ;
	}
else
	{
	return(__PACKAGE__) ;
	}
}

#-----------------------------------------------------------------------------

sub RunCommand
{
my ($self, $command) = @_ ;

RunShellCommands($command) ;
}

#-------------------------------------------------------------------------------

sub RunPerlSub
{
my ($self, $perl_sub, @args) = @_ ;

if($PBS::Shell::silent_commands_output)
	{
	my ($out, $err, @r) = ('', '') ; 

	no warnings 'once';
	open(OLDOUT, ">&STDOUT") ; 
	open(OLDERR, ">&STDERR") ;

	{
	close(STDOUT);
	open STDOUT, '>>', \$out or die "Can't redirect STDOUT to variable: $!";

	close(STDERR);
	open STDERR, '>>', \$out or die "Can't redirect STDERR to variable: $!" ;

	@r = $perl_sub->(@_) ;
	}

	open(STDERR, ">&OLDERR");
	open(STDOUT, ">&OLDOUT");

	#print STDOUT $out ;
	#print STDERR $err ;

	@r ;
	}
else
	{
	$perl_sub->(@args) ;
	}
}

#-------------------------------------------------------------------------------

sub RunShellCommands
{
# Run a command through system or sh
# if $PBS::Shell::silent_commands is defined, this sub
# will capture the output of the command
# and only show it if an error occurs

# if an error occurs while running the command, an exception is thrown.

# note that this is _not_ a member function.

for my $shell_command (@_)
	{
	if('' eq ref $shell_command)
		{
		PrintShell "$shell_command\n" unless $PBS::Shell::silent_commands ;
	
		if($PBS::Shell::silent_commands_output)
			{
			my $output = `$shell_command 2>&1` ;
		
			if($?)
				{
				print STDERR $output if $output;
				
				die bless
					{
					error        => 'Shell',
					command      => $shell_command,
					errno        => $?,
					errno_string => $!,
					}, __PACKAGE__ ;
					
				}
			}
		else
			{
			if(system $shell_command)
				{
				die bless
					{
					error => 'Shell' ,
					command => $shell_command,
					errno => $?,
					errno_string => $!,
					}, __PACKAGE__ ;
				}
			}
		}
	else
		{
		croak ERROR "RunShellCommands doesn't accept references to '" . ref($shell_command) . "'!\n" ;
		}
	}
	
1 ;
}

#-------------------------------------------------------------------------------

sub RunHostedShellCommands
{
my $shell = shift || new PBS::Shell() ;

for my $shell_command (@_)
	{
	if('CODE' eq ref $shell_command)
		{
		$shell->RunPerlSub($shell_command) ;
		}
	else
		{
		$shell->RunCommand($shell_command) ;
		}
	}

1 ;
}

#-------------------------------------------------------------------------------

1 ;


__END__
=head1 NAME

PBS::Shell  -

=head1 SYNOPSIS

  use PBS::Shell ;
  
  RunShellCommands
	(
	"ls",
	"echo hi",
	"generate an exception"
	) ;

=head1 DESCRIPTION

PBS::Shell allows you to build a local shell object or to run commands in a local shell.

=head2 EXPORT

I<RunShellCommands>

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=head1 SEE ALSO

B<PBS> reference manual.

=cut

