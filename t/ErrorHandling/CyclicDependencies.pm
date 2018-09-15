#!/usr/bin/env perl

# Tests for detection of cycles in the dependency graphs.

package t::ErrorHandling::CyclicDependencies;

use strict;
use warnings;

use base qw(Test::Class);

use Test::More;
use t::PBS;

my $t;

sub setup : Test(setup) {
    $t = t::PBS->new(string => 'Cyclic dependencies');

    $t->build_dir('build_dir');
    $t->target('test-c' . $t::PBS::_exe);
    $t->command_line_flags('-die_source_cyclic_warning');
}


unless (caller()) {
    #    t::PBS::set_global_warp_mode('1.0');
    $ENV{"TEST_VERBOSE"} = 1;
    Test::Class->runtests;
}

1;
