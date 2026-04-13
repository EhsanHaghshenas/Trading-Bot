#ifndef WAVEBOT_TRIGGER_STATEMENT_MQH
#define WAVEBOT_TRIGGER_STATEMENT_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Trigger.mqh>
#include <WaveBot/TriggerSLTP.mqh>

#define TRGSTMT_RESULT_OPEN 0
#define TRGSTMT_RESULT_WIN  1
#define TRGSTMT_RESULT_LOSS 2

#define TRGSTMT_SKIP_NONE         0
#define TRGSTMT_SKIP_ACTIVE_TRADE 1
#define TRGSTMT_SKIP_LOCKOUT      2

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
   if(skip_reason == TRGSTMT_SKIP_LOCKOUT)
      return "WAIT_NEW_4H_ON_AFTER_4_LOSSES";
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

   return ArraySize(out);
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

   TriggerStatementStartEvent start_events[];
   int start_count = __TRGSTM_CollectStartEvents(use_sym, use_scan_to, start_events);

   double equity             = initial_capital;
   double peak_balance       = initial_capital;
   double max_drawdown_money = 0.0;
   double max_drawdown_pct   = 0.0;

   int executed_trades         = 0;
   int ignored_valid_triggers  = 0;
   int skipped_active_trade    = 0;
   int skipped_lockout         = 0;
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

   int gate_loss_streak    = 0;
   int lockout_activations = 0;
   int lockout_releases    = 0;

   double gross_profit = 0.0;
   double gross_loss   = 0.0;
   double net_profit   = 0.0;
   double total_r      = 0.0;

   double sum_win_money  = 0.0;
   double sum_loss_money = 0.0;
   double sum_win_r      = 0.0;
   double sum_loss_r     = 0.0;

   double best_trade_money = -DBL_MAX;
   double worst_trade_money = DBL_MAX;
   double best_trade_r = -DBL_MAX;
   double worst_trade_r = DBL_MAX;
   int    best_trade_exec_index = -1;
   int    worst_trade_exec_index = -1;

   double min_risk_pips = DBL_MAX;
   double max_risk_pips = 0.0;
   double sum_risk_pips = 0.0;

   double total_open_float_money = 0.0;
   double total_open_float_r     = 0.0;

   bool     active_trade_open  = false;
   datetime active_trade_until = 0;

   bool     lockout_active    = false;
   datetime lockout_ref_time  = 0;
   int      next_start_index  = 0;

   for(int i = 0; i < raw_valid_triggers; ++i)
   {
      datetime unlock_on_time = __TRGSTM_AdvanceStartEvents(start_events,
                                                            start_count,
                                                            next_start_index,
                                                            trades[i].rec.hit_time,
                                                            lockout_active,
                                                            lockout_ref_time,
                                                            gate_loss_streak,
                                                            lockout_releases);

      trades[i].unlock_on_time = unlock_on_time;

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

      if(lockout_active)
      {
         __TRGSTM_SetSkip(trades[i],
                          TRGSTMT_SKIP_LOCKOUT,
                          equity,
                          __TRGSTM_AppendNote(trades[i].note, "SKIPPED_WAITING_NEW_4H_SIGNAL_ON_AFTER_4_LOSSES"));
         ignored_valid_triggers++;
         skipped_lockout++;
         __TRGSTM_BumpHypotheticalCounters(trades[i],
                                           skipped_hypo_wins,
                                           skipped_hypo_losses,
                                           skipped_hypo_open);
         continue;
      }

      trades[i].taken       = true;
      trades[i].exec_index  = (executed_trades + 1);
      trades[i].skip_reason = TRGSTMT_SKIP_NONE;
      executed_trades++;

      if(trades[i].unlock_on_time > 0)
         trades[i].note = __TRGSTM_AppendNote(trades[i].note, "UNLOCKED_BY_NEW_4H_SIGNAL_ON");

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

            gate_loss_streak = 0;
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

            gate_loss_streak++;
            if(gate_loss_streak >= TRGSTMT_LOCK_AFTER_LOSSES)
            {
               lockout_active    = true;
               lockout_ref_time  = (trades[i].exit_time > 0 ? trades[i].exit_time : trades[i].rec.hit_time);
               lockout_activations++;
               trades[i].note = __TRGSTM_AppendNote(trades[i].note, "LOCKOUT_ARMED_AFTER_4_CONSEC_LOSSES");
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

   if(lockout_active)
   {
      __TRGSTM_AdvanceStartEvents(start_events,
                                  start_count,
                                  next_start_index,
                                  use_scan_to,
                                  lockout_active,
                                  lockout_ref_time,
                                  gate_loss_streak,
                                  lockout_releases);
   }

   bool lockout_active_at_end = lockout_active;

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
   __TRGSTM_WriteLine(handle, "Execution Model        : Single active trade only | entry at breakout level | touch-based TP/SL | conservative same-bar ambiguity = SL");
   __TRGSTM_WriteLine(handle, "Protection Rule        : After 4 consecutive executed losses, trading is locked until a new 4H signal on arrives");
   __TRGSTM_WriteLine(handle, "Bridge Source          : Trigger.mqh / WB15 bridge start events");
   __TRGSTM_WriteLine(handle, "Output Path            : " + g_trgstmt_last_fullpath);
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "SUMMARY");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   __TRGSTM_WriteLine(handle, "Raw Valid Triggers     : " + IntegerToString(raw_valid_triggers));
   __TRGSTM_WriteLine(handle, "Executed Trades        : " + IntegerToString(executed_trades));
   __TRGSTM_WriteLine(handle, "Execution Rate         : " + __TRGSTM_Pct(execution_rate));
   __TRGSTM_WriteLine(handle, "Ignored Valid Triggers : " + IntegerToString(ignored_valid_triggers) + " | " + __TRGSTM_Pct(ignored_rate));
   __TRGSTM_WriteLine(handle, "Ignored: Active Trade  : " + IntegerToString(skipped_active_trade));
   __TRGSTM_WriteLine(handle, "Ignored: 4L Lockout    : " + IntegerToString(skipped_lockout));
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
   __TRGSTM_WriteLine(handle, "4L Lock Threshold      : " + IntegerToString(TRGSTMT_LOCK_AFTER_LOSSES));
   __TRGSTM_WriteLine(handle, "Lockout Activations    : " + IntegerToString(lockout_activations));
   __TRGSTM_WriteLine(handle, "Lockout Releases       : " + IntegerToString(lockout_releases));
   __TRGSTM_WriteLine(handle, "Lockout Active At End  : " + (lockout_active_at_end ? "YES" : "NO"));
   __TRGSTM_WriteLine(handle, "Max Drawdown           : " + __TRGSTM_Money(max_drawdown_money) + " | " + __TRGSTM_Pct(max_drawdown_pct));
   __TRGSTM_WriteLine(handle, "Balance (Closed)       : " + __TRGSTM_Money(equity));
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
      __TRGSTM_WriteLine(handle, "No executable trades were taken under the single-trade and 4-loss-lock rules.");
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
   __TRGSTM_WriteLine(handle, "3) After 4 consecutive executed losses, new entries are blocked until a fresh 4H signal on is received from the H4->worker bridge.");
   __TRGSTM_WriteLine(handle, "4) Skipped valid triggers are listed separately together with their hypothetical outcome so you can inspect missed opportunities.");
   __TRGSTM_WriteLine(handle, "5) Risk per executed trade is fixed on initial capital, not compounded trade-by-trade.");
   __TRGSTM_WriteLine(handle, "6) Ambiguous same-bar outcomes are counted conservatively as SL to avoid optimistic bias.");

   FileFlush(handle);
   FileClose(handle);

   if(InpDebugPrints)
   {
      Print("[TRG-STATEMENT] Written | path=", g_trgstmt_last_fullpath,
            " | raw_valid=", raw_valid_triggers,
            " | executed=", executed_trades,
            " | ignored=", ignored_valid_triggers,
            " | closed=", closed_trades,
            " | open=", open_trades,
            " | net=", __TRGSTM_Money(net_profit),
            " | lockouts=", lockout_activations);
   }

   return true;
}


#endif // WAVEBOT_TRIGGER_STATEMENT_MQH
