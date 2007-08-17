#!perl
use strict;
use warnings;
use Test::More tests => 2;
use IO::Pty::Easy;

my $pty = new IO::Pty::Easy;
my $script = "$^X -e '-t *STDIN && -t *STDOUT && print \"ok\";'";

my $outside_of_pty = `$script`;
unlike($outside_of_pty, qr/ok/, "running outside of PTY fails -t checks");

$pty->spawn("$script");
like($pty->read, qr/ok/, "runs subprocess in a PTY");
