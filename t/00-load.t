#!/usr/bin/env perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'MojoX::IOLoop::Throttle' ) || print "Bail out!\n";
}

diag( "Testing MojoX::IOLoop::Throttle $MojoX::IOLoop::Throttle::VERSION, Perl $], $^X" );
