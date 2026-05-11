
// WaveBot/SR_GoozBaghali.mqh
// WaveBot/SR_GoozBaghali.mqh
#ifndef WAVEBOT_SR_GOOZBAGHALI_MQH
#define WAVEBOT_SR_GOOZBAGHALI_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/SR_Mitigator.mqh>     // وضعیت unmitigated SR (از SR_Mitigator)
#include <WaveBot/FSMS_SW.mqh>          // Minor session expiry helpers
#include <WaveBot/RaceCoordinator.mqh>  // زمان‌های MTC UP/DN BB
#include <WaveBot/Markers.mqh>          // MarkCandleText و ...

// =========================================================
//   ساختارهای چند‑SR برای gooz baghali
//   هر unmit SR مستقل ذخیره و پایش می‌شود
// =========================================================

struct SRGB_UnmitZone
{
   bool     used;          // اگر false باشد این خانه آزاد است
   bool     gbu_marked;    // آیا برای این ناحیه GBU/GBD رسم شده؟
   int      sr_id;         // همان g_srm_up_id / g_srm_dn_id
   double   price_bottom;  // کف ناحیه unmit
   double   price_top;     // سقف ناحیه unmit
   datetime break_time;    // زمان GGBU / GGBD (اولین شکست deepest SR)

   // lineage ownership
   bool     origin_minor;
   int      origin_minor_dir;      // 0=UP, 1=DOWN
   datetime origin_minor_start;    // starter_time همان session مینور
};

// لیست نواحی unmit برای UP و DOWN
static SRGB_UnmitZone g_srgb_up_zones[];
static SRGB_UnmitZone g_srgb_dn_zones[];

// =========================================================
//   State فعلی (آخرین unmit برای دیباگ و اسکن ترتیبی)
// =========================================================

// -------------------- State: UP (آخرین unmit) --------------------
static bool     g_srgb_up_active        = false;
static bool     g_srgb_up_marked        = false;   // فقط برای آخرین unmit
static int      g_srgb_up_sr_id         = -1;
static double   g_srgb_up_price_top     = 0.0;
static double   g_srgb_up_price_bottom  = 0.0;
static datetime g_srgb_up_break_time    = 0;       // زمان GGBU (deepest SR break)
static bool     g_srgb_up_origin_minor = false;
static int      g_srgb_up_origin_minor_dir = -1;
static datetime g_srgb_up_origin_minor_start = 0;

// شمارنده‌ی یکتاساز نام کندل‌های GBU
static int      g_srgb_up_counter       = 0;

// دیباگ: شماره‌گذاری کندل‌های بعد از GGBU (۱..۳۰)
static datetime g_srgb_up_dbg_break_time = 0;
static int      g_srgb_up_dbg_seq_id     = 0;
static int      g_srgb_up_dbg_counter    = 0;
static bool     g_srgb_up_dbg_active     = false;

// آخرین اندیسی که برای UP پردازش شده (اسکن ترتیبی مستقل)
static int      g_srgb_up_last_index     = -1;

// -------------------- State: DOWN (آخرین unmit) --------------------
static bool     g_srgb_dn_active        = false;
static bool     g_srgb_dn_marked        = false;
static int      g_srgb_dn_sr_id         = -1;
static double   g_srgb_dn_price_top     = 0.0;
static double   g_srgb_dn_price_bottom  = 0.0;
static datetime g_srgb_dn_break_time    = 0;       // زمان GGBD
static bool     g_srgb_dn_origin_minor = false;
static int      g_srgb_dn_origin_minor_dir = -1;
static datetime g_srgb_dn_origin_minor_start = 0;

// شمارنده‌ی یکتاساز نام کندل‌های GBD
static int      g_srgb_dn_counter       = 0;

// دیباگ: شماره‌گذاری کندل‌های بعد از GGBD
static datetime g_srgb_dn_dbg_break_time = 0;
static int      g_srgb_dn_dbg_seq_id     = 0;
static int      g_srgb_dn_dbg_counter    = 0;
static bool     g_srgb_dn_dbg_active     = false;

// آخرین اندیسی که برای DOWN پردازش شده
static int      g_srgb_dn_last_index     = -1;

// ------------------------------
// Context snapshot for SR_GoozBaghali (UP + DOWN)
// ------------------------------
struct SRGBContext
{
   // نواحی unmit برای UP و DOWN
   SRGB_UnmitZone up_zones[];
   SRGB_UnmitZone dn_zones[];

   // -------------------- State: UP (آخرین unmit) --------------------
   bool     up_active;
   bool     up_marked;
   int      up_sr_id;
   double   up_price_top;
   double   up_price_bottom;
   datetime up_break_time;      // زمان GGBU (deepest SR break)
   bool     up_origin_minor;
   int      up_origin_minor_dir;
   datetime up_origin_minor_start;

