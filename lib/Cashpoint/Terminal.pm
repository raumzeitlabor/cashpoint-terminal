#!/usr/bin/perl

package Cashpoint::Terminal;

use strict;
use warnings;

use 5.12.0;

use Carp;
use AnyEvent;

use Exporter 'import';
our @EXPORT = qw/cp_init cp_start/;

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

my ($client, $lcd, $rfid, $pinpad, $scanner);

##################################################


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

sub cp_init {
    my %args = @_;
    $lcd = $args{lcd};
    $rfid = $args{rfid};
    $pinpad = $args{pinpad};
    $scanner = $args{scanner};
    $client = $args{client};
}

sub cp_switch_mode {
    my $mode = shift;
    DEBUG "MODE = $mode";
}

sub cp_start {
    # backlight timer
    $timer = AnyEvent->timer(after => 5, cb => sub { $lcd->off });

    %context = ();

    $lcd->reset;
    $lcd->show("2ce", "RaumZeitLabor e.V. Cashpoint");

    # disable pinpad cb
    $pinpad->on_recv(sub {});

    # disable scanner cb
    $scanner->on_recv(sub {});
    $scanner->ae->on_rtimeout(undef);
    $scanner->ae->rtimeout(0);

    # enable rfid reader
    $rfid->on_recv(sub {
        my $raw = shift;
        my $code;

        # first byte is start flag, last byte is end flag
        if ($raw =~ m/^\x02([a-f0-9]{12})\x03$/i) {
            $code = $1;
        } else {
            WARN "invalid rfid: ".sprintf("%s", $raw);
            return;
        }

        if ($mode eq MODE_START) {# && $code =~ m/^#[a-z0-9]{18}$/i) {
            $context{cashcard} = $code;
            cp_read_pin();
        }
    });

    cp_switch_mode(MODE_START);
    INFO "ready!";
}

sub cp_read_pin {
    my $code = shift;
    my ($cb, $pin) = (undef, "");

    cp_switch_mode(MODE_PIN);
    INFO "reading pin…";

    # disable backlight timer
    $timer = undef; $lcd->on;

    # disable rfid reader
    $rfid->on_recv(sub {});

    $lcd->show("2ce", "Speak, friend, and enter.");

    # pinpad timeout
    $pinpad->ae->on_rtimeout(sub {
        INFO "no activity on pinpad, timing out";
        $pinpad->ae->on_rtimeout(undef);
        $pinpad->ae->rtimeout(0);
        cp_start;
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
                    cp_start;
                });
                return;
            }

            # disable pinpad cb
            $pinpad->on_recv(sub {});

            # the pin is not saved in the context
            cp_authenticate($pin);

        } else {
            $pin .= $input if $input =~ /^\d+$/;
            $lcd->show("3ce", "*" x length $pin);
        }
    });
};

sub cp_authenticate {
    my $pin = shift;

    cp_switch_mode(MODE_AUTH);
    INFO "authenticating…";

    $lcd->reset;
    $lcd->show("2ce", "Authenticating...");

    # this is synchronous
    my ($s, $r) = $client->auth_cashcard($context{cashcard}, $pin);

    if ($s eq '200') {
        # save the context information
        @context{qw/user role auth/} = (
            $r->{user}->{id},
            $r->{role},
            $r->{auth_token}
        );

        # display appropriate information
        $lcd->show("2ce", "- authorized as $r->{user}->{name} -");

        cp_switch_mode(MODE_AUTHED);
        cp_create_basket();

    } else {
        if ($s eq '401') {
            my $attempts = $r->{attempts_left};
            $lcd->show("2cen", "Authorization failed!");
            $lcd->show("3ce", "You have ".$attempts." more tries.");
        } elsif ($s eq '403') {
            $lcd->show("2cen", "There have been too many failed logins.");
            $lcd->show("3ce", "Please try again in five minutes.");
        } else {
            $lcd->show("2cen", "Uh-oh, there seems to be a problem!");
            $lcd->show("3cen", "Please try again later. Thank you.");
            $lcd->show("4re", "CODE: $s");
        }

        $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
            INFO "error timeout";
            cp_start;
        });
    }
};

sub cp_checkout { 
    INFO "user requested checkout";

    $pinpad->on_recv(sub {});
    $scanner->on_recv(sub {});
    
    $client->checkout_basket($context{basket}, sub {
        my ($s, $r) = @_;
        print Dumper $s, $r;
        if ($s eq '200') {
            INFO "checkout successful";

            $lcd->clear;
            $lcd->show("2cen", "Thanks, the amount of **".sprintf("%.2f", (100+rand(500))/100)."** EUR");
            $lcd->show("3ce", "was debited from your cashcard.");

        } else {
            $lcd->show("2cen", "WHY U NO WORKING");
            $lcd->show("3cen", "Please try again later. Thank you.");
            $lcd->show("4re", "CODE: $s");
        }

        $client->logout;

        $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
            DEBUG "checkout done";
            cp_start;
        });
    });
};

sub cp_create_basket {
    # try to create a basket
    $client->create_basket(sub {
        my ($s, $r) = @_;

        if ($s eq '201') {
            $context{basket} = $r->{id};

            # scanner inactivity timeout
            $scanner->ae->on_rtimeout(sub {
                INFO "no activity on scanner, logging out";
                $scanner->ae->on_rtimeout(undef);
                $scanner->ae->rtimeout(0);
                $client->logout;
                cp_start;
            });
            $scanner->ae->rtimeout_reset;
            $scanner->ae->rtimeout(TIMEOUT_SCANNER);

            # enable scanner cb
            $scanner->on_recv(sub {
                my $ean = shift;
                if ($ean =~ /^F\d{8,13}$/) {
                    INFO "scanned ean: $ean";
                    cp_add_item(substr($ean, 1));
                } else {
                    INFO "invalid ean: $ean";
                }
            });

            # enable pinpad cb for logout or checkout
            $pinpad->on_recv(sub {
                my $input = shift;
                DEBUG "PINPAD READ: $input";
                if ($input eq "*") {
                    INFO "user requested logout";
                    $scanner->ae->on_rtimeout(undef);
                    $scanner->ae->rtimeout(0);
                    $client->logout;

                    $lcd->clear;
                    $lcd->show("2ce", "Byebye!");

                    $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                        cp_start;
                    });
                } elsif ($input eq "#") {
                    $scanner->ae->on_rtimeout(undef);
                    $scanner->ae->rtimeout(0);
                    cp_checkout;
                }
            });

            $lcd->show("3ce", "Please start scanning your products.");

        } else {
            $lcd->show("2cen", "WHY U NO WORKING");
            $lcd->show("3ce", "Sorry, please try again later.");

            ERROR "could not create basket ($s), logging out";
            $client->logout;

            $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                INFO "error timeout";
                cp_start;
            });
        }
    });
};

sub cp_add_item {
    my $ean = shift;

    $client->add_item($context{basket}, $ean, sub {
        my ($s, $r) = @_;
        if ($s eq '201') {
            $lcd->clear;
            my $line = $lcd->append($r->{name});
            $lcd->show($line."r", " ".$r->{price}." EUR");
        } else {
            $lcd->show("2cen", "WHY U NO WORKING");
            $lcd->show("3ce", "Sorry, please try again later.");

            $timer = AnyEvent->timer(after => TIMEOUT_ERROR, cb => sub {
                INFO "error timeout";
                cp_start;
            });
        }
    });
};

42;
