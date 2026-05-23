// ============================================================================
#ifndef WAVEBOT_WORLDMANAGER_MQH
#define WAVEBOT_WORLDMANAGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Hunter.mqh>
#include <WaveBot/Hunter_Down.mqh>
#include <WaveBot/Hunter_BodyBreak.mqh>
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/C1PreLock.mqh>
#include <WaveBot/C1W2Gate.mqh>
#include <WaveBot/SWGate.mqh>
#include <WaveBot/ShadowBreaker.mqh>
#include <WaveBot/W3ChainGuard.mqh>
#include <WaveBot/FSMS.mqh>
#include <WaveBot/FSMS_SW.mqh>
#include <WaveBot/StrongRange.mqh>
#include <WaveBot/SR_Gate.mqh>
#include <WaveBot/SR_Mitigator.mqh>
#include <WaveBot/SR_GoozBaghali.mqh>

inline ENUM_TIMEFRAMES __WBWM_RuntimeTF()
{
   ENUM_TIMEFRAMES tf = InpTF;
   ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();

   if(chart_tf == PERIOD_M15)     tf = PERIOD_M15;
   else if(chart_tf == PERIOD_M1) tf = PERIOD_M1;

   return tf;
}


inline bool WBWM_MinorWorldEnabledOnThisChart()
{
   ENUM_TIMEFRAMES chart_tf   = (ENUM_TIMEFRAMES)Period();
   ENUM_TIMEFRAMES runtime_tf = __WBWM_RuntimeTF();

   // M1 slave and M15 master both use only the normal/main scan path.
   if(chart_tf == PERIOD_M1 || chart_tf == PERIOD_M15)
      return false;

   // Standalone scans configured as M15 must also stay in the main world.
   if(runtime_tf == PERIOD_M15)
      return false;

   return true;
}

inline void WBWM_DiscardPendingMinorStarterEvents()
{
   FSMS_SW_MinorSession discard;
   while(FSMS_SW_PopMinorStartEvent(discard))
   {
      // Drain stale MAJ->MIN events when local-minor execution is disabled.
   }
}


// ------------------------------------------------------------------
// World snapshot (MAJ / MIN)
// ------------------------------------------------------------------
struct WBWorldContext
{
   ExtLQContext          ext_up;
   ExtLQDownContext      ext_dn;

   HunterUpContext       hunter_up;
   HunterDownContext     hunter_dn;
   HWBBContext           hwbb;

   RaceContext           race;
   C1PreContext          c1pre;
   C1W2GateContext       c1w2gate;
   SWGateContext         swgate;
   SBContext             sb;
   W3CGContext           w3cg;

   FSMSContext           fsms;
   FSMS_SWContext        fsms_sw;

   StrongRangeContext    sr;
   SRGateContext         srgate;
   SRMITContext          srmit;
   SRGBContext           srgb;

   string                markers_ns;
   int                   scan_id;
};

static bool         g_wbwm_inited         = false;
static WBWorldContext g_wbwm_major;
static WBWorldContext g_wbwm_minor;
static int          g_wbwm_minor_scan_seq = 0;

// -------- NEW: step-per-candle MIN engine state (session-based) --------
static bool                g_wbwm_minor_active       = false;
static FSMS_SW_MinorSession g_wbwm_minor_sess;
static int                 g_wbwm_minor_scan_id      = 0;
static string              g_wbwm_minor_tag_suffix   = "";

// guard: prevent double-run on same MAJ bar inside the same MAJ scan
static int                 g_wbwm_last_maj_scan_id   = -1;
static datetime            g_wbwm_last_maj_time      = 0;

// NEW: minor session lifecycle
static FSMS_SW_MinorSession g_wbwm_minor_s;
// ------------------------------------------------------------------
// MinorOff Stop-Gate (MIN world only)
// ???: ??? ???? ??? ???? ???? ?????? ?? ???/?????? MinorOff ?? MAJ
// ------------------------------------------------------------------
static bool     g_wbwm_minor_stop_armed  = false;
static datetime g_wbwm_minor_stop_start = 0;
static double   g_wbwm_minor_stop_l1    = 0.0;
static double   g_wbwm_minor_stop_l2    = 0.0;