   // شمارنده‌ی یکتاساز نام کندل‌های GBU
   int      up_counter;

   // دیباگ: شماره‌گذاری کندل‌های بعد از GGBU (۱..۳۰)
   datetime up_dbg_break_time;
   int      up_dbg_seq_id;
   int      up_dbg_counter;
   bool     up_dbg_active;

   // آخرین اندیسی که برای UP پردازش شده (اسکن ترتیبی مستقل)
   int      up_last_index;

   // -------------------- State: DOWN (آخرین unmit) --------------------
   bool     dn_active;
   bool     dn_marked;
   int      dn_sr_id;
   double   dn_price_top;
   double   dn_price_bottom;
   datetime dn_break_time;      // زمان GGBD
   bool     dn_origin_minor;
   int      dn_origin_minor_dir;
   datetime dn_origin_minor_start;

   // شمارنده‌ی یکتاساز نام کندل‌های GBD
   int      dn_counter;

   // دیباگ: شماره‌گذاری کندل‌های بعد از GGBD
   datetime dn_dbg_break_time;
   int      dn_dbg_seq_id;
   int      dn_dbg_counter;
   bool     dn_dbg_active;

   // آخرین اندیسی که برای DOWN پردازش شده
   int      dn_last_index;
};

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
inline void SRGB_ContextInit(SRGBContext &ctx)
{
   // آرایه‌های نواحی unmit
   ArrayResize(ctx.up_zones, 0);
   ArrayResize(ctx.dn_zones, 0);

   // UP
   ctx.up_active        = false;
   ctx.up_marked        = false;
   ctx.up_sr_id         = -1;
   ctx.up_price_top     = 0.0;
   ctx.up_price_bottom  = 0.0;
   ctx.up_break_time    = 0;
   ctx.up_origin_minor      = false;
   ctx.up_origin_minor_dir  = -1;
   ctx.up_origin_minor_start= 0;

   ctx.up_counter       = 0;

   ctx.up_dbg_break_time = 0;
   ctx.up_dbg_seq_id     = 0;
   ctx.up_dbg_counter    = 0;
   ctx.up_dbg_active     = false;

   ctx.up_last_index     = -1;

   // DOWN
   ctx.dn_active        = false;
   ctx.dn_marked        = false;
   ctx.dn_sr_id         = -1;
   ctx.dn_price_top     = 0.0;
   ctx.dn_price_bottom  = 0.0;
   ctx.dn_break_time    = 0;
   ctx.dn_origin_minor      = false;
   ctx.dn_origin_minor_dir  = -1;
   ctx.dn_origin_minor_start= 0;

   ctx.dn_counter       = 0;

   ctx.dn_dbg_break_time = 0;
   ctx.dn_dbg_seq_id     = 0;
   ctx.dn_dbg_counter    = 0;
   ctx.dn_dbg_active     = false;

   ctx.dn_last_index     = -1;
}

// Export: کپی وضعیت فعلی globalها به داخل کانتکست
inline void SRGB_ContextExport(SRGBContext &ctx)
{
   // آرایه‌های نواحی unmit
   ArrayCopy(ctx.up_zones, g_srgb_up_zones);
   ArrayCopy(ctx.dn_zones, g_srgb_dn_zones);

   // UP
   ctx.up_active        = g_srgb_up_active;
   ctx.up_marked        = g_srgb_up_marked;
   ctx.up_sr_id         = g_srgb_up_sr_id;
   ctx.up_price_top     = g_srgb_up_price_top;
   ctx.up_price_bottom  = g_srgb_up_price_bottom;
   ctx.up_break_time    = g_srgb_up_break_time;
   ctx.up_origin_minor      = g_srgb_up_origin_minor;
   ctx.up_origin_minor_dir  = g_srgb_up_origin_minor_dir;
   ctx.up_origin_minor_start= g_srgb_up_origin_minor_start;

   ctx.up_counter       = g_srgb_up_counter;

   ctx.up_dbg_break_time = g_srgb_up_dbg_break_time;
   ctx.up_dbg_seq_id     = g_srgb_up_dbg_seq_id;
   ctx.up_dbg_counter    = g_srgb_up_dbg_counter;
   ctx.up_dbg_active     = g_srgb_up_dbg_active;

   ctx.up_last_index     = g_srgb_up_last_index;

   // DOWN
   ctx.dn_active        = g_srgb_dn_active;
   ctx.dn_marked        = g_srgb_dn_marked;
   ctx.dn_sr_id         = g_srgb_dn_sr_id;
   ctx.dn_price_top     = g_srgb_dn_price_top;
   ctx.dn_price_bottom  = g_srgb_dn_price_bottom;
   ctx.dn_break_time    = g_srgb_dn_break_time;
   ctx.dn_origin_minor      = g_srgb_dn_origin_minor;
   ctx.dn_origin_minor_dir  = g_srgb_dn_origin_minor_dir;
   ctx.dn_origin_minor_start= g_srgb_dn_origin_minor_start;

   ctx.dn_counter       = g_srgb_dn_counter;

   ctx.dn_dbg_break_time = g_srgb_dn_dbg_break_time;
   ctx.dn_dbg_seq_id     = g_srgb_dn_dbg_seq_id;
   ctx.dn_dbg_counter    = g_srgb_dn_dbg_counter;
   ctx.dn_dbg_active     = g_srgb_dn_dbg_active;

   ctx.dn_last_index     = g_srgb_dn_last_index;
}

