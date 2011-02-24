#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Loop, listening for data from XBee devices

use strict;

use Getopt::Std qw(getopts);
use YAML qw();

use Selector qw();
use XBee::Device qw();
use XBee::TTY qw();

use vars qw($opt_d $opt_f);

getopts('d:f:');

my $options = { };

if ($opt_f && -f $opt_f) {
	$options = YAML::LoadFile($opt_f);
}

my $device = XBee::TTY->new($opt_d);
my $controller = XBee::Device->new();
my $selector = Selector->new();

my $fh = $device->socket();

$selector->addSelect([ $fh, $controller] );

$controller->writeATCommand($fh, 'NJ');
my $count = 1;

while (1) {
	my $timeout = $selector->pollServer(10);

	if ($timeout) {
		$count ++;
	}
}

# NOTREACHED
exit(0);
