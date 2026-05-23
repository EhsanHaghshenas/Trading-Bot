// ============================================================================
#ifndef WAVEBOT_FSMS_MQH
#define WAVEBOT_FSMS_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/FSMS_Lifecycle.mqh>
#include <WaveBot/FSMS_SW.mqh>   // NEW: FSMS–SW

// ????? ?????: ???? DOWN ?? ?? W3-UP ? ?????
enum FSMSState { FSMS_SEARCH_W2=0, FSMS_WAIT_CONFIRM=1 };

struct FSMSCtx
{
   // ?????? ???
   bool     w3_seen;          // W3 ????? ????? ????
   bool     c1_active;        // C1 ?????? ???? ???? ????
   bool     fired;            // FSMS ???? ??? W3 ??? ????
   datetime c1_time;          // ???? C1 ?????? (?? ??????? ???? ???? ??????)
   int      c1_index;         // ????? C1 ??????
   int      idx;              // ????? ?????? ????? ?????
   int      state;            // FSMS_SEARCH_W2 | FSMS_WAIT_CONFIRM

   // ???? ????? ?? ????? ????
   int      c1,c2,c3,c4,cend;

   // ???? ?????
   bool     have_w3;
   int      w3_c1, k2,k3,k4, w3_end;
   int      w3_cand;
   double   w3_cand_low, w3_cand_high;

   // ?????? body-break (???? ?????)
   bool     wickActive;
   int      firstWickIdx, wickBreakIdx;
   double   bodyBreakLevel;
   bool     breakAchieved;
   int      bodyBreakIdx;

   // ?????? ?? ?? body-break ?? ????? W3
   bool     postBreak_c1_lock;
   int      postBreak_c1_ref;

   // ??????? ?? C1 ???? ????? ?? ??????? FSMS (?????? ????? C1Pre_* ?????)
   bool   prelock_active;
   int    prelock_idx;
   double prelock_level;  // ???? DOWN: L1(C1) | ???? UP: H1(C1)
   
      // ??????? ?????? ?? FSMS ?? ???? ????? ??? ?????
   int      same_w3_c1_index;   // ????? C1 ???? ?????? (W3 ????)
   datetime same_w3_c1_time;    // ???? C1 ???? ??????


   // Performance cache: repeated W3 count checks during FSMS confirmation
   // are deterministic for the same startIdx/history tail.
   int      w3_cache_start_idx;
   int      w3_cache_n;
   datetime w3_cache_last_time;
   bool     w3_cache_ready;
   bool     w3_cache_ok;
   int      w3_cache_k2;
   int      w3_cache_k3;
   int      w3_cache_k4;
   int      w3_cache_end;
};

// ?? ?????: ?? ?? W3-UP? ???? DOWN ? FSMS_U? ?? ?? W3-DOWN? ???? UP ? FSMS_D
static FSMSCtx g_fsms_from_up;
static FSMSCtx g_fsms_from_dn;

static int g_fsms_u_counter=0, g_fsms_d_counter=0;
// ------------------------------
// Context snapshot for FSMS (W3-based cross-direction scans)
// ------------------------------
struct FSMSContext
{
   // ?? ?? W3-UP: ???? ??????? ????? ?? ??? DOWN
   FSMSCtx from_up;

   // ?? ?? W3-DOWN: ???? ??????? ????? ?? ??? UP
   FSMSCtx from_dn;

   // lifecycle ???? FSMS (???? ??? world?? snapshot ???)
   FSMSLifecycleContext lc;

   // ??????????? ????? ???? ?????
   int     u_counter;   // FSMS_U_*
   int     d_counter;   // FSMS_D_*
};

inline void __FSMS_Reset(FSMSCtx &S)
{
   S.w3_seen=false; S.c1_active=false; S.fired=false; S.c1_time=0; S.c1_index=-1;
   S.idx=-1; S.state=FSMS_SEARCH_W2;

   S.c1=S.c2=S.c3=S.c4=S.cend=-1;

   S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
   S.w3_cand=-1; S.w3_cand_low=DBL_MAX; S.w3_cand_high=-DBL_MAX;

   S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
   S.bodyBreakLevel=0.0; S.breakAchieved=false; S.bodyBreakIdx=-1;

   S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

   S.prelock_active = false;
   S.prelock_idx    = -1;
   S.prelock_level  = 0.0;

   // NEW: ???? ??????? ???? ??????
   S.same_w3_c1_index = -1;
   S.same_w3_c1_time  = 0;

   S.w3_cache_start_idx = -1;
   S.w3_cache_n         = -1;
   S.w3_cache_last_time = 0;
   S.w3_cache_ready     = false;
   S.w3_cache_ok        = false;
   S.w3_cache_k2        = -1;
   S.w3_cache_k3        = -1;
   S.w3_cache_k4        = -1;
   S.w3_cache_end       = -1;
}