// Import: برگرداندن وضعیت ذخیره‌شدهٔ کانتکست به متغیرهای global
inline void SRGB_ContextImport(const SRGBContext &ctx)
{
   // آرایه‌های نواحی unmit
   ArrayCopy(g_srgb_up_zones, ctx.up_zones);
   ArrayCopy(g_srgb_dn_zones, ctx.dn_zones);

   // UP
   g_srgb_up_active        = ctx.up_active;
   g_srgb_up_marked        = ctx.up_marked;
   g_srgb_up_sr_id         = ctx.up_sr_id;
   g_srgb_up_price_top     = ctx.up_price_top;
   g_srgb_up_price_bottom  = ctx.up_price_bottom;
   g_srgb_up_break_time    = ctx.up_break_time;
   g_srgb_up_origin_minor      = ctx.up_origin_minor;
   g_srgb_up_origin_minor_dir  = ctx.up_origin_minor_dir;
   g_srgb_up_origin_minor_start= ctx.up_origin_minor_start;

   g_srgb_up_counter       = ctx.up_counter;

   g_srgb_up_dbg_break_time = ctx.up_dbg_break_time;
   g_srgb_up_dbg_seq_id     = ctx.up_dbg_seq_id;
   g_srgb_up_dbg_counter    = ctx.up_dbg_counter;
   g_srgb_up_dbg_active     = ctx.up_dbg_active;

   g_srgb_up_last_index     = ctx.up_last_index;

   // DOWN
   g_srgb_dn_active        = ctx.dn_active;
   g_srgb_dn_marked        = ctx.dn_marked;
   g_srgb_dn_sr_id         = ctx.dn_sr_id;
   g_srgb_dn_price_top     = ctx.dn_price_top;
   g_srgb_dn_price_bottom  = ctx.dn_price_bottom;
   g_srgb_dn_break_time    = ctx.dn_break_time;
   g_srgb_dn_origin_minor      = ctx.dn_origin_minor;
   g_srgb_dn_origin_minor_dir  = ctx.dn_origin_minor_dir;
   g_srgb_dn_origin_minor_start= ctx.dn_origin_minor_start;

   g_srgb_dn_counter       = ctx.dn_counter;

   g_srgb_dn_dbg_break_time = ctx.dn_dbg_break_time;
   g_srgb_dn_dbg_seq_id     = ctx.dn_dbg_seq_id;
   g_srgb_dn_dbg_counter    = ctx.dn_dbg_counter;
   g_srgb_dn_dbg_active     = ctx.dn_dbg_active;

   g_srgb_dn_last_index     = ctx.dn_last_index;
}

// ریست کامل وضعیت SR_GoozBaghali در world فعلی
inline void SRGB_ResetGlobals()
{
   // از ریست کامل خود ماژول استفاده می‌کنیم
   SR_GoozBaghali_ResetAll();
}

// =========================================================
//   Reset helpers
// =========================================================

inline void SRGB_Reset_UP()
{
   g_srgb_up_active        = false;
   g_srgb_up_marked        = false;
   g_srgb_up_sr_id         = -1;
   g_srgb_up_price_top     = 0.0;
   g_srgb_up_price_bottom  = 0.0;
   g_srgb_up_break_time    = 0;
   g_srgb_up_origin_minor      = false;
   g_srgb_up_origin_minor_dir  = -1;
   g_srgb_up_origin_minor_start= 0;

   g_srgb_up_last_index    = -1;

   g_srgb_up_dbg_active     = false;
   g_srgb_up_dbg_break_time = 0;
   g_srgb_up_dbg_counter    = 0;
}

inline void SRGB_Reset_DN()
{
   g_srgb_dn_active        = false;
   g_srgb_dn_marked        = false;
   g_srgb_dn_sr_id         = -1;
   g_srgb_dn_price_top     = 0.0;
   g_srgb_dn_price_bottom  = 0.0;
   g_srgb_dn_break_time    = 0;
   g_srgb_dn_origin_minor      = false;
   g_srgb_dn_origin_minor_dir  = -1;
   g_srgb_dn_origin_minor_start= 0;

   g_srgb_dn_last_index    = -1;

   g_srgb_dn_dbg_active     = false;
   g_srgb_dn_dbg_break_time = 0;
   g_srgb_dn_dbg_counter    = 0;
}

