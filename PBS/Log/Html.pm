
package PBS::Log::Html ;
use PBS::Debug ;

use strict ;
use warnings ;

use 5.006 ;
 
require Exporter ;

our @ISA = qw(Exporter) ;
our %EXPORT_TAGS = ('all' => [ qw() ]) ;
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } ) ;
our @EXPORT = qw() ;
our $VERSION = '0.01' ;

use Data::TreeDumper;
use File::MkTemp;
use File::Path;
use FileHandle;
use POSIX qw(strftime);
use Cwd ;
use Term::ANSIColor qw(:constants) ;

use PBS::Log ;
use PBS::Output ;
use PBS::PBSConfig ;

my $template = <<'EOT' ;
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
.div {
    border: none;
    outline: none;
    cursor: pointer;
    padding: 20px 28px;
    font-size: 14px;
i   margin=0 ;
}

</style>

<style>
ul.breadcrumb {
    padding: 8px 8px;
    list-style: none;
    background-color: #eee;
    margin= 0px 0px ; 
}
ul.breadcrumb li {
    display: inline;
    font-size: 14px;
}
ul.breadcrumb li+li:before {
    padding: 4px;
    color: black;
    content: "/\00a0";
}
ul.breadcrumb li a {
    color: #0275d8;
    text-decoration: none;
}
ul.breadcrumb li a:hover {
    color: #01447e;
    text-decoration: underline;
}
</style>
<style>

/* Style the tab */
.tab {
    overflow: hidden;
    border: 1px solid #ccc;
    background-color: #f1f1f1;
    position: fixed; /* Set the navbar to fixed position */
    top: 0; /* Position the navbar at the top of the page */
    width: 100%; /* Full width */
}

/* Style the buttons inside the tab */
.tab button {
    background-color: inherit;
    float: left;
    border: none;
    outline: none;
    cursor: pointer;
    padding: 8px 8px;
    transition: 0.3s;
    font-size: 14px;
}

/* Change background color of buttons on hover */
.tab button:hover {
    background-color: #ddd;
}

/* Create an active/current tablink class */
.tab button.active {
    background-color: #ccc;
}

/* Style the tab content */
.tabcontent {
    display: none;
    padding: 4px 4px;
    border: 1px solid #ccc;
    border-top: none;
}
</style>
</head>
<body>

<div class="tab">
  <button class="tablinks" onclick="open_tab(event, 'node info')" >Node Info</button>
  <button class="tablinks" onclick="open_tab(event, 'build buffer') "id="defaultOpen">Build buffer</button>
  <button class="tablinks" onclick="open_tab(event, 'log')">Log</button>
<button class="tablinks" onclick="open_tab(event, 'graph')">Graph</button>
<br/>
<ul class="breadcrumb">
  <li><a href="#">Parent</a></li>
  <li><a href="#">Parent</a></li>
  <li><a href="#">Parent</a></li>
  <li>Compiler_1</li>
</ul>

</div>

<div><br><br><br><br></div>
<div id="node info" class="tabcontent">

<pre>
Node Info

</pre>
</div>

<div id="build buffer" class="tabcontent" style="background-color: black ;">
build buffer
</div>

<div id="log" class="tabcontent">
<pre>
LOG
</pre>
</div>

<div id="graph" class="tabcontent">
<IMG SRC="graph.png" USEMAP=#mainmap>

<IMG>
</div>

<script>
function open_tab(evt, cityName) {
    var i, tabcontent, tablinks;
    tabcontent = document.getElementsByClassName("tabcontent");
    for (i = 0; i < tabcontent.length; i++) {
        tabcontent[i].style.display = "none";
    }
    tablinks = document.getElementsByClassName("tablinks");
    for (i = 0; i < tablinks.length; i++) {
        tablinks[i].className = tablinks[i].className.replace(" active", "");
    }
    document.getElementById(cityName).style.display = "block";
    evt.currentTarget.className += " active";
}

// Get the element with id="defaultOpen" and click on it
document.getElementById("defaultOpen").click();
</script>
     
</body>
</html> 

EOT

sub LogNodeData
{
my ($node, $redirection_path, $redirection_file, $redirection_file_log) = @_ ;

# Nodes.
my $GetAttributesOnly = sub
	{
	my $tree = shift ;

	if('HASH' eq ref $tree)
		{
		return
			(
			'HASH',
			undef,
			sort
				grep 
					{ 
					/^[A-Z_]/ 
					&& ($_ ne '__DEPENDENCY_TO') 
					&& ($_ ne '__PARENTS')
					&& defined $tree->{$_}
					} keys %$tree 
			) ;
		}

	return (Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
	} ;
			
# colorize tree in blocks
my @colors = map { Term::ANSIColor::color($_) }	( 'green', 'yellow', 'cyan') ;

my $node_tree_dump  = DumpTree
			(
			$node,
			"$node->{__NAME}:",
			FILTER => $GetAttributesOnly,
			USE_ASCII => 1,
			COLOR_LEVELS => [\@colors, ''],									
			#RENDERER => 'DHTML',
			)  ;
				
}