inline void __FSMS_ResetKeepW3(FSMSCtx &S)
{
   const bool     had_w3  = S.w3_seen;
   const int      w3_idx  = S.same_w3_c1_index;
   const datetime w3_time = S.same_w3_c1_time;

   __FSMS_Reset(S);

   S.w3_seen          = had_w3;
   S.same_w3_c1_index = w3_idx;
   S.same_w3_c1_time  = w3_time;
}

inline void __FSMS_W3CacheClear(FSMSCtx &S)
{
   S.w3_cache_start_idx = -1;
   S.w3_cache_n         = -1;
   S.w3_cache_last_time = 0;
   S.w3_cache_ready     = false;
   S.w3_cache_ok        = false;
   S.w3_cache_k2        = -1;
   S.w3_cache_k3        = -1;
   S.w3_cache_k4        = -1;
   S.w3_cache_end       = -1;
}

inline bool __FSMS_W3CacheMatches(const FSMSCtx &S,
                                  const MqlRates &rates[],
                                  const int n,
                                  const int startIdx)
{
   if(!S.w3_cache_ready) return false;
   if(S.w3_cache_start_idx != startIdx) return false;
   if(S.w3_cache_n != n) return false;
   if(n <= 0) return false;
   if(S.w3_cache_last_time != rates[n-1].time) return false;
   return true;
}

inline void __FSMS_W3CacheStore(FSMSCtx &S,
                                const MqlRates &rates[],
                                const int n,
                                const int startIdx,
                                const bool ok,
                                const int k2,
                                const int k3,
                                const int k4,
                                const int end_idx)
{
   S.w3_cache_start_idx = startIdx;
   S.w3_cache_n         = n;
   S.w3_cache_last_time = (n > 0 ? rates[n-1].time : 0);
   S.w3_cache_ready     = true;
   S.w3_cache_ok        = ok;
   S.w3_cache_k2        = k2;
   S.w3_cache_k3        = k3;
   S.w3_cache_k4        = k4;
   S.w3_cache_end       = end_idx;
}

inline bool __FSMS_CheckWave3DownCached(FSMSCtx &S,
                                        const MqlRates &rates[],
                                        const bool &insideHL[],
                                        const double &bodyLowEff[],
                                        const double &bodyHighEff[],
                                        const int n,
                                        const int startIdx,
                                        int &k2, int &k3, int &k4, int &w3e)
{
   if(__FSMS_W3CacheMatches(S, rates, n, startIdx))
   {
      k2  = S.w3_cache_k2;
      k3  = S.w3_cache_k3;
      k4  = S.w3_cache_k4;
      w3e = S.w3_cache_end;
      return S.w3_cache_ok;
   }

   bool ok = CheckWave3CountOnly_Local_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, k2, k3, k4, w3e);
   __FSMS_W3CacheStore(S, rates, n, startIdx, ok, k2, k3, k4, w3e);
   return ok;
}

inline bool __FSMS_CheckWave3UpCached(FSMSCtx &S,
                                      const MqlRates &rates[],
                                      const bool &insideHL[],
                                      const double &bodyLowEff[],
                                      const double &bodyHighEff[],
                                      const int n,
                                      const int startIdx,
                                      int &k2, int &k3, int &k4, int &w3e)
{
   if(__FSMS_W3CacheMatches(S, rates, n, startIdx))
   {
      k2  = S.w3_cache_k2;
      k3  = S.w3_cache_k3;
      k4  = S.w3_cache_k4;
      w3e = S.w3_cache_end;
      return S.w3_cache_ok;
   }

   bool ok = CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, k2, k3, k4, w3e);
   __FSMS_W3CacheStore(S, rates, n, startIdx, ok, k2, k3, k4, w3e);
   return ok;
}

inline void __FSMS_ApplyLifecycleTransition()
{
   if(!FSMSLC_HasTerminalRequest())
      return;

   int owner = FSMSLC_OWNER_NONE;
   int term_kind = FSMSLC_TERM_NONE;
   datetime term_time = 0;
   FSMSLC_PeekTerminal(owner, term_kind, term_time);

   if(owner == FSMSLC_OWNER_UP)
      __FSMS_Reset(g_fsms_from_up);
   else if(owner == FSMSLC_OWNER_DN)
      __FSMS_Reset(g_fsms_from_dn);
   else
   {
      __FSMS_Reset(g_fsms_from_up);
      __FSMS_Reset(g_fsms_from_dn);
   }

   FSMSLC_FinishTerminal(term_time);
}

inline bool __FSMS_CanOpenAt(const datetime t)
{
   __FSMS_ApplyLifecycleTransition();
   return FSMSLC_CanOpenAt(t);
}

// ???????? ?????? ?? ??????? ???? (???? ???? world ????: ?????/?????)
inline void FSMS_ContextInit(FSMSContext &ctx)
{
   __FSMS_Reset(ctx.from_up);
   __FSMS_Reset(ctx.from_dn);
   FSMSLC_ContextInit(ctx.lc);
   ctx.u_counter = 0;
   ctx.d_counter = 0;
}

