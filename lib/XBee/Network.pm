#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::Network - A high level interface to a network of XBees

=head1 DESCRIPTION

XBee::Network provides a way to communicate with an XBee controller and
one or more XBee end devices. It abstracts the controller device (in
this class) and end devices (as subclasses of XBee::Node).

=head1 METHODS

=over

=cut

package XBee::Network;

use strict;

use XBee::Node qw();

my $receive_specs = {
	'receivePacket'   => 'handleReceivePacket',
	'ATResponse'      => 'handleATResponse',
	'modemStatus'     => 'handleModemStatus',
	'transmitStatus'     => 'handleTransmitStatus',
	'explicitReceivePacket'       => 'handleExplicitReceivePacket',
	'receiveIOSample'             => 'handleReceiveIOSample',
	'receiveSensor'               => 'handleReceiveSensor',
	'nodeIdentificationIndicator' => 'handleNodeIdentificationIndicator',
	'OTAFirmwareUpdateStatus'     => 'handleOTAFirmwareUpdateStatus',
};


=item I<new($api, $client)>

Return a new instance of this class.

$api is a reference to an XBee::AT (to interpret AT commands and responses).

$client is a reference to an XBee::Client (to communicate with the controller/daemon).

=cut

sub new {
	my ($class, $api, $client) = @_;

	my $self = {
		api => $api,
		client => $client,
		default_class => 'XBee::Node',
		nodes => { },
		frame_id => int(rand(254)) + 1,
	};

	if (ref $class) {
		use Carp qw(confess);
		confess "Here";
	}

	bless $self, $class;
	return $self;
}

# ---------------------------------------------------------------------------
# Return a canonical address (xxxxxx:xxxxxx)
# ---------------------------------------------------------------------------

sub _canonical {
	my ($address) = @_;

	die "Need address" if (!defined $address);

	if ($address !~ /^([0-9a-f]+):([0-9a-f]+)$/) {
		die "Invalid address: $address";
	}

	my($hi, $lo) = ($1, $2);

	return sprintf("%x:%x", hex($hi), hex($lo));
}

=item I<getNode($address, $class)>

Instantiate a new node, given its address (xxxxxx:xxxxxx).

This returns an existing object from our set of nodes if known, otherwise
it creates a new object of the specified class (which adds it to the set).

=cut

sub getNode {
	my ($self, $address, $class) = @_;

	$class ||= $self->{default_class};

	$address = _canonical($address);

	my $node = $self->{nodes}->{$address};

	if (! $node) {
		$node = $class->new($address, $self);
		$self->{nodes}->{$address} = $node;
	}

	return $node;
}

=item I<addNode($address, $node)>

Add a node to our set of nodes. Die if the node already exists.

=cut

sub addNode {
	my ($self, $address, $node) = @_;

	$address = _canonical($address);

	if ($self->{nodes}->{$address}) {
		die "Node $address already in set";
	}

	$self->{nodes}->{$address} = $node;
}

=item I<receive($timeout)>

Receive a packet from the server, with a timeout.

Process any packet received:
  - data packets are sent to the node object
  - transmit status packets are sent to the node object
  - other packet types are handled by this class.

=cut

sub receive {
	my ($self, $timeout) = @_;

	my $client = $self->{client};

	my $packet = $client->receivePacket($timeout);
	if (! $packet) {
		return 0;
	}

	# Process the packet
	my $type = $packet->type();

	my $func = $receive_specs->{$type};

	if (! $func) {
		print "Received packet of unknown type $type\n";
	} else {
		$self->$func($packet);
	}

	return 1;
}

=item I<handleReceivePacket($packet)>

Handle a received packet of type 'receivePacket'.
A 'receivePacket' is a string of data from a node. If the sending node
is in our set of nodes, then call the node's addData() function to append
to the node's internal buffer.

=cut

