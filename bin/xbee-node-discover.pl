#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Send node discover command to XBee controller.
#  Format and print all node discovery responses.
#
#  Usage: xbee-node-discover.pl [-h host:port]
#
#  -h host:port        Specify xbee daemon host and/or port (default 127.0.0.1:7862)

use strict;

use Getopt::Std qw(getopts);

use XBee::Client qw();

use vars qw($opt_h);

$| = 1;
getopts('h:');

$opt_h ||= '127.0.0.1:7862';

$SIG{'INT'} = sub {
	print("SIGINT received, exiting\n");
	exit(4);
};

$SIG{'PIPE'} = sub {
	print("SIGPIPE received, exiting\n");
	exit(4);
};

connectAndProcess();

exit(0);

sub connectAndProcess {

	my $xcl = XBee::Client->new($opt_h);

	if (!defined $xcl) {
		die "Unable to create a client socket";
	}

	my $frame_id = 8;
	my $data = pack('CCa2', 0x08, $frame_id, 'ND');

	my $cmd_hr = {
		type => 'APICommand',
		data => $data,
	};

	$xcl->sendData($cmd_hr);

	# The following is a blocking loop but 
	my $end_time = time() + 10;

	while (1) {
		my $now = time();
		if ($now >= $end_time) {
			last;
		}

		my $timeout = $end_time - $now;

		my $packet = $xcl->receivePacket($timeout);
		next if (!defined $packet);
		processPacket($packet);
	}
}

sub processPacket {
	my ($frame) = @_;

	if (!defined $frame || ! ref $frame) {
		print "Illegal frame\n";
		return;
	}

	my $type = $frame->{type};
	my $payload = $frame->{payload};

	if (! $type || ! $payload) {
		print "Frame missing type or payload\n";
		return;
	}

	if ($type eq 'receivePacket') {
		# Ignore received packets
		return;
	}

	if ($type eq 'ATResponse') {
		my $cmd = $payload->{cmd};
		my $value = $payload->{value};

		my @bytes = split(//, $value);
		printf("Cmd: %s data: %s\n", $cmd, join(' ', map { sprintf("%02x", ord($_)) } (@bytes)));

		if ($cmd eq 'ND') {
			my ($my, $sh, $sl, $ni, $parent_network, $device_type, $status, $profile_id, $manufacturer_id) = unpack('nNNZ*nCCnn', $value);
			printf("AT Command Response : Node Discover\n");
			printf("16-bit address      : %04x\n", $my);
			printf("64 bit address      : %08x %08x\n", $sh, $sl);
			printf("Node Identifier     : <%s>\n", $ni);
			printf("Parent Network Addr : %04x\n", $parent_network);
			printf("Device Type         : %x\n", $device_type);
			printf("Status              : %x\n", $status);
			printf("Profile ID          : %04x\n", $profile_id);
			printf("Manufacturer ID     : %04x\n", $manufacturer_id);
		}

		print "\n";
	}
}
