#ifndef WAVEBOT_TRIGGER_STATEMENT_MQH
#define WAVEBOT_TRIGGER_STATEMENT_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/Trigger.mqh>
#include <WaveBot/TriggerSLTP.mqh>
#include <WaveBot/FSMS_SW.mqh>
#include <WaveBot/TriggerM15SignalGate.mqh>

#define TRGSTMT_RESULT_OPEN 0
#define TRGSTMT_RESULT_WIN  1
#define TRGSTMT_RESULT_LOSS 2

#define TRGSTMT_SKIP_NONE          0
#define TRGSTMT_SKIP_ACTIVE_TRADE  1
#define TRGSTMT_SKIP_DAILY_LOSS_CAP 2
#define TRGSTMT_SKIP_TREND_FILTER  3
#define TRGSTMT_SKIP_LOCAL_GATE    4
#define TRGSTMT_SKIP_POST_WIN_WAIT 5

#define TRGSTMT_NS_MAJ             0
#define TRGSTMT_NS_MIN             1

#define TRGSTMT_LOCK_AFTER_LOSSES 4

struct TriggerStatementTrade
{
   bool              valid;
   bool              taken;
   int               raw_index;
   int               exec_index;
   int               skip_reason;
   datetime          unlock_on_time;
   TriggerSLTPRecord rec;

   int               result_status;
   bool              ambiguous;
   bool              trigger_bar_ambiguous;

   datetime          exit_time;
   double            exit_price;

   double            result_r;
   double            pnl_money;

   double            floating_r;
   double            floating_money;

   double            equity_after;
   int               streak_after;
   int               bars_held;

   string            note;
};

struct TriggerStatementStartEvent
{
   datetime          t;
   datetime          bar_time;
   Direction         dir;
   int               kind;
   int               ns;
   int               seq;
};

struct TriggerStatementModeEvent
{
   datetime          t;
   Direction         dir;
   int               ns;
};

struct TriggerStatementTrendWindow
{
   datetime          start_time;
   datetime          end_time;
   Direction         dir;
   string            tag;
};

struct TriggerStatementBootResult
{
   bool              ok;
   Direction         mode;
   datetime          complete_time;
};

static string   g_trgstmt_last_filename = "";

static string   g_trgstmt_last_fullpath = "";
static bool     g_trgstmt_last_write_ok = false;
static datetime g_trgstmt_last_scan_from = 0;
static datetime g_trgstmt_last_scan_to   = 0;
static int      g_trgstmt_last_records   = 0;

inline void __TRGSTM_ClearTrade(TriggerStatementTrade &stmt_trade)
{
   stmt_trade.valid                  = false;
   stmt_trade.taken                  = false;
   stmt_trade.raw_index              = 0;
   stmt_trade.exec_index             = -1;
   stmt_trade.skip_reason            = TRGSTMT_SKIP_NONE;
   stmt_trade.unlock_on_time         = 0;
   __TRGSL_ClearRecord(stmt_trade.rec);
   stmt_trade.result_status          = TRGSTMT_RESULT_OPEN;
   stmt_trade.ambiguous              = false;
   stmt_trade.trigger_bar_ambiguous  = false;
   stmt_trade.exit_time              = 0;
   stmt_trade.exit_price             = 0.0;
   stmt_trade.result_r               = 0.0;
   stmt_trade.pnl_money              = 0.0;
   stmt_trade.floating_r             = 0.0;
   stmt_trade.floating_money         = 0.0;
   stmt_trade.equity_after           = 0.0;
   stmt_trade.streak_after           = 0;
   stmt_trade.bars_held              = 0;
   stmt_trade.note                   = "";
}

inline void TriggerStatement_ResetGlobals()
{
   g_trgstmt_last_filename = "";
   g_trgstmt_last_fullpath = "";
   g_trgstmt_last_write_ok = false;
   g_trgstmt_last_scan_from = 0;
   g_trgstmt_last_scan_to   = 0;
   g_trgstmt_last_records   = 0;
}

inline string TriggerStatement_LastFileName() { return g_trgstmt_last_filename; }
inline string TriggerStatement_LastFullPath() { return g_trgstmt_last_fullpath; }
inline bool   TriggerStatement_LastWriteOK()  { return g_trgstmt_last_write_ok; }
inline int    TriggerStatement_LastRecordCount() { return g_trgstmt_last_records; }

inline string __TRGSTM_SafeTime(const datetime t)
{
   if(t <= 0)
      return "n/a";

   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

inline string __TRGSTM_DirName(const Direction dir)
{
   return (dir == DIR_UP ? "BUY" : "SELL");
}

inline string __TRGSTM_StatusName(const int status)
{
   if(status == TRGSTMT_RESULT_WIN)  return "WIN";
   if(status == TRGSTMT_RESULT_LOSS) return "LOSS";
   return "OPEN";
}

inline string __TRGSTM_StreakText(const int streak)
{
   if(streak > 0)
      return ("W" + IntegerToString(streak));
   if(streak < 0)
      return ("L" + IntegerToString(-streak));
   return "-";
}

inline string __TRGSTM_SkipReasonName(const int skip_reason)
{
   if(skip_reason == TRGSTMT_SKIP_ACTIVE_TRADE)
      return "ACTIVE_TRADE_OPEN";
   if(skip_reason == TRGSTMT_SKIP_DAILY_LOSS_CAP)
      return "DAILY_4_LOSSES_REACHED_WAIT_NEXT_DAY";
   if(skip_reason == TRGSTMT_SKIP_TREND_FILTER)
      return (__TRGSTM_WorkerLabel() + "_TREND_NOT_ALIGNED");
   if(skip_reason == TRGSTMT_SKIP_LOCAL_GATE)
      return (__TRGSTM_WorkerLabel() + "_LOCAL_SIGNAL_WINDOW_NOT_OPEN");
   if(skip_reason == TRGSTMT_SKIP_POST_WIN_WAIT)
      return ("WAIT_NEW_LOCAL_" + __TRGSTM_WorkerLabel() + "_SIGNAL_ON_AFTER_WIN");
   return "-";
}

inline string __TRGSTM_AppendNote(const string left_text,
                                  const string right_text)
{
   if(right_text == "")
      return left_text;
   if(left_text == "")
      return right_text;
   return (left_text + "|" + right_text);
}

inline bool __TRGSTM_IsClosedStatus(const int status)
{
   return (status == TRGSTMT_RESULT_WIN || status == TRGSTMT_RESULT_LOSS);
}

inline double __TRGSTM_EffectiveR(const TriggerStatementTrade &stmt_trade)
{
   if(stmt_trade.result_status == TRGSTMT_RESULT_OPEN)
      return stmt_trade.floating_r;

   return stmt_trade.result_r;
}

inline double __TRGSTM_EffectiveMoneyByRisk(const TriggerStatementTrade &stmt_trade,
                                            const double                 risk_money)
{
   return (__TRGSTM_EffectiveR(stmt_trade) * risk_money);
}

inline void __TRGSTM_BumpHypotheticalCounters(const TriggerStatementTrade &stmt_trade,
                                              int &wins,
                                              int &losses,
                                              int &opens)
{
   if(stmt_trade.result_status == TRGSTMT_RESULT_WIN)
   {
      wins++;
      return;
   }

   if(stmt_trade.result_status == TRGSTMT_RESULT_LOSS)
   {
      losses++;
      return;
   }

   opens++;
}

inline void __TRGSTM_SetSkip(TriggerStatementTrade &stmt_trade,
                             const int              skip_reason,
                             const double           equity_after,
                             const string           note)
{
   stmt_trade.taken        = false;
   stmt_trade.exec_index   = -1;
   stmt_trade.skip_reason  = skip_reason;
   stmt_trade.equity_after = equity_after;
   stmt_trade.streak_after = 0;
   stmt_trade.note         = note;
}


inline int __TRGSTM_CompareStartEvent(const TriggerStatementStartEvent &a,
                                      const TriggerStatementStartEvent &b)
{
   if(a.bar_time < b.bar_time) return -1;
   if(a.bar_time > b.bar_time) return 1;

   if(a.t < b.t) return -1;
   if(a.t > b.t) return 1;

   if(a.seq < b.seq) return -1;
   if(a.seq > b.seq) return 1;

   return 0;
}

inline void __TRGSTM_SortStartEvents(TriggerStatementStartEvent &events[])
{
   int n = ArraySize(events);
   if(n <= 1)
      return;

   for(int i = 0; i < n - 1; ++i)
   {
      int best = i;
      for(int j = i + 1; j < n; ++j)
      {
         if(__TRGSTM_CompareStartEvent(events[j], events[best]) < 0)
            best = j;
      }

      if(best != i)
      {
         TriggerStatementStartEvent tmp = events[i];
         events[i] = events[best];
         events[best] = tmp;
      }
   }
}

inline string __TRGSTM_LocalGateNsName(const int ns)
{
   if(ns == WB15_NS_MAJ)  return "MAJ";
   if(ns == WB15_NS_MIN)  return "MIN";
   return "NONE";
}

inline string __TRGSTM_LocalGateKindName(const int kind)
{
   return TriggerM15SignalGate_KindName(kind);
}

inline string __TRGSTM_TimeframeTag(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M4:   return "M4";
      case PERIOD_M5:   return "M5";
      case PERIOD_M6:   return "M6";
      case PERIOD_M10:  return "M10";
      case PERIOD_M12:  return "M12";
      case PERIOD_M15:  return "M15";
      case PERIOD_M20:  return "M20";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
   }

   return IntegerToString((int)tf);
}


inline string __TRGSTM_WorkerLabel()
{
   return WBBridge_WorkerLabel();
}

inline string __TRGSTM_ParentLabel()
{
   return WBBridge_ParentLabel();
}

inline string __TRGSTM_LocalGateToken()
{
   return (__TRGSTM_WorkerLabel() + "_LOCAL_SIGNAL");
}

inline string __TRGSTM_SanitizeFilePart(string text)
{
   StringReplace(text, "\\", "_");
   StringReplace(text, "/",  "_");
   StringReplace(text, ":",  "_");
   StringReplace(text, "*",  "_");
   StringReplace(text, "?",  "_");
   StringReplace(text, "\"", "_");
   StringReplace(text, "<",  "_");
   StringReplace(text, ">",  "_");
   StringReplace(text, "|",  "_");
   StringReplace(text, " ",  "_");
   return text;
}

inline string __TRGSTM_BuildFileName(const string tag,
                                     const string sym,
                                     const ENUM_TIMEFRAMES tf)
{
   string base = tag;
   if(base == "")
      base = "WaveBot_TriggerStatement";

   base = __TRGSTM_SanitizeFilePart(base);
   string safe_sym = __TRGSTM_SanitizeFilePart(sym);
   string tf_tag   = __TRGSTM_TimeframeTag(tf);

   return (base + "_" + safe_sym + "_" + tf_tag + ".txt");
}

inline void __TRGSTM_WriteLine(const int handle, const string text)
{
   FileWriteString(handle, text + "\r\n");
}

inline int __TRGSTM_FindFirstBarAtOrAfter(const MqlRates &rates[],
                                          const int       n,
                                          const datetime  t)
{
   if(n <= 0)
      return -1;

   for(int i = 0; i < n; ++i)
   {
      if(rates[i].time >= t)
         return i;
   }

   return -1;
}

inline int __TRGSTM_FindLastBarAtOrBefore(const MqlRates &rates[],
                                          const int       n,
                                          const datetime  t)
{
   if(n <= 0)
      return -1;

   int idx = -1;
   for(int i = 0; i < n; ++i)
   {
      if(rates[i].time <= t)
         idx = i;
      else
         break;
   }

   return idx;
}


inline int __TRGSTM_DayKey(const datetime t)
{
   if(t <= 0)
      return 0;

   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (dt.year * 10000 + dt.mon * 100 + dt.day);
}

inline string __TRGSTM_DayKeyText(const int day_key)
{
   if(day_key <= 0)
      return "n/a";

   int y = (day_key / 10000);
   int m = ((day_key / 100) % 100);
   int d = (day_key % 100);

   return (IntegerToString(y) + "." + IntegerToString(m) + "." + IntegerToString(d));
}

inline datetime __TRGSTM_NextDayStart(const datetime t)
{
   if(t <= 0)
      return 0;

   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime base = StructToTime(dt);
   return (base + 86400);
}

inline void __TRGSTM_EnsureDailyLossBucket(const datetime t,
                                           int           &day_key,
                                           int           &daily_losses,
                                           bool          &cap_active,
                                           int           &cap_resets)
{
   int current_key = __TRGSTM_DayKey(t);
   if(current_key <= 0)
      return;

   if(day_key == current_key)
      return;

   if(day_key > 0 && cap_active)
      cap_resets++;

   day_key      = current_key;
   daily_losses = 0;
   cap_active   = false;
}

inline int __TRGSTM_CompareRecord(const TriggerSLTPRecord &a,
                                  const TriggerSLTPRecord &b)
{
   if(a.hit_time < b.hit_time) return -1;
   if(a.hit_time > b.hit_time) return 1;

   if(a.src_time < b.src_time) return -1;
   if(a.src_time > b.src_time) return 1;

   if(a.serial < b.serial) return -1;
   if(a.serial > b.serial) return 1;

   return 0;
}

inline void __TRGSTM_SortRecords(TriggerSLTPRecord &records[])
{
   int n = ArraySize(records);
   if(n <= 1)
      return;

   for(int i = 0; i < n - 1; ++i)
   {
      int best = i;
      for(int j = i + 1; j < n; ++j)
      {
         if(__TRGSTM_CompareRecord(records[j], records[best]) < 0)
            best = j;
      }

      if(best != i)
      {
         TriggerSLTPRecord tmp = records[i];
         records[i] = records[best];
         records[best] = tmp;
      }
   }
}

inline int __TRGSTM_CollectRecords(const string   sym,
                                   const datetime scan_from,
                                   const datetime scan_to,
                                   TriggerSLTPRecord &out[])
{
   ArrayResize(out, 0);

   int count = TriggerSLTP_RecordCount();
   for(int i = 0; i < count; ++i)
   {
      TriggerSLTPRecord rec;
      if(!TriggerSLTP_RecordGet(i, rec))
         continue;
      if(!rec.valid)
         continue;

      if(sym != "" && rec.symbol != "" && rec.symbol != sym)
         continue;

      if(scan_from > 0 && rec.hit_time < scan_from)
         continue;
      if(scan_to > 0 && rec.hit_time > scan_to)
         continue;

      int pos = ArraySize(out);
      ArrayResize(out, pos + 1);
      out[pos] = rec;
   }

   __TRGSTM_SortRecords(out);
   return ArraySize(out);
}


inline int __TRGSTM_CollectStartEvents(const string sym,
                                       const datetime scan_to,
                                       TriggerStatementStartEvent &out[])
{
   ArrayResize(out, 0);

   if(sym == "")
      return 0;

   if(!__TRG_RebuildBridgeEvents(sym))
      return 0;

   int total = ArraySize(g_trigger_events);
   for(int i = 0; i < total; ++i)
   {
      TriggerEvent evt = g_trigger_events[i];

      if(!__TRG_IsStartKind(evt.kind))
         continue;
      if(evt.bar_time <= 0)
         continue;
      if(scan_to > 0 && evt.bar_time > scan_to)
         continue;

      int pos = ArraySize(out);
      ArrayResize(out, pos + 1);

      out[pos].t        = evt.t;
      out[pos].bar_time = evt.bar_time;
      out[pos].dir      = evt.dir;
      out[pos].kind     = evt.kind;
      out[pos].ns       = evt.ns;
      out[pos].seq      = evt.seq;
   }

   __TRGSTM_SortStartEvents(out);
   return ArraySize(out);
}


inline int __TRGSTM_CollectBridgeEvents(const string sym,
                                        const datetime scan_to,
                                        TriggerStatementStartEvent &out[])
{
   ArrayResize(out, 0);

   if(sym == "")
      return 0;

   if(!__TRG_RebuildBridgeEvents(sym))
      return 0;

   int total = ArraySize(g_trigger_events);
   for(int i = 0; i < total; ++i)
   {
      TriggerEvent evt = g_trigger_events[i];

      if(evt.bar_time <= 0)
         continue;
      if(scan_to > 0 && evt.bar_time > scan_to)
         continue;

      int pos = ArraySize(out);
      ArrayResize(out, pos + 1);

      out[pos].t        = evt.t;
      out[pos].bar_time = evt.bar_time;
      out[pos].dir      = evt.dir;
      out[pos].kind     = evt.kind;
      out[pos].ns       = evt.ns;
      out[pos].seq      = evt.seq;
   }

   __TRGSTM_SortStartEvents(out);
   return ArraySize(out);
}

inline int __TRGSTM_CollectLocalGateEvents(const string sym,
                                           const datetime scan_to,
                                           TriggerStatementStartEvent &out[])
{
   ArrayResize(out, 0);

   int total = TriggerM15SignalGate_EventCount();
   for(int i = 0; i < total; ++i)
   {
      TriggerM15SignalGateEvent evt;
      if(!TriggerM15SignalGate_EventGet(i, evt))
         continue;

      if(sym != "" && evt.symbol != "" && evt.symbol != sym)
         continue;
      if(evt.bar_time <= 0)
         continue;
      if(scan_to > 0 && evt.bar_time > scan_to)
         continue;

      int pos = ArraySize(out);
      ArrayResize(out, pos + 1);

      out[pos].t        = evt.t;
      out[pos].bar_time = evt.bar_time;
      out[pos].dir      = evt.dir;
      out[pos].kind     = evt.kind;
      out[pos].ns       = evt.ns;
      out[pos].seq      = evt.seq;
   }

   __TRGSTM_SortStartEvents(out);
   return ArraySize(out);
}

inline int __TRGSTM_FilterLocalGateStartEvents(const TriggerStatementStartEvent &events[],
                                               const int                         total,
                                               TriggerStatementStartEvent        &out[])
{
   ArrayResize(out, 0);

   for(int i = 0; i < total; ++i)
   {
      if(!__TRGM15_IsStartKind(events[i].kind))
         continue;

      int pos = ArraySize(out);
      ArrayResize(out, pos + 1);
      out[pos] = events[i];
   }

   return ArraySize(out);
}

inline datetime __TRGSTM_AdvanceLocalGateRearmEvents(const TriggerStatementStartEvent &events[],
                                                     const int                         total,
                                                     int                               &next_index,
                                                     const datetime                    upto_time,
                                                     bool                              &wait_active,
                                                     datetime                          &wait_ref_time,
                                                     Direction                         &release_dir,
                                                     int                               &release_kind,
                                                     int                               &release_ns)
{
   datetime release_time = 0;
   release_dir  = DIR_UP;
   release_kind = 0;
   release_ns   = WB15_NS_NONE;

   while(next_index < total)
   {
      TriggerStatementStartEvent evt = events[next_index];
      if(evt.bar_time > upto_time)
         break;

      if(wait_active && evt.bar_time > wait_ref_time)
      {
         wait_active   = false;
         wait_ref_time = 0;

         if(release_time <= 0)
         {
            release_time = evt.bar_time;
            release_dir  = evt.dir;
            release_kind = evt.kind;
            release_ns   = evt.ns;
         }
      }

      next_index++;
   }

   return release_time;
}

inline datetime __TRGSTM_AdvanceStartEvents(const TriggerStatementStartEvent &events[],
                                            const int total,
                                            int &next_index,
                                            const datetime upto_time,
                                            bool &lockout_active,
                                            datetime &lockout_ref_time,
                                            int &gate_loss_streak,
                                            int &lockout_releases)
{
   datetime release_time = 0;

   while(next_index < total)
   {
      TriggerStatementStartEvent evt = events[next_index];
      if(evt.bar_time > upto_time)
         break;

      if(lockout_active && evt.bar_time > lockout_ref_time)
      {
         lockout_active   = false;
         lockout_ref_time = 0;
         gate_loss_streak = 0;
         lockout_releases++;

         if(release_time <= 0)
            release_time = evt.bar_time;
      }

      next_index++;
   }

   return release_time;
}


inline void __TRGSTM_ClearLocalGateState(bool      &gate_active,
                                         Direction &gate_dir,
                                         int       &gate_kind,
                                         int       &gate_ns,
                                         datetime  &gate_start_time,
                                         datetime  &gate_start_bar,
                                         int       &gate_seq)
{
   gate_active     = false;
   gate_dir        = DIR_UP;
   gate_kind       = 0;
   gate_ns         = WB15_NS_NONE;
   gate_start_time = 0;
   gate_start_bar  = 0;
   gate_seq        = -1;
}

inline void __TRGSTM_AdvanceParentGateEvents(const TriggerStatementStartEvent &events[],
                                             const int total,
                                             int &next_index,
                                             const datetime upto_time,
                                             bool &gate_active,
                                             Direction &gate_dir,
                                             int &gate_kind,
                                             int &gate_ns,
                                             datetime &gate_start_time,
                                             datetime &gate_start_bar,
                                             int &gate_seq)
{
   while(next_index < total)
   {
      TriggerStatementStartEvent evt = events[next_index];
      if(evt.bar_time > upto_time)
         break;

      if(__TRG_IsStartKind(evt.kind))
      {
         gate_active     = true;
         gate_dir        = evt.dir;
         gate_kind       = evt.kind;
         gate_ns         = evt.ns;
         gate_start_time = evt.t;
         gate_start_bar  = evt.bar_time;
         gate_seq        = evt.seq;
      }
      else if(__TRG_IsStopKind(evt.kind))
      {
         if(gate_active && evt.dir == WBBridge_Opposite(gate_dir))
            __TRGSTM_ClearLocalGateState(gate_active,
                                         gate_dir,
                                         gate_kind,
                                         gate_ns,
                                         gate_start_time,
                                         gate_start_bar,
                                         gate_seq);
      }

      next_index++;
   }
}

inline void __TRGSTM_AdvanceLocalGateEvents(const TriggerStatementStartEvent &events[],
                                            const int total,
                                            int &next_index,
                                            const datetime upto_time,
                                            bool &gate_active,
                                            Direction &gate_dir,
                                            int &gate_kind,
                                            int &gate_ns,
                                            datetime &gate_start_time,
                                            datetime &gate_start_bar,
                                            int &gate_seq)
{
   while(next_index < total)
   {
      TriggerStatementStartEvent evt = events[next_index];
      if(evt.bar_time > upto_time)
         break;

      if(__TRG_IsStartKind(evt.kind))
      {
         gate_active     = true;
         gate_dir        = evt.dir;
         gate_kind       = evt.kind;
         gate_ns         = evt.ns;
         gate_start_time = evt.t;
         gate_start_bar  = evt.bar_time;
         gate_seq        = evt.seq;
      }
      else if(__TRG_IsStopKind(evt.kind))
      {
         if(gate_active && evt.dir == __WB15_Opposite(gate_dir))
            __TRGSTM_ClearLocalGateState(gate_active,
                                         gate_dir,
                                         gate_kind,
                                         gate_ns,
                                         gate_start_time,
                                         gate_start_bar,
                                         gate_seq);
      }

      next_index++;
   }
}

inline string __TRGSTM_BuildLocalGateSkipNote(const Direction trg_dir,
                                              const bool      gate_active,
                                              const Direction gate_dir,
                                              const int       gate_kind,
                                              const int       gate_ns,
                                              const datetime  gate_start_bar)
{
   string note = ("SKIPPED_" + __TRGSTM_LocalGateToken() + "_GATE");
   note = __TRGSTM_AppendNote(note, "TRG_" + __TRGSTM_DirName(trg_dir));

   if(!gate_active)
      return __TRGSTM_AppendNote(note, "LOCAL_GATE_NONE");

   note = __TRGSTM_AppendNote(note, "LOCAL_GATE_" + __TRGSTM_DirName(gate_dir));
   note = __TRGSTM_AppendNote(note, "TYPE_" + __TRGSTM_LocalGateKindName(gate_kind));
   note = __TRGSTM_AppendNote(note, "NS_" + __TRGSTM_LocalGateNsName(gate_ns));
   note = __TRGSTM_AppendNote(note, "FROM_" + __TRGSTM_SafeTime(gate_start_bar));
   return note;
}

inline string __TRGSTM_BuildLocalGateMatchNote(const Direction trg_dir,
                                               const int       gate_kind,
                                               const int       gate_ns,
                                               const datetime  gate_start_bar)
{
   string note = (__TRGSTM_LocalGateToken() + "_GATE_OPEN");
   note = __TRGSTM_AppendNote(note, "TRG_" + __TRGSTM_DirName(trg_dir));
   note = __TRGSTM_AppendNote(note, "TYPE_" + __TRGSTM_LocalGateKindName(gate_kind));
   note = __TRGSTM_AppendNote(note, "NS_" + __TRGSTM_LocalGateNsName(gate_ns));
   note = __TRGSTM_AppendNote(note, "FROM_" + __TRGSTM_SafeTime(gate_start_bar));
   return note;
}

inline string __TRGSTM_BuildPostWinWaitSkipNote(const Direction trg_dir,
                                                const datetime  ref_time,
                                                const bool      gate_active,
                                                const Direction gate_dir,
                                                const int       gate_kind,
                                                const int       gate_ns,
                                                const datetime  gate_start_bar)
{
   string note = ("SKIPPED_WAITING_FRESH_LOCAL_" + __TRGSTM_WorkerLabel() + "_SIGNAL_AFTER_WIN");
   note = __TRGSTM_AppendNote(note, "TRG_" + __TRGSTM_DirName(trg_dir));
   note = __TRGSTM_AppendNote(note, "AFTER_WIN_" + __TRGSTM_SafeTime(ref_time));

   if(!gate_active)
      return __TRGSTM_AppendNote(note, "LOCAL_GATE_NONE");

   note = __TRGSTM_AppendNote(note, "LOCAL_GATE_" + __TRGSTM_DirName(gate_dir));
   note = __TRGSTM_AppendNote(note, "TYPE_" + __TRGSTM_LocalGateKindName(gate_kind));
   note = __TRGSTM_AppendNote(note, "NS_" + __TRGSTM_LocalGateNsName(gate_ns));
   note = __TRGSTM_AppendNote(note, "FROM_" + __TRGSTM_SafeTime(gate_start_bar));
   return note;
}

