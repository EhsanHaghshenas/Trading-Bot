// ============================================================================
#ifndef WAVEBOT_EXTLQ_MQH
#define WAVEBOT_EXTLQ_MQH
#include <WaveBot/Markers.mqh>

// -------------------- وضعیت ext lq فعلی (اصلی) --------------------
static bool     g_ext_has   = false;
static double   g_ext_price = 0.0;
static datetime g_ext_time  = 0;

// -------------------- تاریخچهٔ ext lq های قبلی --------------------
struct LQLevel
{
   double   price;
   datetime t;
   bool     broken;
};

// آرایهٔ تاریخچه (از قدیمی به جدید)
static LQLevel g_hist[];
// اندیس جدیدترین سطح قبلیِ «دست‌نخورده» که الان نمایش می‌دهیم
static int     g_prev_idx = -1;

// محدودکنندهٔ تعداد تاریخچه (در صورت نیاز)
static const int  EXTLQ_MAX_HISTORY = 200;

// -------------------- نام اشیاء ترسیمی ----------------------------
static const string EXTLQ_LINE_CURR = "EXTLQ_CURR"; // اصلی (magenta, solid)
static const string EXTLQ_LINE_PREV = "EXTLQ_PREV"; // رزروی منتخب (violet, dot)

// =======================[ ExtLQContext: snapshot کامل وضعیت ExtLQ (UP) ]=======================
//
// این struct تمام state داخلی ExtLQ (UP) را در خود نگه می‌دارد تا بتوانیم آن را
// برای دنیای ماژور/مینور جداگانه ذخیره/بازیابی کنیم.
struct ExtLQContext
{
   bool     ext_has;    // معادل g_ext_has
   double   ext_price;  // معادل g_ext_price
   datetime ext_time;   // معادل g_ext_time

   LQLevel  hist[];     // کپی آرایه‌ی g_hist[]
   int      prev_idx;   // معادل g_prev_idx
};

// Export: گرفتن snapshot از وضعیت فعلی ExtLQ در کانتکست
inline void ExtLQ_ContextExport(ExtLQContext &ctx)
{
   ctx.ext_has   = g_ext_has;
   ctx.ext_price = g_ext_price;
   ctx.ext_time  = g_ext_time;

   int sz = ArraySize(g_hist);
   ArrayResize(ctx.hist, sz);
   for(int i=0; i<sz; ++i)
      ctx.hist[i] = g_hist[i];

   ctx.prev_idx  = g_prev_idx;
}

// Import: اعمال یک کانتکست روی state گلوبال ExtLQ
inline void ExtLQ_ContextImport(const ExtLQContext &ctx)
{
   g_ext_has   = ctx.ext_has;
   g_ext_price = ctx.ext_price;
   g_ext_time  = ctx.ext_time;

   int sz = ArraySize(ctx.hist);
   ArrayResize(g_hist, sz);
   for(int i=0; i<sz; ++i)
      g_hist[i] = ctx.hist[i];

   g_prev_idx  = ctx.prev_idx;
}

// -------------------- Getters -------------------------------------
inline bool     ExtLQ_Has()        { return g_ext_has; }
inline double   ExtLQ_Get()        { return g_ext_price; }
inline datetime ExtLQ_Time()       { return g_ext_time; }

// آیا رزروی «نمایش‌داده‌شده» داریم؟
inline bool     ExtLQ_PrevHas()
{
   return (g_prev_idx>=0 && g_prev_idx<ArraySize(g_hist) && !g_hist[g_prev_idx].broken);
}
inline double   ExtLQ_PrevGet()    { return ExtLQ_PrevHas()? g_hist[g_prev_idx].price : 0.0; }
inline datetime ExtLQ_PrevTime()   { return ExtLQ_PrevHas()? g_hist[g_prev_idx].t     : 0;   }
inline bool     ExtLQ_PrevIsBroken(){ return (g_prev_idx>=0 && g_hist[g_prev_idx].broken); }

// -------------------- ترسیم/حذف خطوط ------------------------------
inline bool ExtLQ_ShouldDrawVisuals()
{
   return false;
}

inline void ExtLQ_DeleteAllVisuals_AllScans()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "") continue;

      if(StringFind(on, EXTLQ_LINE_CURR) >= 0 ||
         StringFind(on, EXTLQ_LINE_PREV) >= 0)
      {
         ObjectDelete(0, on);
      }
   }
}

inline void ExtLQ_DrawLine(const string base, const double price, const color col, const int style)
{
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);

   if(!ExtLQ_ShouldDrawVisuals())
      return;

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

inline void ExtLQ_DeleteLine(const string base)
{
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
}

inline void ExtLQ_DeleteVisuals_CurrentScan()
{
   ExtLQ_DeleteLine(EXTLQ_LINE_CURR);
   ExtLQ_DeleteLine(EXTLQ_LINE_PREV);
}

inline void ExtLQ_ClearAll(const bool delete_visuals = true)
{
   if(delete_visuals)
   {
      ExtLQ_DeleteVisuals_CurrentScan();
      ExtLQ_DeleteAllVisuals_AllScans();
   }

   g_ext_has   = false;
   g_ext_price = 0.0;
   g_ext_time  = 0;
   ArrayFree(g_hist);
   g_prev_idx  = -1;
}

