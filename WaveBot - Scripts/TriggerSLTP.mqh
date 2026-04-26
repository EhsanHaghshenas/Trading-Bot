#ifndef WAVEBOT_TRIGGER_SLTP_MQH
#define WAVEBOT_TRIGGER_SLTP_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>

#define TRGSL_MAX_RISK_PIPS       25.0
#define TRGSL_R_MULTIPLE          3.0
#define TRGSL_FORWARD_BARS        4
#define TRGSL_MAX_LOSSES_PER_DAY  4

#define TRGSL_EXEC_RESULT_OPEN 0
#define TRGSL_EXEC_RESULT_WIN  1
#define TRGSL_EXEC_RESULT_LOSS 2

struct TriggerSLTPRecord
{
   bool      valid;
   Direction dir;
   int       type_id;
   int       serial;
   string    symbol;

   int       src_idx;
   datetime  src_time;
   double    breakout_level;

   int       hit_idx;
   datetime  hit_time;

   double    sl_level;
   double    tp_level;
   double    risk_price;
   double    risk_pips;
};

struct TriggerSLTPExecutionRecord
{
   bool              valid;
   bool              active;
   int               exec_index;
   int               local_gate_seq;
   datetime          local_gate_time;
   int               result_status;
   bool              ambiguous;
   bool              trigger_bar_ambiguous;
   datetime          exit_time;
   double            exit_price;
   double            result_r;
   int               bars_held;
   int               daily_losses_before;
   int               daily_losses_after;
   string            note;
   TriggerSLTPRecord rec;
};

struct TriggerSLTPFireEvent
{
   bool      valid;
   int       event_index;
   Direction dir;
   int       type_id;
   string    symbol;

   int       src_idx;
   datetime  src_time;
   double    breakout_level;

   int       hit_idx;
   datetime  hit_time;

   int       local_gate_seq;
   datetime  local_gate_time;

   bool      sltp_valid;
   int       valid_serial;
   double    sl_level;
   double    tp_level;
   double    risk_pips;

   bool      execution_allowed;
   bool      execution_opened;
   int       execution_index;
   string    decision_reason;
};

static TriggerSLTPRecord          g_trgsl_records[];
static TriggerSLTPExecutionRecord g_trgsl_exec_records[];
static TriggerSLTPFireEvent       g_trgsl_fire_events[];

static int      g_trgsl_up_serial               = 0;
static int      g_trgsl_dn_serial               = 0;
static int      g_trgsl_exec_counter            = 0;
static bool     g_trgsl_exec_active             = false;
static int      g_trgsl_exec_active_pos         = -1;
static datetime g_trgsl_exec_block_until        = 0;
static datetime g_trgsl_exec_last_sync_bar_time = 0;
static int      g_trgsl_exec_day_key            = 0;
static int      g_trgsl_exec_daily_losses       = 0;
static bool     g_trgsl_exec_post_win_wait      = false;
static int      g_trgsl_exec_post_win_gate_seq  = -1;
static datetime g_trgsl_exec_post_win_ref_time  = 0;
static int      g_trgsl_fire_counter            = 0;
static bool     g_trgsl_stmt_dirty              = false;
static int      g_trgsl_stmt_dirty_seq          = 0;
static int      g_trgsl_stmt_clear_seq          = 0;

inline void __TRGSL_ClearRecord(TriggerSLTPRecord &rec)
{
   rec.valid          = false;
   rec.dir            = DIR_UP;
   rec.type_id        = 0;
   rec.serial         = 0;
   rec.symbol         = "";
   rec.src_idx        = -1;
   rec.src_time       = 0;
   rec.breakout_level = 0.0;
   rec.hit_idx        = -1;
   rec.hit_time       = 0;
   rec.sl_level       = 0.0;
   rec.tp_level       = 0.0;
   rec.risk_price     = 0.0;
   rec.risk_pips      = 0.0;
}

