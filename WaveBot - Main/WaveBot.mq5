#property strict
#property description "WaveBot M1/M15 selectable independent market-structure analysis (no trading)"

#include <WaveBot/Types.mqh>

// Only the supported analysis periods appear in the FIRST EA input dropdown.
// Select M1 on an M1 chart and M15 on an M15 chart. An accidental mismatch
// fails clearly instead of silently drawing candles from the wrong period.
enum WB_ANALYSIS_TIMEFRAME
{
   WB_ANALYSIS_M1  = 1,   // 1 minute (M1)
   WB_ANALYSIS_M15 = 15   // 15 minutes (M15)
};

input WB_ANALYSIS_TIMEFRAME InpAnalysisTimeframe = WB_ANALYSIS_M15; // 01. Analysis Timeframe (M1/M15)

// ===== Market-analysis configuration =====
input string           InpSymbol                   = ""; // empty = symbol of the attached chart
input bool             InpEnableCentralMultiSymbol = false; // per-chart analysis by default; legacy preview is optional
input string           InpMultiSymbolList          = "EURUSD,USDCAD,AUDUSD";
input bool             InpDrawOnlyChartSymbol      = true;
input int              InpLookbackBars             = 20000;
input int              InpMaxBarsInWave            = 1000;
input bool             InpDrawMarkers              = true;
input bool             InpDebugPrints              = true;
input Direction        InpDirection                = DIR_DOWN;
input datetime         InpScanFromDate             = D'2026.01.01 00:00:00'; // adjustable start; older dates require complete MT5 history
input datetime         InpStatementCloseDate        = 0; // 0 = newest closed candle for selected timeframe
input bool             InpRequireCloseBreakAboveW2H1 = true;
input bool             InpDrawExtLQ                = false;
input color            InpExtLQColor               = clrMagenta;
input bool             InpEnableHunterMarkers      = true;
input bool             InpRunShadowBreakerOnce     = false;

// Single shared analysis engine; resolved from the FIRST EA dropdown.
// InpTF is retained as a runtime alias for structural modules (NOT an input).
// The period selection is confirmed against the actual attached chart.
ENUM_TIMEFRAMES InpTF = PERIOD_M15;
inline ENUM_TIMEFRAMES WB_RuntimeTF() { return InpTF; }
inline string WB_RuntimeTFName() { return EnumToString(WB_RuntimeTF()); }

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
   TC_ResetGlobals();
   IMB_ResetGlobals();

   SR_AllowBoth();
}

inline void WB_RunMarketScan(const string sym,
                             const datetime start,
                             const datetime stop)
{
   const ENUM_TIMEFRAMES tf = WB_RuntimeTF();
   BootOutcome boot = Bootstrap_RaceDetect(sym, tf, start, stop);
   Direction direction = InpDirection;
   datetime resume = start;
   if(boot.ok)
   {
      direction = boot.mode;
      resume = boot.complete_time + PeriodSeconds(tf);
      if(InpDebugPrints)
         Print("[WB-ANALYSIS-BOOT] Symbol=",sym,
               " | winner=",(direction==DIR_UP?"UP":"DOWN"),
               " | resume=",TimeToString(resume,TIME_DATE|TIME_SECONDS));
   }
   else if(InpDebugPrints)
      Print("[WB-ANALYSIS-BOOT] Symbol=",sym," | fallback direction used.");

   if(resume > stop) return;
   if(direction == DIR_UP)
      API_RunScanSequential_W2W3_Hunter(sym,tf,resume,stop);
   else
      API_Down_RunScanSequential_W2W3_Hunter(sym,tf,resume,stop);
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
   // For the default empty InpSymbol, the attached chart is always the
   // primary analysis target, even when omitted from the multi-symbol list.
   // Preserve an explicitly configured non-chart InpSymbol as a legacy mode.
   string primary=WB_PrimaryInputSymbol();
   if(InpEnableCentralMultiSymbol)
   {
      // Add the primary FIRST so it cannot be displaced by the 12-symbol cap.
      ArrayResize(g_wb_symbols,1);
      g_wb_symbols[0]=primary;
      g_wb_symbol_count=1;
   }
   string src=(InpEnableCentralMultiSymbol ? InpMultiSymbolList : primary);
   if(src=="") src=primary;
   string pieces[];
   int n=StringSplit(src,',',pieces);
   for(int i=0;i<n && g_wb_symbol_count<WB_MAX_ANALYSIS_SYMBOLS;i++)
   {
      string sym=WB_TrimSymbol(pieces[i]);
      if(sym=="") continue;
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
      g_wb_symbols[0]=primary;
      g_wb_symbol_count=1;
   }
   for(int i=0;i<g_wb_symbol_count;i++)
      if(!SymbolSelect(g_wb_symbols[i],true) && InpDebugPrints)
         Print("[WB-ANALYSIS] Cannot select symbol: ",g_wb_symbols[i],
               " error=",GetLastError());
}

