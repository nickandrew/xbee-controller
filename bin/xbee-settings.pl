#!/usr/bin/perl
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010-2017, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Send various AT commands, and output the responses.
#
#  Usage: xbee-settings.pl [-h host:port]
#
#  -h host:port        Specify xbee daemon host and/or port (default 127.0.0.1:7862)

use strict;
use warnings;

use Getopt::Std qw(getopts);

use TullNet::XBee::Client qw();
use TullNet::XBee::API::Series2 qw();

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

	my $xcl = TullNet::XBee::Client->new($opt_h);

	if (!defined $xcl) {
		die "Unable to create a client socket";
	}

	my $xbee_api = TullNet::XBee::API::Series2->new($xcl);
	if (! $xbee_api) {
		die "Unable to create an XBee API implementation";
	}

	$xbee_api->sendNodeDiscover();
	$xbee_api->sendNodeIdentity();
	$xbee_api->sendMaxRFPayloadBytes();
	$xbee_api->sendPowerLevel();
	$xbee_api->sendMY();
	$xbee_api->sendSerialNumberHigh();
	$xbee_api->sendSerialNumberLow();
	$xbee_api->sendNodeJoin();
	$xbee_api->sendFirmwareVersion();

	# The loop needs to process an indeterminate number of response
	# packets as it's also reporting on connected nodes.
	my $end_time = time() + 10;

	while (1) {
		my $now = time();
		if ($now >= $end_time) {
			last;
		}

		my $timeout = $end_time - $now;

		my $packet = $xcl->receivePacket($timeout);
		next if (!defined $packet);
		processPacket($xbee_api, $packet);
	}
}

sub processPacket {
	my ($xbee_api, $frame) = @_;

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
		my $hr = $xbee_api->parseATResponse($payload);

		if ($hr) {
			foreach my $k (sort (keys %$hr)) {
				printf("%-20s : %s\n", $k, $hr->{$k});
			}
			print "\n";
		}
	}
}
