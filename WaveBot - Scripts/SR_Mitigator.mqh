// ============================================================================
// WaveBot/SR_Mitigator.mqh

// WaveBot/SR_Mitigator.mqh
#ifndef WAVEBOT_SR_MITIGATOR_MQH
#define WAVEBOT_SR_MITIGATOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>   // __ScanPrefix()
#include <WaveBot/FSMS_SW.mqh>   // Minor session binding / expiry helpers

/*
  نقش این ماژول:
  - نگهداری وضعیت SR فعال (UP/DOWN)
  - تشخیص و علامت‌گذاری «first SR mitigator» با منطق earliest-first
  - پس از تشخیص، ثبت extremum بین [کندل سازنده SR .. first mitigator] و
    رسم خط افقی خط‌چین ۱۰ کندل رو به جلو از همان کندل extremum
*/

// -------------------- State (UP) --------------------
static bool     g_srm_up_active          = false;
static double   g_srm_up_top             = 0.0;      // = High(C1-HW یا C1-W2 هم‌جهت FSMS)
static double   g_srm_up_bottom          = 0.0;      // = Low(C1-SW یا C1-FSMS-SW)
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

// زمان C1-SW یا C1-FSMS-SW (لبه چپ ناحیه strong range و unmitigated SR در UP)
static datetime g_srm_up_bottom_time     = 0;

// وضعیت ناحیه unmitigated SR (UP)
static bool     g_srm_up_unmit_active      = false;  // آیا اسکن برای unmit فعال است؟
static bool     g_srm_up_unmit_break_seen  = false;  // آیا اولین شکست SR U HH دیده شده؟
static int      g_srm_up_unmit_break_idx   = -1;
static datetime g_srm_up_unmit_break_time  = 0;
static int      g_srm_up_unmit_deep_idx    = -1;     // اندیس deepest SR mitigation
static double   g_srm_up_unmit_deep_price  = 0.0;    // Low deepest SR mitigation
static bool     g_srm_up_unmit_drawn       = false;  // آیا مستطیل unmit کشیده شده؟

// lineage ownership (برای جلوگیری از اثرگذاری state مینور بعد از MinorOff)
static bool     g_srm_up_origin_minor        = false;
static int      g_srm_up_origin_minor_dir    = -1;   // 0=UP, 1=DOWN
static datetime g_srm_up_origin_minor_start  = 0;

// -------------------- State (DOWN) --------------------
static bool     g_srm_dn_active          = false;
static double   g_srm_dn_top             = 0.0;      // = High(C1-SW یا C1-FSMS-SW)
static double   g_srm_dn_bottom          = 0.0;      // = Low(C1-HW یا C1-W2 هم‌جهت FSMS)
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

// زمان C1-SW یا C1-FSMS-SW (لبه چپ ناحیه strong range و unmitigated SR در DOWN)
static datetime g_srm_dn_top_time        = 0;

// وضعیت ناحیه unmitigated SR (DOWN)
static bool     g_srm_dn_unmit_active      = false;
static bool     g_srm_dn_unmit_break_seen  = false;
static int      g_srm_dn_unmit_break_idx   = -1;
static datetime g_srm_dn_unmit_break_time  = 0;
static int      g_srm_dn_unmit_deep_idx    = -1;     // اندیس deepest SR mitigation (بیشترین High)
static double   g_srm_dn_unmit_deep_price  = 0.0;    // High deepest SR mitigation
static bool     g_srm_dn_unmit_drawn       = false;