inline void WBWM_MinorStop_Disarm()
{
   g_wbwm_minor_stop_armed  = false;
   g_wbwm_minor_stop_start  = 0;
   g_wbwm_minor_stop_l1     = 0.0;
   g_wbwm_minor_stop_l2     = 0.0;
}

inline void WBWM_MinorStop_Arm(const datetime starter_time,
                               const double   off_level_1,
                               const double   off_level_2)
{
   g_wbwm_minor_stop_armed  = true;
   g_wbwm_minor_stop_start  = starter_time;
   g_wbwm_minor_stop_l1     = off_level_1;
   g_wbwm_minor_stop_l2     = off_level_2;
}

inline bool WBWM_MinorStop_ShouldStop(const MqlRates &r)
{
   if(!g_wbwm_minor_stop_armed) return false;

   // Off ??? ??? ?? ???? ???? MinorStarter ????? ???
   if(r.time <= g_wbwm_minor_stop_start) return false;

   const double low  = r.low;
   const double high = r.high;

   bool crossed = false;

   if(g_wbwm_minor_stop_l1 > 0.0)
   {
      if(low <= g_wbwm_minor_stop_l1 && high >= g_wbwm_minor_stop_l1)
         crossed = true;
   }
   if(!crossed && g_wbwm_minor_stop_l2 > 0.0)
   {
      if(low <= g_wbwm_minor_stop_l2 && high >= g_wbwm_minor_stop_l2)
         crossed = true;
   }

   return crossed;
}

// -------------------- helpers --------------------
inline void __WBWM_InitExtLQUpContext(ExtLQContext &ctx)
{
   ctx.ext_has   = false;
   ctx.ext_price = 0.0;
   ctx.ext_time  = 0;
   ArrayResize(ctx.hist, 0);
   ctx.prev_idx  = -1;
}

inline void WBWM_ContextInit(WBWorldContext &ctx)
{
   __WBWM_InitExtLQUpContext(ctx.ext_up);
   ExtLQ_Down_ContextReset(ctx.ext_dn);

   Hunter_UP_ContextInit(ctx.hunter_up);
   Hunter_DN_ContextInit(ctx.hunter_dn);
   HW_BB_ContextInit(ctx.hwbb);

   Race_ContextReset(ctx.race);
   C1Pre_ContextInit(ctx.c1pre);
   C1W2Gate_ContextInit(ctx.c1w2gate);
   SWGate_ContextInit(ctx.swgate);
   SB_ContextInit(ctx.sb);
   W3CG_ContextInit(ctx.w3cg);

   FSMS_ContextInit(ctx.fsms);
   FSMS_SW_ContextInit(ctx.fsms_sw);

   SR_ContextInit(ctx.sr);
   SRGate_ContextInit(ctx.srgate);
   SRMIT_ContextInit(ctx.srmit);
   SRGB_ContextInit(ctx.srgb);

   ctx.markers_ns = "MAJ";
   ctx.scan_id    = 0;
}

inline void WBWM_ContextExport(WBWorldContext &ctx)
{
   ExtLQ_ContextExport(ctx.ext_up);
   ExtLQ_Down_ContextExport(ctx.ext_dn);

   Hunter_UP_ContextExport(ctx.hunter_up);
   Hunter_DN_ContextExport(ctx.hunter_dn);
   HW_BB_ContextExport(ctx.hwbb);

   Race_ContextExport(ctx.race);
   C1Pre_ContextExport(ctx.c1pre);
   C1W2Gate_ContextExport(ctx.c1w2gate);
   SWGate_ContextExport(ctx.swgate);
   SB_ContextExport(ctx.sb);
   W3CG_ContextExport(ctx.w3cg);

   FSMS_ContextExport(ctx.fsms);
   FSMS_SW_ContextExport(ctx.fsms_sw);

   SR_ContextExport(ctx.sr);
   SRGate_ContextExport(ctx.srgate);
   SRMIT_ContextExport(ctx.srmit);
   SRGB_ContextExport(ctx.srgb);

   ctx.markers_ns = Markers_GetNamespace();
   ctx.scan_id    = g_scan_id;
}

