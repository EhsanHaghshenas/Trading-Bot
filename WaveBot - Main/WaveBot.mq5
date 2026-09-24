#property strict
#property description "WaveBot - M15 market-structure analysis only; no bridge, triggers, trades or execution"

#include <WaveBot/Types.mqh>

// ===== Market-analysis configuration =====
input string           InpSymbol                   = "EURUSD";
input bool             InpEnableCentralMultiSymbol = true;
input string           InpMultiSymbolList          = "EURUSD,USDCAD,AUDUSD";
input bool             InpDrawOnlyChartSymbol      = true;
input int              InpLookbackBars             = 20000;
input int              InpMaxBarsInWave            = 1000;
input bool             InpDrawMarkers              = true;
input bool             InpDebugPrints              = true;
input Direction        InpDirection                = DIR_DOWN;
input datetime         InpScanFromDate             = D'2020.01.01 00:00:00';
input datetime         InpStatementCloseDate        = D'2020.12.21 10:00:00';
input bool             InpRequireCloseBreakAboveW2H1 = true;
input bool             InpDrawExtLQ                = false;
input color            InpExtLQColor               = clrMagenta;
input bool             InpEnableHunterMarkers      = true;
input bool             InpRunShadowBreakerOnce     = false;

// The former signal engine's M1 role no longer exists.
// Keep this name for existing structural modules that reference it.
const ENUM_TIMEFRAMES InpTF = PERIOD_M15;

string g_wb_active_symbol = "";
int g_scan_id = 0;
bool g_once = false;
bool g_sb_ran = false;

inline string WB_PrimaryInputSymbol()
{
   string s = InpSymbol;
   if(s == "") s = _Symbol;
   if(s == "") s = "EURUSD";
   return s;
}

inline string WB_ActiveSymbol()
{
   if(g_wb_active_symbol != "")
      return g_wb_active_symbol;
   return WB_PrimaryInputSymbol();
}

inline void WB_SetActiveSymbol(const string sym)
{
   g_wb_active_symbol = sym;
}

inline bool WB_IsPrimaryVisualSymbol()
{
   string s = WB_ActiveSymbol();
   return (s == _Symbol);
}

inline bool WB_RuntimeAllowMarkerRender()
{
   return (!InpDrawOnlyChartSymbol || WB_IsPrimaryVisualSymbol());
}

#define InpSymbol WB_ActiveSymbol()

#include <WaveBot/Utils.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/API.mqh>
#include <WaveBot/API_Down.mqh>
#include <WaveBot/Bootstrap.mqh>
#include <WaveBot/SWGate.mqh>
#include <WaveBot/ShadowBreaker.mqh>
#include <WaveBot/W3ChainGuard.mqh>

inline void ResolveWindow(datetime &start, datetime &stop)
{
   start = InpScanFromDate;
   if(start <= 0) start = TimeCurrent();
   stop = InpStatementCloseDate;
   if(stop <= 0) stop = TimeCurrent();
   if(stop < start) stop = start;
}

inline void WB_ApplyHiddenVisualPolicies()
{
   ExtLQ_DeleteAllVisuals_AllScans();
   ExtLQ_Down_DeleteAllVisuals_AllScans();
   Race_DeleteRefVisuals_AllScans();
}

inline void WB_ResetMarketWorld()
{
   ExtLQContext up;
   up.ext_has = false; up.ext_price=0.0; up.ext_time=0;
   ArrayResize(up.hist,0); up.prev_idx=-1;
   ExtLQ_ContextImport(up);

   ExtLQDownContext dn;
   ExtLQ_Down_ContextReset(dn);
   ExtLQ_Down_ContextImport(dn);

   Hunter_UP_ResetGlobals();
   Hunter_DN_ResetGlobals();
   HW_BB_ResetGlobals();

   RaceContext rc;
   Race_ContextReset(rc);
   Race_ContextImport(rc);

   C1Pre_ResetGlobals();
   C1W2Gate_ResetGlobals();
   SWGate_ResetGlobals();
   SB_ResetGlobals();
   W3CG_ResetGlobals();


   SR_ResetGlobals();
   SRMIT_ResetGlobals();

   SR_AllowBoth();
}

inline void WB_RunMarketScan(const string sym,
                             const datetime start,
                             const datetime stop)
{
   BootOutcome boot = Bootstrap_RaceDetect(sym, PERIOD_M15, start, stop);
   Direction direction = InpDirection;
   datetime resume = start;
   if(boot.ok)
   {
      direction = boot.mode;
      resume = boot.complete_time + PeriodSeconds(PERIOD_M15);
      if(InpDebugPrints)
         Print("[WB-ANALYSIS-BOOT] Symbol=",sym,
               " | winner=",(direction==DIR_UP?"UP":"DOWN"),
               " | resume=",TimeToString(resume,TIME_DATE|TIME_SECONDS));
   }
   else if(InpDebugPrints)
      Print("[WB-ANALYSIS-BOOT] Symbol=",sym," | fallback direction used.");

   if(resume > stop) return;
   if(direction == DIR_UP)
      API_RunScanSequential_W2W3_Hunter(sym,PERIOD_M15,resume,stop);
   else
      API_Down_RunScanSequential_W2W3_Hunter(sym,PERIOD_M15,resume,stop);
}

