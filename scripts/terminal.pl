#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';

use 5.12.0;

use EV;
use Carp;
use AnyEvent;

use Data::Dumper;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Device::SerialPort;

use Cashpoint::Client;
use Cashpoint::Client::LCD;
use Cashpoint::Client::SerialInput;

$| = 1;

# state machine
use constant {
    MODE_START    => "MODE_START",
    MODE_PIN      => "MODE_PIN",
    MODE_AUTH     => "MODE_AUTH",
    MODE_AUTHED   => "MODE_AUTHED",

    TIMEOUT_PIN     => 5,     # time until the pin input will time out
    TIMEOUT_ERROR   => 10,    # time a fatal error message will be shown
    TIMEOUT_SCANNER => 20,
};

my $mode = MODE_START;

# will be used for storing timers etc; is regularly cleaned up
my @heap = ();

# will be used for timeouts
my $timer;

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
$client->{debug} = 1;

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

# rfid reader
$dev = Device::SerialPort->new('/dev/ttyUSB2') or croak $!;
$dev->baudrate(9600);
$dev->databits(8);
$dev->parity("none");
$dev->stopbits(1);

my $rfid = Cashpoint::Client::SerialInput->new($dev, [chunk => 14]);

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

sub switch_mode {
    my $mode = shift;
    DEBUG "MODE = $mode";
}

sub start {
    # backlight timer
    $timer = AnyEvent->timer(after => 5, cb => sub { $lcd->off });

    %context = ();

    $lcd->on;
    $lcd->reset;
    $lcd->show("2ce", "RaumZeitLabor e.V. Cashpoint");

    # disable pinpad cb
    $pinpad->on_recv(sub {});

    # enable rfid reader
    $rfid->on_recv(sub {
        my $raw = shift;

        # first byte is start flag, last byte is end flag
        if ($raw =~ m/^\\u0002([a-z0-9]{12})\\0003$/i) {
            my $code = $1;
        } else {
            WARN "invalid rfid: ".sprintf("%x", $raw);
            return;
        }

        if ($mode eq MODE_START) {# && $code =~ m/^#[a-z0-9]{18}$/i) {
            $context{cashcard} = $code;
            read_pin();
        }
    });

    switch_mode(MODE_START);
    INFO "ready!";
}

sub read_pin {
    my $code = shift;
    my ($cb, $pin) = (undef, "");

    switch_mode(MODE_PIN);
    INFO "reading pin…";

    # disable backlight timer
    $timer = undef; $lcd->on;

    # disable rfid reader
    $rfid->on_recv(sub {});

    $lcd->show("2ce", "Speak, friend, and enter.");

    $pinpad->ae->on_rtimeout(sub {
        INFO "no activity on pinpad, timing out";
        $pinpad->ae->on_rtimeout(undef);
        $pinpad->ae->rtimeout(0);
        start;
    });
    $pinpad->ae->rtimeout_reset;
    $pinpad->ae->rtimeout(TIMEOUT_PIN);

    $cb = $pinpad->on_recv(sub {
        my $input = shift;
        # check if the user pressed return
        if ($input eq "#") {
            # disable pin timeout
            $pinpad->ae->on_rtimeout(undef);
            $pinpad->ae->rtimeout(0);

            # cancel if the pin was empty
            if (length $pin == 0) {
                WARN "pin is empty, resetting";
                $lcd->show("2cen", "You did not enter a PIN.");
                $lcd->show("3ce", "Please try again.");
                $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                    INFO "error timeout";
                    start;
                });
                return;
            }

            # the pin is not saved in the context
            authenticate($pin);

        } else {
            $pin .= $input if $input =~ /^\d+$/;
            $lcd->show("3ce", "*" x length $pin);
        }
    });
};

sub authenticate {
    my $pin = shift;

    switch_mode(MODE_AUTH);
    INFO "authenticating…";

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
        $lcd->show("2cen", "- authorized as $r->{user}->{name} -");
        $lcd->show("3ce", "Please start scanning your products.");

        switch_mode(MODE_AUTHED);
        create_basket();

    } else {
        if ($s eq '401') {
            my $attempts = $r->{attempts_left};
            $lcd->show("2cen", "Authorization Failed!");
            $lcd->show("3ce", "You have ".$attempts." more tries.");
        } elsif ($s eq '403') {
            $lcd->show("2cen", "There have been too many failed logins.");
            $lcd->show("3ce", "Please try again in five minutes.");
        } else {
            $lcd->show("2cen", "Uh-oh, there seems to be a problem!");
            $lcd->show("3ce", "Please try again later. Thank you.");
        }

        $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
            INFO "error timeout";
            start;
        });
    }
};

sub create_basket {
    # try to create a basket
    $client->create_basket(sub {
        my ($s, $r) = @_;

        if ($s eq '201') {
            $context{basket} = $r->{id};

            # enable scanner cb
            $scanner->on_recv(sub {
                my $code = shift;
                add_product($code);
            });

            $lcd->show("2ce", "Please start scanning your products.");

        } else {
            $lcd->show("2cen", "WHY U NO WORKING");
            $lcd->show("3ce", "Sorry, please try again later.");

            $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                INFO "error timeout";
                start;
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

            $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                INFO "error timeout";
                start;
            });
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
