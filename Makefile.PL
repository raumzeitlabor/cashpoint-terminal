use inc::Module::Install;

name     'Cashpoint-Terminal';
all_from 'lib/Cashpoint/Client.pm';
author   q{Simon Elsbrock <simon@iodev.org>};
license  'perl';

build_requires 'Test::More';

requires 'JSON';
requires 'AnyEvent::HTTP';
requires 'Device::SerialPort';

auto_install;

WriteAll;

