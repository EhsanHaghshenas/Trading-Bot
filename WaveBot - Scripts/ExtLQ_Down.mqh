
#ifndef WAVEBOT_EXTLQ_DOWN_MQH
#define WAVEBOT_EXTLQ_DOWN_MQH
#include <WaveBot/Markers.mqh>

// -------------------- وضعیت ext lq فعلی (Down) --------------------
static bool     g_extD_has   = false;
static double   g_extD_price = 0.0;
static datetime g_extD_time  = 0;

// -------------------- تاریخچهٔ ext lq های قبلی --------------------
struct LQLevel_D
{
   double   price;
   datetime t;
   bool     broken;
};

// آرایهٔ تاریخچه (از قدیمی به جدید)
static LQLevel_D g_histD[];
static int       g_prev_idxD = -1;
// =======================[ ExtLQDownContext: snapshot کامل وضعیت ExtLQ_Down ]=======================
//
// این struct تمام state داخلی ExtLQ_Down را در خود نگه می‌دارد تا بتوانیم آن را
// برای دنیاهای ماژور/مینور جداگانه ذخیره/بازیابی کنیم، بدون اینکه منطق اصلی
// ماژول تغییری کند.
struct ExtLQDownContext
{
   bool      ext_has;      // معادل g_extD_has
   double    ext_price;    // معادل g_extD_price
   datetime  ext_time;     // معادل g_extD_time

   LQLevel_D hist[];       // کپی آرایهٔ g_histD[]
   int       prev_idx;     // معادل g_prev_idxD
};

// ریست یک کانتکست (برای استفادهٔ دستی در لایهٔ بالاتر)
inline void ExtLQ_Down_ContextReset(ExtLQDownContext &ctx)
{
   ctx.ext_has   = false;
   ctx.ext_price = 0.0;
   ctx.ext_time  = 0;
   ArrayFree(ctx.hist);
   ctx.prev_idx  = -1;
}

// Export: گرفتن snapshot از وضعیت فعلی ماژول به داخل کانتکست
inline void ExtLQ_Down_ContextExport(ExtLQDownContext &ctx)
{
   // وضعیت اصلی
   ctx.ext_has   = g_extD_has;
   ctx.ext_price = g_extD_price;
   ctx.ext_time  = g_extD_time;

   // تاریخچه
   int sz = ArraySize(g_histD);
   ArrayResize(ctx.hist, sz);
   for(int i=0; i<sz; ++i)
      ctx.hist[i] = g_histD[i];

   // اندیس رزروی
   ctx.prev_idx  = g_prev_idxD;
}

// Import: اعمال یک کانتکست روی state داخلی ماژول
inline void ExtLQ_Down_ContextImport(const ExtLQDownContext &ctx)
{
   // وضعیت اصلی
   g_extD_has   = ctx.ext_has;
   g_extD_price = ctx.ext_price;
   g_extD_time  = ctx.ext_time;

   // تاریخچه
   int sz = ArraySize(ctx.hist);
   ArrayResize(g_histD, sz);
   for(int i=0; i<sz; ++i)
      g_histD[i] = ctx.hist[i];

   // اندیس رزروی
   g_prev_idxD  = ctx.prev_idx;
}

#define EXTLQ_D_LINE_CURR  "EXTLQ_D_CURR"
#define EXTLQ_D_LINE_PREV  "EXTLQ_D_PREV"

inline void ExtLQ_Down_DeleteLine(const string base)
{
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
}

inline bool ExtLQ_Down_ShouldDrawVisuals()
{
   return false;
}

inline void ExtLQ_Down_DeleteAllVisuals_AllScans()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "") continue;

      if(StringFind(on, EXTLQ_D_LINE_CURR) >= 0 ||
         StringFind(on, EXTLQ_D_LINE_PREV) >= 0)
      {
         ObjectDelete(0, on);
      }
   }
}

inline void ExtLQ_Down_DrawLine(const string base, const double price, const color col, const ENUM_LINE_STYLE st)
{
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);

   if(!ExtLQ_Down_ShouldDrawVisuals())
      return;

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

inline void ExtLQ_Down_DeleteVisuals_CurrentScan()
{
   ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_CURR);
   ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_PREV);
}

inline void ExtLQ_Down_ClearAll(const bool delete_visuals = true)
{
   if(delete_visuals)
   {
      ExtLQ_Down_DeleteVisuals_CurrentScan();
      ExtLQ_Down_DeleteAllVisuals_AllScans();
   }

   g_extD_has   = false;
   g_extD_price = 0.0;
   g_extD_time  = 0;
   ArrayFree(g_histD);
   g_prev_idxD  = -1;
}

