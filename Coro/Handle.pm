=head1 NAME

Coro::Handle - non-blocking io with a blocking interface.

=head1 SYNOPSIS

 use Coro::Handle;

=head1 DESCRIPTION

This module implements IO-handles in a coroutine-compatible way, that is,
other coroutines can run while reads or writes block on the handle.

It does so by using L<AnyEvent|AnyEvent> to wait for readable/writable
data, allowing other coroutines to run while one coroutine waits for I/O.

Coro::Handle does NOT inherit from IO::Handle but uses tied objects.

=over 4

=cut

package Coro::Handle;

BEGIN { eval { require warnings } && warnings->unimport ("uninitialized") }

use Errno ();
use base 'Exporter';

$VERSION = 2.5;

@EXPORT = qw(unblock);

=item $fh = new_from_fh Coro::Handle $fhandle [, arg => value...]

Create a new non-blocking io-handle using the given
perl-filehandle. Returns undef if no fhandle is given. The only other
supported argument is "timeout", which sets a timeout for each operation.

=cut

sub new_from_fh {
   my $class = shift;
   my $fh = shift or return;
   my $self = do { local *Coro::Handle };

   my ($package, $filename, $line) = caller;
   $filename =~ s/^.*[\/\\]//;

   tie $self, Coro::Handle::FH, fh => $fh, desc => "$filename:$line", @_;

   my $_fh = select bless \$self, ref $class ? ref $class : $class; $| = 1; select $_fh;
}

=item $fh = unblock $fh

This is a convinience function that just calls C<new_from_fh> on the given
filehandle. Use it to replace a normal perl filehandle by a non-blocking
equivalent.

=cut

sub unblock($) {
   new_from_fh Coro::Handle $_[0];
}

=item $fh->writable, $fh->readable

Wait until the filehandle is readable or writable (and return true) or
until an error condition happens (and return false).

=cut

sub readable	{ Coro::Handle::FH::readable(tied ${$_[0]}) }
sub writable	{ Coro::Handle::FH::writable(tied ${$_[0]}) }

=item $fh->readline([$terminator])

Like the builtin of the same name, but allows you to specify the input
record separator in a coroutine-safe manner (i.e. not using a global
variable).

=cut

sub readline	{ tied(${+shift})->READLINE(@_) }

=item $fh->autoflush([...])

Always returns true, arguments are being ignored (exists for compatibility
only). Might change in the future.

=cut

sub autoflush	{ !0 }

=item $fh->fileno, $fh->close, $fh->read, $fh->sysread, $fh->syswrite, $fh->print, $fh->printf

