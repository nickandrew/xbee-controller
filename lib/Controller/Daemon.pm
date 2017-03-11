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
use Selector::PeerSocket qw();
use Selector qw();
use TullNet::XBee::Encaps::JSON qw();
use TullNet::XBee::Device qw();

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

	my $xbee = TullNet::XBee::Device->new();
	$self->{xbee} = $xbee;
	$xbee->setHandler('recvdPacket', $self, 'serverDistribute');
	$xbee->setHandler('readEOF', $self, 'serverReadEOF');

	return $self;
}

sub debug {
	my $self = shift;

	if (@_) {
		$self->{debug} = shift;
	}

	return $self->{debug};
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

	my $peer = Selector::PeerSocket->new($self->{selector}, $socket);
	my $encaps = TullNet::XBee::Encaps::JSON->new();

	$peer->setHandler('socketError', $self, 'removeClient');
	$peer->setHandler('EOF', $self, 'removeClient');
	$peer->setHandler('addData', $encaps, 'addData');

	$encaps->setHandler('sendPacket', $peer, 'writeData');
	$encaps->setHandler('packet', $self, 'clientRead');

	$self->{client_sockets}->{$socket} = $encaps;
	$self->{clients} ++;
}

sub removeClient {
	my ($self, $socket) = @_;

	if (exists $self->{client_sockets}->{$socket}) {
		delete $self->{client_sockets}->{$socket};
		$self->{clients} --;
		print("Removed client\n");
	}
}

sub eventLoop {
	my ($self) = @_;

	my $activity_time = time() + 120;

	while (1) {
		if (time() > $activity_time) {
			# No activity timeout, exit
			die "No activity for a long time";
		}

		my $rc = $self->{selector}->pollServer(60);
		if ($rc == 0) {
			# Something happened
			$activity_time = time() + 120;
		}

		if ($self->{server_eof}) {
			print "eventLoop() noticed EOF from server, returning\n";
			return;
		}
	}
}

sub serverDistribute {
	my ($self, $packet_hr, $source) = @_;

	my ($seconds, $microseconds) = Time::HiRes::gettimeofday();

	$packet_hr->{time_s} = $seconds;
	$packet_hr->{time_u} = $microseconds;

	my $json = $self->{json}->encode($packet_hr);

	if ($self->{clients} == 0) {
		print("Ignored: $json\n") if ($self->{debug});
		return;
	}

	my $rest = '';
	if ($self->{clients} > 1) {
		$rest = " to $self->{clients} clients";
	}

	print("Emitting: $json$rest\n") if ($self->{debug});

	# Transmit packet to all clients, except possibly the object $source
	foreach my $client (values %{$self->{client_sockets}}) {
		if (! $source || $source != $client) {
			$client->sendPacket($packet_hr);
		}
	}
}

# ---------------------------------------------------------------------------
# Called when EOF read on server socket (XBee device)
# ---------------------------------------------------------------------------

sub serverReadEOF {
	my ($self) = @_;

	print "Server socket read EOF\n";
	$self->{server_eof} = 1;
}

# Receive a packet structure from a client.
# Transmit it to the XBee

sub clientRead {
	my ($self, $packet_hr, $source) = @_;

	if (!defined $packet_hr) {
		print "No packet received\n";
		return;
	}

	my $type = $packet_hr->{type};
	my $xbee = $self->{xbee};
	my $socket = $self->{xbee_socket};
	my $payload = $packet_hr->{payload};

	# Distribute this packet to all other clients
	# First make an unblessed form, as JSON cannot handle it
	my %unblessed = %$packet_hr;
	$self->serverDistribute(\%unblessed, $source);

	if ($type eq 'transmitRequest') {
		$xbee->transmitRequest($socket, $packet_hr);
	}
	elsif ($type eq 'APICommand') {
		$xbee->writeData($socket, $packet_hr->{data});
	}
	elsif ($type eq 'ATCommand') {
		$xbee->writeATCommand($socket, $payload->{cmd}, $payload->{args});
	}
	elsif ($type eq 'remoteATCommand') {
		$xbee->sendRemoteCommand($socket, $payload);
	}
}

1;
