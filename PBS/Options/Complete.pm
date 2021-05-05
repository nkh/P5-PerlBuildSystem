package PBS::Options::Complete ;

use v5.10 ; use strict ; use warnings ;

require Exporter ;

our @ISA         = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT      = qw() ;

our $VERSION = '0.01' ;

use File::Slurp ;
use File::Find::Rule ;
use List::Util qw(max any);
use Sort::Naturally ;
use Term::Bash::Completion::Generator ;
use Tree::Trie ;
	
use PBS::Output ;
use PBS::PBSConfigSwitches ;

#-------------------------------------------------------------------------------

=pod

pbs *
pbs text*

pbs [--]text
pbs text+number

pbs text?

pbs #file|number
pbs #man,page
pbs #smenu

pbs ** 

# use readline?, xdotool, ioctl, tmux

=cut

sub Complete
{
my ($guide_paths, $options, $options_elements, $word_to_complete, $AliasOptions, $DisplaySwitchesHelp) = @_ ;

if($word_to_complete =~ /^#/)
	{
	my $result ;
	
	local @ARGV =  split ',', $word_to_complete ;
	
	my ($guide, $argc) = ($ARGV[0] // '', $ARGV[1] // '') ;
	substr($guide, 0, 1, '') ;
	
	my %guides ;

	File::Find::Rule->file()->name('*.pl')->maxdepth(1)->exec( sub { push $guides{$_[0]}->@*, $_[1]} )
			->in( $guide_paths->@* ) ;
	
	if(exists $guides{"$guide.pl"})
		{
		my $file_located = $guides{"$guide.pl"}[0] . "/$guide.pl" ;
		
		$result = do "$file_located" ;
		die "PBS: couldn't evaluate file: $guide\nFile error: $!\nError: $@\n" unless defined $result;
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
			my $index = $guide - 1 ;
			my $file_located = "$guides[$index][1][0]/$guides[$index][0]" ;
			
			$result = do "$file_located" ;
			#die "PBS: couldn't evaluate SubpbsResult, file: $file_located\nFile error: $!\nError: $@\n" unless defined $result;
			}
		else
			{
			my $index = 1 ;
			open my $fzf_in, '>', 'pbs_fzf_guides' ;
			binmode $fzf_in ;
			
			print $fzf_in 
				EC substr(sprintf("<W3>%d <I>%-${max_length}s", $index++, $_->[0]) . " <I3>$_->[2]", 0, 99) . "<R>\n" for @guides ;
			
			my $query = $guide eq '' ? '' : "-q $guide" ;
			
			my ($n, $m) ;
			{
			local $/ = "R" ;
			print STDERR "\033[6n" ;
			($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
			print STDERR "\n" ;
			}
			
			my $fzf = qx"cat pbs_fzf_guides | fzf --height=30% --ansi --reverse -1 $query" ;
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
				my $index = $guide - 1 ;
				my $file_located = "$guides[$index][1][0]/$guides[$index][0]" ;
				
				$result = do "$file_located" ;
				#die "PBS: couldn't evaluate '$file_located', error: $!, exception: $@\n" unless defined $result ;
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

	my @fzf = qx"fd --color=always | fzf --height=30% --ansi --reverse -m" ;

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

if($word_to_complete =~ /\*$/ and 0 == system 'fzf --version > /dev/null')
	{
	my (@long, @options) ;
	
	my ($search) = $word_to_complete =~ /-?-?([^\*]+)\*+$/ ;
	$search //= '' ;
	
	for (@$options_elements)
		{
		my ($option_type) = @{$_} ;
		
		my ($option, $type) = $option_type  =~ m/^([^=]+)(=.*)?$/ ;
		$type //= '' ;
		
		my ($long, $short) = split(/\|/, $option, 2) ;
		$short //= '' ;
		
		next if $long !~ /$search/ && $short !~ /$search/ ;
		
		push @long, length($long) ;
		push @options, $long ; 
		}
	
	return unless @options ;
	
	my $max_long  = max(@long) + 2 + 5 ;
	
	open my $fzf_in, '>', 'pbs_fzf_options' ;
	binmode $fzf_in ;
	
	print $fzf_in "--$_\n" for @options ;
	
	my ($n, $m) ;
	{
	local $/ = "R" ;
	print STDERR "\033[6n" ;
	($n, $m) = (<STDIN> =~ m/(\d+)\;(\d+)/) ;
	}
	my @fzf = qx"cat pbs_fzf_options | fzfp -x $m -y $n --height=30% --width $max_long --reverse -m -q '$search'" ;

	print STDERR "\e[$n;${m}H" ;

	
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
	push @options, $slice[0] while (@slice = splice @$options, 0, 4 ) ; 
	
	my ($names, $option_tuples) = Term::Bash::Completion::Generator::de_getop_ify_list(\@options) ;
	
	my $aliases = $AliasOptions->([]) ;
	push @$names, keys %$aliases ;
	
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
					$munged = $reduce ?  $tuple->[0] : defined $tuple->[1] ? $tuple->[1] : $tuple->[0] ;
					last ;
					}
				}
			
			defined $munged ? "-$munged\n": "-$matches[0]\n" ;
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
				
				$DisplaySwitchesHelp->(@matches) ;
				
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
1 ;

__END__
=head1 NAME

PBS::Options::Complete - Helper functions for bash completion

=head1 DESCRIPTION

=head1 AUTHOR

Khemir Nadim ibn Hamouda. nadim@khemir.net

=cut