Work like their function equivalents (except read, which works like
sysread. You should not use the read function with Coro::Handles, it will
work but it's not efficient).

=cut

sub read	{ Coro::Handle::FH::READ   (tied ${$_[0]}, $_[1], $_[2], $_[3]) }
sub sysread	{ Coro::Handle::FH::READ   (tied ${$_[0]}, $_[1], $_[2], $_[3]) }
sub syswrite	{ Coro::Handle::FH::WRITE  (tied ${$_[0]}, $_[1], $_[2], $_[3]) }
sub print	{ Coro::Handle::FH::WRITE  (tied ${+shift}, join "", @_) }
sub printf	{ Coro::Handle::FH::PRINTF (tied ${+shift}, @_) }
sub fileno	{ Coro::Handle::FH::FILENO (tied ${$_[0]}) }
sub close	{ Coro::Handle::FH::CLOSE  (tied ${$_[0]}) }
sub blocking    { !0 } # this handler always blocks the caller

sub partial     {
   my $obj = tied ${$_[0]};

   my $retval = $obj->[8];
   $obj->[8] = $_[1] if @_ > 1;
   $retval
}

=item $fh->timeout([...])

The optional argument sets the new timeout (in seconds) for this
handle. Returns the current (new) value.

C<0> is a valid timeout, use C<undef> to disable the timeout.

=cut

sub timeout {
   my $self = tied(${$_[0]});
   if (@_ > 1) {
      $self->[2] = $_[1];
      $self->[5]->timeout($_[1]) if $self->[5];
      $self->[6]->timeout($_[1]) if $self->[6];
   }
   $self->[2];
}

=item $fh->fh

Returns the "real" (non-blocking) filehandle. Use this if you want to
do operations on the file handle you cannot do using the Coro::Handle
interface.

=item $fh->rbuf

Returns the current contents of the read buffer (this is an lvalue, so you
can change the read buffer if you like).

You can use this function to implement your own optimized reader when neither
readline nor sysread are viable candidates, like this:

  # first get the _real_ non-blocking filehandle
  # and fetch a reference to the read buffer
  my $nb_fh = $fh->fh;
  my $buf = \$fh->rbuf;

  for(;;) {
     # now use buffer contents, modifying
     # if necessary to reflect the removed data

     last if $$buf ne ""; # we have leftover data

     # read another buffer full of data
     $fh->readable or die "end of file";
     sysread $nb_fh, $$buf, 8192;
  }

=cut

sub fh {
   (tied ${$_[0]})->[0];
}

sub rbuf : lvalue {
   (tied ${$_[0]})->[3];
}

sub DESTROY {
   # nop
}

sub AUTOLOAD {
   my $self = tied ${$_[0]};

   (my $func = $AUTOLOAD) =~ s/^(.*):://;

   my $forward = UNIVERSAL::can $self->[7], $func;

   $forward or
      die "Can't locate object method \"$func\" via package \"" . (ref $self) . "\"";

   goto &$forward;
}

package Coro::Handle::FH;

BEGIN { eval { require warnings } && warnings->unimport ("uninitialized") }

use Fcntl ();
use Errno ();
use Carp 'croak';

use AnyEvent;

# formerly a hash, but we are speed-critical, so try
# to be faster even if it hurts.
#
# 0 FH
# 1 desc
# 2 timeout
# 3 rb
# 4 wb # unused
# 5 unused
# 6 unused
# 7 forward class
# 8 blocking

sub TIEHANDLE {
   my ($class, %arg) = @_;

   my $self = bless [], $class;
   $self->[0] = $arg{fh};
   $self->[1] = $arg{desc};
   $self->[2] = $arg{timeout};
   $self->[3] = "";
   $self->[4] = "";
   $self->[7] = $arg{forward_class};
   $self->[8] = $arg{partial};

   fcntl $self->[0], &Fcntl::F_SETFL, &Fcntl::O_NONBLOCK
      or croak "fcntl(O_NONBLOCK): $!";

   $self
}

sub cleanup {
   $_[0][3] = "";
   $_[0][4] = "";
}

sub OPEN {
   &cleanup;
   my $self = shift;
   my $r = @_ == 2 ? open $self->[0], $_[0], $_[1]
                   : open $self->[0], $_[0], $_[1], $_[2];
   if ($r) {
      fcntl $self->[0], &Fcntl::F_SETFL, &Fcntl::O_NONBLOCK
         or croak "fcntl(O_NONBLOCK): $!";
   }
   $r;
}

sub PRINT {
   WRITE(shift, join "", @_);
}

sub PRINTF {
   WRITE(shift, sprintf(shift,@_));
}

sub GETC {
   my $buf;
   READ($_[0], $buf, 1);
   $buf;
}

sub BINMODE {
   binmode $_[0][0];
}

sub TELL {
   use Carp (); Carp::croak("Coro::Handle's don't support tell()");
}

sub SEEK {
   use Carp (); Carp::croak("Coro::Handle's don't support seek()");
}

sub EOF {
   use Carp (); Carp::croak("Coro::Handle's don't support eof()");
}

sub CLOSE {
   &cleanup;
   close $_[0][0];
}

sub DESTROY {
   &cleanup;
}

sub FILENO {
   fileno $_[0][0];
}

# seems to be called for stringification (how weird), at least
# when DumpValue::dumpValue is used to print this.
sub FETCH {
   "$_[0]<$_[0][1]>";
}

sub readable {
   my $current = $Coro::current;
   my $io = 1;

   my $w = AnyEvent->io (
      fh      => $_[0][0],
      desc    => "$_[0][1] readable",
      poll    => 'r',
      cb      => sub {
         $current->ready;
         undef $current;
      },
   );

   my $t = $_[0][2] && AnyEvent->timer (
      after => $_[0][2],
      cb    => sub {
         $io = 0;
         $current->ready;
         undef $current;
      },
   );

   &Coro::schedule;
   &Coro::schedule while $current;

   $io
}

sub writable {
   my $current = $Coro::current;
   my $io = 1;

   my $w = AnyEvent->io (
      fh      => $_[0][0],
      desc    => "$_[0][1] writable",
      poll    => 'w',
      cb      => sub {
         $current->ready;
         undef $current;
      },
   );

   my $t = $_[0][2] && AnyEvent->timer (
      after => $_[0][2],
      cb    => sub {
         $io = 0;
         $current->ready;
         undef $current;
      },
   );

   &Coro::schedule while $current;

   $io
}

sub WRITE {
   my $len = defined $_[2] ? $_[2] : length $_[1];
   my $ofs = $_[3];
   my $res = 0;

   while() {
      my $r = syswrite $_[0][0], $_[1], $len, $ofs;
      if (defined $r) {
         $len -= $r;
         $ofs += $r;
         $res += $r;
         last unless $len;
      } elsif ($! != Errno::EAGAIN) {
         last;
      }
      last unless &writable;
   }

   return $res;
}

sub READ {
   my $len = $_[2];
   my $ofs = $_[3];
   my $res = 0;

   # first deplete the read buffer
   if (length $_[0][3]) {
      my $l = length $_[0][3];
      if ($l <= $len) {
         substr($_[1], $ofs) = $_[0][3]; $_[0][3] = "";
         $len -= $l;
         $ofs += $l;
         $res += $l;
         return $res unless $len;
      } else {
         substr($_[1], $ofs) = substr($_[0][3], 0, $len);
         substr($_[0][3], 0, $len) = "";
         return $len;
      }
   }

   while() {
      my $r = sysread $_[0][0], $_[1], $len, $ofs;
      if (defined $r) {
         $len -= $r;
         $ofs += $r;
         $res += $r;
         last unless $len && $r;
      } elsif ($! != Errno::EAGAIN) {
         last;
      }
      last if $_[0][8] || !&readable;
   }

   return $res;
}

sub READLINE {
   my $irs = @_ > 1 ? $_[1] : $/;

   while() {
      my $pos = index $_[0][3], $irs;
      if ($pos >= 0) {
         $pos += length $irs;
         my $res = substr $_[0][3], 0, $pos;
         substr ($_[0][3], 0, $pos) = "";
         return $res;
      }

      my $r = sysread $_[0][0], $_[0][3], 8192, length $_[0][3];
      if (defined $r) {
         return undef unless $r;
      } elsif ($! != Errno::EAGAIN || !&readable) {
         return undef;
      }
   }
}

1;

=back

=head1 BUGS

 - Perl's IO-Handle model is THE bug.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

