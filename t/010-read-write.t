#!perl
use strict;
use warnings;
use Test::More tests => 2;
use IO::Pty::Easy;

my $pty = IO::Pty::Easy->new;

$pty->spawn("$^X -ple ''");
$pty->write("testing\n");
like($pty->read, qr/testing/, "basic read/write testing");
is($pty->read(0.1), undef, "read returns undef on timeout");
# if the perl script ends with a subprocess still running, the test will exit
# with the exit status of the signal that the subprocess dies with, so we have
# to kill the subprocess before exiting.
$pty->close;
