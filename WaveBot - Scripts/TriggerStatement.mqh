#ifndef WAVEBOT_TRIGGER_STATEMENT_MQH
#define WAVEBOT_TRIGGER_STATEMENT_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/TriggerSLTP.mqh>

#define TRGSTMT_RESULT_OPEN 0
#define TRGSTMT_RESULT_WIN  1
#define TRGSTMT_RESULT_LOSS 2

struct TriggerStatementTrade
{
   bool              valid;
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

static string   g_trgstmt_last_filename = "";
static string   g_trgstmt_last_fullpath = "";
static bool     g_trgstmt_last_write_ok = false;
static datetime g_trgstmt_last_scan_from = 0;
static datetime g_trgstmt_last_scan_to   = 0;
static int      g_trgstmt_last_records   = 0;

inline void __TRGSTM_ClearTrade(TriggerStatementTrade &stmt_trade)
{
   stmt_trade.valid                 = false;
   __TRGSL_ClearRecord(stmt_trade.rec);
   stmt_trade.result_status         = TRGSTMT_RESULT_OPEN;
   stmt_trade.ambiguous             = false;
   stmt_trade.trigger_bar_ambiguous = false;
   stmt_trade.exit_time             = 0;
   stmt_trade.exit_price            = 0.0;
   stmt_trade.result_r              = 0.0;
   stmt_trade.pnl_money             = 0.0;
   stmt_trade.floating_r            = 0.0;
   stmt_trade.floating_money        = 0.0;
   stmt_trade.equity_after          = 0.0;
   stmt_trade.streak_after          = 0;
   stmt_trade.bars_held             = 0;
   stmt_trade.note                  = "";
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
   int filtered_count = __TRGSTM_CollectRecords(use_sym, scan_from, scan_to, records);

   int tfsec = PeriodSeconds(tf);
   if(tfsec <= 0)
      tfsec = 60;

   datetime load_from = scan_from;
   if(filtered_count > 0)
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
   if(filtered_count > 0)
      have_rates = __TRGSTM_LoadRates(use_sym, tf, load_from, use_scan_to, rates);

   TriggerStatementTrade trades[];
   ArrayResize(trades, filtered_count);
   for(int i = 0; i < filtered_count; ++i)
   {
      __TRGSTM_ClearTrade(trades[i]);
      if(have_rates)
         __TRGSTM_EvaluateTrade(records[i], rates, ArraySize(rates), use_scan_to, trades[i]);
      else
      {
         trades[i].valid = true;
         trades[i].rec   = records[i];
         trades[i].note  = "NO_RATE_DATA";
      }
   }

   double risk_money = initial_capital * (risk_percent / 100.0);

   double equity             = initial_capital;
   double peak_balance       = initial_capital;
   double max_drawdown_money = 0.0;
   double max_drawdown_pct   = 0.0;

   int    closed_trades = 0;
   int    wins          = 0;
   int    losses        = 0;
   int    open_trades   = 0;
   int    ambiguous_losses = 0;
   int    trigger_bar_ambiguous = 0;

   int    buy_total  = 0;
   int    sell_total = 0;
   int    buy_wins   = 0;
   int    sell_wins  = 0;
   int    buy_losses = 0;
   int    sell_losses= 0;

   int    current_win_streak  = 0;
   int    current_loss_streak = 0;
   int    max_win_streak      = 0;
   int    max_loss_streak     = 0;

   double gross_profit = 0.0;
   double gross_loss   = 0.0;
   double net_profit   = 0.0;
   double total_r      = 0.0;

   double sum_win_money = 0.0;
   double sum_loss_money = 0.0;
   double sum_win_r = 0.0;
   double sum_loss_r = 0.0;

   double best_trade_money = -DBL_MAX;
   double worst_trade_money = DBL_MAX;
   double best_trade_r = -DBL_MAX;
   double worst_trade_r = DBL_MAX;
   int    best_trade_index = -1;
   int    worst_trade_index = -1;

   double min_risk_pips = DBL_MAX;
   double max_risk_pips = 0.0;
   double sum_risk_pips = 0.0;

   double total_open_float_money = 0.0;
   double total_open_float_r = 0.0;

   for(int i = 0; i < filtered_count; ++i)
   {
      if(trades[i].rec.dir == DIR_UP)
         ++buy_total;
      else
         ++sell_total;

      if(trades[i].rec.risk_pips < min_risk_pips)
         min_risk_pips = trades[i].rec.risk_pips;
      if(trades[i].rec.risk_pips > max_risk_pips)
         max_risk_pips = trades[i].rec.risk_pips;
      sum_risk_pips += trades[i].rec.risk_pips;

      if(trades[i].result_status == TRGSTMT_RESULT_WIN || trades[i].result_status == TRGSTMT_RESULT_LOSS)
      {
         ++closed_trades;
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
            ++wins;
            gross_profit += trades[i].pnl_money;
            sum_win_money += trades[i].pnl_money;
            sum_win_r     += trades[i].result_r;
            current_win_streak++;
            current_loss_streak = 0;
            if(current_win_streak > max_win_streak)
               max_win_streak = current_win_streak;
            trades[i].streak_after = current_win_streak;

            if(trades[i].rec.dir == DIR_UP)
               ++buy_wins;
            else
               ++sell_wins;
         }
         else
         {
            ++losses;
            gross_loss += MathAbs(trades[i].pnl_money);
            sum_loss_money += MathAbs(trades[i].pnl_money);
            sum_loss_r     += MathAbs(trades[i].result_r);
            current_loss_streak++;
            current_win_streak = 0;
            if(current_loss_streak > max_loss_streak)
               max_loss_streak = current_loss_streak;
            trades[i].streak_after = -current_loss_streak;

            if(trades[i].rec.dir == DIR_UP)
               ++buy_losses;
            else
               ++sell_losses;

            if(trades[i].ambiguous)
               ++ambiguous_losses;
            if(trades[i].trigger_bar_ambiguous)
               ++trigger_bar_ambiguous;
         }

         if(trades[i].pnl_money > best_trade_money)
         {
            best_trade_money = trades[i].pnl_money;
            best_trade_r     = trades[i].result_r;
            best_trade_index = i;
         }
         if(trades[i].pnl_money < worst_trade_money)
         {
            worst_trade_money = trades[i].pnl_money;
            worst_trade_r     = trades[i].result_r;
            worst_trade_index = i;
         }
      }
      else
      {
         ++open_trades;
         trades[i].floating_money = (trades[i].floating_r * risk_money);
         trades[i].equity_after   = equity;
         total_open_float_money += trades[i].floating_money;
         total_open_float_r     += trades[i].floating_r;
      }
   }

