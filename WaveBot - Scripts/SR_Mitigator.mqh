// WaveBot/SR_Mitigator.mqh

// WaveBot/SR_Mitigator.mqh
#ifndef WAVEBOT_SR_MITIGATOR_MQH
#define WAVEBOT_SR_MITIGATOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>   // __ScanPrefix()

/*
  نقش این ماژول:
  - نگهداری وضعیت SR فعال (UP/DOWN)
  - تشخیص و علامت‌گذاری «first SR mitigator» با منطق earliest-first
  - پس از تشخیص، ثبت extremum بین [کندل سازنده SR .. first mitigator] و
    رسم خط افقی خط‌چین ۱۰ کندل رو به جلو از همان کندل extremum
*/

// -------------------- State (UP) --------------------
static bool     g_srm_up_active          = false;
static double   g_srm_up_top             = 0.0;      // = High(C1-HW)
static double   g_srm_up_bottom          = 0.0;      // = Low(C1-SW)
static datetime g_srm_up_created_at      = 0;        // زمان کندلِ سازنده SR
static int      g_srm_up_id              = 0;        // شمارنده همان "SR_U_<id>"
static bool     g_srm_up_created_by_body = false;    // true اگر شکست با بدنه بوده
static bool     g_srm_up_marked          = false;    // first mitigator مارک شد؟

// indexهای مفید
static int      g_srm_up_created_idx     = -1;       // اندیس کندل سازنده SR
static datetime g_srm_up_mitig_time      = 0;        // زمان first mitigator (برای wick-case = create_time)
static int      g_srm_up_mitig_idx       = -1;       // اندیس first mitigator

// ثبت و رسم خط ۱۰ کندلی از extremum (SR U HH)
static bool     g_srm_up_ext_drawn       = false;
static double   g_srm_up_ext_price       = 0.0;      // قیمت SR U HH
static int      g_srm_up_ext_idx         = -1;       // اندیس کندل SR U HH
static datetime g_srm_up_ext_time        = 0;        // زمان کندل SR U HH




// -------------------- State (DOWN) --------------------
static bool     g_srm_dn_active          = false;
static double   g_srm_dn_top             = 0.0;      // = High(C1-SW)
static double   g_srm_dn_bottom          = 0.0;      // = Low(C1-HW)
static datetime g_srm_dn_created_at      = 0;
static int      g_srm_dn_id              = 0;        // شمارنده همان "SR_D_<id>"
static bool     g_srm_dn_created_by_body = false;
static bool     g_srm_dn_marked          = false;

static int      g_srm_dn_created_idx     = -1;
static datetime g_srm_dn_mitig_time      = 0;
static int      g_srm_dn_mitig_idx       = -1;

// SR D LL
static bool     g_srm_dn_ext_drawn       = false;
static double   g_srm_dn_ext_price       = 0.0;      // قیمت SR D LL
static int      g_srm_dn_ext_idx         = -1;       // اندیس SR D LL
static datetime g_srm_dn_ext_time        = 0;



// ------------------------------
// Context snapshot for SR_Mitigator (UP + DOWN)
// ------------------------------
struct SRMITContext
{
   // ===== UP state =====
   bool     up_active;
   double   up_top;
   double   up_bottom;
   datetime up_created_at;
   int      up_id;
   bool     up_created_by_body;
   bool     up_marked;

   int      up_created_idx;
   datetime up_mitig_time;
   int      up_mitig_idx;

   bool     up_ext_drawn;
   double   up_ext_price;
   int      up_ext_idx;
   datetime up_ext_time;




   // ===== DOWN state =====
   bool     dn_active;
   double   dn_top;
   double   dn_bottom;
   datetime dn_created_at;
   int      dn_id;
   bool     dn_created_by_body;
   bool     dn_marked;

   int      dn_created_idx;
   datetime dn_mitig_time;
   int      dn_mitig_idx;

   bool     dn_ext_drawn;
   double   dn_ext_price;
   int      dn_ext_idx;
   datetime dn_ext_time;



};

