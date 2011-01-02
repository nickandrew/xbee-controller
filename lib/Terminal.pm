#!/usr/bin/perl -w
#   vim:sw=4:ts=4:
#
#  A terminal device

package Terminal;

use strict;

sub new {
	my ($class) = @_;

	my $self = {
		buf => undef,
		handlers => { },
	};
	bless $self, $class;

	return $self;
}

sub setHandler {
	my ($self, $name, $obj, $func) = @_;

	if (! $name) {
		die "setHandler: need name";
	}

	$self->{handlers}->{$name} = {
		obj => $obj,
		func => $func,
	};
}

sub runHandler {
	my ($self, $name, @args) = @_;

	if (!defined $name) {
		die "runHandler: need name";
	}

	my $hr = $self->{handlers}->{$name};

	if ($hr && $hr->{obj} && $hr->{func}) {
		my $obj = $hr->{obj};
		my $func = $hr->{func};

		if ($obj && $func) {
			$obj->$func(@args);
		}
	}
}

sub handleRead {
	my ($self, $selector, $socket) = @_;

	my $buf;

	my $n = sysread($socket, $buf, 100);
	if ($n == 0) {
		# EOF
		print STDERR "FIXME - read EOF\n";
		$selector->removeSelect($self);
		return 0;
	}

	print "Read text line: $buf\n";

	$self->{buf} .= $buf;

	my $i = index($self->{buf}, "\n");

	# Flush the buffer one line at a time
	while ($i > 0) {
		my $line = substr($self->{buf}, 0, $i);
		$self->{buf} = substr($self->{buf}, $i + 1);

		$self->runHandler('line', $line);
		$i = index($self->{buf}, "\n");
	}
}

1;