// lineage ownership (برای جلوگیری از اثرگذاری state مینور بعد از MinorOff)
static bool     g_srm_dn_origin_minor        = false;
static int      g_srm_dn_origin_minor_dir    = -1;   // 0=UP, 1=DOWN
static datetime g_srm_dn_origin_minor_start  = 0;
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

   datetime up_bottom_time;

   bool     up_unmit_active;
   bool     up_unmit_break_seen;
   int      up_unmit_break_idx;
   datetime up_unmit_break_time;
   int      up_unmit_deep_idx;
   double   up_unmit_deep_price;
   bool     up_unmit_drawn;

   bool     up_origin_minor;
   int      up_origin_minor_dir;
   datetime up_origin_minor_start;

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

   datetime dn_top_time;

   bool     dn_unmit_active;
   bool     dn_unmit_break_seen;
   int      dn_unmit_break_idx;
   datetime dn_unmit_break_time;
   int      dn_unmit_deep_idx;
   double   dn_unmit_deep_price;
   bool     dn_unmit_drawn;

   bool     dn_origin_minor;
   int      dn_origin_minor_dir;
   datetime dn_origin_minor_start;
};

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
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

   ctx.up_bottom_time     = 0;

   ctx.up_unmit_active      = false;
   ctx.up_unmit_break_seen  = false;
   ctx.up_unmit_break_idx   = -1;
   ctx.up_unmit_break_time  = 0;
   ctx.up_unmit_deep_idx    = -1;
   ctx.up_unmit_deep_price  = 0.0;
   ctx.up_unmit_drawn       = false;

   ctx.up_origin_minor      = false;
   ctx.up_origin_minor_dir  = -1;
   ctx.up_origin_minor_start= 0;

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

   ctx.dn_top_time        = 0;

   ctx.dn_unmit_active      = false;
   ctx.dn_unmit_break_seen  = false;
   ctx.dn_unmit_break_idx   = -1;
   ctx.dn_unmit_break_time  = 0;
   ctx.dn_unmit_deep_idx    = -1;
   ctx.dn_unmit_deep_price  = 0.0;
   ctx.dn_unmit_drawn       = false;

   ctx.dn_origin_minor      = false;
   ctx.dn_origin_minor_dir  = -1;
   ctx.dn_origin_minor_start= 0;
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

   ctx.up_bottom_time     = g_srm_up_bottom_time;

   ctx.up_unmit_active      = g_srm_up_unmit_active;
   ctx.up_unmit_break_seen  = g_srm_up_unmit_break_seen;
   ctx.up_unmit_break_idx   = g_srm_up_unmit_break_idx;
   ctx.up_unmit_break_time  = g_srm_up_unmit_break_time;
   ctx.up_unmit_deep_idx    = g_srm_up_unmit_deep_idx;
   ctx.up_unmit_deep_price  = g_srm_up_unmit_deep_price;
   ctx.up_unmit_drawn       = g_srm_up_unmit_drawn;

   ctx.up_origin_minor      = g_srm_up_origin_minor;
   ctx.up_origin_minor_dir  = g_srm_up_origin_minor_dir;
   ctx.up_origin_minor_start= g_srm_up_origin_minor_start;

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

   ctx.dn_top_time        = g_srm_dn_top_time;

   ctx.dn_unmit_active      = g_srm_dn_unmit_active;
   ctx.dn_unmit_break_seen  = g_srm_dn_unmit_break_seen;
   ctx.dn_unmit_break_idx   = g_srm_dn_unmit_break_idx;
   ctx.dn_unmit_break_time  = g_srm_dn_unmit_break_time;
   ctx.dn_unmit_deep_idx    = g_srm_dn_unmit_deep_idx;
   ctx.dn_unmit_deep_price  = g_srm_dn_unmit_deep_price;
   ctx.dn_unmit_drawn       = g_srm_dn_unmit_drawn;

   ctx.dn_origin_minor      = g_srm_dn_origin_minor;
   ctx.dn_origin_minor_dir  = g_srm_dn_origin_minor_dir;
   ctx.dn_origin_minor_start= g_srm_dn_origin_minor_start;
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

   g_srm_up_bottom_time     = ctx.up_bottom_time;

   g_srm_up_unmit_active      = ctx.up_unmit_active;
   g_srm_up_unmit_break_seen  = ctx.up_unmit_break_seen;
   g_srm_up_unmit_break_idx   = ctx.up_unmit_break_idx;
   g_srm_up_unmit_break_time  = ctx.up_unmit_break_time;
   g_srm_up_unmit_deep_idx    = ctx.up_unmit_deep_idx;
   g_srm_up_unmit_deep_price  = ctx.up_unmit_deep_price;
   g_srm_up_unmit_drawn       = ctx.up_unmit_drawn;

   g_srm_up_origin_minor      = ctx.up_origin_minor;
   g_srm_up_origin_minor_dir  = ctx.up_origin_minor_dir;
   g_srm_up_origin_minor_start= ctx.up_origin_minor_start;

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

   g_srm_dn_top_time        = ctx.dn_top_time;

   g_srm_dn_unmit_active      = ctx.dn_unmit_active;
   g_srm_dn_unmit_break_seen  = ctx.dn_unmit_break_seen;
   g_srm_dn_unmit_break_idx   = ctx.dn_unmit_break_idx;
   g_srm_dn_unmit_break_time  = ctx.dn_unmit_break_time;
   g_srm_dn_unmit_deep_idx    = ctx.dn_unmit_deep_idx;
   g_srm_dn_unmit_deep_price  = ctx.dn_unmit_deep_price;
   g_srm_dn_unmit_drawn       = ctx.dn_unmit_drawn;

   g_srm_dn_origin_minor      = ctx.dn_origin_minor;
   g_srm_dn_origin_minor_dir  = ctx.dn_origin_minor_dir;
   g_srm_dn_origin_minor_start= ctx.dn_origin_minor_start;
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

