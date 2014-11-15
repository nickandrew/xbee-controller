# XBee/ZigBee daemon

xbee-controller is a daemon to control a network of XBee/ZigBee radio devices
through TCP/IP. The binary protocol is decoded into JSON messages.

# Synopsis

    xbee-daemon.pl [-d /dev/ttyUSBx] [-v] listen_addr ...

    -d /dev/ttyUSBx      Connect to specified device
	-v                   Verbose

	listen_addr:         A set of one or more listening host:port pairs.
	ipv4:                0.0.0.0:7862
	ipv4:                127.0.0.1:7862
	ipv6:                :::7862
	ipv6:                [::]:7862

The daemon opens the specified device (/dev/ttyUSBx) which is expected to
be an XBee radio modem such as these:

	http://littlebirdelectronics.com.au/products/xbee-2mw-wire-antenna-series-2-zb
	http://www.digi.com/products/wireless-wired-embedded-solutions/zigbee-rf-modules/point-multipoint-rfmodules/xbee-series1-module#overview

with a USB interface, configured as a Coordinator and
using the binary (API) protocol as opposed to the text-based AT protocol.

The daemon will listen on one or more specified host/port pairs. Any packets
received on the XBee network will be decoded and transmitted in JSON format
to all connected clients.

A connected client can send a JSON message to the server, and the server will
transmit that packet out over the local XBee network.

# JSON message format

The JSON message for a packet received over the XBee network looks like this:

```json
{"payload":{"data":"TMP1 T 28.00000269B9E9 01DE\r\n","options":1,"sender16":63874,"sender64_h":1286656,"sender64_l":1081049161,"type":144},"time_s":1416047469,"time_u":269406,"type":"receivePacket"}
```

Let's go through the data structure item by item.

	"type": "receivePacket",         This message type. Others include: ATResponse, modemStatus, nodeIdentificationIndicator, ...
	"time_s": 1416047469,            Time the message was received in seconds
	"time_u": 269406,                Time the message was received, microseconds portion
	"payload": {                     The received message's contents

		"data": "...",               The received data frame
		"options": 1,                XBee packet options
		"sender16": 63874,           16-bit sender address (in decimal)
		"sender64_h": 1286656,       High-order 32 bits of the 64-bit sender address (in decimal),
		"sender64_l": 1081049161,    Low-order 32 bits of the 64-bit sender address (in decimal),
		"type": 144                  Frame type 0x90, "ZigBee Receive Packet"
	}

## Sending a packet over the XBee network

```json
{"payload":{"data":"?\n","dest16":65534,"dest64_h":1286656,"dest64_l":1080068162,"frame_id":253,"options":0,"radius":0},"time_s":1416049321,"time_u":702500,"type":"transmitRequest"}
```

Breaking down the data structure again:

	"type": "transmitRequest",       Request to transmit a frame
	"time_s": 1416049321,            Seconds, as above (supplied by daemon)
	"time_u": 702500,                Microseconds, as above (supplied by daemon)
	"payload": {                     The frame to be transmitted
		"data": "...",                   Data portion of the frame
		"dest16": 65534,                 0xfffe means we don't know the short 16-bit destination device address
		"dest64_h": 1286656,             0x0013a200 the high-order 32 bits of the destination address
		"dest64_l": 1080068162,          0x40608842 the low-order 32 bits of the destination address
		"frame_id: 253,                  Frame sequence number (increment per frame sent)
		"options": 0,                    Transmit frame options
		"radius:" 0                      How many hops are permitted
	}

A client sending a "transmitRequest" packet can expect a "transmitStatus" response
with the `delivery_status` and `discovery_status` of the request. If the recipient node
could be found then `remote_address` is provided, to be used as the `dest16` in
future transmissions.

# Specifications

The ZigBee protocol is defined by Digi International Inc. There have been several variants
of the XBee/ZigBee protocol implemented.

The documentation homepage is http://www.digi.com/products/wireless-wired-embedded-solutions/zigbee-rf-modules/point-multipoint-rfmodules/xbee-series1-module#docs

Where specification differences exist, this library implements the protocol in document
90000976_G dated 11/15/2010.

The current specification looks like http://ftp1.digi.com/support/documentation/90000982_R.pdf

# Writing a client

See perldoc for module XBee::Client for this. The synopsis is:

```perl
  $xcl = XBee::Client->new($server_address);

  $packet = $xcl->receivePacket($timeout);

  if ($packet && $packet->isData()) {
    my $contents = $packet->data();
  }

Or

  $packet = $xcl->readPacket();

  if (! $packet) {
    $data_pending = $xcl->poll($timeout);

    if ($data_pending) {
      $xcl->handleRead($xcl->socket());
      $packet = $xcl->readPacket();
    }
  }
```
