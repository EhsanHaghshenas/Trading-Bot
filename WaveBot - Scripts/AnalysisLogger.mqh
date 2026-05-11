
#ifndef WAVEBOT_ANALYSIS_LOGGER_MQH
#define WAVEBOT_ANALYSIS_LOGGER_MQH

#include <WaveBot/Types.mqh>

// ============================================================================
// AnalysisLogger.mqh
// Runtime CSV logger for full WaveBot post-analysis.
// All files are written under Terminal Common Files\WaveBot_Analysis_*.
// ============================================================================

#define WBA_FILE_RUN_MANIFEST       "01_WaveBot_RunManifest.csv"
#define WBA_FILE_CANDLES_M1         "02_WaveBot_Candles_M1.csv"
#define WBA_FILE_CANDLES_M15        "03_WaveBot_Candles_M15.csv"
#define WBA_FILE_M15_MAIN           "04_WaveBot_M15_MainSignals.csv"
#define WBA_FILE_M15_STAGE          "05_WaveBot_M15_ThreeStageGateEvents.csv"
#define WBA_FILE_M15_ZONES          "06_WaveBot_M15_Zones.csv"
#define WBA_FILE_BRIDGE             "07_WaveBot_M15_to_M1_BridgeEvents.csv"
#define WBA_FILE_M1_TRIGGERS        "08_WaveBot_M1_TriggerEvents.csv"
#define WBA_FILE_M1_REJECTED        "09_WaveBot_M1_RejectedTriggerCandidates.csv"
#define WBA_FILE_TRADES             "10_WaveBot_Trades.csv"
#define WBA_FILE_TRADE_PATH         "11_WaveBot_TradePath_M1.csv"
#define WBA_FILE_TRADE_MAE_MFE      "12_WaveBot_TradeMAE_MFE.csv"
#define WBA_FILE_EQUITY             "13_WaveBot_EquityCurve.csv"
#define WBA_FILE_SUMMARY            "14_WaveBot_StatementSummary.csv"
#define WBA_FILE_RESETS             "15_WaveBot_StateResets.csv"
#define WBA_FILE_FEATURES           "16_WaveBot_TradeFeatures.csv"
#define WBA_FILE_DEBUG              "17_WaveBot_DebugRawLog.txt"

static bool     g_wba_ready              = false;
static string   g_wba_symbol             = "";
static string   g_wba_run_id             = "";
static string   g_wba_folder             = "";
static datetime g_wba_from               = 0;
static datetime g_wba_to                 = 0;
static datetime g_wba_last_m1_exported   = 0;
static datetime g_wba_last_m15_exported  = 0;
static int      g_wba_debug_seq          = 0;
static int      g_wba_event_seq          = 0;
static int      g_wba_reset_seq          = 0;

// Current active M15->M1 context, set by Trigger.mqh while processing M1 bars.
static int       g_wba_ctx_seq        = -1;
static int       g_wba_ctx_kind       = 0;
static int       g_wba_ctx_ns         = 0;
static Direction g_wba_ctx_dir        = DIR_UP;
static datetime  g_wba_ctx_start_time = 0;
static datetime  g_wba_ctx_start_bar  = 0;

inline bool AnalysisLogger_IsReady()
{
   return (g_wba_ready && InpAnalysisLogEnabled);
}

inline string __WBA_Str(const string v)
{
   string s = v;
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\"", "\"\"");
   return "\"" + s + "\"";
}

inline string __WBA_Int(const int v){ return IntegerToString(v); }
inline string __WBA_Long(const long v){ return IntegerToString(v); }
inline string __WBA_Dbl(const double v, const int digits=5){ return DoubleToString(v, digits); }
inline string __WBA_Bool(const bool v){ return (v ? "1" : "0"); }

inline string __WBA_Time(const datetime t)
{
   if(t <= 0) return "";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

inline string __WBA_TimeCsv(const datetime t)
{
   return __WBA_Str(__WBA_Time(t));
}

inline string __WBA_Dir(const Direction dir)
{
   return (dir == DIR_UP ? "UP" : "DOWN");
}

inline string __WBA_TFTag(const ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1)  return "M1";
   if(tf == PERIOD_M5)  return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1)  return "H1";
   if(tf == PERIOD_H4)  return "H4";
   if(tf == PERIOD_D1)  return "D1";
   return IntegerToString((int)tf);
}

inline string AnalysisLogger_SignalKindName(const int kind)
{
   if(kind == 1)  return "HWX";
   if(kind == 2)  return "HWBB";
   if(kind == 3)  return "FSMS";
   if(kind == 4)  return "GOOZBAGHALI";
   if(kind == 10) return "MTC";
   if(kind == 11) return "MINORSTARTER";
   if(kind == 12) return "MINOROFF_ZONE";
   return "UNKNOWN";
}

inline string AnalysisLogger_NamespaceName(const int ns)
{
   if(ns == 1) return "MAJ";
   if(ns == 2) return "MIN";
   return "NONE";
}

inline bool AnalysisLogger_IsStartKind(const int kind)
{
   return (kind == 1 || kind == 2 || kind == 3 || kind == 4);
}

inline bool AnalysisLogger_IsStopKind(const int kind)
{
   return (kind == 10 || kind == 11 || kind == 12);
}

