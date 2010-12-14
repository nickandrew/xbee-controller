#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  XBee device

package XBee::Device;

use strict;

my $DEBUG = 1;

my $response_set = {
	'88' => {
		description => 'AT Command Response',
		func => '_ATResponse',
	},
	'8a' => {
		description => 'RF Module Status',
		func => '_modemStatus',
	},
	'8b' => {
		description => 'ZigBee Transmit Status',
		func => '_transmitStatus',
	},
	'8c' => {
		description => 'Advanced Modem Status',
		func => '_advancedModemStatus',
	},
	'90' => {
		description => 'ZigBee Receive Packet',
		func => '_receivePacket',
	},
	'91' => {
		description => 'ZigBee Explicit RX Indicator',
		func => '_explicitReceivePacket',
	},
	'92' => {
		description => 'ZigBee Binding RX Indicator',
		func => '_bindingReceivePacket',
	},
	'94' => {
		description => 'XBee Sensor Read Indicator', # ZB not 2.5
		func => undef,
	},
	'95' => {
		description => 'Node Identification Indicator', # ZB not 2.5
		func => undef,
	},
	'97' => {
		description => 'Remote Command Response', # ZB not 2.5
		func => undef,
	},
};

sub new {
	my ($class) = @_;

	my $self = {
		data => undef,
		l_msb => undef,
		to_read => undef,
		cksum => undef,
		state => 0,
	};

	bless $self, $class;

	return $self;
}

# ---------------------------------------------------------------------------
# We've been advised that there is data to read on the socket. Read it and
# try to construct a frame from it.
# ---------------------------------------------------------------------------

