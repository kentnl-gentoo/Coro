#ifndef CORO_API_H
#define CORO_API_H

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef pTHX_
# define pTHX_
# define aTHX_
# define pTHX
# define aTHX
#endif

/* perl-related */
#define CORO_SAVE_DEFAV	0x00000001 /* @_ */
#define CORO_SAVE_DEFSV	0x00000002 /* $_ */
#define CORO_SAVE_ERRSV	0x00000004 /* $@ */
#define CORO_SAVE_IRSSV	0x00000008 /* $/ */
#define CORO_SAVE_DEFFH	0x00000010 /* default filehandle */

#define CORO_SAVE_ALL	( CORO_SAVE_DEFAV \
                        | CORO_SAVE_DEFSV \
                        | CORO_SAVE_ERRSV \
                        | CORO_SAVE_IRSSV \
                        | CORO_SAVE_DEFFH)

#define CORO_SAVE_DEF CORO_SAVE_ALL

/*struct coro;*/ /* opaque */

/* private structure, always use the provided macros below */
struct CoroAPI {
  I32 ver;
#define CORO_API_VERSION 4
#define CORO_API_REVISION 0

  /* internal */
  /*struct coro *(*sv_to_coro)(SV *arg, const char *funcname, const char *varname);*/

  /* private API, Coro::State */
  void (*transfer) (SV *prev_sv, SV *next_sv);
  int (*save) (SV *coro_sv, int new_save);

  /* private API, Coro */
  void (*schedule) (void);
  int (*cede) (void);
  int (*cede_notself) (void);
  int (*ready) (SV *coro_sv);
  int (*is_ready) (SV *coro_sv);
  int *nready;
  SV *current;
};

static struct CoroAPI *GCoroAPI;

/* public API macros */
#define CORO_TRANSFER(prev,next) GCoroAPI->transfer (aTHX_ (prev), (next))
#define CORO_SCHEDULE            GCoroAPI->schedule ()
#define CORO_CEDE                GCoroAPI->cede ()
#define CORO_CEDE_NOTSELF        GCoroAPI->cede_notself ()
#define CORO_READY(coro)         GCoroAPI->ready (coro)
#define CORO_IS_READY(coro)      GCoroAPI->is_ready (coro)
#define CORO_NREADY              (*GCoroAPI->nready)
#define CORO_CURRENT             SvRV (GCoroAPI->current)
#define CORO_GET_SAVE(coro)      GCoroAPI->save ((coro), -1)
#define CORO_SET_SAVE(coro,save) GCoroAPI->save ((coro), (save))

#define I_CORO_API(YourName)                                               \
STMT_START {                                                               \
  SV *sv = perl_get_sv("Coro::API",0);                                     \
  if (!sv) croak("Coro::API not found");                                   \
  GCoroAPI = (struct CoroAPI*) SvIV(sv);                                   \
  if (GCoroAPI->ver != CORO_API_VERSION) {                                 \
    croak("Coro::API version mismatch (%d != %d) -- please recompile %s",  \
          GCoroAPI->ver, CORO_API_VERSION, YourName);                      \
  }                                                                        \
} STMT_END

#endif