   if(filtered_count <= 0)
   {
      min_risk_pips = 0.0;
      max_risk_pips = 0.0;
   }
   else if(min_risk_pips == DBL_MAX)
   {
      min_risk_pips = 0.0;
   }

   double win_rate      = 0.0;
   double loss_rate     = 0.0;
   double profit_factor = 0.0;
   double avg_win_money = 0.0;
   double avg_loss_money= 0.0;
   double avg_win_r     = 0.0;
   double avg_loss_r    = 0.0;
   double expectancy_money = 0.0;
   double expectancy_r     = 0.0;
   double payoff_ratio     = 0.0;
   double recovery_factor  = 0.0;
   double avg_risk_pips    = 0.0;
   double return_pct       = 0.0;
   double balance_plus_float = (equity + total_open_float_money);

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
   if(filtered_count > 0)
      avg_risk_pips = (sum_risk_pips / (double)filtered_count);
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
      g_trgstmt_last_records   = filtered_count;

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
   g_trgstmt_last_records   = filtered_count;

   int digits = __TRGSL_DigitsOf(use_sym);

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
   __TRGSTM_WriteLine(handle, "Execution Model        : Entry at breakout level, TP/SL touch-based, same-bar ambiguity resolved conservatively in favor of SL");
   __TRGSTM_WriteLine(handle, "Output Path            : " + g_trgstmt_last_fullpath);
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "SUMMARY");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   __TRGSTM_WriteLine(handle, "Valid Triggers         : " + IntegerToString(filtered_count));
   __TRGSTM_WriteLine(handle, "Closed Trades          : " + IntegerToString(closed_trades));
   __TRGSTM_WriteLine(handle, "Open Trades            : " + IntegerToString(open_trades));
   __TRGSTM_WriteLine(handle, "Wins / Losses          : " + IntegerToString(wins) + " / " + IntegerToString(losses));
   __TRGSTM_WriteLine(handle, "Win Rate / Loss Rate   : " + __TRGSTM_Pct(win_rate) + " / " + __TRGSTM_Pct(loss_rate));
   __TRGSTM_WriteLine(handle, "Bull Trades W/L        : " + IntegerToString(buy_total) + " | " + IntegerToString(buy_wins) + " / " + IntegerToString(buy_losses));
   __TRGSTM_WriteLine(handle, "Bear Trades W/L        : " + IntegerToString(sell_total) + " | " + IntegerToString(sell_wins) + " / " + IntegerToString(sell_losses));
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
   __TRGSTM_WriteLine(handle, "Best Trade             : " + (best_trade_index >= 0 ? (__TRGSTM_Money(best_trade_money) + " | " + DoubleToString(best_trade_r, 2) + "R") : "n/a"));
   __TRGSTM_WriteLine(handle, "Worst Trade            : " + (worst_trade_index >= 0 ? (__TRGSTM_Money(worst_trade_money) + " | " + DoubleToString(worst_trade_r, 2) + "R") : "n/a"));
   __TRGSTM_WriteLine(handle, "Max Win Streak         : " + IntegerToString(max_win_streak));
   __TRGSTM_WriteLine(handle, "Max Loss Streak        : " + IntegerToString(max_loss_streak));
   __TRGSTM_WriteLine(handle, "Max Drawdown           : " + __TRGSTM_Money(max_drawdown_money) + " | " + __TRGSTM_Pct(max_drawdown_pct));
   __TRGSTM_WriteLine(handle, "Balance (Closed)       : " + __TRGSTM_Money(equity));
   __TRGSTM_WriteLine(handle, "Open Floating P/L      : " + __TRGSTM_Money(total_open_float_money) + " | " + DoubleToString(total_open_float_r, 2) + "R");
   __TRGSTM_WriteLine(handle, "Equity + Floating      : " + __TRGSTM_Money(balance_plus_float));
   __TRGSTM_WriteLine(handle, "Ambiguous Losses       : " + IntegerToString(ambiguous_losses));
   __TRGSTM_WriteLine(handle, "Trigger-Bar Ambiguous  : " + IntegerToString(trigger_bar_ambiguous));
   __TRGSTM_WriteLine(handle, "Risk Pips Min/Avg/Max  : " + DoubleToString(min_risk_pips, 1) + " / " + DoubleToString(avg_risk_pips, 1) + " / " + DoubleToString(max_risk_pips, 1));
   __TRGSTM_WriteLine(handle, "Target Model           : 3R fixed from TriggerSLTP.mqh");
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "TRADE LIST");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");

   if(filtered_count <= 0)
   {
      __TRGSTM_WriteLine(handle, "No valid TriggerSLTP trades were found inside the selected scan window.");
   }
   else
   {
      for(int i = 0; i < filtered_count; ++i)
      {
         TriggerStatementTrade stmt_trade = trades[i];
         string serial_tag = (stmt_trade.rec.dir == DIR_UP ? "U" : "D") + IntegerToString(stmt_trade.rec.serial);
         string result_tag = __TRGSTM_StatusName(stmt_trade.result_status);
         string r_tag = "0.00R";
         string money_tag = __TRGSTM_Money(0.0);

         if(stmt_trade.result_status == TRGSTMT_RESULT_OPEN)
         {
            r_tag = DoubleToString(stmt_trade.floating_r, 2) + "R";
            money_tag = __TRGSTM_Money(stmt_trade.floating_money);
         }
         else
         {
            r_tag = DoubleToString(stmt_trade.result_r, 2) + "R";
            money_tag = __TRGSTM_Money(stmt_trade.pnl_money);
         }

         string line = "#" + IntegerToString(i + 1)
                     + " | Serial=" + serial_tag
                     + " | Dir=" + __TRGSTM_DirName(stmt_trade.rec.dir)
                     + " | Type=" + IntegerToString(stmt_trade.rec.type_id)
                     + " | EntryTime=" + __TRGSTM_SafeTime(stmt_trade.rec.hit_time)
                     + " | Entry=" + DoubleToString(stmt_trade.rec.breakout_level, digits)
                     + " | SL=" + DoubleToString(stmt_trade.rec.sl_level, digits)
                     + " | TP=" + DoubleToString(stmt_trade.rec.tp_level, digits)
                     + " | Risk=" + DoubleToString(stmt_trade.rec.risk_pips, 1) + " pip"
                     + " | Result=" + result_tag
                     + " | ExitTime=" + __TRGSTM_SafeTime(stmt_trade.exit_time)
                     + " | Exit/Mark=" + DoubleToString(stmt_trade.exit_price, digits)
                     + " | R=" + r_tag
                     + " | P/L=" + money_tag
                     + " | Equity=" + __TRGSTM_Money(stmt_trade.equity_after)
                     + " | Streak=" + __TRGSTM_StreakText(stmt_trade.streak_after)
                     + " | BarsHeld=" + IntegerToString(stmt_trade.bars_held)
                     + " | Note=" + stmt_trade.note;

         __TRGSTM_WriteLine(handle, line);
      }
   }

   __TRGSTM_WriteLine(handle, "");
   __TRGSTM_WriteLine(handle, "USAGE NOTES");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   __TRGSTM_WriteLine(handle, "1) This statement only includes valid TriggerSLTP trades inside the selected scan window.");
   __TRGSTM_WriteLine(handle, "2) Risk per trade is fixed on initial capital, not compounded trade-by-trade.");
   __TRGSTM_WriteLine(handle, "3) Ambiguous same-bar outcomes are counted conservatively as SL to avoid optimistic bias.");
   __TRGSTM_WriteLine(handle, "4) OPEN trades remain unclosed at scan end and are shown separately with mark-to-market P/L.");

   FileFlush(handle);
   FileClose(handle);

   if(InpDebugPrints)
   {
      Print("[TRG-STATEMENT] Written | path=", g_trgstmt_last_fullpath,
            " | filtered_records=", filtered_count,
            " | closed=", closed_trades,
            " | open=", open_trades,
            " | net=", __TRGSTM_Money(net_profit));
   }

   return true;
}

#endif // WAVEBOT_TRIGGER_STATEMENT_MQH
