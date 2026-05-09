#ifndef WAVEBOT_TRIGGER_SLTP_MQH
#define WAVEBOT_TRIGGER_SLTP_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>

#define TRGSL_MAX_RISK_PIPS 25.0
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
   // Bullish trigger => SL below the Low of the same Flip/MajicFlip candle.
   double buffer = __TRGSL_PointOf(sym);
   if(buffer <= 0.0)
      buffer = _Point;
   if(buffer <= 0.0)
      buffer = 0.00000001;

   double sl = rates[hit_idx].low - buffer;

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

   // New Flip/MajicFlip SL rule:
   // Bearish trigger => SL above the High of the same Flip/MajicFlip candle.
   double buffer = __TRGSL_PointOf(sym);
   if(buffer <= 0.0)
      buffer = _Point;
   if(buffer <= 0.0)
      buffer = 0.00000001;

   double sl = rates[hit_idx].high + buffer;

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

   TriggerSLTPRecord rec;
   bool ok = false;

   if(dir == DIR_UP)
      ok = __TRGSL_BuildBull(use_sym, type_id, src_idx, level, hit_idx, rates, n, rec);
   else
      ok = __TRGSL_BuildBear(use_sym, type_id, src_idx, level, hit_idx, rates, n, rec);

   if(!ok)
   {
      if(InpDebugPrints)
      {
         Print("[TRG-SLTP] Skip invalid ",
               (dir == DIR_UP ? "UP" : "DOWN"),
               " trigger | breakout=", DoubleToString(level, __TRGSL_DigitsOf(use_sym)),
               " | src_idx=", src_idx,
               " | hit_idx=", hit_idx,
               " | reason=risk>25pip_or_bad_flip_candle_range");
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
