package Cashpoint::Client;

use warnings;
use strict;

use JSON;
use AnyEvent::HTTP;

use Data::Dumper;

our $VERSION = '0.01';

sub new {
    my ($class, $baseurl) = @_;
    my $self = {
        baseurl => $baseurl,
    };
    return bless $self, $class;
}

# generic http request dispatcher
# can be used both async- and synchronously
sub generic {
    my ($self, $method, $path, $payload, $cb) = @_;

    my %headers = ();
    $headers{'Content-Type'} = 'application/json' if $payload;

    # add auth info, if available
    if (defined $self->{session}) {
        $headers{'auth_token'} = $self->{session}->{auth_token};
    }

    # build request
    my $httpr = [
        headers    => \%headers,
        timeout    => 10,
    ];

    push @$httpr, (body => to_json($payload)) if $payload;
    print "HEADER: ".Dumper $httpr if $self->{debug};

    # do the request
    my $data;
    my $hdr;
    my $cv = AE::cv;
    http_request(uc $method => $self->{baseurl}.$path, @$httpr, sub {
        my $body = shift;
        $hdr = shift;

        print Dumper $hdr, $body if $self->{debug};

        if ($hdr->{Status} =~ m/^20[01]/) {
            $data = from_json($body) if $body;
            &$cb($hdr->{Status}, $data) if $cb;
        } else {
            &$cb($hdr->{Status}, undef) if $cb;
        }

        $cv->send unless $cb;
    });

    # if no callback is defined, work synchronously
    $cv->recv unless $cb;

    # return payload if no data is returned
    return ($hdr->{Status}, $data);
}

# synchronous
sub auth_by_pin {
    my ($self, $cashcard, $pin) = @_;
    my ($s, $r) = $self->generic(POST => '/auth', {
        code => $cashcard,
        pin  => $pin,
    });

    $self->{session} = $r if $r;
    return ($s, $r);
};

sub auth_by_passwd {
    my ($self, $username, $passwd) = @_;
    my ($s, $r) = $self->generic(POST => '/auth', {
        username => $username,
        passwd   => $passwd,
    });

    $self->{session} = $r if $r;
    return ($s, $r);
};

sub logout {
    my ($self, $cb) = @_;
    return $self->generic(DELETE => '/auth', undef, $cb);
}

# bothchronous
sub get_products {
    my ($self, $cb) = @_;
    return $self->generic(GET => '/products', undef, $cb);
}

sub add_product {
    my ($self, $name, $ean, $threshold, $cb) = @_;
    return $self->generic(POST => '/products', {
        name => $name,
        ean  => '4029764001807',
    }, $cb);
}

sub get_product {
    my ($self, $ean, $cb) = @_;
    return $self->generic(GET => "/products/$ean", undef, $cb);
}

# groups create, delete
sub create_group {
    my ($self, $name, $cb) = @_;
    return $self->generic(POST => '/groups', {
        name => $name,
    }, $cb);
}

# cashcard create, unlock, enable, disable, credit, transfer

sub register_cashcard {
    my ($self, $user, $group, $code, $pin, $cb) = @_;
    return $self->generic(POST => '/cashcards', {
        user  => $user,
        group => $group,
        code  => $code,
        pin   => $pin,
    }, $cb);
}

sub unlock_cashcard {
    my ($self, $code, $pin, $cb) = @_;
    return $self->generic(PUT => "/cashcards/$code", {
        pin => $pin,
    }, $cb);
}

sub enable_cashcard {
    my ($self, $code, $cb) = @_;
    return $self->generic(PUT => "/cashcards/$code/enable", undef, $cb);
}

sub disable_cashcard {
    my ($self, $code, $cb) = @_;
    return $self->generic(PUT => "/cashcards/$code/disable", undef, $cb);
}

sub get_cashcard_credits {
    my ($self, $code, $cb) = @_;
    return $self->generic(GET => "/cashcards/$code/credits", undef, $cb);
}

sub charge_cashcard {
    my ($self, $code, $amount, $remark, $type, $cb) = @_;
    return $self->generic(POST => "/cashcards/$code/credits", {
        type   => $type,
        remark => $remark,
        amount => $amount,
    }, $cb);
}

sub transfer_credits {
    my ($self, $from, $to, $amount, $reason, $cb) = @_;
    return $self->generic(POST => "/cashcards/$from/transfers", {
        recipient => $to,
        amount    => $amount,
        reason    => $reason,
    }, $cb);
}

sub get_transfers {
    my ($self, $code, $cb) = @_;
    return $self->generic(GET => "/cashcards/$code/transfers", undef, $cb);
}

# basket
sub create_basket {
    my ($self, $cb) = @_;
    return $self->generic(POST => '/baskets', undef, $cb);
};

sub delete_basket {
    my ($self, $basket, $cb) = @_;
    return $self->generic(DELETE => "/baskets/$basket", undef, $cb);
}

# delete, checkout basket
sub get_items {
    my ($self, $basket, $cb) = @_;
    return $self->generic(GET => "/baskets/$basket/items", undef, $cb);
}

sub add_item {
    my ($self, $basket, $ean, $cb) = @_;
    return $self->generic(POST => "/baskets/$basket/items", {
        ean => $ean,
    }, $cb);
}

42;
