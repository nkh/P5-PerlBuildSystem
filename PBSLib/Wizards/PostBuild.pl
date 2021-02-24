# WIZARD_GROUP PBS
# WIZARD_NAME  post_build
# WIZARD_DESCRIPTION template for a post build rulle
# WIZARD_ON

print <<'EOT' ;

AddPostBuildCommand 'post_build', ['a', 'b'], \&PostBuildCommandTest, 'hi' ;

sub PostBuildCommandTest
{
my ($build_result, $build_message, $config, $names, $dependencies, $triggered_dependencies, $argument, $node, $inserted_nodes) = @_ ;

return($build_result, $build_message) if $build_result != BUILD_SUCCESS ;

PrintUser DumpTree [$config, $names, $dependencies, $triggered_dependencies, $argument], 'Post Build:', USE_ASCII => 1 ;

return(1, "PostBuildCommandTest OK.") ;
}

EOT

# ------------------------------------------------------------------
1;

