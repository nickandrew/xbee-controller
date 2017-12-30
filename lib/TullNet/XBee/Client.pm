#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

TullNet::XBee::Client - A tcp client of the XBee daemon

=head1 DESCRIPTOIN

The TullNet::XBee::Client maintains a TCP socket connection to an XBee Daemon and is
able to receive and send JSON-encoded packets with the daemon.

=head1 SYNOPSIS

  $xcl = TullNet::XBee::Client->new($server_address);

  $packet = $xcl->receivePacket($timeout);

  if ($packet && $packet->isData()) {
    my $contents = $packet->data();
  }

Or

  $packet = $xcl->readPacket();

  if (! $packet) {
    $data_pending = $xcl->poll($timeout);

    if ($data_pending) {
      $xcl->handleRead($xcl->socket());
      $packet = $xcl->readPacket();
    }
  }


=head1 METHODS

=cut

package TullNet::XBee::Client;

use strict;

use IO::Select qw();
use JSON qw();

use Selector qw();
use Selector::PeerSocket qw();
use Selector::SocketFactory qw();
use TullNet::XBee::Encaps::JSON qw();
use TullNet::XBee::Packet qw();

=head2 I<new($server_address)>

Connect to the specified server (e.g. '127.0.0.1:7862' or ':::7862') and
return an instantiated object.

=cut

sub new {
	my ($class, $server_address) = @_;

	my $socket = Selector::SocketFactory->new(
		PeerAddr => $server_address,
		Proto => 'tcp',
	);

	if (!defined $socket) {
		die "Unable to create a client socket to $server_address";
	}

	my $selector = Selector->new();
	my $peer = Selector::PeerSocket->new($selector, $socket);
	my $encaps = TullNet::XBee::Encaps::JSON->new();

	my $self = {
		eof => 0,
		error => 0,
		json => JSON->new()->utf8(),
		packet_queue => [ ],
		encaps => $encaps,
		socket => $socket,
		selector => $selector,
		peer => $peer,
	};

	$peer->setHandler('addData', $encaps, 'addData');
	$peer->setHandler('EOF', $self, 'setEOF');
	$peer->setHandler('socketError', $self, 'setError');

	$encaps->setHandler('packet', $self, 'queuePacket');
	$encaps->setHandler('sendPacket', $peer, 'writeData');

	bless $self, $class;

	return $self;
}

=head2 I<poll($timeout)>

Call select() on the socket with the specified timeout and return true
if it has data ready for read.

=cut

sub poll {
	my ($self, $timeout) = @_;

	my $rc = $self->{selector}->pollServer($timeout);

	if ($rc == 0) {
		return 1;
	}

	return 0;
}

=head2 I<queuePacket()>

Accept a packet from a socket and queue internally.

=cut

sub queuePacket {
	my ($self, $packet) = @_;

	push(@{$self->{packet_queue}}, $packet);
}

=head2 I<readPacket()>

Dequeue a packet from our internal queue, and return it.
Return undef if the queue is empty.

=cut

sub readPacket {
	my ($self) = @_;

	my $packet = shift(@{$self->{packet_queue}});

	return $packet;
}

=head2 I<receivePacket($timeout)>

A packet is a hashref. It's passed through the TCP connection encoded as
a JSON data structure on a single line.

If a complete line has already been received, then decode the JSON data
and return the corresponding data structure.

Otherwise, try to receive data from the socket (until the specified
timeout) and return a packet data structure if possible.

=cut

sub receivePacket {
	my ($self, $timeout) = @_;

	my $packet = $self->readPacket();
	return $packet if ($packet);

	if (! $self->poll($timeout)) {
		return undef;
	}

	# Try again to retrieve a packet

	return $self->readPacket();
}

=head2 I<isEOF()>

Return true if EOF has been seen.

=cut

sub isEOF {
	my ($self) = @_;

	return $self->{eof};
}

=head2 I<isError()>

Return true if a socket error has been seen.

=cut

sub isError {
	my ($self) = @_;

	return $self->{error};
}

=head2 I<close()>

Close the open socket.

=cut

sub close {
	my ($self) = @_;

	if ($self->{socket}) {
		$self->{socket}->close();
		delete $self->{socket};
	}
}

=head2 I<socket()>

Return the socket handle.

=cut

sub socket {
	my ($self) = @_;

	return $self->{socket};
}

=head2 I<sendData($packet)>

Send a packet to the server.

=cut

sub sendData {
	my ($self, $packet) = @_;

	my $string = $self->{json}->encode($packet);

	$self->{encaps}->sendPacket($packet);
}

=head2 I<sendATCommand($string)>

Send an AT command packet (type 0x08)

=cut

sub sendATCommand {
	my ($self, $cmd, $args) = @_;

	my $packet = {
		type => 'ATCommand',
		payload => {
			cmd => $cmd,
			args => $args,
		},
	};

	$self->sendData($packet);
}

=head2 I<setEOF()>

Set this object's EOF flag. It's called by a peer socket when EOF is noticed.

=cut

sub setEOF {
	my ($self) = @_;

	$self->{eof} = 1;
}

=head2 I<setError()>

Set this object's error flag. It's called by a peer socket when an error occurs.

=cut

sub setError {
	my ($self) = @_;

	$self->{error} = 1;
}

1;
