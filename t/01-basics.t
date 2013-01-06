#!perl -T

use Test::More;
use Cashpoint::Client;
use Data::Dump qw/pp/;

my $client = Cashpoint::Client->new('http://localhost:3000');
$client->{debug} = 1;
my ($s, $r);

($s, $r) = $client->auth_by_pin('0123456789abcdefgh', '242596');
ok($s == 1 and defined $r, 'logged in');

($s, $r) = $client->add_product('Club Mate', '4029764001807');
ok($s == 1, 'created product');

($s, $r) = $client->get_products;
ok($s == 1 and defined $r, 'got all products');

($s, $r) = $client->get_product('4029764001807');
ok($s == 1 and defined $r, 'got specific products');

($s, $r) = $client->create_group('RaumZeitLabor');
ok($s == 1 and defined $r, 'created group');

($s, $r) = $client->register_cashcard(7, 1, '0123456788abcdefgh', '123456');
ok($s == 1 and defined $r, 'registered cashcard');

($s, $r) = $client->create_basket;
ok($s == 1 and defined $r, 'created basket');

($s, $r) = $client->delete_basket($r->{id});
ok($s == 1 and defined $r, 'deleted basket');

($s, $r) = $client->logout;
ok($s == 1 and defined $r, 'logged out');

done_testing;
