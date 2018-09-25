#!/usr/bin/env perl

# Tests the C depender and its handling of dependency cache files.

package t::Correctness::CDepender;

use strict;
use warnings;

use base qw(Test::Class);

use File::Copy::Recursive qw(rcopy);
use Test::More;
use t::PBS;

my $t;

sub setup : Test(setup) {
    $t = t::PBS->new(string => 'C depender');

    $t->setup_test_data('c_depender');

    $t->build_dir('build_dir');
    $t->target('test-c.exe');

    $t->write('post_pbs.pl', <<'_EOF_');
    for my $node ( @{$dependency_tree->{__BUILD_SEQUENCE}}) {
	print "Rebuild node $node->{__NAME}\n";
    }
1;
_EOF_

    $t->command_line_flags('--post_pbs=post_pbs.pl -dsi -ndpb -no_color');
}

sub copy_from_pbsfiles_dir {
	my ($src,
		$dst) = @_;

	$t->setup_test_data_file('c_depender', $src, $dst);
}

sub change_include_file : Test(8) {
# Build
    #$t->generate_test_snapshot_and_exit() ;

    $t->build_test;
    $t->run_target_test(stdout => "ab");

    $t->test_up_to_date;

# Modify the first include file and rebuild
	copy_from_pbsfiles_dir('a2.h', 'a.h');
		
    $t->build_test;
    $t->run_target_test(stdout => "a2b");

    $t->test_up_to_date;
}

sub use_unsynchronized_cache : Test(10) {
# Build
	$t->build_test;
	
# Introduce an error in the first C file and modify the second
# include file.
	copy_from_pbsfiles_dir('1_error.c', '1.c');
	copy_from_pbsfiles_dir('b2.h', 'b.h');
		
# Rebuild.
#
# The second C file will be redepended, but the C depend cache
# of the second C file will not be synchronized, because the
# build will already fail with the compilation of the first C
# file, and that is before the C depend cache of the second C
# file is going to be synchronized.

	$t->build_test_fail;
	
# Fix the error in the first C file.
	copy_from_pbsfiles_dir('1_2.c', '1.c');

# Rebuild.
#
# The C depender will try to redepend the second C file, but it
# will find the unsynchronized cache, verify it, and use it.
	$t->build_test;
	my $stdout = $t->stdout;
	
	$t->run_target_test(stdout => "ab2");
}


unless (caller()) {
    $ENV{"TEST_VERBOSE"} = 1;
    Test::Class->runtests;
}

1;