// مستطیل ناحیه unmitigated SR (فقط بصری)
inline void __SRMIT_DrawUnmitRect(const string base,
                                  const datetime t1, const double p_top,
                                  const datetime t2, const double p_bottom)
{
   if(!Markers_ShouldRender()) return;

   datetime a = t1;
   datetime b = t2;
   if(b < a)
   {
      datetime tmp = a;
      a = b;
      b = tmp;
   }

   const string nm = __ScanPrefix() + base;
   if(ObjectFind(0, nm) != -1) ObjectDelete(0, nm);

   ObjectCreate(0, nm, OBJ_RECTANGLE, 0, a, p_top, b, p_bottom);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrPowderBlue);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_BACK,  true);
   ObjectSetInteger(0, nm, OBJPROP_FILL,  false);
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

// رسم خط افقی ۲۰ کندلی روی deepest SR mitigation (UP)
// این خط همان سطح قیمتی است که با شکست دوباره‌اش gooz baghali ساخته می‌شود
inline void __SRMIT_DrawDeepestLine_UP(const MqlRates &rates[],
                                       const int       n,
                                       const int       deep_idx,
                                       const double    price)
{
   if(deep_idx < 0 || deep_idx >= n)
      return;

   datetime t1 = rates[deep_idx].time;
   datetime t2 = __SRMIT_TimePlusBars(rates, n, deep_idx, 20);

   string base = "SR_U_"+IntegerToString(g_srm_up_id)+"_DEEP20";
   __SRMIT_DrawHSeg(base, t1, price, t2);   // خط افقی با استایل خط‌چین (داخل خود DrawHSeg)
}

// رسم خط افقی ۲۰ کندلی روی deepest SR mitigation (DOWN)
inline void __SRMIT_DrawDeepestLine_DN(const MqlRates &rates[],
                                       const int       n,
                                       const int       deep_idx,
                                       const double    price)
{
   if(deep_idx < 0 || deep_idx >= n)
      return;

   datetime t1 = rates[deep_idx].time;
   datetime t2 = __SRMIT_TimePlusBars(rates, n, deep_idx, 20);

   string base = "SR_D_"+IntegerToString(g_srm_dn_id)+"_DEEP20";
   __SRMIT_DrawHSeg(base, t1, price, t2);
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

   g_srm_up_bottom_time     = 0;

   g_srm_up_unmit_active      = false;
   g_srm_up_unmit_break_seen  = false;
   g_srm_up_unmit_break_idx   = -1;
   g_srm_up_unmit_break_time  = 0;
   g_srm_up_unmit_deep_idx    = -1;
   g_srm_up_unmit_deep_price  = 0.0;
   g_srm_up_unmit_drawn       = false;

   g_srm_up_origin_minor      = false;
   g_srm_up_origin_minor_dir  = -1;
   g_srm_up_origin_minor_start= 0;
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

   g_srm_dn_top_time        = 0;

   g_srm_dn_unmit_active      = false;
   g_srm_dn_unmit_break_seen  = false;
   g_srm_dn_unmit_break_idx   = -1;
   g_srm_dn_unmit_break_time  = 0;
   g_srm_dn_unmit_deep_idx    = -1;
   g_srm_dn_unmit_deep_price  = 0.0;
   g_srm_dn_unmit_drawn       = false;

   g_srm_dn_origin_minor      = false;
   g_srm_dn_origin_minor_dir  = -1;
   g_srm_dn_origin_minor_start= 0;
}
// ریست کامل کل state ماژول SR_Mitigator در world فعلی
inline void SRMIT_ResetGlobals()
{
   SRMIT_Reset_UP();
   SRMIT_Reset_DN();
}

