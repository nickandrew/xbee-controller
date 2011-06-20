#!/usr/bin/perl -w
#  vim:sw=4:ts=4:

=head1 NAME

XBee::API::ZB - XBee ZB API

=head1 DESCRIPTION

This class performs API frame parsing for the ZB firmware (version 21xx).

See I<XBee::API::Common> for usage information.

=head1 METHODS

This class implements the following methods:

=cut

package XBee::API::ZB;

use strict;

use base 'XBee::API::Common';

my $class_api = {
	'10' => {
		description => 'ZigBee Transmit Request',
		unpack => 'CCNNnCCa*',
		keys => [qw(type frame_id sender64_h sender64_l sender16 radius options data)],
		handler => 'transmitRequest',
	},
	'8a' => {
		description => 'Modem Status',
		unpack => 'CC',
		keys => [qw(type status_code)],
		func => '_modemStatus',
		handler => 'modemStatus',
	},
	'90' => {
		description => 'ZigBee Receive Packet',
		unpack => 'CNNnCa*',
		keys => [qw(type sender64_h sender64_l sender16 options data)],
		handler => 'receivePacket',
	},
};


=head2 I<new()>

Instantiate a new object of this class.

=cut

sub new {
	my ($class, $client) = @_;

	my $self = { };

	bless $self, $class;
	return $self;
}

# ---------------------------------------------------------------------------
# Return a reference to decoding information for packet types known to
# this class. If the type is not provided in this class, try the superclass.
# ---------------------------------------------------------------------------

sub _getTypeRef {
	my ($self, $type) = @_;

	my $hr = $class_api->{$type};
	if ($hr) {
		return $hr;
	}

	return $self->SUPER::_getTypeRef($type);
}

# ---------------------------------------------------------------------------
# Decode type 0x8a - Modem Status
# The exact list of codes varies by series.
# ---------------------------------------------------------------------------

sub _modemStatus {
	my ($self, $data, $packet_desc, $packet) = @_;

	my ($type, $status_code) = unpack('CC', $data);

	my $modem_status = {
		0 => 'Hardware reset',
		1 => 'Watchdog timer reset',
		2 => 'Joined network', # routers and end devices
		3 => 'Disassociated',
		6 => 'Coordinator started',
		7 => 'Network security key was updated',
		13 => 'Voltage supply limit exceeded', # PRO S2B only
		17 => 'Modem configuration changed while join in progress',
	};

	my $status = $modem_status->{$status_code} || 'Unknown';
	if ($status_code >= 0x80) {
		$status = sprintf("Stack error %02x", $status_code);
	}

	$packet->{status} = $status;
}

1;
