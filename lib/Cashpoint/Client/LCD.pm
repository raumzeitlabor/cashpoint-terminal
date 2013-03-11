package Cashpoint::Client::LCD;

use strict;
use warnings;

use Carp;
use AnyEvent;

use Log::Log4perl qw/:easy/;
use LCD2USB::Wrapper;

use Data::Dumper;

sub new {
    my ($class, $format) = @_;

    if (l2u_open() == -1) {
        carp 'could not find a display';
    }

    carp 'invalid format' if ($format !~ /^\d+x\d+$/);
    my ($height, $width) = ($format =~ /^(\d+)x(\d+)$/);

    my @empty_scrollbuffer = ('') x $height;
    my $self = {
        empty_scrollbuffer => \@empty_scrollbuffer,
        scrollbuffer => \@empty_scrollbuffer,
        toplineptr => 0,
        currline   => 1,
        width      => $width,
        height     => $height,
    };

    bless $self, $class;
    return $self;
};

sub on {
    DEBUG "LCD on";
    l2u_brightness(30);
}

sub off {
    DEBUG "LCD off";
    l2u_brightness(0);
}

sub scrollbuffer_size {
    my $self = shift;
    return scalar @{$self->{scrollbuffer}};
}

sub reset {
    my $self = shift;
    for (0..($self->{height} - 1)) {
        l2u_write($_, 0, " " x $self->{width});
    }
    $self->{scrollbuffer} = $self->{empty_scrollbuffer};
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

    for (0..($self->{height} - 1)) {
        l2u_write($_, 0, $visible_scrollbuffer[$_] // " " x $self->{width});
    }
};

sub show {
    my ($self, $key, $msg) = @_;
    my @scrollbuffer = @{$self->{scrollbuffer}};

    # formatting keys (spaces added for readability):
    # linenr(center|right|left)(erase)?(noflush)?
    if ($key !~ /^\d+[clr]?e?n?$/) {
        carp 'invalid hash key, skipping' if $key !~ /^\d+$/;
        return;
    }

    my ($lineno, $format, $empty, $noflush) = ($key =~ /^(\d+)([clr]?)(e)?(n)?$/);

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
    my $currline = $empty ? '' : $scrollbuffer[$self->{toplineptr}+$lineno-1];
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
    unless ($noflush) {
        # debug scrollbuffer
        DEBUG "LCD: ". ($_ ? $_ : '') for (@scrollbuffer) ;
        $self->flush unless $noflush;
    }
}

42;