// ریست کامل همهٔ نواحی و استیت‌ها (برای SR_DeleteAllObjects)
inline void SR_GoozBaghali_ResetAll()
{
   SRGB_Reset_UP();
   SRGB_Reset_DN();

   g_srgb_up_counter = 0;
   g_srgb_dn_counter = 0;

   g_srgb_up_dbg_seq_id = 0;
   g_srgb_dn_dbg_seq_id = 0;

   ArrayResize(g_srgb_up_zones, 0);
   ArrayResize(g_srgb_dn_zones, 0);
}


// =========================================================
//   Helper: تماس کندل با بازهٔ قیمتی
// =========================================================

inline bool __SRGB_CandleTouchesRange(const MqlRates &r,
                                      const double    bottom_in,
                                      const double    top_in)
{
   double bottom = bottom_in;
   double top    = top_in;

   if(bottom > top)
   {
      double tmp = bottom;
      bottom     = top;
      top        = tmp;
   }

   if(bottom <= 0.0 || top <= 0.0)
      return false;

   const double eps = __SRMIT_EPS();

   // هر تداخل بین ویک/بدنه با بازه [bottom, top]
   if(r.low  <= top + eps &&
      r.high >= bottom - eps)
      return true;

   return false;
}


// =========================================================
//   Array helpers: ثبت چند unmit SR (UP / DOWN)
// =========================================================

inline int SRGB_FindZoneIndex_UP(const int sr_id,
                                 const datetime brk_time)
{
   const int count = ArraySize(g_srgb_up_zones);
   for(int i = 0; i < count; ++i)
   {
      if(!g_srgb_up_zones[i].used) continue;
      if(g_srgb_up_zones[i].sr_id == sr_id &&
         g_srgb_up_zones[i].break_time == brk_time)
         return i;
   }
   return -1;
}

inline void SRGB_RegisterUnmit_UP(const int       sr_id,
                                  const double    price_bottom,
                                  const double    price_top,
                                  const datetime  brk_time,
                                  const bool      origin_minor,
                                  const int       origin_minor_dir,
                                  const datetime  origin_minor_start)
{
   int idx = SRGB_FindZoneIndex_UP(sr_id, brk_time);
   if(idx < 0)
   {
      int count = ArraySize(g_srgb_up_zones);
      ArrayResize(g_srgb_up_zones, count + 1);
      idx = count;
   }

   g_srgb_up_zones[idx].used               = true;
   g_srgb_up_zones[idx].gbu_marked         = false;
   g_srgb_up_zones[idx].sr_id              = sr_id;
   g_srgb_up_zones[idx].price_bottom       = price_bottom;
   g_srgb_up_zones[idx].price_top          = price_top;
   g_srgb_up_zones[idx].break_time         = brk_time;
   g_srgb_up_zones[idx].origin_minor       = origin_minor;
   g_srgb_up_zones[idx].origin_minor_dir   = origin_minor_dir;
   g_srgb_up_zones[idx].origin_minor_start = origin_minor_start;
}

inline int SRGB_FindZoneIndex_DN(const int sr_id,
                                 const datetime brk_time)
{
   const int count = ArraySize(g_srgb_dn_zones);
   for(int i = 0; i < count; ++i)
   {
      if(!g_srgb_dn_zones[i].used) continue;
      if(g_srgb_dn_zones[i].sr_id == sr_id &&
         g_srgb_dn_zones[i].break_time == brk_time)
         return i;
   }
   return -1;
}

inline void SRGB_RegisterUnmit_DN(const int       sr_id,
                                  const double    price_bottom,
                                  const double    price_top,
                                  const datetime  brk_time,
                                  const bool      origin_minor,
                                  const int       origin_minor_dir,
                                  const datetime  origin_minor_start)
{
   int idx = SRGB_FindZoneIndex_DN(sr_id, brk_time);
   if(idx < 0)
   {
      int count = ArraySize(g_srgb_dn_zones);
      ArrayResize(g_srgb_dn_zones, count + 1);
      idx = count;
   }

   g_srgb_dn_zones[idx].used               = true;
   g_srgb_dn_zones[idx].gbu_marked         = false;
   g_srgb_dn_zones[idx].sr_id              = sr_id;
   g_srgb_dn_zones[idx].price_bottom       = price_bottom;
   g_srgb_dn_zones[idx].price_top          = price_top;
   g_srgb_dn_zones[idx].break_time         = brk_time;
   g_srgb_dn_zones[idx].origin_minor       = origin_minor;
   g_srgb_dn_zones[idx].origin_minor_dir   = origin_minor_dir;
   g_srgb_dn_zones[idx].origin_minor_start = origin_minor_start;
}