inline string __WBA_Sanitize(const string raw)
{
   string s = raw;
   StringReplace(s, " ", "_");
   StringReplace(s, ".", "_");
   StringReplace(s, ":", "_");
   StringReplace(s, "-", "_");
   StringReplace(s, "/", "_");
   StringReplace(s, "\\", "_");
   StringReplace(s, "#", "_");
   return s;
}

inline string __WBA_DateTag(const datetime t)
{
   if(t <= 0) return "NA";
   string s = TimeToString(t, TIME_DATE);
   StringReplace(s, ".", "-");
   return s;
}

inline string AnalysisLogger_ContextId(const int seq)
{
   if(seq < 0) return "";
   return g_wba_run_id + "_CTX_" + IntegerToString(seq);
}

inline string AnalysisLogger_ZoneId(const int seq)
{
   if(seq < 0) return "";
   return g_wba_run_id + "_ZONE_" + IntegerToString(seq);
}

inline string AnalysisLogger_TriggerId(const int type_id, const int serial, const datetime t)
{
   if(serial <= 0 && t <= 0) return "";
   return g_wba_run_id + "_TRG_T" + IntegerToString(type_id) + "_" + IntegerToString(serial) + "_" + IntegerToString((int)t);
}

inline string AnalysisLogger_TradeId(const int exec_index)
{
   if(exec_index <= 0) return "";
   return g_wba_run_id + "_TRD_" + IntegerToString(exec_index);
}

inline double AnalysisLogger_PipSize(const string sym)
{
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(pt <= 0.0) pt = _Point;
   int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(dg <= 0) dg = _Digits;
   if(dg == 3 || dg == 5) return (pt * 10.0);
   return pt;
}

inline double AnalysisLogger_ToPips(const string sym, const double dist)
{
   double p = AnalysisLogger_PipSize(sym);
   if(p <= 0.0) return 0.0;
   return (dist / p);
}

inline int __WBA_OpenAppend(const string file_name)
{
   if(!AnalysisLogger_IsReady()) return INVALID_HANDLE;
   string path = g_wba_folder + "\\" + file_name;
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return INVALID_HANDLE;
   FileSeek(h, 0, SEEK_END);
   return h;
}

inline int AnalysisLogger_OpenRewrite(const string file_name, const string header)
{
   if(!AnalysisLogger_IsReady()) return INVALID_HANDLE;
   string path = g_wba_folder + "\\" + file_name;
   int h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return INVALID_HANDLE;
   if(header != "")
      FileWriteString(h, header + "\r\n");
   return h;
}

inline void AnalysisLogger_WriteRaw(const int handle, const string line)
{
   if(handle == INVALID_HANDLE) return;
   FileWriteString(handle, line + "\r\n");
}

inline void AnalysisLogger_Close(const int handle)
{
   if(handle == INVALID_HANDLE) return;
   FileFlush(handle);
   FileClose(handle);
}

inline void AnalysisLogger_AppendRaw(const string file_name, const string line)
{
   int h = __WBA_OpenAppend(file_name);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, line + "\r\n");
   FileFlush(h);
   FileClose(h);
}

