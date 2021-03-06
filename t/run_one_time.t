#!/usr/bin/env perl

# when all test fail:
# Add  $t->generate_test_snapshot_and_exit('dynamic_c_dependencies') ;

use strict;
use warnings;

#use t::Correctness::DependencyGraphIsNotATree;
#use t::Correctness::IncludeFiles ;
#use t::Correctness::CDepender ;
use t::Misc::ExtraDependencies ;

t::PBS::set_global_warp_mode('1.5');

#my $num_runs = 1 ;
#my $num_tests_per_run = t::Correctness::DependencyGraphIsNotATree->expected_tests();
#my $extra_tests = ($num_runs - 1) * $num_tests_per_run;
#t::Correctness::DependencyGraphIsNotATree->runtests($extra_tests);

#t::Correctness::DependencyGraphIsNotATree->runtests();
#t::Correctness::IncludeFiles->runtests();
#t::Correctness::CDepender->runtests();
t::Misc::ExtraDependencies->runtests() ;
