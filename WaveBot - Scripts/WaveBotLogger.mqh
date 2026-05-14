#ifndef WAVEBOT_LOGGER_MQH
#define WAVEBOT_LOGGER_MQH

#include <WaveBot/Types.mqh>

// ============================================================================
// WaveBotLogger.mqh
// Pure diagnostic logger. This module only writes CSV/TXT diagnostics and does
// not change trading, trigger, Flip, MajicFlip, bridge, or statement logic.
// ============================================================================

#define WBLOG_KIND_START_HWX          1
#define WBLOG_KIND_START_HWBB         2
#define WBLOG_KIND_START_FSMS         3
#define WBLOG_KIND_START_GOOZBAGHALI  4
#define WBLOG_KIND_STOP_MTC              10
#define WBLOG_KIND_STOP_MINORSTARTER     11
#define WBLOG_KIND_STOP_MINOROFF_ZONE    12
#define WBLOG_KIND_STOP_ZONE_INVALIDATED 13

struct WBLogM15ContextRow
{
   bool      used;
   bool      active;
   int       id;
   int       signal_type;
   int       ns;
   Direction dir;
   datetime  signal_time;
   datetime  signal_bar_time;
   double    o;
   double    h;
   double    l;
   double    c;
   string    source_module;
   datetime  off_time;
   datetime  off_bar_time;
   string    off_reason;
};

struct WBLogM15ZoneRow
{
   bool      used;
   int       context_id;
   int       zone_id;
   int       zone_source;
   int       zone_kind;
   Direction dir;
   datetime  flip_time;
   datetime  anchor_time;
   double    flip_open;
   double    flip_high;
   double    flip_low;
   double    flip_close;
   double    anchor_high;
   double    anchor_low;
   double    zone_low;
   double    zone_high;
   double    zone_width_pips;
   double    invalid_level;
   string    status;
   datetime  invalid_time;
   int       invalid_bar_index;
   string    invalid_reason;
};

static bool     g_wblog_ready       = false;
static string   g_wblog_run_id      = "";
static string   g_wblog_dir         = "";
static int      g_wblog_event_seq   = 0;
static int      g_wblog_context_seq = 0;
static int      g_wblog_zone_seq    = 0;
static int      g_wblog_bridge_seq  = 0;
static int      g_wblog_candidate_seq = 0;
static int      g_wblog_reject_seq  = 0;
static int      g_wblog_reset_seq   = 0;
static int      g_wblog_state_seq   = 0;
static datetime g_wblog_last_m1_candle  = 0;
static datetime g_wblog_last_m15_candle = 0;

static int      g_wblog_cur_context_id = 0;
static int      g_wblog_cur_zone_id    = 0;
static int      g_wblog_cur_window_id  = 0;
static int      g_wblog_cur_start_kind = 0;
static int      g_wblog_cur_start_ns   = 0;
static Direction g_wblog_cur_dir       = DIR_UP;
static datetime g_wblog_cur_window_start = 0;
static datetime g_wblog_cur_window_bar   = 0;
static int      g_wblog_last_candidate_id = 0;

static WBLogM15ContextRow g_wblog_contexts[];
static WBLogM15ZoneRow    g_wblog_zones[];

// Cached CSV file handles. Keeping handles open removes thousands of
// FileOpen/FileSeek/FileClose cycles during historical M1 scans.
//
// IMPORTANT PERFORMANCE NOTE:
// The logger keeps files open and avoids full-file rewrites during the scan.
// FSMS is frequent; rewriting M15 snapshot CSVs on every FSMS/HWX/HWBB/Gooz
// event creates visible multi-second stalls. Live rows are appended immediately
// and final clean snapshots are rewritten once on finalization.
static string g_wblog_open_names[];
static int    g_wblog_open_handles[];
static int    g_wblog_unflushed_rows = 0;
static const int WBLOG_FLUSH_EVERY_ROWS = 250;
static bool   g_wblog_snapshot_dirty_contexts = false;
static bool   g_wblog_snapshot_dirty_zones    = false;

// Deferred output mode for the M1 chart. When enabled, diagnostic files are
// not updated continuously. Low-frequency rows are buffered in memory,
// high-frequency candle/feature/equity/path rows are skipped until the final
// output write. The final write opens the files, writes buffered rows plus
// snapshot files once, then freezes further output.
static bool     g_wblog_scheduled_output_enabled = false;
static bool     g_wblog_final_only_output_enabled = false;
static datetime g_wblog_scheduled_output_at      = 0;
static bool     g_wblog_scheduled_output_done    = false;
static bool     g_wblog_scheduled_output_writing = false;
static string   g_wblog_deferred_names[];
static string   g_wblog_deferred_rows[];

inline string WBLOG_TFName(const ENUM_TIMEFRAMES tf)
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

inline string WBLOG_DirName(const Direction dir)
{
   return (dir == DIR_UP ? "UP" : "DOWN");
}

inline string WBLOG_NsName(const int ns)
{
   if(ns == 1) return "MAJ";
   if(ns == 2) return "MIN";
   return "NONE";
}

inline string WBLOG_KindName(const int kind)
{
   if(kind == WBLOG_KIND_START_HWX) return "HWX";
   if(kind == WBLOG_KIND_START_HWBB) return "HWBB";
   if(kind == WBLOG_KIND_START_FSMS) return "FSMS";
   if(kind == WBLOG_KIND_START_GOOZBAGHALI) return "GOOZBAGHALI";
   if(kind == WBLOG_KIND_STOP_MTC) return "MTC";
   if(kind == WBLOG_KIND_STOP_MINORSTARTER) return "MINORSTARTER";
   if(kind == WBLOG_KIND_STOP_MINOROFF_ZONE) return "MINOROFF_ZONE";
   if(kind == WBLOG_KIND_STOP_ZONE_INVALIDATED) return "ZONE_INVALIDATED";
   return "UNKNOWN_" + IntegerToString(kind);
}

inline string WBLOG_ZoneTypeName(const int source, const int kind)
{
   if(source == 2) return "MAJICFLIP";
   if(source == 1)
   {
      if(kind == 2) return "FLIP_T2";
      return "FLIP_T1";
   }
   return "NA";
}

