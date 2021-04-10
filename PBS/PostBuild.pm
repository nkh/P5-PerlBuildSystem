
package PBS::PostBuild ;

use v5.10 ; use strict ; use warnings ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw(AddPostBuildCommand post_build) ;
our $VERSION = '0.01' ;

use Data::TreeDumper ;
use File::Basename ;
use File::Spec::Functions qw(:ALL) ;

use PBS::Constants ;
use PBS::Output ;
use PBS::Rules ;

#-------------------------------------------------------------------------------

my %post_build_commands;

#-------------------------------------------------------------------------------

sub GetPostBuildRules
{
my ($package) = @_ ;

exists $post_build_commands{$package} ? @{$post_build_commands{$package}} : () ;
}

#-------------------------------------------------------------------------------

sub AddPostBuildCommand
{
my($name, $switch, $builder_sub, $build_arguments) = @_ ;

my ($package, $file_name, $line) = caller() ;
$file_name =~ s/^'// ;
$file_name =~ s/'$// ;

RegisterPostBuildCommand
	(
	$file_name, $line,
	$package,
	$name,
	$switch, $builder_sub, $build_arguments,
	) ;
}
*post_build=\&AddPostBuildCommand ;

sub RegisterPostBuildCommand
{
my ($file_name, $line, $package, $name, $switch, $builder_sub, $build_arguments) = @_ ;

my $pbs_config = PBS::PBSConfig::GetPbsConfig($package) ;

if(exists $post_build_commands{$package})
	{
	for my $post_build_commands (@{$post_build_commands{$package}})
		{
		if
			(
			$post_build_commands->{NAME} eq $name
			&& 
				(
				   $post_build_commands->{FILE} ne $file_name
				|| $post_build_commands->{LINE} ne $line
				)
			)
			{
			PrintError "Depend: post build '$name' is already used\n" ;
			PbsDisplayErrorWithContext $pbs_config, $post_build_commands->{FILE}, $post_build_commands->{LINE} ;
			PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
			die "\n" ;
			}
		}
	}
	
if('' eq ref $switch || 'HASH' eq ref $switch)
	{
	PrintError "Depend: post build: invalid command definition\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
	die "\n" ;
	}
	
if(defined $builder_sub && 'CODE' ne ref $builder_sub)
	{
	PrintError"Depend: post build: builder must be a sub reference\n" ;
	PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
	die "\n" ;
	}
	
my $post_build_depender_sub ;
	
if('ARRAY' eq ref $switch)
	{
	unless(@$switch)
		{
		PrintError "Depend: post build '$name', nothing defined in post build definition" ;
		PbsDisplayErrorWithContext $pbs_config, $file_name, $line ;
		die "\n" ;
		}

	my @post_build_regexes ;
	
	for my $post_build_regex_definition (@$switch)
		{
		unless(file_name_is_absolute($post_build_regex_definition) || $post_build_regex_definition =~ /^\.\//)
			{
			$post_build_regex_definition= "./$post_build_regex_definition" ;
			}
			
		my 
			(
			$build_ok, $build_message,
			$post_build_path_regex,
			$post_build_prefix_regex,
			$post_build_regex,
			) = PBS::Rules::BuildDependentRegex($post_build_regex_definition) ;
		
		unless($build_ok)
			{
			PrintError $build_message ;
			PbsDisplayErrorWithContext $pbs_config, $file_name,$line ;
			die "\n" ;
			}
			
		push @post_build_regexes, "^$post_build_path_regex$post_build_prefix_regex$post_build_regex\$";
		}
		
	$post_build_depender_sub = sub 
					{
					my ($node_name) = @_ ; 
					my $index = -1 ;
					
					for my $regex (@post_build_regexes)
						{
						$index++ ;
						
						#PrintDebug "post build '$name' checking '$node_name' with regex: '$regex'\n" ;
						
						if($node_name =~ $regex)
							{
							#PrintDebug DumpTree $switch, "post build matched" ;
							
							return 1, "regex index: $index matched" ;
							}
						}
						
					return 0, "'$node_name' didn't match any post build ccommand regex" ;
					}
	}
elsif('CODE' eq ref $switch)
	{
	$post_build_depender_sub = $switch ;
	}
	
my $origin = ":$package:$file_name:$line" ;

my $post_build_definition = 
	{
	TYPE                => [], #unused type field
	NAME                => $name,
	ORIGIN              => $origin,
	FILE                => $file_name,
	LINE                => $line,
	DEPENDER            => $post_build_depender_sub,
	BUILDER             => $builder_sub,
	BUILDER_ARGUMENTS   => $build_arguments,
	TEXTUAL_DESCRIPTION => $switch, # keep a visual on how the rule was defined
	} ;

if($pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMANDS_REGISTRATION} || $pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION})
	{
	PrintInfo "Depend: adding post build command: $name:" . GetRunRelativePath($pbs_config, $file_name) . ":$line\n"  ;
	}

if($pbs_config->{DEBUG_DISPLAY_POST_BUILD_COMMAND_DEFINITION})
	{
	PrintInfo DumpTree $post_build_definition, '', DISPLAY_ADDRESS => 0 ;
	}

push @{$post_build_commands{$package}}, $post_build_definition ;
}

#-------------------------------------------------------------------------------

sub DisplayAllPostBuildCommands
{
PrintInfo DumpTree(\%post_build_commands, "PostBuild: commands:") ;
}

#-------------------------------------------------------------------------------

1 ;

__END__
=head1 NAME

PBS::PostBuild  -

=head1 SYNOPSIS

	# in a Pbsfile
	AddRule 'a', ['a' => 'aa'], BuildOk('fake builder') ;
	AddRule 'aar', ['aa' => undef], BuildOk('fake builder') ;
	
	AddPostBuildCommand 'post build', ['a', 'b', 'c', 'aa'], \&PostBuildCommands ;
	
	AddPostBuildCommand 'post build', \&Filter, \&PostBuildCommands ;
	
	
=head1 DESCRIPTION

I<AddPostBuildCommand> allows you to AddPostBuildCommand  perl subs for run after a node has been build.

=head2 EXPORT

I<AddPostBuildCommand>.

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut
