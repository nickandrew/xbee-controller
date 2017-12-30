#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010-2017, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

=head1 NAME

TullNet::XBee::API::Frame - XBee API packet framing

=head1 DESCRIPTION

This class implements the lowest layer of the XBee API protocol: correct assembly
and disassembly of frames.

The frame structure is:

  start delimiter - 0x7e
  data length MSB (1 byte)
  data length LSB (1 byte)
  data (N bytes)
  checksum (1 byte)

Packets longer than 255 bytes (by default) are ignored.

=head2 METHODS

=cut

package TullNet::XBee::API::Frame;

use strict;
use warnings;


=head2 I<new()>

Return a new instance of this class. There are no parameters.

=cut

sub new {
	my ($class) = @_;

	my $self = {
		debug => 0,
		data => undef,
		leading_junk => '',
		l_msb => undef,
		packet_max_length => 255,
		to_read => undef,
		cksum => undef,
		state => 0,
	};

	bless $self, $class;

	return $self;
}


=head2 I<addData($buf)>

Add the contents of $buf to our internal buffer. Whenever it contains a
complete and correct frame, call $self->recvdFrame($data).

If there's an error in the frame, call $self->checksumError().

=cut

sub addData {
	my ($self, $buf) = @_;

	my $state = $self->{'state'};

	foreach my $c (split(//, $buf)) {

		if ($state == 0) {
			if ($c eq chr(0x7e)) {
				$self->{'data'} = undef;
				$self->{'done'} = 0;
				$self->{'cksum'} = 0;
				$state = 1;
				if ($self->{'leading_junk'} ne '') {
					$self->printHex("Skipping junk pre frame start:", $self->{'leading_junk'});
				}
				$self->{'leading_junk'} = '';
			} else {
				$self->{'leading_junk'} .= $c;
			}
		}
		elsif ($state == 1) {
			$self->{'l_msb'} = ord($c);
			$state = 2;
		}
		elsif ($state == 2) {
			$self->{'l_lsb'} = ord($c);
			my $length = ($self->{'l_msb'} << 8) + $self->{'l_lsb'};
			if ($length > $self->{'packet_max_length'}) {
				# Don't allow arbitrarily long packets
				$self->error("Long packet (length %d) ignored, max is %d",
					$length, $self->{'packet_max_length'});
				$state = 0;
			} else {
				$self->{'length'} = $length;
				$self->{'to_read'} = $length;
				$state = 3;
			}
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
			my $cksum_byte = ord($c);
			$self->{'cksum_byte'} = $cksum_byte;
			$self->{'cksum'} += $cksum_byte;

			if (($self->{'cksum'} & 0xff) != 0xff) {
				$self->checksumError();
			} else {
				# We're done here
				my $data = $self->{'data'};
				$self->{'data'} = undef;
				$self->recvdFrame($data);
			}

			$state = 0;
		}
		else {
			die "Illegal state $state";
		}
	}

	# Remember state within frame for next time
	$self->{'state'} = $state;

	return 1;
}


=head2 I<checksumError()>

Called when an invalid frame has been detected.

Override this in subclasses.

=cut

sub checksumError {
	my ($self) = @_;

	my $err = sprintf("Frame Checksum error: start=7e l_msb=%02x l_lsb=%02x (length %d), cksum_byte=%02x, cksum=%02x (expected 0xff), data:",
		$self->{'l_msb'},
		$self->{'l_lsb'},
		$self->{'length'},
		$self->{'cksum_byte'},
		$self->{'cksum'},
	);
	$self->printHex($err, $self->{'data'});
}


=head2 I<recvdFrame($data)>

Called when a frame has been successfully received from the XBee.

Override this in subclasses.

=cut

sub recvdFrame {
	my ($self, $data) = @_;

	$self->{'done'} = 1;
	$self->printHex("Received frame:", $data);
}


=head2 I<serialise($buf)>

Build a frame from the data in $buf, and return it:

    0x7e, MSB(length), LSB(length), $buf, checksum($buf)

Return undef if unable to build a packet, with a reason in $@.

=cut

sub serialise {
	my ($self, $buf) = @_;

	if (!defined $buf) {
		$@ = 'No data supplied';
		return undef;
	}

	my $len = length($buf);

	if ($len > $self->{'packet_max_length'}) {
		# Too long
		$@ = sprintf('Packet too long: length=%d, maximum=%d', $len, $self->{'packet_max_length'});
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


=head2 I<debug($string, args...)>

If debugging is enabled, then printf supplied string and args to STDERR. A newline is appended.

=cut

sub debug {
	my $self = shift;

	if ($self->{'debug'}) {
		printf STDERR (@_);
		print STDERR "\n";
	}
}


=head2 I<error($string, args...)>

Printf supplied string to STDERR. A newline is appended.

=cut

sub error {
	my $self = shift;

	printf STDERR (@_);
	print STDERR "\n";
}

=head2 I<printHex($title, $buf)>

If a buffer is supplied, then print to STDERR the title followed
by the buffer contents in hex, then a newline.

=cut

sub printHex {
	my ($self, $title, $buf) = @_;

	if (defined($buf)) {
		my $str = $title;

		my @chars = unpack('C*', $buf);
		foreach my $i (@chars) {
			$str .= sprintf(" %02x", $i);
		}

		print STDERR $str, "\n";
	}
}

1;
