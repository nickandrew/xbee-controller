#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Test parsing of various XBee API frames (for the ZB series)

use Test::More qw(no_plan);
use YAML qw();

use XBee::API::Common qw();
use XBee::API::ZB qw();

my $api = XBee::API::ZB->new();

testUnknownType(); # 0x05
testATResponse();  # 0x88
testModemStatus(); # 0x8a
testReceivePacket(); # 0x90

testParsePacket();

exit(0);

# ---------------------------------------------------------------------------
# This tests the encoding of a frame of unknown type (bogus id 0x05)
# ---------------------------------------------------------------------------

sub testUnknownType {
	my @values = (0x05, 0x36, 0x37, 0x38);
	my $bytes = pack('C*', @values);
	my $packet = $api->parseFrame($bytes);

	my $compare = {
		type => 'APIFrame',
		payload => {
			type => 0x05,
			data => chr(0x05) . '678',
		},
	};

	is_deeply($packet, $compare, "Unknown API Frame") || diag(explain($packet));
}

# ---------------------------------------------------------------------------
# Test parsing of a response to an AT Command
# ---------------------------------------------------------------------------

sub testATResponse {
	my @values = (0x88, 0x2a, ord('X'), ord('B'), 0x00, 0x34);
	my $bytes = pack('C*', @values);
	my $packet = $api->parseFrame($bytes);

	my $compare = {
		payload => {
			cmd => 'XB',
			frame_id => 42,
			status => 0,
			value => '4',
			type => 0x88,
		},
		type => 'ATResponse',
	};

	is_deeply($packet, $compare, "AT Response packet") || diag(explain($packet));
}

# ---------------------------------------------------------------------------
# This tests a Modem Status (for ZB; the values differ by device type)
# ---------------------------------------------------------------------------

sub testModemStatus {
	my @values = (0x8a, 0x11);
	my $bytes = pack('C*', @values);
	my $packet = $api->parseFrame($bytes);

	my $compare = {
		type => 'modemStatus',
		payload => {
			type => 0x8a,
			status_code => 0x11,
			status => 'Modem configuration changed while join in progress',
		},
	};

	is_deeply($packet, $compare, "Modem Status") || diag(explain($packet));
}

# ---------------------------------------------------------------------------
# This tests Receiving a packet
# ---------------------------------------------------------------------------

sub testReceivePacket {
	my @values = (0x90, 0x12, 0x34, 0x56, 0x78, 0x87, 0x65, 0x43, 0x21, 0x12, 0x34, 0x01);
	my $bytes = pack('C*', @values) . "Hello!\n";
	my $packet = $api->parseFrame($bytes);

	my $compare = {
		type => 'receivePacket',
		payload => {
			type => 0x90,
			sender64_h => 0x12345678,
			sender64_l => 0x87654321,
			sender16 => 0x1234,
			options => 0x01,
			data => "Hello!\n",
		},
	};

	is_deeply($packet, $compare, "Receive Packet") || diag(explain($packet));
}

# ---------------------------------------------------------------------------
# This tests re-parsing a packet
# ---------------------------------------------------------------------------

sub testParsePacket {
	my @values = (0x88, 0x2a, ord('X'), ord('B'), 0x00, 0x34);
	my $bytes = pack('C*', @values);

	my $packet = {
		type => 'APIFrame',
		payload => {
			type => 0x88,
			data => $bytes,
		},
	};

	my $packet2 = $api->parsePacket($packet);

	my $compare = {
		payload => {
			cmd => 'XB',
			frame_id => 42,
			status => 0,
			value => '4',
			type => 0x88,
		},
		type => 'ATResponse',
	};

	is_deeply($packet2, $compare, "Re-Parse Packet") || diag(explain($packet));
}