inline void WB_RunAllMarketScans()
{
   datetime start=0,stop=0;
   ResolveWindow(start,stop);
   const ENUM_TIMEFRAMES tf=WB_RuntimeTF();
   // Same chart-isolated engine on both timeframes: preview other symbols
   // first, then draw only the primary chart symbol (if requested).
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
            datetime last_closed=iTime(sym,tf,1);
            if(last_closed<=0)
            {
               Print("[WB-ANALYSIS] No completed history for ",sym," ",
                     WB_RuntimeTFName(),". Skipping this symbol.");
               continue;
            }
            if(last_closed<sym_stop) sym_stop=last_closed;
         }
         if(sym_stop<start)
         {
            if(InpDebugPrints)
               Print("[WB-ANALYSIS] No completed bars within selected window: ",
                     sym," ",WB_RuntimeTFName());
            continue;
         }
         // Warn, rather than silently claim an identical complete M1/M15
         // reconstruction when MT5 has not downloaded the requested bars.
         long first_loaded=0;
         if(SeriesInfoInteger(sym,tf,SERIES_FIRSTDATE,first_loaded) &&
            first_loaded>0 && (datetime)first_loaded > start+7*86400)
            Print("[WB-ANALYSIS] POSSIBLY INCOMPLETE HISTORY ",sym," ",WB_RuntimeTFName(),
                  " | requested=",TimeToString(start,TIME_DATE|TIME_SECONDS),
                  " | first available=",TimeToString((datetime)first_loaded,TIME_DATE|TIME_SECONDS));
         if(InpDebugPrints)
            Print("[WB-ANALYSIS] Start ",sym," ",WB_RuntimeTFName(),
                  " from ",TimeToString(start,TIME_DATE|TIME_SECONDS),
                  " to ",TimeToString(sym_stop,TIME_DATE|TIME_SECONDS));
         WB_RunMarketScan(sym,start,sym_stop);
         // TC/MTC are generated by the existing market engine. IMB uses their
         // completed event timeline to handle all three-bar gaps chronologically.
         IMB_RunConfirmedTrendScan(sym,tf,start,sym_stop);
      }
   Markers_SetPreviewMode(false);
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
   g_once=true;
   EventKillTimer();
   if(InpDebugPrints)
      Print("[WB-ANALYSIS] Market-only historical ",WB_RuntimeTFName(),
            " pass completed. No trade or signal files.");
   // Do not forcibly remove the EA: leave final analytical markers visible.
}

int OnInit()
{
   // The first input is the authority; enforce an exact chart match so both
   // attached EAs analyze and draw only on their respective chart periods.
   const ENUM_TIMEFRAMES selected_tf=(ENUM_TIMEFRAMES)InpAnalysisTimeframe;
   const ENUM_TIMEFRAMES chart_tf=(ENUM_TIMEFRAMES)Period();
   if(selected_tf!=PERIOD_M1 && selected_tf!=PERIOD_M15)
   {
      Print("[WB-ANALYSIS] Select M1 or M15 in the FIRST EA input.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(chart_tf!=selected_tf)
   {
      Print("[WB-ANALYSIS] Timeframe mismatch: EA input=",EnumToString(selected_tf),
            " while attached chart=",EnumToString(chart_tf),
            ". Change the FIRST input or attach to the matching chart.");
      return INIT_PARAMETERS_INCORRECT;
   }
   InpTF=selected_tf;
   if(InpDebugPrints)
      Print("[WB-ANALYSIS] Chart=",_Symbol," / ",EnumToString(chart_tf),
            " | Selected=",WB_RuntimeTFName()," | Independent analysis instance.");
   g_once=false;
   g_sb_ran=false;
   g_scan_id=0;
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
   WB_SelectAnalysisSymbols();
   Markers_SetNamespace("MAJ");
   Markers_SetPreviewMode(false);

   WB_ResetMarketWorld();
   // Chart-scoped: remove stale MAJ objects before rebuilding this chart's TF.
   // Never accesses another chart, so simultaneous M1 and M15 EAs are safe.
   Markers_DeletePreviousAnalysisScanObjects();
   Markers_DeleteObsoleteObjects();
   TC_DeletePreviousMarkers();
   IMB_DeletePreviousMarkers();
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
      const ENUM_TIMEFRAMES tf=WB_RuntimeTF();
      API_RunScanSequential_W2W3_Hunter(InpSymbol,tf,start,stop);
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol,tf,start,stop);
      g_sb_ran=true;
      // Original one-shot mode is analysis-only and does not bypass the normal scan.
      WB_ResetMarketWorld();
      // The diagnostic pass is not the actual market scan: remove its TC labels.
      TC_DeletePreviousMarkers();
      IMB_DeletePreviousMarkers();
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
