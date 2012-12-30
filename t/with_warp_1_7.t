#!/usr/bin/env perl

use strict;
use warnings;

use Test::More ;

#~ SKIP:
#~ {
eval "use GDBM_File;" ;
#~ skip "Warp 1.7 needs module GDBM_File which is not installed:\n\n$@\n" if $@ ;

plan (skip_all => "Warp 1.7 needs module GDBM_File which is not installed:\n\n$@\n") if $@ ;

use t::AllTests;

t::PBS::set_global_warp_mode('1.7');
Test::Class->runtests;
#~ }