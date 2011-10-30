#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

Selector::Handler - A base class for objects which connect via handlers

=head1 SYNOPSIS

   $object->setHandler('handler-name', $self, 'function-name');

   $self->runHandler('handler-name', @args);

=head1 DESCRIPTION

This base class provides methods for decoupling objects. The coupling
is added at runtime via named handlers. A handler is a string which
invokes a function on another object. Both the object and function are
not hardcoded, but set at runtime (usually by some controlling object).

=cut

package Selector::Handler;

use strict;

sub setHandler {
	my ($self, $name, $obj, $func) = @_;

	if (! $name) {
		die "setHandler: need name";
	}

	$self->{handlers}->{$name} = {
		obj => $obj,
		func => $func,
	};
}

sub runHandler {
	my ($self, $name, @args) = @_;

	if (!defined $name) {
		die "runHandler: need name";
	}

	my $hr = $self->{handlers}->{$name};

	if ($hr && $hr->{obj} && $hr->{func}) {
		my $obj = $hr->{obj};
		my $func = $hr->{func};

		if ($obj && $func) {
			$obj->$func(@args);
		}
	} elsif ($ENV{DEBUG}) {
		print STDERR "No handler for $self handler $name\n";
	}
}

1;
