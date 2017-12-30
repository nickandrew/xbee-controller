#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010-2011, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Send a frame to an XBee in API mode.
#  This can be used to send any type of API frame; the entire contents of the frame
#  must be supplied in hex on the command line.
#
#  Usage: xbee-cmd.pl -h host:port xx xx xx ...
#
#  Example: Send an AT 'NI' command:
#     xbee-cmd.pl -h host:port 08 11 4e 49
#  Example: Read the firmware version:
#     xbee-cmd.pl -h host:port 08 11 56 52

use strict;

use Getopt::Std qw(getopts);
use YAML qw();

use TullNet::XBee::Client qw();

use vars qw($opt_h);

getopts('h:');

my $host = $opt_h || die "Need option -h host:port";
my $xcl = TullNet::XBee::Client->new($host);

# Convert all hex arguments to characters

my $args = undef;
foreach my $a (@ARGV) {
	my $c = pack('C', hex($a));
	$args .= $c;
}

# This packet type allows any API command to be sent.

my $packet = {
	type => 'APICommand',
	data => $args,
};

$xcl->sendData($packet);
my $count = 0;

while ($count < 10) {
	my $packet = $xcl->receivePacket(4);

	if (! $packet) {
		$count ++;
		next;
	}

	my $type = $packet->type();

	print '-=' x 32, "\n";
	print "Received packet of type: $type\n";
	print '-=' x 32, "\n\n";
	print YAML::Dump($packet);
	print "\n\n";
}

exit(0);