inline bool SRMIT_UP_IsMinorOrigin()            { return g_srm_up_origin_minor; }
inline int  SRMIT_UP_MinorDirCode()             { return g_srm_up_origin_minor_dir; }
inline datetime SRMIT_UP_MinorStarterTime()     { return g_srm_up_origin_minor_start; }

inline bool SRMIT_DN_IsMinorOrigin()            { return g_srm_dn_origin_minor; }
inline int  SRMIT_DN_MinorDirCode()             { return g_srm_dn_origin_minor_dir; }
inline datetime SRMIT_DN_MinorStarterTime()     { return g_srm_dn_origin_minor_start; }

inline bool __SRMIT_MinorExpired_UP(const datetime asof_time)
{
   if(!g_srm_up_origin_minor) return false;
   return FSMS_SW_IsMinorLineageExpired(g_srm_up_origin_minor_dir,
                                        g_srm_up_origin_minor_start,
                                        asof_time);
}

inline bool __SRMIT_MinorExpired_DN(const datetime asof_time)
{
   if(!g_srm_dn_origin_minor) return false;
   return FSMS_SW_IsMinorLineageExpired(g_srm_dn_origin_minor_dir,
                                        g_srm_dn_origin_minor_start,
                                        asof_time);
}

inline void SRMIT_ExpireMinorLineages(const int dir_code,
                                      const datetime starter_time)
{
   if(starter_time <= 0) return;

   if(g_srm_up_origin_minor &&
      g_srm_up_origin_minor_dir == dir_code &&
      g_srm_up_origin_minor_start == starter_time)
   {
      SRMIT_Reset_UP();
   }

   if(g_srm_dn_origin_minor &&
      g_srm_dn_origin_minor_dir == dir_code &&
      g_srm_dn_origin_minor_start == starter_time)
   {
      SRMIT_Reset_DN();
   }
}