inline string WBLOG_Time(const datetime t)
{
   if(t <= 0) return "";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

inline string WBLOG_Int(const int v)
{
   return IntegerToString(v);
}

inline string WBLOG_Double(const double v, const int digits = 8)
{
   return DoubleToString(v, digits);
}

inline string WBLOG_Cell(string v)
{
   StringReplace(v, "\r", " ");
   StringReplace(v, "\n", " ");
   bool need_quote = false;
   if(StringFind(v, ",") >= 0) need_quote = true;
   if(StringFind(v, "\"") >= 0) need_quote = true;
   if(StringFind(v, ";") >= 0) need_quote = true;
   if(need_quote)
   {
      StringReplace(v, "\"", "\"\"");
      v = "\"" + v + "\"";
   }
   return v;
}

inline string WBLOG_Join2(const string a, const string b)
{
   return WBLOG_Cell(a) + "," + WBLOG_Cell(b);
}

inline string WBLOG_AppendCell(const string row, const string cell)
{
   if(row == "") return WBLOG_Cell(cell);
   return row + "," + WBLOG_Cell(cell);
}

inline string WBLOG_FilePath(const string filename)
{
   return g_wblog_dir + "\\" + filename;
}

inline int WBLOG_FindOpenFile(const string filename)
{
   int total = ArraySize(g_wblog_open_names);
   for(int i=0; i<total; ++i)
   {
      if(g_wblog_open_names[i] == filename)
         return i;
   }
   return -1;
}

inline void WBLOG_SetScheduledOutput(const datetime update_at, const bool enabled)
{
   g_wblog_scheduled_output_enabled  = (enabled && update_at > 0);
   g_wblog_final_only_output_enabled = false;
   g_wblog_scheduled_output_at       = (g_wblog_scheduled_output_enabled ? update_at : 0);
   g_wblog_scheduled_output_done     = false;
   g_wblog_scheduled_output_writing  = false;
   ArrayResize(g_wblog_deferred_names, 0);
   ArrayResize(g_wblog_deferred_rows, 0);
}

inline void WBLOG_SetFinalOnlyOutput(const bool enabled)
{
   g_wblog_scheduled_output_enabled  = false;
   g_wblog_final_only_output_enabled = enabled;
   g_wblog_scheduled_output_at       = 0;
   g_wblog_scheduled_output_done     = false;
   g_wblog_scheduled_output_writing  = false;
   ArrayResize(g_wblog_deferred_names, 0);
   ArrayResize(g_wblog_deferred_rows, 0);
}

inline bool WBLOG_ScheduledOutputActive()
{
   return (g_wblog_scheduled_output_enabled || g_wblog_final_only_output_enabled);
}

inline bool WBLOG_ScheduledOutputDone()
{
   return g_wblog_scheduled_output_done;
}

inline datetime WBLOG_ScheduledOutputAt()
{
   if(g_wblog_final_only_output_enabled)
      return 0;
   return g_wblog_scheduled_output_at;
}

inline bool WBLOG_OutputCanWriteNow()
{
   if(!g_wblog_scheduled_output_enabled && !g_wblog_final_only_output_enabled)
      return true;
   return g_wblog_scheduled_output_writing;
}

inline bool WBLOG_ShouldBufferBeforeScheduledWrite(const string filename)
{
   if(filename == "WaveBot_Candles_M1.csv") return false;
   if(filename == "WaveBot_Candles_M15.csv") return false;
   if(filename == "WaveBot_MarketFeatures_M1.csv") return false;
   if(filename == "WaveBot_MarketFeatures_M15.csv") return false;
   if(filename == "WaveBot_TradePath_M1.csv") return false;
   if(filename == "WaveBot_EquityCurve.csv") return false;

   // These two files are rewritten from the in-memory context/zone snapshots
   // during the scheduled write, so buffering their repeated live snapshots
   // would only create duplicate/stale rows.
   if(filename == "WaveBot_M15_MainSignals.csv") return false;
   if(filename == "WaveBot_M15_FlipZones.csv") return false;

   // These files are regenerated by TriggerStatement_WriteTextReport during
   // the scheduled write. Dropping their live rows prevents duplication.
   if(filename == "WaveBot_TradeCandidates.csv") return false;
   if(filename == "WaveBot_Trades.csv") return false;
   if(filename == "WaveBot_TradeMAE_MFE.csv") return false;
   if(filename == "WaveBot_SummaryByRun.csv") return false;

   return true;
}

inline void WBLOG_BufferScheduledRow(const string filename, const string line)
{
   int n = ArraySize(g_wblog_deferred_rows);
   ArrayResize(g_wblog_deferred_names, n + 1);
   ArrayResize(g_wblog_deferred_rows,  n + 1);
   g_wblog_deferred_names[n] = filename;
   g_wblog_deferred_rows[n]  = line;
}

inline void WBLOG_CloseOpenFile(const string filename)
{
   int idx = WBLOG_FindOpenFile(filename);
   if(idx < 0)
      return;

   int h = g_wblog_open_handles[idx];
   if(h != INVALID_HANDLE)
   {
      FileFlush(h);
      FileClose(h);
   }

   int total = ArraySize(g_wblog_open_names);
   for(int i=idx; i<total-1; ++i)
   {
      g_wblog_open_names[i]   = g_wblog_open_names[i+1];
      g_wblog_open_handles[i] = g_wblog_open_handles[i+1];
   }
   ArrayResize(g_wblog_open_names, total-1);
   ArrayResize(g_wblog_open_handles, total-1);
}

inline void WBLOG_CloseAllFiles()
{
   int total = ArraySize(g_wblog_open_handles);
   for(int i=0; i<total; ++i)
   {
      int h = g_wblog_open_handles[i];
      if(h != INVALID_HANDLE)
      {
         FileFlush(h);
         FileClose(h);
      }
   }
   ArrayResize(g_wblog_open_names, 0);
   ArrayResize(g_wblog_open_handles, 0);
   g_wblog_unflushed_rows = 0;
}

inline bool WBLOG_OpenAppend(const string filename, int &handle)
{
   handle = INVALID_HANDLE;
   if(!g_wblog_ready) return false;
   if(!WBLOG_OutputCanWriteNow()) return false;

   int idx = WBLOG_FindOpenFile(filename);
   if(idx >= 0)
   {
      handle = g_wblog_open_handles[idx];
      return (handle != INVALID_HANDLE);
   }

   string path = WBLOG_FilePath(filename);
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);

   if(h == INVALID_HANDLE)
      return false;

   // Optional diagnostic files are no longer pre-created with header-only
   // contents. When the first real row is appended, create the CSV header
   // on demand so non-empty files stay self-describing.
   if(FileSize(h) <= 0)
      FileWriteString(h, WBLOG_FileHeader(filename) + "\r\n");

   FileSeek(h, 0, SEEK_END);

   int pos = ArraySize(g_wblog_open_names);
   ArrayResize(g_wblog_open_names, pos + 1);
   ArrayResize(g_wblog_open_handles, pos + 1);
   g_wblog_open_names[pos]   = filename;
   g_wblog_open_handles[pos] = h;

   handle = h;
   return true;
}

inline bool WBLOG_ShouldFlushImmediately(const string filename)
{
   // High-frequency files are intentionally batched. Low-frequency state,
   // trigger and trade files are flushed immediately. Trade/open/close paths
   // explicitly flush all handles when the trade event is written.
   if(filename == "WaveBot_Candles_M1.csv") return false;
   if(filename == "WaveBot_Candles_M15.csv") return false;
   if(filename == "WaveBot_MarketFeatures_M1.csv") return false;
   if(filename == "WaveBot_MarketFeatures_M15.csv") return false;
   if(filename == "WaveBot_TradePath_M1.csv") return false;
   if(filename == "WaveBot_EquityCurve.csv") return false;
   return true;
}

inline void WBLOG_FlushAllOpenFiles()
{
   int total = ArraySize(g_wblog_open_handles);
   for(int i=0; i<total; ++i)
   {
      int h = g_wblog_open_handles[i];
      if(h != INVALID_HANDLE)
         FileFlush(h);
   }
   g_wblog_unflushed_rows = 0;
}

inline bool WBLOG_FlushOpenFileName(const string filename)
{
   int idx = WBLOG_FindOpenFile(filename);
   if(idx < 0)
      return false;

   int h = g_wblog_open_handles[idx];
   if(h == INVALID_HANDLE)
      return false;

   FileFlush(h);
   return true;
}

inline void WBLOG_WriteLineAppend(const string filename, const string line)
{
   if((g_wblog_scheduled_output_enabled || g_wblog_final_only_output_enabled) && !g_wblog_scheduled_output_writing)
   {
      // Before the selected M1 date, avoid disk I/O completely. Keep only
      // low-frequency event rows that cannot be reconstructed from snapshots.
      if(!g_wblog_scheduled_output_done && WBLOG_ShouldBufferBeforeScheduledWrite(filename))
         WBLOG_BufferScheduledRow(filename, line);
      return;
   }

   int h = INVALID_HANDLE;
   if(!WBLOG_OpenAppend(filename, h)) return;

   FileWriteString(h, line + "\r\n");
   g_wblog_unflushed_rows++;

   // PERFORMANCE FIX #4:
   // Immediate files should flush only their own handle. Flushing every open
   // file on each trigger also flushes high-frequency candle/feature/equity
   // files and creates a visible stall at trigger recognition.
   if(WBLOG_ShouldFlushImmediately(filename))
      WBLOG_FlushOpenFileName(filename);
   else if(g_wblog_unflushed_rows >= WBLOG_FLUSH_EVERY_ROWS)
      WBLOG_FlushAllOpenFiles();
}

inline void WBLOG_ResetFile(const string filename, const string header)
{
   if(!g_wblog_ready) return;
   if(!WBLOG_OutputCanWriteNow()) return;
   WBLOG_CloseOpenFile(filename);
   string path = WBLOG_FilePath(filename);
   int h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, header + "\r\n");
   FileFlush(h);
   FileClose(h);
}

inline void WBLOG_RewriteFileWithRows(const string filename, const string header, string &rows[])
{
   if(!g_wblog_ready) return;
   if(!WBLOG_OutputCanWriteNow()) return;

   int n = ArraySize(rows);
   if(n <= 0 && WBLOG_IsHeaderlessWhenEmptyFile(filename))
   {
      WBLOG_DeleteFileIfExists(filename);
      return;
   }

   WBLOG_CloseOpenFile(filename);
   string path = WBLOG_FilePath(filename);
   int h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, header + "\r\n");
   for(int i=0; i<n; ++i)
      FileWriteString(h, rows[i] + "\r\n");
   FileFlush(h);
   FileClose(h);
}

inline double WBLOG_PointOf(const string sym)
{
   double p = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(p <= 0.0) p = _Point;
   if(p <= 0.0) p = 0.00000001;
   return p;
}

