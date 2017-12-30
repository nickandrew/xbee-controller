#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#   A controller for a terminal function (i.e. a program which allows the
#   user to send text messages to XBees, and which displays the text messages
#   received from XBees).


package Controller::Terminal2;

use strict;

use Time::HiRes qw();
use YAML qw();

use Selector qw();
use Selector::PeerSocket qw();
use Terminal qw();
use TullNet::XBee::Encaps::JSON qw();
use TullNet::XBee::TTY qw();

sub new {
	my ($class, $client_socket) = @_;

	my $selector = Selector->new();

	my $encaps = TullNet::XBee::Encaps::JSON->new();
	my $peer = Selector::PeerSocket->new($selector, $client_socket);
	my $tty_device = TullNet::XBee::TTY->new('/dev/tty');
	my $terminal = Terminal->new();

	$selector->addSelect( [ $client_socket, $peer ] );
	$selector->addSelect( [ $tty_device->socket(), $terminal ] );

	my $self = {
		terminal => $terminal,
		tty_device => $tty_device,
		encaps => $encaps,
		selector => $selector,
		eof => 0,
		frame_id => int(rand(254)) + 1,
	};

	$encaps->setHandler('packet', $self, 'dumpPacket');
	$encaps->setHandler('sendPacket', $peer, 'writeData');

	$peer->setHandler('addData', $encaps, 'addData');
	$peer->setHandler('socketError', $self, 'peerError');
	$peer->setHandler('EOF', $self, 'peerEOF');

	bless $self, $class;

	$terminal->setHandler('line', $self, 'terminalLine');
	$terminal->setHandler('EOF', $self, 'terminalEOF');

	return $self;
}

sub pollForever {
	my ($self) = @_;

	my $selector = $self->{selector};
	my $count = 0;

	while (! $self->{eof}) {
		my $timeout = $selector->pollServer(10);

		if ($timeout) {
			$count ++;
		}
	}
}

sub terminalLine {
	my ($self, $line) = @_;

	if ($line =~ /^ND/) {
		$self->sendNodeDiscover();
	}
	elsif ($line =~ /^AT (..)/) {
		# Send AT command (no args yet)
		my $cmd = $1;
		print "Sending AT command: $cmd\n";
		my $packet = {
			type => 'ATCommand',
			payload => {
				cmd => $cmd,
				args => '',
			},
		};

		$self->{encaps}->sendPacket($packet);
	}
	elsif ($line =~ /^AO (\d+)/) {
		# Send AO command (no args yet)
		my $arg = chr($1);
		my $packet = {
			type => 'ATCommand',
			payload => {
				cmd => 'AO',
				args => $arg,
			},
		};
		print "Sending AO command\n";
		$self->{encaps}->sendPacket($packet);
	}
	elsif ($line =~ /^DEST ([0-9a-f]+):([0-9a-f]+)/) {
		# Set the destination of the next packet
		$self->{destination}->{'64_h'} = hex($1);
		$self->{destination}->{'64_l'} = hex($2);
		print "Set destination to $1:$2\n";
	}
	elsif ($line =~ /^SOURCE ([0-9a-f]+):([0-9a-f]+)/) {
		# Set a filter on incoming messages
		$self->{source} = "$1:$2";
		print "Set filtered source to $1:$2\n";
	}
	elsif ($line =~ /^SEND (.+)/) {
		my $data = $1;

		# Do simple unescaping of the data
		$data =~ s/\\n/\n/g;
		$data =~ s/\\r/\r/g;
		$data =~ s/\\/\\/g;

		my $d_h = $self->{destination}->{'64_h'};
		my $d_l = $self->{destination}->{'64_l'};
		if (! $d_h || ! $d_l) {
			print "No destination set\n";
		} else {
			my $packet = {
				type => 'transmitRequest',
				payload => {
					dest64_h => $d_h,
					dest64_l => $d_l,
					dest16 => 0xfffe,
					radius => 0,
					options => 0,
					data => $data,
				},
			};

			$self->{encaps}->sendPacket($packet);
		}
	}
}