inline bool ExtLQ_Down_Has(){ return g_extD_has; }
inline double ExtLQ_Down_Get(){ return g_extD_price; }
inline datetime ExtLQ_Down_Time(){ return g_extD_time; }

// آخرین رزرویِ دست‌نخورده
int ExtLQ_Down_FindLatestUntouchedIndex()
{
   int sz = ArraySize(g_histD);
   for(int i=sz-1;i>=0;--i)
      if(!g_histD[i].broken) return i;
   return -1;
}

// تنظیم سطح جدید (Down = Highِ C1_W3)
inline void ExtLQ_Down_Set(const double price, const datetime t)
{
   g_extD_has   = true;
   g_extD_price = price;
   g_extD_time  = t;

   // به تاریخچه اضافه کن و قبلی‌ها را نمایش/رزرو کن
   int sz = ArraySize(g_histD);
   ArrayResize(g_histD, sz+1);
   g_histD[sz].price  = price;
   g_histD[sz].t      = t;
   g_histD[sz].broken = false;

   // خط فعلی
   if(ExtLQ_Down_ShouldDrawVisuals()) ExtLQ_Down_DrawLine(EXTLQ_D_LINE_CURR, price, InpExtLQColor, STYLE_SOLID);

   // رزروی جدید را پیدا و رسم کن
   int idx = ExtLQ_Down_FindLatestUntouchedIndex();
   if(g_prev_idxD != idx)
   {
      if(g_prev_idxD>=0) ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_PREV);
      g_prev_idxD = idx;
      if(g_prev_idxD>=0 && ExtLQ_Down_ShouldDrawVisuals())
         ExtLQ_Down_DrawLine(EXTLQ_D_LINE_PREV, g_histD[g_prev_idxD].price, clrViolet, STYLE_DOT);
   }
}

// آپدیت روی هر کندل (cross-up)
inline void ExtLQ_Down_OnBar(const MqlRates &r)
{
   int sz = ArraySize(g_histD);
   if(sz>0)
   {
      for(int i=0;i<sz;++i)
      {
         if(!g_histD[i].broken)
         {
            if(r.high >= g_histD[i].price || r.close > g_histD[i].price)
               g_histD[i].broken = true;
         }
      }
      int idx = ExtLQ_Down_FindLatestUntouchedIndex();
      if(idx != g_prev_idxD)
      {
         if(g_prev_idxD>=0) ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_PREV);
         g_prev_idxD = idx;
         if(g_prev_idxD>=0 && ExtLQ_Down_ShouldDrawVisuals())
            ExtLQ_Down_DrawLine(EXTLQ_D_LINE_PREV, g_histD[g_prev_idxD].price, clrViolet, STYLE_DOT);
      }
   }
}

// Promote previous untouched LQ (DOWN side) to be the current active one.
inline bool ExtLQ_Down_PromotePrevToCurrent()
{
   int idx = ExtLQ_Down_FindLatestUntouchedIndex();
   if(idx < 0) return false;

   if(g_extD_has)
   {
      int sz = ArraySize(g_histD);
      ArrayResize(g_histD, sz+1);
      g_histD[sz].price  = g_extD_price;
      g_histD[sz].t      = g_extD_time;
      g_histD[sz].broken = true;
   }

   g_extD_has   = true;
   g_extD_price = g_histD[idx].price;
   g_extD_time  = g_histD[idx].t;

   if(ExtLQ_Down_ShouldDrawVisuals())
      ExtLQ_Down_DrawLine(EXTLQ_D_LINE_CURR, g_extD_price, InpExtLQColor, STYLE_SOLID);

   // prev قدیمی‌ترِ دست‌نخورده
   int new_prev = -1;
   for(int i=idx-1; i>=0; --i)
      if(!g_histD[i].broken){ new_prev=i; break; }

   if(new_prev != g_prev_idxD)
   {
      if(g_prev_idxD>=0) ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_PREV);
      g_prev_idxD = new_prev;
      if(g_prev_idxD>=0 && ExtLQ_Down_ShouldDrawVisuals())
         ExtLQ_Down_DrawLine(EXTLQ_D_LINE_PREV, g_histD[g_prev_idxD].price, clrViolet, STYLE_DOT);
   }
   return true;
}

#endif // WAVEBOT_EXTLQ_DOWN_MQH