// مقداردهی اولیهٔ یک کانتکست خالی (برای مقداردهی ساختار بازار)
inline void SRMIT_ContextInit(SRMITContext &ctx)
{
   // UP
   ctx.up_active          = false;
   ctx.up_top             = 0.0;
   ctx.up_bottom          = 0.0;
   ctx.up_created_at      = 0;
   ctx.up_id              = 0;
   ctx.up_created_by_body = false;
   ctx.up_marked          = false;

   ctx.up_created_idx     = -1;
   ctx.up_mitig_time      = 0;
   ctx.up_mitig_idx       = -1;

   ctx.up_ext_drawn       = false;
   ctx.up_ext_price       = 0.0;
   ctx.up_ext_idx         = -1;
   ctx.up_ext_time        = 0;




   // DOWN
   ctx.dn_active          = false;
   ctx.dn_top             = 0.0;
   ctx.dn_bottom          = 0.0;
   ctx.dn_created_at      = 0;
   ctx.dn_id              = 0;
   ctx.dn_created_by_body = false;
   ctx.dn_marked          = false;

   ctx.dn_created_idx     = -1;
   ctx.dn_mitig_time      = 0;
   ctx.dn_mitig_idx       = -1;

   ctx.dn_ext_drawn       = false;
   ctx.dn_ext_price       = 0.0;
   ctx.dn_ext_idx         = -1;
   ctx.dn_ext_time        = 0;



}

// Export: کپی وضعیت فعلی globalها به داخل کانتکست
inline void SRMIT_ContextExport(SRMITContext &ctx)
{
   // UP
   ctx.up_active          = g_srm_up_active;
   ctx.up_top             = g_srm_up_top;
   ctx.up_bottom          = g_srm_up_bottom;
   ctx.up_created_at      = g_srm_up_created_at;
   ctx.up_id              = g_srm_up_id;
   ctx.up_created_by_body = g_srm_up_created_by_body;
   ctx.up_marked          = g_srm_up_marked;

   ctx.up_created_idx     = g_srm_up_created_idx;
   ctx.up_mitig_time      = g_srm_up_mitig_time;
   ctx.up_mitig_idx       = g_srm_up_mitig_idx;

   ctx.up_ext_drawn       = g_srm_up_ext_drawn;
   ctx.up_ext_price       = g_srm_up_ext_price;
   ctx.up_ext_idx         = g_srm_up_ext_idx;
   ctx.up_ext_time        = g_srm_up_ext_time;




   // DOWN
   ctx.dn_active          = g_srm_dn_active;
   ctx.dn_top             = g_srm_dn_top;
   ctx.dn_bottom          = g_srm_dn_bottom;
   ctx.dn_created_at      = g_srm_dn_created_at;
   ctx.dn_id              = g_srm_dn_id;
   ctx.dn_created_by_body = g_srm_dn_created_by_body;
   ctx.dn_marked          = g_srm_dn_marked;

   ctx.dn_created_idx     = g_srm_dn_created_idx;
   ctx.dn_mitig_time      = g_srm_dn_mitig_time;
   ctx.dn_mitig_idx       = g_srm_dn_mitig_idx;

   ctx.dn_ext_drawn       = g_srm_dn_ext_drawn;
   ctx.dn_ext_price       = g_srm_dn_ext_price;
   ctx.dn_ext_idx         = g_srm_dn_ext_idx;
   ctx.dn_ext_time        = g_srm_dn_ext_time;



}

// Import: برگرداندن وضعیت ذخیره‌شدهٔ کانتکست به متغیرهای global
inline void SRMIT_ContextImport(const SRMITContext &ctx)
{
   // UP
   g_srm_up_active          = ctx.up_active;
   g_srm_up_top             = ctx.up_top;
   g_srm_up_bottom          = ctx.up_bottom;
   g_srm_up_created_at      = ctx.up_created_at;
   g_srm_up_id              = ctx.up_id;
   g_srm_up_created_by_body = ctx.up_created_by_body;
   g_srm_up_marked          = ctx.up_marked;

   g_srm_up_created_idx     = ctx.up_created_idx;
   g_srm_up_mitig_time      = ctx.up_mitig_time;
   g_srm_up_mitig_idx       = ctx.up_mitig_idx;

   g_srm_up_ext_drawn       = ctx.up_ext_drawn;
   g_srm_up_ext_price       = ctx.up_ext_price;
   g_srm_up_ext_idx         = ctx.up_ext_idx;
   g_srm_up_ext_time        = ctx.up_ext_time;




   // DOWN
   g_srm_dn_active          = ctx.dn_active;
   g_srm_dn_top             = ctx.dn_top;
   g_srm_dn_bottom          = ctx.dn_bottom;
   g_srm_dn_created_at      = ctx.dn_created_at;
   g_srm_dn_id              = ctx.dn_id;
   g_srm_dn_created_by_body = ctx.dn_created_by_body;
   g_srm_dn_marked          = ctx.dn_marked;

   g_srm_dn_created_idx     = ctx.dn_created_idx;
   g_srm_dn_mitig_time      = ctx.dn_mitig_time;
   g_srm_dn_mitig_idx       = ctx.dn_mitig_idx;

   g_srm_dn_ext_drawn       = ctx.dn_ext_drawn;
   g_srm_dn_ext_price       = ctx.dn_ext_price;
   g_srm_dn_ext_idx         = ctx.dn_ext_idx;
   g_srm_dn_ext_time        = ctx.dn_ext_time;



}

