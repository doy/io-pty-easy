#!perl
use strict;
use warnings;
use Test::More tests => 2;
use IO::Pty::Easy;

my $pty = new IO::Pty::Easy;
eval { $pty->spawn("missing_program_io_pty_easy") };
like($@, qr/Cannot exec\(missing_program_io_pty_easy\)/);
ok(!$pty->is_active, "pty isn't active if program doesn't exist");
