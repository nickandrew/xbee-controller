#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  XBee door lock monitoring & logging daemon
#
#  Usage: xbee-lock-monitor.pl [-d data_dir] [-h host:port]
#
#  -c control_file     YAML control file (default $HOME/etc/xbee-locks.yaml)
#  -d data_dir         Specify data directory for logging the temperature (default 'data')
#  -h host:port        Specify xbee daemon host and/or port (default 127.0.0.1:7862)

use strict;

use Date::Format qw(time2str);
use Getopt::Std qw(getopts);
use Sys::Syslog qw();
use YAML qw();

use XBee::Client qw();

use vars qw($opt_c $opt_d $opt_h);

$| = 1;
getopts('c:d:h:');

$opt_c ||= "$ENV{HOME}/etc/xbee-locks.yaml";
$opt_d ||= 'data';
$opt_h ||= '127.0.0.1:7862';

# Quick fudge default ipv6 address
if ($opt_h eq ':::7862') {
	$opt_h = '[::]:7862';
}

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

if (! -f $opt_c) {
	die "No file $opt_c";
}

my $event_dir = 'event.d';
my $made_dirs = { };
my $lock_config = YAML::LoadFile($opt_c);
my $lock_list = { };

foreach my $k (keys %$lock_config) {
	my $device = $lock_config->{$k}->{'device-args'}->{xbee_device};
	if ($device) {
		$lock_list->{$device} = $k;
	}
}

my $buffered_data = { };

Sys::Syslog::openlog('xbee-lock-monitor', "", "local0");

while (1) {
	eval {
		connectAndProcess();
	};

	if ($@) {
		my $err = $@;
		Sys::Syslog::openlog('xbee-lock-monitor', "", "local0");
		Sys::Syslog::syslog('err', "Daemon died: %s", $err);
		print "Sleeping\n";
		sleep(30);
	} else {
		print "Reconnecting\n";
		sleep(5);
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
			print "EOF on XBee::Client\n";
			last;
		}

		if ($xcl->isError()) {
			print "Error on XBee::Client\n";
			last;
		}

		my $packet = $xcl->receivePacket(60);

		next if (!defined $packet);

		processPacket($packet);
	}

	$xcl->close();
	sleep(5);
}

sub processPacket {
	my ($packet) = @_;

	if (!defined $packet || ! ref $packet) {
		Sys::Syslog::syslog('warning', "Illegal packet");
		return;
	}

	my $type = $packet->{type};
	my $payload = $packet->{payload};

	if (! $type || ! $payload) {
		Sys::Syslog::syslog('warning', "Packet missing type or payload");
		return;
	}

	if ($type eq 'receivePacket') {
		my $source = sprintf("%x:%x", $payload->{sender64_h}, $payload->{sender64_l});

		if (! $lock_list->{$source}) {
			# Ignore this; not a lock
			return;
		}

		# Process it.
		$buffered_data->{$source} .= $payload->{data};

		while ($buffered_data->{$source} =~ /^([^\n]*)\n(.*)/s) {
			my ($line, $rest) = ($1, $2);

			$line =~ s/\r//g;

			my $device_name = $lock_list->{$source};
			logLine($device_name, $line);

			runEvents($device_name, $line);

			$buffered_data->{$source} = $rest;
		}

		# Clear anything which is not outputting lines of text
		if (length($buffered_data->{$source}) >= 500) {
			$buffered_data->{$source} = '';
		}

		return;
	}
}

sub logLine {
	my ($source, $line) = @_;

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

	my $log_file = "$opt_d/$yyyy/$mm/$yyyy$mm$dd-$source.log";

	if (open(LF, ">>$log_file")) {
		print LF "$now $now_ts $source $line\n";
		close(LF);
	}
}

sub runEvents {
	my ($device_name, $line) = @_;

	if ($line =~ /^U (\S+) (.+)/) {
		$ENV{LOCK_ACTION} = 'U';
		$ENV{LOCK_CARD} = $1;
		$ENV{LOCK_NAME} = $2;
		runCommands('lock', $line);
		delete $ENV{LOCK_ACTION};
		delete $ENV{LOCK_CARD};
		delete $ENV{LOCK_NAME};
	}

	if ($line =~ /^L/) {
		# Don't need to do anything
	}
}

sub runCommands {
	my ($file_prefix, $message) = @_;

	if (! -d $event_dir) {
		# Cannot run anything
		return;
	}

	if (! opendir(DIR, $event_dir)) {
		warn "Unable to opendir $event_dir - $!";
		return;
	}

	my @files = sort(readdir DIR);

	foreach my $f (@files) {
		next if ($f =~ /^\./);

		next if ($f !~ /^$file_prefix/);

		my $path = "$event_dir/$f";

		my @buf = stat($path);
		next if (! -f _ || ! -r _ || ! -x _);

		my $rc = system($path, $message);

		if ($rc) {
			print "system($path, $message) rc is $rc\n";
		}
	}
}

