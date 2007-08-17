#!perl
use strict;
use warnings;
use Test::More tests => 1;
use IO::Pty::Easy;

my $pty = new IO::Pty::Easy;
$pty->close;
ok(!defined($pty->{pty}), "closing a pty before a spawn");
