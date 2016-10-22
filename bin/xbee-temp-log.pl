#!/usr/bin/perl
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  XBee temperature logging daemon
#
#  Usage: xbee-temp-log.pl [-d data_dir] [-h host:port] [-i influxdb_url]
#
#  -d data_dir         Specify data directory for logging the temperature (default 'data')
#  -h host:port        Specify xbee daemon host and/or port (default 127.0.0.1:7862)
#  -i influxdb_url     Specify optional InfluxDB URL for logging the data

use strict;
use warnings;

use Date::Format qw(time2str);
use Getopt::Long qw(GetOptions);
use Sys::Syslog qw();

use XBee::Client qw();

my $opt_d = 'data';
my $opt_h = '127.0.0.1:7862';
my $opt_i;

$| = 1;
GetOptions(
	'd=s' => \$opt_d,
	'h=s' => \$opt_h,
	'i=s' => \$opt_i,
);

if (! $opt_d) {
	die "Need option -d directory";
}

if (! -d $opt_d) {
	die "No directory: $opt_d";
}

if ($opt_i && $opt_i !~ /^https?:\/\//) {
	die "Invalid option -i $opt_i";
}

my $ua;

if ($opt_i) {
	require Mojo::UserAgent;
	$ua = Mojo::UserAgent->new;

	# Ensure that precision is supplied
	if ($opt_i !~ /precision=s/) {
		$opt_i .= "&precision=s";
	}
}

$SIG{'INT'} = sub {
	Sys::Syslog::syslog('err', "Daemon exiting due to SIGINT");
	exit(4);
};

$SIG{'TERM'} = sub {
	Sys::Syslog::syslog('err', "Daemon exiting due to SIGTERM");
	print("SIGTERM received, exiting\n");
	exit(4);
};

$SIG{'PIPE'} = sub {
	Sys::Syslog::syslog('err', "Daemon exiting due to SIGPIPE");
	exit(4);
};

my $buffered_data = { };

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
		Sys::Syslog::syslog('err', "Daemon died: %s", $err);
		sleep(30);
	}
}

# NOTREACHED
exit(0);

# Create a client socket, connect to the server and process all XBee packets
# received by the server (from all devices).

sub connectAndProcess {

	my $xcl = XBee::Client->new($opt_h);

	if (!defined $xcl) {
		die "Unable to create a client socket";
	}

	Sys::Syslog::syslog('info', "Connected to $opt_h");

	while (1) {
		if ($xcl->isEOF()) {
			Sys::Syslog::syslog('info', "EOF on client socket");
			last;
		}

		if ($xcl->isError()) {
			Sys::Syslog::syslog('info', "Error on client socket");
			last;
		}

		my $packet = $xcl->receivePacket(60);

		next if (!defined $packet);

		processPacket($packet);
	}

	# Error or EOF, so wait a bit
	sleep(5);
}

sub processPacket {
	my ($frame) = @_;

	if (!defined $frame || ! ref $frame) {
		Sys::Syslog::syslog('warning', "Illegal frame");
		return;
	}

	my $type = $frame->{type};
	my $payload = $frame->{payload};

	if (! $type || ! $payload) {
		Sys::Syslog::syslog('warning', "Frame missing type or payload");
		return;
	}

	if ($type eq 'receivePacket') {
		my $source = "$payload->{sender64_h}/$payload->{sender64_l}";

		# Process it.
		$buffered_data->{$source} .= $payload->{data};

		while ($buffered_data->{$source} =~ /^([^\n]*)\r?\n(.*)/s) {
			my ($line, $rest) = ($1, $2);

			if ($line =~ /^T=(\S+) D=(\S+) Temp (\S+)/) {
				# It's a temperature log

				my ($time, $device, $temp) = ($1, $2, $3);
				logTemperature($time, $device, $temp);
			}
			elsif ($line =~ /^TMP1 T (\S+) (\S+)/) {
				# New style temp log from Tullnet Tiny Temp Monitor V1
				my ($device, $hex_temp) = ($1, $2);

				my $tempx16 = hex($hex_temp);
				if ($tempx16 >= 0x8000) {
					# Temp is negative, 2s complement
					$tempx16 -= 0x10000;
				}

				my $temp = $tempx16 / 16;

				if ($hex_temp ne '0550') {
					logTemperature("N/A", $device, $temp);
				}
			}

			$buffered_data->{$source} = $rest;
		}

		# Clear non-thermometer sources which do not output lines of text
		if (length($buffered_data->{$source}) >= 500) {
			$buffered_data->{$source} = '';
		}

		return;
	}
}

sub logTemperature {
	my ($time, $device, $temp) = @_;

	# Ensure a consistent timestamp for all logging
	my $now = time();
	logTemperatureToFile($now, $time, $device, $temp);
	logTemperatureToInfluxDB($now, $device, $temp);
}

sub logTemperatureToFile {
	my ($now, $time, $device, $temp) = @_;

	my $one_file = "$now_dir/$device";
	if (open(OF, ">$one_file")) {
		print OF "$time $device $temp\n";
		close(OF);
	}

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

sub logTemperatureToInfluxDB {
	my ($now, $device, $temp) = @_;

	if ($ua) {
		my $line = sprintf("temperature,device=%s temp=%f %d\n",
			$device,
			$temp,
			$now,
		);

		my $tx = $ua->post($opt_i, { Accept => '*/*' }, $line);
		my $res = $tx->success;
		if (!$res) {
			my $err = $tx->error;
			if ($err->{code}) {
				printf STDERR ("Post %s failed: %d %s\n", $opt_i, $err->{code}, $err->{message});
			} else {
				printf STDERR ("Connection %s failed: %s\n", $opt_i, $err->{message});
			}
		}
	}
}