inline string __TRGSTM_BuildPostWinRearmNote(const Direction gate_dir,
                                             const int       gate_kind,
                                             const int       gate_ns,
                                             const datetime  gate_start_bar)
{
   string note = ("FRESH_LOCAL_" + __TRGSTM_WorkerLabel() + "_SIGNAL_ON_AFTER_WIN");
   note = __TRGSTM_AppendNote(note, "LOCAL_GATE_" + __TRGSTM_DirName(gate_dir));
   note = __TRGSTM_AppendNote(note, "TYPE_" + __TRGSTM_LocalGateKindName(gate_kind));
   note = __TRGSTM_AppendNote(note, "NS_" + __TRGSTM_LocalGateNsName(gate_ns));
   note = __TRGSTM_AppendNote(note, "FROM_" + __TRGSTM_SafeTime(gate_start_bar));
   return note;
}

inline int __TRGSTM_Boot_LeftmostMinLow_ExInside(const MqlRates &rates[],
                                                 const bool     &insideHL[],
                                                 const int       from,
                                                 const int       to)
{
   if(from > to) return -1;

   double mn = DBL_MAX;
   int    idx = -1;

   for(int i = from; i <= to; ++i)
   {
      if(insideHL[i]) continue;

      double l = rates[i].low;
      if(l < mn)
      {
         mn  = l;
         idx = i;
      }
   }

   if(idx < 0)
      idx = from;

   return idx;
}

inline int __TRGSTM_Boot_LeftmostMaxHigh_ExInside(const MqlRates &rates[],
                                                  const bool     &insideHL[],
                                                  const int       from,
                                                  const int       to)
{
   if(from > to) return -1;

   double mx = -DBL_MAX;
   int    idx = -1;

   for(int i = from; i <= to; ++i)
   {
      if(insideHL[i]) continue;

      double h = rates[i].high;
      if(h > mx)
      {
         mx  = h;
         idx = i;
      }
   }

   if(idx < 0)
      idx = from;

   return idx;
}

inline bool __TRGSTM_Boot_FindFirstPair_UP(const string          sym,
                                           const ENUM_TIMEFRAMES tf,
                                           const datetime        from_time,
                                           const datetime        to_time,
                                           datetime             &out_body_break_time)
{
   out_body_break_time = 0;

   int tfsec = PeriodSeconds(tf);
   if(tfsec <= 0)
      tfsec = 60;

   datetime effective_start = from_time;
   datetime from_adj = from_time - (datetime)(tfsec * 10);
   if(from_adj < 0)
      from_adj = 0;

   MqlRates rates[];
   int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n <= 0)
      return false;

   double bodyLowEff[];
   double bodyHighEff[];
   BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);

   bool insideHL[];
   BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff = 0;
   while(first_eff < n && rates[first_eff].time < effective_start)
      first_eff++;

   int idx = MathMax(0, first_eff - 2);

   enum TRGSTMTBootStateUP
   {
      TRGSTMT_BOOT_SEARCH_W2_UP = 0,
      TRGSTMT_BOOT_WAIT_CONFIRM_UP = 1
   };

   TRGSTMTBootStateUP state = TRGSTMT_BOOT_SEARCH_W2_UP;

   int c1 = -1;
   int c2 = -1;
   int c3 = -1;
   int c4 = -1;
   int cend = -1;

   bool have_w3 = false;
   int  w3_c1 = -1;

   int    w3_cand = -1;
   double w3_cand_low = DBL_MAX;

   bool   wick_active = false;
   int    first_wick_idx = -1;
   double body_break_level = 0.0;
   bool   break_achieved = false;
   int    body_break_idx = -1;

   while(idx < n)
   {
      if(state == TRGSTMT_BOOT_SEARCH_W2_UP)
      {
         bool found = false;

         for(int i = idx; i < n; ++i)
         {
            if(insideHL[i])
               continue;

            int i2 = -1;
            int i3 = -1;
            int i4 = -1;

            if(!CheckWave2_FromIndex_LocalOnly(rates,
                                               insideHL,
                                               bodyLowEff,
                                               bodyHighEff,
                                               n,
                                               i,
                                               i2,
                                               i3,
                                               i4))
            {
               continue;
            }

            c1   = i;
            c2   = i2;
            c3   = i3;
            c4   = i4;
            cend = (c4 >= 0 ? c4 : c3);

            if(rates[c1].time < effective_start || rates[c1].time > to_time)
            {
               idx = cend + 1;
               continue;
            }

            have_w3 = false;
            w3_c1   = -1;

            w3_cand     = -1;
            w3_cand_low = DBL_MAX;

            wick_active    = false;
            first_wick_idx = -1;
            body_break_level = rates[c1].high;
            break_achieved   = false;
            body_break_idx   = -1;

            idx   = cend;
            state = TRGSTMT_BOOT_WAIT_CONFIRM_UP;
            found = true;
            break;
         }

         if(!found)
            break;
      }
      else
      {
         bool progressed = false;

         for(int j = idx; j < n; ++j)
         {
            if(insideHL[j])
               continue;

            if(!break_achieved)
            {
               if(rates[j].high > body_break_level)
               {
                  if(rates[j].close > body_break_level)
                  {
                     break_achieved = true;
                     body_break_idx = j;
                  }
                  else
                  {
                     body_break_level = rates[j].high;

                     if(first_wick_idx < 0)
                     {
                        first_wick_idx = j;
                        wick_active    = true;

                        int anchor_c1 = __TRGSTM_Boot_LeftmostMinLow_ExInside(rates,
                                                                              insideHL,
                                                                              cend,
                                                                              first_wick_idx);
                        have_w3 = false;
                        w3_c1   = anchor_c1;
                        w3_cand = -1;
                        w3_cand_low = DBL_MAX;
                     }
                  }
               }
            }

            int rewind_idx = -1;
            if(ChainInv_PreBody_WickWindow_UP_OnBar(rates,
                                                    insideHL,
                                                    n,
                                                    j,
                                                    break_achieved,
                                                    wick_active,
                                                    first_wick_idx,
                                                    w3_c1,
                                                    w3_cand,
                                                    rewind_idx))
            {
               idx       = rewind_idx;
               state     = TRGSTMT_BOOT_SEARCH_W2_UP;
               progressed = true;
               break;
            }

            if(!wick_active && !break_achieved)
            {
               int c1_eff = (w3_c1 >= 0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  have_w3 = false;
                  w3_c1 = -1;
                  w3_cand = j;
                  w3_cand_low = rates[j].low;
                  continue;
               }
            }

            if(!wick_active)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].low < w3_cand_low))
               {
                  w3_cand     = j;
                  w3_cand_low = rates[j].low;
                  have_w3     = false;
               }
            }

            int start_idx = -1;
            if(w3_c1 >= 0)
               start_idx = w3_c1;
            else if(w3_cand >= 0)
               start_idx = w3_cand;

            if(!have_w3 && start_idx >= 0 && !insideHL[start_idx])
            {
               int a2  = -1;
               int a3  = -1;
               int a4  = -1;
               int w3e = -1;

               if(CheckWave3CountOnly_Local(rates,
                                            insideHL,
                                            bodyLowEff,
                                            bodyHighEff,
                                            n,
                                            start_idx,
                                            a2,
                                            a3,
                                            a4,
                                            w3e))
               {
                  have_w3 = true;
                  if(w3_c1 < 0)
                     w3_c1 = start_idx;
               }
            }

            if(break_achieved && !have_w3)
            {
               int c1_eff = (w3_c1 >= 0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  idx       = (body_break_idx >= 0 ? body_break_idx : j);
                  state     = TRGSTMT_BOOT_SEARCH_W2_UP;
                  progressed = true;
                  break;
               }
            }

            if(have_w3 && break_achieved)
            {
               int out_idx = (body_break_idx >= 0 ? body_break_idx : j);
               out_body_break_time = rates[out_idx].time;
               return true;
            }
         }

         if(!progressed)
            break;
      }
   }

   return false;
}

inline bool __TRGSTM_Boot_FindFirstPair_DOWN(const string          sym,
                                             const ENUM_TIMEFRAMES tf,
                                             const datetime        from_time,
                                             const datetime        to_time,
                                             datetime             &out_body_break_time)
{
   out_body_break_time = 0;

   int tfsec = PeriodSeconds(tf);
   if(tfsec <= 0)
      tfsec = 60;

   datetime effective_start = from_time;
   datetime from_adj = from_time - (datetime)(tfsec * 10);
   if(from_adj < 0)
      from_adj = 0;

   MqlRates rates[];
   int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n <= 0)
      return false;

   double bodyLowEff[];
   double bodyHighEff[];
   BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);

   bool insideHL[];
   BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff = 0;
   while(first_eff < n && rates[first_eff].time < effective_start)
      first_eff++;

   int idx = MathMax(0, first_eff - 2);

   enum TRGSTMTBootStateDN
   {
      TRGSTMT_BOOT_SEARCH_W2_DN = 0,
      TRGSTMT_BOOT_WAIT_CONFIRM_DN = 1
   };

   TRGSTMTBootStateDN state = TRGSTMT_BOOT_SEARCH_W2_DN;

   int c1 = -1;
   int c2 = -1;
   int c3 = -1;
   int c4 = -1;
   int cend = -1;

   bool have_w3 = false;
   int  w3_c1 = -1;

   int    w3_cand = -1;
   double w3_cand_high = -DBL_MAX;

   bool   wick_active = false;
   int    first_wick_idx = -1;
   double body_break_level = 0.0;
   bool   break_achieved = false;
   int    body_break_idx = -1;

   while(idx < n)
   {
      if(state == TRGSTMT_BOOT_SEARCH_W2_DN)
      {
         bool found = false;

         for(int i = idx; i < n; ++i)
         {
            if(insideHL[i])
               continue;

            int i2 = -1;
            int i3 = -1;
            int i4 = -1;

            if(!CheckWave2_FromIndex_LocalOnly_Down(rates,
                                                    insideHL,
                                                    bodyLowEff,
                                                    bodyHighEff,
                                                    n,
                                                    i,
                                                    i2,
                                                    i3,
                                                    i4))
            {
               continue;
            }

            c1   = i;
            c2   = i2;
            c3   = i3;
            c4   = i4;
            cend = (c4 >= 0 ? c4 : c3);

            if(rates[c1].time < effective_start || rates[c1].time > to_time)
            {
               idx = cend + 1;
               continue;
            }

            have_w3 = false;
            w3_c1   = -1;

            w3_cand      = -1;
            w3_cand_high = -DBL_MAX;

            wick_active    = false;
            first_wick_idx = -1;
            body_break_level = rates[c1].low;
            break_achieved   = false;
            body_break_idx   = -1;

            idx   = cend;
            state = TRGSTMT_BOOT_WAIT_CONFIRM_DN;
            found = true;
            break;
         }

         if(!found)
            break;
      }
      else
      {
         bool progressed = false;

         for(int j = idx; j < n; ++j)
         {
            if(insideHL[j])
               continue;

            if(!break_achieved)
            {
               if(rates[j].low < body_break_level)
               {
                  if(rates[j].close < body_break_level)
                  {
                     break_achieved = true;
                     body_break_idx = j;
                  }
                  else
                  {
                     body_break_level = rates[j].low;

                     if(first_wick_idx < 0)
                     {
                        first_wick_idx = j;
                        wick_active    = true;

                        int anchor_c1 = __TRGSTM_Boot_LeftmostMaxHigh_ExInside(rates,
                                                                               insideHL,
                                                                               cend,
                                                                               first_wick_idx);
                        have_w3 = false;
                        w3_c1   = anchor_c1;
                        w3_cand = -1;
                        w3_cand_high = -DBL_MAX;
                     }
                  }
               }
            }

            int rewind_idx = -1;
            if(ChainInv_PreBody_WickWindow_DN_OnBar(rates,
                                                    insideHL,
                                                    n,
                                                    j,
                                                    break_achieved,
                                                    wick_active,
                                                    first_wick_idx,
                                                    w3_c1,
                                                    w3_cand,
                                                    rewind_idx))
            {
               idx       = rewind_idx;
               state     = TRGSTMT_BOOT_SEARCH_W2_DN;
               progressed = true;
               break;
            }

            if(!wick_active && !break_achieved)
            {
               int c1_eff = (w3_c1 >= 0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  have_w3 = false;
                  w3_c1 = -1;
                  w3_cand = j;
                  w3_cand_high = rates[j].high;
                  continue;
               }
            }

            if(!wick_active)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].high > w3_cand_high))
               {
                  w3_cand      = j;
                  w3_cand_high = rates[j].high;
                  have_w3      = false;
               }
            }

            int start_idx = -1;
            if(w3_c1 >= 0)
               start_idx = w3_c1;
            else if(w3_cand >= 0)
               start_idx = w3_cand;

            if(!have_w3 && start_idx >= 0 && !insideHL[start_idx])
            {
               int a2  = -1;
               int a3  = -1;
               int a4  = -1;
               int w3e = -1;

               if(CheckWave3CountOnly_Local_Down(rates,
                                                 insideHL,
                                                 bodyLowEff,
                                                 bodyHighEff,
                                                 n,
                                                 start_idx,
                                                 a2,
                                                 a3,
                                                 a4,
                                                 w3e))
               {
                  have_w3 = true;
                  if(w3_c1 < 0)
                     w3_c1 = start_idx;
               }
            }

            if(break_achieved && !have_w3)
            {
               int c1_eff = (w3_c1 >= 0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  idx       = (body_break_idx >= 0 ? body_break_idx : j);
                  state     = TRGSTMT_BOOT_SEARCH_W2_DN;
                  progressed = true;
                  break;
               }
            }

            if(have_w3 && break_achieved)
            {
               int out_idx = (body_break_idx >= 0 ? body_break_idx : j);
               out_body_break_time = rates[out_idx].time;
               return true;
            }
         }

         if(!progressed)
            break;
      }
   }

   return false;
}

