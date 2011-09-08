package Cashpoint::Client;

use warnings;
use strict;

use JSON;
use AnyEvent::HTTP;

use Data::Dumper;

sub new {
    my ($class, $baseurl) = @_;
    my $self = {
        baseurl => $baseurl,
    };
    return bless $self, $class;
}

sub auth {
    my ($self, $cashcard, $pin, $cb) = @_;

    print Dumper to_json({code => $cashcard, pin => $pin});

    http_request(
        POST    => $self->{baseurl}."/auth",
        headers => {
            'Content-Type' => 'application/json',
        },
        timeout => 5,
        body => to_json({code => $cashcard, pin => $pin}),
        sub {
            my ($body, $hdr) = @_;
            print Dumper $body, $hdr;

            if ($hdr->{Status} eq '200') {
                my $auth_info = from_json($body);
                &$cb(1, $auth_info->{user}, $auth_info->{role}, $auth_info->{auth_token});
            } else {
                &$cb(0, $hdr->{Status});
            }
        }
    );
};

sub create_basket {
    my ($self, $auth, $cb) = @_;

    http_request(
        POST    => $self->{baseurl}."/baskets?auth=".$auth,
        headers => {
            'Content-Type' => 'application/json',
        },
        timeout => 5,
        sub {
            my ($body, $hdr) = @_;
            print Dumper $body, $hdr;
        }
    );
};

42;
