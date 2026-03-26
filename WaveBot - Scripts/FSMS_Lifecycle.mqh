// WaveBot/FSMS_Lifecycle.mqh
#ifndef WAVEBOT_FSMS_LIFECYCLE_MQH
#define WAVEBOT_FSMS_LIFECYCLE_MQH

#include <WaveBot/Types.mqh>

enum FSMSLCOwnerKind
{
   FSMSLC_OWNER_NONE = 0,
   FSMSLC_OWNER_UP   = 1,
   FSMSLC_OWNER_DN   = 2
};

enum FSMSLCTerminalKind
{
   FSMSLC_TERM_NONE         = 0,
   FSMSLC_TERM_FSMS_SW      = 1,
   FSMSLC_TERM_MINORSTARTER = 2,
   FSMSLC_TERM_HWX          = 3,
   FSMSLC_TERM_HWBB         = 4
};

struct FSMSLifecycleContext
{
   bool     pending;
   int      owner;
   datetime formed_time;

   int      terminal_kind;
   datetime terminal_time;

   datetime resume_after_time;
};

static bool     g_fsmslc_pending          = false;
static int      g_fsmslc_owner            = FSMSLC_OWNER_NONE;
static datetime g_fsmslc_formed_time      = 0;
static int      g_fsmslc_terminal_kind    = FSMSLC_TERM_NONE;
static datetime g_fsmslc_terminal_time    = 0;
static datetime g_fsmslc_resume_after_time= 0;

inline int __FSMSLC_OwnerFromDir(const Direction dir)
{
   return (dir == DIR_UP ? FSMSLC_OWNER_UP : FSMSLC_OWNER_DN);
}

inline void FSMSLC_ContextInit(FSMSLifecycleContext &ctx)
{
   ctx.pending           = false;
   ctx.owner             = FSMSLC_OWNER_NONE;
   ctx.formed_time       = 0;
   ctx.terminal_kind     = FSMSLC_TERM_NONE;
   ctx.terminal_time     = 0;
   ctx.resume_after_time = 0;
}

inline void FSMSLC_ContextExport(FSMSLifecycleContext &ctx)
{
   ctx.pending           = g_fsmslc_pending;
   ctx.owner             = g_fsmslc_owner;
   ctx.formed_time       = g_fsmslc_formed_time;
   ctx.terminal_kind     = g_fsmslc_terminal_kind;
   ctx.terminal_time     = g_fsmslc_terminal_time;
   ctx.resume_after_time = g_fsmslc_resume_after_time;
}

inline void FSMSLC_ContextImport(const FSMSLifecycleContext &ctx)
{
   g_fsmslc_pending           = ctx.pending;
   g_fsmslc_owner             = ctx.owner;
   g_fsmslc_formed_time       = ctx.formed_time;
   g_fsmslc_terminal_kind     = ctx.terminal_kind;
   g_fsmslc_terminal_time     = ctx.terminal_time;
   g_fsmslc_resume_after_time = ctx.resume_after_time;
}

inline void FSMSLC_ResetGlobals()
{
   g_fsmslc_pending           = false;
   g_fsmslc_owner             = FSMSLC_OWNER_NONE;
   g_fsmslc_formed_time       = 0;
   g_fsmslc_terminal_kind     = FSMSLC_TERM_NONE;
   g_fsmslc_terminal_time     = 0;
   g_fsmslc_resume_after_time = 0;
}

inline bool FSMSLC_HasPending()
{
   return g_fsmslc_pending;
}

inline int FSMSLC_Owner()
{
   return g_fsmslc_owner;
}

inline datetime FSMSLC_FormedTime()
{
   return g_fsmslc_formed_time;
}

inline datetime FSMSLC_ResumeAfterTime()
{
   return g_fsmslc_resume_after_time;
}

inline bool FSMSLC_CanOpenAt(const datetime t)
{
   if(g_fsmslc_pending) return false;
   if(g_fsmslc_resume_after_time > 0 && t > 0 && t <= g_fsmslc_resume_after_time)
      return false;
   return true;
}

inline void FSMSLC_OnFormed(const Direction dir, const datetime formed_time)
{
   if(formed_time <= 0) return;

   g_fsmslc_pending           = true;
   g_fsmslc_owner             = __FSMSLC_OwnerFromDir(dir);
   g_fsmslc_formed_time       = formed_time;
   g_fsmslc_terminal_kind     = FSMSLC_TERM_NONE;
   g_fsmslc_terminal_time     = 0;
   g_fsmslc_resume_after_time = 0;
}

inline void FSMSLC_RequestTerminal(const int terminal_kind, const datetime terminal_time)
{
   if(!g_fsmslc_pending) return;
   if(terminal_kind == FSMSLC_TERM_NONE) return;
   if(terminal_time <= 0) return;
   if(g_fsmslc_formed_time > 0 && terminal_time < g_fsmslc_formed_time) return;

   if(g_fsmslc_terminal_kind == FSMSLC_TERM_NONE ||
      g_fsmslc_terminal_time <= 0 ||
      terminal_time < g_fsmslc_terminal_time ||
      (terminal_time == g_fsmslc_terminal_time && terminal_kind > g_fsmslc_terminal_kind))
   {
      g_fsmslc_terminal_kind = terminal_kind;
      g_fsmslc_terminal_time = terminal_time;
   }
}

inline bool FSMSLC_HasTerminalRequest()
{
   return (g_fsmslc_pending && g_fsmslc_terminal_kind != FSMSLC_TERM_NONE && g_fsmslc_terminal_time > 0);
}

inline void FSMSLC_PeekTerminal(int &owner, int &terminal_kind, datetime &terminal_time)
{
   owner         = g_fsmslc_owner;
   terminal_kind = g_fsmslc_terminal_kind;
   terminal_time = g_fsmslc_terminal_time;
}

inline void FSMSLC_ClearTerminalRequest()
{
   g_fsmslc_terminal_kind = FSMSLC_TERM_NONE;
   g_fsmslc_terminal_time = 0;
}

inline void FSMSLC_FinishTerminal(const datetime resume_after)
{
   g_fsmslc_pending           = false;
   g_fsmslc_owner             = FSMSLC_OWNER_NONE;
   g_fsmslc_formed_time       = 0;
   g_fsmslc_resume_after_time = resume_after;
   g_fsmslc_terminal_kind     = FSMSLC_TERM_NONE;
   g_fsmslc_terminal_time     = 0;
}

#endif // WAVEBOT_FSMS_LIFECYCLE_MQH