inline TriggerStatementBootResult __TRGSTM_BootstrapDetect(const string          sym,
                                                           const ENUM_TIMEFRAMES tf,
                                                           const datetime        scan_from,
                                                           const datetime        scan_to)
{
   TriggerStatementBootResult out;
   out.ok            = false;
   out.mode          = InpDirection;
   out.complete_time = 0;

   datetime up_t = 0;
   datetime dn_t = 0;

   bool up_ok = __TRGSTM_Boot_FindFirstPair_UP(sym, tf, scan_from, scan_to, up_t);
   bool dn_ok = __TRGSTM_Boot_FindFirstPair_DOWN(sym, tf, scan_from, scan_to, dn_t);

   if(!up_ok && !dn_ok)
      return out;

   out.ok = true;

   if(up_ok && !dn_ok)
   {
      out.mode          = DIR_UP;
      out.complete_time = up_t;
      return out;
   }

   if(!up_ok && dn_ok)
   {
      out.mode          = DIR_DOWN;
      out.complete_time = dn_t;
      return out;
   }

   if(up_t <= dn_t)
   {
      out.mode          = DIR_UP;
      out.complete_time = up_t;
   }
   else
   {
      out.mode          = DIR_DOWN;
      out.complete_time = dn_t;
   }

   return out;
}

inline int __TRGSTM_CompareModeEvent(const TriggerStatementModeEvent &a,
                                     const TriggerStatementModeEvent &b)
{
   if(a.t < b.t) return -1;
   if(a.t > b.t) return 1;

   if(a.ns < b.ns) return -1;
   if(a.ns > b.ns) return 1;

   if((int)a.dir < (int)b.dir) return -1;
   if((int)a.dir > (int)b.dir) return 1;

   return 0;
}

inline void __TRGSTM_SortModeEvents(TriggerStatementModeEvent &events[])
{
   int n = ArraySize(events);
   if(n <= 1)
      return;

   for(int i = 0; i < n - 1; ++i)
   {
      int best = i;
      for(int j = i + 1; j < n; ++j)
      {
         if(__TRGSTM_CompareModeEvent(events[j], events[best]) < 0)
            best = j;
      }

      if(best != i)
      {
         TriggerStatementModeEvent tmp = events[i];
         events[i] = events[best];
         events[best] = tmp;
      }
   }
}

inline bool __TRGSTM_ModeEventSame(const TriggerStatementModeEvent &a,
                                   const TriggerStatementModeEvent &b)
{
   return (a.t == b.t && a.ns == b.ns && a.dir == b.dir);
}

inline bool __TRGSTM_ParseMarkerNSTail(const string full_name,
                                       int         &scan_id,
                                       int         &ns,
                                       string      &tail)
{
   scan_id = -1;
   ns      = -1;
   tail    = "";

   int len = StringLen(full_name);
   if(len < 6)
      return false;

   if(StringGetCharacter(full_name, 0) != 'S')
      return false;

   int p1 = StringFind(full_name, "_");
   if(p1 <= 1)
      return false;

   string scan_text = StringSubstr(full_name, 1, p1 - 1);
   scan_id = (int)StringToInteger(scan_text);
   if(scan_id <= 0)
      return false;

   int p2 = StringFind(full_name, "_", p1 + 1);
   if(p2 < 0)
      return false;

   string ns_text = StringSubstr(full_name, p1 + 1, p2 - p1 - 1);
   if(ns_text == "MAJ")
      ns = TRGSTMT_NS_MAJ;
   else if(ns_text == "MIN")
      ns = TRGSTMT_NS_MIN;
   else
      return false;

   tail = StringSubstr(full_name, p2 + 1);
   if(tail == "")
      return false;

   return true;
}

inline int __TRGSTM_CollectMTCMarkerEvents(const datetime scan_from,
                                           const datetime scan_to,
                                           TriggerStatementModeEvent &out[])
{
   ArrayResize(out, 0);

   int total = ObjectsTotal(0);
   for(int i = 0; i < total; ++i)
   {
      string on = ObjectName(0, i);
      if(on == "")
         continue;

      if((ENUM_OBJECT)ObjectGetInteger(0, on, OBJPROP_TYPE) != OBJ_VLINE)
         continue;

      int scan_id = -1;
      int ns      = -1;
      string tail = "";

      if(!__TRGSTM_ParseMarkerNSTail(on, scan_id, ns, tail))
         continue;

      if(scan_id > g_scan_id)
         continue;

      Direction dir;
      bool is_mtc = false;

      if(StringFind(tail, "MTC_U_") == 0)
      {
         dir = DIR_UP;
         is_mtc = true;
      }
      else if(StringFind(tail, "MTC_D_") == 0)
      {
         dir = DIR_DOWN;
         is_mtc = true;
      }

      if(!is_mtc)
         continue;

      datetime t = (datetime)ObjectGetInteger(0, on, OBJPROP_TIME);
      if(scan_from > 0 && t < scan_from)
         continue;
      if(scan_to > 0 && t > scan_to)
         continue;

      int pos = ArraySize(out);
      ArrayResize(out, pos + 1);
      out[pos].t   = t;
      out[pos].dir = dir;
      out[pos].ns  = ns;
   }

   __TRGSTM_SortModeEvents(out);

   int n = ArraySize(out);
   if(n <= 1)
      return n;

   int wr = 1;
   for(int i = 1; i < n; ++i)
   {
      if(__TRGSTM_ModeEventSame(out[i], out[wr - 1]))
         continue;

      out[wr] = out[i];
      wr++;
   }

   ArrayResize(out, wr);
   return wr;
}

inline void __TRGSTM_AppendTrendWindow(TriggerStatementTrendWindow &out[],
                                       const datetime               start_time,
                                       const datetime               end_time,
                                       const Direction              dir,
                                       const string                 tag)
{
   if(start_time <= 0 && end_time <= 0)
      return;
   if(end_time > 0 && end_time < start_time)
      return;

   int pos = ArraySize(out);
   ArrayResize(out, pos + 1);

   out[pos].start_time = start_time;
   out[pos].end_time   = end_time;
   out[pos].dir        = dir;
   out[pos].tag        = tag;
}

inline int __TRGSTM_CompareTrendWindow(const TriggerStatementTrendWindow &a,
                                       const TriggerStatementTrendWindow &b)
{
   if(a.start_time < b.start_time) return -1;
   if(a.start_time > b.start_time) return 1;

   if(a.end_time < b.end_time) return -1;
   if(a.end_time > b.end_time) return 1;

   if((int)a.dir < (int)b.dir) return -1;
   if((int)a.dir > (int)b.dir) return 1;

   return 0;
}

inline void __TRGSTM_SortTrendWindows(TriggerStatementTrendWindow &windows[])
{
   int n = ArraySize(windows);
   if(n <= 1)
      return;

   for(int i = 0; i < n - 1; ++i)
   {
      int best = i;
      for(int j = i + 1; j < n; ++j)
      {
         if(__TRGSTM_CompareTrendWindow(windows[j], windows[best]) < 0)
            best = j;
      }

      if(best != i)
      {
         TriggerStatementTrendWindow tmp = windows[i];
         windows[i] = windows[best];
         windows[best] = tmp;
      }
   }
}

inline int __TRGSTM_BuildMajorTrendWindows(const datetime                  scan_from,
                                           const datetime                  scan_to,
                                           const int                       tfsec,
                                           const TriggerStatementBootResult &boot,
                                           const TriggerStatementModeEvent &events[],
                                           TriggerStatementTrendWindow     &out[])
{
   ArrayResize(out, 0);

   datetime start_time = scan_from;
   Direction cur_dir   = InpDirection;

   if(boot.ok && boot.complete_time > 0)
   {
      cur_dir = boot.mode;
      start_time = boot.complete_time + (datetime)tfsec;
   }

   if(start_time < 0)
      start_time = 0;

   if(scan_to > 0 && start_time > scan_to)
      return 0;

   datetime cursor = start_time;
   int total = ArraySize(events);

   for(int i = 0; i < total; ++i)
   {
      TriggerStatementModeEvent evt = events[i];
      if(evt.ns != TRGSTMT_NS_MAJ)
         continue;
      if(evt.t < start_time)
         continue;
      if(scan_to > 0 && evt.t > scan_to)
         continue;

      __TRGSTM_AppendTrendWindow(out,
                                 cursor,
                                 evt.t - 1,
                                 cur_dir,
                                 "MAJ");

      cur_dir = evt.dir;
      cursor  = evt.t;
   }

   __TRGSTM_AppendTrendWindow(out,
                              cursor,
                              scan_to,
                              cur_dir,
                              "MAJ");

   __TRGSTM_SortTrendWindows(out);
   return ArraySize(out);
}

inline int __TRGSTM_BuildMinorTrendWindows(const datetime                  scan_to,
                                           const TriggerStatementModeEvent &events[],
                                           TriggerStatementTrendWindow     &out[])
{
   ArrayResize(out, 0);

   if(!__FSMS_SW_ShouldRunMinorWorldOnThisChart())
      return 0;

   int session_count = FSMS_SW_Session_Count();
   for(int si = 0; si < session_count; ++si)
   {
      FSMS_SW_MinorSession s;
      if(!FSMS_SW_Session_Get(si, s))
         continue;
      if(!s.used)
         continue;
      if(s.starter_time <= 0)
         continue;

      datetime session_end = 0;
      if(s.open)
         session_end = scan_to;
      else
         session_end = (s.off_time > 0 ? (s.off_time - 1) : 0);

      if(session_end <= 0)
         continue;
      if(session_end < s.starter_time)
         continue;

      Direction cur_dir = s.dir;
      datetime  cursor  = s.starter_time;

      int total = ArraySize(events);
      for(int i = 0; i < total; ++i)
      {
         TriggerStatementModeEvent evt = events[i];
         if(evt.ns != TRGSTMT_NS_MIN)
            continue;
         if(evt.t < s.starter_time)
            continue;
         if(evt.t > session_end)
            continue;

         __TRGSTM_AppendTrendWindow(out,
                                    cursor,
                                    evt.t - 1,
                                    cur_dir,
                                    s.tag);

         cur_dir = evt.dir;
         cursor  = evt.t;
      }

      __TRGSTM_AppendTrendWindow(out,
                                 cursor,
                                 session_end,
                                 cur_dir,
                                 s.tag);
   }

   __TRGSTM_SortTrendWindows(out);
   return ArraySize(out);
}

inline int __TRGSTM_BuildEligibleTrendEpochs(const TriggerStatementTrendWindow &major_windows[],
                                             const TriggerStatementTrendWindow &minor_windows[],
                                             TriggerStatementTrendWindow       &out[])
{
   ArrayResize(out, 0);

   TriggerStatementTrendWindow combined[];
   ArrayResize(combined, 0);

   int major_total = ArraySize(major_windows);
   for(int i = 0; i < major_total; ++i)
   {
      __TRGSTM_AppendTrendWindow(combined,
                                 major_windows[i].start_time,
                                 major_windows[i].end_time,
                                 major_windows[i].dir,
                                 major_windows[i].tag);
   }

   int minor_total = ArraySize(minor_windows);
   for(int i = 0; i < minor_total; ++i)
   {
      __TRGSTM_AppendTrendWindow(combined,
                                 minor_windows[i].start_time,
                                 minor_windows[i].end_time,
                                 minor_windows[i].dir,
                                 minor_windows[i].tag);
   }

   __TRGSTM_SortTrendWindows(combined);

   for(int d = 0; d < 2; ++d)
   {
      Direction epoch_dir = (d == 0 ? DIR_UP : DIR_DOWN);
      bool     have_epoch = false;
      datetime epoch_start = 0;
      datetime epoch_end   = 0;

      int total = ArraySize(combined);
      for(int i = 0; i < total; ++i)
      {
         TriggerStatementTrendWindow w = combined[i];
         if(w.dir != epoch_dir)
            continue;
         if(w.end_time > 0 && w.end_time < w.start_time)
            continue;

         if(!have_epoch)
         {
            have_epoch = true;
            epoch_start = w.start_time;
            epoch_end   = w.end_time;
            continue;
         }

         bool merge = false;
         if(epoch_end <= 0)
            merge = true;
         else if(w.start_time <= (epoch_end + 1))
            merge = true;

         if(merge)
         {
            if(epoch_end <= 0 || w.end_time <= 0)
               epoch_end = 0;
            else if(w.end_time > epoch_end)
               epoch_end = w.end_time;
         }
         else
         {
            __TRGSTM_AppendTrendWindow(out,
                                       epoch_start,
                                       epoch_end,
                                       epoch_dir,
                                       "ELIG");

            epoch_start = w.start_time;
            epoch_end   = w.end_time;
         }
      }

      if(have_epoch)
      {
         __TRGSTM_AppendTrendWindow(out,
                                    epoch_start,
                                    epoch_end,
                                    epoch_dir,
                                    "ELIG");
      }
   }

   __TRGSTM_SortTrendWindows(out);
   return ArraySize(out);
}

