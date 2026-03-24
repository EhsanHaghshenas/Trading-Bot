
#ifndef WAVEBOT_C1PRELOCK_MQH
#define WAVEBOT_C1PRELOCK_MQH

// ---------- UP (وفاداری به C1 موج۲ نزولی برای روند صعودی) ----------
static bool   g_pre_up_active = false;
static int    g_pre_up_idx    = -1;
static double g_pre_up_level  = 0.0;   // H1(C1)

// ------------------------------
// Context snapshot for C1 Pre-Lock (UP/DOWN)
// ------------------------------
// این ساختار فقط برای ذخیره/بازگردانی وضعیت استفاده می‌شود
// و منطق اصلی همچنان مستقیماً از روی متغیرهای global اجرا می‌شود.
struct C1PreContext
{
   // UP (وفاداری به C1 موج۲ نزولی برای روند صعودی)
   bool   pre_up_active;
   int    pre_up_idx;
   double pre_up_level;   // H1(C1)

   // DOWN (وفاداری به C1 موج۲ صعودی برای روند نزولی)
   bool   pre_dn_active;
   int    pre_dn_idx;
   double pre_dn_level;   // L1(C1)
};

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
inline void C1Pre_ContextInit(C1PreContext &ctx)
{
   ctx.pre_up_active = false;
   ctx.pre_up_idx    = -1;
   ctx.pre_up_level  = 0.0;

   ctx.pre_dn_active = false;
   ctx.pre_dn_idx    = -1;
   ctx.pre_dn_level  = 0.0;
}

// Export: کپی وضعیت فعلی global ها به داخل کانتکست
inline void C1Pre_ContextExport(C1PreContext &ctx)
{
   ctx.pre_up_active = g_pre_up_active;
   ctx.pre_up_idx    = g_pre_up_idx;
   ctx.pre_up_level  = g_pre_up_level;

   ctx.pre_dn_active = g_pre_dn_active;
   ctx.pre_dn_idx    = g_pre_dn_idx;
   ctx.pre_dn_level  = g_pre_dn_level;
}

// Import: برگرداندن وضعیت ذخیره‌شدهٔ کانتکست به متغیرهای global
inline void C1Pre_ContextImport(const C1PreContext &ctx)
{
   g_pre_up_active = ctx.pre_up_active;
   g_pre_up_idx    = ctx.pre_up_idx;
   g_pre_up_level  = ctx.pre_up_level;

   g_pre_dn_active = ctx.pre_dn_active;
   g_pre_dn_idx    = ctx.pre_dn_idx;
   g_pre_dn_level  = ctx.pre_dn_level;
}

// ریست کامل وضعیت وفاداری C1 در کانتکست فعلی (world فعال)
inline void C1Pre_ResetGlobals()
{
   g_pre_up_active = false;
   g_pre_up_idx    = -1;
   g_pre_up_level  = 0.0;

   g_pre_dn_active = false;
   g_pre_dn_idx    = -1;
   g_pre_dn_level  = 0.0;
}

inline void C1Pre_UP_Reset()
{
   g_pre_up_active = false;
   g_pre_up_idx    = -1;
   g_pre_up_level  = 0.0;
}
inline void C1Pre_UP_OnW2Locked(){ C1Pre_UP_Reset(); }

// فقط اجازه‌ی بررسی i وقتی:
// - هنوز قفلی نداریم ⇒ همین i قفل می‌شود
// - یا i == کاندید قفل‌شده
// - یا i > کاندید و H(i) > H1(C1_locked) ⇒ ابطال کاندید قبلی و ری‌انکر روی همین i
inline bool C1Pre_UP_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored = false;

   if(!g_pre_up_active)
   {
      g_pre_up_active = true;
      g_pre_up_idx    = i;
      g_pre_up_level  = rates[i].high;
      reanchored      = true;           // اولین کاندید هم به عنوان ری‌انکر محسوب شود
      return true;
   }

   if(i == g_pre_up_idx) return true;
   if(i  < g_pre_up_idx) return false;  // حلقه رو به جلو است، ولی برای اطمینان

   if(rates[i].high > g_pre_up_level)   // ابطال C1 قبلی
   {
      g_pre_up_idx   = i;
      g_pre_up_level = rates[i].high;
      reanchored     = true;
      return true;
   }
   return false;  // وفاداری به C1 قبلی ⇒ تست i ممنوع
}

// ---------- DOWN (وفاداری به C1 موج۲ صعودی برای روند نزولی) ----------
static bool   g_pre_dn_active = false;
static int    g_pre_dn_idx    = -1;
static double g_pre_dn_level  = 0.0;   // L1(C1)

inline void C1Pre_DN_Reset()
{
   g_pre_dn_active = false;
   g_pre_dn_idx    = -1;
   g_pre_dn_level  = 0.0;
}
inline void C1Pre_DN_OnW2Locked(){ C1Pre_DN_Reset(); }

inline bool C1Pre_DN_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored = false;

   if(!g_pre_dn_active)
   {
      g_pre_dn_active = true;
      g_pre_dn_idx    = i;
      g_pre_dn_level  = rates[i].low;
      reanchored      = true;           // اولین کاندید هم ری‌انکر است
      return true;
   }

   if(i == g_pre_dn_idx) return true;
   if(i  < g_pre_dn_idx) return false;

   if(rates[i].low < g_pre_dn_level)    // ابطال C1 قبلی
   {
      g_pre_dn_idx   = i;
      g_pre_dn_level = rates[i].low;
      reanchored     = true;
      return true;
   }
   return false;
}

#endif // WAVEBOT_C1PRELOCK_MQH
