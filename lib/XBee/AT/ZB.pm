#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::AT::ZB - XBee AT command set - ZB firmware (latest)

=head1 DESCRIPTION

This class attempts to implement the full 'AT' command set supported by
the ZB firmware.
At present there is some support for parsing AT command responses, but
very little for constructing valid commands.

=head1 METHODS

=over

=cut

package XBee::AT::ZB;

use strict;

my $at_cmd_set = {
	# Special Commands
	'WR' => 'Write NVRAM',
	'WB' => 'Write Binding Table',
	'RE' => 'Restore Defaults',
	'FR' => 'Software Reset',
	'NR' => 'Network Reset',

	# Addressing
	'DH' => 'Destination Address High',
	'DL' => 'Destination Address Low',
	'ZA' => 'ZigBee Application Layer Addressing',
	'SE' => 'Source Endpoint', # AT only
	'DE' => 'Destination Endpoint', # AT only
	'CI' => 'Cluster Identifier', # AT only
	'BI' => 'Binding Table Index', # AT only
	'MY' => '16-bit Network Address',
	'MP' => '16-bit Parent Network Address',
	'SH' => 'Serial Number High',
	'SL' => 'Serial Number Low',
	'NI' => 'Node Identifier',

	# Networking & Security
	'CH' => 'Operating Channel',
	'ID' => 'PAN ID',
	'BH' => 'Broadcast Hops',
	'NT' => 'Node Discover Timeout',
	'ND' => 'Node Discover',
	'DN' => 'Destination Node',
	'JN' => 'Join Notification',
	'SC' => 'Scan Channels',
	'SD' => 'Scan Duration',
	'NJ' => 'Node Join Time',
	'AR' => 'Aggregate Routing Notification',
	'AI' => 'Association Indication',

	# RF Interfacing
	'PL' => 'Power Level',
	'PM' => 'Power Mode',

	# Serial Interfacing (I/O)
	'AP' => 'API Enable',
	'AO' => 'API Options',
	'BD' => 'Interface Data Rate',
	'RO' => 'Packetization Timeout',
	'D7' => 'DIO7 Configuration', # Default is CTS Flow Control
	'D6' => 'DIO6 Configuration', # Disabled or RTS Flow Control
	'D5' => 'DIO5 Configuration',

	# I/O Commands
	'P0' => 'PWM0 Configuration',
	'P1' => 'DIO11 Configuration',
	'P2' => 'DIO12 Configuration',
	'RP' => 'RSSI PWM Timer',
	'IS' => 'Force Sample',
	'D0' => 'AD0/DIO0 Configuration',
	'D0' => 'AD1/DIO1 Configuration',
	'D0' => 'AD2/DIO2 Configuration',
	'D0' => 'AD3/DIO3 Configuration',
	'D0' => 'DIO4 Configuration',

	# Diagnostics
	'VR' => 'Firmware Version',
	'HV' => 'Hardware Version',

	# AT Command Options
	'CT' => 'Command Mode Timeout',
	'CN' => 'Exit Command Mode',
	'GT' => 'Guard Times',
	'CC' => 'Command Sequence Character',

	# Sleep Commands
	'SM' => 'Sleep Mode',
	'SN' => 'Number of Sleep Periods',
	'SP' => 'Sleep Period',
	'ST' => 'Time Before Sleep',
};

my $at_cmd_specs = {
	'pack' => {
		'NJ' => [
			[ 'time', 'C' ],
		],
	},
};

=item I<new()>

Return a new instance of this class.

=cut

sub new {
	my ($class) = @_;

	my $self = { };
	bless $self, $class;
	return $self;
}

=item I<getCommandName($cmd)>

Return a readable English description of a 2-character AT command name.

=cut

sub getCommandName {
	my ($self, $cmd) = @_;

	my $v = $at_cmd_set->{$cmd};
	return $v;
}

=item I<listCommands()>

Return a hashref listing each supported AT command and its English
description.

=cut

sub listCommands {
	my ($self) = @_;

	my %list = %$at_cmd_set;
	return \%list;
}