inline bool __SRGB_ZoneMinorExpired(const SRGB_UnmitZone &z,
                                    const datetime asof_time)
{
   if(!z.origin_minor) return false;
   return FSMS_SW_IsMinorLineageExpired(z.origin_minor_dir,
                                        z.origin_minor_start,
                                        asof_time);
}

inline void SRGB_ExpireMinorLineages(const int dir_code,
                                     const datetime starter_time)
{
   if(starter_time <= 0) return;

   int up_count = ArraySize(g_srgb_up_zones);
   for(int i=0; i<up_count; ++i)
   {
      if(!g_srgb_up_zones[i].used) continue;
      if(!g_srgb_up_zones[i].origin_minor) continue;
      if(g_srgb_up_zones[i].origin_minor_dir != dir_code) continue;
      if(g_srgb_up_zones[i].origin_minor_start != starter_time) continue;
      g_srgb_up_zones[i].used = false;
   }

   int dn_count = ArraySize(g_srgb_dn_zones);
   for(int j=0; j<dn_count; ++j)
   {
      if(!g_srgb_dn_zones[j].used) continue;
      if(!g_srgb_dn_zones[j].origin_minor) continue;
      if(g_srgb_dn_zones[j].origin_minor_dir != dir_code) continue;
      if(g_srgb_dn_zones[j].origin_minor_start != starter_time) continue;
      g_srgb_dn_zones[j].used = false;
   }

   if(g_srgb_up_origin_minor &&
      g_srgb_up_origin_minor_dir == dir_code &&
      g_srgb_up_origin_minor_start == starter_time)
   {
      SRGB_Reset_UP();
   }

   if(g_srgb_dn_origin_minor &&
      g_srgb_dn_origin_minor_dir == dir_code &&
      g_srgb_dn_origin_minor_start == starter_time)
   {
      SRGB_Reset_DN();
   }
}


// =========================================================
//   Sync از SR_Mitigator (آخرین unmit فعال) + ثبت در آرایه‌ها
// =========================================================

inline void __SRGB_SyncFromMitigator_UP()
{
   if(g_srm_up_unmit_drawn)
   {
      // unmit جدید اگر SR_id یا break_time عوض شده باشد
      if(!g_srgb_up_active ||
         g_srgb_up_sr_id      != g_srm_up_id ||
         g_srgb_up_break_time != g_srm_up_unmit_break_time)
      {
         g_srgb_up_active       = true;
         g_srgb_up_marked       = false;
         g_srgb_up_sr_id        = g_srm_up_id;

         // ناحیه unmit در حالت UP:
         // bottom = Low(C1-SW / C1-FSMS-SW)
         // top    = deepest SR mitigation
         g_srgb_up_price_bottom = g_srm_up_bottom;
         g_srgb_up_price_top    = g_srm_up_unmit_deep_price;

         if(g_srgb_up_price_bottom > g_srgb_up_price_top)
         {
            double tmp             = g_srgb_up_price_bottom;
            g_srgb_up_price_bottom = g_srgb_up_price_top;
            g_srgb_up_price_top    = tmp;
         }

         g_srgb_up_break_time = g_srm_up_unmit_break_time;
         g_srgb_up_origin_minor = SRMIT_UP_IsMinorOrigin();
         g_srgb_up_origin_minor_dir = SRMIT_UP_MinorDirCode();
         g_srgb_up_origin_minor_start = SRMIT_UP_MinorStarterTime();

         // ریست اسکن و دیباگ برای این unmit جدید
         g_srgb_up_last_index     = -1;
         g_srgb_up_dbg_active     = false;
         g_srgb_up_dbg_break_time = 0;
         g_srgb_up_dbg_counter    = 0;

         // ثبت در لیست نواحی چندگانه
         SRGB_RegisterUnmit_UP(g_srgb_up_sr_id,
                               g_srgb_up_price_bottom,
                               g_srgb_up_price_top,
                               g_srgb_up_break_time,
                               g_srgb_up_origin_minor,
                               g_srgb_up_origin_minor_dir,
                               g_srgb_up_origin_minor_start);
      }
   }
   else
   {
      if(g_srgb_up_active)
         SRGB_Reset_UP();
   }
}