// Export: ??? ????? ???? global?? ?? ???? ???????
inline void FSMS_ContextExport(FSMSContext &ctx)
{
   ctx.from_up   = g_fsms_from_up;
   ctx.from_dn   = g_fsms_from_dn;
   FSMSLC_ContextExport(ctx.lc);
   ctx.u_counter = g_fsms_u_counter;
   ctx.d_counter = g_fsms_d_counter;
}

// Import: ????????? ??????? ????????? ?? ???????? global
inline void FSMS_ContextImport(const FSMSContext &ctx)
{
   g_fsms_from_up   = ctx.from_up;
   g_fsms_from_dn   = ctx.from_dn;
   FSMSLC_ContextImport(ctx.lc);
   g_fsms_u_counter = ctx.u_counter;
   g_fsms_d_counter = ctx.d_counter;
}

// ???? ???? ????? FSMS ?? world ????
inline void FSMS_ResetGlobals()
{
   __FSMS_Reset(g_fsms_from_up);
   __FSMS_Reset(g_fsms_from_dn);
   g_fsms_u_counter = 0;
   g_fsms_d_counter = 0;
   FSMSLC_ResetGlobals();
}

inline void FSMS_DisarmAll()
{
   __FSMS_Reset(g_fsms_from_up);
   __FSMS_Reset(g_fsms_from_dn);
   FSMSLC_ResetGlobals();
}

// --- ????? 1: ??? W3 (???? ???? FSMS ???? ???????)
inline void FSMS_OnW3Confirmed_UP(const MqlRates &rates[], const int n, const int w3_c1_index)
{
   datetime evt_t = TimeCurrent();
   if(w3_c1_index >= 0 && w3_c1_index < n)
      evt_t = rates[w3_c1_index].time;

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   FSMS_DisarmAll();
   FSMSLC_OnOpportunityOpen(DIR_UP, evt_t);

   g_fsms_from_up.w3_seen = true;

   if(w3_c1_index >= 0 && w3_c1_index < n)
   {
      g_fsms_from_up.same_w3_c1_index = w3_c1_index;
      g_fsms_from_up.same_w3_c1_time  = rates[w3_c1_index].time;
   }
   else
   {
      g_fsms_from_up.same_w3_c1_index = -1;
      g_fsms_from_up.same_w3_c1_time  = 0;
   }
}

inline void FSMS_OnW3Confirmed_DOWN(const MqlRates &rates[], const int n, const int w3_c1_index)
{
   datetime evt_t = TimeCurrent();
   if(w3_c1_index >= 0 && w3_c1_index < n)
      evt_t = rates[w3_c1_index].time;

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   FSMS_DisarmAll();
   FSMSLC_OnOpportunityOpen(DIR_DOWN, evt_t);

   g_fsms_from_dn.w3_seen = true;

   if(w3_c1_index >= 0 && w3_c1_index < n)
   {
      g_fsms_from_dn.same_w3_c1_index = w3_c1_index;
      g_fsms_from_dn.same_w3_c1_time  = rates[w3_c1_index].time;
   }
   else
   {
      g_fsms_from_dn.same_w3_c1_index = -1;
      g_fsms_from_dn.same_w3_c1_time  = 0;
   }
}

// --- ????? 2: ????? C1 ???? ?????? ???? ?? ? ????? ?????? FSMS ?? ???? ????
inline void FSMS_OnSameDirC1_First_UP(const MqlRates &rates[], const int n, const int idx)
{
   const int safe_idx = (idx>=0 && idx<n ? idx : 0);
   const datetime evt_t = (n>0 ? rates[safe_idx].time : TimeCurrent());

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   if(!FSMSLC_CanOwnerRearmAt(FSMSLC_OWNER_UP, evt_t))
      return;

   // ???? ???? ?? C1 ????? ????? W3 ?????? ?? ??? ????????
   const bool     was_w3        = g_fsms_from_up.w3_seen;
   const int      was_w3_c1_idx = g_fsms_from_up.same_w3_c1_index;
   const datetime was_w3_c1_t   = g_fsms_from_up.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_up);

   g_fsms_from_up.w3_seen           = was_w3;
   g_fsms_from_up.same_w3_c1_index  = was_w3_c1_idx;
   g_fsms_from_up.same_w3_c1_time   = was_w3_c1_t;

   g_fsms_from_up.c1_active = true;
   g_fsms_from_up.c1_index  = safe_idx;
   g_fsms_from_up.c1_time   = evt_t;
   g_fsms_from_up.idx       = g_fsms_from_up.c1_index;
   g_fsms_from_up.state     = FSMS_SEARCH_W2;

   g_fsms_from_up.prelock_active = false;
   g_fsms_from_up.prelock_idx    = -1;
   g_fsms_from_up.prelock_level  = 0.0;
}