inline int WBLOG_DigitsOf(const string sym)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(d <= 0) d = _Digits;
   return d;
}

inline double WBLOG_PipSize(const string sym)
{
   double p = WBLOG_PointOf(sym);
   int d = WBLOG_DigitsOf(sym);
   if(d == 3 || d == 5) return p * 10.0;
   return p;
}

inline double WBLOG_ToPips(const string sym, const double price_distance)
{
   double pip = WBLOG_PipSize(sym);
   if(pip <= 0.0) return 0.0;
   return price_distance / pip;
}

inline string WBLOG_SessionName(const int hour)
{
   if(hour >= 0 && hour < 7) return "ASIA";
   if(hour >= 7 && hour < 13) return "LONDON";
   if(hour >= 13 && hour < 21) return "NEWYORK";
   return "LATE_US";
}

inline int WBLOG_HourOf(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour;
}

inline int WBLOG_DayOfWeekOf(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_week;
}

inline double WBLOG_ATR(const MqlRates &rates[], const int n, const int idx, const int period)
{
   if(n <= 0 || idx < 0 || idx >= n) return 0.0;
   int p = period;
   if(p <= 0) p = 14;
   int from = idx - p + 1;
   if(from < 0) from = 0;
   double sum = 0.0;
   int cnt = 0;
   for(int i=from; i<=idx; ++i)
   {
      double tr = rates[i].high - rates[i].low;
      if(i > 0)
      {
         double a = MathAbs(rates[i].high - rates[i-1].close);
         double b = MathAbs(rates[i].low  - rates[i-1].close);
         if(a > tr) tr = a;
         if(b > tr) tr = b;
      }
      sum += tr;
      cnt++;
   }
   if(cnt <= 0) return 0.0;
   return sum / (double)cnt;
}

inline string WBLOG_FileHeader(const string name)
{
   if(name == "WaveBot_RunConfig.csv")
      return "run_id,symbol,broker,server_timezone,data_timezone,start_time,end_time,ea_version,code_version_or_git_commit,input_direction,timeframe_master,timeframe_slave,initial_capital,risk_percent,spread_mode,commission_mode,notes";
   if(name == "WaveBot_Params.csv")
      return "run_id,param_name,param_value,param_source";
   if(name == "WaveBot_Candles_M15.csv" || name == "WaveBot_Candles_M1.csv")
      return "run_id,bar_index,time,open,high,low,close,tick_volume,real_volume,spread";
   if(name == "WaveBot_M15_MainSignals.csv")
      return "run_id,m15_context_id,signal_type,direction,signal_time,signal_bar_index,signal_open,signal_high,signal_low,signal_close,source_module,is_active,off_time,off_bar_index,off_reason,namespace";
   if(name == "WaveBot_M15_FlipZones.csv")
      return "run_id,m15_context_id,m15_zone_id,zone_type,direction,flip_time,flip_bar_index,flip_open,flip_high,flip_low,flip_close,body_broken_candle_time,body_broken_candle_index,body_broken_candle_high,body_broken_candle_low,zone_low,zone_high,zone_width_pips,invalid_level,zone_status,invalid_time,invalid_bar_index,invalid_reason";
   if(name == "WaveBot_M15_GateEvents.csv")
      return "run_id,event_id,m15_context_id,m15_zone_id,event_time,event_bar_index,event_type,direction,price_open,price_high,price_low,price_close,zone_low,zone_high,details";
   if(name == "WaveBot_M15_To_M1_Bridge.csv")
      return "run_id,bridge_event_id,m15_context_id,m15_zone_id,m1_window_id,event_type,direction,send_time_m15,send_bar_index_m15,effective_start_time_m1,source_signal_type,zone_type,zone_low,zone_high,stop_time,stop_reason,namespace,bridge_seq";
   if(name == "WaveBot_M1_TriggerCandidates.csv")
      return "run_id,candidate_id,m15_context_id,m15_zone_id,m1_window_id,trigger_type,direction,candidate_time,candidate_bar_index,open,high,low,close,is_inside_active_m1_window,is_valid,reject_reason,source_module";
   if(name == "WaveBot_M1_Triggers.csv")
      return "run_id,trigger_id,m15_context_id,m15_zone_id,m1_window_id,trigger_type,direction,trigger_time,trigger_bar_index,trigger_open,trigger_high,trigger_low,trigger_close,entry_price,sl_price,tp_price,risk_pips,reward_pips,rr_multiple,zone_low,zone_high,distance_from_zone_pips,bars_after_m15_retouch,bars_after_m1_window_start,is_trade_candidate,trade_id";
   if(name == "WaveBot_TradeCandidates.csv")
      return "run_id,trade_candidate_id,trigger_id,m15_context_id,m15_zone_id,m1_window_id,trigger_type,direction,candidate_time,entry_price,sl_price,tp_price,risk_pips,risk_money,lot_size,accepted_for_trade,reject_reason";
   if(name == "WaveBot_Trades.csv")
      return "run_id,trade_id,trigger_id,m15_context_id,m15_zone_id,m1_window_id,symbol,direction,trigger_type,m15_signal_type,m15_zone_type,open_time,open_bar_index_m1,entry_price,sl_price,tp_price,close_time,close_bar_index_m1,close_price,close_reason,lot_size,risk_pips,risk_money,profit_pips,profit_money,result_R,commission,swap,spread_at_entry,duration_minutes,duration_bars_m1,win_loss";
   if(name == "WaveBot_TradePath_M1.csv")
      return "run_id,trade_id,m1_bar_index,time,open,high,low,close,entry_price,sl_price,tp_price,floating_pips_at_close,floating_money_at_close,mae_pips_so_far,mfe_pips_so_far,drawdown_pips_from_entry,is_sl_touched,is_tp_touched";
   if(name == "WaveBot_TradeMAE_MFE.csv")
      return "run_id,trade_id,trigger_id,direction,entry_time,exit_time,result_R,mae_pips,mfe_pips,mae_R,mfe_R,bars_to_mae,bars_to_mfe,bars_to_exit,max_adverse_price,max_favorable_price,sl_touched_before_tp,tp_touched_before_sl";
   if(name == "WaveBot_EquityCurve.csv")
      return "run_id,time,balance,equity,floating_pnl,closed_pnl,open_trades_count,drawdown_abs,drawdown_pct,peak_equity";
   if(name == "WaveBot_StateTransitions.csv")
      return "run_id,event_id,time,timeframe,module,state_from,state_to,direction,m15_context_id,m15_zone_id,m1_window_id,trigger_id,reason,bar_index,price_open,price_high,price_low,price_close";
   if(name == "WaveBot_ResetEvents.csv")
      return "run_id,reset_id,time,timeframe,reset_scope,direction,m15_context_id,m15_zone_id,m1_window_id,reason,old_stage,new_stage,price_high,price_low,price_close";
   if(name == "WaveBot_RejectedTriggers.csv")
      return "run_id,candidate_id,trigger_type,direction,time,bar_index,m15_context_id,m15_zone_id,m1_window_id,open,high,low,close,reject_reason,risk_pips,zone_low,zone_high,details";
   if(name == "WaveBot_SummaryByRun.csv")
      return "run_id,symbol,start_time,end_time,total_trades,wins,losses,breakevens,win_rate,net_profit,gross_profit,gross_loss,profit_factor,max_drawdown_abs,max_drawdown_pct,max_consecutive_losses,max_consecutive_wins,average_R,median_R,expectancy_R,average_risk_pips,average_trade_duration_bars,type1_trades,type1_win_rate,type2_trades,type2_win_rate";
   if(name == "WaveBot_MarketFeatures_M1.csv" || name == "WaveBot_MarketFeatures_M15.csv")
      return "run_id,time,bar_index,atr,range,body_size,upper_wick,lower_wick,spread,hour_of_day,day_of_week,session_name";
   return "run_id,details";
}

inline bool WBLOG_IsM15MasterDiagnosticFile(const string filename)
{
   if(filename == "WaveBot_M15_MainSignals.csv")  return true;
   if(filename == "WaveBot_M15_FlipZones.csv")    return true;
   if(filename == "WaveBot_M15_GateEvents.csv")   return true;
   if(filename == "WaveBot_M15_To_M1_Bridge.csv") return true;
   return false;
}

inline bool WBLOG_IsHeaderlessWhenEmptyFile(const string filename)
{
   if(WBLOG_IsM15MasterDiagnosticFile(filename)) return true;
   if(filename == "WaveBot_RejectedTriggers.csv") return true;
   return false;
}