inline void __SRGB_SyncFromMitigator_DN()
{
   if(g_srm_dn_unmit_drawn)
   {
      if(!g_srgb_dn_active ||
         g_srgb_dn_sr_id      != g_srm_dn_id ||
         g_srgb_dn_break_time != g_srm_dn_unmit_break_time)
      {
         g_srgb_dn_active       = true;
         g_srgb_dn_marked       = false;
         g_srgb_dn_sr_id        = g_srm_dn_id;

         // ناحیه unmit در حالت DOWN:
         // bottom = deepest SR mitigation
         // top    = High(C1-SW / C1-FSMS-SW)
         g_srgb_dn_price_bottom = g_srm_dn_unmit_deep_price;
         g_srgb_dn_price_top    = g_srm_dn_top;

         if(g_srgb_dn_price_bottom > g_srgb_dn_price_top)
         {
            double tmp              = g_srgb_dn_price_bottom;
            g_srgb_dn_price_bottom  = g_srgb_dn_price_top;
            g_srgb_dn_price_top     = tmp;
         }

         g_srgb_dn_break_time = g_srm_dn_unmit_break_time;
         g_srgb_dn_origin_minor = SRMIT_DN_IsMinorOrigin();
         g_srgb_dn_origin_minor_dir = SRMIT_DN_MinorDirCode();
         g_srgb_dn_origin_minor_start = SRMIT_DN_MinorStarterTime();

         g_srgb_dn_last_index     = -1;
         g_srgb_dn_dbg_active     = false;
         g_srgb_dn_dbg_break_time = 0;
         g_srgb_dn_dbg_counter    = 0;

         // ثبت در لیست چند unmit
         SRGB_RegisterUnmit_DN(g_srgb_dn_sr_id,
                               g_srgb_dn_price_bottom,
                               g_srgb_dn_price_top,
                               g_srgb_dn_break_time,
                               g_srgb_dn_origin_minor,
                               g_srgb_dn_origin_minor_dir,
                               g_srgb_dn_origin_minor_start);
      }
   }
   else
   {
      if(g_srgb_dn_active)
         SRGB_Reset_DN();
   }
}


// =========================================================
//   دیباگ: شماره‌گذاری کندل‌های بعد از GGBU / GGBD
// =========================================================

inline void __SRGB_DebugNumberAfterBreak_UP(const MqlRates &rates[],
                                            const int       n,
                                            const int       j)
{
   if(!InpDrawMarkers) return;
   if(j < 0 || j >= n) return;
   if(!g_srgb_up_active) return;

   const datetime brk = g_srgb_up_break_time;
   if(brk <= 0) return;

   // اگر GGBU جدیدی آمده، سکانس دیباگ جدید
   if(!g_srgb_up_dbg_active || brk != g_srgb_up_dbg_break_time)
   {
      g_srgb_up_dbg_active     = true;
      g_srgb_up_dbg_break_time = brk;
      g_srgb_up_dbg_counter    = 0;
      ++g_srgb_up_dbg_seq_id;
   }

   const MqlRates r = rates[j];

   if(r.time <= g_srgb_up_dbg_break_time)
      return;

   if(g_srgb_up_dbg_counter >= 30)
      return;

   ++g_srgb_up_dbg_counter;
   const int k = g_srgb_up_dbg_counter;

   // فقط عدد خالی لازم است؛ نام و رسم را فعلاً کامنت می‌گذاریم
   //string tag  = IntegerToString(k);
   //string name = "GGBU_SEQ_U_"
   //              + IntegerToString(g_srgb_up_sr_id)
   //              + "_"
   //              + IntegerToString(g_srgb_up_dbg_seq_id)
   //              + "_"
   //              + tag;

   double span = r.high - r.low;
   if(span <= 0.0) span = 10 * _Point;
   double pad = span * 0.20;
   if(pad < 3 * _Point) pad = 3 * _Point;
   double y = r.high + pad;

   //MarkCandleText(name, r.time, y, tag, clrWhite);
}

inline void __SRGB_DebugNumberAfterBreak_DN(const MqlRates &rates[],
                                            const int       n,
                                            const int       j)
{
   if(!InpDrawMarkers) return;
   if(j < 0 || j >= n) return;
   if(!g_srgb_dn_active) return;

   const datetime brk = g_srgb_dn_break_time;
   if(brk <= 0) return;

   if(!g_srgb_dn_dbg_active || brk != g_srgb_dn_dbg_break_time)
   {
      g_srgb_dn_dbg_active     = true;
      g_srgb_dn_dbg_break_time = brk;
      g_srgb_dn_dbg_counter    = 0;
      ++g_srgb_dn_dbg_seq_id;
   }

   const MqlRates r = rates[j];

   if(r.time <= g_srgb_dn_dbg_break_time)
      return;

   if(g_srgb_dn_dbg_counter >= 30)
      return;

   ++g_srgb_dn_dbg_counter;
   const int k = g_srgb_dn_dbg_counter;

   //string tag  = IntegerToString(k);
   //string name = "GGBD_SEQ_D_"
   //              + IntegerToString(g_srgb_dn_sr_id)
   //              + "_"
   //              + IntegerToString(g_srgb_dn_dbg_seq_id)
   //              + "_"
   //              + tag;

   double span = r.high - r.low;
   if(span <= 0.0) span = 10 * _Point;
   double pad = span * 0.20;
   if(pad < 3 * _Point) pad = 3 * _Point;
   double y = r.low - pad;

   //MarkCandleText(name, r.time, y, tag, clrWhite);
}