inline void WBWM_ContextImport(const WBWorldContext &ctx)
{
   ExtLQ_ContextImport(ctx.ext_up);
   ExtLQ_Down_ContextImport(ctx.ext_dn);

   Hunter_UP_ContextImport(ctx.hunter_up);
   Hunter_DN_ContextImport(ctx.hunter_dn);
   HW_BB_ContextImport(ctx.hwbb);

   Race_ContextImport(ctx.race);
   C1Pre_ContextImport(ctx.c1pre);
   C1W2Gate_ContextImport(ctx.c1w2gate);
   SWGate_ContextImport(ctx.swgate);
   SB_ContextImport(ctx.sb);
   W3CG_ContextImport(ctx.w3cg);

   FSMS_ContextImport(ctx.fsms);
   FSMS_SW_ContextImport(ctx.fsms_sw);

   SR_ContextImport(ctx.sr);
   SRGate_ContextImport(ctx.srgate);
   SRMIT_ContextImport(ctx.srmit);
   SRGB_ContextImport(ctx.srgb);

   Markers_SetNamespace(ctx.markers_ns);
   g_scan_id = ctx.scan_id;
}

inline void WBWM_Init()
{
   if(g_wbwm_inited) return;

   WBWM_ContextInit(g_wbwm_major);
   WBWM_ContextInit(g_wbwm_minor);

   g_wbwm_minor_scan_seq     = 0;
   g_wbwm_minor_active       = false;
   g_wbwm_minor_scan_id      = 0;
   g_wbwm_minor_tag_suffix   = "";

   g_wbwm_last_maj_scan_id   = -1;
   g_wbwm_last_maj_time      = 0;

   FSMS_SW_RuntimeMinor_Clear();
   WBWM_MinorStop_Disarm();
   Markers_SetPreviewMode(false);

   if(!WBWM_MinorWorldEnabledOnThisChart())
      WBWM_DiscardPendingMinorStarterEvents();

   g_wbwm_inited = true;
}

// Delete only objects that belong to the current prefix (current g_scan_id + namespace)
inline void WBWM_DeleteAllObjects_CurrentScan()
{
   const string p    = __ScanPrefix();
   const int    plen = StringLen(p);

   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "" || StringLen(on) < plen) continue;
      if(StringSubstr(on, 0, plen) != p)   continue;
      ObjectDelete(0, on);
   }
}

inline int __WBWM_FindMinorOffIndex(const MqlRates &rates[], const int n,
                                   const int starter_idx,
                                   const double off_level_1,
                                   const double off_level_2)
{
   if(n<=0) return -1;
   int from = starter_idx + 1;
   if(from < 0) from = 0;

   for(int i=from; i<n; ++i)
   {
      const double low  = rates[i].low;
      const double high = rates[i].high;

      bool crossed = false;

      if(off_level_1 > 0.0)
      {
         if(low <= off_level_1 && high >= off_level_1)
            crossed = true;
      }
      if(!crossed && off_level_2 > 0.0)
      {
         if(low <= off_level_2 && high >= off_level_2)
            crossed = true;
      }

      if(crossed) return i;
   }
   return -1;
}

// Apply initial ext LQ for minor world WITHOUT drawing any lines.
inline void __WBWM_ApplyMinorInitialExtLQ_NoDraw(const FSMS_SW_MinorSession &s)
{
   // reset both sides first
   ExtLQContext u;
   __WBWM_InitExtLQUpContext(u);
   ExtLQ_ContextImport(u);

   ExtLQDownContext d;
   ExtLQ_Down_ContextReset(d);
   ExtLQ_Down_ContextImport(d);

   if(s.ext_init_price <= 0.0 || s.ext_init_time <= 0) return;

   if(s.dir == DIR_UP)
   {
      ExtLQContext e;
      __WBWM_InitExtLQUpContext(e);
      e.ext_has   = true;
      e.ext_price = s.ext_init_price;
      e.ext_time  = s.ext_init_time;
      ExtLQ_ContextImport(e);

      Hunter_OnExtLQUpdated();
   }
   else
   {
      ExtLQDownContext ed;
      ExtLQ_Down_ContextReset(ed);
      ed.ext_has   = true;
      ed.ext_price = s.ext_init_price;
      ed.ext_time  = s.ext_init_time;
      ExtLQ_Down_ContextImport(ed);

      Hunter_Down_OnExtLQUpdated();
   }
}

