#!/usr/bin/perl
#   vim:sw=4:ts=4:
#
#  Log one temperature record manually
#
#  Usage: manual-log-temp.pl [-i influxdb_url] [-d device] [-t temp]
#
#  -i influxdb_url     Specify optional InfluxDB URL for logging the data

use strict;
use warnings;

use Data::Dumper qw(Dumper);
use Date::Format qw(time2str);
use Getopt::Long qw(GetOptions);
use Sys::Syslog qw();

use TullNet::XBee::Client qw();

my $opt_d;
my $opt_i;
my $opt_t;

$| = 1;
GetOptions(
	'd=s' => \$opt_d,
	'i=s' => \$opt_i,
	't=f' => \$opt_t,
);

if (! $opt_d) {
	die "Need option -d device";
}

if (! $opt_i) {
	die "Need option -i influxdb_url";
}

if ($opt_i && $opt_i !~ /^https?:\/\//) {
	die "Invalid option -i $opt_i";
}

if (! $opt_t) {
	die "Need option -t temperature";
}

my $ua;

if ($opt_i) {
	require Mojo::UserAgent;
	$ua = Mojo::UserAgent->new;

	# Ensure that precision is supplied
	if ($opt_i !~ /precision=s/) {
		$opt_i .= "&precision=s";
	}
}

my $now = time();
logTemperatureToInfluxDB($now, $opt_d, $opt_t);

exit(0);

sub logTemperatureToInfluxDB {
	my ($now, $device, $temp) = @_;

	if ($ua) {
		my $line = sprintf("temperature,device=%s temp=%f %d\n",
			$device,
			$temp,
			$now,
		);

		my $tx = $ua->post($opt_i, { Accept => '*/*' }, $line);

		my $res = $tx->success;
		if (!$res) {
			my $err = $tx->error;
			if ($err->{code}) {
				printf STDERR ("Post %s failed: %d %s\n", $opt_i, $err->{code}, $err->{message});
			} else {
				printf STDERR ("Connection %s failed: %s\n", $opt_i, $err->{message});
			}
		}
		else {
			print $line;
			printf ("Accepted, code %d\n", $res->code);
		}
	}
}
