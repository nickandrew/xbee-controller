#!/usr/bin/perl
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  A point-to-point XBee connection

package TullNet::XBee::PointToPoint;

use strict;
use warnings;

use Carp qw(confess);

use TullNet::XBee::Client qw();

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

	my $client = TullNet::XBee::Client->new($server_address);
	if (! $client) {
		die "Unable to connect to XBee server at $server_address";
	}

	my $self = {
		client => $client,
		frame_id => int(rand(255)),
		remote16_address => 0xfffe,
		remote64_h => hex($h),
		remote64_l => hex($l),
		xbee_device => lc($xbee_device),
		rx_packet_queue => [ ],
	};

	bless $self, $class;

	return $self;
}

sub close {
	my ($self) = @_;

	$self->{client}->close();
}

# ---------------------------------------------------------------------------
# Send a string to the peer.
# If timeout is defined and equals zero, do not wait for an acknowledgement.
# Otherwise wait for an acknowledgement (timeout defaults to 10 seconds).
# Return 1 if sent packet was acknowledged,
#        0 if packet was not received, or not waited-for.
# ---------------------------------------------------------------------------

sub sendString {
	my ($self, $string, $timeout) = @_;

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

	if ($ENV{DEBUG}) {
		print STDERR "** Sending: ", printable($string), "\n";
	}

	$self->{client}->sendData($packet);

	# Wait for an acknowledgement packet (transmitStatus)
	if (!defined $timeout) {
		$timeout = 10;
	}

	if ($timeout == 0) {
		# Do not wait
		return 0;
	}

	my $end_time = time() + $timeout;
	my $interval = $timeout;

	while (1) {
		my $interval = $end_time - time();
		if ($interval <= 0) {
			last;
		}

		my $packet = $self->{client}->receivePacket($interval);
		if (!defined $packet) {
			last;
		}

		my $type = $packet->type();

		if ($type eq 'receivePacket') {
			# Queue the packet for later inspection (by recvString)
			push(@{$self->{rx_packet_queue}}, $packet);
			next;
		}
		elsif ($type eq 'transmitStatus') {
			my $payload = $packet->{payload};

			# Capture the 16-bit remote address of our peer
			if ($payload->{frame_id} == $frame_id) {
				$self->{remote16_address} = $payload->{remote_address};

				my $delivery_status = $payload->{delivery_status};
				my $discovery_status = $payload->{discovery_status};

				if ($delivery_status == 0) {
					# Ack for the sent data

					if ($ENV{DEBUG}) {
						printf STDERR ("** Delivery status: %d  Discovery status: %d\n",
							$delivery_status,
							$discovery_status,
						);
					}

					return 1;
				} else {

					printf STDERR ("** Delivery status: %d  Discovery status: %d\n",
						$delivery_status,
						$discovery_status,
					);

					return 0;
				}
			} else {
				# Ignore it, not ours
			}
		}
	}

	# No acknowledgement received
	return 0;
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

	my $end_time = time() + $timeout;

	while (1) {
		my $interval = $end_time - time();
		if ($interval <= 0) {
			return undef;
		}

		my $packet = pop(@{$self->{rx_packet_queue}});
		if (! $packet) {
			$packet = $self->{client}->receivePacket($interval);
			if (!defined $packet) {

				if ($ENV{DEBUG}) {
					print STDERR "** receivePacket($timeout) returning undef\n";
				}

				return undef;
			}
		}

		my $type = $packet->type();

		if ($type eq 'receivePacket') {

			my $source = $packet->source();
			if ($source ne $self->{xbee_device}) {
				# Ignore other sources
				next;
			}

			my $buf = $packet->data();

			if ($ENV{DEBUG}) {
				print STDERR "** recvString() returning: ", printable($buf), "\n";
			}

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
					printf STDERR ("** Delivery status: %d  Discovery status: %d\n",
						$delivery_status,
						$discovery_status,
					);
				}
			}
		}
		elsif ($type eq 'transmitRequest') {
			# Ignore this quietly
		}
		else {
			print STDERR "** Ignored Packet type $type\n";
			next;
		}
	}
}

sub printable {
	my ($string) = @_;

	$string =~ s/([^ -}])/sprintf("<%02x>", ord($1))/ge;

	return $string;
}

1;
