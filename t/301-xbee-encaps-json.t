#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

use Test::More qw(no_plan);

use TullNet::XBee::Encaps::JSON qw();

my $tested_sendpacket = 0;
my $tested_packet = 0;

my $e = TullNet::XBee::Encaps::JSON->new();
isa_ok($e, 'TullNet::XBee::Encaps::JSON');

my $packet = {
	type => 'testPacket',
	payload => { a => 1, b => 2, c => 'hello' },
};

my $test_packet = '{"payload":{"a":1,"b":2,"c":"hello"},"type":"testPacket"}' . "\n";

can_ok($e, qw(setHandler addData sendPacket));

$e->setHandler('sendPacket', 'main', 'sendPacket');
$e->setHandler('packet', 'main', 'packet');

# Test sendPacket

$e->sendPacket($packet);

# Test packet
$e->addData($test_packet);

if (! $tested_sendpacket) {
	fail("Failed to test sendPacket()");
}

if (! $tested_packet) {
	fail("Failed to test packet()");
}

exit(0);

sub sendPacket {
	my ($class, $string) = @_;

	if ($string eq $test_packet) {
		pass("sendPacket");
		$tested_sendpacket = 1;
	} else {
		print "Expected: $test_packet\n";
		print "Got:      $string\n";
		fail("sendPacket");
	}
}

sub packet {
	my ($class, $hashref) = @_;

	is_deeply($hashref, $packet, "packet()");
	$tested_packet = 1;
}