inline bool WBLOG_ShouldPreserveM15MasterDiagnostics()
{
   // The M1 slave shares the same run directory with the M15 master. Its
   // final/deferred CSV rebuild must not blank the M15 master-owned bridge,
   // signal, zone, and gate diagnostics because the M1 chart cannot
   // reconstruct those rows from its local memory.
   if((ENUM_TIMEFRAMES)Period() != PERIOD_M1)
      return false;

   return (g_wblog_scheduled_output_enabled || g_wblog_final_only_output_enabled);
}

inline void WBLOG_DeleteFileIfExists(const string filename)
{
   if(!g_wblog_ready) return;
   if(!WBLOG_OutputCanWriteNow()) return;

   WBLOG_CloseOpenFile(filename);

   string path = WBLOG_FilePath(filename);
   if(FileIsExist(path, FILE_COMMON))
      FileDelete(path, FILE_COMMON);
}

inline void WBLOG_ResetOutputFiles(const bool preserve_m15_master_diagnostics)
{
   // A clean rebuild must reset candle de-dup cursors as well as file contents.
   g_wblog_last_m1_candle  = 0;
   g_wblog_last_m15_candle = 0;

   WBLOG_ResetFile("WaveBot_RunConfig.csv", WBLOG_FileHeader("WaveBot_RunConfig.csv"));
   WBLOG_ResetFile("WaveBot_Params.csv", WBLOG_FileHeader("WaveBot_Params.csv"));
   WBLOG_ResetFile("WaveBot_Candles_M15.csv", WBLOG_FileHeader("WaveBot_Candles_M15.csv"));
   WBLOG_ResetFile("WaveBot_Candles_M1.csv", WBLOG_FileHeader("WaveBot_Candles_M1.csv"));

   if(!preserve_m15_master_diagnostics)
   {
      // These files are event/snapshot diagnostics. Do not create 1 KB
      // header-only CSVs; the first real row will create the file with a
      // header via WBLOG_OpenAppend(), and rewrites with zero rows delete it.
      WBLOG_DeleteFileIfExists("WaveBot_M15_MainSignals.csv");
      WBLOG_DeleteFileIfExists("WaveBot_M15_FlipZones.csv");
      WBLOG_DeleteFileIfExists("WaveBot_M15_GateEvents.csv");
      WBLOG_DeleteFileIfExists("WaveBot_M15_To_M1_Bridge.csv");
   }

   WBLOG_ResetFile("WaveBot_M1_TriggerCandidates.csv", WBLOG_FileHeader("WaveBot_M1_TriggerCandidates.csv"));
   WBLOG_ResetFile("WaveBot_M1_Triggers.csv", WBLOG_FileHeader("WaveBot_M1_Triggers.csv"));
   WBLOG_ResetFile("WaveBot_TradeCandidates.csv", WBLOG_FileHeader("WaveBot_TradeCandidates.csv"));
   WBLOG_ResetFile("WaveBot_Trades.csv", WBLOG_FileHeader("WaveBot_Trades.csv"));
   WBLOG_ResetFile("WaveBot_TradePath_M1.csv", WBLOG_FileHeader("WaveBot_TradePath_M1.csv"));
   WBLOG_ResetFile("WaveBot_TradeMAE_MFE.csv", WBLOG_FileHeader("WaveBot_TradeMAE_MFE.csv"));
   WBLOG_ResetFile("WaveBot_EquityCurve.csv", WBLOG_FileHeader("WaveBot_EquityCurve.csv"));
   WBLOG_ResetFile("WaveBot_StateTransitions.csv", WBLOG_FileHeader("WaveBot_StateTransitions.csv"));
   WBLOG_ResetFile("WaveBot_ResetEvents.csv", WBLOG_FileHeader("WaveBot_ResetEvents.csv"));

   // Optional: create only when at least one rejection row really exists.
   WBLOG_DeleteFileIfExists("WaveBot_RejectedTriggers.csv");

   WBLOG_ResetFile("WaveBot_SummaryByRun.csv", WBLOG_FileHeader("WaveBot_SummaryByRun.csv"));
   WBLOG_ResetFile("WaveBot_MarketFeatures_M1.csv", WBLOG_FileHeader("WaveBot_MarketFeatures_M1.csv"));
   WBLOG_ResetFile("WaveBot_MarketFeatures_M15.csv", WBLOG_FileHeader("WaveBot_MarketFeatures_M15.csv"));

   g_wblog_snapshot_dirty_contexts = false;
   g_wblog_snapshot_dirty_zones    = false;
}

inline void WBLOG_ResetM1FinalOutputFiles()
{
   WBLOG_ResetOutputFiles(true);
}

inline void WBLOG_ResetAllFiles()
{
   WBLOG_ResetOutputFiles(false);
}

inline void WBLOG_BeginScheduledOutputWrite()
{
   if(!g_wblog_scheduled_output_enabled && !g_wblog_final_only_output_enabled)
      return;
   if(g_wblog_scheduled_output_done)
      return;
   if(!g_wblog_ready)
      return;

   g_wblog_scheduled_output_writing = true;

   const bool preserve_m15_master_diagnostics = WBLOG_ShouldPreserveM15MasterDiagnostics();

   // Create a clean CSV set exactly at the final/deferred output point.
   // On the M1 slave, keep the master-owned M15 diagnostic files intact;
   // otherwise the final M1 rebuild erases signal/zone/gate/bridge rows that
   // were already produced by the M15 master.
   if(preserve_m15_master_diagnostics)
      WBLOG_ResetM1FinalOutputFiles();
   else
      WBLOG_ResetAllFiles();

   // Replay buffered low-frequency rows accumulated before the scheduled date.
   int n = ArraySize(g_wblog_deferred_rows);
   for(int i=0; i<n; ++i)
      WBLOG_WriteLineAppend(g_wblog_deferred_names[i], g_wblog_deferred_rows[i]);

   ArrayResize(g_wblog_deferred_names, 0);
   ArrayResize(g_wblog_deferred_rows, 0);

   // Context and zone files are snapshot files. The M1 slave must not rewrite
   // them from its empty local context arrays because those rows belong to the
   // M15 master and have already been written in the shared run directory.
   if(!preserve_m15_master_diagnostics)
   {
      WBLOG_RewriteM15MainSignals();
      WBLOG_RewriteM15Zones();
   }
}

inline void WBLOG_EndScheduledOutputWrite(const bool mark_done)
{
   if(!g_wblog_scheduled_output_enabled && !g_wblog_final_only_output_enabled)
      return;

   WBLOG_FlushAllOpenFiles();
   WBLOG_CloseAllFiles();
   g_wblog_scheduled_output_writing = false;
   if(mark_done)
      g_wblog_scheduled_output_done = true;
}

inline string WBLOG_MakeRunId(const string sym, const datetime t)
{
   string s = sym + "_" + TimeToString(t, TIME_DATE|TIME_SECONDS);
   StringReplace(s, ":", "");
   StringReplace(s, ".", "");
   StringReplace(s, " ", "_");
   StringReplace(s, "/", "_");
   StringReplace(s, "\\", "_");
   return s;
}

inline void WBLOG_Initialize(const string sym,
                             const ENUM_TIMEFRAMES master_tf,
                             const ENUM_TIMEFRAMES slave_tf,
                             const datetime scan_from,
                             const datetime scan_to,
                             const double initial_capital,
                             const double risk_percent,
                             const string input_direction,
                             const string version_tag,
                             const bool force_new_run)
{
   string use_sym = sym;
   if(use_sym == "") use_sym = _Symbol;

   string key = "WBLOG_RUN_" + use_sym;
   StringReplace(key, ".", "_");
   StringReplace(key, "#", "_");

   double gv = 0.0;
   if(force_new_run || !GlobalVariableCheck(key))
   {
      gv = (double)TimeCurrent();
      GlobalVariableSet(key, gv);
   }
   else
   {
      gv = GlobalVariableGet(key);
      if(gv <= 0.0)
      {
         gv = (double)TimeCurrent();
         GlobalVariableSet(key, gv);
      }
   }

   datetime run_time = (datetime)gv;
   g_wblog_run_id = WBLOG_MakeRunId(use_sym, run_time);
   g_wblog_dir = "WaveBot_Logs\\" + g_wblog_run_id;

   FolderCreate("WaveBot_Logs", FILE_COMMON);
   FolderCreate(g_wblog_dir, FILE_COMMON);

   g_wblog_ready = true;

   string init_key = "WBLOG_INIT_" + g_wblog_run_id;
   bool need_reset = force_new_run || !GlobalVariableCheck(init_key);
   if(need_reset)
   {
      WBLOG_ResetAllFiles();
      GlobalVariableSet(init_key, 1.0);
   }

   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, use_sym);
   row = WBLOG_AppendCell(row, AccountInfoString(ACCOUNT_COMPANY));
   row = WBLOG_AppendCell(row, "SERVER_TIME");
   row = WBLOG_AppendCell(row, "SERVER_TIME");
   row = WBLOG_AppendCell(row, WBLOG_Time(scan_from));
   row = WBLOG_AppendCell(row, WBLOG_Time(scan_to));
   row = WBLOG_AppendCell(row, "WaveBot");
   row = WBLOG_AppendCell(row, version_tag);
   row = WBLOG_AppendCell(row, input_direction);
   row = WBLOG_AppendCell(row, WBLOG_TFName(master_tf));
   row = WBLOG_AppendCell(row, WBLOG_TFName(slave_tf));
   row = WBLOG_AppendCell(row, WBLOG_Double(initial_capital, 2));
   row = WBLOG_AppendCell(row, WBLOG_Double(risk_percent, 4));
   row = WBLOG_AppendCell(row, "BAR_SPREAD_FIELD");
   row = WBLOG_AppendCell(row, "NOT_APPLIED_IN_STATEMENT");
   row = WBLOG_AppendCell(row, "diagnostic_logger_initialized");
   WBLOG_WriteLineAppend("WaveBot_RunConfig.csv", row);
}

