#!perl
use strict;
use warnings;
use Test::More tests => 2;
use IO::Pty::Easy;

my $pty = new IO::Pty::Easy;
my $script = << 'EOF';
$| = 1;
if (-t *STDIN && -t *STDOUT) { print "ok" }
else { print "failed" }
EOF

my $outside_of_pty = `$^X -e '$script'`;
unlike($outside_of_pty, qr/ok/, "running outside of pty fails -t checks");

# we need to keep the script alive until we can read the output from it
$script .= "sleep 1 while 1;";
$pty->spawn("$^X -e '$script'");
like($pty->read, qr/ok/, "runs subprocess in a pty");
$pty->close;
