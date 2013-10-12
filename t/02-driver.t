use Test::More;
use Data::Dump qw/pp/;

use EV;
use AnyEvent;
use Cashpoint::Driver;

my $cpd = Cashpoint::Driver->new;

EV::loop;