inline bool __TRGSTM_TimeInsideTrendWindow(const TriggerStatementTrendWindow &w,
                                           const datetime                    t)
{
   if(t < w.start_time)
      return false;
   if(w.end_time > 0 && t > w.end_time)
      return false;
   return true;
}

inline bool __TRGSTM_FindActiveTrend(const TriggerStatementTrendWindow &windows[],
                                     const datetime                    t,
                                     Direction                        &dir,
                                     string                           &tag)
{
   dir = DIR_UP;
   tag = "";

   bool found = false;
   datetime best_start = 0;

   int total = ArraySize(windows);
   for(int i = 0; i < total; ++i)
   {
      if(!__TRGSTM_TimeInsideTrendWindow(windows[i], t))
         continue;

      if(!found || windows[i].start_time >= best_start)
      {
         found      = true;
         best_start = windows[i].start_time;
         dir        = windows[i].dir;
         tag        = windows[i].tag;
      }
   }

   return found;
}

inline string __TRGSTM_BuildTrendSlotText(const bool      active,
                                          const Direction dir,
                                          const string    tag,
                                          const string    prefix)
{
   if(!active)
      return (prefix + "_NONE");

   string text = prefix + "_" + __TRGSTM_DirName(dir);
   if(tag != "")
      text += ("#" + tag);

   return text;
}

inline string __TRGSTM_BuildTrendSkipNote(const Direction trg_dir,
                                          const bool      major_active,
                                          const Direction major_dir,
                                          const string    major_tag,
                                          const bool      minor_active,
                                          const Direction minor_dir,
                                          const string    minor_tag)
{
   string note = ("SKIPPED_" + __TRGSTM_WorkerLabel() + "_TREND_FILTER");
   note = __TRGSTM_AppendNote(note, "TRG_" + __TRGSTM_DirName(trg_dir));
   note = __TRGSTM_AppendNote(note, __TRGSTM_BuildTrendSlotText(major_active, major_dir, major_tag, "MAJ"));
   note = __TRGSTM_AppendNote(note, __TRGSTM_BuildTrendSlotText(minor_active, minor_dir, minor_tag, "MIN"));
   return note;
}

inline string __TRGSTM_BuildTrendMatchNote(const Direction trg_dir,
                                           const bool      major_match,
                                           const Direction major_dir,
                                           const string    major_tag,
                                           const bool      minor_match,
                                           const Direction minor_dir,
                                           const string    minor_tag)
{
   string note = "";

   if(major_match && minor_match)
      note = (__TRGSTM_WorkerLabel() + "_TREND_MATCH_BOTH");
   else if(major_match)
      note = (__TRGSTM_WorkerLabel() + "_TREND_MATCH_MAJOR");
   else if(minor_match)
      note = (__TRGSTM_WorkerLabel() + "_TREND_MATCH_MINOR");

   note = __TRGSTM_AppendNote(note, "TRG_" + __TRGSTM_DirName(trg_dir));

   if(major_match)
      note = __TRGSTM_AppendNote(note, __TRGSTM_BuildTrendSlotText(true, major_dir, major_tag, "MAJ"));
   if(minor_match)
      note = __TRGSTM_AppendNote(note, __TRGSTM_BuildTrendSlotText(true, minor_dir, minor_tag, "MIN"));

   return note;
}

inline bool __TRGSTM_FindEligibleTrendEpochStart(const TriggerStatementTrendWindow &epochs[],
                                                 const Direction                   dir,
                                                 const datetime                    t,
                                                 datetime                         &epoch_start)
{
   epoch_start = 0;

   bool found = false;
   datetime best_start = 0;

   int total = ArraySize(epochs);
   for(int i = 0; i < total; ++i)
   {
      if(epochs[i].dir != dir)
         continue;
      if(!__TRGSTM_TimeInsideTrendWindow(epochs[i], t))
         continue;

      if(!found || epochs[i].start_time >= best_start)
      {
         found       = true;
         best_start  = epochs[i].start_time;
         epoch_start = epochs[i].start_time;
      }
   }

   return found;
}

inline bool __TRGSTM_ResetGateIfNewTrendCycle(const TriggerStatementTrendWindow &eligible_epochs[],
                                              const Direction                   dir,
                                              const datetime                    t,
                                              bool                             &gate_cycle_set,
                                              Direction                        &gate_cycle_dir,
                                              datetime                         &gate_cycle_start,
                                              int                              &gate_loss_streak)
{
   datetime epoch_start = 0;
   if(!__TRGSTM_FindEligibleTrendEpochStart(eligible_epochs, dir, t, epoch_start))
      return false;

   bool had_cycle = gate_cycle_set;
   bool new_cycle = (!gate_cycle_set || gate_cycle_dir != dir || gate_cycle_start != epoch_start);
   if(!new_cycle)
      return false;

   gate_cycle_set   = true;
   gate_cycle_dir   = dir;
   gate_cycle_start = epoch_start;
   gate_loss_streak = 0;

   return had_cycle;
}

inline bool __TRGSTM_LoadRates(const string          sym,
                               const ENUM_TIMEFRAMES tf,
                               const datetime        from_time,
                               const datetime        to_time,
                               MqlRates              &rates[])
{
   ArrayResize(rates, 0);

   datetime use_from = from_time;
   datetime use_to   = to_time;

   if(use_to <= 0)
      use_to = TimeCurrent();

   if(use_from < 0)
      use_from = 0;

   if(use_from > use_to)
   {
      datetime tmp = use_from;
      use_from = use_to;
      use_to   = tmp;
   }

   int copied = CopyRates(sym, tf, use_from, use_to, rates);
   if(copied <= 0)
      return false;

   ArraySetAsSeries(rates, false);
   return true;
}

inline bool __TRGSTM_EvaluateTrade(const TriggerSLTPRecord &rec,
                                   const MqlRates          &rates[],
                                   const int                n,
                                   const datetime           scan_to,
                                   TriggerStatementTrade   &out)
{
   __TRGSTM_ClearTrade(out);
   out.valid = true;
   out.rec   = rec;

   if(n <= 0)
   {
      out.note = "NO_RATE_DATA";
      return false;
   }

   int start_idx = __TRGSTM_FindFirstBarAtOrAfter(rates, n, rec.hit_time);
   if(start_idx < 0)
      start_idx = __TRGSTM_FindLastBarAtOrBefore(rates, n, rec.hit_time);

   if(start_idx < 0 || start_idx >= n)
   {
      out.note = "NO_TRIGGER_BAR_IN_HISTORY";
      return false;
   }

   int    last_mark_idx = -1;
   double last_mark_px  = 0.0;

   for(int i = start_idx; i < n; ++i)
   {
      if(scan_to > 0 && rates[i].time > scan_to)
         break;

      last_mark_idx = i;
      last_mark_px  = rates[i].close;

      bool hit_tp = false;
      bool hit_sl = false;

      if(rec.dir == DIR_UP)
      {
         hit_tp = (rates[i].high >= rec.tp_level);
         hit_sl = (rates[i].low  <= rec.sl_level);
      }
      else
      {
         hit_tp = (rates[i].low  <= rec.tp_level);
         hit_sl = (rates[i].high >= rec.sl_level);
      }

      if(i == start_idx)
      {
         if(hit_tp && hit_sl)
         {
            out.result_status         = TRGSTMT_RESULT_LOSS;
            out.ambiguous             = true;
            out.trigger_bar_ambiguous = true;
            out.exit_time             = rates[i].time;
            out.exit_price            = rec.sl_level;
            out.result_r              = -1.0;
            out.bars_held             = 1;
            out.note                  = "AMBIGUOUS_TRIGGER_BAR_BOTH_HIT_ASSUMED_SL";
            return true;
         }

         if(hit_tp)
         {
            out.result_status = TRGSTMT_RESULT_WIN;
            out.exit_time     = rates[i].time;
            out.exit_price    = rec.tp_level;
            out.result_r      = ((rec.tp_level - rec.breakout_level) / rec.risk_price);
            if(rec.dir == DIR_DOWN)
               out.result_r = ((rec.breakout_level - rec.tp_level) / rec.risk_price);
            out.bars_held    = 1;
            out.note         = "TP_ON_TRIGGER_BAR";
            return true;
         }

         if(hit_sl)
         {
            out.result_status         = TRGSTMT_RESULT_LOSS;
            out.ambiguous             = true;
            out.trigger_bar_ambiguous = true;
            out.exit_time             = rates[i].time;
            out.exit_price            = rec.sl_level;
            out.result_r              = -1.0;
            out.bars_held             = 1;
            out.note                  = "AMBIGUOUS_TRIGGER_BAR_SL_ASSUMED_LOSS";
            return true;
         }

         continue;
      }

      if(hit_tp && hit_sl)
      {
         out.result_status = TRGSTMT_RESULT_LOSS;
         out.ambiguous     = true;
         out.exit_time     = rates[i].time;
         out.exit_price    = rec.sl_level;
         out.result_r      = -1.0;
         out.bars_held     = (i - start_idx + 1);
         out.note          = "AMBIGUOUS_SAME_BAR_BOTH_HIT_ASSUMED_SL";
         return true;
      }

      if(hit_tp)
      {
         out.result_status = TRGSTMT_RESULT_WIN;
         out.exit_time     = rates[i].time;
         out.exit_price    = rec.tp_level;
         out.result_r      = ((rec.tp_level - rec.breakout_level) / rec.risk_price);
         if(rec.dir == DIR_DOWN)
            out.result_r = ((rec.breakout_level - rec.tp_level) / rec.risk_price);
         out.bars_held     = (i - start_idx + 1);
         out.note          = "TP_HIT";
         return true;
      }

      if(hit_sl)
      {
         out.result_status = TRGSTMT_RESULT_LOSS;
         out.exit_time     = rates[i].time;
         out.exit_price    = rec.sl_level;
         out.result_r      = -1.0;
         out.bars_held     = (i - start_idx + 1);
         out.note          = "SL_HIT";
         return true;
      }
   }

   out.result_status = TRGSTMT_RESULT_OPEN;
   out.note          = "OPEN_AT_SCAN_END";

   if(last_mark_idx >= 0)
   {
      out.exit_time  = rates[last_mark_idx].time;
      out.exit_price = last_mark_px;
      out.bars_held  = (last_mark_idx - start_idx + 1);

      if(rec.risk_price > 0.0)
      {
         if(rec.dir == DIR_UP)
            out.floating_r = ((last_mark_px - rec.breakout_level) / rec.risk_price);
         else
            out.floating_r = ((rec.breakout_level - last_mark_px) / rec.risk_price);
      }
   }

   return true;
}

inline string __TRGSTM_Money(double v)
{
   return DoubleToString(v, 2);
}

inline string __TRGSTM_Pct(const double v)
{
   return (DoubleToString(v, 2) + "%");
}