=item I<packCommand($cmd, $args)>

Pack the arguments to a command into a string, and return the string.

=cut

sub packCommand {
	my ($self, $cmd, $args) = @_;

	if (!defined $cmd) {
		return undef;
	}

	if ($cmd !~ /^..$/) {
		# Not a 2-char command
		return undef;
	}

	my $spec = $at_cmd_specs->{$cmd};

	if (! $spec) {
		# Simplest - if not specified, return command with no arguments.
		return $cmd;
	}

	my $s = $cmd;

	foreach my $lr (@{$spec->{'pack'}}) {
		my ($key, $pack) = @$lr;

		$s .= pack($pack, $args->{$key});
	}

	return $s;
}

=item I<parseATResponse($payload_hr)>

Parse the received AT Response and return a formatted hashref.

$payload_hr contains {cmd} and {value} keys, where 'cmd' is the
AT command code, and 'value' is a string to be unpacked.

At present the following AT responses are parsed:

  - ND  Node Discovery
  - NI  Node Identification
  - PL  Power Level
  - SH  Serial Number High
  - SL  Serial Number Low
  - NJ  Node Join
  - VR  Firmware Version

=cut

sub parseATResponse {
	my ($self, $payload) = @_;

	my $cmd = $payload->{cmd};
	my $value = $payload->{value};

	my $hr;

	if ($cmd eq 'ND') {
		my ($my, $sh, $sl, $ni, $parent_network, $device_type, $status, $profile_id, $manufacturer_id) = unpack('nNNZ*nCCnn', $value);

		$hr = {
			'AT Command Response' => 'Node Discover',
			'16-bit address'      => sprintf("%04x", $my),
			'64 bit address'      => sprintf("%x:%x", $sh, $sl),
			'Node Identifier'     => $ni,
			'Parent Network Addr' => sprintf("%04x", $parent_network),
			'Device Type'         => sprintf("%x", $device_type),
			'Status'              => sprintf("%x", $status),
			'Profile ID'          => sprintf("%04x", $profile_id),
			'Manufacturer ID'     => sprintf("%04x", $manufacturer_id),
		};
	}
	elsif ($cmd eq 'NI') {
		my ($ni) = $value;

		$hr = {
			'AT Command Response' => 'Node Identity',
			'Node Identifier'     => $ni,
		};
	}
	elsif ($cmd eq 'PL') {
		my ($power_level) = unpack('C', $value);

		my $power_levels = {
			0 => '-10/10 dBm',
			1 => '-6/12 dBm',
			2 => '-4/14 dBm',
			3 => '-2/16 dBm',
			4 => '0/18 dBm',
		};

		$hr = {
			'AT Command Response' => 'Power Level',
			'Power Level Id' => $power_level,
			'Power Level' => $power_levels->{$power_level},
		};
	}
	elsif ($cmd eq 'SH') {
		my ($sh) = unpack('N', $value);

		$hr = {
			'AT Command Response' => 'Serial Number High',
			'Serial Number High' => sprintf("%x", $sh),
		};
	}
	elsif ($cmd eq 'SL') {
		my ($sl) = unpack('N', $value);

		$hr = {
			'AT Command Response' => 'Serial Number Low',
			'Serial Number Low' => sprintf("%x", $sl),
		};
	}
	elsif ($cmd eq 'NJ') {
		my ($nj) = unpack('C', $value);

		$hr = {
			'AT Command Response' => 'Node Join',
			'Node Join' => sprintf("%x", $nj),
		};
	}
	elsif ($cmd eq 'VR') {
		my ($vr) = unpack('n', $value);

		$hr = {
			'AT Command Response' => 'Firmware Version',
			'Firmware Version' => sprintf("%x", $vr),
		};
	}
	else {
		my @bytes = split(//, $value);
		printf("Unparsed AT: %s data: %s\n", $cmd, join(' ', map { sprintf("%02x", ord($_)) } (@bytes)));
	}

	return $hr;
}

1;
