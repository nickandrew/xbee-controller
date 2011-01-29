#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

XBee::API::Frame - XBee API packet framing

=head1 DESCRIPTION

This class implements the lowest layer of the XBee API protocol: correct assembly
and disassembly of frames.

The frame structure is:

  start delimiter - 0x7e
  data length MSB (1 byte)
  data length LSB (1 byte)
  data (N bytes)
  checksum (1 byte)

=head2 METHODS

=cut

package XBee::API::Frame;

use strict;

my $DEBUG = 1;


=head2 I<new()>

Return a new instance of this class. There are no parameters.

=cut

sub new {
	my ($class) = @_;

	my $self = {
		data => undef,
		l_msb => undef,
		to_read => undef,
		cksum => undef,
		state => 0,
	};

	bless $self, $class;

	return $self;
}


=head2 I<addData($buf)>

Add the contents of $buf to our internal buffer. Whenever it contains a
complete and correct frame, call $self->recvdFrame(); the data is in
$self->{data}.

If there's an error in the frame, call $self->checksumError().

=cut

sub addData {
	my ($self, $buf) = @_;

	my $start = chr(0x7e);
	my $state = $self->{'state'};

	foreach my $c (split(//, $buf)) {

		if ($state == 0) {
			if ($c eq $start) {
				$self->{'data'} = undef;
				$self->{'done'} = 0;
				$state = 1;
			}
		}
		elsif ($state == 1) {
			$self->{'l_msb'} = ord($c);
			$state = 2;
		}
		elsif ($state == 2) {
			my $l_lsb = ord($c);
			$self->{'to_read'} = ($self->{'l_msb'} << 8) + $l_lsb;
			$self->{'cksum'} = 0;
			$state = 3;
		}
		elsif ($state == 3) {
			$self->{'data'} .= $c;
			$self->{'cksum'} += ord($c);
			$self->{'to_read'} --;
			if ($self->{'to_read'} == 0) {
				$state = 4;
			}
		}
		elsif ($state == 4) {
			$self->{'cksum'} += ord($c);

			if (($self->{'cksum'} & 0xff) != 0xff) {
				$self->checksumError();
			} else {
				# We're done here
				$self->recvdFrame();
			}

			$state = 0;
		}
		else {
			die "Illegal state $state";
		}
	}

	# Remember state for next time
	$self->{'state'} = $state;

	return 1;
}


=head2 I<checksumError()>

Called when an illegal frame has been detected.

Override this in subclasses.

=cut

sub checksumError {
	my ($self) = @_;

	printf STDERR ("Checksum error: got %02x, expected 0xff\n", $self->{'cksum'});
	$self->printHex("Bad frame:", $self->{'data'});
}


=head2 I<recvdFrame()>

Called when a frame has been successfully received from the XBee.

Override this in subclasses.

=cut

sub recvdFrame {
	my ($self) = @_;

	$self->{'done'} = 1;
	my $data = $self->{'data'};
	$self->printHex("Received frame:", $data);
}


=head2 I<serialise($buf)>

Build a frame from the data in $buf, and return it:

    0x7e, MSB(length), LSB(length), $buf, checksum($buf)

Return undef if unable to build a packet, with a reason in $@.

=cut

sub serialise {
	my ($self, $buf) = @_;

	my $len = length($buf);

	if ($len > 10000) {
		# Too long
		$@ = 'Packet too long';
		return undef;
	}

	my $l_lsb = $len & 0xff;
	my $l_msb = $len >> 8;

	my $chksum = 0;
	foreach my $c (split(//, $buf)) {
		$chksum += ord($c);
	}
	$chksum = 0xff - ($chksum & 0xff);

	my $s = chr(0x7e) . chr($l_msb) . chr($l_lsb) . $buf . chr($chksum);

	return $s;
}


=head2 I<printHex($title, $string)>

If debugging is enabled and a string is supplied,
then print to STDOUT the title followed by the string in hex.

=cut

sub printHex {
	my ($self, $heading, $s) = @_;

	if ($DEBUG && defined($s)) {
		my $str = $heading;

		my @chars = unpack('C*', $s);
		foreach my $i (@chars) {
			$str .= sprintf(" %02x", $i);
		}

		print STDERR "$str\n";
	}
}

1;
