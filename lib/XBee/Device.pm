#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  XBee device

package XBee::Device;

use strict;

use base qw(XBee::API::Frame);

my $DEBUG = 1;

my $response_set = {
	'88' => {
		description => 'AT Command Response',
		func => '_ATResponse',
		unpack => 'CCa2Ca*',
		keys => [qw(type frame_id cmd status value)],
		handler => 'ATResponse',
	},
	'8a' => {
		description => 'RF Module Status',
		func => '_modemStatus',
		handler => 'modemStatus',
	},
	'8b' => {
		description => 'ZigBee Transmit Status',
		unpack => 'CCnCCC',
		keys => [qw(type frame_id remote_address retry_count delivery_status discovery_status)],
		handler => 'transmitStatus',
	},
	'8c' => {
		description => 'Advanced Modem Status',
		func => '_advancedModemStatus',
		handler => 'advancedModemStatus',
	},
	'90' => {
		description => 'ZigBee Receive Packet',
		func => '_receivePacket',
		unpack => 'CNNnCa*',
		keys => [qw(type sender64_h sender64_l sender16 options data)],
		handler => 'receivePacket',
	},
	'91' => {
		description => 'ZigBee Explicit RX Indicator',
		func => '_explicitReceivePacket',
		unpack => 'CNNnCCnnCa*',
		keys => [qw(type sender64_h sender64_l sender16 src_endpoint dst_endpoint cluster_id profile_id options data)],
		handler => 'receivePacket',
	},
	'92' => {
		description => 'ZigBee IO Data Sample Rx Indicator',
		func => '_IODataSample',
		unpack => 'CNNnCCnCa*',
		keys => [qw(type sender64_h sender64_l sender16 options samples digital_ch_mask analog_ch_mask data)],
		handler => 'receiveIOSample',
	},
	'94' => {
		description => 'XBee Sensor Read Indicator', # ZB not 2.5
		func => undef,
	},
	'95' => {
		description => 'Node Identification Indicator', # ZB not 2.5
		unpack => 'CNNnCnNNZnCCnn',
		keys => [qw(type sender64_h sender64_l sender16 rx_options remote16 remote64_h remote64_l node_id parent16 device_type source_event digi_profile_id manufacturer_id)],
		handler => 'nodeIdentificationIndicator',
	},
	'97' => {
		description => 'Remote Command Response', # ZB not 2.5
		func => undef,
	},
};

my $unknown_frame_type = {
	description => 'API Frame',
	func => '_APIFrame',
	handler => 'APIFrame',
};

sub new {
	my ($class) = @_;

	my $self = $class->SUPER::new();

	bless $self, $class;

	return $self;
}

sub setHandler {
	my ($self, $name, $obj, $func) = @_;

	if (! $name) {
		die "setHandler: need name";
	}

	$self->{handlers}->{$name} = {
		obj => $obj,
		func => $func,
	};
}

sub runHandler {
	my ($self, $name, @args) = @_;

	if (!defined $name) {
		die "runHandler: need name";
	}

	my $hr = $self->{handlers}->{$name};

	if ($hr && $hr->{obj} && $hr->{func}) {
		my $obj = $hr->{obj};
		my $func = $hr->{func};

		if ($obj && $func) {
			$obj->$func(@args);
		}
	}
}

sub checksumError {
	my ($self, $cksum) = @_;

	printf STDERR ("Checksum error: got %02x, expected 0xff\n", $self->{'cksum'});
	$self->printHex("Bad frame:", $self->{'data'});
}

# ---------------------------------------------------------------------------
# Called when a frame has been successfully received from the XBee
# ---------------------------------------------------------------------------

sub recvdFrame {
	my ($self, $data) = @_;

	$self->{'done'} = 1;

	my $type = sprintf('%02x', ord(substr($data, 0, 1)));

	my $hr = $response_set->{$type};
	if (! $hr) {
		# Minimally encapsulate the frame
		$hr = $unknown_frame_type;
	}

	my $description = $hr->{description} || 'no description';
	my $func = $hr->{func};
	my $handler = $hr->{handler};

	my $payload = _unpackFrame($hr->{unpack}, $hr->{keys}, $data);

	if (defined $func) {
		$self->$func($data, $hr, $payload);
	}

	my $packet = {
		type => $handler,
		payload => $payload,
	};

	$self->runHandler('recvdPacket', $packet);
}