inline bool __WBWM_IsSameMinorSession(const FSMS_SW_MinorSession &a,
                                       const FSMS_SW_MinorSession &b)
{
   if(!a.used || !b.used) return false;
   if(a.dir != b.dir) return false;
   if(a.tag != b.tag) return false;
   if(a.starter_time != b.starter_time) return false;
   return true;
}

inline void WBWM_MinorSession_Activate(const FSMS_SW_MinorSession &s)
{
   g_wbwm_minor_active     = true;
   g_wbwm_minor_sess       = s;
   g_wbwm_minor_scan_id    = (1000000 + (++g_wbwm_minor_scan_seq));
   g_wbwm_minor_tag_suffix = "_minor_" + s.tag;

   WBWM_MinorStop_Arm(s.starter_time, s.off_level_1, s.off_level_2);
}

inline void WBWM_MinorSession_Deactivate()
{
   g_wbwm_minor_active     = false;
   g_wbwm_minor_scan_id    = 0;
   g_wbwm_minor_tag_suffix = "";
   WBWM_MinorStop_Disarm();
   FSMS_SW_RuntimeMinor_Clear();
   Markers_SetPreviewMode(false);

   WBWM_ContextInit(g_wbwm_minor);
   g_wbwm_minor.markers_ns = "MIN";
   g_wbwm_minor.scan_id    = 0;
}

inline void WBWM_ExpireMinorLineageInCurrentWorld(const FSMS_SW_MinorSession &s)
{
   if(!s.used) return;
   if(s.starter_time <= 0) return;

   const int dir_code = (s.dir == DIR_UP ? 0 : 1);

   SRMIT_ExpireMinorLineages(dir_code, s.starter_time);
   SRGB_ExpireMinorLineages(dir_code, s.starter_time);
}

inline void WBWM_DeleteMinorLiveOnlyObjects_CurrentScan()
{
   const string p    = __ScanPrefix();
   const int    plen = StringLen(p);

   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "" || StringLen(on) < plen) continue;
      if(StringSubstr(on, 0, plen) != p)   continue;

      string tail = StringSubstr(on, plen);
      bool kill = false;

      if(StringFind(tail, "SR_") == 0 ||
         StringFind(tail, "STRONG_RANGE_") == 0 ||
         StringFind(tail, "StrongRange_") == 0 ||
         StringFind(tail, "SRANGE_") == 0 ||
         StringFind(tail, "first_SR_mitigator_") == 0 ||
         StringFind(tail, "deepest_SR_mitigation_") == 0 ||
         StringFind(tail, "unmitigated_SR_") == 0 ||
         StringFind(tail, "RACE_START_HWBB_") == 0 ||
         StringFind(tail, "SHADOW_BREAK_") == 0 ||
         StringFind(tail, "temp-c1-sw_") == 0 ||
         StringFind(tail, "invalidator_") == 0)
      {
         kill = true;
      }

      if(kill)
         ObjectDelete(0, on);
   }
}

