
use strict ;
use warnings ;

use Module::Build;

my %all_modules ;
my @split_modules ;

my @pm_files = qw(

PBS/Build/ForkedNodeBuilder.pm
PBS/Build/Forked.pm
PBS/Build/NodeBuilder.pm
PBS/Build.pm
PBS/Caller.pm
PBS/Check/ForkedCheck.pm
PBS/Check.pm
PBS/Config.pm
PBS/Config/Subpbs.pm
PBS/Config/Options.pm
PBS/Constants.pm
PBS/Cyclic.pm
PBS/Debug.pm
PBS/DefaultBuild.pm
PBS/Depend.pm
PBS/Digest.pm
PBS/Distributor.pm
PBS/Documentation.pm
PBS/FrontEnd.pm
PBS/Graph/Html.pm
PBS/Graph.pm
PBS/Graph/Snapshots.pm
PBS/GraphViz.pm
PBS/Information.pm
PBS/Log/ForkedLNI.pm
PBS/Log/Full.pm
PBS/Log/Html.pm
PBS/Log.pm
PBS/Net.pm
PBS/Node.pm
PBS/Nop.pm
PBS/Output.pm
PBS/Options/Complete.pm
PBS/PBSConfig.pm
PBS/PBSConfigSwitches.pm
PBS/PBS/Forked.pm
PBS/PBS.pm
PBS/Plugin.pm
PBS/PostBuild.pm
PBS/PrfNop.pm
PBS/Prf.pm
PBS/Rules/Builders.pm
PBS/Rules/Dependers.pm
PBS/Rules/Dependers/Subpbs.pm
PBS/Rules/Order.pm
PBS/Rules.pm
PBS/Rules.pm
PBS/Rules/Scope.pm
PBS/Shell.pm
PBS/Shell/SSH.pm
PBS/Shell/Telnet.pm
PBS/Stack.pm
PBS/SubpbsResult.pm
PBS/Triggers.pm
PBS/Version.pm
PBS/Warp.pm
PBS/Warp/Warp0.pm
PBS/Warp/Warp1_5.pm
PBS/Warp/Warp1_8.pm
PBS/Watch/Client.pm
PBS/Watch/InotifyWatcher.pm
PBS/Watch/Win32Watcher.pm
PBS/Wizard.pm
);

for(@pm_files)
	{
	$all_modules{$_} = "lib/$_" ;
	push @split_modules, $_ ;
	}

my @extra_modules =
qw(
Plugins/CheckNodeName.pm
Plugins/CheckNode.pm
Plugins/ColorDefinitions.pm
Plugins/CreateDump.pm
Plugins/CreateLog.pm
Plugins/EvaluateShellCommand.pm
Plugins/ExpandObjects.pm
Plugins/FileWatchClient.pm
Plugins/GraphGeneration.pm
Plugins/MyOptions.pm
Plugins/PackageVisualisation.pm
Plugins/PostPbs.pm
Plugins/SimplifyRule.pm
Plugins/TreeVisualisation.pm
Plugins/Visualisation.pm
) ;

for(@extra_modules)
        {
        $all_modules{$_} = "lib/PBS/$_" ;
        }

my @PBSLib =
qw(

PBSLib/Builders/Objects.pm
PBSLib/Builders/SingleRunBuilder.pm

PBSLib/Node/Config.pm

PBSLib/Configs/Compilers/cl.pm
PBSLib/Configs/Compilers/compiler.pm
PBSLib/Configs/Compilers/gcc.pm
PBSLib/Configs/Compilers/old_gcc.pm
PBSLib/Configs/ConfigureProject.pm
PBSLib/Configs/ConfigureProjectVariablesAndRules.pm
PBSLib/Configs/ShellCommands.pm

PBSLib/Dependers/AddDependencies.pm
PBSLib/Dependers/Locator.pm
PBSLib/Dependers/Matchers.pm

PBSLib/Language/Simplified.pm

PBSLib/Rules/C_depender.pm
PBSLib/Rules/C_EvalShellCommand.pm
PBSLib/Rules/C.pm
PBSLib/Rules/Object_rules_utils.pm

PBSLib/Rules/Compilers/cl.pm
PBSLib/Rules/Compilers/compiler.pm
PBSLib/Rules/Compilers/gcc.pm

PBSLib/Rules/NodeSubs/Config.pm

PBSLib/Rules/cl_pch.pm
PBSLib/Rules/VisualStudioDSP.pm
PBSLib/Rules/VisualStudioProject.pm

PBSLib/UserBuild/BuildSequenceMiner.pm
PBSLib/UserBuild/Multiple_O_Compile.pm

PBSLib/Utils/VisualStudioProjectFile.pm

PBSLib/Wizards/Breakpoint.pl
PBSLib/Wizards/BuilderSub.pl
PBSLib/Wizards/DependentMatcher.pl
PBSLib/Wizards/Distributor.pl
PBSLib/Wizards/menu.pl
PBSLib/Wizards/NodeSub.pl
PBSLib/Wizards/Plugin.pl
PBSLib/Wizards/PostBuild.pl
PBSLib/Wizards/PostPbs.pl
PBSLib/Wizards/Prf.pl
PBSLib/Wizards/SimpleDependerSub.pl
PBSLib/Wizards/StandardPbsfile.pl
PBSLib/Wizards/Subpbs.pl
PBSLib/Wizards/template.pl

PBSLib/Guides/insert_options.pl
PBSLib/Guides/interactive.pl
PBSLib/Guides/interactive_list.pl
PBSLib/Guides/man.pl
PBSLib/Guides/smenu.pl
) ;