inline void FSMS_OnSameDirC1_First_DOWN(const MqlRates &rates[], const int n, const int idx)
{
   const int safe_idx = (idx>=0 && idx<n ? idx : 0);
   const datetime evt_t = (n>0 ? rates[safe_idx].time : TimeCurrent());

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   if(!FSMSLC_CanOwnerRearmAt(FSMSLC_OWNER_DN, evt_t))
      return;

   const bool     was_w3        = g_fsms_from_dn.w3_seen;
   const int      was_w3_c1_idx = g_fsms_from_dn.same_w3_c1_index;
   const datetime was_w3_c1_t   = g_fsms_from_dn.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_dn);

   g_fsms_from_dn.w3_seen           = was_w3;
   g_fsms_from_dn.same_w3_c1_index  = was_w3_c1_idx;
   g_fsms_from_dn.same_w3_c1_time   = was_w3_c1_t;

   g_fsms_from_dn.c1_active = true;
   g_fsms_from_dn.c1_index  = safe_idx;
   g_fsms_from_dn.c1_time   = evt_t;
   g_fsms_from_dn.idx       = g_fsms_from_dn.c1_index;
   g_fsms_from_dn.state     = FSMS_SEARCH_W2;

   g_fsms_from_dn.prelock_active = false;
   g_fsms_from_dn.prelock_idx    = -1;
   g_fsms_from_dn.prelock_level  = 0.0;
}

// --- ????? 3: ????? C1 ?????? (re-anchor) ? ???? ? ???? ?? C1 ????
inline void FSMS_OnSameDirC1_Reanchor_UP(const MqlRates &rates[], const int n, const int i)
{
   FSMS_OnSameDirC1_First_UP(rates,n,i);
}

inline void FSMS_OnSameDirC1_Reanchor_DOWN(const MqlRates &rates[], const int n, const int i)
{
   FSMS_OnSameDirC1_First_DOWN(rates,n,i);
}

// --- ????? 3.5: ????? W2/C1 ?????? ? ?????? FSMS ?? ?? (?? ???? W3)
// ????: ??? FSMS ???? ???? W3 ????? ???? ???? «???? ????» ??? ?????? ? re-arm ????????.

inline void FSMS_OnSameDirW2Invalidated_UP()
{
   __FSMS_ApplyLifecycleTransition();
   if(FSMSLC_HasPending()) return;
   if(!FSMSLC_IsOwnerOpen(FSMSLC_OWNER_UP)) return;

   bool     fired_prev      = g_fsms_from_up.fired;
   bool     w3_prev         = g_fsms_from_up.w3_seen;
   int      w3_c1_prev_idx  = g_fsms_from_up.same_w3_c1_index;
   datetime w3_c1_prev_time = g_fsms_from_up.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_up);

   g_fsms_from_up.w3_seen          = w3_prev;
   g_fsms_from_up.fired            = fired_prev;
   g_fsms_from_up.same_w3_c1_index = w3_c1_prev_idx;
   g_fsms_from_up.same_w3_c1_time  = w3_c1_prev_time;
}

inline void FSMS_OnSameDirW2Invalidated_DOWN()
{
   __FSMS_ApplyLifecycleTransition();
   if(FSMSLC_HasPending()) return;
   if(!FSMSLC_IsOwnerOpen(FSMSLC_OWNER_DN)) return;

   bool     fired_prev      = g_fsms_from_dn.fired;
   bool     w3_prev         = g_fsms_from_dn.w3_seen;
   int      w3_c1_prev_idx  = g_fsms_from_dn.same_w3_c1_index;
   datetime w3_c1_prev_time = g_fsms_from_dn.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_dn);

   g_fsms_from_dn.w3_seen          = w3_prev;
   g_fsms_from_dn.fired            = fired_prev;
   g_fsms_from_dn.same_w3_c1_index = w3_c1_prev_idx;
   g_fsms_from_dn.same_w3_c1_time  = w3_c1_prev_time;
}

// ???????
inline void __FSMS_Mark_UP(const datetime t)
{
   ++g_fsms_u_counter;
   if(InpDrawMarkers)
      MarkV("FSMS_U_"+IntegerToString(g_fsms_u_counter), t, clrWhite);

   FSMSLC_OnFormed(DIR_UP, t);

   // Stage-1 M15->M1 publication is intentionally gated later by
   // M15NewMarker_OnTarget(). Only FSMS with a confirmed "new" tag may publish.
}
inline void __FSMS_Mark_DN(const datetime t)
{
   ++g_fsms_d_counter;
   if(InpDrawMarkers)
      MarkV("FSMS_D_"+IntegerToString(g_fsms_d_counter), t, clrWhite);

   FSMSLC_OnFormed(DIR_DOWN, t);

   // Stage-1 M15->M1 publication is intentionally gated later by
   // M15NewMarker_OnTarget(). Only FSMS with a confirmed "new" tag may publish.
}

