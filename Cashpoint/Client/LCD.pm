package Cashpoint::Client::LCD;

use strict;
use warnings;

use Carp;
use AnyEvent;
use AnyEvent::Run;

use Data::Dumper;

my $lcd_handle;

sub new {
    my ($class, $name) = @_;
    my $self = {};

    $lcd_handle = AnyEvent::Run->new(
        cmd      => [ $name, ],
        on_error  => sub {
            my ($handle, $fatal, $msg) = @_;
            if ($fatal) {
                $handle->destroy;
                croak "Fatal error";
            }
            carp "Error: $!";
        },
        on_eof => sub {
            my $handle = shift;
            $handle->destroy;
            croak "LCD disconnected.";
        },
    );

    $lcd_handle->push_write("foo");

    bless $self, $class;
    return $self;
};

sub show {
    my ($self, $msg) = shift;
    $lcd_handle->push_write($msg);
};

42;
