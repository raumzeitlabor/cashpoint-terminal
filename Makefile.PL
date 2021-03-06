use inc::Module::Install;

name     'Cashpoint-Terminal';
all_from 'lib/Cashpoint/Client.pm';
author   q{Simon Elsbrock <simon@iodev.org>};
license  'perl';

build_requires 'Test::More';

requires 'Moo';
requires 'JSON::XS';
requires 'Log::Log4perl';
requires 'AnyEvent::HTTP';
requires 'Device::SerialPort';

auto_install;

WriteAll;

