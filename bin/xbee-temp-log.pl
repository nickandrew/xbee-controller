#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#   Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#   Licensed under the terms of the GNU General Public License, Version 3
#
#   XBee temperature logging daemon
#
#  Usage: xbee-temp-log.pl [-d data_dir] [-h host:port]
#
#  -d data_dir         Specify data directory for logging the temperature (default 'data')
#  -h host:port        Specify xbee daemon host and/or port (default 127.0.0.1:7862)

use strict;

use Date::Format qw(time2str);
use Getopt::Std qw(getopts);
use JSON qw();
use Sys::Syslog qw();

use Selector::SocketFactory qw();

use vars qw($opt_d $opt_h);

$| = 1;
getopts('d:h:');

$opt_d ||= 'data';
$opt_h ||= '127.0.0.1:7862';

if (! $opt_d) {
	die "Need option -d directory";
}

if (! -d $opt_d) {
	die "No directory: $opt_d";
}

$SIG{'INT'} = sub {
	print("SIGINT received, exiting\n");
	exit(4);
};

$SIG{'PIPE'} = sub {
	print("SIGPIPE received, exiting\n");
	exit(4);
};

my $json = JSON->new()->utf8();

my $buffered;
my $buffered_data;

# Make directory for latest temperature from all devices
my $now_dir = "$opt_d/now";
mkdir($now_dir, 0755);
my $made_dirs = { };

Sys::Syslog::openlog('xbee-temp-log', "", "local0");

while (1) {
	eval {
		connectAndProcess();
	};

	if ($@) {
		my $err = $@;
		Sys::Syslog::openlog('xbee-temp-log', "", "local0");
		Sys::Syslog::syslog('error', "Daemon died: %s", $err);
		sleep(30);
	}
}

# NOTREACHED
exit(0);

# Create a client socket, connect to the server and process all XBee packets
# received by the server (from all devices).

sub connectAndProcess {


	my $socket = Selector::SocketFactory->new(
		PeerAddr => $opt_h,
		Proto => 'tcp',
	);

	Sys::Syslog::syslog('info', "Connected to $opt_h");

	if (!defined $socket) {
		die "Unable to create a client socket";
	}

	while (1) {
		my $buffer;

		my $n = sysread($socket, $buffer, 256);

		if (!defined $n) {
			die "Undef return from sysread";
		}

		if ($n == 0) {
			die "EOF on client socket";
		}

		if ($n < 0) {
			die "Error on client socket";
		}

		$buffered .= $buffer;

		while ($buffered =~ /^(.+)\r?\n(.*)/s) {
			my ($line, $rest) = ($1, $2);

			$buffered = $rest;

			processLine($line);
		}
	}

	# NOTREACHED
}

sub processLine {
	my ($line) = @_;

	my $frame = $json->decode($line);

	if (!defined $frame || ! ref $frame) {
		Sys::Syslog::syslog('warning', "Illegal JSON frame in %s", $line);
		return;
	}

	my $type = $frame->{type};
	my $payload = $frame->{payload};

	if (! $type || ! $payload) {
		Sys::Syslog::syslog('warning', "Frame missing type or payload in %s", $line);
		return;
	}

	if ($type ne 'receivePacket') {
		Sys::Syslog::syslog('info', "Ignoring non-receivePacket frame in %s", $line);
		return;
	}

	# Process it.
	$buffered_data .= $payload->{data};

	while ($buffered_data =~ /^([^\n]+)\r?\n(.*)/s) {
		my ($line, $rest) = ($1, $2);

		if ($line =~ /^T=(\S+) D=(\S+) Temp (\S+)/) {
			# It's a temperature log

			my ($time, $device, $temp) = ($1, $2, $3);
			logTemperature($time, $device, $temp);
		}

		$buffered_data = $rest;
	}
}

sub logTemperature {
	my ($time, $device, $temp) = @_;

	my $one_file = "$now_dir/$device";
	if (open(OF, ">$one_file")) {
		print OF "$time $device $temp\n";
		close(OF);
	}

	my $now = time();
	my $yyyy = time2str('%Y', $now);
	my $mm = time2str('%m', $now);
	my $dd = time2str('%d', $now);
	my $now_ts = time2str('%Y-%m-%d %T', $now);

	if (! $made_dirs->{"$yyyy$mm"}) {
		mkdir("$opt_d/$yyyy", 0755);
		mkdir("$opt_d/$yyyy/$mm", 0755);
		$made_dirs->{"$yyyy$mm"} = 1;
	}

	my $log_file = "$opt_d/$yyyy/$mm/$yyyy$mm$dd-$device.log";

	if (open(LF, ">>$log_file")) {
		print LF "$now $now_ts $device $temp\n";
		close(LF);
	}
}
