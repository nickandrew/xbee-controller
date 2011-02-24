#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::Packet - Encapsulation of a packet to/from XBee via TCP

=cut

package XBee::Packet;

use strict;

sub new {
	my ($class, $hr) = @_;

	my $self = { %$hr };
	bless $self, $class;

	return $self;
}

sub source {
	my ($self, $source) = @_;

	if (defined $source) {
		if ($source !~ /^([0-9a-fA-F]+):([0-9a-fA-F]+)$/) {
			die "Invalid XBee address $source";
		}

		# Not sure if this is useful
		my ($h, $l) = ($1, $2);
		$self->{payload}->{sender64_h} = hex($h);
		$self->{payload}->{sender64_l} = hex($l);

		return;
	}

	if (! $self->{payload}) {
		return undef;
	}

	my $p = $self->{payload};

	return sprintf("%x:%x", $p->{sender64_h}, $p->{sender64_l});
}

# Set or get the data string in a packet

sub data {
	my ($self, $data) = @_;

	if (defined $data) {
		$self->{payload}->{data} = $data;
		return;
	}

	if (! $self->{payload}) {
		return undef;
	}

	return $self->{payload}->{data};
}

sub type {
	my ($self, $type) = @_;

	if ($type) {
		$self->{type} = $type;
		return;
	}

	return $self->{type};
}

1;