// -------------------- On New SR (UP/DOWN) --------------------
inline void SRMIT_OnNewSR_UP(const int id,
                             const double p_top,
                             const double p_bottom,
                             const datetime create_time,
                             const bool created_by_body,
                             const datetime bottom_time)     // زمان C1-SW یا C1-FSMS-SW
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

   g_srm_up_bottom_time     = bottom_time;

   g_srm_up_unmit_active      = false;
   g_srm_up_unmit_break_seen  = false;
   g_srm_up_unmit_break_idx   = -1;
   g_srm_up_unmit_break_time  = 0;
   g_srm_up_unmit_deep_idx    = -1;
   g_srm_up_unmit_deep_price  = 0.0;
   g_srm_up_unmit_drawn       = false;

   FSMS_SW_CaptureCurrentMinorBinding(g_srm_up_origin_minor,
                                      g_srm_up_origin_minor_dir,
                                      g_srm_up_origin_minor_start);

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
                             const bool created_by_body,
                             const datetime top_time)        // زمان C1-SW یا C1-FSMS-SW (لبه بالایی SR)
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

   g_srm_dn_top_time        = top_time;

   g_srm_dn_unmit_active      = false;
   g_srm_dn_unmit_break_seen  = false;
   g_srm_dn_unmit_break_idx   = -1;
   g_srm_dn_unmit_break_time  = 0;
   g_srm_dn_unmit_deep_idx    = -1;
   g_srm_dn_unmit_deep_price  = 0.0;
   g_srm_dn_unmit_drawn       = false;

   FSMS_SW_CaptureCurrentMinorBinding(g_srm_dn_origin_minor,
                                      g_srm_dn_origin_minor_dir,
                                      g_srm_dn_origin_minor_start);

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

      // شروع اسکن unmit / deepest SR mitigation برای این SR (UP)
      g_srm_up_unmit_active      = true;
      g_srm_up_unmit_break_seen  = false;
      g_srm_up_unmit_break_idx   = -1;
      g_srm_up_unmit_break_time  = 0;
      g_srm_up_unmit_deep_idx    = -1;
      g_srm_up_unmit_deep_price  = 0.0;
      g_srm_up_unmit_drawn       = false;
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

      // شروع اسکن unmit / deepest SR mitigation برای این SR (DOWN)
      g_srm_dn_unmit_active      = true;
      g_srm_dn_unmit_break_seen  = false;
      g_srm_dn_unmit_break_idx   = -1;
      g_srm_dn_unmit_break_time  = 0;
      g_srm_dn_unmit_deep_idx    = -1;
      g_srm_dn_unmit_deep_price  = 0.0;
      g_srm_dn_unmit_drawn       = false;
   }
}

// -------------------- Per-bar scan (earliest-first + post-mark draw) --------------------

