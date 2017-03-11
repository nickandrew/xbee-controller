#!/usr/bin/perl -w
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#

package XBee::TTY;

use strict;

use IO::File qw(O_RDWR);

sub new {
	my ($class, $filename) = @_;

	my $self = {
		filename => $filename,
	};

	bless $self, $class;

	if (! -c $filename) {
		die "Not a character special file: $filename";
	}

	my $fh = IO::File->new($filename, O_RDWR());
	if (! $fh) {
		die "Unable to open $filename for read-write - $!";
	}

	$self->{fh} = $fh;
	$self->{fd} = $fh->fileno();

	return $self;
}

sub socket {
	my ($self) = @_;

	return $self->{fh};
}

1;
