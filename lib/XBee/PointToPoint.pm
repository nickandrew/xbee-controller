#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  A point-to-point XBee connection

package XBee::PointToPoint;

use strict;

use Carp qw(confess);

use XBee::Client qw();

sub new {
	my ($class, $args) = @_;

	my $server_address = $args->{xbee_server};
	my $xbee_device = $args->{xbee_device};

	if (! $server_address) {
		confess "Need argument xbee_server";
	}

	if (! $args->{xbee_device}) {
		confess "Need argument xbee_device";
	}

	if ($xbee_device !~ /^([0-9a-fA-F]+):([0-9a-fA-F]+)$/) {
		die "Invalid xbee device identifier: $xbee_device";
	}

	my ($h, $l) = ($1, $2);

	my $client = XBee::Client->new($server_address);
	if (! $client) {
		die "Unable to connect to XBee server at $server_address";
	}

	my $self = {
		client => $client,
		frame_id => int(rand(255)),
		remote16_address => 0xfffe,
		remote64_h => hex($h),
		remote64_l => hex($l),
		xbee_device => $xbee_device,
	};

	bless $self, $class;

	return $self;
}

sub close {
	my ($self) = @_;

	$self->{client}->close();
}

sub sendString {
	my ($self, $string) = @_;

	my $frame_id = ($self->{frame_id} + 1) & 0xff;
	$self->{frame_id} = $frame_id;

	my $packet = {
		type => 'transmitRequest',
		payload => {
			data => $string,
			frame_id => $frame_id,
			dest64_h => $self->{remote64_h},
			dest64_l => $self->{remote64_l},
			dest16 => $self->{remote16_address},
			radius => 0,
			options => 0,
		},
	};

	$self->{client}->sendData($packet);
}

sub recvString {
	my ($self, $size, $timeout) = @_;

	# Return from the loop when:
	#  1. No packet is received for 'timeout' seconds, or
	#  2. A data packet is received from our defined remote address.
	#  Notes:
	#    - Can't distinguish between timeout and EOF
	#    - Doesn't limit size of returned data to $size
	#    - A busy network may never time out
	#    - A slightly busy network may time out later than expected.

	while (1) {
		my $packet = $self->{client}->receivePacket($timeout);
		if (!defined $packet) {
			return undef;
		}

		my $type = $packet->type();

		if ($type eq 'receivePacket') {

			my $source = $packet->source();
			if ($source ne $self->{xbee_device}) {
				next;
			}

			my $buf = $packet->data();

			return $buf;
		}
		elsif ($type eq 'transmitStatus') {
			my $payload = $packet->{payload};

			# Capture the 16-bit remote address of our peer
			if ($payload->{frame_id} == $self->{frame_id}) {
				$self->{remote16_address} = $payload->{remote_address};

				my $delivery_status = $payload->{delivery_status};
				my $discovery_status = $payload->{discovery_status};

				if ($delivery_status != 0 || $discovery_status != 0) {
					printf("Delivery status: %d  Discovery status: %d\n",
						$delivery_status,
						$discovery_status,
					);
				}
			}
		}
		else {
			print "Ignored Packet type $type\n";
			next;
		}
	}
}

1;
