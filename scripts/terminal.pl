#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';

use EV;
use Carp;
use AnyEvent;

use Data::Dumper;
use Log::Log4perl qw(:easy);

use Device::SerialPort;

use Cashpoint::Client;
use Cashpoint::Client::LCD;
use Cashpoint::Client::SerialInput;

$| = 1;

# state machine
use constant {
    MODE_START    => 0,
    MODE_AUTH     => 1,
    MODE_AUTHED   => 2,

    TIMEOUT_PIN   => 5,     # time until the pin input will time out
    TIMEOUT_RETRY => 5,     # time after which a failed auth can be started again
    TIMEOUT_ERROR => 15,    # time a fatal error message will be shown
};

my $mode = MODE_START;

# will be used for storing timers etc; is regularly cleaned up
my @heap = ();

# contains the context of the currently auth'ed user
my %context = (
    cashcard => undef,
    user     => undef,
    role     => undef,
    basket   => undef,
    auth     => undef,
);

##################################################

# client library
my $client = Cashpoint::Client->new("http://172.22.37.76:3000");

# lcd output
my $lcd = Cashpoint::Client::LCD->new('4x40');

# pinpad input
my $dev = Device::SerialPort->new('/dev/ttyUSB3') or croak $!;
$dev->baudrate(9600);
$dev->databits(8);
$dev->parity("none");
$dev->stopbits(1);

my $pinpad = Cashpoint::Client::SerialInput->new($dev, [chunk => 1]);

# scanner input
$dev = Device::SerialPort->new('/dev/ttyUSB0') or croak $!;
$dev->baudrate(9600);
$dev->databits(8);
$dev->parity("none");
$dev->stopbits(1);

my $scanner = Cashpoint::Client::SerialInput->new($dev);
$scanner->on_recv(sub {
    my $code = shift;

    if ($mode eq MODE_START && $code =~ m/^#[a-z0-9]{18}$/i) {
        #$context{cashcard} = substr($code, 1);
        #read_pin();
    } elsif ($mode eq MODE_AUTH && $code =~ m/^#[a-z0-9]{18}$/i) {
    } elsif ($mode eq MODE_AUTHED && $code =~ m/^F{1,2}([0-9]{8}|[0-9]{12})$/) {
        add_product($code);
    }
});

# rfid reader
$dev = Device::SerialPort->new('/dev/ttyUSB2') or croak $!;
$dev->baudrate(9600);
$dev->databits(8);
$dev->parity("none");
$dev->stopbits(1);

my $rfid = Cashpoint::Client::SerialInput->new($dev, [chunk => 14]);
$rfid->on_recv(sub {
    my $code = shift;

    # XXX: chksum prüfen
    if ($mode eq MODE_START) {# && $code =~ m/^#[a-z0-9]{18}$/i) {
        $context{cashcard} = substr($code);
        read_pin();
    }
});

##################################################
# General Flow:
# 1. Either RFID or Scanner callback gets triggered.
#    State == MODE_START
# 2. read_pin is called
#    State == MODE_AUTH
#
#    on success:
#    State == MODE_AUTHED
# 3. create_basket creates an empty basket
# 4. Each SCAN add $product to basket.
##################################################

sub start {
    $mode = MODE_START;
    %context = ();
    #$reader->reset_cb;
    $lcd->reset;
    $lcd->show("2ce", "RaumZeitLabor e.V. Cashpoint");
}

sub read_pin {
    my $code = shift;
    my ($cb, $pin, $timer) = (undef, "");

    $lcd->show("2ce", "Please enter your PIN:");

    # this is called to cancel the authorization process
    my $cancel = sub {
        return unless $mode == MODE_AUTH;

        # make sure the input receiver is disabled
        undef $timer if $timer;
        #$reader->reset_cb;
    };

    $cb = $pinpad->on_recv(sub {
        my $input = shift;
        # check if the user pressed return
        if ($input eq "#") {

            # stop listening for input
            &$cancel();

            # cancel if the pin was empty
            if (length $pin == 0) {
                start();
                return;
            }

            # the pin is not saved in the context
            authenticate($pin);
        }

        $pin .= $input if $input =~ /^\d+$/;
        $lcd->show("3ce", "*" x length $pin);
        $timer = AnyEvent->timer(after => TIMEOUT_PIN, cb => $cancel);
    });

    # if the user does not enter anything for more than five seconds,
    # we cancel the authorization process
    $timer = AnyEvent->timer(after => TIMEOUT_PIN, cb => $cancel);
};

sub authenticate {
    my $pin = shift;

    my ($s, $r) = $client->auth_by_pin($context{cashcard}, $pin);
    $lcd->show("3ce", "");

    if ($s eq '200') {
        # save the context information
        @context{qw/user role auth/} = (
            $r->{user}->{id},
            $r->{role},
            $r->{auth_token}
        );

        # display appropriate information
        $lcd->show("2ce", "Successfully Authorized");

        # try to create a basket
        create_basket();

    } else {
        if ($s eq '401') {
            $lcd->show("2ce", "Authorization Failed!");
        } elsif ($s eq '403') {
            $lcd->show("2ce", "There have been too many failed logins.");
            $lcd->show("3ce", "Please try again in five minutes.");
        } else {
            $lcd->show("2ce", "Uh-oh, there seems to be a problem!");
            $lcd->show("3ce", "Please try again later. Thank you.");
        }

        push @heap, AnyEvent->timer(after => TIMEOUT_RETRY, cb => sub {
            return if $mode == MODE_START;
            start();
        });
    }
};

sub create_basket {
    # try to create a basket
    $client->create_basket(sub {
        my ($s, $r) = @_;

        if ($s eq '201') {
            $mode = MODE_AUTHED;
            $context{basket} = $r->{id};

            # if the user hasn't started scanning yet, tell him
            push @heap, AnyEvent->timer(after => 3, cb => sub {
                $lcd->show("2ce", "Please start scanning your products.");
            });

        } else {
            # this should not happen, but who knows.
            $mode = MODE_START;

            $lcd->show("2ce", "WHY U NO WORKING");
            $lcd->show("3ce", "Sorry, please try again later.");

            push @heap, AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                return if $mode == MODE_START;
                start();
            });
        }
    });
};

sub add_product {
    my $code = shift;

    $client->add_product($context{auth}, $context{basket}, $code, sub {
        my ($s, $r) = @_;
        if ($s eq '201') {
            my $line = $lcd->append($r->{name});
            $lcd->show($line."r", " ".$r->{price}." EUR");
        } else {
            $lcd->show("2ce", "WHY U NO WORKING");
            $lcd->show("3ce", "Sorry, please try again later.");
        }
    });
};

my $heap_cleaner = AnyEvent->timer(
    interval => 60,
    after    => 60,
    cb       => sub { map { undef $_ unless $_ } @heap; }
);

start();

EV::loop;
