#!/usr/bin/perl -w
#
#  TTY access library

package Selector::TTY;

use strict;

use IO::File qw(O_RDWR);
use POSIX qw();

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

	setupDevice($fh);

	$self->{fh} = $fh;
	$self->{fd} = $fh->fileno();

	return $self;
}

sub socket {
	my ($self) = @_;

	return $self->{fh};
}

# ---------------------------------------------------------------------------
# Setup a TTY device, set 9600 bps etc
# ---------------------------------------------------------------------------

sub setupDevice {
	my ($dev) = @_;

	my $fd = $dev->fileno();

	my $termios = POSIX::Termios->new();
	$termios->getattr($fd);
	my $c_cflag = $termios->getcflag();
	my $c_lflag = $termios->getlflag();
	my $c_oflag = $termios->getoflag();

	$termios->setispeed( &POSIX::B9600 );
	$termios->setospeed( &POSIX::B9600 );
	my $l_off = ( &POSIX::ECHO | &POSIX::ECHONL | &POSIX::ICANON | &POSIX::ISIG | &POSIX::IEXTEN );
	my $o_off = ( &POSIX::OPOST );
	$termios->setlflag( $c_lflag & ~$l_off );
	$termios->setoflag( $c_oflag & ~$o_off );
}

1;