sub handleRead {
	my ($self, $selector, $socket) = @_;

	my $buf;
	my $start = chr(0x7e);

	my $n = sysread($socket, $buf, 100);
	if ($n == 0) {
		# EOF
		print STDERR "FIXME - read EOF\n";
		$selector->removeSelect($self);
		return 0;
	}

	my $state = $self->{'state'};

	foreach my $c (split(//, $buf)) {

		if ($state == 0) {
			if ($c eq $start) {
				$self->{'data'} = undef;
				$self->{'done'} = 0;
				$state = 1;
			}
		}
		elsif ($state == 1) {
			$self->{'l_msb'} = ord($c);
			$state = 2;
		}
		elsif ($state == 2) {
			my $l_lsb = ord($c);
			$self->{'to_read'} = ($self->{'l_msb'} << 8) + $l_lsb;
			$self->{'cksum'} = 0;
			$state = 3;
		}
		elsif ($state == 3) {
			$self->{'data'} .= $c;
			$self->{'cksum'} += ord($c);
			$self->{'to_read'} --;
			if ($self->{'to_read'} == 0) {
				$state = 4;
			}
		}
		elsif ($state == 4) {
			$self->{'cksum'} += ord($c);
			if ($self->{'cksum'} & 0xff != 0xff) {
				$self->checksumError();
			} else {
				# We're done here
				$self->recvdFrame();
			}

			$state = 0;
		}
		else {
			die "Illegal state $state";
		}
	}

	# Remember state for next time
	$self->{'state'} = $state;

	return 1;
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
	my ($self) = @_;

	$self->{'done'} = 1;
	my $data = $self->{'data'};
	$self->printHex("Received frame:", $data);

	my $type = sprintf('%02x', ord(substr($self->{'data'}, 0, 1)));

	my $hr = $response_set->{$type};
	if (! $hr) {
		printf STDERR ("Received unknown packet type: %s\n", $type);
		return;
	}

	my $description = $hr->{description} || 'no description';
	my $func = $hr->{func};

	if (!defined $func) {
		printf STDERR ("Ignoring packet of type: %s\n", $description);
		return;
	}

	# Call the appropriate handler function
	$self->$func($data);
}

# ---------------------------------------------------------------------------
# Received packet handler functions
# ---------------------------------------------------------------------------

sub _ATResponse {
	my ($self, $data) = @_;

	my ($type, $frame_id, $cmd, $status, $value) = unpack('CCa2Ca*', $data);

	printf STDERR ("Recvd AT response: frame_id %d, cmd %s, status %d ", $frame_id, $cmd, $status);
	$self->printHex("value:", $value);
}

sub _modemStatus {
	my ($self, $data) = @_;

	my ($type, $cmd_data) = unpack('CC', $data);

	my $hr = {
		hardware_reset => ($cmd_data & 1) ? 1 : 0,
		watchdog_reset => ($cmd_data & 2) ? 1 : 0,
		joined => ($cmd_data & 4) ? 1 : 0,
		unjoined => ($cmd_data & 8) ? 1 : 0,
		coord_started => ($cmd_data & 16) ? 1 : 0,
	};

	printf STDERR ("Recvd Modem Status: hw_reset %d, wdog_reset %d, join %d, unjoin %d, coord %d\n",
		$hr->{hardware_reset},
		$hr->{watchdog_reset},
		$hr->{joined},
		$hr->{unjoined},
		$hr->{coord_started},
	);
}

sub _transmitStatus {
	my ($self, $data) = @_;

	my ($type, $frame_id, $remote_address, $retry_count, $delivery_status, $discovery_status) = unpack('CCnCC', $data);

	printf STDERR ("Recvd Transmit Status: frame_id %d, remote_addr %04x, retries %d, delivery_status 0x%02x, discovery_status 0x%02x\n", $frame_id, $remote_address, $retry_count, $delivery_status, $discovery_status);
}

sub _advancedModemStatus {
	my ($self, $data) = @_;

	my ($type, $status_id) = unpack('CC', $data);

	if ($status_id == 0) {
		my ($type, $status_id, $addr64_h, $addr64_l, $addr_16, $dev_type, $join_action) = unpack('CCNNnCC', $data);
		printf STDERR "Recvd Advanced Modem Status: node64 %08x %08x, node16 %04x, type %d, join_action %d\n", $addr64_h, $addr64_l, $addr_16, $dev_type, $join_action;
	} elsif ($status_id == 1) {
		my ($type, $status_id, $bind_index, $bind_type) = unpack('CCCC', $data);
		printf STDERR "Recvd Advanced Modem Status: bind_index %d, bind type %d\n", $bind_index, $bind_type;
	} else {
		printf STDERR "Recvd Advanced Modem Status: invalid status_id 0x%02x\n", $status_id;
	}
}

sub _receivePacket {
	my ($self, $data) = @_;

	my ($type, $addr64_h, $addr64_l, $addr_16, $options, $rf_data) = unpack('CNNnCa*', $data);

	printf STDERR ("Recvd data packet: node64 %08x %08x, node16 %04x, options %d, rf_data %s\n", $addr64_h, $addr64_l, $addr_16, $options, $rf_data);
	$self->{'rx_data'} = $rf_data;
	$self->printHex("RF Data:", $rf_data);
}

sub _explicitReceivePacket {
	my ($self, $data) = @_;

	my ($type, $addr64_h, $addr64_l, $addr_16, $src_endpoint, $dst_endpoint, $cluster_id, $profile_id, $options, $rf_data) = unpack('CNNnCCnnCa*', $data);

	printf STDERR ("Recvd explicit data packet: node64 %08x %08x, node16 %04x, src_e %02x, dst_e %02x, cluster_id %04x, profile_id %04x, options %d, rf_data %s\n", $addr64_h, $addr64_l, $addr_16, $src_endpoint, $dst_endpoint, $cluster_id, $profile_id, $options, $rf_data);
	$self->{'rx_data'} = $rf_data;
	$self->printHex("RF Data:", $rf_data);
}

sub _bindingReceivePacket {
	my ($self, $data) = @_;

	my ($type, $bind_index, $dst_endpoint, $cluster_id, $options, $rf_data) = unpack('CCCnCa*', $data);

	printf STDERR ("Recvd binding data packet: bind_index %d, dst_e %02x, cluster_id %04x, options %d, rf_data %s\n", $bind_index, $dst_endpoint, $cluster_id, $options, $rf_data);
	$self->{'rx_data'} = $rf_data;
	$self->printHex("RF Data:", $rf_data);
}

sub getLastRXData {
	my ($self) = @_;

	my $rx_data = $self->{'rx_data'};
	$self->{'rx_data'} = undef;

	return $rx_data;
}

# ---------------------------------------------------------------------------
# Write a data frame to the device
# Return 1 if written, 0 if error
# ---------------------------------------------------------------------------

sub writeData {
	my ($self, $fh, $buf) = @_;

	my $len = length($buf);

	if ($len > 10000) {
		# Too long
		$@ = 'Packet too long';
		return 0;
	}

	my $l_lsb = $len & 0xff;
	my $l_msb = $len >> 8;

	my $chksum = 0;
	foreach my $c (split(//, $buf)) {
		$chksum += ord($c);
	}
	$chksum = 0xff - ($chksum & 0xff);

	my $s = chr(0x7e) . chr($l_msb) . chr($l_lsb) . $buf . chr($chksum);

	# $self->printHex("Send Frame:", $s);

	syswrite($fh, $s);

	return 1;
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

sub printHex {
	my ($self, $heading, $s) = @_;

	if ($DEBUG && defined($s)) {
		my $str = $heading;

		my @chars = unpack('C*', $s);
		foreach my $i (@chars) {
			$str .= sprintf(" %02x", $i);
		}
		print STDERR "$str\n";
	}
}

sub sendRemoteCommand {
	my ($self, $fh, $addr64_h, $addr64_l, $addr_16, $options, $cmd, $args) = @_;

	my $frame_id = $self->{'frame_id'} || 0;
	if (! $frame_id) {
		$frame_id = 1;
	}

	my $s = pack('CCNNnCa2', 0x17, $frame_id, $addr64_h, $addr64_l, $addr_16, $options, $cmd);
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

1;
