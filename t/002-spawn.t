#!perl
use strict;
use warnings;
use Test::More tests => 5;
use IO::Pty::Easy;

my $pty = new IO::Pty::Easy;
$pty->spawn("$^X -ple ''");
ok($pty->is_active, "spawning a subprocess");
ok(kill(0 => $pty->{pid}), "subprocess actually exists");
$pty->kill;
TODO: {
local $TODO = "kill() needs to block";
ok(!$pty->is_active, "killing a subprocess");
}
$pty->spawn("$^X -ple ''");
$pty->close;
TODO: {
local $TODO = "kill() needs to block";
ok(!$pty->is_active, "auto-killing a pty with close()");
}
ok(!defined($pty->{pty}), "closing a pty after a spawn");
