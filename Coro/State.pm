=head1 NAME

Coro::State - create and manage simple coroutines

=head1 SYNOPSIS

 use Coro::State;

 $new = new Coro::State sub {
    print "in coroutine (called with @_), switching back\n";
    $new->transfer ($main);
    print "in coroutine again, switching back\n";
    $new->transfer ($main);
 }, 5;

 $main = new Coro::State;

 print "in main, switching to coroutine\n";
 $main->transfer ($new);
 print "back in main, switch to coroutine again\n";
 $main->transfer ($new);
 print "back in main\n";

=head1 DESCRIPTION

This module implements coroutines. Coroutines, similar to continuations,
allow you to run more than one "thread of execution" in parallel. Unlike
threads, there is no parallelism and only voluntary switching is used so
locking problems are greatly reduced.

This can be used to implement non-local jumps, exception handling,
continuations and more.

This module provides only low-level functionality. See L<Coro> and related
modules for a higher level process abstraction including scheduling.

=head2 MEMORY CONSUMPTION

A newly created coroutine that has not been used only allocates a
relatively small (a few hundred bytes) structure. Only on the first
C<transfer> will perl allocate stacks (a few kb) and optionally
a C stack/coroutine (cctx) for coroutines that recurse through C
functions. All this is very system-dependent. On my x86_64-pc-linux-gnu
system this amounts to about 8k per (non-trivial) coroutine. You can view
the actual memory consumption using Coro::Debug.

=head2 FUNCTIONS

=over 4

=cut

package Coro::State;

use strict;
no warnings "uninitialized";

use XSLoader;

BEGIN {
   our $VERSION = '3.0';

   # must be done here because the xs part expects it to exist
   # it might exist already because Coro::Specific created it.
   $Coro::current ||= { };

   XSLoader::load __PACKAGE__, $VERSION;
}

use Exporter;
use base Exporter::;

our @EXPORT_OK = qw(SAVE_DEFAV SAVE_DEFSV SAVE_ERRSV SAVE_IRSSV SAVE_DEFFH SAVE_DEFAULT SAVE_ALL);

=item $coro = new Coro::State [$coderef[, @args...]]

Create a new coroutine and return it. The first C<transfer> call to this
coroutine will start execution at the given coderef. If the subroutine
returns the program will be terminated as if execution of the main program
ended. If it throws an exception the program will terminate.

Calling C<exit> in a coroutine does the same as calling it in the main
program.

The initial save flags for a new state is C<SAVE_DEFAULT>, which can be
changed using the C<save> method.

If the coderef is omitted this function will create a new "empty"
coroutine, i.e. a coroutine that cannot be transfered to but can be used
to save the current coroutine in.

The returned object is an empty hash which can be used for any purpose
whatsoever, for example when subclassing Coro::State.

=cut

# this is called for each newly created C coroutine,
# and is being artificially injected into the opcode flow.
# its sole purpose is to call transfer() once so it knows
# the stop level stack frame for stack sharing.
sub _cctx_init {
   _set_stacklevel $_[0];
}

=item $old_save_flags = $state->save ([$new_save_flags])

It is possible to "localise" certain global variables for each state:
for example, it would be awkward if @_ or $_ would suddenly change just
because you temporarily switched to another coroutine, so Coro::State can
save those variables in the state object on transfers.

The C<$new_save_flags> value can be used to specify which variables (and
other things) are to be saved (and later restored) on each transfer, by
ORing the following constants together:

   Constant    Effect
   SAVE_DEFAV  save/restore @_
   SAVE_DEFSV  save/restore $_
   SAVE_ERRSV  save/restore $@
   SAVE_IRSSV  save/restore $/ (the Input Record Separator, slow)
   SAVE_DEFFH  save/restore default filehandle (select)
   SAVE_DEF    the default set of saves
   SAVE_ALL    everything that can be saved

These constants are not exported by default. If you don't need any extra
additional variables saved, use C<0> as the flags value.

If you feel that something important is missing then tell me. Also
remember that every function call that might call C<transfer> (such
as C<Coro::Channel::put>) might clobber any global and/or special
variables. Yes, this is by design ;) You can always create your own
process abstraction model that saves these variables.

The easiest way to do this is to create your own scheduling primitive like
this:

  sub schedule {
     local ($_, $@, ...);
     $old->transfer ($new);
  }

=item $old_save_flags = $state->save_also ($new_save_flags)

Like C<save>, but adds the given flags to the existing save flags, and
still returns the old flag set.

=item $guard = $state->guarded_save ($new_save_flags)

Like C<save_also>, but returns a guard that resets the save flags when
destroyed.

This is useful when you need to save additional state in a lexically
scoped block.

=cut

sub Coro::State::save_guard::DESTROY {
   $_[0][0]->save ($_[0][1]);

}

sub guarded_save {
   bless [$_[0], $_[0]->save_also ($_[1])], Coro::State::save_guard::
}

=item $state->has_stack

Returns wether the state currently uses a cctx/C stack. An active state
always has a cctx, as well as the main program. Other states only use a
cctx when needed.

=item $bytes = $state->rss

Returns the memory allocated by the coroutine (which includes
static structures, various perl stacks but NOT local variables,
arguments or any C stack).

=item $state->call ($coderef)

Try to call the given $coderef in the context of the given state.  This
works even when the state is currently within an XS function, and can
be very dangerous. You can use it to acquire stack traces etc. (see the
Coro::Debug module for more details). The coderef MUST NOT EVER transfer
to another state.

=item $state->eval ($string)

Like C<call>, but eval's the string. Dangerous. Do not
use. Untested. Unused. Biohazard.

=item $state->trace ($flags)

Internal function to control tracing. I just mention this so you can stay
from abusing it.

=item $prev->transfer ($next)

Save the state of the current subroutine in C<$prev> and switch to the
coroutine saved in C<$next>.

The "state" of a subroutine includes the scope, i.e. lexical variables and
the current execution state (subroutine, stack).

=item Coro::State::cctx_count

Returns the number of C-level coroutines allocated. If this number is
very high (more than a dozen) it might help to identify points of C-level
recursion in your code and moving this into a separate coroutine.

=item Coro::State::cctx_idle

Returns the number of allocated but idle (free for reuse) C level
coroutines. Currently, Coro will limit the number of idle/unused cctxs to
8.

=item Coro::State::cctx_stacksize [$new_stacksize]

Returns the current C stack size and optionally sets the new I<minimum>
stack size to C<$new_stacksize> I<long>s. Existing stacks will not
be changed, but Coro will try to replace smaller stacks as soon as
possible. Any Coro::State's that starts to use a stack after this call is
guarenteed this minimum size. Please note that Coroutines will only need
to use a C-level stack if the interpreter recurses or calls a function in
a module that calls back into the interpreter.

=item @states = Coro::State::list

Returns a list of all states currently allocated.

=cut

sub debug_desc {
   $_[0]{desc}
}

1;

=back

=head1 BUGS

This module is not thread-safe. You must only ever use this module from
the same thread (this requirement might be loosened in the future).

=head1 SEE ALSO

L<Coro>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