inline void __TRGSL_ClearExecRecord(TriggerSLTPExecutionRecord &rec)
{
   rec.valid                 = false;
   rec.active                = false;
   rec.exec_index            = 0;
   rec.local_gate_seq        = -1;
   rec.local_gate_time       = 0;
   rec.result_status         = TRGSL_EXEC_RESULT_OPEN;
   rec.ambiguous             = false;
   rec.trigger_bar_ambiguous = false;
   rec.exit_time             = 0;
   rec.exit_price            = 0.0;
   rec.result_r              = 0.0;
   rec.bars_held             = 0;
   rec.daily_losses_before   = 0;
   rec.daily_losses_after    = 0;
   rec.note                  = "";
   __TRGSL_ClearRecord(rec.rec);
}

inline void __TRGSL_ClearFireEvent(TriggerSLTPFireEvent &evt)
{
   evt.valid              = false;
   evt.event_index        = 0;
   evt.dir                = DIR_UP;
   evt.type_id            = 0;
   evt.symbol             = "";
   evt.src_idx            = -1;
   evt.src_time           = 0;
   evt.breakout_level     = 0.0;
   evt.hit_idx            = -1;
   evt.hit_time           = 0;
   evt.local_gate_seq     = -1;
   evt.local_gate_time    = 0;
   evt.sltp_valid         = false;
   evt.valid_serial       = 0;
   evt.sl_level           = 0.0;
   evt.tp_level           = 0.0;
   evt.risk_pips          = 0.0;
   evt.execution_allowed  = false;
   evt.execution_opened   = false;
   evt.execution_index    = -1;
   evt.decision_reason    = "";
}

inline int TriggerSLTP_RecordCount()
{
   return ArraySize(g_trgsl_records);
}

inline bool TriggerSLTP_RecordGet(const int index, TriggerSLTPRecord &out)
{
   if(index < 0 || index >= ArraySize(g_trgsl_records))
      return false;

   out = g_trgsl_records[index];
   return true;
}

inline int TriggerSLTP_ExecutedCount()
{
   return ArraySize(g_trgsl_exec_records);
}

inline bool TriggerSLTP_ExecutedGet(const int index, TriggerSLTPExecutionRecord &out)
{
   if(index < 0 || index >= ArraySize(g_trgsl_exec_records))
      return false;

   out = g_trgsl_exec_records[index];
   return true;
}

inline bool TriggerSLTP_HasActiveExecutedTrade()
{
   return g_trgsl_exec_active;
}

inline int TriggerSLTP_DailyLossCount()
{
   return g_trgsl_exec_daily_losses;
}

inline int TriggerSLTP_FireEventCount()
{
   return ArraySize(g_trgsl_fire_events);
}

inline bool TriggerSLTP_FireEventGet(const int index, TriggerSLTPFireEvent &out)
{
   if(index < 0 || index >= ArraySize(g_trgsl_fire_events))
      return false;

   out = g_trgsl_fire_events[index];
   return true;
}

inline int TriggerSLTP_StatementDirtySeq()
{
   return g_trgsl_stmt_dirty_seq;
}

inline bool TriggerSLTP_IsStatementDirty()
{
   return (g_trgsl_stmt_dirty || g_trgsl_stmt_dirty_seq != g_trgsl_stmt_clear_seq);
}

inline void TriggerSLTP_ClearStatementDirty()
{
   g_trgsl_stmt_dirty = false;
   g_trgsl_stmt_clear_seq = g_trgsl_stmt_dirty_seq;
}

inline void TriggerSLTP_MarkStatementDirty()
{
   g_trgsl_stmt_dirty = true;
   ++g_trgsl_stmt_dirty_seq;
}

inline double __TRGSL_PointOf(const string sym)
{
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(pt <= 0.0)
      pt = _Point;
   return pt;
}

inline int __TRGSL_DigitsOf(const string sym)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits <= 0)
      digits = _Digits;
   return digits;
}

inline double __TRGSL_PipSize(const string sym)
{
   double pt = __TRGSL_PointOf(sym);
   int digits = __TRGSL_DigitsOf(sym);

   if(digits == 3 || digits == 5)
      return (pt * 10.0);

   return pt;
}

inline double __TRGSL_ToPips(const string sym, const double price_distance)
{
   double pip = __TRGSL_PipSize(sym);
   if(pip <= 0.0)
      return 0.0;

   return (price_distance / pip);
}

inline datetime __TRGSL_ForwardEndTime(const datetime start_t)
{
   if(start_t <= 0)
      return 0;

   int tfsec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(tfsec <= 0)
      tfsec = 60;

   return (start_t + (datetime)(tfsec * TRGSL_FORWARD_BARS));
}

inline void __TRGSL_DrawSegment(const string   base,
                                datetime       t1,
                                datetime       t2,
                                const double   level,
                                const color    col)
{
   if(!Markers_ShouldRender())
      return;
   if(t1 <= 0 || t2 <= 0)
      return;

   if(t2 < t1)
   {
      datetime tmp = t1;
      t1 = t2;
      t2 = tmp;
   }

   if(t2 == t1)
      t2 = (t1 + 1);

   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, level, t2, level))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

inline void __TRGSL_StoreRecord(const TriggerSLTPRecord &rec)
{
   int pos = ArraySize(g_trgsl_records);
   ArrayResize(g_trgsl_records, pos + 1);
   g_trgsl_records[pos] = rec;
   TriggerSLTP_MarkStatementDirty();
}

inline int __TRGSL_AppendFireEvent(const string    sym,
                                   const Direction dir,
                                   const int       type_id,
                                   const int       src_idx,
                                   const double    level,
                                   const int       hit_idx,
                                   const MqlRates &rates[],
                                   const int       n,
                                   const int       local_gate_seq,
                                   const datetime  local_gate_time)
{
   TriggerSLTPFireEvent evt;
   __TRGSL_ClearFireEvent(evt);

   ++g_trgsl_fire_counter;
   evt.valid           = true;
   evt.event_index     = g_trgsl_fire_counter;
   evt.dir             = dir;
   evt.type_id         = type_id;
   evt.symbol          = sym;
   evt.src_idx         = src_idx;
   evt.breakout_level  = level;
   evt.hit_idx         = hit_idx;
   evt.local_gate_seq  = local_gate_seq;
   evt.local_gate_time = local_gate_time;
   evt.decision_reason = "FIRED_WAITING_SLTP_VALIDATION";

   if(src_idx >= 0 && src_idx < n)
      evt.src_time = rates[src_idx].time;
   if(hit_idx >= 0 && hit_idx < n)
      evt.hit_time = rates[hit_idx].time;

   int pos = ArraySize(g_trgsl_fire_events);
   ArrayResize(g_trgsl_fire_events, pos + 1);
   g_trgsl_fire_events[pos] = evt;

   TriggerSLTP_MarkStatementDirty();
   return pos;
}

inline void __TRGSL_UpdateFireEventInvalid(const int pos,
                                           const string reason)
{
   if(pos < 0 || pos >= ArraySize(g_trgsl_fire_events))
      return;

   g_trgsl_fire_events[pos].sltp_valid        = false;
   g_trgsl_fire_events[pos].valid_serial      = 0;
   g_trgsl_fire_events[pos].execution_allowed = false;
   g_trgsl_fire_events[pos].execution_opened  = false;
   g_trgsl_fire_events[pos].execution_index   = -1;
   g_trgsl_fire_events[pos].decision_reason   = reason;
   TriggerSLTP_MarkStatementDirty();
}

inline void __TRGSL_UpdateFireEventValid(const int               pos,
                                         const TriggerSLTPRecord &rec,
                                         const bool              execution_allowed,
                                         const bool              execution_opened,
                                         const int               execution_index,
                                         const string            reason)
{
   if(pos < 0 || pos >= ArraySize(g_trgsl_fire_events))
      return;

   g_trgsl_fire_events[pos].sltp_valid        = true;
   g_trgsl_fire_events[pos].valid_serial      = rec.serial;
   g_trgsl_fire_events[pos].sl_level          = rec.sl_level;
   g_trgsl_fire_events[pos].tp_level          = rec.tp_level;
   g_trgsl_fire_events[pos].risk_pips         = rec.risk_pips;
   g_trgsl_fire_events[pos].execution_allowed = execution_allowed;
   g_trgsl_fire_events[pos].execution_opened  = execution_opened;
   g_trgsl_fire_events[pos].execution_index   = execution_index;
   g_trgsl_fire_events[pos].decision_reason   = reason;
   TriggerSLTP_MarkStatementDirty();
}

inline int __TRGSL_DayKey(const datetime t)
{
   if(t <= 0)
      return 0;

   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (dt.year * 10000 + dt.mon * 100 + dt.day);
}

inline void __TRGSL_EnsureDailyBucket(const datetime t)
{
   if(t <= 0)
      return;

   int day_key = __TRGSL_DayKey(t);
   if(day_key <= 0)
      return;

   if(g_trgsl_exec_day_key != day_key)
   {
      g_trgsl_exec_day_key      = day_key;
      g_trgsl_exec_daily_losses = 0;
   }
}

inline string __TRGSL_AppendNote(const string left_text,
                                 const string right_text)
{
   if(right_text == "")
      return left_text;
   if(left_text == "")
      return right_text;
   return (left_text + "|" + right_text);
}

inline double __TRGSL_WinR(const TriggerSLTPRecord &rec)
{
   if(rec.risk_price <= 0.0)
      return 0.0;

   if(rec.dir == DIR_UP)
      return ((rec.tp_level - rec.breakout_level) / rec.risk_price);

   return ((rec.breakout_level - rec.tp_level) / rec.risk_price);
}

inline bool __TRGSL_BuildBull(const string    sym,
                              const int       type_id,
                              const int       src_idx,
                              const double    level,
                              const int       hit_idx,
                              const MqlRates &rates[],
                              const int       n,
                              TriggerSLTPRecord &out)
{
   if(n <= 0)
      return false;
   if(src_idx < 0 || src_idx >= n)
      return false;
   if(hit_idx < 0 || hit_idx >= n)
      return false;

   int from = src_idx;
   int to   = hit_idx;
   if(from > to)
   {
      int tmp = from;
      from = to;
      to   = tmp;
   }

   double sl = rates[from].low;
   for(int i = from + 1; i <= to; ++i)
   {
      if(rates[i].low < sl)
         sl = rates[i].low;
   }

   double risk = (level - sl);
   if(risk <= 0.0)
      return false;

   double risk_pips = __TRGSL_ToPips(sym, risk);
   if(risk_pips > TRGSL_MAX_RISK_PIPS)
      return false;

   __TRGSL_ClearRecord(out);
   out.valid          = true;
   out.dir            = DIR_UP;
   out.type_id        = type_id;
   out.symbol         = sym;
   out.src_idx        = src_idx;
   out.src_time       = rates[src_idx].time;
   out.breakout_level = level;
   out.hit_idx        = hit_idx;
   out.hit_time       = rates[hit_idx].time;
   out.sl_level       = sl;
   out.tp_level       = (level + (risk * TRGSL_R_MULTIPLE));
   out.risk_price     = risk;
   out.risk_pips      = risk_pips;
   return true;
}

inline bool __TRGSL_BuildBear(const string    sym,
                              const int       type_id,
                              const int       src_idx,
                              const double    level,
                              const int       hit_idx,
                              const MqlRates &rates[],
                              const int       n,
                              TriggerSLTPRecord &out)
{
   if(n <= 0)
      return false;
   if(src_idx < 0 || src_idx >= n)
      return false;
   if(hit_idx < 0 || hit_idx >= n)
      return false;

   int from = src_idx;
   int to   = hit_idx;
   if(from > to)
   {
      int tmp = from;
      from = to;
      to   = tmp;
   }

   double sl = rates[from].high;
   for(int i = from + 1; i <= to; ++i)
   {
      if(rates[i].high > sl)
         sl = rates[i].high;
   }

   double risk = (sl - level);
   if(risk <= 0.0)
      return false;

   double risk_pips = __TRGSL_ToPips(sym, risk);
   if(risk_pips > TRGSL_MAX_RISK_PIPS)
      return false;

   __TRGSL_ClearRecord(out);
   out.valid          = true;
   out.dir            = DIR_DOWN;
   out.type_id        = type_id;
   out.symbol         = sym;
   out.src_idx        = src_idx;
   out.src_time       = rates[src_idx].time;
   out.breakout_level = level;
   out.hit_idx        = hit_idx;
   out.hit_time       = rates[hit_idx].time;
   out.sl_level       = sl;
   out.tp_level       = (level - (risk * TRGSL_R_MULTIPLE));
   out.risk_price     = risk;
   out.risk_pips      = risk_pips;
   return true;
}

inline int __TRGSL_AppendExecutionRecord(const TriggerSLTPRecord &rec,
                                         const int               local_gate_seq,
                                         const datetime          local_gate_time)
{
   TriggerSLTPExecutionRecord exec_rec;
   __TRGSL_ClearExecRecord(exec_rec);

   exec_rec.valid               = true;
   exec_rec.active              = true;
   exec_rec.exec_index          = (g_trgsl_exec_counter + 1);
   exec_rec.local_gate_seq      = local_gate_seq;
   exec_rec.local_gate_time     = local_gate_time;
   exec_rec.result_status       = TRGSL_EXEC_RESULT_OPEN;
   exec_rec.daily_losses_before = g_trgsl_exec_daily_losses;
   exec_rec.daily_losses_after  = g_trgsl_exec_daily_losses;
   exec_rec.bars_held           = 1;
   exec_rec.rec                 = rec;

   int pos = ArraySize(g_trgsl_exec_records);
   ArrayResize(g_trgsl_exec_records, pos + 1);
   g_trgsl_exec_records[pos] = exec_rec;

   g_trgsl_exec_counter     = exec_rec.exec_index;
   g_trgsl_exec_active      = true;
   g_trgsl_exec_active_pos  = pos;
   g_trgsl_exec_block_until = 0;
   TriggerSLTP_MarkStatementDirty();

   return pos;
}

inline void __TRGSL_CloseExecutionRecord(const int      pos,
                                         const datetime exit_time,
                                         const double   exit_price,
                                         const int      result_status,
                                         const bool     ambiguous,
                                         const bool     trigger_bar_ambiguous,
                                         const double   result_r,
                                         const int      bars_held,
                                         const string   note)
{
   if(pos < 0 || pos >= ArraySize(g_trgsl_exec_records))
      return;

   TriggerSLTPExecutionRecord rec = g_trgsl_exec_records[pos];
   if(!rec.valid)
      return;

   g_trgsl_exec_records[pos].active                = false;
   g_trgsl_exec_records[pos].result_status         = result_status;
   g_trgsl_exec_records[pos].ambiguous             = ambiguous;
   g_trgsl_exec_records[pos].trigger_bar_ambiguous = trigger_bar_ambiguous;
   g_trgsl_exec_records[pos].exit_time             = exit_time;
   g_trgsl_exec_records[pos].exit_price            = exit_price;
   g_trgsl_exec_records[pos].result_r              = result_r;
   g_trgsl_exec_records[pos].bars_held             = bars_held;
   g_trgsl_exec_records[pos].note                  = __TRGSL_AppendNote(g_trgsl_exec_records[pos].note, note);

   if(result_status == TRGSL_EXEC_RESULT_LOSS)
   {
      __TRGSL_EnsureDailyBucket(exit_time);
      g_trgsl_exec_daily_losses++;
      g_trgsl_exec_records[pos].daily_losses_after = g_trgsl_exec_daily_losses;
   }
   else
   {
      g_trgsl_exec_records[pos].daily_losses_after = g_trgsl_exec_daily_losses;
   }

   if(result_status == TRGSL_EXEC_RESULT_WIN)
   {
      g_trgsl_exec_post_win_wait     = true;
      g_trgsl_exec_post_win_gate_seq = rec.local_gate_seq;
      g_trgsl_exec_post_win_ref_time = exit_time;
   }

   g_trgsl_exec_active      = false;
   g_trgsl_exec_active_pos  = -1;
   g_trgsl_exec_block_until = exit_time;
   TriggerSLTP_MarkStatementDirty();
}