// =========================================================
//   Main per-bar logic (UP) — اسکن مستقل + چند unmit
// =========================================================

inline void SR_GoozBaghali_OnBar_UP(const MqlRates &rates[],
                                    const int       n,
                                    int             upto_idx)
{
   if(n <= 0)   return;
   if(upto_idx < 0) return;
   if(upto_idx >= n) upto_idx = n - 1;

   // اگر back-seek شد، از اول
   if(g_srgb_up_last_index > upto_idx)
      g_srgb_up_last_index = -1;

   int start = g_srgb_up_last_index + 1;
   if(start < 0) start = 0;
   if(start > upto_idx)
   {
      g_srgb_up_last_index = upto_idx;
      return;
   }

   for(int j = start; j <= upto_idx; ++j)
   {
      // هر بار قبل از چک کردن کندل، وضعیت unmit را از SR_Mitigator سینک می‌کنیم
      __SRGB_SyncFromMitigator_UP();

      // دیباگ شماره‌گذاری کندل‌های بعد از GGBU فقط برای آخرین unmit
      __SRGB_DebugNumberAfterBreak_UP(rates, n, j);

      const MqlRates r = rates[j];

      // روی هر کندل، تمام نواحی unmit (جدیدتر به قدیمی‌تر) را چک می‌کنیم
      const int zoneCount = ArraySize(g_srgb_up_zones);
      for(int zi = zoneCount - 1; zi >= 0; --zi)   // اولویت: جدیدترین ناحیه
      {
         if(zi < 0) break;
         if(!g_srgb_up_zones[zi].used)       continue;
         if(g_srgb_up_zones[zi].gbu_marked)  continue;   // اگر قبلاً برای این ناحیه GBU زده شده، رد شو

         // کپی لوکال از ناحیه (بعد از تغییر، دوباره داخل آرایه می‌نویسیم)
         SRGB_UnmitZone z = g_srgb_up_zones[zi];

         if(__SRGB_ZoneMinorExpired(z, r.time))
         {
            z.used = false;
            g_srgb_up_zones[zi] = z;

            if(g_srgb_up_active &&
               z.sr_id == g_srgb_up_sr_id &&
               z.break_time == g_srgb_up_break_time)
            {
               SRGB_Reset_UP();
            }
            continue;
         }

         // فقط کندل‌های بعد از GGBU مخصوص این ناحیه
         if(r.time <= z.break_time)
            continue;

         // شرط "قبل از mtc dn/up bb" برای این ناحیه
         const datetime tRefUp   = Race_ActiveRef_Up_Time();
         const datetime tRefDown = Race_ActiveRef_Down_Time();

         const bool mtc_after_break_up  =
            (tRefUp   > z.break_time && tRefUp   <= r.time);
         const bool mtc_after_break_dn  =
            (tRefDown > z.break_time && tRefDown <= r.time);

         if(mtc_after_break_up || mtc_after_break_dn)
         {
            // بعد از MTC دیگر این ناحیه معتبر نیست
            z.used = false;
            // چون z فقط کپی است، باید تغییر را در آرایه برگردانیم
            g_srgb_up_zones[zi] = z;
            continue;
         }

         // آیا این کندل وارد ناحیه unmit شده؟
         if(!__SRGB_CandleTouchesRange(r, z.price_bottom, z.price_top))
            continue;

         // این کندل = اولین gooz baghali برای این ناحیه
         ++g_srgb_up_counter;
         string tag = IntegerToString(g_srgb_up_counter);

         string name = "gooz_baghali_U_"
                       + IntegerToString(z.sr_id)
                       + "_"
                       + tag;

         double span = r.high - r.low;
         if(span <= 0.0) span = 10 * _Point;
         double pad = span * 0.20;
         if(pad < 3 * _Point) pad = 3 * _Point;
         double y = r.high + pad;

         MarkCandleText(name, r.time, y, "GBU", clrMagenta);

         // NEW (H4->M15 bridge): GOOZBAGHALI is a START trigger (intrabar)
         WB15_PublishStartGooz(InpSymbol, DIR_UP, r.time, z.price_bottom, z.price_top);

         // فقط اولین برخورد این ناحیه ⇒ بعد از این کندل دیگر برای این zone، GBU تکرار نمی‌شود
         z.gbu_marked = true;
         // حتماً تغییر را در آرایه هم ذخیره می‌کنیم
         g_srgb_up_zones[zi] = z;

         // اگر این ناحیه همان آخرین unmit است، state تک‌نفره هم آپدیت شود
         if(g_srgb_up_active &&
            z.sr_id      == g_srgb_up_sr_id &&
            z.break_time == g_srgb_up_break_time)
         {
            g_srgb_up_marked = true;
         }

         // طبق قانون: روی هر کندل اگر چند ناحیه هم‌زمان برخورد داشته باشند
         // اولویت با جدیدترین است ⇒ برای بقیه نواحی همین کندل را نمی‌گیریم
         break;
      }
   }

   g_srgb_up_last_index = upto_idx;
}

