#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::Encaps::JSON - JSON format encapsulation of XBee messages

XBee packets are processed as a hashref of the following format:

  $packet = {
    type => 'typeString',
    payload => { ... },
  };

They may be serialised as JSON strings or in some other manner. This class
implements the JSON serialisation.

=head1 METHODS

=over

=cut

use strict;

package XBee::Encaps::JSON;

use strict;

use JSON qw();

use Selector::Handler qw();

use base qw(Selector::Handler);

=item I<new()>

Return a new instance of this class.

=cut

sub new {
	my ($class) = @_;

	my $self = {
		buffer => '',
		json => JSON->new()->utf8(),
	};
	bless $self, $class;

	$self->{json}->canonical(1);

	return $self;
}

=item I<addData($data)>

Add the string $data to the internal buffer.
Any complete lines in the buffer are parsed as JSON strings, and if valid,
are passed to the 'packet' handler after being blessed as 'XBee::Packet'.

=cut

sub addData {
	my ($self, $data) = @_;

	$self->{buffer} .= $data;

	while ($self->{buffer} =~ /^([^\n]*\r?\n)(.*)/s) {
		my ($line, $rest) = ($1, $2);

		$self->{buffer} = $rest;

		chomp($line);
		$line =~ s/\r//g;

		if ($line ne '') {
			my $packet;

			eval {
				$packet = $self->{json}->decode($line);
			};

			if ($@) {
				# Error in decoding JSON
				$self->{error} = $@;
			} elsif ($packet) {
				bless $packet, 'XBee::Packet';
				$self->runHandler('packet', $packet, $self);
			}
		}
	}
}


=item I<sendPacket($packet)>

Encode a packet as JSON and pass it to the 'sendPacket' handler.

=cut

sub sendPacket {
	my ($self, $packet) = @_;

	my $string = $self->{json}->encode($packet) . "\n";

	$self->runHandler('sendPacket', $string);
}

1;