inline string AnalysisLogger_HeaderRunManifest()
{
   return "run_id,symbol,date_from,date_to,broker_server_timezone,initial_balance,account_currency,risk_percent,rr_multiple,ea_version,code_version_tag,input_direction,use_most_recent_only,use_months_ago,months_ago,scan_from_date,enable_trigger_statement,spread_mode,commission_mode,created_at";
}
inline string AnalysisLogger_HeaderCandles()
{
   return "run_id,symbol,timeframe,bar_index,time,open,high,low,close,tick_volume,real_volume,spread";
}
inline string AnalysisLogger_HeaderM15MainSignals()
{
   return "run_id,context_id,event_id,symbol,timeframe,event_time,bar_index_m15,direction,event_action,main_signal_type,source_module,signal_name,open,high,low,close,off_reason,is_context_open,comment";
}
inline string AnalysisLogger_HeaderM15Stage()
{
   return "run_id,context_id,zone_id,event_id,symbol,timeframe,event_time,bar_index_m15,direction,main_signal_type,stage_event,flip_source,flip_type,flip_kind,flip_bar_index,flip_time,flip_open,flip_high,flip_low,flip_close,broken_bar_index,broken_time,broken_open,broken_high,broken_low,broken_close,zone_low,zone_high,zone_width_pips,invalid_level,touch_price,m1_start_time,reset_reason,comment";
}
inline string AnalysisLogger_HeaderM15Zones()
{
   return "run_id,context_id,zone_id,symbol,direction,main_signal_type,zone_source,zone_type,flip_time,flip_bar_index,flip_low,flip_high,broken_time,broken_bar_index,broken_low,broken_high,zone_low,zone_high,zone_width_pips,invalid_level,created_time,retouch_time,retouch_bar_index,sent_to_m1,sent_to_m1_time,invalidated,invalidated_time,invalidated_reason,main_off_time,final_status";
}
inline string AnalysisLogger_HeaderBridge()
{
   return "run_id,bridge_event_id,context_id,zone_id,symbol,direction,event_action,event_time_m15,event_bar_index_m15,received_time_m1,received_bar_index_m1,main_signal_type,zone_type,active_from_time_m1,active_from_bar_index_m1,active_to_time_m1,active_to_bar_index_m1,off_reason,payload_comment";
}
inline string AnalysisLogger_HeaderM1Triggers()
{
   return "run_id,trigger_id,context_id,zone_id,symbol,timeframe,direction,trigger_type,trigger_name,trigger_kind,trigger_time,trigger_bar_index_m1,trigger_open,trigger_high,trigger_low,trigger_close,entry_price,sl_price,tp_price,risk_pips,rr_multiple,valid_sltp,executed_as_trade,trade_id,rejection_reason,m15_main_signal_type,m15_zone_type,m15_zone_low,m15_zone_high,m15_zone_width_pips,bars_after_m1_start,minutes_after_m1_start,comment";
}
inline string AnalysisLogger_HeaderRejected()
{
   return "run_id,candidate_id,context_id,zone_id,symbol,timeframe,direction,candidate_type,candidate_name,candidate_time,candidate_bar_index_m1,open,high,low,close,would_be_entry,would_be_sl,would_be_tp,would_be_risk_pips,valid_sltp,rejection_reason,m15_main_signal_type,m15_zone_type,bars_after_m1_start,comment";
}
inline string AnalysisLogger_HeaderTrades()
{
   return "run_id,trade_id,trigger_id,context_id,zone_id,symbol,direction,trigger_type,trigger_name,main_signal_type,m15_zone_type,open_time,open_bar_index_m1,entry_price,sl_price,tp_price,lot_size,risk_percent,risk_money,risk_pips,rr_multiple,spread_at_entry,commission,swap,close_time,close_bar_index_m1,close_price,exit_reason,profit_money,profit_pips,result_R,is_win,is_loss,duration_minutes,duration_bars_m1,balance_before,balance_after,equity_before,equity_after,max_adverse_pips,max_favorable_pips,mae_R,mfe_R,comment";
}
inline string AnalysisLogger_HeaderTradePath()
{
   return "run_id,trade_id,symbol,direction,time,bar_index_m1,open,high,low,close,entry_price,sl_price,tp_price,floating_pips_at_close,floating_R_at_close,adverse_pips_this_bar,favorable_pips_this_bar,mae_R_so_far,mfe_R_so_far,distance_to_sl_pips,distance_to_tp_pips,inside_m15_zone,comment";
}
inline string AnalysisLogger_HeaderTradeMAEMFE()
{
   return "run_id,trade_id,max_adverse_pips,max_favorable_pips,mae_R,mfe_R,time_of_mae,time_of_mfe,bar_index_mae_m1,bar_index_mfe_m1";
}
inline string AnalysisLogger_HeaderEquity()
{
   return "run_id,symbol,time,bar_index_m1,balance,equity,floating_profit,closed_profit,open_trade_id,drawdown_money,drawdown_percent,peak_equity,consecutive_wins,consecutive_losses,comment";
}
inline string AnalysisLogger_HeaderSummary()
{
   return "run_id,symbol,date_from,date_to,total_trades,wins,losses,win_rate,gross_profit,gross_loss,net_profit,profit_factor,average_win,average_loss,average_R,expectancy_R,max_drawdown_money,max_drawdown_percent,max_consecutive_wins,max_consecutive_losses,largest_win,largest_loss,sharpe_like_metric,recovery_factor,comment";
}
inline string AnalysisLogger_HeaderResets()
{
   return "run_id,event_id,time,timeframe,bar_index,module_name,context_id,zone_id,trigger_id,old_state,new_state,reset_reason,direction,comment";
}
inline string AnalysisLogger_HeaderFeatures()
{
   return "run_id,trade_id,context_id,zone_id,trigger_id,symbol,direction,result_R,is_win,main_signal_type,m15_zone_type,m15_zone_width_pips,m15_flip_candle_range_pips,m15_broken_candle_range_pips,m15_retouch_depth_percent,m1_trigger_type,m1_trigger_candle_range_pips,risk_pips,entry_to_zone_low_pips,entry_to_zone_high_pips,bars_from_m15_main_to_flip,bars_from_flip_to_retouch,bars_from_retouch_to_m1_trigger,bars_from_entry_to_exit,hour_of_day,day_of_week,session_name,m1_atr_14,m15_atr_14,spread_at_entry,previous_trade_result,consecutive_losses_before,consecutive_wins_before,comment";
}

inline void __WBA_ResetAllFiles()
{
   int h;
   h=AnalysisLogger_OpenRewrite(WBA_FILE_RUN_MANIFEST, AnalysisLogger_HeaderRunManifest()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_CANDLES_M1, AnalysisLogger_HeaderCandles()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_CANDLES_M15, AnalysisLogger_HeaderCandles()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_M15_MAIN, AnalysisLogger_HeaderM15MainSignals()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_M15_STAGE, AnalysisLogger_HeaderM15Stage()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_M15_ZONES, AnalysisLogger_HeaderM15Zones()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_BRIDGE, AnalysisLogger_HeaderBridge()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_M1_TRIGGERS, AnalysisLogger_HeaderM1Triggers()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_M1_REJECTED, AnalysisLogger_HeaderRejected()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_TRADES, AnalysisLogger_HeaderTrades()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_TRADE_PATH, AnalysisLogger_HeaderTradePath()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_TRADE_MAE_MFE, AnalysisLogger_HeaderTradeMAEMFE()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_EQUITY, AnalysisLogger_HeaderEquity()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_SUMMARY, AnalysisLogger_HeaderSummary()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_RESETS, AnalysisLogger_HeaderResets()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_FEATURES, AnalysisLogger_HeaderFeatures()); AnalysisLogger_Close(h);
   h=AnalysisLogger_OpenRewrite(WBA_FILE_DEBUG, "time,seq,module,event,comment"); AnalysisLogger_Close(h);
}