sub terminalEOF {
	my ($self) = @_;

	print "EOF on terminal.\n";
	$self->{eof} = 1;
}

sub peerError {
	my ($self) = @_;

	print "Error from peer.\n";
	$self->{eof} = 1;
}

sub peerEOF {
	my ($self) = @_;

	print "EOF from peer.\n";
	$self->{eof} = 1;
}

# ---------------------------------------------------------------------------
# Return a readable string (newlines, tabs etc converted to \\ notation)
# ---------------------------------------------------------------------------

sub escapeString {
	my ($s) = @_;

	$s =~ s/\\/\\\\/g;
	$s =~ s/\n/\\n/g;
	$s =~ s/\r/\\r/g;
	$s =~ s/\t/\\t/g;

	return $s;
}

sub dumpPacket {
	my ($self, $packet) = @_;

	my $type = $packet->{type};
	my $payload = $packet->{payload};

	my ($sec, $usec) = Time::HiRes::gettimeofday();

	if ($type eq 'receivePacket') {
		my $src = sprintf("%x:%x", $payload->{sender64_h}, $payload->{sender64_l});

		if ($self->{source} && $self->{source} ne $src) {
			# Ignore this packet; from a different source
			return;
		}

		printf("%10d.%06d %-15.15s ", $sec, $usec, $type);
		my $i = index($payload->{data}, "\n");
		printf("<<< %-17s  ", $src);

		my $s = escapeString($payload->{data});

		print $s, "\n";
		return;
	}
	elsif ($type eq 'transmitStatus') {
		printf("%10d.%06d %-15.15s ", $sec, $usec, $type);
		printf("Transmit status: frame_id %d delivery %d discovery %d remote 0x%04x\n",
			$payload->{frame_id},
			$payload->{delivery_status},
			$payload->{discovery_status},
			$payload->{remote_address},
		);
		return;
	}
	elsif ($type eq 'ATResponse') {
		my $cmd = $payload->{cmd};
		printf("%10d.%06d %-15.15s ", $sec, $usec, $type);
		print "AT Response, command $cmd\n";

		if ($cmd eq 'ND') {
			print "  Node Discovery (not decoded)\n";
		}
		else {
			print YAML::Dump($packet);
		}
		return;
	}
	elsif ($type eq 'transmitRequest') {
		printf("%10d.%06d %-15.15s ", $sec, $usec, $type);
		my $dst = sprintf("%8x:%8x", $payload->{dest64_h}, $payload->{dest64_l});
		printf(">>> %-17s  ", $dst);

		my $s = escapeString($payload->{data});

		print $s, "\n";
		return;
	}
	elsif ($type eq 'nodeIdentificationIndicator') {
		printf("%10d.%06d %-15.15s ", $sec, $usec, $type);
		my $src = sprintf("%8x:%8x", $payload->{sender64_h}, $payload->{sender64_l});
		my $src16 = sprintf("%4x", $payload->{sender16});
		my $remote = sprintf("%8x:%8x", $payload->{remote64_h}, $payload->{remote64_l});
		my $remote16 = sprintf("%4x", $payload->{remote16});
		my $device_type = $payload->{device_type};

		printf("Device type %d at %s %s connected to %s %s\n",
			$device_type,
			$src,
			$src16,
			$remote,
			$remote16
		);

		# Fall through to dump the whole packet
	}

	print "Received packet:\n";
	print YAML::Dump($packet);
}

sub sendNodeDiscover {
	my ($self, $ni_value) = @_;

	return $self->_sendATCommand('ND');
}

# ---------------------------------------------------------------------------
# Pack an AT command and send it
# ---------------------------------------------------------------------------

sub _sendATCommand {
	my ($self, $at, $rest) = @_;

	my $frame_id = $self->{frame_id};
	$rest = '' if (!defined $rest);
	my $data = pack('CCa2', 0x08, $frame_id, $at) . $rest;

	my $cmd_hr = {
		type => 'APICommand',
		data => $data,
	};

	$self->{encaps}->sendPacket($cmd_hr);

	# Bump frame number
	$self->{frame_id} = ($frame_id + 1) % 0xff;

	return 1;
}

1;