// --- NEW: Text ??? C1 ???? ? C1 ???? ??????? ???? FSMS (UP) ---
inline void __FSMS_DrawSourceTexts_UP(const MqlRates &rates[], const int n,
                                      const FSMSCtx &S, const int fsms_id)
{
   if(!InpDrawMarkers) return;

   // C1 ???? ?????? (W2 ???? ?? ????? FSMS ?? ???? ??????)
   if(S.c1_index >= 0 && S.c1_index < n)
   {
      const MqlRates r = rates[S.c1_index];
      double span = r.high - r.low;
      if(span <= 0.0) span = 10 * _Point;
      double pad = span * 0.25;
      if(pad < 3 * _Point) pad = 3 * _Point;
      double y = r.high + pad;

      string name = "FSMS_SRC_U_W2_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name, r.time, y, "FSMS_W2", clrYellow);
   }

   // C1 ???? ?????? (W3 ????? ??? ?? FSMS)
   if(S.same_w3_c1_index >= 0 && S.same_w3_c1_index < n)
   {
      const MqlRates r2 = rates[S.same_w3_c1_index];
      double span2 = r2.high - r2.low;
      if(span2 <= 0.0) span2 = 10 * _Point;
      double pad2 = span2 * 0.25;
      if(pad2 < 3 * _Point) pad2 = 3 * _Point;
      double y2 = r2.high + pad2;

      string name2 = "FSMS_SRC_U_W3_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name2, r2.time, y2, "FSMS_W3", clrOrange);
   }
}

// --- NEW: Text ??? C1 ???? ? ???? ??????? ???? FSMS (DOWN) ---
inline void __FSMS_DrawSourceTexts_DN(const MqlRates &rates[], const int n,
                                      const FSMSCtx &S, const int fsms_id)
{
   if(!InpDrawMarkers) return;

   // C1 ???? ?????? (??? ?????)
   if(S.c1_index >= 0 && S.c1_index < n)
   {
      const MqlRates r = rates[S.c1_index];
      double span = r.high - r.low;
      if(span <= 0.0) span = 10 * _Point;
      double pad = span * 0.25;
      if(pad < 3 * _Point) pad = 3 * _Point;
      double y = r.low - pad;

      string name = "FSMS_SRC_D_W2_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name, r.time, y, "FSMS_W2", clrYellow);
   }

   // C1 ???? ?????? (W3 ????? ???? FSMS_D)
   if(S.same_w3_c1_index >= 0 && S.same_w3_c1_index < n)
   {
      const MqlRates r2 = rates[S.same_w3_c1_index];
      double span2 = r2.high - r2.low;
      if(span2 <= 0.0) span2 = 10 * _Point;
      double pad2 = span2 * 0.25;
      if(pad2 < 3 * _Point) pad2 = 3 * _Point;
      double y2 = r2.low - pad2;

      string name2 = "FSMS_SRC_D_W3_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name2, r2.time, y2, "FSMS_W3", clrOrange);
   }
}

// ?????????? ???????? ????? (?? ????? inside)
inline int __LeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[], const int from, const int to){
   if(from>to) return -1; double mx=-DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){ if(insideHL[i]) continue; if(rates[i].high>mx){mx=rates[i].high; idx=i;} }
   if(idx<0) idx=from; return idx;
}
inline int __LeftmostMinLow_ExInside(const MqlRates &rates[], const bool &insideHL[], const int from, const int to){
   if(from>to) return -1; double mn=DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){ if(insideHL[i]) continue; if(rates[i].low<mn){mn=rates[i].low; idx=i;} }
   if(idx<0) idx=from; return idx;
}

