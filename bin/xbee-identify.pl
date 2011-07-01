#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Find all XBee nodes in the network and identify them by sending a '?' command
#
#  Options:
#    -h host:port        XBee server host:port

use strict;

use Getopt::Std qw(getopts);
use Data::Dumper qw(Dumper);
use YAML qw();

use XBee::Client qw();
use XBee::Network qw();
use XBee::AT::ZB qw();

use vars qw($opt_h);

getopts('h:');

$opt_h ||= '127.0.0.1:7862';

my $xcl = XBee::Client->new($opt_h);

if (!defined $xcl) {
	die "Unable to connect to xbee server";
}

my $network = XBee::Network->new(
	XBee::AT::ZB->new(),
	$xcl);

print "Finding network nodes\n";

my @nodes = $network->listNodes();

my $howmany = scalar(@nodes);

if ($howmany == 1) {
	print "Found 1 node.\n";
} else {
	printf("Found %d nodes.\n", $howmany);
}

print "Sending identity requests\n";

my $need = { };
my $count = 0;

foreach my $node (@nodes) {
	$node->sendString('?');
	my $address = $node->getAddress();
	$need->{$address} = {
		identity => '',
		node_id => $node->getNodeID(),
	};
	$count ++;
}

print "Waiting for responses\n";

my $now = time();
my $end_time = $now + 20;

while ($count && $now < $end_time) {
	my $timeout = $end_time - $now;
	$network->receive($timeout);

	foreach my $node (@nodes) {
		my $address = $node->getAddress();
		my $line = $node->getLine();
		if ($line) {
			chomp($line);
			if ($line =~ /^\?=(.+)/) {
				my $identity = $1;

				if (! $need->{$address}->{identity}) {
					# This is a new piece of info
					$count --;
				}

				$need->{$address}->{identity} = $identity;
			}
		}
	}

	$now = time();
}

# Now report all identities
printf "Nodes found:\n";

foreach my $address (sort (keys %$need)) {
	my $identity = $need->{$address}->{identity};
	my $node_id = $need->{$address}->{node_id};

	printf("%-20s : %-20s : %s\n", $address, $node_id, $identity);
}

exit(0);
