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
        scrollbuffer => [],
        toplineptr => 0,
        currline   => 1,
        width      => $width,
        height     => $height,
        handle     => $lcd_handle,
    };

    bless $self, $class;
    return $self;
};

sub scrollbuffer_size {
    my $self = shift;
    return scalar @{$self->{scrollbuffer}};
}

sub reset {
    my $self = shift;
    for (1..$self->{height}) {
        $self->{handle}->push_write(" " x $self->{width}."\n");
    }
    $self->{scrollbuffer} = [];
    $self->{toplineptr} = 0;
};

sub clear {
    my ($self, $noflush) = @_;
    $self->append("") for (1..$self->{height});
    $self->flush unless $noflush;
};

sub append {
    my ($self, $msg) = @_;

    # pad the message to be appended to the full lcd width
    push @{$self->{scrollbuffer}}, $msg." " x ($self->{width} - length $msg);

    # if there is enough data in the scrollbuffer, scroll down one line
    if ($self->scrollbuffer_size > $self->{height}) {
        $self->{toplineptr}++;
    }

    $self->flush;

    # using this information, lines can be changed afterwards
    return $self->{toplineptr}-1 % $self->{width};
};

sub new_line {
    my $self = shift;
    $self->{handle}->push_write("\n");
};

sub scroll {
    my ($self, $lines) = @_;
    if ($lines < 0) {
        if ($self->{toplineptr} + $lines < 0) {
            $self->scroll_top;
        } else {
            $self->{toplineptr} += $lines;
            $self->flush;
        }
    } else {
        if ($self->{toplineptr} + $lines > $self->scrollbuffer_size) {
            $self->scroll_bottom;
        } else {
            $self->{toplineptr} += $lines;
            $self->flush;
        }
    }
};

sub scroll_top {
    my $self = shift;
    $self->{toplineptr} = 0;
    $self->flush;
};

sub scroll_bottom {
    my $self = shift;
    $self->{toplineptr} = $self->scrollbuffer_size - $self->{height};
    $self->flush;
};

sub flush {
    my $self = shift;
    my @scrollbuffer = @{$self->{scrollbuffer}};

    # calculate visible part
    my $from = $self->{toplineptr};
    my $to   = $from+$self->{height}-1;
    my @visible_scrollbuffer = @scrollbuffer[$from..$to];

    # flush it to the process
    $self->{handle}->push_write(
        join("\n", map { $_ // ' ' x $self->{height} } @visible_scrollbuffer)."\n"
    );
};

sub show {
    my ($self, $key, $msg) = @_;
    my @scrollbuffer = @{$self->{scrollbuffer}};

    if ($key !~ /^\d+[clr]?e?$/) {
        carp 'invalid hash key, skipping' if $key !~ /^\d+$/;
        next;
    }

    my ($lineno, $format, $empty) = ($key =~ /^(\d+)([clr]?)(e)?$/);

    if ($lineno > $self->{height}) {
        carp 'invalid line numer';
        return;
    }

    # make sure the line is not too long
    $msg = substr($msg, 0, $self->{width}) if length $msg > $self->{width};

    # enlarge scrollbuffer if necessary
    $#scrollbuffer = $lineno - 1 if ($self->scrollbuffer_size < $lineno);

    # figure out what the desired line currently looks like
    # if empty was requested, we'll comply :-)
    my $currline = $empty ? undef : $scrollbuffer[$self->{toplineptr}+$lineno-1];
    $currline =  ' ' x $self->{width} unless $currline;

    # do the requested formatting
    my $line;

    # align left
    if ($format eq '' || $format && $format eq 'l') {
        $line = $msg . substr($currline, length($msg));

    # center
    } elsif ($format && $format eq 'c') {
        my $space_left = $self->{width} - length $msg;
        my $lspace = int($space_left/2);
        my $rspace = $space_left/2 == $lspace ? $lspace : $space_left - $lspace;
        $line = substr($currline, 0, $lspace).$msg.
                substr($currline, length $msg, $rspace);

    # align right
    } elsif ($format && $format eq 'r') {
        $line = substr($currline, 0, $self->{width}-length($msg)).$msg;
    }

    # save the formatted line in the scrollbuffer
    $scrollbuffer[$self->{toplineptr}+$lineno-1] = $line;
    $self->{scrollbuffer} = \@scrollbuffer;

    # write the new scrollbuffer to the display
    $self->flush;
}

42;
