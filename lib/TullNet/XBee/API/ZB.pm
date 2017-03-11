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
	'11' => {
		description => 'Explicit Addressing ZigBee Command Frame',
		unpack => 'CCNNnCCnnCCa*',
		keys => [qw(type frame_id dst64_h dst64_l dst16 src_endpoint dst_endpoint cluster_id profile_id radius options data)],
		handler => 'explicitCommandFrame',
	},
	'21' => {
		description => 'Create Source Route',
		unpack => 'CCNNnCC',
		keys => [qw(type frame_id dst64_h dst64_l dst16 route_options nr_addresses)],
		handler => 'createSourceRoute',
	},
	'88' => {
		description => 'AT Command Response',
		unpack => 'CCa2Ca*',
		keys => [qw(type frame_id cmd status value)],
		handler => 'ATResponse',
	},
	'8a' => {
		description => 'Modem Status',
		unpack => 'CC',
		keys => [qw(type status_code)],
		func => '_modemStatus',
		handler => 'modemStatus',
	},
	'8b' => {
		description => 'ZigBee Transmit Status',
		unpack => 'CCnCCC',
		keys => [qw(type frame_id remote_address retry_count delivery_status discovery_status)],
		handler => 'transmitStatus',
	},
	'90' => {
		description => 'ZigBee Receive Packet',
		unpack => 'CNNnCa*',
		keys => [qw(type sender64_h sender64_l sender16 options data)],
		handler => 'receivePacket',
	},
	'91' => {
		description => 'ZigBee Explicit Rx Indicator',
		unpack => 'CNNnCCnnCa*',
		keys => [qw(type src64_h src64_l src16 src_endpoint dst_endpoint cluster_id profile_id options data)],
		handler => 'explicitReceivePacket',
	},
	'92' => {
		description => 'ZigBee IO Data Sample Rx Indicator',
		unpack => 'CNNnCCnC',
		keys => [qw(type src64_h src64_l src16 options samples digital_ch_mask analog_ch_mask)],
		handler => 'receiveIOSample',
	},
	'94' => {
		description => 'XBee Sensor Read Indicator',
		unpack => 'CNNnCC',
		keys => [qw(type src64_h src64_l src16 options sensors)],
		handler => 'receiveSensor',
	},
	'95' => {
		description => 'Node Identification Indicator',
		unpack => 'CNNnCnNNZnCCnn',
		keys => [qw(type sender64_h sender64_l sender16 rx_options remote16 remote64_h remote64_l node_id parent16 device_type source_event digi_profile_id manufacturer_id)],
		handler => 'nodeIdentificationIndicator',
	},
	'97' => {
		description => 'Over-the-Air Firmware Update Status',
		unpack => 'CNNnCCCNN',
		keys => [qw(type src64_h src64_l dst16 rx_options message_type block_number target64_h target64_l)],
		handler => 'OTAFirmwareUpdateStatus',
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
