#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Open a lock by sending a message to a Tullnet RFID Doorlock v3.
#
#  Usage: xbee-unlock.pl [-l lock-name]
#
#  -l lock-name        Specify which lock to unlock, by name

use strict;

use Getopt::Std qw(getopts);
use YAML qw();

use XBee::Client qw();
use XBee::API::Series2 qw();
use XBee::PointToPoint qw();

use vars qw($opt_l);

my $p2p;
my $buffered_input = '';
my $control_file = "$ENV{HOME}/etc/locks.yaml";

$| = 1;
getopts('l:');

$SIG{'INT'} = sub {
	print("SIGINT received, exiting\n");
	exit(4);
};

$SIG{'PIPE'} = sub {
	print("SIGPIPE received, exiting\n");
	exit(4);
};

if (! -f $control_file) {
	die "No file $control_file";
}

my $control = YAML::LoadFile($control_file);

my $name = $opt_l || $control->{default};
if (! $name) {
	die "Need to specify lock name or missing default lock name in $control_file";
}

my $lock_args = $control->{$name};

if (! $lock_args) {
	die "No such lock $name in $control_file";
}

connectAndProcess();

exit(0);

sub connectAndProcess {

	$p2p = XBee::PointToPoint->new( {
		xbee_device => $lock_args->{device_args}->{xbee_device},
		xbee_server => $lock_args->{device_args}->{xbee_server},
	} );

	my $buf;

	foreach my $try (1 .. 5) {
		$p2p->sendString('?');

		$buf = readLine(5);

		last if (defined $buf);

		sleep(2 * $try);
	}

	if (!defined $buf) {
		print "Cannot get device identity.\n";
		exit(5);
	}

	chomp($buf);

	if ($buf !~ /^?=Tullnet RFID Doorlock v(\d+)/) {
		print "Unexpected device identity: $buf\n";
		exit(6);
	}

	my $version = $1;
	if ($version < 3 || $version > 3) {
		print "Unsupported device version: $buf\n";
		exit(7);
	}

	$p2p->sendString('V');

	$buf = readLine(5);

	if (defined $buf) {
		chomp($buf);
		if ($buf =~ /^V (\d+) (\d+) (\d+) (\d+)/) {
			my ($a0_1, $a1_1, $a0_2, $a1_2) = ($1, $2, $3, $4);
			printf("Voltages at $name: %d %d\n", int(($a0_1 + $a0_2) / 2), int(($a1_1 + $a1_2) / 2));
		}
	}

	$p2p->sendString('U');

	# Wait up to 10 seconds for a subsequent 'L' message.
	my $end_time = time() + 10;

	while (1) {
		my $now = time();
		if ($now >= $end_time) {
			last;
		}

		my $timeout = $end_time - $now;

		my $buf = readLine($timeout);
		next if (!defined $buf);

		chomp($buf);
		if ($buf eq 'L') {
			print "Locked $name\n";
			last;
		}
	}
}

# ---------------------------------------------------------------------------
# Return 1 line of text from the device, with a timeout. If no data is
# available, return undef. The line ends with \n and any \r is removed.
# ---------------------------------------------------------------------------

sub readLine {
	my ($timeout) = @_;

	# Retrieve existing line from buffer
	if ($buffered_input =~ /^([^\n]*)\n(.*)/s) {
		my ($line, $rest) = ($1, $2);
		$buffered_input = $rest;
		$line =~ s/\r//g; # remove any \r
		return $line . "\n";
	}

	my $buf = $p2p->recvString(100, $timeout);

	if (defined $buf) {
		# Append to buffer and return first line, if any
		$buffered_input .= $buf;

		if ($buffered_input =~ /^([^\n]*)\n(.*)/s) {
			my ($line, $rest) = ($1, $2);
			$buffered_input = $rest;
			$line =~ s/\r//g; # remove any \r
			return $line . "\n";
		}
	}

	# No complet line was read within timeout
	return undef;
}