// -------------------- کمکی‌های داخلی ------------------------------
inline int ExtLQ_FindLatestUntouchedIndex()
{
   int sz = ArraySize(g_hist);
   for(int i=sz-1; i>=0; --i)
      if(!g_hist[i].broken) return i;
   return -1;
}
inline void ExtLQ_TrimHistoryIfNeeded()
{
   int sz = ArraySize(g_hist);
   if(sz<=EXTLQ_MAX_HISTORY) return;
   // حذف قدیمی‌ترین‌ها تا سقف
   int removeN = sz - EXTLQ_MAX_HISTORY;
   for(int k=removeN; k<sz; ++k)
      g_hist[k-removeN] = g_hist[k];
   ArrayResize(g_hist, EXTLQ_MAX_HISTORY);
   // اندیس نمایش فعلی اصلاح شود
   if(g_prev_idx>=0) g_prev_idx = MathMax(-1, g_prev_idx-removeN);
}

// -------------------- ست کردن سطح جدید (بعد از تایید W3) --------
// - ext lq فعلی به تاریخچه (به‌عنوان «دست‌نخورده») اضافه می‌شود
// - ext lq جدید ثبت و خط افقی آن رسم می‌گردد
// - رزروی منتخب: جدیدترین دست‌نخورده از تاریخچه
inline void ExtLQ_Set(const double price, const datetime t)
{
   // فعلی → تاریخچه
   if(g_ext_has)
   {
      int sz = ArraySize(g_hist);
      ArrayResize(g_hist, sz+1);
      g_hist[sz].price  = g_ext_price;
      g_hist[sz].t      = g_ext_time;
      g_hist[sz].broken = false;
      ExtLQ_TrimHistoryIfNeeded();
   }

   // سطح جدید (اصلی)
   g_ext_has   = true;
   g_ext_price = price;
   g_ext_time  = t;
   ExtLQ_DrawLine(EXTLQ_LINE_CURR, g_ext_price, clrMagenta, STYLE_SOLID);

   // انتخاب رزرویِ دست‌نخورده (اگر موجود)
   int idx = ExtLQ_FindLatestUntouchedIndex();
   if(idx != g_prev_idx)
   {
      if(g_prev_idx>=0) ExtLQ_DeleteLine(EXTLQ_LINE_PREV);
      g_prev_idx = idx;
      if(g_prev_idx>=0) ExtLQ_DrawLine(EXTLQ_LINE_PREV, g_hist[g_prev_idx].price, clrViolet, STYLE_DOT);
   }
}

// -------------------- آپدیت روی هر کندل ---------------------------
// - اگر رزروی یا هر سطح تاریخچه شکسته شد، پرچمش broken=true می‌شود
// - سپس جدیدترینِ دست‌نخورده را پیدا و خط افقی را مطابق آن به‌روز می‌کنیم
inline void ExtLQ_OnBar(const MqlRates &r)
{
   int sz = ArraySize(g_hist);
   if(sz>0)
   {
      for(int i=0;i<sz;++i)
      {
         if(!g_hist[i].broken)
         {
            if(r.low <= g_hist[i].price || r.close < g_hist[i].price)
               g_hist[i].broken = true;
         }
      }
      int idx = ExtLQ_FindLatestUntouchedIndex();
      if(idx != g_prev_idx)
      {
         // رزروی قبلی را پاک/تعویض کن
         if(g_prev_idx>=0) ExtLQ_DeleteLine(EXTLQ_LINE_PREV);
         g_prev_idx = idx;
         if(g_prev_idx>=0) ExtLQ_DrawLine(EXTLQ_LINE_PREV, g_hist[g_prev_idx].price, clrViolet, STYLE_DOT);
      }
   }
}

// Promote the latest untouched previous LQ to be the current active LQ.
inline bool ExtLQ_PromotePrevToCurrent()
{
   if(!ExtLQ_PrevHas()) return false;

   // فعلی را به تاریخچه (به‌عنوان invalidated) منتقل کن
   if(g_ext_has)
   {
      int sz = ArraySize(g_hist);
      ArrayResize(g_hist, sz+1);
      g_hist[sz].price  = g_ext_price;
      g_hist[sz].t      = g_ext_time;
      g_hist[sz].broken = true; // این سطح عملاً باطل شده است
   }

   // ارتقای رزرویِ دست‌نخورده به فعلی
   g_ext_has   = true;
   g_ext_price = g_hist[g_prev_idx].price;
   g_ext_time  = g_hist[g_prev_idx].t;

   ExtLQ_DrawLine(EXTLQ_LINE_CURR, g_ext_price, clrMagenta, STYLE_SOLID);

   // رزروی بعدی (قدیمی‌ترِ دست‌نخورده) را پیدا و نمایش بده
   int new_prev = -1;
   for(int i=g_prev_idx-1; i>=0; --i)
      if(!g_hist[i].broken){ new_prev=i; break; }

   if(new_prev != g_prev_idx)
   {
      if(g_prev_idx>=0) ExtLQ_DeleteLine(EXTLQ_LINE_PREV);
      g_prev_idx = new_prev;
      if(g_prev_idx>=0) ExtLQ_DrawLine(EXTLQ_LINE_PREV, g_hist[g_prev_idx].price, clrViolet, STYLE_DOT);
   }
   return true;
}

#endif // WAVEBOT_EXTLQ_MQH