inline bool TriggerStatement_WriteTextReport(const string          sym,
                                             const ENUM_TIMEFRAMES tf,
                                             const datetime        scan_from,
                                             const datetime        scan_to,
                                             const double          initial_capital_input,
                                             const double          risk_percent_input,
                                             const string          file_tag)
{
   string use_sym = sym;
   if(use_sym == "")
      use_sym = _Symbol;

   double initial_capital = initial_capital_input;
   if(initial_capital <= 0.0)
      initial_capital = AccountInfoDouble(ACCOUNT_BALANCE);
   if(initial_capital <= 0.0)
      initial_capital = 10000.0;

   double risk_percent = risk_percent_input;
   if(risk_percent <= 0.0)
      risk_percent = 1.0;

   TriggerSLTPRecord records[];
   int raw_valid_triggers = __TRGSTM_CollectRecords(use_sym, scan_from, scan_to, records);

   int tfsec = PeriodSeconds(tf);
   if(tfsec <= 0)
      tfsec = 60;

   datetime load_from = scan_from;
   if(raw_valid_triggers > 0)
   {
      load_from = records[0].hit_time - (datetime)(tfsec * 2);
      if(load_from < 0)
         load_from = 0;
   }

   datetime use_scan_to = scan_to;
   if(use_scan_to <= 0)
      use_scan_to = TimeCurrent();

   MqlRates rates[];
   bool have_rates = false;
   if(raw_valid_triggers > 0)
      have_rates = __TRGSTM_LoadRates(use_sym, tf, load_from, use_scan_to, rates);

   double risk_money = initial_capital * (risk_percent / 100.0);

   TriggerStatementTrade trades[];
   ArrayResize(trades, raw_valid_triggers);
   for(int i = 0; i < raw_valid_triggers; ++i)
   {
      __TRGSTM_ClearTrade(trades[i]);
      trades[i].valid     = true;
      trades[i].raw_index = (i + 1);
      trades[i].rec       = records[i];

      if(have_rates)
      {
         bool eval_ok = __TRGSTM_EvaluateTrade(records[i], rates, ArraySize(rates), use_scan_to, trades[i]);
         trades[i].valid     = true;
         trades[i].raw_index = (i + 1);
         trades[i].rec       = records[i];

         if(!eval_ok)
            trades[i].rec = records[i];
      }
      else
      {
         trades[i].note = "NO_RATE_DATA";
      }
   }

   TriggerStatementStartEvent bridge_events[];
   int bridge_event_count = __TRGSTM_CollectBridgeEvents(use_sym, use_scan_to, bridge_events);

   TriggerStatementStartEvent local_gate_events[];
   int local_gate_count = __TRGSTM_CollectLocalGateEvents(use_sym, use_scan_to, local_gate_events);

   TriggerStatementStartEvent local_gate_start_events[];
   int local_gate_start_count = __TRGSTM_FilterLocalGateStartEvents(local_gate_events,
                                                                    local_gate_count,
                                                                    local_gate_start_events);

   TriggerStatementModeEvent mtc_events[];
   int mtc_count = __TRGSTM_CollectMTCMarkerEvents(scan_from, use_scan_to, mtc_events);

   TriggerStatementBootResult major_boot = __TRGSTM_BootstrapDetect(use_sym, tf, scan_from, use_scan_to);

   TriggerStatementTrendWindow major_windows[];
   TriggerStatementTrendWindow minor_windows[];
   TriggerStatementTrendWindow eligible_epochs[];

   int major_window_count = __TRGSTM_BuildMajorTrendWindows(scan_from,
                                                            use_scan_to,
                                                            tfsec,
                                                            major_boot,
                                                            mtc_events,
                                                            major_windows);

   int minor_window_count = __TRGSTM_BuildMinorTrendWindows(use_scan_to,
                                                            mtc_events,
                                                            minor_windows);

   int eligible_epoch_count = __TRGSTM_BuildEligibleTrendEpochs(major_windows,
                                                                minor_windows,
                                                                eligible_epochs);

   int minor_session_count = (__FSMS_SW_ShouldRunMinorWorldOnThisChart() ? FSMS_SW_Session_Count() : 0);

   datetime major_resume_from = scan_from;
   if(major_boot.ok && major_boot.complete_time > 0)
   {
      major_resume_from = major_boot.complete_time + (datetime)tfsec;
   }

   string major_seed_text = "";
   if(major_boot.ok && major_boot.complete_time > 0)
   {
      major_seed_text = "BOOTSTRAP_" + __TRGSTM_DirName(major_boot.mode)
                      + " @ " + __TRGSTM_SafeTime(major_boot.complete_time)
                      + " | ActiveFrom=" + __TRGSTM_SafeTime(major_resume_from);
   }
   else
   {
      major_seed_text = "FALLBACK_" + __TRGSTM_DirName(InpDirection)
                      + " | ActiveFrom=" + __TRGSTM_SafeTime(scan_from);
   }

   double equity             = initial_capital;
   double peak_balance       = initial_capital;
   double highest_balance    = initial_capital;
   double lowest_balance     = initial_capital;
   double max_drawdown_money = 0.0;
   double max_drawdown_pct   = 0.0;

   int executed_trades         = 0;
   int ignored_valid_triggers  = 0;
   int skipped_active_trade    = 0;
   int skipped_daily_loss_cap  = 0;
   int skipped_post_win_wait   = 0;
   int skipped_hypo_wins       = 0;
   int skipped_hypo_losses     = 0;
   int skipped_hypo_open       = 0;

   int closed_trades = 0;
   int wins          = 0;
   int losses        = 0;
   int open_trades   = 0;
   int ambiguous_losses      = 0;
   int trigger_bar_ambiguous = 0;

   int buy_total   = 0;
   int sell_total  = 0;
   int buy_wins    = 0;
   int sell_wins   = 0;
   int buy_losses  = 0;
   int sell_losses = 0;

   int current_win_streak  = 0;
   int current_loss_streak = 0;
   int max_win_streak      = 0;
   int max_loss_streak     = 0;

   int  daily_loss_count         = 0;
   int  daily_loss_day_key       = 0;
   bool daily_loss_cap_active    = false;
   int  daily_loss_cap_activations = 0;
   int  daily_loss_cap_resets      = 0;
   int  post_win_wait_arms         = 0;
   int  post_win_wait_releases     = 0;

   int exec_trend_major_only = 0;
   int exec_trend_minor_only = 0;
   int exec_trend_both       = 0;

   double gross_profit = 0.0;
   double gross_loss   = 0.0;
   double net_profit   = 0.0;
   double total_r      = 0.0;

   double sum_win_money  = 0.0;
   double sum_loss_money = 0.0;
   double sum_win_r      = 0.0;
   double sum_loss_r     = 0.0;

   double best_trade_money  = -DBL_MAX;
   double worst_trade_money = DBL_MAX;
   double best_trade_r      = -DBL_MAX;
   double worst_trade_r     = DBL_MAX;
   int    best_trade_exec_index  = -1;
   int    worst_trade_exec_index = -1;

   double min_risk_pips = DBL_MAX;
   double max_risk_pips = 0.0;
   double sum_risk_pips = 0.0;

   double total_open_float_money = 0.0;
   double total_open_float_r     = 0.0;

   bool     active_trade_open  = false;
   datetime active_trade_until = 0;

   bool     post_win_wait_active   = false;
   datetime post_win_wait_ref_time = 0;
   int      next_local_rearm_index = 0;

   bool      parent_gate_active     = false;
   Direction parent_gate_dir        = DIR_UP;
   int       parent_gate_kind       = 0;
   int       parent_gate_ns         = WB15_NS_NONE;
   datetime  parent_gate_start_time = 0;
   datetime  parent_gate_start_bar  = 0;
   int       next_parent_gate_index = 0;
   int       parent_gate_seq        = -1;

   bool      local_gate_active     = false;
   Direction local_gate_dir        = DIR_UP;
   int       local_gate_kind       = 0;
   int       local_gate_ns         = WB15_NS_NONE;
   datetime  local_gate_start_time = 0;
   datetime  local_gate_start_bar  = 0;
   int       next_local_gate_index = 0;
   int       local_gate_seq        = -1;

   for(int i = 0; i < raw_valid_triggers; ++i)
   {
      __TRGSTM_AdvanceParentGateEvents(bridge_events,
                                       bridge_event_count,
                                       next_parent_gate_index,
                                       trades[i].rec.hit_time,
                                       parent_gate_active,
                                       parent_gate_dir,
                                       parent_gate_kind,
                                       parent_gate_ns,
                                       parent_gate_start_time,
                                       parent_gate_start_bar,
                                       parent_gate_seq);

      __TRGSTM_AdvanceLocalGateEvents(local_gate_events,
                                      local_gate_count,
                                      next_local_gate_index,
                                      trades[i].rec.hit_time,
                                      local_gate_active,
                                      local_gate_dir,
                                      local_gate_kind,
                                      local_gate_ns,
                                      local_gate_start_time,
                                      local_gate_start_bar,
                                      local_gate_seq);

      Direction local_rearm_dir  = DIR_UP;
      int       local_rearm_kind = 0;
      int       local_rearm_ns   = WB15_NS_NONE;
      datetime  local_rearm_time = __TRGSTM_AdvanceLocalGateRearmEvents(local_gate_start_events,
                                                                         local_gate_start_count,
                                                                         next_local_rearm_index,
                                                                         trades[i].rec.hit_time,
                                                                         post_win_wait_active,
                                                                         post_win_wait_ref_time,
                                                                         local_rearm_dir,
                                                                         local_rearm_kind,
                                                                         local_rearm_ns);
      if(local_rearm_time > 0)
         post_win_wait_releases++;

      __TRGSTM_EnsureDailyLossBucket(trades[i].rec.hit_time,
                                     daily_loss_day_key,
                                     daily_loss_count,
                                     daily_loss_cap_active,
                                     daily_loss_cap_resets);

      if(active_trade_open)
      {
         if(active_trade_until > 0 && trades[i].rec.hit_time > active_trade_until)
         {
            active_trade_open  = false;
            active_trade_until = 0;
         }
      }

      if(active_trade_open)
      {
         __TRGSTM_SetSkip(trades[i],
                          TRGSTMT_SKIP_ACTIVE_TRADE,
                          equity,
                          __TRGSTM_AppendNote(trades[i].note, "SKIPPED_ACTIVE_TRADE_ALREADY_OPEN"));
         ignored_valid_triggers++;
         skipped_active_trade++;
         __TRGSTM_BumpHypotheticalCounters(trades[i],
                                           skipped_hypo_wins,
                                           skipped_hypo_losses,
                                           skipped_hypo_open);
         continue;
      }

      if(daily_loss_cap_active && daily_loss_count >= TRGSTMT_LOCK_AFTER_LOSSES)
      {
         trades[i].unlock_on_time = __TRGSTM_NextDayStart(trades[i].rec.hit_time);
         __TRGSTM_SetSkip(trades[i],
                          TRGSTMT_SKIP_DAILY_LOSS_CAP,
                          equity,
                          __TRGSTM_AppendNote(trades[i].note,
                                              "SKIPPED_DAILY_4L_CAP_UNTIL_" + __TRGSTM_SafeTime(trades[i].unlock_on_time)));
         ignored_valid_triggers++;
         skipped_daily_loss_cap++;
         __TRGSTM_BumpHypotheticalCounters(trades[i],
                                           skipped_hypo_wins,
                                           skipped_hypo_losses,
                                           skipped_hypo_open);
         continue;
      }

      Direction major_dir = DIR_UP;
      Direction minor_dir = DIR_UP;
      string    major_tag = "";
      string    minor_tag = "";

      bool major_active = __TRGSTM_FindActiveTrend(major_windows,
                                                   trades[i].rec.hit_time,
                                                   major_dir,
                                                   major_tag);

      bool minor_active = __TRGSTM_FindActiveTrend(minor_windows,
                                                   trades[i].rec.hit_time,
                                                   minor_dir,
                                                   minor_tag);

      bool major_match = (major_active && major_dir == trades[i].rec.dir);
      bool minor_match = (minor_active && minor_dir == trades[i].rec.dir);

      if(major_match && minor_match)
         exec_trend_both++;
      else if(major_match)
         exec_trend_major_only++;
      else if(minor_match)
         exec_trend_minor_only++;

      if(post_win_wait_active)
      {
         __TRGSTM_SetSkip(trades[i],
                          TRGSTMT_SKIP_POST_WIN_WAIT,
                          equity,
                          __TRGSTM_AppendNote(trades[i].note,
                                              __TRGSTM_BuildPostWinWaitSkipNote(trades[i].rec.dir,
                                                                                post_win_wait_ref_time,
                                                                                local_gate_active,
                                                                                local_gate_dir,
                                                                                local_gate_kind,
                                                                                local_gate_ns,
                                                                                local_gate_start_bar)));
         ignored_valid_triggers++;
         skipped_post_win_wait++;
         __TRGSTM_BumpHypotheticalCounters(trades[i],
                                           skipped_hypo_wins,
                                           skipped_hypo_losses,
                                           skipped_hypo_open);
         continue;
      }

      if(local_rearm_time > 0)
      {
         trades[i].note = __TRGSTM_AppendNote(trades[i].note,
                                              __TRGSTM_BuildPostWinRearmNote(local_rearm_dir,
                                                                            local_rearm_kind,
                                                                            local_rearm_ns,
                                                                            local_rearm_time));
      }

      trades[i].taken       = true;
      trades[i].exec_index  = (executed_trades + 1);
      trades[i].skip_reason = TRGSTMT_SKIP_NONE;
      executed_trades++;

      trades[i].note = __TRGSTM_AppendNote(trades[i].note, "ENGINE_TRIGGER_WINDOW_OK");
      trades[i].note = __TRGSTM_AppendNote(trades[i].note,
                                           __TRGSTM_BuildTrendMatchNote(trades[i].rec.dir,
                                                                        major_match,
                                                                        major_dir,
                                                                        major_tag,
                                                                        minor_match,
                                                                        minor_dir,
                                                                        minor_tag));
      if(local_gate_active)
      {
         trades[i].note = __TRGSTM_AppendNote(trades[i].note,
                                              __TRGSTM_BuildLocalGateMatchNote(trades[i].rec.dir,
                                                                               local_gate_kind,
                                                                               local_gate_ns,
                                                                               local_gate_start_bar));
      }
      if(parent_gate_active)
      {
         trades[i].note = __TRGSTM_AppendNote(trades[i].note,
                                              "PARENT_GATE_FROM_" + __TRGSTM_SafeTime(parent_gate_start_bar));
      }

      if(trades[i].rec.dir == DIR_UP)
         buy_total++;
      else
         sell_total++;

      if(trades[i].rec.risk_pips < min_risk_pips)
         min_risk_pips = trades[i].rec.risk_pips;
      if(trades[i].rec.risk_pips > max_risk_pips)
         max_risk_pips = trades[i].rec.risk_pips;
      sum_risk_pips += trades[i].rec.risk_pips;

      if(__TRGSTM_IsClosedStatus(trades[i].result_status))
      {
         closed_trades++;
         trades[i].pnl_money    = (trades[i].result_r * risk_money);
         trades[i].equity_after = (equity + trades[i].pnl_money);
         equity                 = trades[i].equity_after;
         net_profit            += trades[i].pnl_money;
         total_r               += trades[i].result_r;

         if(equity > peak_balance)
            peak_balance = equity;
         if(equity > highest_balance)
            highest_balance = equity;
         if(equity < lowest_balance)
            lowest_balance = equity;

         double dd_money = (peak_balance - equity);
         double dd_pct   = 0.0;
         if(peak_balance > 0.0)
            dd_pct = (dd_money / peak_balance) * 100.0;

         if(dd_money > max_drawdown_money)
         {
            max_drawdown_money = dd_money;
            max_drawdown_pct   = dd_pct;
         }

         if(trades[i].result_status == TRGSTMT_RESULT_WIN)
         {
            wins++;
            gross_profit += trades[i].pnl_money;
            sum_win_money += trades[i].pnl_money;
            sum_win_r     += trades[i].result_r;
            current_win_streak++;
            current_loss_streak = 0;
            if(current_win_streak > max_win_streak)
               max_win_streak = current_win_streak;
            trades[i].streak_after = current_win_streak;

            if(trades[i].rec.dir == DIR_UP)
               buy_wins++;
            else
               sell_wins++;

            post_win_wait_active   = true;
            post_win_wait_ref_time = (trades[i].exit_time > 0 ? trades[i].exit_time : trades[i].rec.hit_time);
            post_win_wait_arms++;
            trades[i].note = __TRGSTM_AppendNote(trades[i].note,
                                                 ("WAIT_FRESH_LOCAL_" + __TRGSTM_WorkerLabel() + "_SIGNAL_ON_AFTER_WIN"));
         }
         else
         {
            losses++;
            gross_loss += MathAbs(trades[i].pnl_money);
            sum_loss_money += MathAbs(trades[i].pnl_money);
            sum_loss_r     += MathAbs(trades[i].result_r);
            current_loss_streak++;
            current_win_streak = 0;
            if(current_loss_streak > max_loss_streak)
               max_loss_streak = current_loss_streak;
            trades[i].streak_after = -current_loss_streak;

            if(trades[i].rec.dir == DIR_UP)
               buy_losses++;
            else
               sell_losses++;

            if(trades[i].ambiguous)
               ambiguous_losses++;
            if(trades[i].trigger_bar_ambiguous)
               trigger_bar_ambiguous++;

            daily_loss_count++;
            if(daily_loss_count >= TRGSTMT_LOCK_AFTER_LOSSES)
            {
               daily_loss_cap_active = true;
               daily_loss_cap_activations++;
               trades[i].note = __TRGSTM_AppendNote(trades[i].note,
                                                    "DAILY_4L_CAP_ACTIVE_UNTIL_" + __TRGSTM_SafeTime(__TRGSTM_NextDayStart(trades[i].exit_time > 0 ? trades[i].exit_time : trades[i].rec.hit_time)));
            }
         }

         if(trades[i].pnl_money > best_trade_money)
         {
            best_trade_money      = trades[i].pnl_money;
            best_trade_r          = trades[i].result_r;
            best_trade_exec_index = trades[i].exec_index;
         }

         if(trades[i].pnl_money < worst_trade_money)
         {
            worst_trade_money      = trades[i].pnl_money;
            worst_trade_r          = trades[i].result_r;
            worst_trade_exec_index = trades[i].exec_index;
         }

         active_trade_open = true;
         if(trades[i].exit_time > 0)
            active_trade_until = trades[i].exit_time;
         else
            active_trade_until = trades[i].rec.hit_time;
      }
      else
      {
         open_trades++;
         trades[i].floating_money = (trades[i].floating_r * risk_money);
         trades[i].equity_after   = equity;
         total_open_float_money += trades[i].floating_money;
         total_open_float_r     += trades[i].floating_r;

         active_trade_open  = true;
         active_trade_until = use_scan_to;
      }
   }

   if(post_win_wait_active)
   {
      Direction local_rearm_dir  = DIR_UP;
      int       local_rearm_kind = 0;
      int       local_rearm_ns   = WB15_NS_NONE;
      datetime  local_rearm_time = __TRGSTM_AdvanceLocalGateRearmEvents(local_gate_start_events,
                                                                         local_gate_start_count,
                                                                         next_local_rearm_index,
                                                                         use_scan_to,
                                                                         post_win_wait_active,
                                                                         post_win_wait_ref_time,
                                                                         local_rearm_dir,
                                                                         local_rearm_kind,
                                                                         local_rearm_ns);
      if(local_rearm_time > 0)
         post_win_wait_releases++;
   }

   bool daily_loss_cap_active_at_end = daily_loss_cap_active;
   bool post_win_wait_at_end         = post_win_wait_active;
   int  daily_loss_count_at_end      = daily_loss_count;
   int  daily_loss_day_key_at_end    = daily_loss_day_key;

   if(executed_trades <= 0)
   {
      min_risk_pips = 0.0;
      max_risk_pips = 0.0;
   }
   else if(min_risk_pips == DBL_MAX)
   {
      min_risk_pips = 0.0;
   }

   double execution_rate     = 0.0;
   double ignored_rate       = 0.0;
   double win_rate           = 0.0;
   double loss_rate          = 0.0;
   double profit_factor      = 0.0;
   double avg_win_money      = 0.0;
   double avg_loss_money     = 0.0;
   double avg_win_r          = 0.0;
   double avg_loss_r         = 0.0;
   double expectancy_money   = 0.0;
   double expectancy_r       = 0.0;
   double payoff_ratio       = 0.0;
   double recovery_factor    = 0.0;
   double avg_risk_pips      = 0.0;
   double return_pct         = 0.0;
   double balance_plus_float = (equity + total_open_float_money);

   if(raw_valid_triggers > 0)
   {
      execution_rate = ((double)executed_trades / (double)raw_valid_triggers) * 100.0;
      ignored_rate   = ((double)ignored_valid_triggers / (double)raw_valid_triggers) * 100.0;
   }

   if(closed_trades > 0)
   {
      win_rate         = ((double)wins / (double)closed_trades) * 100.0;
      loss_rate        = ((double)losses / (double)closed_trades) * 100.0;
      expectancy_money = (net_profit / (double)closed_trades);
      expectancy_r     = (total_r / (double)closed_trades);
   }

   if(losses > 0)
   {
      avg_loss_money = (sum_loss_money / (double)losses);
      avg_loss_r     = (sum_loss_r / (double)losses);
   }

   if(wins > 0)
   {
      avg_win_money = (sum_win_money / (double)wins);
      avg_win_r     = (sum_win_r / (double)wins);
   }

   if(gross_loss > 0.0)
      profit_factor = (gross_profit / gross_loss);

   if(avg_loss_money > 0.0)
      payoff_ratio = (avg_win_money / avg_loss_money);

   if(max_drawdown_money > 0.0)
      recovery_factor = (net_profit / max_drawdown_money);

   if(executed_trades > 0)
      avg_risk_pips = (sum_risk_pips / (double)executed_trades);

   if(initial_capital > 0.0)
      return_pct = (net_profit / initial_capital) * 100.0;

   string filename = __TRGSTM_BuildFileName(file_tag, use_sym, tf);
   int handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_UNICODE|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      g_trgstmt_last_filename = filename;
      g_trgstmt_last_fullpath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + filename;
      g_trgstmt_last_write_ok = false;
      g_trgstmt_last_scan_from = scan_from;
      g_trgstmt_last_scan_to   = use_scan_to;
      g_trgstmt_last_records   = raw_valid_triggers;

      if(InpDebugPrints)
         Print("[TRG-STATEMENT] FileOpen failed | path=", g_trgstmt_last_fullpath,
               " | error=", GetLastError());
      return false;
   }

   g_trgstmt_last_filename = filename;
   g_trgstmt_last_fullpath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + filename;
   g_trgstmt_last_write_ok = true;
   g_trgstmt_last_scan_from = scan_from;
   g_trgstmt_last_scan_to   = use_scan_to;
   g_trgstmt_last_records   = raw_valid_triggers;

   int digits = __TRGSL_DigitsOf(use_sym);

   string best_trade_text = "n/a";
   if(best_trade_exec_index > 0)
      best_trade_text = ("#" + IntegerToString(best_trade_exec_index)
                      + " | " + __TRGSTM_Money(best_trade_money)
                      + " | " + DoubleToString(best_trade_r, 2) + "R");

   string worst_trade_text = "n/a";
   if(worst_trade_exec_index > 0)
      worst_trade_text = ("#" + IntegerToString(worst_trade_exec_index)
                       + " | " + __TRGSTM_Money(worst_trade_money)
                       + " | " + DoubleToString(worst_trade_r, 2) + "R");

   __TRGSTM_WriteLine(handle, "WaveBot Trigger Statement");
   __TRGSTM_WriteLine(handle, "============================================================");
   __TRGSTM_WriteLine(handle, "Generated At           : " + __TRGSTM_SafeTime(TimeCurrent()));
   __TRGSTM_WriteLine(handle, "Symbol                 : " + use_sym);
   __TRGSTM_WriteLine(handle, "Timeframe              : " + __TRGSTM_TimeframeTag(tf));
   __TRGSTM_WriteLine(handle, "Scan From              : " + __TRGSTM_SafeTime(scan_from));
   __TRGSTM_WriteLine(handle, "Scan To                : " + __TRGSTM_SafeTime(use_scan_to));
   __TRGSTM_WriteLine(handle, "Initial Capital        : " + __TRGSTM_Money(initial_capital));
   __TRGSTM_WriteLine(handle, "Fixed Risk Per Trade   : " + __TRGSTM_Pct(risk_percent) + " = " + __TRGSTM_Money(risk_money));
   __TRGSTM_WriteLine(handle, "SL/TP Source           : TriggerSLTP.mqh valid triggers only");
   __TRGSTM_WriteLine(handle, "Execution Model        : Single active trade only | entry at breakout level | touch-based TP/SL | conservative same-bar ambiguity = SL | Trigger.mqh already enforces the parent " + __TRGSTM_ParentLabel() + " -> " + __TRGSTM_WorkerLabel() + " window plus the active local " + __TRGSTM_WorkerLabel() + " signal gate | max 4 executed losses per calendar day | fresh local " + __TRGSTM_WorkerLabel() + " signal-on required after every executed WIN");
   __TRGSTM_WriteLine(handle, "Protection Rule        : After 4 executed losses on the same calendar day, no more trades are allowed until the next calendar day starts");
   if(__FSMS_SW_ShouldRunMinorWorldOnThisChart())
      __TRGSTM_WriteLine(handle, "Trend Context          : " + __TRGSTM_WorkerLabel() + " major/minor windows are reported as context only; execution itself follows Trigger.mqh parent/local gate rules");
   else
      __TRGSTM_WriteLine(handle, "Trend Context          : local minor world is disabled on this chart; execution itself follows Trigger.mqh parent/local gate rules");

   if(__FSMS_SW_ShouldRunMinorWorldOnThisChart())
      __TRGSTM_WriteLine(handle, "Local " + __TRGSTM_WorkerLabel() + " Signal Gate  : Trigger direction must also sit inside the active local " + __TRGSTM_WorkerLabel() + " signal-on window opened by HWX/HWBB/FSMS/Gooz and closed by opposite MTC/MinorStarter/MinorOff");
   else
      __TRGSTM_WriteLine(handle, "Local " + __TRGSTM_WorkerLabel() + " Signal Gate  : Trigger direction must also sit inside the active local " + __TRGSTM_WorkerLabel() + " signal-on window opened by HWX/HWBB/FSMS/Gooz and closed by opposite MTC only");
   __TRGSTM_WriteLine(handle, "Post-Win Re-Entry Rule : After each executed WIN, no new trigger can become a trade until a fresh local " + __TRGSTM_WorkerLabel() + " signal-on event arrives after that win");
   __TRGSTM_WriteLine(handle, "Trend Seed (Major)     : " + major_seed_text);
   __TRGSTM_WriteLine(handle, "Trend Windows MAJ/MIN  : " + IntegerToString(major_window_count) + " / " + IntegerToString(minor_window_count));
   __TRGSTM_WriteLine(handle, "Aligned Trend Cycles   : " + IntegerToString(eligible_epoch_count));
   __TRGSTM_WriteLine(handle, "Minor Sessions Seen    : " + IntegerToString(minor_session_count));
   __TRGSTM_WriteLine(handle, "MTC Marker Events      : " + IntegerToString(mtc_count));
   __TRGSTM_WriteLine(handle, "Local Gate Events      : " + IntegerToString(local_gate_count));
   __TRGSTM_WriteLine(handle, "Bridge Source          : Trigger.mqh / " + __TRGSTM_ParentLabel() + " -> " + __TRGSTM_WorkerLabel() + " bridge events");
   __TRGSTM_WriteLine(handle, "Local Gate Source      : TriggerM15SignalGate.mqh / local " + __TRGSTM_WorkerLabel() + " signal on-off events");
   __TRGSTM_WriteLine(handle, "Output Path            : " + g_trgstmt_last_fullpath);
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "SUMMARY");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   __TRGSTM_WriteLine(handle, "Raw Valid Triggers     : " + IntegerToString(raw_valid_triggers));
   __TRGSTM_WriteLine(handle, "Executed Trades        : " + IntegerToString(executed_trades));
   __TRGSTM_WriteLine(handle, "Execution Rate         : " + __TRGSTM_Pct(execution_rate));
   __TRGSTM_WriteLine(handle, "Ignored Valid Triggers : " + IntegerToString(ignored_valid_triggers) + " | " + __TRGSTM_Pct(ignored_rate));
   __TRGSTM_WriteLine(handle, "Ignored: Active Trade  : " + IntegerToString(skipped_active_trade));
   __TRGSTM_WriteLine(handle, "Ignored: Daily 4L Cap  : " + IntegerToString(skipped_daily_loss_cap));
   __TRGSTM_WriteLine(handle, "Engine Gate            : Parent/local gate enforced before TriggerSLTP records are created inside Trigger.mqh");
   __TRGSTM_WriteLine(handle, "Trend Context MAJ/MIN/B: " + IntegerToString(exec_trend_major_only) + " / " + IntegerToString(exec_trend_minor_only) + " / " + IntegerToString(exec_trend_both));
   __TRGSTM_WriteLine(handle, "Ignored: Post-Win Wait : " + IntegerToString(skipped_post_win_wait));
   __TRGSTM_WriteLine(handle, "Skipped Hypo W/L/O     : " + IntegerToString(skipped_hypo_wins) + " / " + IntegerToString(skipped_hypo_losses) + " / " + IntegerToString(skipped_hypo_open));
   __TRGSTM_WriteLine(handle, "Closed Trades          : " + IntegerToString(closed_trades));
   __TRGSTM_WriteLine(handle, "Open Trades            : " + IntegerToString(open_trades));
   __TRGSTM_WriteLine(handle, "Wins / Losses          : " + IntegerToString(wins) + " / " + IntegerToString(losses));
   __TRGSTM_WriteLine(handle, "Win Rate / Loss Rate   : " + __TRGSTM_Pct(win_rate) + " / " + __TRGSTM_Pct(loss_rate));
   __TRGSTM_WriteLine(handle, "Bull Exec Trades W/L   : " + IntegerToString(buy_total) + " | " + IntegerToString(buy_wins) + " / " + IntegerToString(buy_losses));
   __TRGSTM_WriteLine(handle, "Bear Exec Trades W/L   : " + IntegerToString(sell_total) + " | " + IntegerToString(sell_wins) + " / " + IntegerToString(sell_losses));
   __TRGSTM_WriteLine(handle, "Gross Profit           : " + __TRGSTM_Money(gross_profit));
   __TRGSTM_WriteLine(handle, "Gross Loss             : " + __TRGSTM_Money(gross_loss));
   __TRGSTM_WriteLine(handle, "Net Profit             : " + __TRGSTM_Money(net_profit));
   __TRGSTM_WriteLine(handle, "Return On Initial Cap. : " + __TRGSTM_Pct(return_pct));
   __TRGSTM_WriteLine(handle, "Profit Factor          : " + DoubleToString(profit_factor, 2));
   __TRGSTM_WriteLine(handle, "Payoff Ratio           : " + DoubleToString(payoff_ratio, 2));
   __TRGSTM_WriteLine(handle, "Recovery Factor        : " + DoubleToString(recovery_factor, 2));
   __TRGSTM_WriteLine(handle, "Expectancy / Trade     : " + __TRGSTM_Money(expectancy_money) + " | " + DoubleToString(expectancy_r, 2) + "R");
   __TRGSTM_WriteLine(handle, "Average Win            : " + __TRGSTM_Money(avg_win_money) + " | " + DoubleToString(avg_win_r, 2) + "R");
   __TRGSTM_WriteLine(handle, "Average Loss           : " + __TRGSTM_Money(avg_loss_money) + " | -" + DoubleToString(avg_loss_r, 2) + "R");
   __TRGSTM_WriteLine(handle, "Best Trade             : " + best_trade_text);
   __TRGSTM_WriteLine(handle, "Worst Trade            : " + worst_trade_text);
   __TRGSTM_WriteLine(handle, "Max Win Streak         : " + IntegerToString(max_win_streak));
   __TRGSTM_WriteLine(handle, "Max Loss Streak        : " + IntegerToString(max_loss_streak));
   __TRGSTM_WriteLine(handle, "Daily 4L Threshold     : " + IntegerToString(TRGSTMT_LOCK_AFTER_LOSSES));
   __TRGSTM_WriteLine(handle, "Daily Cap Activations  : " + IntegerToString(daily_loss_cap_activations));
   __TRGSTM_WriteLine(handle, "Daily Cap Resets       : " + IntegerToString(daily_loss_cap_resets));
   __TRGSTM_WriteLine(handle, "Daily Cap Active End   : " + (daily_loss_cap_active_at_end ? "YES" : "NO"));
   __TRGSTM_WriteLine(handle, "Daily Losses End Day   : " + IntegerToString(daily_loss_count_at_end) + " | " + __TRGSTM_DayKeyText(daily_loss_day_key_at_end));
   __TRGSTM_WriteLine(handle, "Post-Win Wait Arms     : " + IntegerToString(post_win_wait_arms));
   __TRGSTM_WriteLine(handle, "Post-Win Wait Releases : " + IntegerToString(post_win_wait_releases));
   __TRGSTM_WriteLine(handle, "Post-Win Wait At End   : " + (post_win_wait_at_end ? "YES" : "NO"));
   __TRGSTM_WriteLine(handle, "Max Drawdown           : " + __TRGSTM_Money(max_drawdown_money) + " | " + __TRGSTM_Pct(max_drawdown_pct));
   __TRGSTM_WriteLine(handle, "Balance (Closed)       : " + __TRGSTM_Money(equity));
   __TRGSTM_WriteLine(handle, "Highest Balance Seen   : " + __TRGSTM_Money(highest_balance));
   __TRGSTM_WriteLine(handle, "Lowest Balance Seen    : " + __TRGSTM_Money(lowest_balance));
   __TRGSTM_WriteLine(handle, "Open Floating P/L      : " + __TRGSTM_Money(total_open_float_money) + " | " + DoubleToString(total_open_float_r, 2) + "R");
   __TRGSTM_WriteLine(handle, "Equity + Floating      : " + __TRGSTM_Money(balance_plus_float));
   __TRGSTM_WriteLine(handle, "Ambiguous Losses       : " + IntegerToString(ambiguous_losses));
   __TRGSTM_WriteLine(handle, "Trigger-Bar Ambiguous  : " + IntegerToString(trigger_bar_ambiguous));
   __TRGSTM_WriteLine(handle, "Risk Pips Min/Avg/Max  : " + DoubleToString(min_risk_pips, 1) + " / " + DoubleToString(avg_risk_pips, 1) + " / " + DoubleToString(max_risk_pips, 1));
   __TRGSTM_WriteLine(handle, "Target Model           : 3R fixed from TriggerSLTP.mqh");
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "EXECUTED TRADE LIST");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");

   if(executed_trades <= 0)
   {
      __TRGSTM_WriteLine(handle, "No executable trades were taken under the single-trade, daily 4-loss cap, engine-level parent/local gate enforcement, and post-win fresh-local-signal re-entry rules.");
   }
   else
   {
      for(int i = 0; i < raw_valid_triggers; ++i)
      {
         if(!trades[i].taken)
            continue;

         string serial_tag = (trades[i].rec.dir == DIR_UP ? "U" : "D") + IntegerToString(trades[i].rec.serial);
         string result_tag = __TRGSTM_StatusName(trades[i].result_status);
         string r_tag      = DoubleToString(__TRGSTM_EffectiveR(trades[i]), 2) + "R";
         string money_tag  = __TRGSTM_Money(__TRGSTM_EffectiveMoneyByRisk(trades[i], risk_money));

         string line = "#" + IntegerToString(trades[i].exec_index)
                     + " | Raw#=" + IntegerToString(trades[i].raw_index)
                     + " | Serial=" + serial_tag
                     + " | Dir=" + __TRGSTM_DirName(trades[i].rec.dir)
                     + " | Type=" + IntegerToString(trades[i].rec.type_id)
                     + " | EntryTime=" + __TRGSTM_SafeTime(trades[i].rec.hit_time)
                     + " | Entry=" + DoubleToString(trades[i].rec.breakout_level, digits)
                     + " | SL=" + DoubleToString(trades[i].rec.sl_level, digits)
                     + " | TP=" + DoubleToString(trades[i].rec.tp_level, digits)
                     + " | Risk=" + DoubleToString(trades[i].rec.risk_pips, 1) + " pip"
                     + " | Result=" + result_tag
                     + " | ExitTime=" + __TRGSTM_SafeTime(trades[i].exit_time)
                     + " | Exit/Mark=" + DoubleToString(trades[i].exit_price, digits)
                     + " | R=" + r_tag
                     + " | P/L=" + money_tag
                     + " | Equity=" + __TRGSTM_Money(trades[i].equity_after)
                     + " | Streak=" + __TRGSTM_StreakText(trades[i].streak_after)
                     + " | BarsHeld=" + IntegerToString(trades[i].bars_held);

         if(trades[i].unlock_on_time > 0)
            line += " | UnlockOn=" + __TRGSTM_SafeTime(trades[i].unlock_on_time);

         line += " | Note=" + trades[i].note;
         __TRGSTM_WriteLine(handle, line);
      }
   }

   __TRGSTM_WriteLine(handle, "");
   __TRGSTM_WriteLine(handle, "IGNORED VALID TRIGGERS");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");

   if(ignored_valid_triggers <= 0)
   {
      __TRGSTM_WriteLine(handle, "No valid triggers were ignored by the execution model.");
   }
   else
   {
      for(int i = 0; i < raw_valid_triggers; ++i)
      {
         if(trades[i].taken)
            continue;

         string serial_tag = (trades[i].rec.dir == DIR_UP ? "U" : "D") + IntegerToString(trades[i].rec.serial);
         string hypo_result = __TRGSTM_StatusName(trades[i].result_status);
         string hypo_r      = DoubleToString(__TRGSTM_EffectiveR(trades[i]), 2) + "R";
         string hypo_money  = __TRGSTM_Money(__TRGSTM_EffectiveMoneyByRisk(trades[i], risk_money));

         string line = "Raw#=" + IntegerToString(trades[i].raw_index)
                     + " | Serial=" + serial_tag
                     + " | Dir=" + __TRGSTM_DirName(trades[i].rec.dir)
                     + " | Type=" + IntegerToString(trades[i].rec.type_id)
                     + " | EntryTime=" + __TRGSTM_SafeTime(trades[i].rec.hit_time)
                     + " | Entry=" + DoubleToString(trades[i].rec.breakout_level, digits)
                     + " | SkipReason=" + __TRGSTM_SkipReasonName(trades[i].skip_reason)
                     + " | WouldHave=" + hypo_result
                     + " | WouldHaveR=" + hypo_r
                     + " | WouldHaveP/L=" + hypo_money
                     + " | Exit/Mark=" + DoubleToString(trades[i].exit_price, digits)
                     + " | Note=" + trades[i].note;

         __TRGSTM_WriteLine(handle, line);
      }
   }

   __TRGSTM_WriteLine(handle, "");
   __TRGSTM_WriteLine(handle, "USAGE NOTES");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   __TRGSTM_WriteLine(handle, "1) This statement first collects all valid TriggerSLTP triggers inside the scan window, then applies the execution model.");
   __TRGSTM_WriteLine(handle, "2) Only one trade can be active at a time; all later valid triggers are ignored until that trade reaches WIN, LOSS, or remains OPEN at scan end.");
   __TRGSTM_WriteLine(handle, "3) The executed-loss protection counter is calendar-day based; it resets automatically when a new trading day starts.");
   __TRGSTM_WriteLine(handle, "4) After 4 executed losses inside the same calendar day, new entries are blocked until the next calendar day begins.");
   __TRGSTM_WriteLine(handle, "5) Trigger.mqh already enforces the active parent " + __TRGSTM_ParentLabel() + " -> " + __TRGSTM_WorkerLabel() + " bridge window together with the active local " + __TRGSTM_WorkerLabel() + " signal-on window before TriggerSLTP records are created.");
   __TRGSTM_WriteLine(handle, "6) The reported " + __TRGSTM_WorkerLabel() + " major/minor trend windows are context statistics only; they no longer block execution by themselves.");
   __TRGSTM_WriteLine(handle, "7) After every executed WIN, the strategy waits for a fresh local " + __TRGSTM_WorkerLabel() + " signal-on event after that win before any new trigger can become a trade again.");
   __TRGSTM_WriteLine(handle, "8) Skipped valid triggers are listed separately together with their hypothetical outcome so you can inspect missed opportunities.");
   __TRGSTM_WriteLine(handle, "9) Risk per executed trade is fixed on initial capital, not compounded trade-by-trade.");
   __TRGSTM_WriteLine(handle, "10) Ambiguous same-bar outcomes are counted conservatively as SL to avoid optimistic bias.");

   FileFlush(handle);
   FileClose(handle);

   if(InpDebugPrints)
   {
      Print("[TRG-STATEMENT] Written | path=", g_trgstmt_last_fullpath,
            " | raw_valid=", raw_valid_triggers,
            " | executed=", executed_trades,
            " | ignored=", ignored_valid_triggers,
            " | daily_cap_skips=", skipped_daily_loss_cap,
            " | postwin_skips=", skipped_post_win_wait,
            " | major_windows=", major_window_count,
            " | minor_windows=", minor_window_count,
            " | closed=", closed_trades,
            " | open=", open_trades,
            " | net=", __TRGSTM_Money(net_profit),
            " | daily_caps=", daily_loss_cap_activations);
   }

   return true;
}


#endif // WAVEBOT_TRIGGER_STATEMENT_MQH
