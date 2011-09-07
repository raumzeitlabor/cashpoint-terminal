#!/usr/bin/perl

use strict;
use warnings;

use EV;
use AnyEvent;
use AnyEvent::Handle;
use DateTime;
use Term::ReadKey;

$| = 1;

if (@ARGV != 1) {
    print "usage: $0 path_to_fifo\n";
    exit 1;
}

print DateTime->now." - Waiting for FIFO to appear...\n" unless (-p $ARGV[0]);
until (-p $ARGV[0]) { sleep 1; }

open (my $fifo, '>', $ARGV[0]) or die "Cannot open FIFO: $!";

# do not perform any input processing
ReadMode('cbreak');

my ($write_hdl, $read_hdl);

$write_hdl = new AnyEvent::Handle(
    fh => $fifo,
    on_error => sub {
        my ($write_hdl, $fatal, $msg) = @_;
        print DateTime->now." - Could not write to FIFO: $msg\n";
        if ($fatal) {
            $write_hdl->destroy;
            $read_hdl->destroy;
        }
    },
    on_eof => sub {
        my $write_hdl = shift;
        print DateTime->now." - FIFO was closed, exiting\n";
        $write_hdl->destroy;
        $read_hdl->destroy;
    },
);

$read_hdl = new AnyEvent::Handle(
    fh => \*STDIN,
    on_error => sub {
        my ($read_hdl, $fatal, $msg) = @_;
        print DateTime->now." - Error: $msg\n";
        if ($fatal) {
            $read_hdl->destroy;
            $write_hdl->destroy;
        }
    },
    on_eof => sub {
        my $read_hdl = shift;
        print DateTime->now." - EOF was reached; this should not happen; exiting\n";
        $read_hdl->destroy;
        $write_hdl->destroy;
    },
    on_read => sub {
        my $read_hdl = shift;
        $write_hdl->push_write($read_hdl->rbuf);
        $read_hdl->rbuf = "" if $read_hdl->rbuf;
    }
);

print DateTime->now." - InputForwarder running.\n";

EV::loop;
