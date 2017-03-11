#!/usr/bin/perl -w
#  vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Modify an XBee Node.
#  At present this command can only set the Node Identity variable.
#
#  Usage:
#        xbee-node.pl [-h host:port] [-n xxx:xxx] node_identity 'name'
#
#  Options:
#    -h host:port        XBee server host:port

use strict;

use Getopt::Std qw(getopts);

use TullNet::XBee::Client qw();
use TullNet::XBee::Network qw();
use TullNet::XBee::AT::ZB qw();

use vars qw($opt_h $opt_n);

getopts('h:n:');

$opt_h ||= '127.0.0.1:7862';

$opt_n || die "Need option -n xxx:xxx";

my $xcl = TullNet::XBee::Client->new($opt_h);

if (!defined $xcl) {
	die "Unable to connect to xbee server";
}

my $network = TullNet::XBee::Network->new(
	TullNet::XBee::AT::ZB->new(),
	$xcl);

my $node = TullNet::XBee::Node->new($opt_n, $network);
my $updated = 0;

while (@ARGV) {
	my $command = shift @ARGV;

	if ($command eq 'node_identity') {
		my $arg = shift @ARGV;
		if ($arg) {
			$node->setNodeID($arg, 1);
			$updated = 1;
		}
	}
	else {
		print "Unknown command: $command\n";
	}
}

if ($updated) {
	$node->saveSettings();
}

exit(0);