#define WB_MAX_ANALYSIS_SYMBOLS 12
string g_wb_symbols[];
int g_wb_symbol_count=0;

inline string WB_TrimSymbol(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

inline void WB_SelectAnalysisSymbols()
{
   ArrayResize(g_wb_symbols,0);
   g_wb_symbol_count=0;
   string src = (InpEnableCentralMultiSymbol ? InpMultiSymbolList : WB_PrimaryInputSymbol());
   if(src == "") src = WB_PrimaryInputSymbol();
   string pieces[];
   int n=StringSplit(src,',',pieces);
   for(int i=0;i<n && g_wb_symbol_count<WB_MAX_ANALYSIS_SYMBOLS;i++)
   {
      string sym=WB_TrimSymbol(pieces[i]);
      if(sym == "") continue;
      bool seen=false;
      for(int j=0;j<g_wb_symbol_count;j++)
         if(g_wb_symbols[j]==sym){seen=true;break;}
      if(seen) continue;
      int k=g_wb_symbol_count;
      ArrayResize(g_wb_symbols,k+1);
      g_wb_symbols[k]=sym;
      g_wb_symbol_count++;
   }
   if(g_wb_symbol_count==0)
   {
      ArrayResize(g_wb_symbols,1);
      g_wb_symbols[0]=WB_PrimaryInputSymbol();
      g_wb_symbol_count=1;
   }
   for(int i=0;i<g_wb_symbol_count;i++)
      SymbolSelect(g_wb_symbols[i],true);
}

inline void WB_RunAllMarketScans()
{
   datetime start=0,stop=0;
   ResolveWindow(start,stop);
   // As in the baseline: preview non-primary symbols first, primary last.
   for(int pass=0;pass<2;pass++)
      for(int i=0;i<g_wb_symbol_count;i++)
      {
         string sym=g_wb_symbols[i];
         bool primary=(sym==WB_PrimaryInputSymbol() || sym==_Symbol);
         if((pass==1)!=primary) continue;
         WB_SetActiveSymbol(sym);
         Markers_SetNamespace("MAJ");
         WB_ResetMarketWorld();
         Markers_SetPreviewMode(InpDrawOnlyChartSymbol && !primary);
         datetime sym_stop=stop;
         if(InpStatementCloseDate<=0)
         {
            datetime last_closed=iTime(sym,PERIOD_M15,1);
            if(last_closed>0 && last_closed<sym_stop) sym_stop=last_closed;
         }
         if(InpDebugPrints)
            Print("[WB-ANALYSIS] Start ",sym," M15 from ",TimeToString(start,TIME_DATE|TIME_SECONDS),
                  " to ",TimeToString(sym_stop,TIME_DATE|TIME_SECONDS));
         WB_RunMarketScan(sym,start,sym_stop);
      }
   Markers_SetPreviewMode(false);
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
   g_once=true;
   EventKillTimer();
   if(InpDebugPrints)
      Print("[WB-ANALYSIS] Market-only historical M15 pass completed. No trade or signal files.");
   // Do not forcibly remove the EA: leave final analytical markers visible.
}

int OnInit()
{
   if((ENUM_TIMEFRAMES)Period()!=PERIOD_M15)
   {
      Print("[WB-ANALYSIS] Attach to an M15 chart. The M1 signal/trade engine has been removed.");
      return INIT_FAILED;
   }
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
   WB_SelectAnalysisSymbols();
   Markers_SetNamespace("MAJ");
   Markers_SetPreviewMode(false);

   WB_ResetMarketWorld();
   Markers_DeleteObsoleteObjects();
   WB_ApplyHiddenVisualPolicies();

   EventSetTimer(2);
   return INIT_SUCCEEDED;
}

void OnTick() {}

void OnTimer()
{
   if(g_once){EventKillTimer();return;}
   Markers_SetNamespace("MAJ");
   WB_ApplyHiddenVisualPolicies();

   if(InpRunShadowBreakerOnce && !g_sb_ran)
   {
      datetime start=0,stop=0;
      ResolveWindow(start,stop);
      API_RunScanSequential_W2W3_Hunter(InpSymbol,PERIOD_M15,start,stop);
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol,PERIOD_M15,start,stop);
      g_sb_ran=true;
      // Original one-shot mode is analysis-only and does not bypass the normal scan.
      WB_ResetMarketWorld();
   }
   WB_RunAllMarketScans();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Markers_SetPreviewMode(false);
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
   WB_ApplyHiddenVisualPolicies();

}
