#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  XBee controller daemon

=head1 NAME

Controller::Daemon - Connect server, clients and listeners

=head1 DESCRIPTION

This class connects an XBee and clients such that packets received from
the XBee are decoded and forwarded (as json strings) to all clients.

Any packets received from a client are sent to the XBee.

There is also a set of listening sockets; connections on any of them
are accepted and become new clients.

=cut

package Controller::Daemon;

use strict;

use JSON qw();
use Time::HiRes qw();

use Selector::ListenSocket qw();
use Selector qw();
use XBee::ClientSocket qw();
use XBee::Device qw();

sub new {
	my ($class) = @_;

	my $self = {
		clients => 0,
		client_sockets => { },
		selector => undef,
		server => undef,
	};

	bless $self, $class;

	$self->{selector} = Selector->new();
	$self->{json} = JSON->new()->utf8();
	$self->{json}->canonical(1);

	my $xbee = XBee::Device->new();
	$self->{xbee} = $xbee;
	$xbee->setHandler('ATResponse', $self, 'ATResponse');
	$xbee->setHandler('transmitStatus', $self, 'transmitStatus');
	$xbee->setHandler('receivePacket', $self, 'receivePacket');
	$xbee->setHandler('nodeIdentificationIndicator', $self, 'nodeIdentificationIndicator');
	$xbee->setHandler('readEOF', $self, 'serverReadEOF');

	return $self;
}

sub addListener {
	my ($self, $socket) = @_;

	my $listener = Selector::ListenSocket->new($socket, $self);
	if (! $listener) {
		warn "Unable to add listener\n";
		return;
	}

	$self->{selector}->addSelect([$socket, $listener]);
}

sub addServer {
	my ($self, $tty_obj) = @_;

	my $socket = $tty_obj->socket();
	$self->{xbee_socket} = $socket;
	$self->{selector}->addSelect([$socket, $self->{xbee}]);
}

sub addClient {
	my ($self, $socket) = @_;

	my $client = XBee::ClientSocket->new($self->{selector}, $socket, $self);
	$self->{client_sockets}->{$socket} = $client;
	$self->{clients} ++;
}

sub removeClient {
	my ($self, $client) = @_;

	my $socket = $client->socket();
	if (exists $self->{client_sockets}->{$socket}) {
		delete $self->{client_sockets}->{$socket};
		$self->{clients} --;
		print("Removed client\n");
	}
}

sub eventLoop {
	my ($self) = @_;

	$self->{selector}->eventLoop();
}

sub nodeIdentificationIndicator {
	my ($self, $packet_hr) = @_;

	$self->serverDistribute($packet_hr, 'nodeIdentificationIndicator');
}

sub ATResponse {
	my ($self, $packet_hr) = @_;

	$self->serverDistribute($packet_hr, 'ATResponse');
}

sub transmitStatus {
	my ($self, $packet_hr) = @_;

	$self->serverDistribute($packet_hr, 'transmitStatus');
}

sub receivePacket {
	my ($self, $packet_hr) = @_;

	$self->serverDistribute($packet_hr, 'receivePacket');
}

sub serverDistribute {
	my ($self, $packet_hr, $type) = @_;

	my ($seconds, $microseconds) = Time::HiRes::gettimeofday();

	my $outer_frame = {
		type => $type,
		time_s => $seconds,
		time_u => $microseconds,
		payload => $packet_hr,
	};

	my $json = $self->{json}->encode($outer_frame);

	if ($self->{clients} == 0) {
		print("Ignored: $json\n");
		return;
	}

	my $rest = '';
	if ($self->{clients} > 1) {
		$rest = " to $self->{clients} clients";
	}

	print("Emitting: $json$rest\n");

	# Iterate through all clients

	foreach my $object (values %{$self->{client_sockets}}) {
		$object->send($json . "\n");
	}
}

# ---------------------------------------------------------------------------
# Called when EOF read on server socket (XBee device)
# ---------------------------------------------------------------------------

sub serverReadEOF {
	my ($self) = @_;

	print "Server read EOF\n";
	die "EOF on server socket";
}

# Receive a packet structure from a client.
# Decode it into a hashref, then transmit it to the XBee.

sub clientRead {
	my ($self, $line) = @_;

	print("Received: $line\n");

	my $packet_hr = $self->{json}->decode($line);

	if (!defined $packet_hr) {
		print "Unable to decode into a packet\n";
		return;
	}

	my $type = $packet_hr->{type};
	my $xbee = $self->{xbee};
	my $socket = $self->{xbee_socket};

	if ($type eq 'transmitRequest') {
		$xbee->transmitRequest($socket, $packet_hr);
	}
	elsif ($type eq 'APICommand') {
		$xbee->writeData($socket, $packet_hr->{data});
	}
}

1;