for(@PBSLib)
	{
	$all_modules{$_} = "lib/PBS/$_" ;
	}

sub GetVersionAndRevisionFrom
{
my ($file) = @_ ;

my $version_from = File::Spec->catfile( split '/', $file );
my $version      = Module::Build->version_from_file($version_from);

if(-d '.git')
        {
        my $number_of_commits = `git log --format="%H" | wc -l` ;
        chomp $number_of_commits ;

	my $latest_commit = `git log --format="%H" -1` ;
	chomp $latest_commit ;
	
        if($number_of_commits)
                {
                #print "number of git revision: $number_of_commits.\n" ;
                return("${version}.${number_of_commits}", $latest_commit) ;
                }
        else
                {
                print "Couldn't get git revision, using version from '$file'!\n" ;
                return($version, '') ;
                }
        }
else
        {
        return($version) ;
        }
}

my $code = <<'EOC' ;
#~ use Data::TreeDumper ;
#~ print DumpTree \@_, 'args:' ;

sub GetVersionAndRevisionFrom
{
my ($file) = @_ ;

my $version_from = File::Spec->catfile( split '/', $file );
my $version      = Module::Build->version_from_file($version_from);

if(-d '.git')
        {
        my $number_of_commits = `git log --format="%H" | wc -l` ;
        chomp $number_of_commits ;

	my $latest_commit = `git log --format="%H" -1` ;
	chomp $latest_commit ;
	
        if($number_of_commits)
                {
                #print "number of git revision: $number_of_commits.\n" ;
                return("${version}.${number_of_commits}", $latest_commit) ;
                }
        else
                {
                print "Couldn't get git revision, using version from '$file'!\n" ;
                return($version, '') ;
                }
        }
else
        {
        return($version) ;
        }
}

sub ACTION_build 
{
my $self = shift;

if(-d '.git')
	{
	my ($pbs_version, $commit) = GetVersionAndRevisionFrom('PBS/FrontEnd.pm') ;
	$pbs_version .= "_$commit" ;

	print "Generating version module ($pbs_version)\n" ;
	
	open VERSION, '>', 'PBS/Version.pm' or die "can't generate Version module: $!\n" ;
	
	print VERSION <<EOV ;
	
	# version module automatically generated by the build system
	
	package PBS::Version ;
	
	sub GetVersion {return '$pbs_version'} ;
	
	# generated from commit $commit
	
	1 ;
	
	# end of generated version module
EOV
	
	close VERSION ;

	}
	
`git log > Changes` ;

$self->SUPER::ACTION_build(@_);
}

EOC


my $class = Module::Build->subclass(class => 'PBS::Builder', code => $code) ;

my $build = $class->new
	(
	module_name => 'PerlBuildSystem',
	
	dist_version => (GetVersionAndRevisionFrom('PBS/FrontEnd.pm'))[0],
	
	license => 'perl',
	configure_requires => 
		{
		'Net::SCP' => 0,
		} ,
	
	build_requires => 
		{
		'File::Copy::Recursive' => '0',
		'File::Slurp'         => '0',
		'File::Spec'          => '0',
		'IO::String'          => '0',
		'Net::SCP' => 0,
		'Test::Block' => 0,
		'Test::Class'         => '0',
		'Test::Cmd'           => '0',
		'Test::Exception' => 0,
		'Test::NoWarnings' => 0,
		'Test::Warn' => 0,
		'Text::Diff' => 0,
		},
	requires => 
		{
		'Class::MethodMaker'  => '0',
		'Cwd'                 => '2.06',
		'Data::Compare'       => '0',
		'Data::Compare'       => '0',
		'Data::Dumper'        => '2.12',
		'Data::TreeDumper'    => '0.39',
		'Devel::Cycle'        => '0',
		'File::Basename'      => '2.71',
		'File::MkTemp'        => '0',
		'Getopt::Long'        => '2.32',
		'List::PriorityQueue' => 0,
		'Module::Build'       => '0.2611',
		'Module::Util'       => '0.2611',
		'Net::SCP'            => 0,
		'PadWalker'           => '0',
		'Pod::Simple::Search' => '0',
		'String::Truncate'    => 0,
		'Sub::Identify'       => 0,
		'Sub::Name'           => 0,
		'Term::ANSIColor'     => '0',
	        'Term::Bash::Completion::Generator' => 0.04,
	        'Term::ReadKey'       => '0',
		'Term::Size::Any'     => '0',
		'Text::ANSI::Util'    => '0',

		'Devel::Depend::Cpp'  => '0.10',
		'Devel::Depend::Cl'   => '0.06',
		},
		
	pm_files     => \%all_modules,
	
	script_files => ['script/pbs.pl', 'script/watch_server.pl'],
	dist_author  => 'Khemir Nadim ibn Hamouda. <nadim@khemir.net>',
	dist_abstract => 'Build utility/modules in the same spirit as gmake',
	);
	
$build->create_build_script;
  
