#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#   Send a command to an XBee in API mode
#
#   Usage: xbee-cmd.pl XX arg arg ...

use strict;

use Getopt::Std qw(getopts);

use Selector qw();
use XBee::Device qw();
use XBee::TTY qw();

use vars qw($opt_d);

getopts('d:');

my $device = XBee::TTY->new($opt_d);
my $controller = XBee::Device->new();
my $selector = Selector->new();

my $fh = $device->socket();

$selector->addSelect([ $fh, $controller] );

my $cmd = shift @ARGV;
if (! $cmd || $cmd !~ /^..$/) {
	die "Missing or incorrect command - need 2 chars";
}

my $args = undef;
foreach my $a (@ARGV) {
	my $c = pack('C', hex($a));
	$args .= $c;
}

$controller->writeATCommand($fh, $cmd, $args);
my $count = 0;

while ($count < 10) {
	my $timeout = $selector->pollServer(1);

	if ($timeout) {
		$count ++;
	}

	if ($controller->{'done'}) {
		print "Done\n";
		last;
	}
}

exit(0);
