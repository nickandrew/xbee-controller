#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#   Send a command to an XBee in API mode
#
#   Usage: xbee-cmd.pl -h host:port xx xx xx ...

use strict;

use Getopt::Std qw(getopts);
use YAML qw();

use XBee::Client qw();

use vars qw($opt_h);

getopts('h:');

my $host = $opt_h || die "Need option -h host:port";
my $xcl = XBee::Client->new($host);

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