inline void WBWM_FinalizeMinorArchive(const FSMS_SW_MinorSession &closed_s,
                                      const int minor_scan_id,
                                      const string tag_suffix,
                                      const int maj_scan_id,
                                      const datetime major_to_time)
{
   if(!closed_s.used) return;
   if(minor_scan_id <= 0) return;
   if(closed_s.starter_time <= 0) return;

   datetime final_to_time = closed_s.off_time;
   if(final_to_time > closed_s.starter_time)
      final_to_time -= 1;   // candle MinorOff خودش دیگر جزو منطق MIN نیست

   if(final_to_time <= 0)
      final_to_time = major_to_time;
   if(final_to_time <= 0)
      final_to_time = closed_s.starter_time;
   if(final_to_time < closed_s.starter_time)
      final_to_time = closed_s.starter_time;

   WBWM_ContextExport(g_wbwm_major);

   WBWM_ContextInit(g_wbwm_minor);
   g_wbwm_minor.markers_ns = "MIN";
   g_wbwm_minor.scan_id    = minor_scan_id;
   WBWM_ContextImport(g_wbwm_minor);
   Markers_SetPreviewMode(false);

   WBWM_DeleteAllObjects_CurrentScan();
   __WBWM_ApplyMinorInitialExtLQ_NoDraw(closed_s);
   FSMS_SW_RuntimeMinor_Set(closed_s);

   const ENUM_TIMEFRAMES runtime_tf = __WBWM_RuntimeTF();

   if(closed_s.dir == DIR_UP)
   {
      API_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf,
                                       closed_s.starter_time,
                                       final_to_time,
                                       true,
                                       closed_s.ext_init_price,
                                       closed_s.ext_init_time,
                                       tag_suffix,
                                       false);
   }
   else
   {
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf,
                                            closed_s.starter_time,
                                            final_to_time,
                                            true,
                                            closed_s.ext_init_price,
                                            closed_s.ext_init_time,
                                            tag_suffix,
                                            false);
   }

   FSMS_SW_RuntimeMinor_Clear();
   WBWM_DeleteMinorLiveOnlyObjects_CurrentScan();
   Markers_SetPreviewMode(false);

   WBWM_ContextImport(g_wbwm_major);
   Markers_SetNamespace("MAJ");
   g_scan_id = maj_scan_id;
}