// -------------------- Helpers --------------------
inline void __SRMIT_DrawV(const string base, const datetime t)
{
   if(!Markers_ShouldRender()) return;
   const string nm = __ScanPrefix() + base;
   if(ObjectFind(0, nm) != -1) ObjectDelete(0, nm);
   ObjectCreate(0, nm, OBJ_VLINE, 0, t, 0.0);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
}

// خط افقی «بازه‌دار» (نه بی‌نهایت) از t1 تا t2 روی price
inline void __SRMIT_DrawHSeg(const string base, const datetime t1, const double price, const datetime t2)
{
   if(!Markers_ShouldRender()) return;
   const string nm = __ScanPrefix() + base;
   if(ObjectFind(0, nm) != -1) ObjectDelete(0, nm);
   ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
}

// رواداری عددی روی مرز SR
inline double __SRMIT_EPS(){ return (_Point * 2.0); }

// یافتن اندیس کندل با زمان مشخص
inline int __SRMIT_FindIndexByTime(const MqlRates &rates[], const int n, const datetime t)
{
   for(int i=n-1; i>=0; --i) if(rates[i].time == t) return i;
   return -1;
}

// فاصله زمانی یک کندل (برحسب ثانیه) از روی داده‌های همان rates
inline int __SRMIT_TFSec(const MqlRates &rates[], const int n)
{
   if(n >= 2){
      int s = (int)(rates[1].time - rates[0].time);
      if(s > 0) return s;
   }
   return PeriodSeconds(Period());
}

// محاسبه زمان انتهای «N کندل بعد از اندیس from_idx»
inline datetime __SRMIT_TimePlusBars(const MqlRates &rates[],
                                     const int       n,
                                     const int       from_idx,
                                     const int       bars)
{
   // ورودی‌های نامعتبر
   if(from_idx < 0 || from_idx >= n || bars <= 0)
   {
      if(from_idx >= 0 && from_idx < n)
         return rates[from_idx].time;
      return 0;
   }

   const int tfsec = __SRMIT_TFSec(rates, n);

   int eidx = from_idx + bars;
   if(eidx < n)
      return rates[eidx].time;

   datetime t1 = rates[from_idx].time;
   // اگر به آخر آرایه رسیده باشیم، از فاصلهٔ زمانی تایم‌فریم استفاده می‌کنیم
   return (t1 + tfsec * bars);
}

// سازگاری با کد قبلی: نسخهٔ ۱۰ کندلی
inline datetime __SRMIT_TimePlus10Bars(const MqlRates &rates[],
                                       const int       n,
                                       const int       from_idx)
{
   return __SRMIT_TimePlusBars(rates, n, from_idx, 10);
}

// ریست کامل UP
inline void SRMIT_Reset_UP()
{
   g_srm_up_active          = false;
   g_srm_up_marked          = false;
   g_srm_up_id              = 0;
   g_srm_up_top             = 0.0;
   g_srm_up_bottom          = 0.0;
   g_srm_up_created_at      = 0;
   g_srm_up_created_by_body = false;

   g_srm_up_created_idx     = -1;
   g_srm_up_mitig_time      = 0;
   g_srm_up_mitig_idx       = -1;

   g_srm_up_ext_drawn       = false;
   g_srm_up_ext_price       = 0.0;
   g_srm_up_ext_idx         = -1;
   g_srm_up_ext_time        = 0;



}