inline void AnalysisLogger_LogDebug(const string module_name, const string event_name, const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   if(!InpAnalysisDebugRawLog) return;
   g_wba_debug_seq++;
   string line = __WBA_TimeCsv(TimeCurrent()) + "," + __WBA_Int(g_wba_debug_seq) + "," + __WBA_Str(module_name) + "," + __WBA_Str(event_name) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_DEBUG, line);
}

inline void AnalysisLogger_LogStateReset(const datetime t,
                                         const ENUM_TIMEFRAMES tf,
                                         const int bar_index,
                                         const string module_name,
                                         const string context_id,
                                         const string zone_id,
                                         const string trigger_id,
                                         const string old_state,
                                         const string new_state,
                                         const string reset_reason,
                                         const Direction dir,
                                         const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   g_wba_reset_seq++;
   string line = g_wba_run_id + "," + __WBA_Str("RST_" + IntegerToString(g_wba_reset_seq)) + "," + __WBA_TimeCsv(t) + "," + __WBA_Str(__WBA_TFTag(tf)) + "," + __WBA_Int(bar_index) + "," + __WBA_Str(module_name) + "," + __WBA_Str(context_id) + "," + __WBA_Str(zone_id) + "," + __WBA_Str(trigger_id) + "," + __WBA_Str(old_state) + "," + __WBA_Str(new_state) + "," + __WBA_Str(reset_reason) + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_RESETS, line);
}

inline void AnalysisLogger_SetCurrentTriggerWindow(const int seq,
                                                   const int kind,
                                                   const int ns,
                                                   const Direction dir,
                                                   const datetime start_time,
                                                   const datetime start_bar)
{
   g_wba_ctx_seq        = seq;
   g_wba_ctx_kind       = kind;
   g_wba_ctx_ns         = ns;
   g_wba_ctx_dir        = dir;
   g_wba_ctx_start_time = start_time;
   g_wba_ctx_start_bar  = start_bar;
}

inline void AnalysisLogger_ClearCurrentTriggerWindow()
{
   g_wba_ctx_seq        = -1;
   g_wba_ctx_kind       = 0;
   g_wba_ctx_ns         = 0;
   g_wba_ctx_dir        = DIR_UP;
   g_wba_ctx_start_time = 0;
   g_wba_ctx_start_bar  = 0;
}

inline int AnalysisLogger_CurrentContextSeq(){ return g_wba_ctx_seq; }
inline int AnalysisLogger_CurrentContextKind(){ return g_wba_ctx_kind; }
inline int AnalysisLogger_CurrentContextNS(){ return g_wba_ctx_ns; }
inline datetime AnalysisLogger_CurrentContextStartTime(){ return g_wba_ctx_start_time; }
inline datetime AnalysisLogger_CurrentContextStartBar(){ return g_wba_ctx_start_bar; }

inline void AnalysisLogger_ExportCandlesRange(const string sym,
                                              const ENUM_TIMEFRAMES tf,
                                              const datetime from_time,
                                              const datetime to_time,
                                              const bool rewrite)
{
   if(!AnalysisLogger_IsReady()) return;
   if(sym == "") return;
   if(from_time <= 0) return;

   string file_name = (tf == PERIOD_M15 ? WBA_FILE_CANDLES_M15 : WBA_FILE_CANDLES_M1);
   int h = INVALID_HANDLE;
   if(rewrite)
      h = AnalysisLogger_OpenRewrite(file_name, AnalysisLogger_HeaderCandles());
   else
      h = __WBA_OpenAppend(file_name);
   if(h == INVALID_HANDLE) return;

   MqlRates bars[];
   int copied = CopyRates(sym, tf, from_time, to_time, bars);
   if(copied > 0)
   {
      ArraySetAsSeries(bars, false);
      for(int i=0; i<copied; ++i)
      {
         string line = g_wba_run_id + "," + __WBA_Str(sym) + "," + __WBA_Str(__WBA_TFTag(tf)) + "," + __WBA_Int(i) + "," + __WBA_TimeCsv(bars[i].time) + "," + __WBA_Dbl(bars[i].open,_Digits) + "," + __WBA_Dbl(bars[i].high,_Digits) + "," + __WBA_Dbl(bars[i].low,_Digits) + "," + __WBA_Dbl(bars[i].close,_Digits) + "," + __WBA_Long((long)bars[i].tick_volume) + "," + __WBA_Long((long)bars[i].real_volume) + "," + __WBA_Int((int)bars[i].spread);
         AnalysisLogger_WriteRaw(h, line);
         if(tf == PERIOD_M1)  g_wba_last_m1_exported  = bars[i].time;
         if(tf == PERIOD_M15) g_wba_last_m15_exported = bars[i].time;
      }
   }

   AnalysisLogger_Close(h);
}