inline string WBLOG_RunId()
{
   return g_wblog_run_id;
}

inline void WBLOG_LogParam(const string name, const string value, const string source)
{
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, name);
   row = WBLOG_AppendCell(row, value);
   row = WBLOG_AppendCell(row, source);
   WBLOG_WriteLineAppend("WaveBot_Params.csv", row);
}

inline void WBLOG_FlushSnapshotFilesIfDirty()
{
   if(!g_wblog_ready) return;

   if(WBLOG_ShouldPreserveM15MasterDiagnostics())
   {
      // M1 final/deferred output shares the run directory but does not own the
      // M15 snapshot arrays. Preserve the master files exactly as written by
      // the M15 chart.
      g_wblog_snapshot_dirty_contexts = false;
      g_wblog_snapshot_dirty_zones    = false;
      return;
   }

   if(g_wblog_snapshot_dirty_contexts)
   {
      WBLOG_RewriteM15MainSignals();
      g_wblog_snapshot_dirty_contexts = false;
   }

   if(g_wblog_snapshot_dirty_zones)
   {
      WBLOG_RewriteM15Zones();
      g_wblog_snapshot_dirty_zones = false;
   }
}

inline void WBLOG_Finalize()
{
   if(!g_wblog_ready)
      return;

   // In deferred M1 output mode, no extra final write is allowed here. The only
   // output write happens at terminal M1 hard stop. Finalize only closes handles.
   if(g_wblog_scheduled_output_enabled || g_wblog_final_only_output_enabled)
   {
      WBLOG_CloseAllFiles();
      g_wblog_ready = false;
      return;
   }

   WBLOG_FlushSnapshotFilesIfDirty();

   string row = "";
   row = WBLOG_AppendCell(row, WBLOG_RunId());
   row = WBLOG_AppendCell(row, IntegerToString(++g_wblog_state_seq));
   row = WBLOG_AppendCell(row, WBLOG_Time(TimeCurrent()));
   row = WBLOG_AppendCell(row, WBLOG_TFName((ENUM_TIMEFRAMES)Period()));
   row = WBLOG_AppendCell(row, "WaveBotLogger");
   row = WBLOG_AppendCell(row, "RUNNING");
   row = WBLOG_AppendCell(row, "FINALIZED");
   row = WBLOG_AppendCell(row, "");
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_context_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_window_id));
   row = WBLOG_AppendCell(row, "0");
   row = WBLOG_AppendCell(row, "WaveBotLogger_Finalize");
   row = WBLOG_AppendCell(row, "0");
   row = WBLOG_AppendCell(row, "0");
   row = WBLOG_AppendCell(row, "0");
   row = WBLOG_AppendCell(row, "0");
   row = WBLOG_AppendCell(row, "0");
   WBLOG_WriteLineAppend("WaveBot_StateTransitions.csv", row);

   WBLOG_FlushAllOpenFiles();
   WBLOG_CloseAllFiles();
   g_wblog_ready = false;
}

inline void WBLOG_LogCandleAndFeatures(const string sym,
                                       const ENUM_TIMEFRAMES tf,
                                       const MqlRates &rates[],
                                       const int n,
                                       const int bar_idx)
{
   if(!g_wblog_ready) return;
   if(!WBLOG_OutputCanWriteNow()) return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n) return;

   const datetime t = rates[bar_idx].time;
   if(t <= 0) return;

   if(tf == PERIOD_M15)
   {
      if(g_wblog_last_m15_candle > 0 && t <= g_wblog_last_m15_candle) return;
      g_wblog_last_m15_candle = t;
   }
   else if(tf == PERIOD_M1)
   {
      if(g_wblog_last_m1_candle > 0 && t <= g_wblog_last_m1_candle) return;
      g_wblog_last_m1_candle = t;
   }
   else
      return;

   string file = (tf == PERIOD_M15 ? "WaveBot_Candles_M15.csv" : "WaveBot_Candles_M1.csv");
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(bar_idx));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, WBLOG_Double(rates[bar_idx].open, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(rates[bar_idx].high, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(rates[bar_idx].low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(rates[bar_idx].close, 8));
   row = WBLOG_AppendCell(row, IntegerToString((int)rates[bar_idx].tick_volume));
   row = WBLOG_AppendCell(row, IntegerToString((int)rates[bar_idx].real_volume));
   row = WBLOG_AppendCell(row, IntegerToString(rates[bar_idx].spread));
   WBLOG_WriteLineAppend(file, row);

   double range = rates[bar_idx].high - rates[bar_idx].low;
   double body  = MathAbs(rates[bar_idx].close - rates[bar_idx].open);
   double upper = rates[bar_idx].high - MathMax(rates[bar_idx].open, rates[bar_idx].close);
   double lower = MathMin(rates[bar_idx].open, rates[bar_idx].close) - rates[bar_idx].low;
   double atr   = WBLOG_ATR(rates, n, bar_idx, 14);
   int hour     = WBLOG_HourOf(t);
   int dow      = WBLOG_DayOfWeekOf(t);

   string ffile = (tf == PERIOD_M15 ? "WaveBot_MarketFeatures_M15.csv" : "WaveBot_MarketFeatures_M1.csv");
   string frow = "";
   frow = WBLOG_AppendCell(frow, g_wblog_run_id);
   frow = WBLOG_AppendCell(frow, WBLOG_Time(t));
   frow = WBLOG_AppendCell(frow, IntegerToString(bar_idx));
   frow = WBLOG_AppendCell(frow, WBLOG_Double(atr, 8));
   frow = WBLOG_AppendCell(frow, WBLOG_Double(range, 8));
   frow = WBLOG_AppendCell(frow, WBLOG_Double(body, 8));
   frow = WBLOG_AppendCell(frow, WBLOG_Double(upper, 8));
   frow = WBLOG_AppendCell(frow, WBLOG_Double(lower, 8));
   frow = WBLOG_AppendCell(frow, IntegerToString(rates[bar_idx].spread));
   frow = WBLOG_AppendCell(frow, IntegerToString(hour));
   frow = WBLOG_AppendCell(frow, IntegerToString(dow));
   frow = WBLOG_AppendCell(frow, WBLOG_SessionName(hour));
   WBLOG_WriteLineAppend(ffile, frow);
}

inline void WBLOG_ExportCandlesSnapshotForTF(const string sym,
                                               const ENUM_TIMEFRAMES tf,
                                               const datetime from_time,
                                               const datetime to_time)
{
   if(!g_wblog_ready) return;
   if(!WBLOG_OutputCanWriteNow()) return;
   if(to_time <= 0) return;

   datetime use_from = from_time;
   if(use_from <= 0)
      use_from = (datetime)1;
   if(to_time < use_from)
      return;

   MqlRates rr[];
   ArrayFree(rr);
   int copied = CopyRates(sym, tf, use_from, to_time, rr);
   if(copied <= 0)
      return;

   ArraySetAsSeries(rr, false);
   for(int i=0; i<copied; ++i)
      WBLOG_LogCandleAndFeatures(sym, tf, rr, copied, i);
}

inline void WBLOG_ExportScheduledCandleSnapshots(const string sym,
                                                 const datetime from_time,
                                                 const datetime to_time)
{
   WBLOG_ExportCandlesSnapshotForTF(sym, PERIOD_M15, from_time, to_time);
   WBLOG_ExportCandlesSnapshotForTF(sym, PERIOD_M1,  from_time, to_time);
}

inline bool WBLOG_GetM15BarByTime(const string sym, const datetime t, MqlRates &bar, int &bar_index)
{
   bar_index = -1;
   if(t <= 0) return false;
   int sh = iBarShift(sym, PERIOD_M15, t, false);
   if(sh < 0) return false;
   MqlRates rr[1];
   if(CopyRates(sym, PERIOD_M15, sh, 1, rr) != 1) return false;
   bar = rr[0];
   bar_index = sh;
   return true;
}

inline string WBLOG_ContextRowToCSV(const WBLogM15ContextRow &r)
{
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(r.id));
   row = WBLOG_AppendCell(row, WBLOG_KindName(r.signal_type));
   row = WBLOG_AppendCell(row, WBLOG_DirName(r.dir));
   row = WBLOG_AppendCell(row, WBLOG_Time(r.signal_time));
   row = WBLOG_AppendCell(row, IntegerToString((int)r.signal_bar_time));
   row = WBLOG_AppendCell(row, WBLOG_Double(r.o, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(r.h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(r.l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(r.c, 8));
   row = WBLOG_AppendCell(row, r.source_module);
   row = WBLOG_AppendCell(row, (r.active ? "true" : "false"));
   row = WBLOG_AppendCell(row, WBLOG_Time(r.off_time));
   row = WBLOG_AppendCell(row, IntegerToString((int)r.off_bar_time));
   row = WBLOG_AppendCell(row, r.off_reason);
   row = WBLOG_AppendCell(row, WBLOG_NsName(r.ns));
   return row;
}

inline void WBLOG_RewriteM15MainSignals()
{
   string rows[];
   ArrayResize(rows, 0);
   int n = ArraySize(g_wblog_contexts);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_contexts[i].used) continue;
      int p = ArraySize(rows);
      ArrayResize(rows, p+1);
      rows[p] = WBLOG_ContextRowToCSV(g_wblog_contexts[i]);
   }
   WBLOG_RewriteFileWithRows("WaveBot_M15_MainSignals.csv", WBLOG_FileHeader("WaveBot_M15_MainSignals.csv"), rows);
}

inline string WBLOG_ZoneRowToCSV(const WBLogM15ZoneRow &z)
{
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(z.context_id));
   row = WBLOG_AppendCell(row, IntegerToString(z.zone_id));
   row = WBLOG_AppendCell(row, WBLOG_ZoneTypeName(z.zone_source, z.zone_kind));
   row = WBLOG_AppendCell(row, WBLOG_DirName(z.dir));
   row = WBLOG_AppendCell(row, WBLOG_Time(z.flip_time));
   row = WBLOG_AppendCell(row, IntegerToString((int)z.flip_time));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.flip_open, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.flip_high, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.flip_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.flip_close, 8));
   row = WBLOG_AppendCell(row, WBLOG_Time(z.anchor_time));
   row = WBLOG_AppendCell(row, IntegerToString((int)z.anchor_time));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.anchor_high, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.anchor_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.zone_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.zone_high, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.zone_width_pips, 3));
   row = WBLOG_AppendCell(row, WBLOG_Double(z.invalid_level, 8));
   row = WBLOG_AppendCell(row, z.status);
   row = WBLOG_AppendCell(row, WBLOG_Time(z.invalid_time));
   row = WBLOG_AppendCell(row, IntegerToString(z.invalid_bar_index));
   row = WBLOG_AppendCell(row, z.invalid_reason);
   return row;
}