// ریست کامل DOWN
inline void SRMIT_Reset_DN()
{
   g_srm_dn_active          = false;
   g_srm_dn_marked          = false;
   g_srm_dn_id              = 0;
   g_srm_dn_top             = 0.0;
   g_srm_dn_bottom          = 0.0;
   g_srm_dn_created_at      = 0;
   g_srm_dn_created_by_body = false;

   g_srm_dn_created_idx     = -1;
   g_srm_dn_mitig_time      = 0;
   g_srm_dn_mitig_idx       = -1;

   g_srm_dn_ext_drawn       = false;
   g_srm_dn_ext_price       = 0.0;
   g_srm_dn_ext_idx         = -1;
   g_srm_dn_ext_time        = 0;



}
// ریست کامل کل state ماژول SR_Mitigator در world فعلی
inline void SRMIT_ResetGlobals()
{
   SRMIT_Reset_UP();
   SRMIT_Reset_DN();
}

// -------------------- On New SR (UP/DOWN) --------------------
inline void SRMIT_OnNewSR_UP(const int id,
                             const double p_top,
                             const double p_bottom,
                             const datetime create_time,
                             const bool created_by_body)
{
   g_srm_up_active          = true;
   g_srm_up_id              = id;
   g_srm_up_top             = p_top;
   g_srm_up_bottom          = p_bottom;
   g_srm_up_created_at      = create_time;
   g_srm_up_created_by_body = created_by_body;
   g_srm_up_marked          = false;

   g_srm_up_created_idx     = -1;
   g_srm_up_mitig_time      = 0;
   g_srm_up_mitig_idx       = -1;

   g_srm_up_ext_drawn       = false;
   g_srm_up_ext_price       = 0.0;
   g_srm_up_ext_idx         = -1;
   g_srm_up_ext_time        = 0;




   // اگر با شدو ساخته شده ⇒ همان کندل first mitigator است (ولی رسم خط ۱۰ کندلی را
   // بعداً در OnBar و پس از resolve اندیس، انجام می‌دهیم)
   if(!created_by_body)
   {
      __SRMIT_DrawV("first_SR_mitigator_U_"+IntegerToString(id), create_time);
      g_srm_up_marked     = true;
      g_srm_up_mitig_time = create_time; // همان کندل
   }
}

inline void SRMIT_OnNewSR_DN(const int id,
                             const double p_top,
                             const double p_bottom,
                             const datetime create_time,
                             const bool created_by_body)
{
   g_srm_dn_active          = true;
   g_srm_dn_id              = id;
   g_srm_dn_top             = p_top;
   g_srm_dn_bottom          = p_bottom;
   g_srm_dn_created_at      = create_time;
   g_srm_dn_created_by_body = created_by_body;
   g_srm_dn_marked          = false;

   g_srm_dn_created_idx     = -1;
   g_srm_dn_mitig_time      = 0;
   g_srm_dn_mitig_idx       = -1;

   g_srm_dn_ext_drawn       = false;
   g_srm_dn_ext_price       = 0.0;
   g_srm_dn_ext_idx         = -1;
   g_srm_dn_ext_time        = 0;




   if(!created_by_body)
   {
      __SRMIT_DrawV("first_SR_mitigator_D_"+IntegerToString(id), create_time);
      g_srm_dn_marked     = true;
      g_srm_dn_mitig_time = create_time;
   }
}

