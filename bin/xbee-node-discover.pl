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
use JSON qw();

use Selector::SocketFactory qw();

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

my $alarm = 0;

$SIG{'ALRM'} = sub {
	$alarm = 1;
};

my $json = JSON->new()->utf8();

my $buffered;

connectAndProcess();

exit(0);

sub connectAndProcess {

	my $socket = Selector::SocketFactory->new(
		PeerAddr => $opt_h,
		Proto => 'tcp',
	);

	if (!defined $socket) {
		die "Unable to create a client socket";
	}

	my $frame_id = 8;
	my $data = pack('CCa2', 0x08, $frame_id, 'ND');

	my $cmd_hr = {
		type => 'APICommand',
		data => $data,
	};

	sendPacket($socket, $cmd_hr);

	# The following is a blocking loop but 
	alarm(10);

	while (! $alarm) {
		my $buffer;

		my $n = sysread($socket, $buffer, 256);

		if (!defined $n) {
			# Alarmed
			next;
		}

		if ($n == 0) {
			die "EOF on client socket";
		}

		if ($n < 0) {
			die "Error on client socket";
		}

		$buffered .= $buffer;

		while ($buffered =~ /^(.+)\r?\n(.*)/s) {
			my ($line, $rest) = ($1, $2);

			$buffered = $rest;

			processLine($line);
		}
	}
}

sub processLine {
	my ($line) = @_;

	my $frame = $json->decode($line);

	if (!defined $frame || ! ref $frame) {
		print "Illegal JSON frame: $line\n";
		return;
	}

	my $type = $frame->{type};
	my $payload = $frame->{payload};

	if (! $type || ! $payload) {
		print "Frame missing type or payload: $line\n";
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

sub sendPacket {
	my ($socket, $packet) = @_;

	my $string = $json->encode($packet) . "\n";

	$socket->syswrite($string);
}
