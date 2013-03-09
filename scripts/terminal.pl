#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';

use EV;
use Carp;
use AnyEvent;

use Device::SerialPort;

use Cashpoint::Client;
use Cashpoint::Client::LCD;
use Cashpoint::Client::SerialInput;

use constant {
    MODE_START    => 0,
    MODE_AUTH     => 1,
    MODE_AUTHED   => 2,
    MODE_BASKET   => 3,
    MODE_SHOPPING => 4,

    TIMEOUT_PIN   => 5,     # time until the pin input will time out
    TIMEOUT_RETRY => 5,     # time after which a failed auth can be started again
    TIMEOUT_ERROR => 15,    # time a fatal error message will be shown
};

$| = 1;

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

# client library
my $client = Cashpoint::Client->new("http://localhost:3000");

# pinpad input
my $dev = Device::SerialPort->new('/dev/pinpad') or croak $!;
$dev->baudrate(9600);
$dev->databits(8);
$dev->parity("none");
$dev->stopbits(1);

my $pinpad = Cashpoint::Client::SerialInput->new($dev);

# scanner input
$dev = Device::SerialPort->new('/dev/scanner') or croak $!;
$dev->baudrate(9600);
$dev->databits(8);
$dev->parity("none");
$dev->stopbits(1);

my $scanner = Cashpoint::Client::SerialInput->new($dev);
$scanner->on_recv(sub {
    my $code = shift;

    if ($mode eq MODE_START && $code =~ m/^#[a-z0-9]{18}$/i) {
        $context{cashcard} = substr($code, 1);
        read_pin();
    } elsif ($mode eq MODE_AUTH && $code =~ m/^#[a-z0-9]{18}$/i) {
    } elsif ($mode eq MODE_AUTHED && $code =~ m/^F{1,2}([0-9]{8}|[0-9]{12})$/) {
        add_product($code);
    }
});

# lcd output
my $lcd = Cashpoint::Client::LCD->new('4x40');

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
    my ($cb, $pin, $timer);

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

    $client->auth($context{cashcard}, $pin, sub {
        my ($success, $user, $role, $auth) = @_;

        $lcd->show("3ce", "");
        if ($success) {
            # save the context information
            @context{qw/user role auth/} = ($user, $role, $auth);

            # display appropriate information
            $lcd->show("2ce", "Successfully Authorized");

            # try to create a basket
            create_basket();
        } else {
            # in case the auth was not successful, $user turns into $reason
            my $reason = $user;

            if ($reason eq '401') {
                $lcd->show("2ce", "Authorization Failed!");
            } elsif ($reason eq '403') {
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
    });
};

sub create_basket {
    # try to create a basket
    $client->create_basket($context{auth}, sub {
        my ($success, $id) = @_;

        if ($success) {
            $mode = MODE_AUTHED;
            $context{basket} = $id;

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
        my ($success, $name, $price) = @_;

        if ($success) {
            my $line = $lcd->append($name);
            $lcd->show($line."r", " ".$price." EUR");
        } else {
            # in case of an error, $name turns into $reason
            my $reason = $name;
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