// -------------------- Finalize & draw 10-bar line --------------------
// UP: پس از مشخص شدن first mitigator
inline void __SRMIT_FinalizeAndDraw_UP(const MqlRates &rates[], const int n, const int mitig_idx)
{
   if(mitig_idx < 0 || mitig_idx >= n)
      return;

   if(g_srm_up_created_idx < 0)
      g_srm_up_created_idx = __SRMIT_FindIndexByTime(rates, n, g_srm_up_created_at);

   // شروع بازه از کندل سازندهٔ SR اگر پیدا شده باشد
   int from = 0;
   if(g_srm_up_created_idx >= 0)
      from = g_srm_up_created_idx;

   // به‌طور پیش‌فرض تا خود first SR mitigator
   int to = mitig_idx;

   // --- قانون جدید برای SR U HH نسبت به رنگ first SR mitigation ---
   // اگر:
   //  - اندیس سازنده SR معتبر باشد
   //  - first SR mitigator بعد از کندل سازنده باشد (wick-case نیست)
   //  - کندل first SR mitigator سبز باشد (close >= open)
   // آنگاه خود کندل first mitigator از بازهٔ محاسبهٔ SR U HH حذف می‌شود
   // و HH فقط از بین کندل‌های قبل از آن انتخاب می‌شود.
   if(g_srm_up_created_idx >= 0 && mitig_idx > g_srm_up_created_idx)
   {
      const double o = rates[mitig_idx].open;
      const double c = rates[mitig_idx].close;
      const bool   isBull = (c >= o);   // کندل سبز (یا دوجی متمایل به بالا)

      if(isBull)
         to = mitig_idx - 1;
   }

   // اگر بازه نامعتبر شد، چیزی رسم نکن
   if(from < 0 || from >= n || to < from)
      return;

   // بالاترین High در بازه [کندل سازنده SR .. (first mitigator یا کندل قبل از آن)] = SR U HH
   double hh   = -DBL_MAX;
   int    hhIdx = -1;
   for(int i = from; i <= to; ++i)
   {
      if(rates[i].high > hh)
      {
         hh    = rates[i].high;
         hhIdx = i;
      }
   }

   if(hhIdx >= 0)
   {
      datetime t1 = rates[hhIdx].time;
      datetime t2 = __SRMIT_TimePlus10Bars(rates, n, hhIdx);
      __SRMIT_DrawHSeg("SR_U_"+IntegerToString(g_srm_up_id)+"_HH10", t1, hh, t2);

      g_srm_up_ext_drawn = true;
      g_srm_up_ext_price = hh;
      g_srm_up_ext_idx   = hhIdx;
      g_srm_up_ext_time  = t1;

   }
}


// DOWN: پس از مشخص شدن first mitigator
inline void __SRMIT_FinalizeAndDraw_DN(const MqlRates &rates[], const int n, const int mitig_idx)
{
   if(mitig_idx < 0 || mitig_idx >= n)
      return;

   if(g_srm_dn_created_idx < 0)
      g_srm_dn_created_idx = __SRMIT_FindIndexByTime(rates, n, g_srm_dn_created_at);

   int from = 0;
   if(g_srm_dn_created_idx >= 0)
      from = g_srm_dn_created_idx;

   int to = mitig_idx;

   // --- قانون جدید برای SR D LL نسبت به رنگ first SR mitigation ---
   // اگر:
   //  - first SR mitigator بعد از کندل سازنده SR باشد
   //  - کندل first SR mitigator قرمز باشد (close <= open)
   // آن کندل از بازهٔ محاسبهٔ SR D LL حذف می‌شود.
   if(g_srm_dn_created_idx >= 0 && mitig_idx > g_srm_dn_created_idx)
   {
      const double o = rates[mitig_idx].open;
      const double c = rates[mitig_idx].close;
      const bool   isBear = (c <= o);   // کندل قرمز (یا دوجی متمایل به پایین)

      if(isBear)
         to = mitig_idx - 1;
   }

   if(from < 0 || from >= n || to < from)
      return;

   // پایین‌ترین Low در بازه [کندل سازنده SR .. (first mitigator یا کندل قبل از آن)] = SR D LL
   double ll   = DBL_MAX;
   int    llIdx = -1;
   for(int i = from; i <= to; ++i)
   {
      if(rates[i].low < ll)
      {
         ll    = rates[i].low;
         llIdx = i;
      }
   }

   if(llIdx >= 0)
   {
      datetime t1 = rates[llIdx].time;
      datetime t2 = __SRMIT_TimePlus10Bars(rates, n, llIdx);
      __SRMIT_DrawHSeg("SR_D_"+IntegerToString(g_srm_dn_id)+"_LL10", t1, ll, t2);

      g_srm_dn_ext_drawn = true;
      g_srm_dn_ext_price = ll;
      g_srm_dn_ext_idx   = llIdx;
      g_srm_dn_ext_time  = t1;

   }
}

// -------------------- Per-bar scan (earliest-first + post-mark draw) --------------------