inline void AnalysisLogger_UpdateCandles(const string sym)
{
   if(!AnalysisLogger_IsReady()) return;
   if(!InpAnalysisExportCandles) return;

   ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();
   datetime now_t = TimeCurrent();
   if(now_t <= 0) return;

   if(chart_tf == PERIOD_M1)
   {
      datetime from_t = (g_wba_last_m1_exported > 0 ? g_wba_last_m1_exported + 60 : g_wba_from);
      AnalysisLogger_ExportCandlesRange(sym, PERIOD_M1, from_t, now_t, false);
   }
   else if(chart_tf == PERIOD_M15)
   {
      datetime from_t = (g_wba_last_m15_exported > 0 ? g_wba_last_m15_exported + 900 : g_wba_from);
      AnalysisLogger_ExportCandlesRange(sym, PERIOD_M15, from_t, now_t, false);
   }
}

inline void AnalysisLogger_WriteRunManifest(const string sym,
                                            const datetime from_time,
                                            const datetime to_time,
                                            const double initial_capital,
                                            const double risk_percent)
{
   if(!AnalysisLogger_IsReady()) return;
   int h = AnalysisLogger_OpenRewrite(WBA_FILE_RUN_MANIFEST, AnalysisLogger_HeaderRunManifest());
   if(h == INVALID_HANDLE) return;

   string tz = "BROKER_SERVER_TIME";
   string line = g_wba_run_id + "," + __WBA_Str(sym) + "," + __WBA_TimeCsv(from_time) + "," + __WBA_TimeCsv(to_time) + "," + __WBA_Str(tz) + "," + __WBA_Dbl(initial_capital,2) + "," + __WBA_Str(AccountInfoString(ACCOUNT_CURRENCY)) + "," + __WBA_Dbl(risk_percent,2) + "," + __WBA_Dbl(3.0,2) + "," + __WBA_Str("WaveBot") + "," + __WBA_Str(InpAnalysisCodeVersionTag) + "," + __WBA_Str(__WBA_Dir(InpDirection)) + "," + __WBA_Bool(InpMostRecentOnly) + "," + __WBA_Bool(InpUseMonthsAgo) + "," + __WBA_Int(InpMonthsAgo) + "," + __WBA_TimeCsv(InpScanFromDate) + "," + __WBA_Bool(InpEnableTriggerStatement) + "," + __WBA_Str("MT5_BAR_SPREAD") + "," + __WBA_Str("NOT_APPLIED") + "," + __WBA_TimeCsv(TimeCurrent());
   AnalysisLogger_WriteRaw(h, line);
   AnalysisLogger_Close(h);
}

inline bool AnalysisLogger_Init(const string sym,
                                const datetime from_time,
                                const datetime to_time,
                                const double initial_capital,
                                const double risk_percent)
{
   if(!InpAnalysisLogEnabled)
      return false;

   string use_sym = sym;
   if(use_sym == "") use_sym = _Symbol;

   g_wba_symbol = use_sym;
   g_wba_from   = from_time;
   g_wba_to     = to_time;

   string run_tag = InpAnalysisRunTag;
   if(run_tag == "")
      run_tag = "RUN";

   g_wba_run_id = __WBA_Sanitize(run_tag);
   string from_tag = __WBA_DateTag(from_time);
   string to_tag   = __WBA_DateTag(to_time);
   if(to_tag == "NA") to_tag = "LIVE";

   g_wba_folder = "WaveBot_Analysis_" + __WBA_Sanitize(use_sym) + "_" + from_tag + "_" + to_tag + "_" + g_wba_run_id;
   FolderCreate(g_wba_folder, FILE_COMMON);

   g_wba_ready = true;

   string reset_gv = "WBA_RESET_" + __WBA_Sanitize(g_wba_folder);
   bool must_reset = InpAnalysisResetFilesOnInit;
   if(must_reset)
   {
      if(GlobalVariableCheck(reset_gv))
         must_reset = false;
   }

   if(must_reset)
   {
      __WBA_ResetAllFiles();
      GlobalVariableSet(reset_gv, (double)TimeCurrent());
   }
   else
   {
      // Ensure files exist even when another chart already reset the run.
      int h;
      h = __WBA_OpenAppend(WBA_FILE_DEBUG); AnalysisLogger_Close(h);
   }

   AnalysisLogger_WriteRunManifest(use_sym, from_time, to_time, initial_capital, risk_percent);

   if(InpAnalysisExportCandles)
   {
      ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();
      if(chart_tf == PERIOD_M1)
         AnalysisLogger_ExportCandlesRange(use_sym, PERIOD_M1, from_time, TimeCurrent(), true);
      else if(chart_tf == PERIOD_M15)
         AnalysisLogger_ExportCandlesRange(use_sym, PERIOD_M15, from_time, TimeCurrent(), true);
      else
      {
         AnalysisLogger_ExportCandlesRange(use_sym, PERIOD_M1,  from_time, TimeCurrent(), true);
         AnalysisLogger_ExportCandlesRange(use_sym, PERIOD_M15, from_time, TimeCurrent(), true);
      }
   }

   AnalysisLogger_LogDebug("AnalysisLogger", "INIT", "folder=" + g_wba_folder);
   return true;
}

inline void AnalysisLogger_Finalize()
{
   if(!AnalysisLogger_IsReady()) return;
   AnalysisLogger_LogDebug("AnalysisLogger", "FINALIZE", "logger finalized");
}

