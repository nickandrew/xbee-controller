#!/bin/bash
#
#  Copyright (C) 2010, Nick Andrew <nick@nick-andrew.net>
#  Licensed under the terms of the GNU General Public License, Version 3

DEV=$1
BASE_DIR=$HOME/GIT/Priv/Src/XBee/nick-xbee-controller
export PERLLIB=./lib

echo "Starting XBee daemon"

if [ ! -d $BASE_DIR ] ; then
	echo "No dir $BASE_DIR"
	exit 8
fi

if [ ! -c $DEV ] ; then
	echo "No dev $DEV"
	exit 8
fi

cd $BASE_DIR

while true ; do
	stty 9600 raw -echo < $DEV

	bin/xbee-daemon.pl -d $DEV "[::]:7862"
	rc=$?
	echo rc $rc from bin/xbee-daemon.pl
	if [ $rc != 0 ] ; then
		~/bin/send-jabber.pl -m "xbee-daemon.pl exited code $rc"
	fi

	sleep 30
done
