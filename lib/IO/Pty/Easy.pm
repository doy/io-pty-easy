package IO::Pty::Easy;
use warnings;
use strict;
use IO::Pty;

=head1 NAME

IO::Pty::Easy - ???

=head1 VERSION

Version 0.01 released ???

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use IO::Pty::Easy;
    do_stuff();

=head1 DESCRIPTION

=cut

=head1 CONSTRUCTOR

=head2 new()

=over 4

=back

=cut

sub new {
    my $class = shift;
    my $self = {
        # options
        handle_pty_size => 1,
        def_max_read_chars => 8192,
        def_max_write_chars => 8192,
        @_,

        # state
        pty => undef,
        pid => undef,
    };

    bless $self, $class;

    $self->{pty} = new IO::Pty;

    return $self;
}

=head1 METHODS

=head2 spawn()

=over 4

=back

=cut

sub spawn {
    my $self = shift;
    my $slave = $self->{pty}->slave;

    # set up a pipe to use for keeping track of the child process during exec
    my ($readp, $writep);
    unless (pipe($readp, $writep)) {
        warn "Failed to create a pipe";
        return;
    }
    $writep->autoflush(1);

    # fork a child process
    # if the exec fails, signal the parent by sending the errno across the pipe
    # if the exec succeeds, perl will close the pipe, and the sysread will
    # return due to eof
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
            or warn "Couldn't reopen STDIN for reading";
        open(STDOUT, ">&" . $slave->fileno)
            or warn "Couldn't reopen STDOUT for writing";
        open(STDERR, ">&" . $slave->fileno)
            or warn "Couldn't reopen STDERR for writing";
        close $slave;
        { exec(@_) };
        print $writep $! + 0;
        die "Cannot exec(@_): $!";
    }

    close $writep;
    $self->{pty}->close_slave;
    $self->{pty}->set_raw;
    # this sysread will block until either we get an eof from the other end of
    # the pipe being closed due to the exec, or until the child process sends
    # us the errno of the exec call after it fails
    my $errno;
    my $read_bytes = sysread($readp, $errno, 256);
    unless (defined $read_bytes) {
        warn "Cannot sync with child: $!";
        kill TERM => $self->{pid};
        close $readp;
        return;
    }
    close $readp;
    if ($read_bytes > 0) {
        $errno = $errno + 0;
        warn "Cannot exec(@_): $errno";
        return;
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

=head2 read()

=over 4

=back

=cut

sub read {
    my $self = shift;
    return 0 unless $self->is_active;
    my ($buf, $timeout, $max_chars) = @_;
    $max_chars ||= $self->{def_max_read_chars};

    my $rin = '';
    vec($rin, fileno($self->{pty}), 1) = 1;
    my $nfound = select($rin, undef, undef, $timeout);
    my $nchars;
    if ($nfound > 0) {
        $nchars = sysread($self->{pty}, $_[0], $max_chars);
    }
    return $nchars;
}

=head2 write()

=over 4

=back

=cut

sub write {
    my $self = shift;
    return 0 unless $self->is_active;
    my ($text, $timeout, $max_chars) = @_;
    $max_chars ||= $self->{def_max_write_chars};

    my $win = '';
    vec($win, fileno($self->{pty}), 1) = 1;
    my $nfound = select(undef, $win, undef, $timeout);
    my $nchars;
    if ($nfound > 0) {
        $nchars = syswrite($self->{pty}, $text, $max_chars);
    }
    return $nchars;
}

=head2 is_active()

=over 4

=back

=cut

sub is_active {
    my $self = shift;

    return defined($self->{pid});
}

=head2 kill()

=over 4

=back

=cut

sub kill {
    my $self = shift;

    # SIGCHLD should take care of undefing pid
    kill TERM => $self->{pid} if $self->is_active;
}

=head2 close()

=over 4

=back

=cut

sub close {
    my $self = shift;

    $self->kill;
    close $self->{pty};
    $self->{pty} = undef;
}

=head1 SEE ALSO

L<IO::Pty>
L<Expect>

=head1 AUTHOR

Jesse Luehrs, C<< <jluehrs2 at uiuc dot edu> >>

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

1;