// ------------------------------------------------------------------
// MAIN entry: called from MAJ API loops after FSMS_SW_OnBarCtx()
// Signature must match API calls: (rates,n,upto_j,to_time)
// ------------------------------------------------------------------
inline void WBWM_ProcessMinorStarterEvents(const MqlRates &rates[],
                                          const int n,
                                          const int upto_j,
                                          const datetime major_to_time)
{
   if(!g_wbwm_inited)
      WBWM_Init();

   // M1 and M15 both run the normal/main scan only.
   // When disabled, drain any stale MinorStarter pulse and never activate MIN.
   if(!WBWM_MinorWorldEnabledOnThisChart())
   {
      WBWM_DiscardPendingMinorStarterEvents();
      if(g_wbwm_minor_active)
         WBWM_MinorSession_Deactivate();
      return;
   }

   // Only MAJ drives MIN (never run inside MIN)
   if(Markers_GetNamespace() != "MAJ")
      return;

   if(n <= 0 || upto_j < 0 || upto_j >= n)
      return;

   // guard: prevent double-call on the same bar within the same MAJ scan
   const int      maj_scan_id = g_scan_id;
   const datetime maj_t       = rates[upto_j].time;

   if(g_wbwm_last_maj_scan_id == maj_scan_id && g_wbwm_last_maj_time == maj_t)
      return;

   g_wbwm_last_maj_scan_id = maj_scan_id;
   g_wbwm_last_maj_time    = maj_t;

   // --- 1) Consume ALL pending starter events (keep the latest) ---
   bool have_new_starter = false;
   FSMS_SW_MinorSession latest_start;
   FSMS_SW_MinorSession s;

   while(FSMS_SW_PopMinorStartEvent(s))
   {
      if(!s.used) continue;
      if(s.starter_time <= 0) continue;

      latest_start      = s;
      have_new_starter  = true;
   }

   // If a new starter arrived while another MIN session was active,
   // finalize/archive the previous MIN session BEFORE switching to the new one.
   if(have_new_starter)
   {
      if(g_wbwm_minor_active && !__WBWM_IsSameMinorSession(g_wbwm_minor_sess, latest_start))
      {
         FSMS_SW_MinorSession prev_closed = g_wbwm_minor_sess;
         FSMS_SW_MinorSession prev_saved;

         if(FSMS_SW_Session_FindByTagDir(prev_closed.tag, prev_closed.dir, prev_saved))
            prev_closed = prev_saved;

         if(prev_closed.off_time <= 0)
            prev_closed.off_time = latest_start.starter_time;
         if(prev_closed.off_idx < 0)
            prev_closed.off_idx = latest_start.starter_idx;

         WBWM_FinalizeMinorArchive(prev_closed,
                                   g_wbwm_minor_scan_id,
                                   g_wbwm_minor_tag_suffix,
                                   maj_scan_id,
                                   major_to_time);

         WBWM_ExpireMinorLineageInCurrentWorld(prev_closed);
         WBWM_MinorSession_Deactivate();
      }

      WBWM_MinorSession_Activate(latest_start);
   }

   // --- 2) If MIN is active: STOP immediately when MAJ session is closed (MinorOff) ---
   if(g_wbwm_minor_active)
   {
      // if the MAJ session is no longer open => finalize archive now and kill MIN logic
      if(FSMS_SW_Session_FindOpen(g_wbwm_minor_sess.tag, g_wbwm_minor_sess.dir) < 0)
      {
         FSMS_SW_MinorSession closed_s = g_wbwm_minor_sess;
         FSMS_SW_MinorSession saved_s;

         if(FSMS_SW_Session_FindByTagDir(closed_s.tag, closed_s.dir, saved_s))
            closed_s = saved_s;

         WBWM_FinalizeMinorArchive(closed_s,
                                   g_wbwm_minor_scan_id,
                                   g_wbwm_minor_tag_suffix,
                                   maj_scan_id,
                                   major_to_time);

         WBWM_ExpireMinorLineageInCurrentWorld(closed_s);
         WBWM_MinorSession_Deactivate();

         // hard safety: MAJ must remain MAJ
         Markers_SetNamespace("MAJ");
         g_scan_id = maj_scan_id;
         return;
      }

      // --- 3) Run MIN step only up to THIS MAJ candle time ---
      datetime step_to_time = maj_t;
      if(major_to_time > 0 && step_to_time > major_to_time)
         step_to_time = major_to_time;

      if(step_to_time < g_wbwm_minor_sess.starter_time)
         return;

      // Export MAJ snapshot (so MAJ continues with no side effects)
      WBWM_ContextExport(g_wbwm_major);

      // Build a clean MIN world for this candle-step
      WBWM_ContextInit(g_wbwm_minor);
      g_wbwm_minor.markers_ns = "MIN";
      g_wbwm_minor.scan_id    = g_wbwm_minor_scan_id;
      WBWM_ContextImport(g_wbwm_minor);

      // Clear previous MIN objects of THIS session (to avoid orphan objects during rescan)
      WBWM_DeleteAllObjects_CurrentScan();

      // Apply initial extLQ anchor for MIN logic (no draw)
      __WBWM_ApplyMinorInitialExtLQ_NoDraw(g_wbwm_minor_sess);
      FSMS_SW_RuntimeMinor_Set(g_wbwm_minor_sess);
      Markers_SetPreviewMode(true);

      // Run MIN scan up to current candle (NO bump scan id)
      const ENUM_TIMEFRAMES runtime_tf = __WBWM_RuntimeTF();

      if(g_wbwm_minor_sess.dir == DIR_UP)
      {
         API_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf,
                                          g_wbwm_minor_sess.starter_time,
                                          step_to_time,
                                          true,
                                          g_wbwm_minor_sess.ext_init_price,
                                          g_wbwm_minor_sess.ext_init_time,
                                          g_wbwm_minor_tag_suffix,
                                          false);
      }
      else
      {
         API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf,
                                               g_wbwm_minor_sess.starter_time,
                                               step_to_time,
                                               true,
                                               g_wbwm_minor_sess.ext_init_price,
                                               g_wbwm_minor_sess.ext_init_time,
                                               g_wbwm_minor_tag_suffix,
                                               false);
      }

      FSMS_SW_RuntimeMinor_Clear();
      WBWM_DeleteAllObjects_CurrentScan();
      Markers_SetPreviewMode(false);

      // Restore MAJ snapshot
      WBWM_ContextImport(g_wbwm_major);

      // HARD safety: force MAJ back (even if something leaked)
      Markers_SetNamespace("MAJ");
      g_scan_id = maj_scan_id;
   }
}

#endif // WAVEBOT_WORLDMANAGER_MQH