// UP
// UP
inline void SR_Mitigator_OnBar_UP(const MqlRates &rates[], const int n, const int j)
{
   if(!g_srm_up_active) return;
   if(j < 0 || j >= n)  return;

   if(__SRMIT_MinorExpired_UP(rates[j].time))
   {
      SRMIT_Reset_UP();
      return;
   }

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

   // --------- بعد از مشخص شدن SR U HH ⇒ اسکن برای deepest SR mitigation و unmit ---------
   if(g_srm_up_ext_drawn && g_srm_up_unmit_active)
   {
      int fromIdx = g_srm_up_ext_idx;

      // *** قانون جدید کلی ***
      // اگر کندل سازنده strong range همان کندلی باشد که SR U HH روی آن ثبت شده است
      // (چه strong range با شدو ساخته شده باشد و چه با بدنه)،
      // بازهٔ جست‌وجوی deepest SR mitigation از کندل بعدی شروع می‌شود.
      if(g_srm_up_created_idx >= 0 &&
         g_srm_up_ext_idx      >= 0 &&
         g_srm_up_ext_idx      == g_srm_up_created_idx)
      {
         fromIdx = g_srm_up_ext_idx + 1;
      }

      if(fromIdx >= 0 && fromIdx < n && j >= fromIdx)
      {
         const double eps    = __SRMIT_EPS();
         const double hh     = g_srm_up_ext_price;   // سطح SR U HH
         const double bottom = g_srm_up_bottom;      // Low(C1-SW / C1-FSMS-SW)

         // تا وقتی اولین شکست HH دیده نشده:
         if(!g_srm_up_unmit_break_seen)
         {
            // شرط ۱: اگر قبل از شکست HH، low کندلی، low C1-SW/FSMS-SW را بشکند ⇒ اسکن unmit باطل
            if(rates[j].low < bottom - eps)
            {
               g_srm_up_unmit_active = false;   // دیگر unmit برای این SR محاسبه نمی‌شود
            }
            else
            {
               // شرط ۲: اولین شکست SR U HH به بالا (wick یا body)
               // شرط ۲: اولین شکست SR U HH به بالا (wick یا body)
               if(rates[j].high > hh + eps || rates[j].close > hh + eps)
               {
                  g_srm_up_unmit_break_seen = true;
                  g_srm_up_unmit_break_idx  = j;
                  g_srm_up_unmit_break_time = rates[j].time;
               
                  // --- ماکر کندل «ghable gooz baghali» (UP) کنار کندل breaker ---
                  double span_gb = rates[j].high - rates[j].low;
                  if(span_gb <= 0.0) span_gb = 10 * _Point;
                  double pad_gb = span_gb * 0.20;
                  if(pad_gb < 3 * _Point) pad_gb = 3 * _Point;
                  double y_gb = rates[j].high + pad_gb;
               
                  string gb_name = "ghable_gooz_baghali_U_" + IntegerToString(g_srm_up_id);
                  // متن "GGBU" قابل تغییر است؛ فقط برای تمایز ghable gooz baghali گذاشتم
                  MarkCandleText(gb_name, rates[j].time, y_gb, "GGBU", clrMagenta);
               
                  // عمیق‌ترین نفوذ به strong range در بازه [fromIdx . اولین کندل breaker]
                  double deepest = DBL_MAX;
                  int    deepIdx = -1;
                  for(int k = fromIdx; k <= g_srm_up_unmit_break_idx; ++k)
                  {
                     const double l = rates[k].low;
                     if(l < deepest)
                     {
                        deepest = l;
                        deepIdx = k;
                     }
                  }
               
                  if(deepIdx >= 0)
                  {
                     g_srm_up_unmit_deep_idx   = deepIdx;
                     g_srm_up_unmit_deep_price = deepest;

                     // 1) مارکر عمودی deepest SR mitigation
                     string tag  = IntegerToString(g_srm_up_id);
                     string base = "deepest_SR_mitigation_U_"+tag;
                     __SRMIT_DrawV(base, rates[deepIdx].time);

                     // 2) مستطیل unmitigated SR:
                     //    - از نظر قیمتی: [low C1-SW/FSMS-SW . deepest SR mitigation]
                     //    - از نظر زمانی: از کندل C1-SW/FSMS-SW تا خود کندل deepest
                     //      (لبه راست مستطیل = خود کندل deepest SR mitigation)
                     string   rbase   = "unmitigated_SR_U_"+tag;
                     datetime t_left  = g_srm_up_bottom_time;     // لبه چپ = C1-SW یا C1-FSMS-SW
                     datetime t_right = rates[deepIdx].time;      // لبه راست = خود کندل deepest SR mitigation
                     __SRMIT_DrawUnmitRect(rbase,
                                           t_left,
                                           g_srm_up_unmit_deep_price,  // top
                                           t_right,
                                           bottom);                     // bottom

                     // 3) خط افقی ۲۰ کندلی روی سطح deepest SR mitigation
                     //    این همان سطحی است که اگر دوباره به پایین شکسته شود، کندل gooz baghali ساخته می‌شود
                     __SRMIT_DrawDeepestLine_UP(rates, n, deepIdx, g_srm_up_unmit_deep_price);

                     g_srm_up_unmit_drawn = true;
                  }
                                
                  // بعد از اولین شکست SR U HH (صرف‌نظر از موفق بودن اسکن) دیگر unmit فعال نیست
                  g_srm_up_unmit_active = false;
               }
            }
         }
      }
   }
}

