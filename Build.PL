#!/usr/bin/perl

use Module::Build;
my $build = Module::Build->new(
	dist_abstract => 'XBee networking',
	dist_author   => 'Nick Andrew <nick@nick-andrew.net>',
	dist_version  => '0.001',
	installdirs   => 'vendor',
	module_name   => 'XBee',
	requires      => {
		AnyEvent      => 0,
		'IO::Select'  => 0,
		JSON          => 0,
		'Time::HiRes' => 0,
		YAML          => 0,
	},
);

$build->create_build_script;
