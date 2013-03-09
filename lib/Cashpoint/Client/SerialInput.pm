package Cashpoint::Client::SerialInput;

use strict;
use warnings;

use Carp;

use AnyEvent;
use AnyEvent::Handle;

use Data::Dumper;

sub new {
    my ($class, $dev, $method) = @_;
    my $self = {};

    $self->{dev} = $dev;
    $method ||= [line => "\r"];
    $self->{method} = $method;
    $self->{fh} = $dev->{'HANDLE'};

    $self->{input_handle} = AnyEvent::Handle->new(
        fh => $dev->{'HANDLE'},
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            if ($fatal) {
                $handle->destroy;
                croak "Fatal error: $message";
            }
            carp "Error reading input data: $message";
        },
        on_eof => sub {
            my $handle = shift;
            $handle->destroy;
            croak "Device disconnected.";
        },
    );

    $self->{reader} = sub {
        my ($handle, $code) = @_;
        $self->{recv_cb}->($code) if $self->{recv_cb};
        carp "no input callback defined" unless $self->{recv_cb};

        # retrigger read
        $self->{input_handle}->push_read(@{$self->{method}}, $self->{reader});
    };

    # trigger read for the first time
    $self->{input_handle}->push_read(@{$self->{method}}, $self->{reader});

    bless $self, $class;
    return $self;
};

sub on_recv {
    my ($self, $recv_cb) = @_;
    $self->{recv_cb} = $recv_cb;
};

42;
