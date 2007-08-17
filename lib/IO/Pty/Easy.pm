package IO::Pty::Easy;
use warnings;
use strict;
use IO::Pty;
use Carp;

# Intro documentation {{{

=head1 NAME

IO::Pty::Easy - Easy interface to IO::Pty

=head1 VERSION

Version 0.01 released 08/17/2007

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use IO::Pty::Easy;

    my $pty = IO::Pty::Easy->new;
    $pty->spawn("nethack");

    while (1) {
        my $input = # read a key here...
        $input = 'Elbereth' if $input eq "\ce";
        my $chars = $pty->write($input, 0);
        last if defined($chars) && $chars == 0;
        my $output = $pty->read(0);
        last if defined($output) && $output eq '';
        $output =~ s/Elbereth/\e[35mElbereth\e[m/;
        print $output;
    }

    $pty->close;

=head1 DESCRIPTION

C<IO::Pty::Easy> provides an interface to L<IO::Pty> which hides most of the ugly details of handling ptys, wrapping them instead in simple spawn/read/write commands.

C<IO::Pty::Easy> uses L<IO::Pty> internally, so it inherits all of the portability restrictions from that module.

=cut

# }}}

=head1 CONSTRUCTOR

=cut

# new() {{{

=head2 new()

The C<new> constructor initializes the pty and returns a new C<IO::Pty::Easy> object. The constructor recognizes these parameters:

=over 4

=item handle_pty_size

A boolean option which determines whether or not changes in the size of the user's terminal should be propageted to the pty object. Defaults to true.

=item def_max_read_chars

The maximum number of characters returned by a C<read()> call. This can be overridden in the C<read()> argument list. Defaults to 8192.

=back

=cut

sub new {
    my $class = shift;
    my $self = {
        # options
        handle_pty_size => 1,
        def_max_read_chars => 8192,
        @_,

        # state
        pty => undef,
        pid => undef,
    };

    bless $self, $class;

    $self->{pty} = new IO::Pty;

    return $self;
}
# }}}

=head1 METHODS

=cut

# spawn() {{{

=head2 spawn()

Fork a new subprocess, with stdin/stdout/stderr tied to the pty.

The argument list is passed directly to C<exec()>.

Returns true on success, false on failure.

=cut

sub spawn {
    my $self = shift;
    my $slave = $self->{pty}->slave;

    # set up a pipe to use for keeping track of the child process during exec
    my ($readp, $writep);
    unless (pipe($readp, $writep)) {
        carp "Failed to create a pipe";
        return;
    }
    $writep->autoflush(1);

    # fork a child process
    # if the exec fails, signal the parent by sending the errno across the pipe
    # if the exec succeeds, perl will close the pipe, and the sysread will
    # return due to EOF
    $self->{pid} = fork;
    unless ($self->{pid}) {
        close $readp;
        $self->{pty}->make_slave_controlling_terminal;
        close $self->{pty};
        $slave->clone_winsize_from(\*STDIN) if $self->{handle_pty_size};
        $slave->set_raw;
        # reopen the standard file descriptors in the child to point to the
        # pty rather than wherever they have been pointing during the script's
        # execution
        open(STDIN,  "<&" . $slave->fileno)
            or carp "Couldn't reopen STDIN for reading";
        open(STDOUT, ">&" . $slave->fileno)
            or carp "Couldn't reopen STDOUT for writing";
        open(STDERR, ">&" . $slave->fileno)
            or carp "Couldn't reopen STDERR for writing";
        close $slave;
        { exec(@_) };
        print $writep $! + 0;
        carp "Cannot exec(@_): $!";
        exit 1;
    }

    close $writep;
    $self->{pty}->close_slave;
    $self->{pty}->set_raw;
    # this sysread will block until either we get an EOF from the other end of
    # the pipe being closed due to the exec, or until the child process sends
    # us the errno of the exec call after it fails
    my $errno;
    my $read_bytes = sysread($readp, $errno, 256);
    unless (defined $read_bytes) {
        kill TERM => $self->{pid};
        close $readp;
        croak "Cannot sync with child: $!";
    }
    close $readp;
    if ($read_bytes > 0) {
        $errno = $errno + 0;
        croak "Cannot exec(@_): $errno";
    }

    my $pid = $self->{pid};
    my $winch;
    $winch = sub {
        $self->{pty}->slave->clone_winsize_from(\*STDIN);
        kill WINCH => $self->{pid} if $self->is_active;
        $SIG{WINCH} = $winch;
    };
    $SIG{WINCH} = $winch if $self->{handle_pty_size};
    $SIG{CHLD} = sub { $self->{pid} = undef; wait };
}
# }}}

# read() {{{

=head2 read()

Read data from the process running on the pty.

C<read()> takes two optional arguments: the first is the number of seconds (possibly fractional) to block for data (defaults to blocking forever, 0 means completely non-blocking), and the second is the maximum number of bytes to read (defaults to the value of C<def_max_read_chars>, usually 8192). The requirement for a maximum returned string length is a limitation imposed by the use of C<sysread()>, which we use internally.

Returns C<undef> on timeout, the empty string on EOF (including if no subprocess is currently running on the pty), or a string of at least one character on success (this is consistent with C<sysread()> and L<Term::ReadKey>).

=cut

sub read {
    my $self = shift;
    return '' unless $self->is_active;
    my ($timeout, $max_chars) = @_;
    $max_chars ||= $self->{def_max_read_chars};

    my $rin = '';
    vec($rin, fileno($self->{pty}), 1) = 1;
    my $nfound = select($rin, undef, undef, $timeout);
    my $buf;
    if ($nfound > 0) {
        my $nchars = sysread($self->{pty}, $buf, $max_chars);
        $buf = '' if defined($nchars) && $nchars == 0;
    }
    return $buf;
}
# }}}

# write() {{{

=head2 write()

Writes a string to the pty.

The first argument is the string to write, which is followed by one optional argument, the number of seconds (possibly fractional) to block for, taking the same values as C<read()>.

Returns undef on timeout, 0 on failure to write (including if no subprocess is running on the pty), or the number of bytes actually written on success (this may be less than the number of bytes requested; this should be checked for).

=cut

sub write {
    my $self = shift;
    return 0 unless $self->is_active;
    my ($text, $timeout) = @_;

    my $win = '';
    vec($win, fileno($self->{pty}), 1) = 1;
    my $nfound = select(undef, $win, undef, $timeout);
    my $nchars;
    if ($nfound > 0) {
        $nchars = syswrite($self->{pty}, $text);
    }
    return $nchars;
}
# }}}

# is_active() {{{

=head2 is_active()

Returns whether or not a subprocess is currently running on the pty.

=cut

sub is_active {
    my $self = shift;

    return defined($self->{pid});
}
# }}}

# kill() {{{

=head2 kill()

Kills the process currently running on the pty (if any). After this call, C<read()> and C<write()> will fail, and a new process can be created on the pty with C<spawn()> once C<is_active> returns false.

Returns 1 if a process was actually killed, and 0 otherwise.

=cut

sub kill {
    my $self = shift;

    # SIGCHLD should take care of undefing pid
    kill TERM => $self->{pid} if $self->is_active;
}
# }}}

# close() {{{

=head2 close()

Kills any subprocesses and closes the pty. No other operations are valid after this call.

=over 4

=back

=cut

sub close {
    my $self = shift;

    $self->kill;
    close $self->{pty};
    $self->{pty} = undef;
}
# }}}

# Ending documentation {{{

=head1 SEE ALSO

L<IO::Pty>

L<Expect>

=head1 AUTHOR

Jesse Luehrs, C<< <jluehrs2 at uiuc dot edu> >>

This module is based heavily on the F<try> script bundled with L<IO::Pty>.

=head1 BUGS

No known bugs.

Please report any bugs through RT: email
C<bug-io-pty-easy at rt.cpan.org>, or browse to
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IO-Pty-Easy>.

=head1 SUPPORT

You can find this documentation for this module with the perldoc command.

    perldoc IO::Pty::Easy

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IO-Pty-Easy>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IO-Pty-Easy>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IO-Pty-Easy>

=item * Search CPAN

L<http://search.cpan.org/dist/IO-Pty-Easy>

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2007 Jesse Luehrs.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

# }}}

1;
