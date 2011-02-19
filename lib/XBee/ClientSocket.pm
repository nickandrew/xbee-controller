#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#   Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#   Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::ClientSocket - A client socket

=head1 DESCRIPTION

This class maintains a socket connection to a client.

=head1 METHODS

=over

=cut

package XBee::ClientSocket;

use strict;

use Selector::CommonSocket qw();

use base qw(Selector::CommonSocket);


# ---------------------------------------------------------------------------

=item new($selector, $socket, $handler)

Return a new instance of XBee::ClientSocket for the specified socket.

=cut

sub new {
	my ($class, $selector, $socket, $handler) = @_;

	my $self = {
		socket => $socket,
		selector => $selector,
		handler => $handler,
		buffer => undef,
	};

	bless $self, $class;

	$self->{selector}->addObject($self);

	return $self;
}


# ---------------------------------------------------------------------------

=item disconnect()

If connected, close our socket and forget it.

=cut

sub disconnect {
	my ($self) = @_;

	if ($self->{socket}) {
		$self->{selector}->removeSelect($self->socket());
		close($self->{socket});
		undef $self->{socket};
	}
}


# ---------------------------------------------------------------------------

=item watchdogTime()

Not currently defined. Return undef.

=cut

sub watchdogTime {
	my ($self) = @_;

	return undef;
}


# ---------------------------------------------------------------------------

=item watchdogEvent()

Not currently defined. Return undef.

=cut

sub watchdogEvent {
	my ($self) = @_;

	return undef;
}


# ------------------------------------------------------------------------

=item handleRead()

Read data from the socket. Pass it to our handler object.

=cut

sub handleRead {
	my ($self, $selector, $socket) = @_;

	my $buffer;
	my $handler = $self->{handler};

	my $n = $self->{socket}->recv($buffer, 256);
	if (!defined $n) {
		# Error on the socket
		print("Client socket error\n");
		$handler->removeClient($self);
		$self->disconnect();
		return;
	}

	my $l = length($buffer);

	if ($l == 0) {
		# Other end closed connection
		$handler->removeClient($self);
		$self->disconnect();
		return;
	}

	# Data is expected to be JSON-encoded text lines.
	# Buffer incomplete lines
	$self->{buffer} .= $buffer;

	while ($self->{buffer} =~ /^(.+)\r?\n(.*)/s) {
		my $line = $1;
		my $rest = $2;
		$self->{buffer} = $rest;
		$handler->clientRead($line);
	}
}

1;