sub handleReceivePacket {
	my ($self, $packet) = @_;

	my $sender_address = $packet->source();;
	my $node = $self->{nodes}->{$sender_address};

	if (! $node) {
		print "Received packet from unknown node $sender_address\n";
		return;
	}

	my $string = $packet->data();
	if (defined $string) {
		$node->addData($string);
	}
}

=item I<handleATResponse($packet)>

Handle a received packet of type 'ATResponse'.
An 'ATResponse' is a response to an ATCommand and contains the success/failure 
of the command as well as optional data values (e.g. when reading device
parameters).

=cut

sub handleATResponse {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<handleModemStatus($packet)>

Handle a received packet of type 'modemStatus'.
A 'modemStatus' packet signifies a change in status of the controller's
radio modem (e.g. Co-ordinator started, Joined network, Disassociated).

=cut

sub handleModemStatus {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<handleTransmitStatus($packet)>

Handle a received packet of type 'transmitStatus'.
A 'transmitStatus' packet is sent by the device when a transmit request
is completed. The packet indicates whether the transmit was successful
or failed, whether network discovery was used, and the 16-bit network
address of the destination.

=cut

sub handleTransmitStatus {
	my ($self, $packet) = @_;

	my $payload = $packet->{payload};
	my $frame_id = $payload->{frame_id};
	my $remote_address = $payload->{remote_address};

	# This frame_id has to be matched to the transmitRequest of the same frame_id
	# printf("Received transmitStatus frame_id %d remote_address %d\n", $frame_id, $remote_address);
}

=item I<handleExplicitReceivePacket($packet)>

Handle a received packet of type 'explicitReceivePacket'.
An explicit receive packet is a lower level interface to the ZigBee
protocol which also exposes the endpoints, cluster ID and profile ID
of the received packet.

=cut

sub handleExplicitReceivePacket {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<handleReceiveIOSample($packet)>

Handle a received packet of type 'receiveIOSample'.
This packet type contains the current values of a Node's input pins,
both digital and analogue.

=cut

sub handleReceiveIOSample {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<handleReceiveSensor($packet)>

Handle a received packet of type 'receiveSensor'.
This packet contains data received from a Digi 1-wire sensor adapter.
There are optionally 4 A/D sensors and a temperature sensor.

=cut

sub handleReceiveSensor {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<handleNodeIdentificationIndicator($packet)>

Handle a received packet of type 'nodeIdentificationIndicator'.
This packet is sent by the controller when a Node sends a
node identification message to identify itself (which may
happen upon joining a network).

=cut

sub handleNodeIdentificationIndicator {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<handleOTAFirmwareUpdateStatus($packet)>

Handle a received packet of type 'OTAFirmwareUpdateStatus'.
This packet is a status indication of a firmware update transmission
attempt.

=cut

sub handleOTAFirmwareUpdateStatus {
	my ($self, $packet) = @_;
	my $type = $packet->type();
	print "Received packet of unhandled-type $type\n";
}

=item I<sendPacket($packet)>

Send a supplied packet through our XBee::Client connection.

=cut

sub sendPacket {
	my ($self, $packet) = @_;

	$self->{client}->sendData($packet);
}


=item I<listNodes()>

Return an array of XBee::Node objects representing each node currently
connected to the network.

=cut

sub listNodes {
	my ($self) = @_;

	my $at = $self->{api};
	$self->{client}->sendATCommand('ND');

	my @nodes;
	my $now = time();
	my $end_time = $now + 10;

	while ($now < $end_time) {
		my $timeout = $end_time - $now;

		my $packet = $self->{client}->receivePacket($timeout);
		if (!defined $packet) {
			$now = time();
			next;
		}

		if ($packet->type() eq 'ATResponse') {
			my $hr = $at->parseATResponse($packet->{payload});

			if ($hr && $hr->{'AT Command Response'} eq 'Node Discover') {
				my $addr64 = $hr->{'64 bit address'};
				my $node = $self->getNode($addr64);
				$node->setNodeID($hr->{'Node Identifier'});
				push(@nodes, $node);
			}
		}

		$now = time();
	}

	return @nodes;
}

=back

=cut

1;
