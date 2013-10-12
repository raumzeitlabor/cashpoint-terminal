package Cashpoint::Client::SerialInput;

use strict;
use warnings;

use Carp;

use Moo;
use AnyEvent;
use AnyEvent::Handle;

use Data::Dumper;
use Log::Log4perl qw/:easy/;

has method => (
    is => 'ro',
    default => sub {
        return [line => "\r"]
    },
);

has ae_handle => (
    is => 'ro',
    reader => 'ae',
    writer => '_ae_handle',
    init_arg => undef,
);

has reader => (
    is => 'rw',
    init_arg => undef,
);

has on_recv => (
    is => 'rw',
);

has fh => (
    is => 'ro',
    required => 1,
);

sub BUILD {
    my $self = shift;

    DEBUG "DERP $self->dev";

    $self->_ae_handle(AnyEvent::Handle->new(
        fh => $self->fh,
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            if ($fatal) {
                $handle->destroy;
                croak("Fatal error: $message");
            }
            carp "Error reading input data: $message";
        },
        on_eof => sub {
            my $handle = shift;
            $handle->destroy;
            croak "Device disconnected.";
        },
    ));

    $self->reader(sub {
        my ($handle, $code) = @_;
        $self->on_recv->($code) if $self->on_recv;
        carp "no input callback defined" unless $self->on_recv;

        # retrigger read
        $self->ae->push_read(@{$self->method}, $self->reader);
    });

    # trigger read for the first time
    $self->ae->push_read(@{$self->method}, $self->reader);  
};

42;
