#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Implement a terminal program to talk to XBees
#
#  Options:
#    -h host:port        XBee server host:port

use strict;

use Getopt::Std qw(getopts);

use Selector::SocketFactory qw();
use Controller::Terminal2 qw();

use vars qw($opt_h);

getopts('h:');

$opt_h ||= '127.0.0.1:7862';

my $client_socket = Selector::SocketFactory->new(
	PeerAddr => $opt_h,
	Proto => 'tcp',
);

if (!defined $client_socket) {
	die "Unable to connect to $opt_h";
}

my $controller = Controller::Terminal2->new($client_socket);
$controller->pollForever();

exit(0);