inline void WBLOG_RewriteM15Zones()
{
   string rows[];
   ArrayResize(rows, 0);
   int n = ArraySize(g_wblog_zones);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_zones[i].used) continue;
      int p = ArraySize(rows);
      ArrayResize(rows, p+1);
      rows[p] = WBLOG_ZoneRowToCSV(g_wblog_zones[i]);
   }
   WBLOG_RewriteFileWithRows("WaveBot_M15_FlipZones.csv", WBLOG_FileHeader("WaveBot_M15_FlipZones.csv"), rows);
}

inline void WBLOG_AppendM15MainSignalSnapshot(const WBLogM15ContextRow &r)
{
   if(!g_wblog_ready) return;
   WBLOG_WriteLineAppend("WaveBot_M15_MainSignals.csv", WBLOG_ContextRowToCSV(r));
   g_wblog_snapshot_dirty_contexts = true;
}

inline void WBLOG_AppendM15ZoneSnapshot(const WBLogM15ZoneRow &z)
{
   if(!g_wblog_ready) return;
   WBLOG_WriteLineAppend("WaveBot_M15_FlipZones.csv", WBLOG_ZoneRowToCSV(z));
   g_wblog_snapshot_dirty_zones = true;
}

inline void WBLOG_LogStateTransition(const string module,
                                     const string state_from,
                                     const string state_to,
                                     const Direction dir,
                                     const int context_id,
                                     const int zone_id,
                                     const int window_id,
                                     const int trigger_id,
                                     const string reason,
                                     const datetime t,
                                     const ENUM_TIMEFRAMES tf,
                                     const int bar_index,
                                     const double o,
                                     const double h,
                                     const double l,
                                     const double c)
{
   ++g_wblog_state_seq;
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_state_seq));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, WBLOG_TFName(tf));
   row = WBLOG_AppendCell(row, module);
   row = WBLOG_AppendCell(row, state_from);
   row = WBLOG_AppendCell(row, state_to);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, IntegerToString(context_id));
   row = WBLOG_AppendCell(row, IntegerToString(zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(window_id));
   row = WBLOG_AppendCell(row, IntegerToString(trigger_id));
   row = WBLOG_AppendCell(row, reason);
   row = WBLOG_AppendCell(row, IntegerToString(bar_index));
   row = WBLOG_AppendCell(row, WBLOG_Double(o, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(c, 8));
   WBLOG_WriteLineAppend("WaveBot_StateTransitions.csv", row);
}

inline void WBLOG_LogResetEvent(const string scope,
                                const Direction dir,
                                const int context_id,
                                const int zone_id,
                                const int window_id,
                                const string reason,
                                const string old_stage,
                                const string new_stage,
                                const datetime t,
                                const ENUM_TIMEFRAMES tf,
                                const double h,
                                const double l,
                                const double c)
{
   ++g_wblog_reset_seq;
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_reset_seq));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, WBLOG_TFName(tf));
   row = WBLOG_AppendCell(row, scope);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, IntegerToString(context_id));
   row = WBLOG_AppendCell(row, IntegerToString(zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(window_id));
   row = WBLOG_AppendCell(row, reason);
   row = WBLOG_AppendCell(row, old_stage);
   row = WBLOG_AppendCell(row, new_stage);
   row = WBLOG_AppendCell(row, WBLOG_Double(h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(c, 8));
   WBLOG_WriteLineAppend("WaveBot_ResetEvents.csv", row);
}

inline void WBLOG_LogM15GateEvent(const int context_id,
                                  const int zone_id,
                                  const string event_type,
                                  const Direction dir,
                                  const datetime t,
                                  const int bar_index,
                                  const double o,
                                  const double h,
                                  const double l,
                                  const double c,
                                  const double zone_low,
                                  const double zone_high,
                                  const string details)
{
   ++g_wblog_event_seq;
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_event_seq));
   row = WBLOG_AppendCell(row, IntegerToString(context_id));
   row = WBLOG_AppendCell(row, IntegerToString(zone_id));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, IntegerToString(bar_index));
   row = WBLOG_AppendCell(row, event_type);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, WBLOG_Double(o, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(c, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_high, 8));
   row = WBLOG_AppendCell(row, details);
   WBLOG_WriteLineAppend("WaveBot_M15_GateEvents.csv", row);
}

