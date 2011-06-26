#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

Selector::PeerSocket - A Selector object which maintains a connection to a peer

=head1 DESCRIPTION

This class maintains a socket connection to a peer. It is used as an
intermediary between a Selector object and protocol handlers.

=head1 METHODS

=over

=cut

package Selector::PeerSocket;

use strict;

use Selector::CommonSocket qw();
use Selector::Handler qw();

use base qw(Selector::CommonSocket Selector::Handler);


# ---------------------------------------------------------------------------

=item I<new($selector, $socket, $handler)>

Return a new instance of Selector::PeerSocket for the specified socket.

=cut

sub new {
	my ($class, $selector, $socket) = @_;

	my $self = {
		socket => $socket,
		selector => $selector,
		handlers => { },
	};

	bless $self, $class;

	$self->{selector}->addSelect( [ $socket, $self ] );

	return $self;
}


# ---------------------------------------------------------------------------

=item I<disconnect()>

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


# ------------------------------------------------------------------------

=item I<handleRead($selector, $socket)>

Read data from the socket. Pass it to our handler object.

=cut

sub handleRead {
	my ($self, $selector, $socket) = @_;

	my $buffer;

	my $sock = $self->{socket};
	my $n = $sock->recv($buffer, 256);

	if (!defined $n) {
		# Error on the socket
		$self->runHandler('socketError', $sock);
		$self->disconnect();
		return;
	}

	my $l = length($buffer);

	if ($l == 0) {
		# Other end closed connection
		$self->runHandler('EOF', $sock);
		$self->disconnect();
		return;
	}

	$self->runHandler('addData', $buffer);
}


=item I<writeData($string)>

Write a string to the socket.

=cut

sub writeData {
	my ($self, $string) = @_;

	$self->{socket}->syswrite($string);

	return undef;
}

1;
