package Cashpoint::Client::LCD;

use strict;
use warnings;

use Carp;
use AnyEvent;
use AnyEvent::Run;

use Data::Dumper;

my $lcd_handle;

sub new {
    my ($class, $name, $format) = @_;

    carp 'invalid format' if ($format !~ /^\d+x\d+$/);
    my ($height, $width) = ($format =~ /^(\d+)x(\d+)$/);

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

    my $self = {
        scrollback => [],
        width      => $width,
        height     => $height,
        handle     => $lcd_handle,
        lineptr    => 0,
    };

    bless $self, $class;
    $self->clear;
    return $self;
};

sub clear {
    my $self = shift;
    $self->{handle}->push_write("\n" x $self->{height});
    $self->{scrollback} = [];
    $self->{lineptr} = 0;
};

sub append {
    my ($self, $msg) = shift;
    $self->{handle}->push_write($msg);
    $self->{lineptr}++ if (@{$self->{scrollback}} > $self->{height});
};

sub new_line {
    my $self = shift;
    $self->{handle}->push_write("\n");
    $self->{lineptr}++ if (@{$self->{scrollback}} > $self->{height});
};

sub show {
    my ($self, $key, $msg) = @_;
    my @scrollback = @{$self->{scrollback}};

    if ($key !~ /^\d+[clr]?e?$/) {
        carp 'invalid hash key, skipping' if $key !~ /^\d+$/;
        next;
    }

    my $line;
    my ($lineno, $format, $empty) = ($key =~ /^(\d+)([clr]?)(e)?$/);

    if ($lineno > $self->{height}) {
        carp 'invalid line numer';
        return;
    }

    # enlarge scrollback if necessary
    $#scrollback = $lineno - 1 if (@scrollback < $lineno);

    # figure out what the desired line currently looks like
    my $currline = $empty ? undef : $scrollback[$self->{lineptr}+$lineno-1];
    $currline =  ' ' x $self->{width} unless $currline;

    if ($format eq '' || $format && $format eq 'l') {
        $line = $msg . substr($currline, length($msg));
    } elsif ($format && $format eq 'c') {
        my $space_left = $self->{width} - length $msg;
        my $lspace = int($space_left/2);
        my $rspace = $space_left/2 == $lspace ? $lspace : $space_left - $lspace;
        $line = substr($currline, 0, $lspace).$msg.
                substr($currline, length $msg, $rspace);
    } elsif ($format && $format eq 'r') {
        $line = substr($currline, 0, $self->{width}-length($msg)).$msg;
    }

    $scrollback[$self->{lineptr}+$lineno-1] = $line;
    $self->{scrollback} = \@scrollback;

    # if there are not enough lines in the scrollback buffer, use what we have
    my @visible_scrollback = @scrollback[$self->{lineptr}..$self->{lineptr}+$self->{height}-1];
    print Dumper \@visible_scrollback;
    $self->{handle}->push_write(
        join("\n", map { $_ // '' } @visible_scrollback)
    );

    print "#"x40; print "\n";
}

42;
