#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  XBee API common features implemented by all XBee devices

=head1 NAME

XBee::API::Common - XBee API methods

=head1 DESCRIPTION

This class performs API frame parsing for all XBee series with consistent
frame structures.

=head1 METHODS

This class implements the following methods:

=cut

package XBee::API::Common;

use strict;

my $common_types = {
	'08' => {
		description => 'AT Command',
		unpack => 'CCa2a*',
		keys => [qw(type frame_id cmd value)],
		handler => 'ATCommand',
	},
	'09' => {
		description => 'AT Command Queue',
		unpack => 'CCa2a*',
		keys => [qw(type frame_id cmd value)],
		handler => 'ATCommandQueue',
	},
	'88' => {
		description => 'AT Command Response',
		unpack => 'CCa2Ca*',
		keys => [qw(type frame_id cmd status value)],
		handler => 'ATResponse',
	},
};

my $unknown_type = {
	description => 'Unknown API Frame',
	func => '_APIFrame',
	handler => 'APIFrame',
};


=head2 I<new()>

Instantiate a new object of this class.

=cut

sub new {
	my ($class) = @_;

	my $self = { };

	bless $self, $class;

	return $self;
}


=head2 I<parseFrame($string)>

Parse the supplied string and return a hashref with the decoded contents.

The frame type code is found in the first byte of the string.

The hashref format is:

	type => 'keyword representing the frame type',
	payload => {
		type => integer type code,
		other type-specific keys
	}

=cut

sub parseFrame {
	my ($self, $data) = @_;

	my $type = sprintf('%02x', ord(substr($data, 0, 1)));

	my $hr = $self->_getTypeRef($type);

	if (! $hr) {
		# Hmm, should not happen
		die "Unable to get a reference for type $type";
	}

	my $func = $hr->{func};
	my $handler = $hr->{handler};

	my $payload = _unpackFrame($hr->{unpack}, $hr->{keys}, $data);

	if (defined $func) {
		$self->$func($data, $hr, $payload);
	}

	return {
		payload => $payload,
		type => $handler,
	};
}


=head2 I<parsePacket($packet)>

If a packet type is 'APIFrame' (meaning that it could not be decoded),
try again to decode the packet. This allows client code which uses
packets from an XBee to be newer (i.e. to implement more frame types) than
long-running daemon code which parses frames into packets.

Return a packet hashref, possibly the same one supplied.

=cut

sub parsePacket {
	my ($self, $packet) = @_;

	if ($packet->{type} ne 'APIFrame') {
		return $packet;
	}

	my $string = $packet->{payload}->{data};

	return $self->parseFrame($string);
}

# ---------------------------------------------------------------------------
# Return the hashref describing a specified frame type.
# If the type is unknown to this class (being the superclass), return the
# hashref used for unknown frame types.
# ---------------------------------------------------------------------------

sub _getTypeRef {
	my ($self, $type) = @_;

	my $hr = $common_types->{$type};

	if (! $hr) {
		$hr = $unknown_type;
	}

	return $hr;
}

# ---------------------------------------------------------------------------
# Unpack a frame data structure. Return a hashref.
# ---------------------------------------------------------------------------

sub _unpackFrame {
	my ($unpack, $keys, $data) = @_;

	if (! $unpack || !$keys) {
		return { };
	}

	my @values = unpack($unpack, $data);

	my $packet = { };

	foreach my $k (@$keys) {
		$packet->{$k} = shift(@values);
	}

	return $packet;
}

# ---------------------------------------------------------------------------
# Put the type and unknown data contents into an 'APIFrame' packet.
# ---------------------------------------------------------------------------

sub _APIFrame {
	my ($self, $data, $packet_desc, $packet) = @_;

	$packet->{type} = ord(substr($data, 0, 1));
	$packet->{data} = $data;
}

1;
