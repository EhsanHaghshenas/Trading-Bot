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

// ------------------------------------------------------------------
// Forward declarations (برای جلوگیری از include-cycle)
// ------------------------------------------------------------------
int API_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
                                     const datetime from_time, const datetime to_time,
                                     const bool init_ext,
                                     const double init_ext_price,
                                     const datetime init_ext_time,
                                     const string tag_suffix);

int API_Down_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
                                          const datetime from_time, const datetime to_time,
                                          const bool init_ext,
                                          const double init_ext_price,
                                          const datetime init_ext_time,
                                          const string tag_suffix);

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
   g_wbwm_inited = true;
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

// ------------------------------------------------------------------
// MAIN entry: call from MAJ API loops after FSMS_SW_OnBarCtx()
// ------------------------------------------------------------------
inline void WBWM_ProcessMinorStarterEvents(const MqlRates &rates[], const int n, const datetime major_to_time)
{
   WBWM_Init();

   // prevent recursion: only in MAJ world
   if(Markers_GetNamespace() != "MAJ")
      return;

   FSMS_SW_MinorSession s;
   while(FSMS_SW_PopMinorStartEvent(s))
   {
      if(!s.used) continue;
      if(s.starter_time <= 0) continue;

      datetime from_time = s.starter_time;
      datetime to_time   = major_to_time;

      int off_idx = __WBWM_FindMinorOffIndex(rates, n, s.starter_idx, s.off_level_1, s.off_level_2);
      if(off_idx >= 0 && off_idx < n)
         to_time = rates[off_idx].time;

      if(to_time < from_time)
      {
         datetime tmp = from_time;
         from_time = to_time;
         to_time   = tmp;
      }

      // 1) export MAJ world
      WBWM_ContextExport(g_wbwm_major);

      // 2) import fresh MIN world
      WBWM_ContextInit(g_wbwm_minor);
      g_wbwm_minor.markers_ns = "MIN";
      g_wbwm_minor.scan_id    = (1000000 + (++g_wbwm_minor_scan_seq));
      WBWM_ContextImport(g_wbwm_minor);

      // 3) apply initial minor extLQ (no draw)
      __WBWM_ApplyMinorInitialExtLQ_NoDraw(s);

      // 4) run minor scan
      string suffix = "_minor_" + s.tag;
      if(s.dir == DIR_UP)
         API_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, from_time, to_time, false, 0.0, 0, suffix);
      else
         API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, from_time, to_time, false, 0.0, 0, suffix);

      // 5) keep MIN snapshot updated (optional)
      WBWM_ContextExport(g_wbwm_minor);

      // 6) restore MAJ world
      WBWM_ContextImport(g_wbwm_major);
   }
}

#endif // WAVEBOT_WORLDMANAGER_MQH
