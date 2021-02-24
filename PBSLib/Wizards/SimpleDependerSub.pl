# WIZARD_GROUP PBS
# WIZARD_NAME  depender
# WIZARD_DESCRIPTION template for a depender sub
# WIZARD_ON

print <<'EOP' ;
use File::Basename ;

sub Depender
{
my ($dependent_to_check, $config, $tree, $inserted_nodes) = @_ ;

my ($triggered, @my_dependencies) ;

# add dependencies
my ($basename, $path, $ext) = File::Basename::fileparse($dependent_to_check, ('\..*')) ;
my $name = $basename . $ext ;
$path =~ s/\/$// ;

push @my_dependencies, "$path/..." ;
$triggered = 1 ;

$triggered, @my_dependencies
}

EOP


