#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';

use 5.12.0;

use EV;
use Carp;
use AnyEvent;

use Data::Dumper;
use AnyEvent::Socket;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Cashpoint::Terminal;
use Cashpoint::Client;
use Cashpoint::Client::LCD;
use Cashpoint::Client::SerialInput;

$| = 1;

# client library
my $client = Cashpoint::Client->new("http://172.22.37.76:3000");
$client->{debug} = 1;

my ($cpd, $dev1, $dev2, $dev3);

my ($lcd, $dev, $pinpad, $scanner, $rfid, $debug);
if (exists $ENV{CASHPOINT_ENVIRONMENT} && $ENV{CASHPOINT_ENVIRONMENT} eq 'testing') {
    use Cashpoint::Driver;

    $client->{debug} = $debug = 1;

    $cpd = Cashpoint::Driver->new;
    $pinpad = Cashpoint::Client::SerialInput->new(
        fh => $cpd->get_pinpad, method => [chunk => 1]
    );
    $scanner = Cashpoint::Client::SerialInput->new(
        fh => $cpd->get_scanner
    );
    $rfid = Cashpoint::Client::SerialInput->new(
        fh => $cpd->get_rfid, method => [chunk => 14]
    );

} else {
    use Device::SerialPort;

    # pinpad input
    $dev1 = Device::SerialPort->new('/dev/ttyUSB3') or croak "pinpad: $!";
    $dev1->baudrate(9600);
    $dev1->databits(8);
    $dev1->parity("none");
    $dev1->stopbits(1);
    
    $pinpad = Cashpoint::Client::SerialInput->new(
        fh => $dev1->{HANDLE}, method => [chunk => 1]
    );
    
    # scanner input
    $dev2 = Device::SerialPort->new('/dev/ttyUSB0') or croak "scanner: $!";
    $dev2->baudrate(9600);
    $dev2->databits(8);
    $dev2->parity("none");
    $dev2->stopbits(1);
    
    $scanner = Cashpoint::Client::SerialInput->new(
        fh => $dev2->{HANDLE}
    );
    
    # rfid reader
    $dev3 = Device::SerialPort->new('/dev/ttyUSB2') or croak "rfid: $!";
    $dev3->baudrate(9600);
    $dev3->databits(8);
    $dev3->parity("none");
    $dev3->stopbits(1);
    
    $rfid = Cashpoint::Client::SerialInput->new(
        fh => $dev3->{HANDLE}, method => [chunk => 14]
    );
}

# lcd output
$lcd = Cashpoint::Client::LCD->new('4x40', debug => $debug);
    
cp_init(
    client  => $client,
    lcd     => $lcd,
    rfid    => $rfid,
    scanner => $scanner,
    pinpad  => $pinpad
);

cp_start;

if ($debug) {
    my $w; $w = AnyEvent->timer(after => 0.5, cb => sub {
        $cpd->rfid->push_write("\x023C10CDA84D15\x03");
        $cpd->pinpad->push_write("123456#");
    
        $w = AnyEvent->timer(after => 1, cb => sub {
            $cpd->scanner->push_write("4029764001807\r\n");
            undef $w;
            $cpd->pinpad->push_write("#");
        });
    });
}

EV::loop;
