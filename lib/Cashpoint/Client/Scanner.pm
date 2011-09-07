package Cashpoint::Client::Scanner;

use strict;
use warnings;

use Carp;

use AnyEvent;
use AnyEvent::Handle;
use Device::SerialPort;

use Data::Dumper;

sub new {
    my ($class, $device) = @_;
    my $self = {};

    my $dev = Device::SerialPort->new($device) or croak $!;
    $dev->baudrate(9600);
    $dev->databits(8);
    $dev->parity("none");
    $dev->stopbits(1);

    $self->{dev} = $dev;
    $self->{fh} = $dev->{'HANDLE'};

    $self->{scan_handle} = AnyEvent::Handle->new(
        fh => $dev->{'HANDLE'},
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            if ($fatal) {
                $handle->destroy;
                croak "Fatal error: $message";
            }
            carp "Error reading scanner data: $message";
        },
        on_eof => sub {
            my $handle = shift;
            $handle->destroy;
            croak "Scanner disconnected.";
        },
    );

    $self->{reader} = sub {
        my ($handle, $code) = @_;
        $self->{scan_cb}->($code) if $self->{scan_cb};
        carp "no scan callback defined" unless $self->{scan_cb};
        $self->{scan_handle}->push_read(line => "\r", $self->{reader});
    };

    $self->{scan_handle}->push_read(line => "\r", $self->{reader});

    bless $self, $class;
    return $self;
};

sub on_scan {
    my ($self, $scan_cb) = @_;
    $self->{scan_cb} = $scan_cb;
};

42;
