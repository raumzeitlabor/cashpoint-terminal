#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';

use EV;
use utf8;
use AnyEvent;
use Cashpoint::Client::LCD;
use Cashpoint::Client::Scanner;
use Cashpoint::Client::InputReader;

use constant {
    START      => 0,
    AUTHORIZE  => 1,
    AUTHORIZED => 2,
};

$| = 1;

my $mode = START;

#my $reader = Cashpoint::Client::InputReader->new('/tmp/terminalinput');
my $scanner = Cashpoint::Client::Scanner->new('/dev/ttyUSB0');
my $lcd = Cashpoint::Client::LCD->new('./lcd', '4x40');

sub scan_dispatcher {
    my $code = shift;

    if ($mode eq START && $code =~ m/^#/) {
        print "Entering AUTH mode\n";
        $mode = AUTHORIZE;
    } elsif ($mode eq AUTHORIZED && $code =~ m/^F{1,2}/) {
        print "product scanned";
    }
}

$scanner->on_scan(\&scan_dispatcher);
$lcd->clear;
$lcd->append("hallo welt\n\n\n");
#$lcd->show(1, 'FICKT EUCH');
#$lcd->show("2c", 'RaumZeitLabor e.V. Cashpoint');
#$lcd->show("3l", 'links');
#$lcd->show("4r", 'rechts');
#$lcd->show("2r", "aaa1,50 EUR");
#$lcd->show("1r", "hallo welt");
#$lcd->show("3c", "mitte");
#$lcd->clear;

EV::loop;
