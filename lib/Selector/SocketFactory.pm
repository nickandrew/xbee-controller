#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

Selector::SocketFactory - Socket creation for both IPv4 and IPv6

=head1 DESCRIPTION

This package tests if perl IPv6 libraries are installed on this system
and if so, uses IPv6 socket classes (which are partly backwards compatible
with IPv4). If not, only IPv4 socket classes are used.

=head1 METHODS

=over

=cut

package Selector::SocketFactory;

use strict;

use Socket qw();

# Values should be:
#   0 == no ipv6, use IO::Socket::INET
#   1 == ipv6, use IO::Socket::IP (preferred)
#   2 == ipv6, use IO::Socket::INET6
my $ipv6_supported = 0;

eval "use IO::Socket::IP";

if (!$@) {
	$ipv6_supported = 1;
} else {
	eval "use IO::Socket::INET6";

	if (!$@) {
		$ipv6_supported = 2;
	} else {
		eval "use IO::Socket::INET";
		if ($@) {
			die "Unable to use IO::Socket::INET";
		}
	}
}


# ------------------------------------------------------------------------

=item new(@sockargs)

Create a new socket of IPv6 or IPv4 type and return it.

The argument @sockargs is the same hash which is supplied to IO::Socket::INET
or IO::Socket::INET6.

=cut

sub new {
	my ($class, @sockargs) = @_;

	my $s;

	if ($ipv6_supported == 1) {
		$s = IO::Socket::IP->new(@sockargs);
	} elsif ($ipv6_supported == 2) {
		$s = IO::Socket::INET6->new(@sockargs);
	} else {
		$s = IO::Socket::INET->new(@sockargs);
	}

	return $s;
}

1;
