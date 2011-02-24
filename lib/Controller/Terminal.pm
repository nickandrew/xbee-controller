#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#   A controller for a terminal function (i.e. a program which allows the
#   user to send text messages to XBees, and which displays the text messages
#   received from XBees).


package Controller::Terminal;

use strict;

use XBee::Device qw();
use Selector qw();
use Terminal qw();

sub new {
	my ($class, $xbee_device) = @_;

	my $selector = Selector->new();

	my $device = XBee::Device->new();
	my $tty_device = XBee::TTY->new('/dev/tty');
	my $terminal = Terminal->new();

	$selector->addSelect( [ $xbee_device->socket(), $device ] );
	$selector->addSelect( [ $tty_device->socket(), $terminal ] );

	my $self = {
		xbee_device => $xbee_device,
		terminal => $terminal,
		tty_device => $tty_device,
		device => $device,
		selector => $selector,
	};

	bless $self, $class;

	$terminal->setHandler('line', $self, 'terminalLine');

	return $self;
}

sub pollForever {
	my ($self) = @_;

	my $selector = $self->{selector};
	my $count = 0;

	while (1) {
		my $timeout = $selector->pollServer(10);

		if ($timeout) {
			$count ++;
		}
	}

	# NOTREACHED
}

sub terminalLine {
	my ($self, $line) = @_;

	my $fh = $self->{xbee_device}->socket();

	print "Read line from terminal: $line\n";
	if ($line =~ /^AT (..)/) {
		# Send AT command (no args yet)
		my $cmd = $1;
		print "Sending AT command: $cmd\n";
		$self->{device}->writeATCommand($fh, $cmd);
	}
	elsif ($line =~ /^AO (\d+)/) {
		# Send AO command (no args yet)
		my $arg = chr($1);
		print "Sending AO command\n";
		$self->{device}->writeATCommand($fh, 'AO', $arg);
	}
	elsif ($line =~ /^DEST (\S+) (\S+)/) {
		# Set the destination of the next packet
		$self->{destination}->{'64_h'} = hex($1);
		$self->{destination}->{'64_l'} = hex($2);
		print "Set destination to $1 $2\n";
	}
	elsif ($line =~ /^SEND (.+)/) {
		my $data = $1;
		my $d_h = $self->{destination}->{'64_h'};
		my $d_l = $self->{destination}->{'64_l'};
		if (! $d_h || ! $d_l) {
			print "No destination set\n";
		} else {
			my $packet = {
				dest64_h => $d_h,
				dest64_l => $d_l,
				dest16 => 0xfffe,
				radius => 0,
				options => 0,
				data => $data,
			};

			$self->{device}->transmitRequest($fh, $packet);
		}
	}
}

1;