inline int WBLOG_M15MainSignalStart(const string sym,
                                    const int kind,
                                    const int ns,
                                    const Direction dir,
                                    const datetime signal_time,
                                    const datetime signal_bar_time)
{
   ++g_wblog_context_seq;
   WBLogM15ContextRow r;
   r.used = true;
   r.active = true;
   r.id = g_wblog_context_seq;
   r.signal_type = kind;
   r.ns = ns;
   r.dir = dir;
   r.signal_time = signal_time;
   r.signal_bar_time = signal_bar_time;
   r.o = 0.0; r.h = 0.0; r.l = 0.0; r.c = 0.0;
   r.source_module = "WB15_SignalBridge";
   r.off_time = 0;
   r.off_bar_time = 0;
   r.off_reason = "";

   MqlRates b;
   int bi = -1;
   if(WBLOG_GetM15BarByTime(sym, signal_bar_time, b, bi))
   {
      r.o = b.open; r.h = b.high; r.l = b.low; r.c = b.close;
   }

   int pos = ArraySize(g_wblog_contexts);
   ArrayResize(g_wblog_contexts, pos+1);
   g_wblog_contexts[pos] = r;
   WBLOG_AppendM15MainSignalSnapshot(r);

   WBLOG_LogM15GateEvent(r.id, 0, "MAIN_SIGNAL_ON", dir, signal_time, bi, r.o, r.h, r.l, r.c, 0.0, 0.0,
                         WBLOG_KindName(kind) + "|" + WBLOG_NsName(ns));
   WBLOG_LogStateTransition("WB15_SignalBridge", "IDLE", "STAGE_1_MAIN_SIGNAL", dir, r.id, 0, 0, 0,
                            "MAIN_SIGNAL_ON_" + WBLOG_KindName(kind), signal_time, PERIOD_M15, bi, r.o, r.h, r.l, r.c);
   return r.id;
}

inline void WBLOG_M15MainSignalOff(const int context_id,
                                   const Direction dir,
                                   const datetime off_time,
                                   const string reason)
{
   int n = ArraySize(g_wblog_contexts);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_contexts[i].used) continue;
      if(g_wblog_contexts[i].id != context_id) continue;
      g_wblog_contexts[i].active = false;
      g_wblog_contexts[i].off_time = off_time;
      g_wblog_contexts[i].off_bar_time = off_time;
      g_wblog_contexts[i].off_reason = reason;
      WBLOG_AppendM15MainSignalSnapshot(g_wblog_contexts[i]);
      WBLOG_LogM15GateEvent(context_id, 0, "MAIN_SIGNAL_OFF", dir, off_time, (int)off_time, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, reason);
      WBLOG_LogResetEvent("FULL_M15_CONTEXT_RESET", dir, context_id, 0, 0, reason, "ANY_STAGE", "STAGE_1_SEARCH", off_time, PERIOD_M15, 0.0, 0.0, 0.0);
      return;
   }
}

inline int WBLOG_M15FlipZoneCreated(const string sym,
                                    const int context_id,
                                    const int zone_source,
                                    const int zone_kind,
                                    const Direction dir,
                                    const datetime flip_time,
                                    const datetime anchor_time,
                                    const double zone_low,
                                    const double zone_high,
                                    const double invalid_level)
{
   ++g_wblog_zone_seq;
   WBLogM15ZoneRow z;
   z.used = true;
   z.context_id = context_id;
   z.zone_id = g_wblog_zone_seq;
   z.zone_source = zone_source;
   z.zone_kind = zone_kind;
   z.dir = dir;
   z.flip_time = flip_time;
   z.anchor_time = anchor_time;
   z.flip_open = 0.0; z.flip_high = 0.0; z.flip_low = 0.0; z.flip_close = 0.0;
   z.anchor_high = 0.0; z.anchor_low = 0.0;
   z.zone_low = zone_low;
   z.zone_high = zone_high;
   z.zone_width_pips = WBLOG_ToPips(sym, MathAbs(zone_high - zone_low));
   z.invalid_level = invalid_level;
   z.status = "ACTIVE";
   z.invalid_time = 0;
   z.invalid_bar_index = -1;
   z.invalid_reason = "";

   MqlRates fb; int fbi = -1;
   if(WBLOG_GetM15BarByTime(sym, flip_time, fb, fbi))
   {
      z.flip_open = fb.open;
      z.flip_high = fb.high;
      z.flip_low  = fb.low;
      z.flip_close= fb.close;
   }
   MqlRates ab; int abi = -1;
   if(WBLOG_GetM15BarByTime(sym, anchor_time, ab, abi))
   {
      z.anchor_high = ab.high;
      z.anchor_low  = ab.low;
   }

   int pos = ArraySize(g_wblog_zones);
   ArrayResize(g_wblog_zones, pos+1);
   g_wblog_zones[pos] = z;
   WBLOG_AppendM15ZoneSnapshot(z);

   WBLOG_LogM15GateEvent(context_id, z.zone_id, (zone_source == 2 ? "MAJICFLIP_ZONE_CREATED" : "FLIP_ZONE_CREATED"), dir,
                         flip_time, fbi, z.flip_open, z.flip_high, z.flip_low, z.flip_close, zone_low, zone_high,
                         WBLOG_ZoneTypeName(zone_source, zone_kind));
   WBLOG_LogStateTransition("WB15_SignalBridge", "STAGE_1_MAIN_SIGNAL", "STAGE_2_ZONE_ACTIVE", dir, context_id, z.zone_id, 0, 0,
                            "M15_" + WBLOG_ZoneTypeName(zone_source, zone_kind) + "_ZONE_CREATED", flip_time, PERIOD_M15, fbi,
                            z.flip_open, z.flip_high, z.flip_low, z.flip_close);
   return z.zone_id;
}

inline void WBLOG_M15ZoneStatus(const int zone_id,
                                const string status,
                                const datetime t,
                                const int bar_index,
                                const string reason)
{
   int n = ArraySize(g_wblog_zones);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_zones[i].used) continue;
      if(g_wblog_zones[i].zone_id != zone_id) continue;
      g_wblog_zones[i].status = status;
      if(status == "INVALIDATED")
      {
         g_wblog_zones[i].invalid_time = t;
         g_wblog_zones[i].invalid_bar_index = bar_index;
         g_wblog_zones[i].invalid_reason = reason;
      }
      WBLOG_AppendM15ZoneSnapshot(g_wblog_zones[i]);
      return;
   }
}

inline void WBLOG_M15BridgeEvent(const int context_id,
                                 const int zone_id,
                                 const int m1_window_id,
                                 const string event_type,
                                 const Direction dir,
                                 const datetime send_time_m15,
                                 const datetime effective_start_time_m1,
                                 const int source_kind,
                                 const int zone_source,
                                 const int zone_kind,
                                 const double zone_low,
                                 const double zone_high,
                                 const datetime stop_time,
                                 const string stop_reason,
                                 const int ns,
                                 const int bridge_seq)
{
   ++g_wblog_bridge_seq;
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_bridge_seq));
   row = WBLOG_AppendCell(row, IntegerToString(context_id));
   row = WBLOG_AppendCell(row, IntegerToString(zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(m1_window_id));
   row = WBLOG_AppendCell(row, event_type);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, WBLOG_Time(send_time_m15));
   row = WBLOG_AppendCell(row, IntegerToString((int)send_time_m15));
   row = WBLOG_AppendCell(row, WBLOG_Time(effective_start_time_m1));
   row = WBLOG_AppendCell(row, WBLOG_KindName(source_kind));
   row = WBLOG_AppendCell(row, WBLOG_ZoneTypeName(zone_source, zone_kind));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_high, 8));
   row = WBLOG_AppendCell(row, WBLOG_Time(stop_time));
   row = WBLOG_AppendCell(row, stop_reason);
   row = WBLOG_AppendCell(row, WBLOG_NsName(ns));
   row = WBLOG_AppendCell(row, IntegerToString(bridge_seq));
   WBLOG_WriteLineAppend("WaveBot_M15_To_M1_Bridge.csv", row);
}

inline void WBLOG_SetCurrentTriggerContext(const int context_id,
                                           const int zone_id,
                                           const int window_id,
                                           const int start_kind,
                                           const int start_ns,
                                           const Direction dir,
                                           const datetime window_start,
                                           const datetime window_bar)
{
   g_wblog_cur_context_id = context_id;
   g_wblog_cur_zone_id    = zone_id;
   g_wblog_cur_window_id  = window_id;
   g_wblog_cur_start_kind = start_kind;
   g_wblog_cur_start_ns   = start_ns;
   g_wblog_cur_dir        = dir;
   g_wblog_cur_window_start = window_start;
   g_wblog_cur_window_bar   = window_bar;
}

