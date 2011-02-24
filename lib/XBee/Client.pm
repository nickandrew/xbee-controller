#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::Client - A tcp client of the XBee daemon

=head1 DESCRIPTOIN

The XBee::Client maintains a TCP socket connection to an XBee Daemon and is
able to receive and send JSON-encoded packets with the daemon.

=head1 SYNOPSIS

  $xcl = XBee::Client->new($server_address);

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

package XBee::Client;

use strict;

use IO::Select qw();
use JSON qw();

use Selector::SocketFactory qw();
use XBee::Packet qw();

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
		die "Unable to create a client socket";
	}

	my $self = {
		buffer => '',
		eof => 0,
		error => 0,
		json => JSON->new()->utf8(),
		socket => $socket,
	};

	bless $self, $class;

	return $self;
}

=head2 I<poll($timeout)>

Call select() on the socket with the specified timeout and return true
if it has data ready for read.

=cut

sub poll {
	my ($self, $timeout) = @_;

	my $sel = IO::Select->new();
	$sel->add($self->{socket});

	my @ready = $sel->can_read($timeout);

	if (@ready) {
		return 1;
	}

	return 0;
}

=head2 I<handleRead($socket)>

Read data from $socket and append to internal buffer.

=cut

sub handleRead {
	my ($self, $socket) = @_;

	my $buf;
	my $n = $socket->sysread($buf, 512);

	if ($n < 0) {
		$self->{error} = $!;
		die "Error $! on socket read";
	} elsif ($n == 0) {
		$self->{eof} = 1;
		die "EOF on socket read";
	}

	$self->{buffer} .= $buf;

	return 1;
}

=head2 I<readPacket()>

If the start of our internal buffer contains a text line, then
decode it and return the hashref if possible. The hashref is
blessed as an XBee::Packet.

If no packet is available (or could not be decoded), return undef.

=cut

sub readPacket {
	my ($self) = @_;

	return undef if (!defined $self->{buffer});

	if ($self->{buffer} =~ /^([^\n]*)\r?\n(.*)/s) {
		my ($line, $rest) = ($1, $2);

		$self->{buffer} = $rest;

		if ($line ne '') {
			my $packet = $self->{json}->decode($line);
			if ($packet) {
				bless $packet, 'XBee::Packet';
			}
			return $packet;
		}
	}

	return undef;
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

	# Read pending data
	$self->handleRead($self->{socket});

	# Try again to turn it into a packet

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

	my $string = $self->{json}->encode($packet) . "\n";

	$self->{socket}->syswrite($string);
}

1;
