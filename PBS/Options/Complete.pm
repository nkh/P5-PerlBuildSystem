package PBS::Options::Complete ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw() ;

our $VERSION = '0.02' ;

use File::Slurp ;
use File::Find::Rule ;
use List::Util qw(max any);
use Sort::Naturally ;
use Tree::Trie ;
	
use PBS::Output ;

#-------------------------------------------------------------------------------

=pod

aliases

pbs [--]text
pbs text+number
pbs text?

pbs [--]text*
pbs *
pbs ** 

pbs #file|number
pbs #man,page
pbs #smenu

=cut

sub Complete
{
my ($word_to_complete, $previous_word, $options_elements, $AliasOptions, $DisplaySwitchesHelp, $guide_paths) = @_ ;
my $command_line = $ENV{COMP_LINE} ;

#todo: check options by calling a checker guide

if($word_to_complete =~ /^#|\w#$/)
	{
	$word_to_complete =~ s/(.+)#$/#$1/ if $word_to_complete =~ /\w#$/ ;

	my $result ;
	
	my ($guide, @args) = split ',', $word_to_complete ;
	
	# make arguments available to the guide
	local @ARGV = ($command_line, $previous_word, $guide, @args) ;
	
	substr($guide, 0, 1, '') ;
	my %guides ;
	
	File::Find::Rule->file()->name('*.pl')->maxdepth(1)->exec( sub { push $guides{$_[0]}->@*, $_[1]} )
			->in( $guide_paths->@* ) ;
	
	if(exists $guides{"$guide.pl"})
		{
		my $file_located = $guides{"$guide.pl"}[0] . "/$guide.pl" ;
		
		$result = do "$file_located" ;
		die "PBS: couldn't evaluate '$file_located', error: $!, exception: $@\n" if $@ ;
		}
	else
		{
		my @guides ;
		my $max_length = 0 ;
		
		while (my ($file, $paths) = each %guides)
			{
			next unless -f "$paths->[0]/$file" ;
			
			open my $guide, '<', "$paths->[0]/$file" ;
			
			my $line = <$guide>;
			$line //= '' ;
			chomp $line ;
			
			my $file_name_length = length($file) ;
			
			$max_length = $file_name_length if $max_length <= $file_name_length ;
			
			push @guides, [$file, $paths, $line]  ;
			} 
			
		@guides = sort { $a->[0] cmp $b->[0] } @guides ;
		
		if(defined $guide and $guide =~ /^\d+$/ and $guide != 0 and defined $guides[$guide - 1])
			{
			$ARGV[1] = "#$guide" ;
			
			my $index = $guide - 1 ;
			my $file_located = "$guides[$index][1][0]/$guides[$index][0]" ;
			
			$result = do "$file_located" ;
			die "PBS: couldn't evaluate '$file_located', error: $!, exception: $@\n" if $@ ;
			}
		else
			{
			return unless @guides ;
			
			my $index = 1 ;
			open my $fzf_in, '>', 'pbs_fzf_guides' ;
			binmode $fzf_in ;
			
			print $fzf_in join "\n", map 
						{
						EC substr(sprintf("<W3>%d <I>%-${max_length}s <I3>$_->[2]", $index++, $_->[0]), 0, 99) . "<R>"
						} @guides ;
			
			my $query = $guide eq '' ? '' : "-q $guide" ;
			
			my ($n, $m) ;
			{
			local $/ = "R" ;
			print STDERR "\033[6n" ;
			($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
			print STDERR "\n" ;
			}
			
			my $fzf = qx"cat pbs_fzf_guides | fzf --height=50% --info=inline --ansi --reverse -1 $query" ;
			my $guide = substr($fzf // '', 0, 1) ;
			
			{
			local $/ = "R" ;
			print STDERR "\033[6n" ;
			($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
			$n-- ; # we added an extra newline
			}
			print STDERR "\e[$n;${m}H" ;
			
			if(defined $guide and $guide =~ /^\d+$/ and $guide != 0 and defined $guides[$guide - 1])
				{
				$ARGV[1] = $word_to_complete ;
				
				my $index = $guide - 1 ;
				my $file_located = "$guides[$index][1][0]/$guides[$index][0]" ;
				
				$result = do "$file_located" ;
				die "PBS: couldn't evaluate '$file_located', error: $!, exception: $@\n" if $@ ;
				}
			}
		}
	
	#return ($result ? "\n$result" : "\n​") ;
	return ;
	}

if($word_to_complete =~ /^\*\*$/ and 0 == system 'fzf --version > /dev/null')
	{
	my ($n, $m) ;
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	}
	print STDERR "\n" ;

	my @fzf = qx"fd --color=always | fzf --info=inline --height=50% --info=inline --ansi --reverse -m" ;

	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	$n-- ; # we added an extra newline
	}
	print STDERR "\e[$n;${m}H" ;
	
	
	if(@fzf)
		{
		if(0 == system 'tmux -V > /dev/null' )
			{
			my $options =  join ' ',  map { (($_ // '') =~ /^([a-zA-Z0-9_\/]+)/) } @fzf ;
			my $command = "tmux send-keys -- " . ('C-H ' x length($word_to_complete)) . " '$options '" ;
			qx"$command" ;
			}
		else
			{
			return join "\n", ( map { (($_ // '') =~ /^([a-zA-Z0-9_\/]+)/) } @fzf) ;
			}
		}
	
	return ;
	}

if($word_to_complete =~ /^\-\-?$/)
	{
	my (@short, @long, @options) ;
	
	for($options_elements->@*)
		{
		my ($option_type, $help) = @{$_}[0..1] ;
		
		my ($option, $type) = $option_type  =~ m/^([^=]+)(=.*)?$/ ;
		$type //= '' ;
		
		my ($long, $short) = split(/\|/, $option, 2) ;
		$short //= '' ;
		
		push @short, length($short) ;
		push @long , length($long) ;
		
		push @options, [$long, $short, $type, $help] ; 
		}
	
	my $max_short = max(@short) + 2 ;
	my $max_long  = max(@long);
	
	open my $fzf_in, '>', 'pbs_fzf_all_options' ;
	binmode $fzf_in ;
	
	print $fzf_in join "\n",
			map
			{
			my ($long, $short, $type, $help) = @{$_} ;
			
			EC(sprintf( "<I3>--%-${max_long}s <W3>%--${max_short}s<I3>%2s: ", $long, ($short eq '' ? '' : "--$short"), $type) . "<I>$help") ;
			} @options ;
	
	my ($n, $m) ;
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	print STDERR "\n" ;
	}
	
	my @fzf = qx"cat pbs_fzf_all_options | fzf --height=50% --info=inline --ansi --reverse -m" ;
	
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	$n -= 1 ; # we added an extra lines
	}
	print STDERR "\e[$n;${m}H" ;
	qx"tput ed 1>&2" ;
	
	if(@fzf)
		{
		if(0 == system 'tmux -V > /dev/null' )
			{
			my $options =  join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf ;
			my $command = "tmux send-keys -- " . ('C-H ' x length($word_to_complete)) . " '$options '" ;
			qx"$command" ;
			}
		else
			{
			return join "\n", ( map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf) ;
			}
		}
	
	return ;
	}

if($word_to_complete =~ /\*$/ and 0 == system 'fzf --version > /dev/null')
	{
	my (@short, @long, @options) ;
	
	my ($search) = $word_to_complete =~ /(-?-?[^\*]+)\*+$/ ;
	$search //= '' ;
	
	for($options_elements->@*)
		{
		my ($option_type, $help) = @{$_}[0..1] ;
		
		my ($option, $type) = $option_type  =~ m/^([^=]+)(=.*)?$/ ;
		$type //= '' ;
		
		my ($long, $short) = split(/\|/, $option, 2) ;
		$short //= '' ;
		
		push @short, length($short) ;
		push @long , length($long) ;
		
		push @options, [$long, $short, $type, $help] ; 
		}
	
	my $max_short = max(@short) + 2 ;
	my $max_long  = max(@long);
	
	open my $fzf_in, '>', 'pbs_fzf_options' ;
	binmode $fzf_in ;
	
	print $fzf_in join "\n",
			map
			{
			my ($long, $short, $type, $help) = @{$_} ;
			
			EC(sprintf( "<I3>--%-${max_long}s <W3>%--${max_short}s<I3>%2s: ", $long, ($short eq '' ? '' : "--$short"), $type) . "<I>$help") ;
			} @options ;
	
	my ($n, $m) ;
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	print STDERR "\n" ;
	}
	
	my @fzf = qx"cat pbs_fzf_options | fzf --height=50% --info=inline --ansi --reverse -m -q '$search'" ;
	
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	$n -= 1 ; # we added an extra lines
	}
	print STDERR "\e[$n;${m}H" ;
	qx"tput ed 1>&2" ;
	
	if(@fzf)
		{
		if(0 == system 'tmux -V > /dev/null' )
			{
			my $options =  join ' ',  map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf ;
			my $command = "tmux send-keys -- " . ('C-H ' x length($word_to_complete)) . " '$options '" ;
			qx"$command" ;
			}
		else
			{
			return join "\n", ( map { (($_ // '') =~ /^(--[a-zA-Z0-9_]+)/) } @fzf) ;
			}
		}
	
	return ;
	}

return () unless $word_to_complete =~ /^-?-?[a-zA-Z0-9_+-?]+/ ;

if($word_to_complete !~ /^-?-?\s?$/)
	{
	my (@slice, @options) ;
	my ($names, $option_tuples) = de_getop_ify_list([ map { $_->[0] } $options_elements->@* ]) ;
	
	if($AliasOptions)
		{
		my $aliases = AliasOptions->($AliasOptions, []) ;
		push @$names, keys %$aliases ;
		}
	
	@$names = sort @$names ;
	
	$word_to_complete =~ s/(\+)(\d+)$// ;
	my $point = $2 ;
	
	my $reduce  = $word_to_complete =~ s/-$// ;
	my $expand  = $word_to_complete =~ s/\+$// ;
	
	my $trie = new Tree::Trie ;
	$trie->add( map { ("-" . $_) , ("--" . $_) }  @{$names } ) ;
	
	my @matches = nsort $trie->lookup($word_to_complete) ;
	
	if(@matches)
		{
		if($reduce || $expand)
			{
			my $munged ;
			
			for  my $tuple (@$option_tuples)
				{
				if (any { $word_to_complete =~ /^-*$_$/ } @$tuple)
					{
					$munged = $expand ?  $tuple->[0] : defined $tuple->[1] ? $tuple->[1] : $tuple->[0] ;
					last ;
					}
				}
			
			defined $munged ? "--$munged\n": "$matches[0]\n" ;
			}
		else
			{
			@matches = $matches[$point - 1] if $point and defined $matches[$point - 1] ;
			
			if(@matches < 2)
				{
				join("\n",  @matches) . "\n" ;
				}
			else
				{
				my $counter = 0 ;
				join("\n", map { $counter++ ; "$_₊" . subscript($counter)} @matches) . "\n" ;
				}
			}
		}
	elsif($word_to_complete =~ /[^\?\-\+]+/)
		{
		if($word_to_complete =~ /\?$/)
			{
			my ($whole_option, $word) = $word_to_complete =~ /^(-*)(.+?)\?$/ ;
			
			my $matcher = $whole_option eq '' ? $word : "^$word" ;
			
			@matches = grep { $_ =~ $matcher } @$names ;
			
			if(@matches)
				{
				Print Info "\n\n" ;
				
				if($DisplaySwitchesHelp)
					{
					$DisplaySwitchesHelp->(\@matches, $options_elements) ;
					}
				else
					{
					DisplaySwitchesHelp->(\@matches, $options_elements) ;
					}
					
				my $c = 0 ;
				@matches > 1 ? join("\n", map { $c++ ; "--$_₊" . subscript($c) } nsort @matches) . "\n" : "\n​\n" ;
				}
			else
				{
				my $c = 0 ;
				join("\n", map { $c++ ; "--$_₊" . subscript($c)} nsort grep { $_ =~ $matcher } @$names) . "\n" ;
				}
			}
		else
			{
			my $word = $word_to_complete =~ s/^-*//r ;
			
			my @matches = nsort grep { /$word/ } @$names ;
			   @matches = $matches[$point - 1] if $point and defined $matches[$point - 1] ;
			
			if(@matches < 2)
				{
				join("\n", map { "--$_" } @matches) . "\n" ;
				}
			else
				{
				my $c = 0 ;
				join("\n", map { $c++ ; "--$_₊" . subscript($c)} @matches) . "\n" ;
				}
			}
		}
	}
}

#-------------------------------------------------------------------------------

sub subscript { join '', map { qw / ₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ /[$_] } split '', $_[0] ; } 

#-------------------------------------------------------------------------------

sub AliasOptions
{
my ($alias_file, $arguments) = @_ ;

$alias_file //= 'pbs_option_aliases' ;

my (%aliases) ;

if (-e $alias_file)
	{
	for my $line (read_file $alias_file)
		{
		next if $line =~ /^\s*#/ ;
		next if $line =~ /^$/ ;
		$line =~ s/^\s*// ;
		
		my ($alias, @rest) = split /\s+/, $line ;
		$alias =~ s/^-+// ;
		
		$aliases{$alias} = \@rest if @rest ;
		}
	}

@{$arguments} = map { /^-+/ && exists $aliases{s/^-+//r} ? @{$aliases{s/^-+//r}} : $_ } @$arguments ;

\%aliases
}

#-------------------------------------------------------------------------------

sub de_getop_ify_list
{

=head2 de_getop_ify_list(\@completion_list)

Split L<Getopt::Long> option definitions and remove type information

I<Arguments>

=over 2 

=item * \@completion_list - list of options to create completion for

the options can be simple strings or a L<Getopt::Long> specifications 

=back

I<Returns> - an array reference containing all options and  an array reference containing tuples of options

I<Exceptions> - carps if $completion_list is not defined

=cut

my ($completion_list) = @_ ;

my @de_getopt_ified_list ;
my @de_getopt_ified_list_tuples ;

for my $switch (@{$completion_list})
	{
	my @switches = split(/\|/sxm, $switch) ;
	
	my @tuple ;

	for (@switches) 
		{
		s/=.*$//sxm ;
		s/:.*$//sxm ;
		
		push @de_getopt_ified_list, $_ ;
		push @tuple, $_ ;
		}

	push @de_getopt_ified_list_tuples, \@tuple ;
	}
	
return \@de_getopt_ified_list, \@de_getopt_ified_list_tuples ;
}

#-------------------------------------------------------------------------------

sub DisplaySwitchesHelp
{
my ($switches, $options) = @_ ;

my @matches ;

OPTION:
for my $option (sort { $a->[0] cmp $b->[0] } $options->@*)
	{
	for my $option_element (split /\|/, $option->[0])
		{
		$option_element =~ s/=.*$// ;
		
		if( any { $_ eq $option_element} $switches->@* )
			{
			push @matches, $option ;
			next OPTION ;
			}
		}
	}

my ($narrow_display, $display_long_help) = (0, @matches <= 1) ;

my (@short, @long, @options) ;

my $has_long_help ;

return unless @matches ;

for (@matches)
	{
	my ($option_type, $help, $long_help) = @{$_}[0..2] ;
	
	$help //= '' ;
	$long_help //= '' ;
	
	my ($option, $type) = $option_type  =~ m/^([^=]+)(=.*)?$/ ;
	$type //= '' ;
		
	my ($long, $short) =  split(/\|/, ($option =~ s/=.*$//r), 2) ;
	$short //= '' ;
	
	push @short, length($short) ;
	push @long , length($long) ;
	
	$has_long_help++ if length($long_help) ;
	
	push @options, [$long, $short, $type, $help, $long_help] ; 
	}

my $max_short = $narrow_display ? 0 : max(@short) + 2 ;
my $max_long  = $narrow_display ? 0 : max(@long);

for (@options)
	{
	my ($long, $short, $type, $help, $long_help) = @{$_} ;

	my $lht = $has_long_help 
			? $long_help eq ''
				? ' '
				: '*'
			: '' ;

	Say EC sprintf("<I3>--%-${max_long}s <W3>%-${max_short}s<I3>%-2s%1s: ", $long, ($short eq '' ? '' : "--$short"), $type, $lht)
			. ($narrow_display ? "\n" : '')
			. "<I>$help" ;

	Say Info $long_help if $display_long_help && $long_help ne '' ;
	}
}

#-------------------------------------------------------------------------------
1 ;

__END__
=head1 NAME

PBS::Options::Complete - Helper functions for bash completion

=head1 DESCRIPTION

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut

