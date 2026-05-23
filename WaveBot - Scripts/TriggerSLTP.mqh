#ifndef WAVEBOT_TRIGGER_SLTP_MQH
#define WAVEBOT_TRIGGER_SLTP_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WaveBotLogger.mqh>

#define TRGSL_MIN_RISK_PIPS WB_Config_MinSLPips()
#define TRGSL_MAX_RISK_PIPS WB_Config_MaxSLPips()
#define TRGSL_R_MULTIPLE    3.0
#define TRGSL_FORWARD_BARS  4

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

   // Diagnostic lineage IDs only. These fields do not affect SL/TP logic.
   int       log_context_id;
   int       log_zone_id;
   int       log_m1_window_id;
   int       log_start_kind;
   int       log_start_ns;
};

static TriggerSLTPRecord g_trgsl_records[];
static int g_trgsl_up_serial = 0;
static int g_trgsl_dn_serial = 0;

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
   rec.log_context_id   = 0;
   rec.log_zone_id      = 0;
   rec.log_m1_window_id = 0;
   rec.log_start_kind   = 0;
   rec.log_start_ns     = 0;
}

inline void TriggerSLTP_ResetGlobals()
{
   ArrayResize(g_trgsl_records, 0);
   g_trgsl_up_serial = 0;
   g_trgsl_dn_serial = 0;
}

inline int TriggerSLTP_RecordCount()
{
   return ArraySize(g_trgsl_records);
}

inline int TriggerSLTP_RemoveRecordsAtOrAfter(const datetime cutoff_time,
                                             const int      context_id,
                                             const int      zone_id,
                                             const int      m1_window_id)
{
   if(cutoff_time <= 0)
      return 0;

   int total = ArraySize(g_trgsl_records);
   if(total <= 0)
      return 0;

   int write_pos = 0;
   int removed   = 0;

   for(int i = 0; i < total; ++i)
   {
      TriggerSLTPRecord rec = g_trgsl_records[i];

      bool match = rec.valid && rec.hit_time >= cutoff_time;

      if(match && context_id > 0)
         match = (rec.log_context_id == context_id);
      if(match && zone_id > 0)
         match = (rec.log_zone_id == zone_id);
      if(match && m1_window_id > 0)
         match = (rec.log_m1_window_id == m1_window_id);

      if(match)
      {
         removed++;
         continue;
      }

      g_trgsl_records[write_pos] = rec;
      write_pos++;
   }

   if(removed > 0)
      ArrayResize(g_trgsl_records, write_pos);

   return removed;
}

inline bool TriggerSLTP_RecordGet(const int index, TriggerSLTPRecord &out)
{
   if(index < 0 || index >= ArraySize(g_trgsl_records))
      return false;

   out = g_trgsl_records[index];
   return true;
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
}

inline int __TRGSL_FindFirstBarAtOrAfter(const MqlRates &rates[],
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

inline int __TRGSL_FindLastBarAtOrBefore(const MqlRates &rates[],
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

inline bool __TRGSL_RecordClosedAtOrBefore(const TriggerSLTPRecord &rec,
                                           const MqlRates          &rates[],
                                           const int                n,
                                           const datetime           current_time)
{
   if(!rec.valid)
      return true;
   if(current_time <= 0)
      return false;

   // If the new trigger is on the same candle/time as the previous entry,
   // the previous trade is still treated as open for the one-open-trade gate.
   if(rec.hit_time <= 0 || current_time <= rec.hit_time)
      return false;

   int start_idx = __TRGSL_FindFirstBarAtOrAfter(rates, n, rec.hit_time);
   if(start_idx < 0)
      start_idx = __TRGSL_FindLastBarAtOrBefore(rates, n, rec.hit_time);

   if(start_idx < 0 || start_idx >= n)
      return false;

   for(int i = start_idx; i < n; ++i)
   {
      if(rates[i].time > current_time)
         break;

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

      if(hit_tp || hit_sl)
         return true;
   }

   return false;
}

inline int __TRGSL_OpenTradeCountBefore(const string    sym,
                                         const MqlRates &rates[],
                                         const int       n,
                                         const datetime  current_time)
{
   if(current_time <= 0)
      return 0;

   int opened = 0;
   int total = ArraySize(g_trgsl_records);
   for(int i = 0; i < total; ++i)
   {
      TriggerSLTPRecord rec = g_trgsl_records[i];
      if(!rec.valid)
         continue;

      if(sym != "" && rec.symbol != "" && rec.symbol != sym)
         continue;

      if(rec.hit_time <= 0 || rec.hit_time > current_time)
         continue;

      if(!__TRGSL_RecordClosedAtOrBefore(rec, rates, n, current_time))
         opened++;
   }

   return opened;
}

inline bool __TRGSL_MaxOpenTradesReachedBefore(const string    sym,
                                               const MqlRates &rates[],
                                               const int       n,
                                               const datetime  current_time)
{
   return (__TRGSL_OpenTradeCountBefore(sym, rates, n, current_time) >= WB_Config_MaxOpenTrades());
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

   // New Flip/MajicFlip SL rule:
   // Bullish trigger => SL below the complete Flip/MajicFlip zone.
   // This uses the lower boundary between the pattern source candle and breaker candle.
   double buffer = __TRGSL_PointOf(sym);
   if(buffer <= 0.0)
      buffer = _Point;
   if(buffer <= 0.0)
      buffer = 0.00000001;

   double zone_bottom = MathMin(rates[src_idx].low, rates[hit_idx].low);
   double sl = zone_bottom - buffer;

   double risk = (level - sl);
   if(risk <= 0.0)
      return false;

   double risk_pips = __TRGSL_ToPips(sym, risk);
   if(risk_pips < TRGSL_MIN_RISK_PIPS || risk_pips > TRGSL_MAX_RISK_PIPS)
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

   // New Flip/MajicFlip SL rule:
   // Bearish trigger => SL above the complete Flip/MajicFlip zone.
   // This uses the upper boundary between the pattern source candle and breaker candle.
   double buffer = __TRGSL_PointOf(sym);
   if(buffer <= 0.0)
      buffer = _Point;
   if(buffer <= 0.0)
      buffer = 0.00000001;

   double zone_top = MathMax(rates[src_idx].high, rates[hit_idx].high);
   double sl = zone_top + buffer;

   double risk = (sl - level);
   if(risk <= 0.0)
      return false;

   double risk_pips = __TRGSL_ToPips(sym, risk);
   if(risk_pips < TRGSL_MIN_RISK_PIPS || risk_pips > TRGSL_MAX_RISK_PIPS)
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

inline void TriggerSLTP_OnTriggerFired(const string    sym,
                                       const Direction dir,
                                       const int       type_id,
                                       const int       src_idx,
                                       const double    level,
                                       const int       hit_idx,
                                       const MqlRates &rates[],
                                       const int       n)
{
   string use_sym = sym;
   if(use_sym == "")
      use_sym = _Symbol;

   if(hit_idx >= 0 && hit_idx < n)
   {
      if(__TRGSL_MaxOpenTradesReachedBefore(use_sym, rates, n, rates[hit_idx].time))
      {
         WBLOG_LogRejectedTrigger(type_id,
                                  dir,
                                  rates[hit_idx].time,
                                  hit_idx,
                                  rates[hit_idx].open,
                                  rates[hit_idx].high,
                                  rates[hit_idx].low,
                                  rates[hit_idx].close,
                                  "max_open_trades_limit",
                                  0.0,
                                  0.0,
                                  0.0,
                                  "TriggerSLTP_OnTriggerFired_max_open_gate");

         if(InpDebugPrints)
         {
            Print("[TRG-SLTP] Skip ",
                  (dir == DIR_UP ? "UP" : "DOWN"),
                  " trigger | breakout=", DoubleToString(level, __TRGSL_DigitsOf(use_sym)),
                  " | src_idx=", src_idx,
                  " | hit_idx=", hit_idx,
                  " | reason=max_open_trades_limit_reached",
                  " | max_open=", IntegerToString(WB_Config_MaxOpenTrades()));
         }
         return;
      }
   }

   TriggerSLTPRecord rec;
   bool ok = false;

   if(dir == DIR_UP)
      ok = __TRGSL_BuildBull(use_sym, type_id, src_idx, level, hit_idx, rates, n, rec);
   else
      ok = __TRGSL_BuildBear(use_sym, type_id, src_idx, level, hit_idx, rates, n, rec);

   if(!ok)
   {
      double approx_risk_pips = 0.0;
      if(hit_idx >= 0 && hit_idx < n)
      {
         if(dir == DIR_UP)
            approx_risk_pips = __TRGSL_ToPips(use_sym, MathAbs(level - rates[hit_idx].low));
         else
            approx_risk_pips = __TRGSL_ToPips(use_sym, MathAbs(rates[hit_idx].high - level));

         WBLOG_LogRejectedTrigger(type_id,
                                  dir,
                                  rates[hit_idx].time,
                                  hit_idx,
                                  rates[hit_idx].open,
                                  rates[hit_idx].high,
                                  rates[hit_idx].low,
                                  rates[hit_idx].close,
                                  "risk_outside_configured_sl_range_or_bad_flip_zone_range",
                                  approx_risk_pips,
                                  0.0,
                                  0.0,
                                  "TriggerSLTP_OnTriggerFired_risk_filter_rejected");
      }

      if(InpDebugPrints)
      {
         Print("[TRG-SLTP] Skip invalid ",
               (dir == DIR_UP ? "UP" : "DOWN"),
               " trigger | breakout=", DoubleToString(level, __TRGSL_DigitsOf(use_sym)),
               " | src_idx=", src_idx,
               " | hit_idx=", hit_idx,
               " | reason=risk_outside_configured_sl_range_or_bad_flip_zone_range",
               " | min_sl=", DoubleToString(WB_Config_MinSLPips(), 2),
               " | max_sl=", DoubleToString(WB_Config_MaxSLPips(), 2));
      }
      return;
   }

   rec.log_context_id   = WBLOG_CurrentContextId();
   rec.log_zone_id      = WBLOG_CurrentZoneId();
   rec.log_m1_window_id = WBLOG_CurrentWindowId();
   rec.log_start_kind   = WBLOG_CurrentStartKind();
   rec.log_start_ns     = WBLOG_CurrentStartNS();

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

   if(rec.hit_idx >= 0 && rec.hit_idx < n)
   {
      WBLOG_LogM1TriggerFinal(use_sym,
                              rec.serial,
                              rec.type_id,
                              rec.dir,
                              rec.hit_time,
                              rec.hit_idx,
                              rates[rec.hit_idx].open,
                              rates[rec.hit_idx].high,
                              rates[rec.hit_idx].low,
                              rates[rec.hit_idx].close,
                              rec.breakout_level,
                              rec.sl_level,
                              rec.tp_level,
                              rec.risk_pips,
                              rec.serial);
   }

   const string dir_tag = (dir == DIR_UP ? "U" : "D");
   const string base = "TRG_SLTP_"
                     + dir_tag + "_"
                     + IntegerToString(rec.serial) + "_"
                     + IntegerToString((int)rec.hit_time);

   datetime end_t = __TRGSL_ForwardEndTime(rec.hit_time);
   __TRGSL_DrawSegment(base + "_SL", rec.hit_time, end_t, rec.sl_level, clrRed);
   __TRGSL_DrawSegment(base + "_TP", rec.hit_time, end_t, rec.tp_level, clrGreen);

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
            " | hit=", TimeToString(rec.hit_time, TIME_DATE|TIME_SECONDS));
   }
}

#endif // WAVEBOT_TRIGGER_SLTP_MQH