// --- ????? ???? ????: ????? ??? ?? HWBB ??? ????? ---
inline void FSMS_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                          const double &bodyLowEff[], const double &bodyHighEff[],
                          const int n, const int upto_j)
{
   if(n <= 0 || upto_j < 0 || upto_j >= n) return;

   __FSMS_ApplyLifecycleTransition();
   if(!FSMSLC_HasOpenOpportunity()) return;

   // ===== ?? ?? W3-UP: ????? DOWN (FSMS_U) ???? C1-UP ???? ??? =====
   if(FSMSLC_CanOwnerScanAt(FSMSLC_OWNER_UP, rates[upto_j].time) &&
      g_fsms_from_up.w3_seen && g_fsms_from_up.c1_active && !g_fsms_from_up.fired)
   {
      FSMSCtx S=g_fsms_from_up;
      if(upto_j>=0 && upto_j<n && rates[upto_j].time >= S.c1_time)
      {
         const int limit=upto_j;
         while(S.idx<=limit)
         {
            if(S.state==FSMS_SEARCH_W2)
            {
               bool found=false;
               for(int i=S.idx;i<=limit;++i)
               {
                  if(insideHL[i]) continue;
                  int i2=-1,i3=-1,i4=-1;
         
                  // --- FSMS pre-lock for C1 (DOWN) — ???? ??? C1Pre_DN -------------------
                  if(!S.prelock_active)
                  {
                     S.prelock_active = true;
                     S.prelock_idx    = i;
                     S.prelock_level  = rates[i].low;   // L1(C1)
                  }
                  else
                  {
                     if(i == S.prelock_idx)
                     {
                        // ???? C1 ????? ???? ?? ????? ?????
                     }
                     else if(i > S.prelock_idx)
                     {
                        // ??? ??? Low ????? L1 ???? ?? ????? ? C1 ????
                        if(rates[i].low < S.prelock_level)
                        {
                           S.prelock_idx   = i;
                           S.prelock_level = rates[i].low;
                        }
                        else
                        {
                           // ??????? ?? C1 ???? ? ??? i ???? ?????? C1 ????
                           continue;
                        }
                     }
                     else
                     {
                        // i < prelock_idx ?? ??? ????? ?? ??? (???? ?? ?? ???)?
                        // ???? ?????? ??? ???????
                        continue;
                     }
                  }
                  // -----------------------------------------------------------------------

                  if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;

                  S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

                  // ???? ????? W3 (DOWN)
                  S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
                  S.w3_cand=-1;   S.w3_cand_high=-DBL_MAX;

                  // ?????? ???? ?? ???? (DOWN)
                  S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
                  S.bodyBreakLevel=rates[S.c1].low; S.breakAchieved=false; S.bodyBreakIdx=-1;

                  S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

                  __FSMS_W3CacheClear(S);

                  S.idx=S.cend; S.state=FSMS_WAIT_CONFIRM;
                  S.prelock_active = false;  // NEW: ??? FSMS ?? ????? ??? W2 ???? ???
                  found=true; break;
               }
               if(!found){ S.idx=limit+1; break; }
            }
            else // FSMS_WAIT_CONFIRM (DOWN)
            {
               bool progressed=false;
               for(int j=S.idx;j<=limit;++j)
               {
                  if(insideHL[j]) continue;

                  // wick escalation (DOWN)
                  if(!S.breakAchieved)
                  {
                     if(rates[j].low < S.bodyBreakLevel)
                     {
                        if(rates[j].close < S.bodyBreakLevel)
                        {
                           S.breakAchieved=true; S.bodyBreakIdx=j;
                           int __c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                           S.postBreak_c1_ref=__c1_eff; S.postBreak_c1_lock=(__c1_eff>=0);
                        }
                        else
                        {
                           S.bodyBreakLevel=rates[j].low;
                           if(S.firstWickIdx<0)
                           {
                              S.firstWickIdx=j; S.wickBreakIdx=j; S.wickActive=true;
                              int anchorC1=__LeftmostMaxHigh_ExInside(rates,insideHL,S.cend,S.firstWickIdx);
                              S.have_w3=false; S.w3_c1=anchorC1; S.w3_cand=-1; S.w3_cand_high=-DBL_MAX;
                           }
                        }
                     }
                  }

                  // ChainInvalidation (pre-body, wick-window, DOWN)
                  { int __rew=-1;
                    if(ChainInv_PreBody_WickWindow_DN_OnBar(rates,insideHL,n,j,S.breakAchieved,S.wickActive,S.firstWickIdx,S.w3_c1,S.w3_cand,__rew))
                     { 
                          S.idx  = __rew; 
                          S.state= FSMS_SEARCH_W2; 
                     
                          // --- NEW: ???? ???? prelock ???? ??????? ???? FSMS ---
                          S.prelock_active = false;
                          S.prelock_idx    = -1;
                          S.prelock_level  = 0.0;
                          // -------------------------------------------------------
                     
                          progressed = true; 
                          break; 
                       }
                     }

                  // RESET W3 (non-wick, pre-body): H > H(C1_W3)
                  if(!S.wickActive && !S.breakAchieved)
                  {
                     int c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1_eff>=0 && rates[j].high > rates[c1_eff].high)
                     { S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1=-1; S.w3_cand=j; S.w3_cand_high=rates[j].high; continue; }
                  }

                  // direct-path anchor: ????????? High ?? ?? cend
                  if(!S.wickActive)
                  {
                     if(j>=S.cend && (S.w3_cand<0 || rates[j].high > S.w3_cand_high))
                     { S.w3_cand=j; S.w3_cand_high=rates[j].high; S.have_w3=false; }
                  }

                  // ????? W3 (DOWN)
                  int startIdx=-1;
                  if(S.w3_c1>=0) startIdx=S.w3_c1; else if(S.w3_cand>=0) startIdx=S.w3_cand;
                  if(!S.have_w3 && startIdx>=0 && !insideHL[startIdx])
                  {
                     int a2=-1,a3=-1,a4=-1,w3e=-1;
                     if(__FSMS_CheckWave3DownCached(S,rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
                     { S.have_w3=true; if(S.w3_c1<0) S.w3_c1=startIdx; S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e; }
                  }

                  // ??????: ????? C1_W3 ??? ?? body-break ? ????? W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1n=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(!S.postBreak_c1_lock && c1n>=0){ S.postBreak_c1_ref=c1n; S.postBreak_c1_lock=true; }
                     else if(S.postBreak_c1_lock && c1n>=0 && c1n!=S.postBreak_c1_ref)
                     { 
                        S.idx   = (S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j); 
                        S.state = FSMS_SEARCH_W2;
                  
                        // --- NEW: ???? ???? prelock ??? ????? ---
                        S.prelock_active = false;
                        S.prelock_idx    = -1;
                        S.prelock_level  = 0.0;
                        // -----------------------------------------
                  
                        progressed = true; 
                        break; 
                     }

                  }

                  // ?? ?? body-break ?? ??? ?? ????? W3: H > H(C1_W3) ? ????? W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1e=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1e>=0 && rates[j].high > rates[c1e].high)
                     { S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; }
                  }

                  // ?????: ????? ???? DOWN ?? body-break ? FSMS_U
                  if(S.have_w3 && S.breakAchieved)
                  {
                     datetime bt = rates[(S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j)].time;

                     // ??? FSMS–SW (UP) ?? ???? C1 ???? + C1 ???? ?????? ???? FSMS
                     FSMS_SW_UP_ActivateSeed(rates, n,
                                             S.c1_index,          // C1 ???? ????
                                             S.same_w3_c1_index,  // C1 ???? ????
                                             bt);

                     // ????? FSMS_U ??? ???? FSMS
                     int fsms_idx = (S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j);

                     __FSMS_Mark_UP(bt);

                     bool __m15new_fsms_up_ok = M15NewMarker_OnTarget(DIR_UP, WB_M15NEW_TARGET_FSMS, rates, n, fsms_idx);
                     Trigger_M1LocalGateRegister(DIR_UP, WB15_KIND_START_FSMS, rates, n, fsms_idx, S.c1);
                     if(__m15new_fsms_up_ok)
                        WB15_PublishStartFSMS_MAJONLY(InpSymbol, DIR_UP, bt);

                     // ?? ??? ?? ??? FSMS_W2 / FSMS_W3 ???? ??? ???? ????? ???? ?????????
                     // ??? ?? ??????? ?? ???? FSMS ?? FSMS_Minor ????? ???
                     // Text??? C1_W2_Minor_* ? C1_W3_Minor_* ?? FSMS_SW ??? ?????? ??.

                     S.fired      = true;
                     S.c1_active  = false;
                     g_fsms_from_up = S;
                     return;
                  }
               }
               if(!progressed){ S.idx=limit+1; }
            }
         }
      }
      g_fsms_from_up=S;
   }

   // ===== ?? ?? W3-DOWN: ????? UP (FSMS_D) ???? C1-DN ???? ??? =====
   if(FSMSLC_CanOwnerScanAt(FSMSLC_OWNER_DN, rates[upto_j].time) &&
      g_fsms_from_dn.w3_seen && g_fsms_from_dn.c1_active && !g_fsms_from_dn.fired)
   {
      FSMSCtx S=g_fsms_from_dn;
      if(upto_j>=0 && upto_j<n && rates[upto_j].time >= S.c1_time)
      {
         const int limit=upto_j;
         while(S.idx<=limit)
         {
            if(S.state==FSMS_SEARCH_W2)
            {
               bool found=false;
               for(int i=S.idx;i<=limit;++i)
               {
                  if(insideHL[i]) continue;
                  int i2=-1,i3=-1,i4=-1;

                  // --- FSMS pre-lock for C1 (UP) — ???? ??? C1Pre_UP --------------------
                  if(!S.prelock_active)
                  {
                     S.prelock_active = true;
                     S.prelock_idx    = i;
                     S.prelock_level  = rates[i].high;  // H1(C1)
                  }
                  else
                  {
                     if(i == S.prelock_idx)
                     {
                        // ???? C1 ????
                     }
                     else if(i > S.prelock_idx)
                     {
                        // ??? ??? High ????? H1 ???? ?? ????? ? C1 ????
                        if(rates[i].high > S.prelock_level)
                        {
                           S.prelock_idx   = i;
                           S.prelock_level = rates[i].high;
                        }
                        else
                        {
                           // ??????? ?? C1 ????
                           continue;
                        }
                     }
                     else
                     {
                        // i < prelock_idx ? ???? ????? ?? ???????
                        continue;
                     }
                  }
                  // -----------------------------------------------------------------------
         
                  if(!CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;
                  
                  S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

                  S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
                  S.w3_cand=-1;   S.w3_cand_low=DBL_MAX;

                  S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
                  S.bodyBreakLevel=rates[S.c1].high; S.breakAchieved=false; S.bodyBreakIdx=-1;

                  S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

                  __FSMS_W3CacheClear(S);

                  S.idx=S.cend; S.state=FSMS_WAIT_CONFIRM;
                  S.prelock_active = false;  // NEW: ??? FSMS ?? ????? ??? W2 ???? ???
                  found=true; break;
               }
               if(!found){ S.idx=limit+1; break; }
            }
            else // FSMS_WAIT_CONFIRM (UP)
            {
               bool progressed=false;
               for(int j=S.idx;j<=limit;++j)
               {
                  if(insideHL[j]) continue;

                  // wick escalation (UP)
                  if(!S.breakAchieved)
                  {
                     if(rates[j].high > S.bodyBreakLevel)
                     {
                        if(rates[j].close > S.bodyBreakLevel)
                        {
                           S.breakAchieved=true; S.bodyBreakIdx=j;
                           int __c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                           S.postBreak_c1_ref=__c1_eff; S.postBreak_c1_lock=(__c1_eff>=0);
                        }
                        else
                        {
                           S.bodyBreakLevel=rates[j].high;
                           if(S.firstWickIdx<0)
                           {
                              S.firstWickIdx=j; S.wickBreakIdx=j; S.wickActive=true;
                              int anchorC1=__LeftmostMinLow_ExInside(rates,insideHL,S.cend,S.firstWickIdx);
                              S.have_w3=false; S.w3_c1=anchorC1; S.w3_cand=-1; S.w3_cand_low=DBL_MAX;
                           }
                        }
                     }
                  }

                  // ChainInvalidation (pre-body, wick-window, UP)
                  { int __rew=-1;
                    if(ChainInv_PreBody_WickWindow_UP_OnBar(rates,insideHL,n,j,S.breakAchieved,S.wickActive,S.firstWickIdx,S.w3_c1,S.w3_cand,__rew))
                    { S.idx=__rew; S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; } }

                  // RESET W3 (non-wick, pre-body): L < L(C1_W3)
                  if(!S.wickActive && !S.breakAchieved)
                  {
                     int c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1_eff>=0 && rates[j].low < rates[c1_eff].low)
                     { S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_cand=j; S.w3_cand_low=rates[j].low; S.w3_c1=-1; continue; }
                  }

                  // direct-path anchor: ?????? Low ?? ?? cend
                  if(!S.wickActive)
                  {
                     if(j>=S.cend && (S.w3_cand<0 || rates[j].low < S.w3_cand_low))
                     { S.w3_cand=j; S.w3_cand_low=rates[j].low; S.have_w3=false; }
                  }

                  // ????? W3 (UP)
                  int startIdx=-1;
                  if(S.w3_c1>=0) startIdx=S.w3_c1; else if(S.w3_cand>=0) startIdx=S.w3_cand;
                  if(!S.have_w3 && startIdx>=0 && !insideHL[startIdx])
                  {
                     int a2=-1,a3=-1,a4=-1,w3e=-1;
                     if(__FSMS_CheckWave3UpCached(S,rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
                     { S.have_w3=true; if(S.w3_c1<0) S.w3_c1=startIdx; S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e; }
                  }

                  // ??????: ????? C1_W3 ??? ?? body-break ? ????? W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1n=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(!S.postBreak_c1_lock && c1n>=0){ S.postBreak_c1_ref=c1n; S.postBreak_c1_lock=true; }
                     else if(S.postBreak_c1_lock && c1n>=0 && c1n!=S.postBreak_c1_ref)
                     { S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; }
                  }

                  // ?? ?? body-break ?? ??? ?? ????? W3: L < L(C1_W3) ? ????? W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1e=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1e>=0 && rates[j].low < rates[c1e].low)
                     { S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; }
                  }

                  // ?????: ????? ???? UP ?? body-break ? FSMS_D
                  if(S.have_w3 && S.breakAchieved)
                  {
                     datetime bt = rates[(S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j)].time;

                     // ??? FSMS–SW (DOWN) ?? ???? C1 ???? + C1 ???? ?????? ???? FSMS
                     FSMS_SW_DN_ActivateSeed(rates, n,
                                             S.c1_index,          // C1 ???? ???? ?????
                                             S.same_w3_c1_index,  // C1 ???? ???? ?????
                                             bt);

                     // ????? FSMS_D
                     int fsms_idx = (S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j);

                     __FSMS_Mark_DN(bt);

                     bool __m15new_fsms_dn_ok = M15NewMarker_OnTarget(DIR_DOWN, WB_M15NEW_TARGET_FSMS, rates, n, fsms_idx);
                     Trigger_M1LocalGateRegister(DIR_DOWN, WB15_KIND_START_FSMS, rates, n, fsms_idx, S.c1);
                     if(__m15new_fsms_dn_ok)
                        WB15_PublishStartFSMS_MAJONLY(InpSymbol, DIR_DOWN, bt);

                     // ??? Text ?? ??? FSMS_W2 / FSMS_W3 ???? ??? ???????

                     S.fired      = true;
                     S.c1_active  = false;
                     g_fsms_from_dn = S;
                     return;
                  }
               }
               if(!progressed){ S.idx=limit+1; }
            }
         }
      }
      g_fsms_from_dn=S;
   }
}

#endif // WAVEBOT_FSMS_MQH
