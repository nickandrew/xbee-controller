#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::Node - An XBee end device

=head1 SYNOPSIS

  my $network = XBee::Network->new( ... );
  my $node = XBee::Node->new('12a34:4428cc0', $network);

  $node->sendString("Hello, world.\n");

  $network->receive(20);

  my $line = $node->getLine();

=head1 DESCRIPTION

XBee::Node represents a single XBee end device within a network. It is
identified by its 64-bit ZigBee node identifier, represented like this:
"12a34:4428cc0".

Each XBee::Node keeps an internal buffer of data received, but not yet
processed.

XBee::Node is used in conjunction with XBee::Network, which will receive
packets from a daemon and add them to the XBee::Node internal buffer.

To retrieve data from a node, call getData() to retrieve the whole buffer
(will return '' if empty) or getLine() to return only one line of data
ending in \n (will return undef if none).

=head1 SUBCLASSING

Subclass XBee::Node to implement event-driven processing, for example
by replacing addData().

=head1 METHODS

=over

=cut

package XBee::Node;

use strict;

=item I<new($address, $network)>

Return a new instance of XBee::Node identified by $address and communicating
through $network which is an instance of XBee::Network.

=cut

sub new {
	my ($class, $address, $network) = @_;

	if ($address !~ /^([0-9a-f]{1,8}):([0-9a-f]{1,8})$/) {
		die "Invalid address: $address";
	}

	my ($addr64_h, $addr64_l) = ($1, $2);

	my $self = {
		node_id => $address,
		addr64_h => $addr64_h,
		addr64_l => $addr64_l,
		addr16 => 0xfffe,
		buffer => '',
		network => $network,
		ni => '',
	};

	bless $self, $class;

	$network->addNode($address, $self);

	return $self;
}

# ---------------------------------------------------------------------------
# Send a remote AT command to the device
# ---------------------------------------------------------------------------

sub _sendRemoteCommand {
	my ($self, $cmd, $args) = @_;

	my ($dest64_h, $dest64_l, $dest16) = $self->_getAddress();

	my $packet = {
		type => 'remoteATCommand',
		payload => {
			dest64_h => $dest64_h,
			dest64_l => $dest64_l,
			dest16 => $dest16,
			options => 0,
			cmd => $cmd,
			args => $args,
		},
	};

	$self->{network}->sendPacket($packet);
}

=item I<setNodeID($id, $action)>

Set the ASCII Node Identifier which is stored in non-volatile RAM on the
XBee device.

If $action is true then an update is sent to the device (otherwise, the
value is only stored in this object).

=cut

sub setNodeID {
	my ($self, $id, $action) = @_;

	$self->{ni} = $id;

	if ($action) {
		$self->_sendRemoteCommand('NI', $id);
	}
}

=item I<getNodeID()>

Return the ASCII Node Identifier.

=cut

sub getNodeID {
	my ($self) = @_;

	return $self->{ni};
}

=item I<saveSettings()>

Send a command to save the current settings to NVRAM.

=cut

sub saveSettings {
	my ($self) = @_;

	$self->_sendRemoteCommand('WR', '');
}

=item I<getAddress()>

Return the 64-bit address of this node in hex:hex format.

=cut

sub getAddress {
	my ($self) = @_;

	return $self->{node_id};
}

# ---------------------------------------------------------------------------
# Return the high and low order parts of the 64-bit address numerically,
# as well as the 16-bit address if known (else 0xfffe which tells the
# controller to do network discovery).
# ---------------------------------------------------------------------------

sub _getAddress {
	my ($self) = @_;

	my $addr64_h = hex($self->{addr64_h});
	my $addr64_l = hex($self->{addr64_l});
	my $addr16 = $self->{addr16};

	return ($addr64_h, $addr64_l, $addr16);
}

=item I<sendString($string)>

Send the specified string to the end device.

=cut

sub sendString {
	my ($self, $string) = @_;

	my ($dest64_h, $dest64_l, $dest16) = $self->_getAddress();

	my $packet = {
		type => 'transmitRequest',
		payload => {
			dest64_h => $dest64_h,
			dest64_l => $dest64_l,
			dest16 => $dest16,
			radius => 0,
			options => 0,
			data => $string,
		},
	};

	$self->{network}->sendPacket($packet);
}

=item I<addData($string)>

Add a received string to our buffer of received (unprocessed) data.
This is used by XBee::Network when it has received a data packet from
the device.

=cut

sub addData {
	my ($self, $string) = @_;

	$self->{buffer} .= $string;
}

=item I<getData()>

Retrieve any buffered data which has been previously added to this node
through addData(). Returns '' if the buffer is empty. This function empties
the buffer.

=cut

sub getData {
	my ($self) = @_;

	my $buf = $self->{buffer};
	$self->{buffer} = '';

	return $buf;
}

=item I<getLine()>

Return only one line of text from the buffer.

A line is a (possibly empty) set of characters ending in the first newline
(\n) character.

If the buffer is empty or does not contain a complete line, then return undef.

=cut

sub getLine {
	my ($self) = @_;

	my $buf = $self->{buffer};
	if ($buf =~ /^([^\n]*\n)(.*)/s) {
		my ($line, $rest) = ($1, $2);
		$self->{buffer} = $rest;
		return $line;
	}

	return undef;
}

=item I<handleTransmitStatus($packet)>

This function is a work in progress.

Handle a received 'transmitStatus' packet, which informs if the last data
packet was correctly received by the device. Transmit Status also includes
the 16-bit remote address of the device.

=cut

sub handleTransmitStatus {
	my ($self, $packet) = @_;

	my $payload = $packet->{payload};
	if (! $payload) {
		return;
	}

	my $remote_address = $payload->{remote_address};
	if ($remote_address) {
		$self->{addr16} = $remote_address;
	}

	# printf("%s handled transmit status remote_address %s\n", $self->{node_id}, $remote_address);
}

1;
