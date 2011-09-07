package Cashpoint::Client::InputReader;

use strict;
use warnings;

use Carp;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use POSIX qw/mkfifo/;

sub new {
    my ($class, $path) = @_;
    my $self = {
        path => $path,
    };

    unless (-p $path) {
        unlink $path; # try and fail silently
        mkfifo($path, 0600) or croak "Cannot create FIFO: $!";
    }

    open (my $fifo, '<', $path) or croak "Cannot open FIFO: $!";

    $self->{reader} = new AnyEvent::Handle(
        fh => $fifo,
        on_error => sub {
            my ($handle, $fatal, $msg) = @_;
            if ($fatal) {
                $handle->destroy;
                croak "Fatal error: $msg";
            }
            carp "Error reading from FIFO: $msg";
            $handle->destroy if $fatal;
        },
        on_eof => sub {
            my $handle = shift;
            croak "EOF was reached";
            $handle->destroy;
        },
        on_read => sub {
            my $handle = shift;
            print $handle->rbuf;
            $handle->rbuf = "";
        },
    );

    return bless $self, $class;
}

sub remove_fifo {
    my $self = shift;
    unlink($self->{fifopath});
}

42;
