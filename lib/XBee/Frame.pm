#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  XBee protocol: layer 1, framing

package XBee::Frame;

use strict;

my $DEBUG = 1;

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

# ---------------------------------------------------------------------------
# We've been advised that there is data to read on the socket. Read it and
# try to construct a frame from it.
# ---------------------------------------------------------------------------

sub handleRead {
	my ($self, $selector, $socket) = @_;

	my $buf;

	my $n = sysread($socket, $buf, 200);
	if ($n == 0) {
		# EOF
		$selector->removeSelect($socket);
		close($socket);
		$self->readEOF();
		return 0;
	}

	if ($n < 0) {
		die "Read error on XBee socket";
	}

	$self->addData($buf);
	return 1;
}

# ---------------------------------------------------------------------------
# Add the contents of $buf to our internal buffer. Whenever it contains a
# complete and correct frame, call $self->recvdFrame().
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Called when EOF is seen on the file handle.
# Override this in subclasses.
# ---------------------------------------------------------------------------

sub readEOF {
	my ($self) = @_;

	printf STDERR "EOF on XBee Frame\n";
}

# ---------------------------------------------------------------------------
# Called when an illegal frame has been detected.
# Override this in subclasses.
# ---------------------------------------------------------------------------

sub checksumError {
	my ($self, $cksum) = @_;

	printf STDERR ("Checksum error: got %02x, expected 0xff\n", $self->{'cksum'});
	$self->printHex("Bad frame:", $self->{'data'});
}

# ---------------------------------------------------------------------------
# Called when a frame has been successfully received from the XBee
# Override this in subclasses.
# ---------------------------------------------------------------------------

sub recvdFrame {
	my ($self) = @_;

	$self->{'done'} = 1;
	my $data = $self->{'data'};
	$self->printHex("Received frame:", $data);
}

# ---------------------------------------------------------------------------
# Build a frame from the data in $buf, and return it:
#    0x7e, MSB(length), LSB(length), $buf, checksum($buf)
# ---------------------------------------------------------------------------

sub serialise {
	my ($self, $buf) = @_;

	my $len = length($buf);

	if ($len > 10000) {
		# Too long
		$@ = 'Packet too long';
		return 0;
	}

	my $l_lsb = $len & 0xff;
	my $l_msb = $len >> 8;

	my $chksum = 0;
	foreach my $c (split(//, $buf)) {
		$chksum += ord($c);
	}
	$chksum = 0xff - ($chksum & 0xff);

	my $s = chr(0x7e) . chr($l_msb) . chr($l_lsb) . $buf . chr($chksum);

	# $self->printHex("Send Frame:", $s);

	return $s;
}

# ---------------------------------------------------------------------------
# Write a data frame to the device
# Return 1 if written, 0 if error
# ---------------------------------------------------------------------------

sub writeData {
	my ($self, $fh, $buf) = @_;

	my $s = $self->serialise($buf);

	syswrite($fh, $s);

	return 1;
}

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
