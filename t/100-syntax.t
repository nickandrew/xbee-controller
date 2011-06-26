#!/usr/bin/perl -w
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3
#
#  Syntax-check all modules and scripts

use Test::More qw(no_plan);

checkDir('lib');
checkDir('bin');
checkDir('scripts');

exit(0);

sub checkDir {
	my ($dir) = @_;

	if (! -d $dir) {
		return;
	}

	if (! opendir(DIR, $dir)) {
		return;
	}

	my @files = sort(grep { ! /^\./ } (readdir DIR));
	closedir(DIR);

	foreach my $f (@files) {
		my $path = "$dir/$f";

		if (-f $path && $f =~ /\.(pl|pm|t)$/) {
			open(P, "perl -Mstrict -wc $path 2>&1 |");
			my $lines;
			while (<P>) {
				$lines .= $_;
			}
			if (! close(P)) {
				warn "Error closing pipe from perl syntax check $path";
			}
			my $rc = $?;

			if ($rc) {
				diag($lines);
				fail("$path failed - code $rc");
			} else {
				pass($path);
			}
		}
		elsif (-d $path) {
			checkDir($path);
		}
	}
}