inline void AnalysisLogger_LogM15MainSignal(const string sym,
                                            const int seq,
                                            const int kind,
                                            const int ns,
                                            const Direction dir,
                                            const datetime event_time,
                                            const bool is_start,
                                            const string source_module,
                                            const string off_reason,
                                            const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   string context_id = AnalysisLogger_ContextId(seq);
   string event_id = "M15EVT_" + IntegerToString(seq);
   string action = (is_start ? "MAIN_START" : "MAIN_OFF");
   string signal = AnalysisLogger_SignalKindName(kind);
   string line = g_wba_run_id + "," + __WBA_Str(context_id) + "," + __WBA_Str(event_id) + "," + __WBA_Str(sym) + "," + __WBA_Str("M15") + "," + __WBA_TimeCsv(event_time) + ",-1," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(action) + "," + __WBA_Str(signal) + "," + __WBA_Str(source_module) + "," + __WBA_Str(signal) + ",0,0,0,0," + __WBA_Str(off_reason) + "," + __WBA_Bool(is_start) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_M15_MAIN, line);
}

inline void AnalysisLogger_LogM15StageEvent(const string sym,
                                            const int seq,
                                            const int kind,
                                            const int ns,
                                            const Direction dir,
                                            const datetime event_time,
                                            const string stage_event,
                                            const string reset_reason,
                                            const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   string context_id = AnalysisLogger_ContextId(seq);
   string event_id = "STG_" + IntegerToString(seq) + "_" + IntegerToString(++g_wba_event_seq);
   string line = g_wba_run_id + "," + __WBA_Str(context_id) + "," + __WBA_Str("") + "," + __WBA_Str(event_id) + "," + __WBA_Str(sym) + "," + __WBA_Str("M15") + "," + __WBA_TimeCsv(event_time) + ",-1," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(AnalysisLogger_SignalKindName(kind)) + "," + __WBA_Str(stage_event) + ",,,,,0,,0,0,0,0,-1,,0,0,0,0,0,0,0,0,," + __WBA_Str(reset_reason) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_M15_STAGE, line);
}


inline string AnalysisLogger_StageSourceName(const int source)
{
   if(source == 1) return "FLIP";
   if(source == 2) return "MAJICFLIP";
   return "";
}

inline string AnalysisLogger_StageZoneTypeName(const int source, const int kind)
{
   if(source == 1)
   {
      if(kind > 0) return "FLIP_T" + IntegerToString(kind);
      return "FLIP";
   }
   if(source == 2) return "MAJICFLIP";
   return "";
}

inline void AnalysisLogger_LogM15StageDetailed(const string sym,
                                               const int context_seq,
                                               const int zone_seq,
                                               const int kind,
                                               const int ns,
                                               const Direction dir,
                                               const datetime event_time,
                                               const int bar_index_m15,
                                               const string stage_event,
                                               const int zone_source,
                                               const int zone_kind,
                                               const int flip_bar_index,
                                               const datetime flip_time,
                                               const double flip_open,
                                               const double flip_high,
                                               const double flip_low,
                                               const double flip_close,
                                               const int broken_bar_index,
                                               const datetime broken_time,
                                               const double broken_open,
                                               const double broken_high,
                                               const double broken_low,
                                               const double broken_close,
                                               const double zone_low,
                                               const double zone_high,
                                               const double invalid_level,
                                               const double touch_price,
                                               const datetime m1_start_time,
                                               const string reset_reason,
                                               const string comment)
{
   if(!AnalysisLogger_IsReady()) return;

   string context_id = AnalysisLogger_ContextId(context_seq);
   string zone_id    = AnalysisLogger_ZoneId(zone_seq);
   string event_id   = "STG_" + IntegerToString(context_seq) + "_" + IntegerToString(++g_wba_event_seq);
   string source     = AnalysisLogger_StageSourceName(zone_source);
   string ztype      = AnalysisLogger_StageZoneTypeName(zone_source, zone_kind);
   double width_pips = 0.0;
   if(zone_high > 0.0 && zone_low > 0.0)
      width_pips = AnalysisLogger_ToPips(sym, MathAbs(zone_high - zone_low));

   string line = g_wba_run_id + "," + __WBA_Str(context_id) + "," + __WBA_Str(zone_id) + "," + __WBA_Str(event_id) + "," + __WBA_Str(sym) + "," + __WBA_Str("M15") + "," + __WBA_TimeCsv(event_time) + "," + __WBA_Int(bar_index_m15) + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(AnalysisLogger_SignalKindName(kind)) + "," + __WBA_Str(stage_event) + "," + __WBA_Str(source) + "," + __WBA_Str(ztype) + "," + __WBA_Int(zone_kind) + "," + __WBA_Int(flip_bar_index) + "," + __WBA_TimeCsv(flip_time) + "," + __WBA_Dbl(flip_open,_Digits) + "," + __WBA_Dbl(flip_high,_Digits) + "," + __WBA_Dbl(flip_low,_Digits) + "," + __WBA_Dbl(flip_close,_Digits) + "," + __WBA_Int(broken_bar_index) + "," + __WBA_TimeCsv(broken_time) + "," + __WBA_Dbl(broken_open,_Digits) + "," + __WBA_Dbl(broken_high,_Digits) + "," + __WBA_Dbl(broken_low,_Digits) + "," + __WBA_Dbl(broken_close,_Digits) + "," + __WBA_Dbl(zone_low,_Digits) + "," + __WBA_Dbl(zone_high,_Digits) + "," + __WBA_Dbl(width_pips,2) + "," + __WBA_Dbl(invalid_level,_Digits) + "," + __WBA_Dbl(touch_price,_Digits) + "," + __WBA_TimeCsv(m1_start_time) + "," + __WBA_Str(reset_reason) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_M15_STAGE, line);
}