// DOWN
inline void SR_Mitigator_OnBar_DOWN(const MqlRates &rates[], const int n, const int j)
{
   if(!g_srm_dn_active) return;
   if(j < 0 || j >= n)  return;

   if(__SRMIT_MinorExpired_DN(rates[j].time))
   {
      SRMIT_Reset_DN();
      return;
   }

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

   // --------- حالت نزولی آینه‌ای برای unmitigated SR ---------
   if(g_srm_dn_ext_drawn && g_srm_dn_unmit_active)
   {
      int fromIdx = g_srm_dn_ext_idx;

      // *** قانون جدید کلی (آینه‌ای) ***
      // اگر کندل سازنده strong range همان کندلی باشد که SR D LL روی آن ثبت شده است
      // (چه شکست اولیه با شدو بوده باشد و چه با بدنه)،
      // بازهٔ deepest SR mitigation از کندل بعدی شروع می‌شود.
      if(g_srm_dn_created_idx >= 0 &&
         g_srm_dn_ext_idx      >= 0 &&
         g_srm_dn_ext_idx      == g_srm_dn_created_idx)
      {
         fromIdx = g_srm_dn_ext_idx + 1;
      }

      if(fromIdx >= 0 && fromIdx < n && j >= fromIdx)
      {
         const double eps = __SRMIT_EPS();
         const double ll  = g_srm_dn_ext_price;  // سطح SR D LL
         const double top = g_srm_dn_top;        // High(C1-SW / C1-FSMS-SW)

         if(!g_srm_dn_unmit_break_seen)
         {
            // اگر قبل از شکست LL، high کندلی، high C1-SW/FSMS-SW را بشکند ⇒ unmit باطل
            if(rates[j].high > top + eps)
            {
               g_srm_dn_unmit_active = false;
            }
            else
            {
               // اولین شکست SR D LL به پایین (wick یا body)
               // اولین شکست SR D LL به پایین (wick یا body)
               if(rates[j].low < ll - eps || rates[j].close < ll - eps)
               {
                  g_srm_dn_unmit_break_seen = true;
                  g_srm_dn_unmit_break_idx  = j;
                  g_srm_dn_unmit_break_time = rates[j].time;
               
                  // --- ماکر کندل «ghable gooz baghali» (DOWN) کنار کندل breaker ---
                  double span_gb = rates[j].high - rates[j].low;
                  if(span_gb <= 0.0) span_gb = 10 * _Point;
                  double pad_gb = span_gb * 0.20;
                  if(pad_gb < 3 * _Point) pad_gb = 3 * _Point;
                  double y_gb = rates[j].low - pad_gb;
               
                  string gb_name = "ghable_gooz_baghali_D_" + IntegerToString(g_srm_dn_id);
                  MarkCandleText(gb_name, rates[j].time, y_gb, "GGBD", clrMagenta);
               
                  // deepest SR mitigation (حالت نزولی) = بیشترین High در بازه [fromIdx . breaker]
                  double deepestH = -DBL_MAX;
                  int    deepIdx  = -1;
                  for(int k = fromIdx; k <= g_srm_dn_unmit_break_idx; ++k)
                  {
                     const double h = rates[k].high;
                     if(h > deepestH)
                     {
                        deepestH = h;
                        deepIdx  = k;
                     }
                  }
               
                  if(deepIdx >= 0)
                  {
                     g_srm_dn_unmit_deep_idx   = deepIdx;
                     g_srm_dn_unmit_deep_price = deepestH;

                     // 1) مارکر عمودی deepest SR mitigation (DOWN)
                     string tag  = IntegerToString(g_srm_dn_id);
                     string base = "deepest_SR_mitigation_D_"+tag;
                     __SRMIT_DrawV(base, rates[deepIdx].time);

                     // 2) مستطیل unmitigated SR (DOWN):
                     //    - قیمتی: [deepestHigh . high C1-SW/FSMS-SW]
                     //    - زمانی: از C1-SW/FSMS-SW تا خود کندل deepest
                     //      (لبه راست مستطیل = خود کندل deepest SR mitigation)
                     string   rbase   = "unmitigated_SR_D_"+tag;
                     datetime t_left  = g_srm_dn_top_time;       // لبه چپ = کندل C1-SW یا C1-FSMS-SW
                     datetime t_right = rates[deepIdx].time;     // لبه راست = خود کندل deepest SR mitigation
                     __SRMIT_DrawUnmitRect(rbase,
                                           t_left,
                                           top,                      // top
                                           t_right,
                                           g_srm_dn_unmit_deep_price // bottom
                                           );

                     // 3) خط افقی ۲۰ کندلی روی سطح deepest SR mitigation (DOWN)
                     //    این همان سطحی است که اگر دوباره به بالا شکسته شود (آینه‌ای)، gooz baghali ساخته می‌شود
                     __SRMIT_DrawDeepestLine_DN(rates, n, deepIdx, g_srm_dn_unmit_deep_price);

                     g_srm_dn_unmit_drawn = true;
                  }

                  g_srm_dn_unmit_active = false;
               }
            }
         }
      }
   }
}

#endif // WAVEBOT_SR_MITIGATOR_MQH