// =========================================================
//   Main per-bar logic (DOWN) — اسکن مستقل + چند unmit
// =========================================================

inline void SR_GoozBaghali_OnBar_DOWN(const MqlRates &rates[],
                                      const int       n,
                                      int             upto_idx)
{
   if(n <= 0)   return;
   if(upto_idx < 0) return;
   if(upto_idx >= n) upto_idx = n - 1;

   // اگر back-seek شد، از اول
   if(g_srgb_dn_last_index > upto_idx)
      g_srgb_dn_last_index = -1;

   int start = g_srgb_dn_last_index + 1;
   if(start < 0) start = 0;
   if(start > upto_idx)
   {
      g_srgb_dn_last_index = upto_idx;
      return;
   }

   for(int j = start; j <= upto_idx; ++j)
   {
      __SRGB_SyncFromMitigator_DN();

      // دیباگ شماره‌گذاری کندل‌های بعد از GGBD
      __SRGB_DebugNumberAfterBreak_DN(rates, n, j);

      const MqlRates r = rates[j];

      const int zoneCount = ArraySize(g_srgb_dn_zones);
      for(int zi = zoneCount - 1; zi >= 0; --zi)   // جدیدترین به قدیمی‌ترین
      {
         if(zi < 0) break;
         if(!g_srgb_dn_zones[zi].used)      continue;
         if(g_srgb_dn_zones[zi].gbu_marked) continue;

         SRGB_UnmitZone z = g_srgb_dn_zones[zi];

         if(__SRGB_ZoneMinorExpired(z, r.time))
         {
            z.used = false;
            g_srgb_dn_zones[zi] = z;

            if(g_srgb_dn_active &&
               z.sr_id == g_srgb_dn_sr_id &&
               z.break_time == g_srgb_dn_break_time)
            {
               SRGB_Reset_DN();
            }
            continue;
         }

         // فقط کندل‌های بعد از GGBD مخصوص این ناحیه
         if(r.time <= z.break_time)
            continue;

         const datetime tRefUp   = Race_ActiveRef_Up_Time();
         const datetime tRefDown = Race_ActiveRef_Down_Time();

         const bool mtc_after_break_up  =
            (tRefUp   > z.break_time && tRefUp   <= r.time);
         const bool mtc_after_break_dn  =
            (tRefDown > z.break_time && tRefDown <= r.time);

         if(mtc_after_break_up || mtc_after_break_dn)
         {
            // بعد از MTC این ناحیه دیگر معتبر نیست
            z.used = false;
            g_srgb_dn_zones[zi] = z;
            continue;
         }

         // ورود کندل به ناحیه unmit
         if(!__SRGB_CandleTouchesRange(r, z.price_bottom, z.price_top))
            continue;

         // این کندل = اولین gooz baghali برای این ناحیه (DOWN)
         ++g_srgb_dn_counter;
         string tag = IntegerToString(g_srgb_dn_counter);

         string name = "gooz_baghali_D_"
                       + IntegerToString(z.sr_id)
                       + "_"
                       + tag;

         double span = r.high - r.low;
         if(span <= 0.0) span = 10 * _Point;
         double pad = span * 0.20;
         if(pad < 3 * _Point) pad = 3 * _Point;
         double y = r.low - pad;

         MarkCandleText(name, r.time, y, "GBD", clrMagenta);

         // NEW (H4->M15 bridge): GOOZBAGHALI is a START trigger (intrabar)
         WB15_PublishStartGooz(InpSymbol, DIR_DOWN, r.time, z.price_bottom, z.price_top);

         z.gbu_marked = true;
         g_srgb_dn_zones[zi] = z;

         if(g_srgb_dn_active &&
            z.sr_id      == g_srgb_dn_sr_id &&
            z.break_time == g_srgb_dn_break_time)
         {
            g_srgb_dn_marked = true;
         }

         // اولویت با جدیدترین unmit روی این کندل
         break;
      }
   }

   g_srgb_dn_last_index = upto_idx;
}

#endif // WAVEBOT_SR_GOOZBAGHALI_MQH

