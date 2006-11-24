#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <string.h>

/* this useful idiom is unfortunately missing... */
static void
confess (const char *msg)
{
  dSP;

  PUSHMARK(SP);
  XPUSHs (sv_2mortal(newSVpv("only one coroutine can wait for an event at any given time",0)));
  PUTBACK;
  call_pv ("Carp::confess", G_VOID);
}

#include "EventAPI.h"
#include "../Coro/CoroAPI.h"

#ifndef PE_PERLCB
# define PE_PERLCB 0x020 /* not public, but we need it :( */
#endif

#define CD_CORO	0
#define CD_TYPE	1
#define CD_OK	2
#define CD_PRIO	3 /* hardcoded in Coro::Event */
#define CD_HITS	4 /* hardcoded in Coro::Event */
#define CD_GOT	5 /* hardcoded in Coro::Event, Coro::Handle */
#define CD_MAX	5

#define EV_CLASS "Coro::Event"

static void
coro_std_cb(pe_event *pe)
{
  AV *priv = (AV *)pe->ext_data;
  IV type = SvIV (*av_fetch (priv, CD_TYPE, 1));
  SV **cd_coro = &AvARRAY(priv)[CD_CORO];

  sv_setiv (AvARRAY(priv)[CD_PRIO], pe->prio);
  sv_setiv (AvARRAY(priv)[CD_HITS], pe->hits);

  if (type == 1)
    sv_setiv (AvARRAY(priv)[CD_GOT], ((pe_ioevent *)pe)->got);

  if (*cd_coro != &PL_sv_undef)
    {
      CORO_READY (*cd_coro);
      SvREFCNT_dec (*cd_coro);
      *cd_coro = &PL_sv_undef;
    }
  else
    {
      AvARRAY(priv)[CD_OK] = &PL_sv_yes;
      GEventAPI->stop (pe->up, 0);
    }
}

static double
prepare_hook (void *data)
{
  while (CORO_NREADY)
    CORO_CEDE;

  return 1e10;
}

MODULE = Coro::Event                PACKAGE = Coro::Event

PROTOTYPES: ENABLE

BOOT:
{
        I_EVENT_API ("Coro::Event");
	I_CORO_API ("Coro::Event");

        GEventAPI->add_hook ("prepare", (void *)prepare_hook, 0);
}

void
_install_std_cb(self,type)
	SV *	self
        int	type
        CODE:
        pe_watcher *w = GEventAPI->sv_2watcher (self);

        if (WaFLAGS (w) & PE_PERLCB)
          croak ("Coro::Event watchers must not have a perl callback (see Coro::Event), caught");
        {
          AV *priv = newAV ();
          SV *rv = newRV_noinc ((SV *)priv);

          av_extend (priv, CD_MAX);
          av_store (priv, CD_CORO, &PL_sv_undef);
          av_store (priv, CD_TYPE, newSViv (type));
          av_store (priv, CD_OK  , &PL_sv_no);
          av_store (priv, CD_PRIO, newSViv (0));
          av_store (priv, CD_HITS, newSViv (0));
          av_store (priv, CD_GOT , type ? newSViv (0) : &PL_sv_undef);
          SvREADONLY_on (priv);

          w->callback = coro_std_cb;
          w->ext_data = priv;

          hv_store ((HV *)SvRV (self),
                    EV_CLASS, strlen (EV_CLASS),
                    rv, 0);

          GEventAPI->start (w, 0);
        }

void
_next(self)
	SV *	self
        CODE:
        pe_watcher *w = GEventAPI->sv_2watcher (self);
        AV *priv = (AV *)w->ext_data;

        if (!w->running)
          GEventAPI->start (w, 1);

        if (AvARRAY(priv)[CD_OK] == &PL_sv_yes)
          {
            AvARRAY(priv)[CD_OK] = &PL_sv_no;
            XSRETURN_NO;
          }
        else 
          {
            if (AvARRAY(priv)[CD_CORO] != &PL_sv_undef)
              confess ("only one coroutine can wait for an event");

            AvARRAY(priv)[CD_CORO] = SvREFCNT_inc (CORO_CURRENT);
            XSRETURN_YES;
          }

