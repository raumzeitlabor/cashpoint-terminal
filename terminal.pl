#!/usr/bin/perl
use strict;
use warnings;

use EV;
use AnyEvent;
use Cashpoint::Client::LCD;
use Cashpoint::Client::Scanner;

$| = 1;

my $scanner = Cashpoint::Client::Scanner->new('/dev/ttyUSB0');
$scanner->on_scan(sub { print "scan: ".shift."\n"; });

my $lcd = Cashpoint::Client::LCD->new("./lcd");
$lcd->show("FUCK U\n\n\n\n");

EV::loop;