# ---------------------------------------------------------------------------
# Unpack a frame data structure. Return a hashref
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
# Called when EOF read on socket
# ---------------------------------------------------------------------------

sub readEOF {
	my ($self) = @_;

	$self->runHandler('readEOF', undef);
}

# ---------------------------------------------------------------------------
# Received packet handler functions
# ---------------------------------------------------------------------------

sub _ATResponse {
	my ($self, $data, $packet_desc, $packet) = @_;

	printf STDERR ("Recvd AT response: frame_id %d, cmd %s, status %d ",
		$packet->{frame_id},
		$packet->{cmd},
		$packet->{status}
	);

	$self->printHex("value:", $packet->{value});
}

sub _modemStatus {
	my ($self, $data, $packet_desc, $packet) = @_;

	my ($type, $cmd_data) = unpack('CC', $data);

	$packet->{hardware_reset} = ($cmd_data & 1) ? 1 : 0;
	$packet->{watchdog_reset} = ($cmd_data & 2) ? 1 : 0;
	$packet->{joined} = ($cmd_data & 4) ? 1 : 0;
	$packet->{unjoined} = ($cmd_data & 8) ? 1 : 0;
	$packet->{coord_started} = ($cmd_data & 16) ? 1 : 0;

	printf STDERR ("Recvd Modem Status: hw_reset %d, wdog_reset %d, join %d, unjoin %d, coord %d\n",
		$packet->{hardware_reset},
		$packet->{watchdog_reset},
		$packet->{joined},
		$packet->{unjoined},
		$packet->{coord_started},
	);
}

sub _advancedModemStatus {
	my ($self, $data, $packet_desc, $packet) = @_;

	my ($type, $status_id) = unpack('CC', $data);

	$packet->{type} = $type;
	$packet->{status_id} = $status_id;

	if ($status_id == 0) {
		my ($type, $status_id, $addr64_h, $addr64_l, $addr_16, $dev_type, $join_action) = unpack('CCNNnCC', $data);
		printf STDERR "Recvd Advanced Modem Status: node64 %08x %08x, node16 %04x, type %d, join_action %d\n", $addr64_h, $addr64_l, $addr_16, $dev_type, $join_action;
		$packet->{addr64_h} = $addr64_h;
		$packet->{addr64_l} = $addr64_l;
		$packet->{addr_16} = $addr_16;
		$packet->{dev_type} = $dev_type;
		$packet->{join_action} = $join_action;
	} elsif ($status_id == 1) {
		my ($type, $status_id, $bind_index, $bind_type) = unpack('CCCC', $data);
		printf STDERR "Recvd Advanced Modem Status: bind_index %d, bind type %d\n", $bind_index, $bind_type;
		$packet->{bind_index} = $bind_index;
		$packet->{bind_type} = $bind_type;
	} else {
		printf STDERR "Recvd Advanced Modem Status: invalid status_id 0x%02x\n", $status_id;
	}
}

sub _receivePacket {
	my ($self, $data, $packet_desc, $packet) = @_;

}

sub _explicitReceivePacket {
	my ($self, $data, $packet_desc, $packet) = @_;

	printf STDERR ("Recvd explicit data packet: node64 %08x %08x, node16 %04x, src_e %02x, dst_e %02x, cluster_id %04x, profile_id %04x, options %d\n",
		$packet->{sender64_h},
		$packet->{sender64_l},
		$packet->{sender16},
		$packet->{src_endpoint},
		$packet->{dst_endpoint},
		$packet->{cluster_id},
		$packet->{profile_id},
		$packet->{options});

	$self->printHex("RF Data:", $packet->{data});
	print STDERR "Data: $packet->{data}\n";
}