inline bool __TRGSL_AllowFreshLocalAfterWin(const int      local_gate_seq,
                                            const datetime local_gate_time)
{
   if(!g_trgsl_exec_post_win_wait)
      return true;

   if(local_gate_seq <= 0 || local_gate_time <= 0)
      return false;

   if(local_gate_seq == g_trgsl_exec_post_win_gate_seq)
      return false;

   if(local_gate_time <= g_trgsl_exec_post_win_ref_time)
      return false;

   g_trgsl_exec_post_win_wait     = false;
   g_trgsl_exec_post_win_gate_seq = local_gate_seq;
   g_trgsl_exec_post_win_ref_time = 0;
   return true;
}

inline bool __TRGSL_CanOpenExecution(const datetime hit_time,
                                     const int      local_gate_seq,
                                     const datetime local_gate_time,
                                     string        &reason)
{
   reason = "";

   __TRGSL_EnsureDailyBucket(hit_time);

   if(g_trgsl_exec_active)
   {
      reason = "ACTIVE_TRADE_ALREADY_OPEN";
      return false;
   }

   if(g_trgsl_exec_block_until > 0 && hit_time <= g_trgsl_exec_block_until)
   {
      reason = "ACTIVE_TRADE_ALREADY_OPEN";
      return false;
   }

   if(g_trgsl_exec_daily_losses >= TRGSL_MAX_LOSSES_PER_DAY)
   {
      reason = "DAILY_4L_CAP_REACHED";
      return false;
   }

   if(!__TRGSL_AllowFreshLocalAfterWin(local_gate_seq, local_gate_time))
   {
      reason = "WAIT_FRESH_LOCAL_SIGNAL_AFTER_WIN";
      return false;
   }

   return true;
}

inline void __TRGSL_EvaluateEntryBar(const int       pos,
                                     const MqlRates &bar)
{
   if(pos < 0 || pos >= ArraySize(g_trgsl_exec_records))
      return;

   TriggerSLTPExecutionRecord rec = g_trgsl_exec_records[pos];
   if(!rec.valid || !rec.active)
      return;

   bool hit_tp = false;
   bool hit_sl = false;

   if(rec.rec.dir == DIR_UP)
   {
      hit_tp = (bar.high >= rec.rec.tp_level);
      hit_sl = (bar.low  <= rec.rec.sl_level);
   }
   else
   {
      hit_tp = (bar.low  <= rec.rec.tp_level);
      hit_sl = (bar.high >= rec.rec.sl_level);
   }

   if(hit_tp && hit_sl)
   {
      __TRGSL_CloseExecutionRecord(pos,
                                   bar.time,
                                   rec.rec.sl_level,
                                   TRGSL_EXEC_RESULT_LOSS,
                                   true,
                                   true,
                                   -1.0,
                                   1,
                                   "AMBIGUOUS_TRIGGER_BAR_BOTH_HIT_ASSUMED_SL");
      return;
   }

   if(hit_tp)
   {
      __TRGSL_CloseExecutionRecord(pos,
                                   bar.time,
                                   rec.rec.tp_level,
                                   TRGSL_EXEC_RESULT_WIN,
                                   false,
                                   false,
                                   __TRGSL_WinR(rec.rec),
                                   1,
                                   "TP_ON_TRIGGER_BAR");
      return;
   }

   if(hit_sl)
   {
      __TRGSL_CloseExecutionRecord(pos,
                                   bar.time,
                                   rec.rec.sl_level,
                                   TRGSL_EXEC_RESULT_LOSS,
                                   true,
                                   true,
                                   -1.0,
                                   1,
                                   "AMBIGUOUS_TRIGGER_BAR_SL_ASSUMED_LOSS");
      return;
   }
}

inline void __TRGSL_EvaluateActiveTradeOnBar(const MqlRates &bar)
{
   if(!g_trgsl_exec_active)
      return;

   int pos = g_trgsl_exec_active_pos;
   if(pos < 0 || pos >= ArraySize(g_trgsl_exec_records))
      return;

   TriggerSLTPExecutionRecord rec = g_trgsl_exec_records[pos];
   if(!rec.valid || !rec.active)
      return;

   if(bar.time <= rec.rec.hit_time)
      return;

   bool hit_tp = false;
   bool hit_sl = false;

   if(rec.rec.dir == DIR_UP)
   {
      hit_tp = (bar.high >= rec.rec.tp_level);
      hit_sl = (bar.low  <= rec.rec.sl_level);
   }
   else
   {
      hit_tp = (bar.low  <= rec.rec.tp_level);
      hit_sl = (bar.high >= rec.rec.sl_level);
   }

   int bars_held = rec.bars_held + 1;

   if(hit_tp && hit_sl)
   {
      __TRGSL_CloseExecutionRecord(pos,
                                   bar.time,
                                   rec.rec.sl_level,
                                   TRGSL_EXEC_RESULT_LOSS,
                                   true,
                                   false,
                                   -1.0,
                                   bars_held,
                                   "AMBIGUOUS_SAME_BAR_BOTH_HIT_ASSUMED_SL");
      return;
   }

   if(hit_tp)
   {
      __TRGSL_CloseExecutionRecord(pos,
                                   bar.time,
                                   rec.rec.tp_level,
                                   TRGSL_EXEC_RESULT_WIN,
                                   false,
                                   false,
                                   __TRGSL_WinR(rec.rec),
                                   bars_held,
                                   "TP_HIT");
      return;
   }

   if(hit_sl)
   {
      __TRGSL_CloseExecutionRecord(pos,
                                   bar.time,
                                   rec.rec.sl_level,
                                   TRGSL_EXEC_RESULT_LOSS,
                                   false,
                                   false,
                                   -1.0,
                                   bars_held,
                                   "SL_HIT");
      return;
   }

   g_trgsl_exec_records[pos].bars_held = bars_held;
}

inline void TriggerSLTP_OnBarSync(const string    sym,
                                  const MqlRates &rates[],
                                  const int       n,
                                  const int       bar_idx)
{
   if(sym == "")
      return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return;

   const datetime bar_time = rates[bar_idx].time;
   if(bar_time <= 0)
      return;

   __TRGSL_EnsureDailyBucket(bar_time);

   if(g_trgsl_exec_last_sync_bar_time > 0 && bar_time <= g_trgsl_exec_last_sync_bar_time)
      return;

   g_trgsl_exec_last_sync_bar_time = bar_time;

   if(g_trgsl_exec_active)
   {
      __TRGSL_EvaluateActiveTradeOnBar(rates[bar_idx]);
      TriggerSLTP_MarkStatementDirty();
   }
}

inline void TriggerSLTP_ResetGlobals()
{
   ArrayResize(g_trgsl_records, 0);
   ArrayResize(g_trgsl_exec_records, 0);
   ArrayResize(g_trgsl_fire_events, 0);

   g_trgsl_up_serial               = 0;
   g_trgsl_dn_serial               = 0;
   g_trgsl_exec_counter            = 0;
   g_trgsl_exec_active             = false;
   g_trgsl_exec_active_pos         = -1;
   g_trgsl_exec_block_until        = 0;
   g_trgsl_exec_last_sync_bar_time = 0;
   g_trgsl_exec_day_key            = 0;
   g_trgsl_exec_daily_losses       = 0;
   g_trgsl_exec_post_win_wait      = false;
   g_trgsl_exec_post_win_gate_seq  = -1;
   g_trgsl_exec_post_win_ref_time  = 0;
   g_trgsl_fire_counter            = 0;
   g_trgsl_stmt_dirty              = false;
   g_trgsl_stmt_dirty_seq          = 0;
   g_trgsl_stmt_clear_seq          = 0;
}

inline void TriggerSLTP_OnTriggerFired(const string    sym,
                                       const Direction dir,
                                       const int       type_id,
                                       const int       src_idx,
                                       const double    level,
                                       const int       hit_idx,
                                       const MqlRates &rates[],
                                       const int       n,
                                       const int       local_gate_seq,
                                       const datetime  local_gate_time)
{
   string use_sym = sym;
   if(use_sym == "")
      use_sym = _Symbol;

   int fire_pos = __TRGSL_AppendFireEvent(use_sym,
                                          dir,
                                          type_id,
                                          src_idx,
                                          level,
                                          hit_idx,
                                          rates,
                                          n,
                                          local_gate_seq,
                                          local_gate_time);

   TriggerSLTPRecord rec;
   bool ok = false;

   if(dir == DIR_UP)
      ok = __TRGSL_BuildBull(use_sym, type_id, src_idx, level, hit_idx, rates, n, rec);
   else
      ok = __TRGSL_BuildBear(use_sym, type_id, src_idx, level, hit_idx, rates, n, rec);

   if(!ok)
   {
      __TRGSL_UpdateFireEventInvalid(fire_pos, "SLTP_REJECT_RISK_GT_25PIP_OR_BAD_RANGE");

      if(InpDebugPrints)
      {
         Print("[TRG-SLTP] Skip invalid ",
               (dir == DIR_UP ? "UP" : "DOWN"),
               " trigger | breakout=", DoubleToString(level, __TRGSL_DigitsOf(use_sym)),
               " | src_idx=", src_idx,
               " | hit_idx=", hit_idx,
               " | reason=risk>25pip_or_bad_range");
      }
      return;
   }

   if(dir == DIR_UP)
   {
      ++g_trgsl_up_serial;
      rec.serial = g_trgsl_up_serial;
   }
   else
   {
      ++g_trgsl_dn_serial;
      rec.serial = g_trgsl_dn_serial;
   }

   __TRGSL_StoreRecord(rec);

   const string dir_tag = (dir == DIR_UP ? "U" : "D");
   const string base = "TRG_SLTP_"
                     + dir_tag + "_"
                     + IntegerToString(rec.serial) + "_"
                     + IntegerToString((int)rec.hit_time);

   datetime end_t = __TRGSL_ForwardEndTime(rec.hit_time);
   __TRGSL_DrawSegment(base + "_SL", rec.hit_time, end_t, rec.sl_level, clrRed);
   __TRGSL_DrawSegment(base + "_TP", rec.hit_time, end_t, rec.tp_level, clrGreen);

   string exec_reason = "";
   bool   exec_allowed = false;
   bool   exec_opened  = false;
   int    exec_index   = -1;

   if(__TRGSL_CanOpenExecution(rec.hit_time, local_gate_seq, local_gate_time, exec_reason))
   {
      exec_allowed = true;
      int exec_pos = __TRGSL_AppendExecutionRecord(rec, local_gate_seq, local_gate_time);
      if(exec_pos >= 0 && exec_pos < ArraySize(g_trgsl_exec_records))
      {
         exec_opened = true;
         exec_index  = g_trgsl_exec_records[exec_pos].exec_index;
      }

      if(hit_idx >= 0 && hit_idx < n)
         __TRGSL_EvaluateEntryBar(exec_pos, rates[hit_idx]);

      exec_reason = "EXECUTION_OPENED";
   }
   else if(InpDebugPrints)
   {
      Print("[TRG-EXEC] Skip ",
            (dir == DIR_UP ? "UP" : "DOWN"),
            " #", rec.serial,
            " | reason=", exec_reason,
            " | hit=", TimeToString(rec.hit_time, TIME_DATE|TIME_SECONDS),
            " | local_seq=", local_gate_seq);
   }

   __TRGSL_UpdateFireEventValid(fire_pos,
                                rec,
                                exec_allowed,
                                exec_opened,
                                exec_index,
                                (exec_reason == "" ? "EXECUTION_SKIPPED" : exec_reason));

   if(InpDebugPrints)
   {
      int digits = __TRGSL_DigitsOf(use_sym);
      Print("[TRG-SLTP] ",
            (dir == DIR_UP ? "UP" : "DOWN"),
            " #", rec.serial,
            " | breakout=", DoubleToString(rec.breakout_level, digits),
            " | SL=", DoubleToString(rec.sl_level, digits),
            " | TP=", DoubleToString(rec.tp_level, digits),
            " | risk_pips=", DoubleToString(rec.risk_pips, 1),
            " | src=", TimeToString(rec.src_time, TIME_DATE|TIME_SECONDS),
            " | hit=", TimeToString(rec.hit_time, TIME_DATE|TIME_SECONDS),
            " | local_seq=", local_gate_seq,
            " | daily_losses=", g_trgsl_exec_daily_losses,
            " | postwin_wait=", (g_trgsl_exec_post_win_wait ? "YES" : "NO"));
   }
}

#endif // WAVEBOT_TRIGGER_SLTP_MQH