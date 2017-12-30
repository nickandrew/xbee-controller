#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  XBee air conditioner monitoring daemon
#
#  Usage: xbee-aircon-log.pl [-d data_dir] [-h host:port]
#
#  -d data_dir         Specify data directory for logging the data (default 'data')
#  -h host:port        Specify xbee daemon host and/or port (default 127.0.0.1:7862)
#  -i xbee_id          Specify source id (xxxxxxxx:xxxxxxxx)

use strict;

use Date::Format qw(time2str);
use Getopt::Std qw(getopts);
use JSON qw();
use Sys::Syslog qw();

use TullNet::XBee::Client qw();

use vars qw($opt_d $opt_h $opt_i);

$| = 1;
getopts('d:h:i:');

$opt_d ||= 'data';
$opt_h ||= '127.0.0.1:7862';
$opt_i ||= '13a200:40608a42';

if (! $opt_d) {
	die "Need option -d directory";
}

if (! -d $opt_d) {
	die "No directory: $opt_d";
}

if (! $opt_i) {
	die "Need option -i xbee_id";
}

if ($opt_i !~ /^([0-9a-f]+):([0-9a-f]+)$/) {
	die "Invalid option -i $opt_i - need hex:hex";
}

my ($h_h, $h_l) = ($1, $2);
my $source_h = hex($h_h);
my $source_l = hex($h_l);

$SIG{'INT'} = sub {
	print("SIGINT received, exiting\n");
	exit(4);
};

$SIG{'PIPE'} = sub {
	print("SIGPIPE received, exiting\n");
	exit(4);
};


my $buffered;
my $buffered_data;

# Keep a record of created directories
my $made_dirs = { };

# These are the packet contents we know
my @packets = ( );

Sys::Syslog::openlog('xbee-aircon-log', "", "local0");

while (1) {
	eval {
		connectAndProcess();
	};

	if ($@) {
		my $err = $@;
		Sys::Syslog::openlog('xbee-aircon-log', "", "local0");
		Sys::Syslog::syslog('err', "Daemon died: %s", $err);
		sleep(30);
	}
}

# NOTREACHED
exit(0);

# Create a client socket, connect to the server and process all XBee packets
# received by the server (from specific device).

sub connectAndProcess {

	my $xcl = TullNet::XBee::Client->new($opt_h);
	if (!defined $xcl) {
		die "Unable to create a client socket";
	}

	my $last_packet_time = time();

	while (1) {
		if ($xcl->isEOF()) {
			print "EOF on TullNet::XBee::Client\n";
			last;
		}

		if ($xcl->isError()) {
			print "Error on TullNet::XBee::Client\n";
			last;
		}

		my $now = time();
		if ($now > $last_packet_time + 600) {
			$xcl->close();
			print STDERR "No packet received for over 10 minutes - socket problem?\n";
			die "No packet received for over 10 minutes - socket problem?";
		}

		my $packet = $xcl->receivePacket(60);
		next if (!defined $packet);

		$last_packet_time = $now;

		processPacket($packet);
	}

	$xcl->close();
}

sub processPacket {
	my ($packet) = @_;

	my $type = $packet->type();
	my $payload = $packet->{payload};

	if (! $type || ! $payload) {
		Sys::Syslog::syslog('warning', "Frame missing type or payload");
		return;
	}

	if ($type ne 'receivePacket') {
		Sys::Syslog::syslog('info', "Ignoring non-receivePacket frame");
		return;
	}

	# Test source address
	if ($payload->{sender64_h} != $source_h) {
		return;
	}

	if ($payload->{sender64_l} != $source_l) {
		return;
	}

	# Process it.
	$buffered_data .= $payload->{data};

	while ($buffered_data =~ /^([^\n]+)\r?\n(.*)/s) {
		my ($line, $rest) = ($1, $2);

		if ($line =~ /^R([0-9A-F]+)/) {
			# It's an aircon log

			my $hexstring = $1;
			checkPacket($hexstring);
			logData($hexstring);
		}

		$buffered_data = $rest;
	}
}

sub logData {
	my ($line) = @_;

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

	my $log_file = "$opt_d/$yyyy/$mm/$yyyy$mm$dd-aircon.log";

	if (open(LF, ">>$log_file")) {
		print LF "$now $now_ts $line\n";
		close(LF);
	}
}

# Check that a packet is correct. If so, do further processing on it.

sub checkPacket {
	my ($line) = @_;

	if (length($line) < 16) {
		# Shortest possible line with 1 data byte
		return;
	}

	my $raw = pack('H*', $line);
	my @bytes = map { ord($_) } (split(//, $raw));

	print "Pkt: ", join(' ', map { sprintf("%02x", $_) } @bytes), "\n";

	if ($bytes[0] != 0x55 || $bytes[1] != 0xaa) {
		# Ignore this, it's not valid
		return;
	}

	my $address = $bytes[2];
	if ($address != 0 && $address != 0x80) {
		print "Error: ", $line, "\n";
		print "Saw unusual address $address\n";
		return;
	}

	my $id_1 = $bytes[3];
	my $id_2 = $bytes[4];
	my $payload_len = $bytes[5];

	if ($id_1 != 0 && $id_1 != $id_2) {
		print "Error: ", $line, "\n";
		print "Packet IDs mismatch: $id_1 vs $id_2\n";
		return;
	}

	if ($payload_len < 2 || $payload_len > 8) {
		print "Error: ", $line, "\n";
		print "Unusual payload_len: $payload_len\n";
	}

	my $checksum = 0;

	foreach my $i (2 .. $payload_len + 5) {
		$checksum += $bytes[$i];
	}

	if (($checksum & 0xff) != $bytes[$payload_len + 6]) {
		print "Error: ", $line, "\n";
		my $c = $bytes[$payload_len + 6];
		$checksum &= 0xff;
		print "Checksum mismatch: $checksum vs $c\n";
		return;
	}

	updatePacket(@bytes);
}

sub updatePacket {
	my (@bytes) = @_;

	my $packet_id = $bytes[4];

	if (! $packets[$packet_id]) {
		# Setup initial packet contents
		my $b = \@bytes;
		$packets[$packet_id] = $b;
		printPacket($b);
		return;
	}

	# Check the packet for changes
	my $curr = $packets[$packet_id];

	my $saved_length = scalar(@$curr);
	my $now_length = scalar(@bytes);

	if ($saved_length != $now_length) {
		print "Packet $packet_id length changed from $saved_length to $now_length\n";
	}

	# Check byte values, except the checksum
	my $changed = 0;
	foreach my $i (0 .. $saved_length - 2) {
		my $old = $curr->[$i];
		my $new = $bytes[$i];

		if ($old != $new) {
			printf("Packet %2d byte %d changed from %02x to %02x\n",
				$packet_id,
				$i,
				$old,
				$new,
			);
			$changed = 1;
		}
	}

	if ($changed) {
		printPacket(\@bytes);
	}

	my @new_contents = @bytes;
	$packets[$packet_id] = \@new_contents;
}

sub printPacket {
	my ($b) = @_;

	my $packet_id = $b->[4];

	printf("Packet %2d -- ", $packet_id);
	print join(' ', map { sprintf("%02x", $_) } (@$b)), "\n";
}