// UP
// UP
inline void SR_Mitigator_OnBar_UP(const MqlRates &rates[], const int n, const int j)
{
   if(!g_srm_up_active) return;
   if(j < 0 || j >= n)  return;


   // resolve creation index lazily
   if(g_srm_up_created_idx < 0 && g_srm_up_created_at > 0)
      g_srm_up_created_idx = __SRMIT_FindIndexByTime(rates, n, g_srm_up_created_at);

   // wick-case: قبلاً first SR mitigator با خود کندل سازنده SR مارک شده
   // ولی خط ۱۰ کندلی (SR U HH) هنوز رسم نشده
   if(g_srm_up_marked && !g_srm_up_ext_drawn)
   {
      if(g_srm_up_mitig_idx < 0 && g_srm_up_mitig_time > 0)
         g_srm_up_mitig_idx = __SRMIT_FindIndexByTime(rates, n, g_srm_up_mitig_time);

      if(g_srm_up_mitig_idx >= 0)
         __SRMIT_FinalizeAndDraw_UP(rates, n, g_srm_up_mitig_idx);
      return;
   }

   // بدن‌محور: earliest-first برای first SR mitigator (بعد از کندل سازنده SR)
   if(!g_srm_up_marked && g_srm_up_created_by_body && rates[j].time > g_srm_up_created_at)
   {
      const double eps  = __SRMIT_EPS();
      const int    from = (g_srm_up_created_idx >= 0 ? g_srm_up_created_idx + 1 : 0);

      for(int k = from; k <= j; ++k)
      {
         // اولین ورود به strong range (wick یا body): low <= level_top
         if(rates[k].low <= g_srm_up_top + eps)
         {
            __SRMIT_DrawV("first_SR_mitigator_U_"+IntegerToString(g_srm_up_id), rates[k].time);
            g_srm_up_marked     = true;
            g_srm_up_mitig_time = rates[k].time;
            g_srm_up_mitig_idx  = k;
            __SRMIT_FinalizeAndDraw_UP(rates, n, k);
            break;
         }
      }
   }

}

// DOWN
inline void SR_Mitigator_OnBar_DOWN(const MqlRates &rates[], const int n, const int j)
{
   if(!g_srm_dn_active) return;
   if(j < 0 || j >= n)  return;


   if(g_srm_dn_created_idx < 0 && g_srm_dn_created_at > 0)
      g_srm_dn_created_idx = __SRMIT_FindIndexByTime(rates, n, g_srm_dn_created_at);

   // wick-case نزولی: first SR mitigator قبلاً روی کندل سازنده SR مارک شده است
   // ولی خط ۱۰ کندلی (SR D LL) هنوز رسم نشده
   if(g_srm_dn_marked && !g_srm_dn_ext_drawn)
   {
      if(g_srm_dn_mitig_idx < 0 && g_srm_dn_mitig_time > 0)
         g_srm_dn_mitig_idx = __SRMIT_FindIndexByTime(rates, n, g_srm_dn_mitig_time);

      if(g_srm_dn_mitig_idx >= 0)
         __SRMIT_FinalizeAndDraw_DN(rates, n, g_srm_dn_mitig_idx);
      return;
   }

   // بدن‌محور نزولی: earliest-first برای first SR mitigator (از کندل بعد از سازنده)
   if(!g_srm_dn_marked && g_srm_dn_created_by_body && rates[j].time > g_srm_dn_created_at)
   {
      const double eps  = __SRMIT_EPS();
      const int    from = (g_srm_dn_created_idx >= 0 ? g_srm_dn_created_idx + 1 : 0);

      for(int k = from; k <= j; ++k)
      {
         // اولین ورود به strong range از پایین: high >= level_bottom
         if(rates[k].high >= g_srm_dn_bottom - eps)
         {
            __SRMIT_DrawV("first_SR_mitigator_D_"+IntegerToString(g_srm_dn_id), rates[k].time);
            g_srm_dn_marked     = true;
            g_srm_dn_mitig_time = rates[k].time;
            g_srm_dn_mitig_idx  = k;
            __SRMIT_FinalizeAndDraw_DN(rates, n, k);
            break;
         }
      }
   }

}

#endif // WAVEBOT_SR_MITIGATOR_MQH
