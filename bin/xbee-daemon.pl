#!/usr/bin/perl
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Distribute all messages received from a USB-connected XBee to TCP-connected clients.
#
#  Usage: xbee-daemon.pl [-d /dev/ttyUSBx] [--debug] listen_addr ...
#
#  -d /dev/ttyUSBx     Connect to specified device
#  --debug             Enable per-packet logging (decoded packets)
#
#  listen_addr   A set of one or more listening addresses.
#                Format:  host:port
#                ipv4:    0.0.0.0:7862
#                ipv4:    127.0.0.1:7862
#                ipv6:    :::7862
#                ipv6:    [::]:7862
#
#  All I/O to/from the xbee is logged.

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use IO::Select qw();
use Sys::Syslog qw();

use Controller::Daemon qw();
use Selector::TTY qw();
use Selector::SocketFactory qw();
use TullNet::XBee::Device qw();

my $opt_d;
my $opt_debug;

$| = 1;
GetOptions(
	'debug' => \$opt_debug,
	'd=s' => \$opt_d,
);

$opt_d || die "Need option -d /dev/ttyUSBx";

Sys::Syslog::openlog('xbee-daemon', "", "local0");

$SIG{'INT'} = sub {
	Sys::Syslog::syslog('err', "Daemon exiting due to SIGINT");
	exit(4);
};

$SIG{'TERM'} = sub {
	Sys::Syslog::syslog('err', "Daemon exiting due to SIGTERM");
	exit(4);
};

$SIG{'PIPE'} = sub {
	Sys::Syslog::syslog('err', "Daemon exiting due to SIGPIPE");
	exit(4);
};

while (1) {
	eval {
		main();
	};

	if ($@) {
		my $err = $@;
		Sys::Syslog::syslog('err', "Daemon died: %s", $err);
		exit(8);
	}
}

# NOTREACHED
exit(0);

sub main {
	my $tty_obj = Selector::TTY->new($opt_d);

	my $daemon_obj = Controller::Daemon->new();

	$daemon_obj->addServer($tty_obj);

	if ($opt_debug) {
		$daemon_obj->debug($opt_debug);
	}

	foreach my $local_addr (@ARGV) {
		my $listener = Selector::SocketFactory->new(
			LocalAddr => $local_addr,
			Proto => "tcp",
			ReuseAddr => 1,
			Listen => 5,
		);

		if ($listener) {
			Sys::Syslog::syslog('info', "Listening on %s", $local_addr);
			$daemon_obj->addListener($listener);
		}
	}

	$daemon_obj->eventLoop();

	Sys::Syslog::syslog('info', "Controller eventLoop() returned, exiting");
	exit(0);
}