inline void AnalysisLogger_LogM15ZoneSnapshot(const string sym,
                                              const int context_seq,
                                              const int zone_seq,
                                              const Direction dir,
                                              const int main_kind,
                                              const int zone_source,
                                              const int zone_kind,
                                              const datetime flip_time,
                                              const int flip_bar_index,
                                              const double flip_low,
                                              const double flip_high,
                                              const datetime broken_time,
                                              const int broken_bar_index,
                                              const double broken_low,
                                              const double broken_high,
                                              const double zone_low,
                                              const double zone_high,
                                              const double invalid_level,
                                              const datetime created_time,
                                              const datetime retouch_time,
                                              const int retouch_bar_index,
                                              const bool sent_to_m1,
                                              const datetime sent_to_m1_time,
                                              const bool invalidated,
                                              const datetime invalidated_time,
                                              const string invalidated_reason,
                                              const datetime main_off_time,
                                              const string final_status)
{
   if(!AnalysisLogger_IsReady()) return;

   string context_id = AnalysisLogger_ContextId(context_seq);
   string zone_id    = AnalysisLogger_ZoneId(zone_seq);
   string source     = AnalysisLogger_StageSourceName(zone_source);
   string ztype      = AnalysisLogger_StageZoneTypeName(zone_source, zone_kind);
   double width_pips = 0.0;
   if(zone_high > 0.0 && zone_low > 0.0)
      width_pips = AnalysisLogger_ToPips(sym, MathAbs(zone_high - zone_low));

   string line = g_wba_run_id + "," + __WBA_Str(context_id) + "," + __WBA_Str(zone_id) + "," + __WBA_Str(sym) + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(AnalysisLogger_SignalKindName(main_kind)) + "," + __WBA_Str(source) + "," + __WBA_Str(ztype) + "," + __WBA_TimeCsv(flip_time) + "," + __WBA_Int(flip_bar_index) + "," + __WBA_Dbl(flip_low,_Digits) + "," + __WBA_Dbl(flip_high,_Digits) + "," + __WBA_TimeCsv(broken_time) + "," + __WBA_Int(broken_bar_index) + "," + __WBA_Dbl(broken_low,_Digits) + "," + __WBA_Dbl(broken_high,_Digits) + "," + __WBA_Dbl(zone_low,_Digits) + "," + __WBA_Dbl(zone_high,_Digits) + "," + __WBA_Dbl(width_pips,2) + "," + __WBA_Dbl(invalid_level,_Digits) + "," + __WBA_TimeCsv(created_time) + "," + __WBA_TimeCsv(retouch_time) + "," + __WBA_Int(retouch_bar_index) + "," + __WBA_Bool(sent_to_m1) + "," + __WBA_TimeCsv(sent_to_m1_time) + "," + __WBA_Bool(invalidated) + "," + __WBA_TimeCsv(invalidated_time) + "," + __WBA_Str(invalidated_reason) + "," + __WBA_TimeCsv(main_off_time) + "," + __WBA_Str(final_status);
   AnalysisLogger_AppendRaw(WBA_FILE_M15_ZONES, line);
}

inline void AnalysisLogger_LogBridgeMaster(const string sym,
                                           const int seq,
                                           const int kind,
                                           const int ns,
                                           const Direction dir,
                                           const datetime event_time,
                                           const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   string action = (AnalysisLogger_IsStartKind(kind) ? "START_TO_M1" : "OFF_TO_M1");
   string line = g_wba_run_id + "," + __WBA_Str("BRG_" + IntegerToString(seq)) + "," + __WBA_Str(AnalysisLogger_ContextId(seq)) + "," + __WBA_Str("") + "," + __WBA_Str(sym) + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(action) + "," + __WBA_TimeCsv(event_time) + ",-1,,,-1," + __WBA_Str(AnalysisLogger_SignalKindName(kind)) + ",,,,," + __WBA_Str("") + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_BRIDGE, line);
}

inline void AnalysisLogger_LogBridgeSlave(const string sym,
                                          const int seq,
                                          const int kind,
                                          const int ns,
                                          const Direction dir,
                                          const datetime event_time_m15,
                                          const datetime received_time_m1,
                                          const int received_bar_index_m1,
                                          const bool is_start,
                                          const datetime active_from_time_m1,
                                          const datetime active_to_time_m1,
                                          const string off_reason,
                                          const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   string action = (is_start ? "START_TO_M1" : "OFF_TO_M1");
   string line = g_wba_run_id + "," + __WBA_Str("BRG_" + IntegerToString(seq) + "_RX") + "," + __WBA_Str(AnalysisLogger_ContextId(seq)) + "," + __WBA_Str("") + "," + __WBA_Str(sym) + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Str(action) + "," + __WBA_TimeCsv(event_time_m15) + ",-1," + __WBA_TimeCsv(received_time_m1) + "," + __WBA_Int(received_bar_index_m1) + "," + __WBA_Str(AnalysisLogger_SignalKindName(kind)) + "," + __WBA_Str("") + "," + __WBA_TimeCsv(active_from_time_m1) + "," + __WBA_Int(received_bar_index_m1) + "," + __WBA_TimeCsv(active_to_time_m1) + ",-1," + __WBA_Str(off_reason) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_BRIDGE, line);
}

