#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Cashpoint::Client' ) || print "Bail out!\n";
}

diag( "Testing Cashpoint::Client $Cashpoint::Client::VERSION, Perl $], $^X" );
