#!/usr/bin/perl -w
#  vim:sw=4:ts=4:

=head1 NAME

XBee::API::Series2 - XBee Series 2 API

=head1 DESCRIPTION

This class implements the AT command set and API command set of the
Series 2 modules. Different modules have different arguments and
return values from the same commands.

For example, the return values for the 'ND' command from Series 2 are:
     MY, SH, SL, NI, PARENT_NETWORK_ADDRESS, DEVICE_TYPE, STATUS, PROFILE_ID, MFR_ID
whereas the return values from the 802.15.4 firmware are:
     MY, SH, SL, DB, NI

It's brain dead, so different decoding modules are needed.

=head1 METHODS

This class implements the following methods:

=cut

package XBee::API::Series2;

use strict;

=head2 I<new($client)>

Instantiate a new object of this class.

$client is a reference to an XBee::Client.

=cut

sub new {
	my ($class, $client) = @_;

	my $self = {
		client => $client,
		frame_id => int(rand(64) + 8), # initial frame_id
	};

	bless $self, $class;
	return $self;
}

=head2 I<sendNodeDiscover($ni_value)>

Format and send a 'Node Discover' command.

$ni_value can be an optional 20-byte NI or MY value; it is presently ignored.

Returns a true value.

=cut

sub sendNodeDiscover {
	my ($self, $ni_value) = @_;

	my $frame_id = $self->{frame_id};
	my $data = pack('CCa2', 0x08, $frame_id, 'ND');

	my $cmd_hr = {
		type => 'APICommand',
		data => $data,
	};

	$self->{client}->sendData($cmd_hr);

	# Bump frame number
	$self->{frame_id} = ($frame_id + 1) % 0xff;

	return 1;
}

sub parseATResponse {
	my ($self, $payload) = @_;

	my $cmd = $payload->{cmd};
	my $value = $payload->{value};

	my @bytes = split(//, $value);
	printf("Cmd: %s data: %s\n", $cmd, join(' ', map { sprintf("%02x", ord($_)) } (@bytes)));

	if ($cmd eq 'ND') {
		my ($my, $sh, $sl, $ni, $parent_network, $device_type, $status, $profile_id, $manufacturer_id) = unpack('nNNZ*nCCnn', $value);

		my $hr = {
			'AT Command Response' => 'Node Discover',
			'16-bit address'      => sprintf("%04x", $my),
			'64 bit address'      => sprintf("%08x %08x", $sh, $sl),
			'Node Identifier'     => $ni,
			'Parent Network Addr' => sprintf("%04x", $parent_network),
			'Device Type'         => sprintf("%x", $device_type),
			'Status'              => sprintf("%x", $status),
			'Profile ID'          => sprintf("%04x", $profile_id),
			'Manufacturer ID'     => sprintf("%04x", $manufacturer_id),
		};

		return $hr;
	}

	return undef;
}

1;