inline void AnalysisLogger_LogM1Trigger(const string sym,
                                        const Direction dir,
                                        const int type_id,
                                        const int serial,
                                        const int bar_idx,
                                        const datetime trigger_time,
                                        const double o,
                                        const double h,
                                        const double l,
                                        const double c,
                                        const double entry,
                                        const double sl,
                                        const double tp,
                                        const double risk_pips,
                                        const bool valid_sltp,
                                        const bool executed_as_trade,
                                        const string rejection_reason,
                                        const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   string trigger_name = (type_id == 1 ? "FLIP" : "MAJICFLIP");
   string trigger_id = AnalysisLogger_TriggerId(type_id, serial, trigger_time);
   string context_id = AnalysisLogger_ContextId(g_wba_ctx_seq);
   int bars_after = 0;
   if(g_wba_ctx_start_bar > 0 && trigger_time >= g_wba_ctx_start_bar)
      bars_after = (int)((trigger_time - g_wba_ctx_start_bar) / 60);
   double minutes_after = (double)bars_after;
   string line = g_wba_run_id + "," + __WBA_Str(trigger_id) + "," + __WBA_Str(context_id) + "," + __WBA_Str("") + "," + __WBA_Str(sym) + "," + __WBA_Str("M1") + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Int(type_id) + "," + __WBA_Str(trigger_name) + "," + __WBA_Str(trigger_name) + "," + __WBA_TimeCsv(trigger_time) + "," + __WBA_Int(bar_idx) + "," + __WBA_Dbl(o,_Digits) + "," + __WBA_Dbl(h,_Digits) + "," + __WBA_Dbl(l,_Digits) + "," + __WBA_Dbl(c,_Digits) + "," + __WBA_Dbl(entry,_Digits) + "," + __WBA_Dbl(sl,_Digits) + "," + __WBA_Dbl(tp,_Digits) + "," + __WBA_Dbl(risk_pips,2) + ",3.00," + __WBA_Bool(valid_sltp) + "," + __WBA_Bool(executed_as_trade) + "," + __WBA_Str("") + "," + __WBA_Str(rejection_reason) + "," + __WBA_Str(AnalysisLogger_SignalKindName(g_wba_ctx_kind)) + "," + __WBA_Str("") + ",0,0,0," + __WBA_Int(bars_after) + "," + __WBA_Dbl(minutes_after,2) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_M1_TRIGGERS, line);
}

inline void AnalysisLogger_LogRejectedTrigger(const string sym,
                                              const Direction dir,
                                              const int type_id,
                                              const int candidate_idx,
                                              const datetime candidate_time,
                                              const double o,
                                              const double h,
                                              const double l,
                                              const double c,
                                              const double entry,
                                              const string reason,
                                              const string comment)
{
   if(!AnalysisLogger_IsReady()) return;
   string name = (type_id == 1 ? "FLIP" : "MAJICFLIP");
   string cid = g_wba_run_id + "_CAND_T" + IntegerToString(type_id) + "_" + IntegerToString((int)candidate_time);
   int bars_after = 0;
   if(g_wba_ctx_start_bar > 0 && candidate_time >= g_wba_ctx_start_bar)
      bars_after = (int)((candidate_time - g_wba_ctx_start_bar) / 60);
   string line = g_wba_run_id + "," + __WBA_Str(cid) + "," + __WBA_Str(AnalysisLogger_ContextId(g_wba_ctx_seq)) + "," + __WBA_Str("") + "," + __WBA_Str(sym) + "," + __WBA_Str("M1") + "," + __WBA_Str(__WBA_Dir(dir)) + "," + __WBA_Int(type_id) + "," + __WBA_Str(name) + "," + __WBA_TimeCsv(candidate_time) + "," + __WBA_Int(candidate_idx) + "," + __WBA_Dbl(o,_Digits) + "," + __WBA_Dbl(h,_Digits) + "," + __WBA_Dbl(l,_Digits) + "," + __WBA_Dbl(c,_Digits) + "," + __WBA_Dbl(entry,_Digits) + ",0,0,0,0," + __WBA_Str(reason) + "," + __WBA_Str(AnalysisLogger_SignalKindName(g_wba_ctx_kind)) + "," + __WBA_Str("") + "," + __WBA_Int(bars_after) + "," + __WBA_Str(comment);
   AnalysisLogger_AppendRaw(WBA_FILE_M1_REJECTED, line);
}

inline string AnalysisLogger_SessionName(const int hour)
{
   if(hour >= 0 && hour < 7) return "ASIA";
   if(hour >= 7 && hour < 13) return "LONDON";
   if(hour >= 13 && hour < 21) return "NEWYORK";
   return "LATE_US";
}

#endif // WAVEBOT_ANALYSIS_LOGGER_MQH