inline int WBLOG_LogM1TriggerCandidate(const int type_id,
                                       const Direction dir,
                                       const datetime t,
                                       const int bar_index,
                                       const double o,
                                       const double h,
                                       const double l,
                                       const double c,
                                       const bool inside_active_window,
                                       const bool is_valid,
                                       const string reject_reason,
                                       const string source_module)
{
   ++g_wblog_candidate_seq;
   g_wblog_last_candidate_id = g_wblog_candidate_seq;

   string trigger_type = (type_id == 2 ? "TYPE2_MAJICFLIP" : "TYPE1_FLIP");
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_candidate_seq));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_context_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_window_id));
   row = WBLOG_AppendCell(row, trigger_type);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, IntegerToString(bar_index));
   row = WBLOG_AppendCell(row, WBLOG_Double(o, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(c, 8));
   row = WBLOG_AppendCell(row, (inside_active_window ? "true" : "false"));
   row = WBLOG_AppendCell(row, (is_valid ? "true" : "false"));
   row = WBLOG_AppendCell(row, reject_reason);
   row = WBLOG_AppendCell(row, source_module);
   WBLOG_WriteLineAppend("WaveBot_M1_TriggerCandidates.csv", row);
   return g_wblog_candidate_seq;
}

inline void WBLOG_LogRejectedTrigger(const int type_id,
                                     const Direction dir,
                                     const datetime t,
                                     const int bar_index,
                                     const double o,
                                     const double h,
                                     const double l,
                                     const double c,
                                     const string reject_reason,
                                     const double risk_pips,
                                     const double zone_low,
                                     const double zone_high,
                                     const string details)
{
   int cid = g_wblog_last_candidate_id;
   if(cid <= 0)
   {
      ++g_wblog_candidate_seq;
      cid = g_wblog_candidate_seq;
      g_wblog_last_candidate_id = cid;
   }
   ++g_wblog_reject_seq;
   string trigger_type = (type_id == 2 ? "TYPE2_MAJICFLIP" : "TYPE1_FLIP");
   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(cid));
   row = WBLOG_AppendCell(row, trigger_type);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, IntegerToString(bar_index));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_context_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_window_id));
   row = WBLOG_AppendCell(row, WBLOG_Double(o, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(c, 8));
   row = WBLOG_AppendCell(row, reject_reason);
   row = WBLOG_AppendCell(row, WBLOG_Double(risk_pips, 3));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_high, 8));
   row = WBLOG_AppendCell(row, details);
   WBLOG_WriteLineAppend("WaveBot_RejectedTriggers.csv", row);
}

inline void WBLOG_LogM1TriggerFinal(const string sym,
                                    const int trigger_id,
                                    const int type_id,
                                    const Direction dir,
                                    const datetime t,
                                    const int bar_index,
                                    const double o,
                                    const double h,
                                    const double l,
                                    const double c,
                                    const double entry,
                                    const double sl,
                                    const double tp,
                                    const double risk_pips,
                                    const int trade_id)
{
   string trigger_type = (type_id == 2 ? "TYPE2_MAJICFLIP" : "TYPE1_FLIP");
   double reward_pips = WBLOG_ToPips(sym, MathAbs(tp - entry));
   double rr = 0.0;
   if(risk_pips > 0.0) rr = reward_pips / risk_pips;

   double zone_low = 0.0;
   double zone_high = 0.0;
   int zn = ArraySize(g_wblog_zones);
   for(int i=0; i<zn; ++i)
   {
      if(!g_wblog_zones[i].used) continue;
      if(g_wblog_zones[i].zone_id != g_wblog_cur_zone_id) continue;
      zone_low = g_wblog_zones[i].zone_low;
      zone_high = g_wblog_zones[i].zone_high;
      break;
   }
   double dist_zone = 0.0;
   if(zone_low > 0.0 || zone_high > 0.0)
   {
      if(entry < zone_low) dist_zone = WBLOG_ToPips(sym, zone_low - entry);
      else if(entry > zone_high) dist_zone = WBLOG_ToPips(sym, entry - zone_high);
      else dist_zone = 0.0;
   }

   int tfsec = PeriodSeconds(PERIOD_M1);
   if(tfsec <= 0) tfsec = 60;
   int bars_after_start = 0;
   if(g_wblog_cur_window_bar > 0 && t >= g_wblog_cur_window_bar)
      bars_after_start = (int)((t - g_wblog_cur_window_bar) / tfsec);

   string row = "";
   row = WBLOG_AppendCell(row, g_wblog_run_id);
   row = WBLOG_AppendCell(row, IntegerToString(trigger_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_context_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_zone_id));
   row = WBLOG_AppendCell(row, IntegerToString(g_wblog_cur_window_id));
   row = WBLOG_AppendCell(row, trigger_type);
   row = WBLOG_AppendCell(row, WBLOG_DirName(dir));
   row = WBLOG_AppendCell(row, WBLOG_Time(t));
   row = WBLOG_AppendCell(row, IntegerToString(bar_index));
   row = WBLOG_AppendCell(row, WBLOG_Double(o, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(h, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(l, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(c, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(entry, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(sl, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(tp, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(risk_pips, 3));
   row = WBLOG_AppendCell(row, WBLOG_Double(reward_pips, 3));
   row = WBLOG_AppendCell(row, WBLOG_Double(rr, 3));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_low, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(zone_high, 8));
   row = WBLOG_AppendCell(row, WBLOG_Double(dist_zone, 3));
   row = WBLOG_AppendCell(row, "0");
   row = WBLOG_AppendCell(row, IntegerToString(bars_after_start));
   row = WBLOG_AppendCell(row, "true");
   row = WBLOG_AppendCell(row, IntegerToString(trade_id));
   WBLOG_WriteLineAppend("WaveBot_M1_Triggers.csv", row);

   string crow = "";
   crow = WBLOG_AppendCell(crow, g_wblog_run_id);
   crow = WBLOG_AppendCell(crow, IntegerToString(trade_id));
   crow = WBLOG_AppendCell(crow, IntegerToString(trigger_id));
   crow = WBLOG_AppendCell(crow, IntegerToString(g_wblog_cur_context_id));
   crow = WBLOG_AppendCell(crow, IntegerToString(g_wblog_cur_zone_id));
   crow = WBLOG_AppendCell(crow, IntegerToString(g_wblog_cur_window_id));
   crow = WBLOG_AppendCell(crow, trigger_type);
   crow = WBLOG_AppendCell(crow, WBLOG_DirName(dir));
   crow = WBLOG_AppendCell(crow, WBLOG_Time(t));
   crow = WBLOG_AppendCell(crow, WBLOG_Double(entry, 8));
   crow = WBLOG_AppendCell(crow, WBLOG_Double(sl, 8));
   crow = WBLOG_AppendCell(crow, WBLOG_Double(tp, 8));
   crow = WBLOG_AppendCell(crow, WBLOG_Double(risk_pips, 3));
   crow = WBLOG_AppendCell(crow, "");
   crow = WBLOG_AppendCell(crow, "");
   crow = WBLOG_AppendCell(crow, "true");
   crow = WBLOG_AppendCell(crow, "");
   WBLOG_WriteLineAppend("WaveBot_TradeCandidates.csv", crow);

   // Flush only the trigger/trade-candidate CSVs touched by this event. A full
   // all-file flush is reserved for final/end-of-scan paths.
   WBLOG_FlushOpenFileName("WaveBot_M1_Triggers.csv");
   WBLOG_FlushOpenFileName("WaveBot_TradeCandidates.csv");
}

inline string WBLOG_ZoneTypeById(const int zone_id)
{
   int n = ArraySize(g_wblog_zones);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_zones[i].used) continue;
      if(g_wblog_zones[i].zone_id == zone_id)
         return WBLOG_ZoneTypeName(g_wblog_zones[i].zone_source, g_wblog_zones[i].zone_kind);
   }
   return "";
}

inline double WBLOG_ZoneLowById(const int zone_id)
{
   int n = ArraySize(g_wblog_zones);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_zones[i].used) continue;
      if(g_wblog_zones[i].zone_id == zone_id)
         return g_wblog_zones[i].zone_low;
   }
   return 0.0;
}

inline double WBLOG_ZoneHighById(const int zone_id)
{
   int n = ArraySize(g_wblog_zones);
   for(int i=0; i<n; ++i)
   {
      if(!g_wblog_zones[i].used) continue;
      if(g_wblog_zones[i].zone_id == zone_id)
         return g_wblog_zones[i].zone_high;
   }
   return 0.0;
}

inline int WBLOG_CurrentContextId(){ return g_wblog_cur_context_id; }
inline int WBLOG_CurrentZoneId(){ return g_wblog_cur_zone_id; }
inline int WBLOG_CurrentWindowId(){ return g_wblog_cur_window_id; }
inline int WBLOG_CurrentStartKind(){ return g_wblog_cur_start_kind; }
inline int WBLOG_CurrentStartNS(){ return g_wblog_cur_start_ns; }

#endif // WAVEBOT_LOGGER_MQH
