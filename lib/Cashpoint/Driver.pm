package Cashpoint::Driver;

use v5.10;

use strict;
use warnings;

use File::Temp qw/tmpnam/;
use Data::Dumper;
use namespace::autoclean;

use Moo;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Log::Log4perl qw/:easy/;

has '_sockpaths' => (
    is => 'rw',
    isa => sub { die unless ref $_[0] eq 'HASH' },
    default => sub {
        my %h = map { $_ => scalar tmpnam } qw/pinpad scanner rfid/;
        return \%h;
    },
);

has pinpad => (
    is => 'rw',
    handles => {
        send => 'push_write',
    },
);

has scanner => (
    is => 'rw',
    handles => {
        send => 'push_write',
    },
);

has rfid => (
    is => 'rw',
    handles => {
        send => 'push_write',
    },
);

## XXX: code reuse
## XXX: code reuse
## XXX: code reuse

sub BUILD {
    my $self = shift;

    tcp_server "unix/", $self->_sockpaths->{pinpad}, sub {
        my $sock = shift;
        DEBUG "pinpad accept";
        $self->pinpad(
            new AnyEvent::Handle(
                fh     => $sock,
                on_error => sub {
                   AE::log error => $_[2];
                   $_[0]->destroy;
                },
                on_eof => sub {
                   $sock->destroy; # destroy handle
                   AE::log info => "Done.";
                }
            )
        );
    };

    tcp_server "unix/", $self->_sockpaths->{scanner}, sub {
        my $sock = shift;
        DEBUG "scanner accept";
        $self->scanner(
            new AnyEvent::Handle(
                fh     => $sock,
                on_error => sub {
                   AE::log error => $_[2];
                   $_[0]->destroy;
                },
                on_eof => sub {
                   $sock->destroy; # destroy handle
                   AE::log info => "Done.";
                }
            )
        );
    };

    tcp_server "unix/", $self->_sockpaths->{rfid}, sub {
        my $sock = shift;
        DEBUG "rfid accept";
        $self->rfid(
            new AnyEvent::Handle(
                fh     => $sock,
                on_error => sub {
                   AE::log error => $_[2];
                   $_[0]->destroy;
                },
                on_eof => sub {
                   $sock->destroy; # destroy handle
                   AE::log info => "Done.";
                }
            )
        );
    };
}

sub get_pinpad {
    my $self = shift;
    my $cv = AE::cv;
    tcp_connect "unix/", $self->_sockpaths->{pinpad}, sub {
        my $sock = shift;
        DEBUG "pinpad connect";
        $cv->send($sock);
    };
    return $cv->recv;
}

sub get_scanner {
    my $self = shift;
    my $cv = AE::cv;
    tcp_connect "unix/", $self->_sockpaths->{scanner}, sub {
        my $sock = shift;
        DEBUG "scanner connect";
        $cv->send($sock);
    };
    return $cv->recv;
}

sub get_rfid {
    my $self = shift;
    my $cv = AE::cv;
    tcp_connect "unix/", $self->_sockpaths->{rfid}, sub {
        my $sock = shift;
        DEBUG "rfid connect";
        $cv->send($sock);
    };
    return $cv->recv;
}

42;
