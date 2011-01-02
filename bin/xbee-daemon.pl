#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#   Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#   Licensed under the terms of the GNU General Public License, Version 3
#
#  Distribute all messages received from a USB-connected XBee to TCP-connected clients.
#
#  Usage: xbee-daemon.pl [-d /dev/ttyUSBx] [-v] listen_addr ...
#
#  -d /dev/ttyUSBx     Connect to specified device
#  -v                  Verbose
#
#  listen_addr   A set of one or more listening addresses.
#                Format:  host:port
#                ipv4:    0.0.0.0:1681
#                ipv4:    127.0.0.1:1681
#                ipv6:    :::1681
#                ipv6:    [::]:1681
#
#  All I/O to/from the xbee is logged.

use strict;

use Getopt::Std qw(getopts);
use IO::Select qw();

use Controller::Daemon qw();
use Selector::TTY qw();
use Selector::SocketFactory qw();
use XBee::Device qw();

use vars qw($opt_d $opt_v);

$| = 1;
getopts('d:v');

$opt_d || die "Need option -d /dev/ttyUSBx";

$SIG{'INT'} = sub {
	print("SIGINT received, exiting\n");
	exit(4);
};

$SIG{'PIPE'} = sub {
	print("SIGPIPE received, exiting\n");
	exit(4);
};

my $tty_obj = Selector::TTY->new($opt_d);

my $daemon_obj = Controller::Daemon->new();

$daemon_obj->addServer($tty_obj);

foreach my $local_addr (@ARGV) {
	my $listener = Selector::SocketFactory->new(
		LocalAddr => $local_addr,
		Proto => "tcp",
		ReuseAddr => 1,
		Listen => 5,
	);

	if ($listener) {
		print("Listening on $local_addr\n") if ($opt_v);
		$daemon_obj->addListener($listener);
	}
}

$daemon_obj->eventLoop();
exit(0);
