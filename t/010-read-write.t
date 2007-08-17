#!perl
use strict;
use warnings;
use Test::More tests => 1;
use IO::Pty::Easy;

my $pty = new IO::Pty::Easy;

$pty->spawn("$^X -ple ''");
$pty->write("testing\n");
like($pty->read, qr/testing/, "basic read/write testing");
# if the perl script ends with a subprocess still running, the test will exit
# with the exit status of the signal that the subprocess dies with, so we have to wait for the subprocess to finish before exiting.
$pty->kill;
1 while $pty->is_active;