sub _IODataSample {
	my ($self, $data, $packet_desc, $packet) = @_;

	my $data = $packet->{data};

	printf STDERR ("Recvd IO data sample: sender64 %x:%x sender16 %04x options %x nsamples %x digital_mask %04x analog_mask %02x,",
		$packet->{sender64_h},
		$packet->{sender64_l},
		$packet->{sender16},
		$packet->{options},
		$packet->{nsamples},
		$packet->{digital_ch_mask},
		$packet->{analog_ch_mask},
	);

	$self->printHex(" data:", $packet->{data});

	if ($packet->{digital_ch_mask}) {
		$packet->{digital_data} = unpack('n', substr($data, 0, 2));
		printf STDERR ("Digital data: %04x\n", $packet->{digital_data});
	}

}

sub _APIFrame {
	my ($self, $data, $packet_desc, $packet) = @_;

	$packet->{type} = sprintf('%02x', ord(substr($data, 0, 1)));
	$packet->{data} = $data;
}

sub writeATCommand {
	my ($self, $fh, $cmd, $args) = @_;

	my $frame_id = $self->{'frame_id'} || 0;
	if (! $frame_id) {
		$frame_id = 1;
	}

	my $s = pack('CCa2', 0x08, $frame_id, $cmd);
	if (defined $args) {
		$s .= $args;
	}

	$self->{'frame_id'} = ($frame_id + 1) & 0xff;

	printf STDERR ("Send AT command: frame_id %d, cmd %s", $frame_id, $cmd);
	if (defined $args) {
		$self->printHex(", args:");
	} else {
		print STDERR "\n";
	}

	return $self->writeData($fh, $s);
}

sub sendRemoteCommand {
	my ($self, $fh, $payload) = @_;

	my $frame_id = $self->{'frame_id'} || 0;
	if (! $frame_id) {
		$frame_id = 1;
	}

	my $dest64_h = $payload->{dest64_h};
	my $dest64_l = $payload->{dest64_l};
	my $dest16 = $payload->{dest16};
	my $options = $payload->{options};
	my $cmd = $payload->{cmd};
	my $args = $payload->{args};

	my $s = pack('CCNNnCa2', 0x17, $frame_id, $dest64_h, $dest64_l, $dest16, $options, $cmd);
	if (defined $args) {
		$s .= $args;
	}

	$self->{'frame_id'} = ($frame_id + 1) & 0xff;

	printf STDERR ("Send Remote AT command: frame_id %d, cmd %s", $frame_id, $cmd);
	if (defined $args) {
		$self->printHex(", args:");
	} else {
		print STDERR "\n";
	}

	return $self->writeData($fh, $s);
}

sub transmitRequest {
	my ($self, $fh, $packet) = @_;

	my $payload = $packet->{payload};

	my $frame_id = $payload->{'frame_id'} || $self->{frame_id} || 0;
	if (! $frame_id) {
		$frame_id = 1;
	}

	my $addr64_h = $payload->{'dest64_h'};
	my $addr64_l = $payload->{'dest64_l'};
	my $addr_16 = $payload->{'dest16'};
	my $radius = $payload->{'radius'};
	my $options = $payload->{'options'};
	my $data = $payload->{'data'};

	my $s = pack('CCNNnCCa*', 0x10, $frame_id, $addr64_h, $addr64_l, $addr_16, $radius, $options, $data);

	$self->{'frame_id'} = ($frame_id + 1) & 0xff;

	$self->printHex("Transmit Request:");
	return $self->writeData($fh, $s);
}

# ---------------------------------------------------------------------------
# We've been advised that there is data to read on the socket. Read it and
# try to construct a frame from it.
# ---------------------------------------------------------------------------

sub handleRead {
	my ($self, $selector, $socket) = @_;

	my $buf;

	my $n = sysread($socket, $buf, 200);
	if ($n == 0) {
		# EOF
		$selector->removeSelect($socket);
		close($socket);
		$self->readEOF();
		return 0;
	}

	if ($n < 0) {
		die "Read error on XBee socket";
	}

	$self->addData($buf);
	return 1;
}

# ---------------------------------------------------------------------------
# Write a data frame to the device
# Return 1 if written, 0 if error
# ---------------------------------------------------------------------------

sub writeData {
	my ($self, $fh, $buf) = @_;

	if (!defined $buf) {
		return 0;
	}

	my $s = $self->serialise($buf);

	syswrite($fh, $s);

	return 1;
}

1;
