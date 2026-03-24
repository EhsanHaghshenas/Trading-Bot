#ifndef WAVEBOT_FSMS_SW_MQH
#define WAVEBOT_FSMS_SW_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/Utils.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/ShadowBreaker.mqh>   // برای BringToFront پس از مارک نهایی
#include <WaveBot/Types.mqh>   // برای Direction (DIR_UP / DIR_DOWN)

// ============================================================================
// وضعیت Seed برای FSMS–SW
// ============================================================================

// ------------ حالت UP ------------
static bool     g_fsms_sw_up_active    = false;
static int      g_fsms_sw_up_c1_idx    = -1;     // C1 هم‌جهتِ قبل از FSMS
static double   g_fsms_sw_up_level     = 0.0;    // High(C1 هم‌جهت)
static datetime g_fsms_sw_up_seed_time = 0;      // زمان فایر FSMS
static int      g_fsms_sw_u_counter    = 0;      // شمارندهٔ مارکرهای FSMS–SW (UP)

// ------------ حالت DOWN ----------
static bool     g_fsms_sw_dn_active    = false;
static int      g_fsms_sw_dn_c1_idx    = -1;     // C1 هم‌جهتِ قبل از FSMS
static double   g_fsms_sw_dn_level     = 0.0;    // Low(C1 هم‌جهت)
static datetime g_fsms_sw_dn_seed_time = 0;      // زمان فایر FSMS
static int      g_fsms_sw_d_counter    = 0;      // شمارندهٔ مارکرهای FSMS–SW (DOWN)

// --- NEW: C1 موج۳ هم‌جهت منبع FSMS برای هر Seed ---
static int g_fsms_sw_up_w3_c1_idx = -1;   // C1_W3 اصلی هم‌جهت، سمت UP
static int g_fsms_sw_dn_w3_c1_idx = -1;   // C1_W3 اصلی هم‌جهت، سمت DOWN

// --- NEW: چهار متغیر برای آخرین کندل‌های C1_W2/W3_Minor (سطح قیمتی C1) ---
// برای روند صعودی: High(C1) ذخیره می‌شود
static double g_C1_W2_Minor_U_Value = 0.0;   // High C1_W2_Minor_U آخرین جفت
static double g_C1_W3_Minor_U_Value = 0.0;   // High C1_W3_Minor_U آخرین جفت
// برای روند نزولی: Low(C1) ذخیره می‌شود
static double g_C1_W2_Minor_D_Value = 0.0;   // Low C1_W2_Minor_D آخرین جفت
static double g_C1_W3_Minor_D_Value = 0.0;   // Low C1_W3_Minor_D آخرین جفت

// --- NEW: Getters for FSMS–SW UP ---
inline bool     FSMS_SW_UP_SeedActive()  { return g_fsms_sw_up_active;    }
inline double   FSMS_SW_UP_Level()       { return g_fsms_sw_up_level;     }
inline int      FSMS_SW_UP_C1Index()     { return g_fsms_sw_up_c1_idx;    }
inline datetime FSMS_SW_UP_SeedTime()    { return g_fsms_sw_up_seed_time; }

// --- NEW: Getters for FSMS–SW DOWN ---
inline bool     FSMS_SW_DN_SeedActive()  { return g_fsms_sw_dn_active;    }
inline double   FSMS_SW_DN_Level()       { return g_fsms_sw_dn_level;     }
inline int      FSMS_SW_DN_C1Index()     { return g_fsms_sw_dn_c1_idx;    }
inline datetime FSMS_SW_DN_SeedTime()    { return g_fsms_sw_dn_seed_time; }

// ============================================================================
// نگهبان موازی: پایش «جفت خلاف‌جهت دوم» پس از FSMS
// ============================================================================

enum __SW_OP_STATE { __SW_OP_SEARCH_W2=0, __SW_OP_WAIT_CONFIRM=1 };

struct __SW_OppCtx
{
   bool     active;
   int      state;
   int      idx;

   // W2 مخالف
   int      c1,c2,c3,c4,cend;

   // W3 مخالف
   bool     have_w3;
   int      w3_c1, k2,k3,k4, w3_end;

   // مسیر مستقیم (کاندید C1_W3)
   int      w3_cand;
   double   w3_cand_low;
   double   w3_cand_high;

   // مدیریت ویک/بادی‌بریک
   bool     wickActive;
   int      firstWickIdx, wickBreakIdx;
   double   bodyBreakLevel;  // برای DOWN: باید با بدنه زیرِ سطح بسته شود؛ برای UP: بالای سطح
   bool     breakAchieved;
   int      bodyBreakIdx;

   // گارد پس از body-break تا تکمیل W3
   bool     postBreak_c1_lock;
   int      postBreak_c1_ref;

   // وفاداری C1 قبل از Lock W2 (pre-lock شبیه C1Pre_*)
   bool     prelock_active;
   int      prelock_idx;
   double   prelock_level;
};

inline void __SW_ResetOppCtx(__SW_OppCtx &S)
{
   S.active=false; S.state=__SW_OP_SEARCH_W2; S.idx=-1;
   S.c1=S.c2=S.c3=S.c4=S.cend=-1;
   S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
   S.w3_cand=-1; S.w3_cand_low=DBL_MAX; S.w3_cand_high=-DBL_MAX;
   S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
   S.bodyBreakLevel=0.0; S.breakAchieved=false; S.bodyBreakIdx=-1;
   S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;
   S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
}

// دو زمینه: بعد از FSMS_U باید «DOWN دوم» را پایش کنیم؛ بعد از FSMS_D باید «UP دوم» را پایش کنیم
static __SW_OppCtx g_sw_guard_after_u;  // scan: DOWN
static __SW_OppCtx g_sw_guard_after_d;  // scan: UP

inline void __SW_ResetAllGuards(){ __SW_ResetOppCtx(g_sw_guard_after_u); __SW_ResetOppCtx(g_sw_guard_after_d); }

// ============================================================================
// ابزارهای محلی
// ============================================================================

inline int __SW_LeftmostMinLow_ExInside(const MqlRates &rates[], const bool &insideHL[], const int from, const int to)
{
   if(from>to) return -1; double mn=DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){ if(insideHL[i]) continue; double l=rates[i].low; if(l<mn){mn=l; idx=i;} }
   if(idx<0) idx=from; return idx;
}
inline int __SW_LeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[], const int from, const int to)
{
   if(from>to) return -1; double mx=-DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){ if(insideHL[i]) continue; double h=rates[i].high; if(h>mx){mx=h; idx=i;} }
   if(idx<0) idx=from; return idx;
}

// ============================================================================
//  Minor W2/W3 logging (w2_minor / w3_minor after FSMS / FSMS–SW invalidation)
// ============================================================================

#define FSMS_SW_MINOR_MAX 512

static datetime g_fsms_sw_minor_w2_times[FSMS_SW_MINOR_MAX];
static int      g_fsms_sw_minor_w2_count = 0;

// --- NEW: وضعیت MinorStarter / MinorOff ---
// فقط آخرین سناریوی فعال را نگه می‌داریم (آخرین # مینور)
static bool   g_minor_starter_u_active = false;
static bool   g_minor_starter_d_active = false;
static int    g_minor_starter_u_idx    = -1;   // index کندل MinorStarter_U در rates[]
static int    g_minor_starter_d_idx    = -1;   // index کندل MinorStarter_D در rates[]
static string g_minor_starter_u_tag    = "";
static string g_minor_starter_d_tag    = "";

// سطوح زونی که از لحظهٔ MinorStarter برای حالت off پایش می‌شوند
// اگر MinorStarter_U باشد → زون D مهم است
static double g_minor_starter_u_LowW2_D  = 0.0; // Low_C1_W2_MinorZone_D_#
static double g_minor_starter_u_HighW3_D = 0.0; // High_C1_W3_MinorZone_D_#

// اگر MinorStarter_D باشد → زون U مهم است
static double g_minor_starter_d_HighW2_U = 0.0; // High_C1_W2_MinorZone_U_#
static double g_minor_starter_d_LowW3_U  = 0.0; // Low_C1_W3_MinorZone_U_#

static bool   g_minor_off_u_done        = false;
static bool   g_minor_off_d_done        = false;
static int    g_minor_off_last_j        = -1;   // آخرین اندیسی که برای MinorOff بررسی شده

// --- NEW: شمارندهٔ کندل‌ها بین MinorStarter و MinorOff (جدا برای UP/DOWN) ---
static int    g_minor_u_seq             = 0;    // تعداد کندل‌ها از بعد MinorStarter_U تا MinorOff_U
static int    g_minor_d_seq             = 0;    // تعداد کندل‌ها از بعد MinorStarter_D تا MinorOff_D
// ============================================================================
//  MinorWindow Sessions (Major -> Minor world activation)
// ============================================================================

struct FSMS_SW_MinorSession
{
   bool      used;
   bool      open;               // true بین MinorStarter..MinorOff
   Direction dir;                // DIR_UP برای Starter_U | DIR_DOWN برای Starter_D
   string    tag;                // شماره مینور (همان tag در MinorStarter_U/D)

   // MinorStarter
   int       starter_idx;
   datetime  starter_time;

   // MinorOff (تا وقتی باز است: off_time=0, off_idx=-1)
   int       off_idx;
   datetime  off_time;
   
   // Off-zone levels (برای پیدا کردن سریع MinorOff و اجرای event-driven)
   double    off_level_1;
   double    off_level_2;

   // C1_W3_minor (آغاز موج۳ بعد از FSMS) که مبنای ext lq اولیه است
   int       c1_w3_idx;
   datetime  c1_w3_time;

   // ext lq minor اولیه (طبق قانون شما)
   // UP  => Low(C1_W3_minor)
   // DOWN=> High(C1_W3_minor)
   double    ext_init_price;
   datetime  ext_init_time;

   // metadata/دیباگ
   int       w2_minor_c1_idx;
   datetime  w2_minor_start_time;

   int       bars_between;       // تعداد کندل‌ها از بعد Starter تا Off (شامل کندل Off)
};

static FSMS_SW_MinorSession g_fsms_sw_sessions[];
static int g_fsms_sw_sessions_count = 0;

// -------- Runtime binding of the currently executing MIN world --------
// این state جزو snapshot منطقی world نیست؛ فقط توسط WorldManager
// قبل/بعد از اجرای MIN ست/پاک می‌شود تا ماژول‌های downstream بتوانند
// lineage های ساخته‌شده در MIN را به همان session bind کنند.
static bool                  g_fsms_sw_runtime_minor_active = false;
static FSMS_SW_MinorSession  g_fsms_sw_runtime_minor_sess;

inline void FSMS_SW_RuntimeMinor_Clear()
{
   g_fsms_sw_runtime_minor_active      = false;
   g_fsms_sw_runtime_minor_sess.used   = false;
   g_fsms_sw_runtime_minor_sess.open   = false;
   g_fsms_sw_runtime_minor_sess.dir    = DIR_UP;
   g_fsms_sw_runtime_minor_sess.tag    = "";
   g_fsms_sw_runtime_minor_sess.starter_idx  = -1;
   g_fsms_sw_runtime_minor_sess.starter_time = 0;
   g_fsms_sw_runtime_minor_sess.off_idx      = -1;
   g_fsms_sw_runtime_minor_sess.off_time     = 0;
   g_fsms_sw_runtime_minor_sess.off_level_1  = 0.0;
   g_fsms_sw_runtime_minor_sess.off_level_2  = 0.0;
   g_fsms_sw_runtime_minor_sess.c1_w3_idx    = -1;
   g_fsms_sw_runtime_minor_sess.c1_w3_time   = 0;
   g_fsms_sw_runtime_minor_sess.ext_init_price = 0.0;
   g_fsms_sw_runtime_minor_sess.ext_init_time  = 0;
   g_fsms_sw_runtime_minor_sess.w2_minor_c1_idx     = -1;
   g_fsms_sw_runtime_minor_sess.w2_minor_start_time = 0;
   g_fsms_sw_runtime_minor_sess.bars_between = 0;
}

inline void FSMS_SW_RuntimeMinor_Set(const FSMS_SW_MinorSession &s)
{
   g_fsms_sw_runtime_minor_active = true;
   g_fsms_sw_runtime_minor_sess   = s;
}

inline bool FSMS_SW_RuntimeMinor_Get(FSMS_SW_MinorSession &out)
{
   if(!g_fsms_sw_runtime_minor_active) return false;
   if(!g_fsms_sw_runtime_minor_sess.used) return false;
   out = g_fsms_sw_runtime_minor_sess;
   return true;
}

inline void FSMS_SW_CaptureCurrentMinorBinding(bool &is_minor,
                                               int  &dir_code,
                                               datetime &starter_time)
{
   is_minor     = false;
   dir_code     = -1;
   starter_time = 0;

   if(Markers_GetNamespace() != "MIN")
      return;

   if(!g_fsms_sw_runtime_minor_active)
      return;

   if(!g_fsms_sw_runtime_minor_sess.used)
      return;

   is_minor     = true;
   dir_code     = (g_fsms_sw_runtime_minor_sess.dir == DIR_UP ? 0 : 1);
   starter_time = g_fsms_sw_runtime_minor_sess.starter_time;
}


// ============================================================================
// MinorStarter Event (MAJ → WorldManager trigger)
// ============================================================================
static bool g_minor_start_evt_pending = false;
static FSMS_SW_MinorSession g_minor_start_evt_session;

inline bool FSMS_SW_PopMinorStartEvent(FSMS_SW_MinorSession &out)
{
   if(!g_minor_start_evt_pending) return false;
   out = g_minor_start_evt_session;
   g_minor_start_evt_pending = false;
   return true;
}

inline void FSMS_SW_Sessions_Reset()
{
   ArrayResize(g_fsms_sw_sessions, 0);
   g_fsms_sw_sessions_count = 0;
}

inline int FSMS_SW_Session_Count()
{
   return g_fsms_sw_sessions_count;
}

inline bool FSMS_SW_Session_Get(const int index, FSMS_SW_MinorSession &out)
{
   if(index < 0 || index >= g_fsms_sw_sessions_count) return false;
   out = g_fsms_sw_sessions[index];
   return true;
}

inline int FSMS_SW_Session_FindOpen(const string tag, const Direction dir)
{
   for(int i=0; i<g_fsms_sw_sessions_count; ++i)
   {
      if(!g_fsms_sw_sessions[i].used) continue;
      if(!g_fsms_sw_sessions[i].open) continue;
      if(g_fsms_sw_sessions[i].dir != dir) continue;
      if(g_fsms_sw_sessions[i].tag != tag) continue;
      return i;
   }
   return -1;
}

inline int FSMS_SW_Session_FindAny(const string tag, const Direction dir)
{
   for(int i=0; i<g_fsms_sw_sessions_count; ++i)
   {
      if(!g_fsms_sw_sessions[i].used) continue;
      if(g_fsms_sw_sessions[i].dir != dir) continue;
      if(g_fsms_sw_sessions[i].tag != tag) continue;
      return i;
   }
   return -1;
}

inline bool FSMS_SW_Session_FindByTagDir(const string tag,
                                         const Direction dir,
                                         FSMS_SW_MinorSession &out)
{
   int si = FSMS_SW_Session_FindAny(tag, dir);
   if(si < 0) return false;

   out = g_fsms_sw_sessions[si];
   return true;
}

inline int FSMS_SW_Session_FindByStarterTime(const Direction dir,
                                             const datetime starter_time)
{
   if(starter_time <= 0) return -1;

   for(int i=0; i<g_fsms_sw_sessions_count; ++i)
   {
      if(!g_fsms_sw_sessions[i].used) continue;
      if(g_fsms_sw_sessions[i].dir != dir) continue;
      if(g_fsms_sw_sessions[i].starter_time != starter_time) continue;
      return i;
   }
   return -1;
}

inline bool FSMS_SW_Session_GetByStarterTime(const Direction dir,
                                             const datetime starter_time,
                                             FSMS_SW_MinorSession &out)
{
   int si = FSMS_SW_Session_FindByStarterTime(dir, starter_time);
   if(si < 0) return false;

   out = g_fsms_sw_sessions[si];
   return true;
}

inline Direction __FSMS_SW_DirFromCode(const int dir_code)
{
   return (dir_code == 0 ? DIR_UP : DIR_DOWN);
}

// آیا lineage مینور bind‌شده به این session، در زمان asof_time منقضی شده است؟
inline bool FSMS_SW_IsMinorLineageExpired(const int dir_code,
                                          const datetime starter_time,
                                          const datetime asof_time)
{
   if(starter_time <= 0)
      return true;

   const Direction dir = __FSMS_SW_DirFromCode(dir_code);

   FSMS_SW_MinorSession s;
   if(FSMS_SW_Session_GetByStarterTime(dir, starter_time, s))
   {
      if(s.open)
         return false;

      if(s.off_time <= 0)
         return true;

      if(asof_time <= 0)
         return true;

      return (asof_time >= s.off_time);
   }

   if(Markers_GetNamespace() == "MIN" &&
      g_fsms_sw_runtime_minor_active &&
      g_fsms_sw_runtime_minor_sess.used &&
      g_fsms_sw_runtime_minor_sess.dir == dir &&
      g_fsms_sw_runtime_minor_sess.starter_time == starter_time)
   {
      return false;
   }

   // اگر session دیگر در registry فعلی پیدا نشود، برای جلوگیری از نشت state
   // آن lineage را منقضی فرض می‌کنیم.
   return true;
}

// اگر به هر دلیل یک Starter جدید آمد در حالی که session قبلی هنوز open بود،
// قبلی را فورس-کلوز می‌کنیم تا invariant رعایت شود: حداکثر یک session باز.
inline void FSMS_SW_Session_ForceCloseOpen(const int end_idx, const datetime end_time)
{
   for(int i=0; i<g_fsms_sw_sessions_count; ++i)
   {
      if(!g_fsms_sw_sessions[i].used) continue;
      if(!g_fsms_sw_sessions[i].open) continue;

      g_fsms_sw_sessions[i].open     = false;
      g_fsms_sw_sessions[i].off_idx  = end_idx;
      g_fsms_sw_sessions[i].off_time = end_time;
      if(end_idx > g_fsms_sw_sessions[i].starter_idx)
         g_fsms_sw_sessions[i].bars_between = (end_idx - g_fsms_sw_sessions[i].starter_idx);

      if(InpDebugPrints)
         Print("[FSMS–SESSION] Force-close open session #", g_fsms_sw_sessions[i].tag,
               " @ ", T(end_time));
   }
}

inline void FSMS_SW_Session_Begin(const Direction dir,
                                 const string tag,
                                 const int starter_idx,
                                 const datetime starter_time,
                                 const int c1_w3_idx,
                                 const datetime c1_w3_time,
                                 const double ext_init_price,
                                 const datetime ext_init_time,
                                 const int w2_minor_c1_idx,
                                 const datetime w2_minor_start_time,
                                 const double off_level_1,
                                 const double off_level_2)
{
   // در world مینور هیچ session/trigger جدیدی نساز (جلوگیری از recursion)
   if(Markers_GetNamespace() == "MIN")
      return;

   // enforce single-open-session rule
   FSMS_SW_Session_ForceCloseOpen(starter_idx, starter_time);

   FSMS_SW_MinorSession s;
   s.used  = true;
   s.open  = true;
   s.dir   = dir;
   s.tag   = tag;

   s.starter_idx  = starter_idx;
   s.starter_time = starter_time;

   s.off_idx      = -1;
   s.off_time     = 0;

   s.off_level_1  = off_level_1;
   s.off_level_2  = off_level_2;

   s.c1_w3_idx    = c1_w3_idx;
   s.c1_w3_time   = c1_w3_time;

   s.ext_init_price = ext_init_price;
   s.ext_init_time  = ext_init_time;

   s.w2_minor_c1_idx     = w2_minor_c1_idx;
   s.w2_minor_start_time = w2_minor_start_time;

   s.bars_between = 0;

   int pos = ArraySize(g_fsms_sw_sessions);
   ArrayResize(g_fsms_sw_sessions, pos+1);
   g_fsms_sw_sessions[pos] = s;
   g_fsms_sw_sessions_count = ArraySize(g_fsms_sw_sessions);

   if(InpDebugPrints)
      Print("[FSMS–SESSION] Begin #", tag,
            " | dir=", (dir==DIR_UP?"UP":"DOWN"),
            " | starter=", T(starter_time),
            " | c1_w3=", T(c1_w3_time),
            " | ext_init=", DoubleToString(ext_init_price,_Digits));

   // ------- raise event برای WorldManager (در هر Namespace غیر از MIN) -------
   g_minor_start_evt_pending = true;
   g_minor_start_evt_session = s;
}

inline bool FSMS_SW_Session_Close(const string tag,
                                 const Direction dir,
                                 const int off_idx,
                                 const datetime off_time,
                                 const int bars_between)
{
   int si = FSMS_SW_Session_FindOpen(tag, dir);
   if(si < 0) return false;

   g_fsms_sw_sessions[si].open         = false;
   g_fsms_sw_sessions[si].off_idx      = off_idx;
   g_fsms_sw_sessions[si].off_time     = off_time;
   g_fsms_sw_sessions[si].bars_between = bars_between;

   if(InpDebugPrints)
      Print("[FSMS–SESSION] Close #", tag,
            " | dir=", (dir==DIR_UP?"UP":"DOWN"),
            " | off=", T(off_time),
            " | bars_between=", bars_between);

   return true;
}

// پاک‌کردن بافر لاگ (در صورت نیاز می‌تونی قبل از یک اسکن جدید صدا بزنی)
inline void FSMS_SW_MinorLog_Reset()
{
   g_fsms_sw_minor_w2_count = 0;
   for(int i=0; i<FSMS_SW_MINOR_MAX; ++i)
      g_fsms_sw_minor_w2_times[i] = 0;

   // --- ریست وضعیت MinorStarter / MinorOff ---
   g_minor_starter_u_active = false;
   g_minor_starter_d_active = false;
   g_minor_starter_u_idx    = -1;
   g_minor_starter_d_idx    = -1;
   g_minor_starter_u_tag    = "";
   g_minor_starter_d_tag    = "";

   g_minor_starter_u_LowW2_D  = 0.0;
   g_minor_starter_u_HighW3_D = 0.0;
   g_minor_starter_d_HighW2_U = 0.0;
   g_minor_starter_d_LowW3_U  = 0.0;

   g_minor_off_u_done   = false;
   g_minor_off_d_done   = false;
   g_minor_off_last_j   = -1;

   // --- ریست شمارنده‌های کندل مینور ---
   g_minor_u_seq = 0;
   g_minor_d_seq = 0;

   // --- NEW: reset MinorWindow session registry ---
   FSMS_SW_Sessions_Reset();
   g_minor_start_evt_pending = false;
}


// اضافه کردن زمان شروع یک w2_minor
inline void FSMS_SW_MinorLog_AddW2Start(const datetime t)
{
   if(g_fsms_sw_minor_w2_count >= FSMS_SW_MINOR_MAX) return;
   g_fsms_sw_minor_w2_times[g_fsms_sw_minor_w2_count++] = t;
}

// دسترسی برای چاپ در انتهای اسکن
inline int FSMS_SW_MinorLog_Count()
{
   return g_fsms_sw_minor_w2_count;
}

inline datetime FSMS_SW_MinorLog_TimeAt(const int index)
{
   if(index < 0 || index >= g_fsms_sw_minor_w2_count) return 0;
   return g_fsms_sw_minor_w2_times[index];
}

// چاپ لیست w2_minor در انتهای اسکن (در API.mqh / API_Down.mqh استفاده می‌شود)
inline void FSMS_SW_MinorLog_Dump()
{
   if(!InpDebugPrints) return;
   int cnt = FSMS_SW_MinorLog_Count();
   if(cnt <= 0)
   {
      Print("[FSMS–MINOR] No w2_minor waves detected in current scan.");
      return;
   }

   Print("[FSMS–MINOR] ===== List of w2_minor start times (first candle) =====");
   for(int i=0; i<cnt; ++i)
   {
      datetime t = FSMS_SW_MinorLog_TimeAt(i);
      Print("[FSMS–MINOR] #", (i+1), " W2_minor start = ", T(t));
   }
   Print("[FSMS–MINOR] =======================================================");
}

// ============================================================================
//  Helpers: رسم و لاگ‌کردن جفت w2_minor / w3_minor
// ============================================================================

// حالت DOWN: دومین جفت مخالف DOWN بعد از FSMS_U که FSMS–SW(UP) را باطل می‌کند
// + رسم کندل "minor starter" (کندل W3 مینور که C1_W2 مینور را با بدنه می‌شکند)
inline void FSMS_SW_RecordMinorPair_DN(const MqlRates &rates[], const int n, const __SW_OppCtx &S)
{
   if(Markers_GetNamespace() == "MIN")
      return;

   if(S.c1 < 0 || S.c1 >= n) return;

   int w3c1 = S.w3_c1;
   if(w3c1 < 0 || w3c1 >= n)
      w3c1 = S.w3_cand;
   if(w3c1 < 0 || w3c1 >= n) return;

   const datetime w2_start = rates[S.c1].time;
   FSMS_SW_MinorLog_AddW2Start(w2_start);

   const string tag = IntegerToString(g_fsms_sw_minor_w2_count);

   if(InpDrawMarkers)
   {
      // W2_minor (DOWN)
      MarkV("w2_minor_" + tag + "_C1",  w2_start, clrMagenta);
      if(S.cend >= 0 && S.cend < n)
         MarkV("w2_minor_" + tag + "_END", rates[S.cend].time, clrMagenta);

      // W3_minor (DOWN)
      if(w3c1 >= 0 && w3c1 < n)
         MarkV("w3_minor_" + tag + "_C1", rates[w3c1].time, clrLime);
      if(S.w3_end >= 0 && S.w3_end < n)
         MarkV("w3_minor_" + tag + "_END", rates[S.w3_end].time, clrLime);

      // --- MinorStarter (DOWN) ---
      if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
      {
         const MqlRates r = rates[S.bodyBreakIdx];
         double span = r.high - r.low;
         if(span <= 0.0) span = 10.0 * _Point;
         double pad = span * 0.25;
         if(pad < 3.0 * _Point) pad = 3.0 * _Point;
         double y = r.low - pad;

         MarkCandleText("MinorStarter_D_" + tag, r.time, y, "MinorStarter", clrYellow);
      }
   }

   // --- ثبت وضعیت MinorStarter_D برای منطق MinorOff + ساخت Session ---
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
   {
      // NEW (H4->M15 bridge): MinorStarter is a STOP trigger for FSMS sessions
      WB15_PublishStopMinorStarter(InpSymbol, DIR_DOWN, rates[S.bodyBreakIdx].time);

      g_minor_starter_d_active = true;
      g_minor_starter_d_idx    = S.bodyBreakIdx;
      g_minor_starter_d_tag    = tag;
      g_minor_off_d_done       = false;

      // شمارش کندل‌های مینور از صفر
      g_minor_d_seq = 0;

      // زون U (برای off)
      g_minor_starter_d_HighW2_U = 0.0;
      g_minor_starter_d_LowW3_U  = 0.0;

      if(g_fsms_sw_up_c1_idx >= 0 && g_fsms_sw_up_c1_idx < n)
      {
         const MqlRates zW2 = rates[g_fsms_sw_up_c1_idx];
         g_minor_starter_d_HighW2_U = zW2.high;
      }
      if(g_fsms_sw_up_w3_c1_idx >= 0 && g_fsms_sw_up_w3_c1_idx < n)
      {
         const MqlRates zW3 = rates[g_fsms_sw_up_w3_c1_idx];
         g_minor_starter_d_LowW3_U = zW3.low;
      }

      // -------- NEW: ساخت MinorWindow Session (DOWN) --------
      // طبق قانون شما: ext lq minor اولیه = High(C1_W3_minor)
      FSMS_SW_Session_Begin(
         DIR_DOWN,
         tag,
         S.bodyBreakIdx,
         rates[S.bodyBreakIdx].time,
         w3c1,
         rates[w3c1].time,
         rates[w3c1].high,
         rates[w3c1].time,
         S.c1,
         w2_start,
         g_minor_starter_d_HighW2_U,
         g_minor_starter_d_LowW3_U
      );
   }

   if(InpDebugPrints)
   {
      Print("[FSMS–MINOR-DN] #", tag,
            " | W2_minor start=", T(w2_start),
            " | W3_minor C1=", T(rates[w3c1].time));
      if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
      {
         Print("[FSMS–MINOR-DN] #", tag,
               " | MinorStarter=", T(rates[S.bodyBreakIdx].time),
               " | H(C1_W2_Zone_U)=", DoubleToString(g_minor_starter_d_HighW2_U,_Digits),
               " | L(C1_W3_Zone_U)=", DoubleToString(g_minor_starter_d_LowW3_U,_Digits));
      }
   }
}


// حالت UP: دومین جفت مخالف UP بعد از FSMS_D که FSMS–SW(DOWN) را باطل می‌کند
// + رسم کندل "minor starter" (کندل W3 مینور که C1_W2 مینور را با بدنه می‌شکند)
inline void FSMS_SW_RecordMinorPair_UP(const MqlRates &rates[], const int n, const __SW_OppCtx &S)
{
   if(Markers_GetNamespace() == "MIN")
      return;

   if(S.c1 < 0 || S.c1 >= n) return;

   int w3c1 = S.w3_c1;
   if(w3c1 < 0 || w3c1 >= n)
      w3c1 = S.w3_cand;
   if(w3c1 < 0 || w3c1 >= n) return;

   const datetime w2_start = rates[S.c1].time;
   FSMS_SW_MinorLog_AddW2Start(w2_start);

   const string tag = IntegerToString(g_fsms_sw_minor_w2_count);

   if(InpDrawMarkers)
   {
      // W2_minor (UP)
      MarkV("w2_minor_" + tag + "_C1",  w2_start, clrMagenta);
      if(S.cend >= 0 && S.cend < n)
         MarkV("w2_minor_" + tag + "_END", rates[S.cend].time, clrMagenta);

      // W3_minor (UP)
      if(w3c1 >= 0 && w3c1 < n)
         MarkV("w3_minor_" + tag + "_C1", rates[w3c1].time, clrLime);
      if(S.w3_end >= 0 && S.w3_end < n)
         MarkV("w3_minor_" + tag + "_END", rates[S.w3_end].time, clrLime);

      // --- MinorStarter (UP) ---
      if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
      {
         const MqlRates r = rates[S.bodyBreakIdx];
         double span = r.high - r.low;
         if(span <= 0.0) span = 10.0 * _Point;
         double pad = span * 0.25;
         if(pad < 3.0 * _Point) pad = 3.0 * _Point;
         double y = r.high + pad;

         MarkCandleText("MinorStarter_U_" + tag, r.time, y, "MinorStarter", clrYellow);
      }
   }

   // --- ثبت وضعیت MinorStarter_U برای منطق MinorOff + ساخت Session ---
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
   {
      // NEW (H4->M15 bridge): MinorStarter is a STOP trigger for FSMS sessions
      WB15_PublishStopMinorStarter(InpSymbol, DIR_UP, rates[S.bodyBreakIdx].time);

      g_minor_starter_u_active = true;
      g_minor_starter_u_idx    = S.bodyBreakIdx;
      g_minor_starter_u_tag    = tag;
      g_minor_off_u_done       = false;

      // شمارش کندل‌های مینور از صفر
      g_minor_u_seq = 0;

      // زون D (برای off)
      g_minor_starter_u_LowW2_D  = 0.0;
      g_minor_starter_u_HighW3_D = 0.0;

      if(g_fsms_sw_dn_c1_idx >= 0 && g_fsms_sw_dn_c1_idx < n)
      {
         const MqlRates zW2 = rates[g_fsms_sw_dn_c1_idx];
         g_minor_starter_u_LowW2_D = zW2.low;
      }
      if(g_fsms_sw_dn_w3_c1_idx >= 0 && g_fsms_sw_dn_w3_c1_idx < n)
      {
         const MqlRates zW3 = rates[g_fsms_sw_dn_w3_c1_idx];
         g_minor_starter_u_HighW3_D = zW3.high;
      }

      // -------- NEW: ساخت MinorWindow Session (UP) --------
      // طبق قانون شما: ext lq minor اولیه = Low(C1_W3_minor)
      FSMS_SW_Session_Begin(
         DIR_UP,
         tag,
         S.bodyBreakIdx,
         rates[S.bodyBreakIdx].time,
         w3c1,
         rates[w3c1].time,
         rates[w3c1].low,
         rates[w3c1].time,
         S.c1,
         w2_start,
         g_minor_starter_u_LowW2_D,
         g_minor_starter_u_HighW3_D
      );
   }

   if(InpDebugPrints)
   {
      Print("[FSMS–MINOR-UP] #", tag,
            " | W2_minor start=", T(w2_start),
            " | W3_minor C1=", T(rates[w3c1].time));
      if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
      {
         Print("[FSMS–MINOR-UP] #", tag,
               " | MinorStarter=", T(rates[S.bodyBreakIdx].time),
               " | L(C1_W2_Zone_D)=", DoubleToString(g_minor_starter_u_LowW2_D,_Digits),
               " | H(C1_W3_Zone_D)=", DoubleToString(g_minor_starter_u_HighW3_D,_Digits));
      }
   }
}

// UP side: rename/recolor FSMS_U_* at g_fsms_sw_up_seed_time → FSMS_Minor_U_#
// + Textهای C1_W2_Minor_U_# و C1_W3_Minor_U_# و آپدیت متغیرها (High C1)
// همچنین، جهت مخالف (DOWN) را همزمان Disarm می‌کنیم تا از ساخت FSMS_Minor_D متضاد جلوگیری شود.
inline void FSMS_SW_ConvertFSMS_U_ToMinor(const MqlRates &rates[], const int n)
{
   if(g_fsms_sw_up_seed_time <= 0) return;

   const datetime fsms_t = g_fsms_sw_up_seed_time;
   const string   prefix = __ScanPrefix();
   const int      plen   = StringLen(prefix);

   int fsms_serial = -1;

   // 1) تمام مارکرهای FSMS_U_* همین اسکن که روی همین زمان هستند را حذف کن
   const int total = ObjectsTotal(0);
   for(int oi = total - 1; oi >= 0; --oi)
   {
      string on = ObjectName(0, oi);
      if(on == "" || StringLen(on) < plen) continue;
      if(StringSubstr(on, 0, plen) != prefix) continue;

      string tail = StringSubstr(on, plen);
      if(StringFind(tail, "FSMS_U_") != 0) continue; // فقط FSMS_U_...

      if((ENUM_OBJECT)ObjectGetInteger(0, on, OBJPROP_TYPE) != OBJ_VLINE) continue;

      datetime t = (datetime)ObjectGetInteger(0, on, OBJPROP_TIME);
      if(t != fsms_t) continue;

      // شماره FSMS را استخراج کن (FSMS_U_<id>)
      string id_str = StringSubstr(tail, StringLen("FSMS_U_"));
      fsms_serial   = (int)StringToInteger(id_str);

      ObjectDelete(0, on);
   }

   // (اختیاری) اگر نسخه‌های قدیمی FSMS_W2/FSMS_W3 روی چارت مانده باشند، این‌جا پاک‌شان می‌کنیم
   if(fsms_serial > 0)
   {
      string baseW2 = prefix + "FSMS_SRC_U_W2_C1_" + IntegerToString(fsms_serial);
      string baseW3 = prefix + "FSMS_SRC_U_W3_C1_" + IntegerToString(fsms_serial);
      if(ObjectFind(0, baseW2) != -1) ObjectDelete(0, baseW2);
      if(ObjectFind(0, baseW3) != -1) ObjectDelete(0, baseW3);
   }

   // 2) مارکر جدید FSMS_Minor/Failed_U_# روی همان کندل FSMS
   string tag = IntegerToString(g_fsms_sw_minor_w2_count);
   if(InpDrawMarkers)
      MarkV("FSMS_Minor_U_" + tag, fsms_t, clrOrange);   // اگر قبلاً به FSMS_Failed_U_ تغییر داده‌ای، همین جا هم همان نام را بگذار

   // 3) Textهای C1_W2_MinorZone_U_# و C1_W3_MinorZone_U_# + آپدیت متغیرها
   // C1 موج۲ هم‌جهت منبع FSMS
   if(g_fsms_sw_up_c1_idx >= 0 && g_fsms_sw_up_c1_idx < n)
   {
      const MqlRates rW2 = rates[g_fsms_sw_up_c1_idx];
      double span = rW2.high - rW2.low;
      if(span <= 0.0) span = 10 * _Point;
      double pad = span * 0.25;
      if(pad < 3 * _Point) pad = 3 * _Point;
      double y = rW2.high + pad;

      // *** این شیء قبلاً C1_W2_Minor_U_# بود، الان به C1_W2_MinorZone_U_# تغییر داده شده
      string name = "C1_W2_MinorZone_U_" + tag;
      if(InpDrawMarkers)
         MarkCandleText(name, rW2.time, y, "C1_W2_MinorZone_U", clrLime);

      // مقدار عددی (High همین C1_W2) مثل قبل در متغیر قدیمی ذخیره می‌شود
      g_C1_W2_Minor_U_Value = rW2.high;
   }

   // C1 موج۳ هم‌جهت منبع FSMS (اگر در Seed ثبت شده باشد)
   if(g_fsms_sw_up_w3_c1_idx >= 0 && g_fsms_sw_up_w3_c1_idx < n)
   {
      const MqlRates rW3 = rates[g_fsms_sw_up_w3_c1_idx];
      double span2 = rW3.high - rW3.low;
      if(span2 <= 0.0) span2 = 10 * _Point;
      double pad2 = span2 * 0.25;
      if(pad2 < 3 * _Point) pad2 = 3 * _Point;
      double y2 = rW3.high + pad2;

      // *** این شیء قبلاً C1_W3_Minor_U_# بود، الان به C1_W3_MinorZone_U_# تغییر داده شده
      string name2 = "C1_W3_MinorZone_U_" + tag;
      if(InpDrawMarkers)
         MarkCandleText(name2, rW3.time, y2, "C1_W3_MinorZone_U", clrAqua);

      // مقدار عددی (High C1_W3) مثل قبل در متغیر قدیمی ذخیره می‌شود
      g_C1_W3_Minor_U_Value = rW3.high;
   }
   
   // 4) Disarm متقابل: جهت DOWN را همزمان خاموش کن تا Minor_D متضاد ساخته نشود
   __SW_Disarm_DN();
}


// DOWN side: rename/recolor FSMS_D_* at g_fsms_sw_dn_seed_time → FSMS_Minor_D_#
// + Textهای C1_W2_Minor_D_# و C1_W3_Minor_D_# و آپدیت متغیرها (Low C1)
// همچنین جهت مخالف (UP) را Disarm می‌کنیم تا Minor_U متضاد ساخته نشود.
inline void FSMS_SW_ConvertFSMS_D_ToMinor(const MqlRates &rates[], const int n)
{
   if(g_fsms_sw_dn_seed_time <= 0) return;

   const datetime fsms_t = g_fsms_sw_dn_seed_time;
   const string   prefix = __ScanPrefix();
   const int      plen   = StringLen(prefix);

   int fsms_serial = -1;

   const int total = ObjectsTotal(0);
   for(int oi = total - 1; oi >= 0; --oi)
   {
      string on = ObjectName(0, oi);
      if(on == "" || StringLen(on) < plen) continue;
      if(StringSubstr(on, 0, plen) != prefix) continue;

      string tail = StringSubstr(on, plen);
      if(StringFind(tail, "FSMS_D_") != 0) continue; // فقط FSMS_D_...

      if((ENUM_OBJECT)ObjectGetInteger(0, on, OBJPROP_TYPE) != OBJ_VLINE) continue;

      datetime t = (datetime)ObjectGetInteger(0, on, OBJPROP_TIME);
      if(t != fsms_t) continue;

      string id_str = StringSubstr(tail, StringLen("FSMS_D_"));
      fsms_serial   = (int)StringToInteger(id_str);

      ObjectDelete(0, on);
   }

   // پاک‌کردن نسخه‌های قدیمی FSMS_W2/FSMS_W3 (اگر وجود داشته باشند)
   if(fsms_serial > 0)
   {
      string baseW2 = prefix + "FSMS_SRC_D_W2_C1_" + IntegerToString(fsms_serial);
      string baseW3 = prefix + "FSMS_SRC_D_W3_C1_" + IntegerToString(fsms_serial);
      if(ObjectFind(0, baseW2) != -1) ObjectDelete(0, baseW2);
      if(ObjectFind(0, baseW3) != -1) ObjectDelete(0, baseW3);
   }

   string tag = IntegerToString(g_fsms_sw_minor_w2_count);
   if(InpDrawMarkers)
      MarkV("FSMS_Minor_D_" + tag, fsms_t, clrOrange);   // یا FSMS_Failed_D_ مطابق نسخهٔ فعلی تو

   // C1_W2_MinorZone_D_# روی Low C1 موج۲ هم‌جهت
   if(g_fsms_sw_dn_c1_idx >= 0 && g_fsms_sw_dn_c1_idx < n)
   {
      const MqlRates rW2 = rates[g_fsms_sw_dn_c1_idx];
      double span = rW2.high - rW2.low;
      if(span <= 0.0) span = 10 * _Point;
      double pad = span * 0.25;
      if(pad < 3 * _Point) pad = 3 * _Point;
      double y = rW2.low - pad;

      // قبلاً C1_W2_Minor_D_# بود؛ الان C1_W2_MinorZone_D_#
      string name = "C1_W2_MinorZone_D_" + tag;
      if(InpDrawMarkers)
         MarkCandleText(name, rW2.time, y, "C1_W2_MinorZone_D", clrLime);

      g_C1_W2_Minor_D_Value = rW2.low;
   }

   // C1_W3_MinorZone_D_# روی Low C1 موج۳ هم‌جهت
   if(g_fsms_sw_dn_w3_c1_idx >= 0 && g_fsms_sw_dn_w3_c1_idx < n)
   {
      const MqlRates rW3 = rates[g_fsms_sw_dn_w3_c1_idx];
      double span2 = rW3.high - rW3.low;
      if(span2 <= 0.0) span2 = 10 * _Point;
      double pad2 = span2 * 0.25;
      if(pad2 < 3 * _Point) pad2 = 3 * _Point;
      double y2 = rW3.low - pad2;

      // قبلاً C1_W3_Minor_D_# بود؛ الان C1_W3_MinorZone_D_#
      string name2 = "C1_W3_MinorZone_D_" + tag;
      if(InpDrawMarkers)
         MarkCandleText(name2, rW3.time, y2, "C1_W3_MinorZone_D", clrAqua);

      g_C1_W3_Minor_D_Value = rW3.low;
   }
   
   // Disarm متقابل: جهت UP را خاموش کن تا Minor_U متضاد در همین ناحیه ساخته نشود
   __SW_Disarm_UP();
}

inline int __SW_FindIndexAtOrAfter(const MqlRates &rates[], const int n, const datetime t)
{
   for(int i=0;i<n;++i) if(rates[i].time>=t) return i;
   return n; // not found ⇒ انتهای آرایه
}

// ابطال با HW/HWBB از روی مارکرهای همین اسکن
inline bool __SW_ShouldDisarmOnHWMarkersSince(const datetime seed_time)
{
   if(seed_time<=0) return false;
   const string p   = __ScanPrefix();
   const int    plen= StringLen(p);
   for(int oi=ObjectsTotal(0)-1; oi>=0; --oi)
   {
      string on = ObjectName(0,oi);
      if(on=="" || StringLen(on)<plen) continue;
      if(StringSubstr(on,0,plen)!=p)   continue;

      string tail = StringSubstr(on, plen);

      bool isHWX   = (StringFind(tail,"HW_")==0    && StringFind(tail,"_X")>=0);
      bool isHWBB  = (StringFind(tail,"HWBB_U_")==0 || StringFind(tail,"HWBB_D_")==0);
      if(!isHWX && !isHWBB) continue;

      // فقط روی مارکرهای عمودی (VLINE) زمان را بخوان
      if((ENUM_OBJECT)ObjectGetInteger(0,on,OBJPROP_TYPE) != OBJ_VLINE) continue;

      datetime t = (datetime)ObjectGetInteger(0,on,OBJPROP_TIME);
      if(t >= seed_time) return true;
   }
   return false;
}

inline void __SW_Disarm_UP()
{
   if(g_fsms_sw_up_active && InpDebugPrints)
      Print("[FSMS–SW] Disarm (UP)");
   g_fsms_sw_up_active=false;
   __SW_ResetOppCtx(g_sw_guard_after_u);
}
inline void __SW_Disarm_DN()
{
   if(g_fsms_sw_dn_active && InpDebugPrints)
      Print("[FSMS–SW] Disarm (DOWN)");
   g_fsms_sw_dn_active=false;
   __SW_ResetOppCtx(g_sw_guard_after_d);
}

// ============================================================================
// API عمومی (Seed/Finalize) — همان منطق قبلی + آرم/ریستِ نگهبان‌های موازی
// ============================================================================

inline void FSMS_SW_DisarmAll()
{
   g_fsms_sw_up_active    = false;
   g_fsms_sw_up_c1_idx    = -1;
   g_fsms_sw_up_level     = 0.0;
   g_fsms_sw_up_seed_time = 0;
   g_fsms_sw_up_w3_c1_idx = -1;

   g_fsms_sw_dn_active    = false;
   g_fsms_sw_dn_c1_idx    = -1;
   g_fsms_sw_dn_level     = 0.0;
   g_fsms_sw_dn_seed_time = 0;
   g_fsms_sw_dn_w3_c1_idx = -1;

   __SW_ResetAllGuards();
}

// ---------- فعال‌سازی بذر پس از فایر FSMS ----------
inline void FSMS_SW_UP_ActivateSeed(const MqlRates &rates[], const int n,
                                    const int sameDirC1_Index,
                                    const int sameDirW3_Index,
                                    const datetime fsms_fire_time)
{
   if(sameDirC1_Index < 0 || sameDirC1_Index >= n || fsms_fire_time<=0) return;

   g_fsms_sw_up_active    = true;
   g_fsms_sw_up_c1_idx    = sameDirC1_Index;
   g_fsms_sw_up_level     = rates[sameDirC1_Index].high;   // High(C1-W2 هم‌جهت)
   g_fsms_sw_up_seed_time = fsms_fire_time;

   // NEW: ذخیرهٔ C1 موج۳ هم‌جهتِ منبع FSMS (اگر معتبر بود)
   if(sameDirW3_Index >= 0 && sameDirW3_Index < n)
      g_fsms_sw_up_w3_c1_idx = sameDirW3_Index;
   else
      g_fsms_sw_up_w3_c1_idx = -1;

   // نگهبان: از همین لحظه مراقب «جفت DOWN بعد از FSMS» باش
   __SW_ResetOppCtx(g_sw_guard_after_u);
   g_sw_guard_after_u.active = true;

   if(InpDebugPrints)
      Print("[FSMS–SW-UP] Seed armed | C1=", T(rates[sameDirC1_Index].time),
            " | Level(H)=", DoubleToString(g_fsms_sw_up_level, _Digits),
            " | SeedTime=", T(fsms_fire_time),
            " | SameDirW3_C1=", (g_fsms_sw_up_w3_c1_idx>=0 ? T(rates[g_fsms_sw_up_w3_c1_idx].time) : "n/a"));
}

inline void FSMS_SW_DN_ActivateSeed(const MqlRates &rates[], const int n,
                                    const int sameDirC1_Index,
                                    const int sameDirW3_Index,
                                    const datetime fsms_fire_time)
{
   if(sameDirC1_Index < 0 || sameDirC1_Index >= n || fsms_fire_time<=0) return;

   g_fsms_sw_dn_active    = true;
   g_fsms_sw_dn_c1_idx    = sameDirC1_Index;
   g_fsms_sw_dn_level     = rates[sameDirC1_Index].low;    // Low(C1-W2 هم‌جهت)
   g_fsms_sw_dn_seed_time = fsms_fire_time;

   if(sameDirW3_Index >= 0 && sameDirW3_Index < n)
      g_fsms_sw_dn_w3_c1_idx = sameDirW3_Index;
   else
      g_fsms_sw_dn_w3_c1_idx = -1;

   __SW_ResetOppCtx(g_sw_guard_after_d);
   g_sw_guard_after_d.active = true;

   if(InpDebugPrints)
      Print("[FSMS–SW-DOWN] Seed armed | C1=", T(rates[sameDirC1_Index].time),
            " | Level(L)=", DoubleToString(g_fsms_sw_dn_level, _Digits),
            " | SeedTime=", T(fsms_fire_time),
            " | SameDirW3_C1=", (g_fsms_sw_dn_w3_c1_idx>=0 ? T(rates[g_fsms_sw_dn_w3_c1_idx].time) : "n/a"));
}

// ---------- تلاش برای نهایی‌سازی روی تأیید W3 هم‌جهت ----------
inline void FSMS_SW_UP_TryMarkOnConfirmedW3(const MqlRates &rates[], const int n,
                                            const int w3_c1, const int bodyBreakIdx)
{
   if(!g_fsms_sw_up_active) return;
   if(w3_c1 < 0 || bodyBreakIdx < 0 || w3_c1 >= n || bodyBreakIdx >= n) return;

   // فقط W3هایی که بعد از زمان فایر FSMS رخ داده‌اند
   if(rates[w3_c1].time   < g_fsms_sw_up_seed_time) return;
   if(rates[bodyBreakIdx].time < g_fsms_sw_up_seed_time) return;

   // شرط تأیید: بدنهٔ کندل بریکِ W3 بالاتر از High(C1 هم‌جهتِ FSMS)
   if(rates[bodyBreakIdx].close > g_fsms_sw_up_level)
   {
      ++g_fsms_sw_u_counter;
      string tag = IntegerToString(g_fsms_sw_u_counter);

      if(InpDrawMarkers)
      {
         MarkV("FSMS_SW_U_C1_" + tag, rates[w3_c1].time,    clrMediumTurquoise);
         MarkV("FSMS_SW_U_B_"  + tag, rates[bodyBreakIdx].time, clrDarkTurquoise);
      }

      if(InpDebugPrints)
         Print("[FSMS–SW-UP] OK | W3_C1=", T(rates[w3_c1].time),
               " | BODY-BREAK=", T(rates[bodyBreakIdx].time),
               " | > H(FSMS_C1)=", DoubleToString(g_fsms_sw_up_level, _Digits));

      g_fsms_sw_up_active = false;
      __SW_ResetOppCtx(g_sw_guard_after_u);

      // اولویت نمایش مارکرهای SB در صورت وجود
      SB_UP_BringToFront();
      SB_DN_BringToFront();
   }
}
inline void FSMS_SW_DN_TryMarkOnConfirmedW3(const MqlRates &rates[], const int n,
                                            const int w3_c1, const int bodyBreakIdx)
{
   if(!g_fsms_sw_dn_active) return;
   if(w3_c1 < 0 || bodyBreakIdx < 0 || w3_c1 >= n || bodyBreakIdx >= n) return;

   if(rates[w3_c1].time   < g_fsms_sw_dn_seed_time) return;
   if(rates[bodyBreakIdx].time < g_fsms_sw_dn_seed_time) return;

   // شرط تأیید: بدنهٔ کندل بریکِ W3 پایین‌تر از Low(C1 هم‌جهتِ FSMS)
   if(rates[bodyBreakIdx].close < g_fsms_sw_dn_level)
   {
      ++g_fsms_sw_d_counter;
      string tag = IntegerToString(g_fsms_sw_d_counter);

      if(InpDrawMarkers)
      {
         MarkV("FSMS_SW_D_C1_" + tag, rates[w3_c1].time,    clrSandyBrown);
         MarkV("FSMS_SW_D_B_"  + tag, rates[bodyBreakIdx].time, clrChocolate);
      }

      if(InpDebugPrints)
         Print("[FSMS–SW-DOWN] OK | W3_C1=", T(rates[w3_c1].time),
               " | BODY-BREAK=", T(rates[bodyBreakIdx].time),
               " | < L(FSMS_C1)=", DoubleToString(g_fsms_sw_dn_level, _Digits));

      g_fsms_sw_dn_active = false;
      __SW_ResetOppCtx(g_sw_guard_after_d);

      SB_UP_BringToFront();
      SB_DN_BringToFront();
   }
}

// ============================================================================
// پایش موازی (OnBarCtx): HW/HWBB ⇒ Disarm  |  جفت خلاف‌جهت دوم ⇒ Disarm
// ============================================================================

// --- اسکن «DOWN دوم» پس از FSMS_U ---
inline void __SW_Scan_DN_After_FSMS_U(const MqlRates &rates[], const bool &insideHL[],
                                      const double &bodyLowEff[], const double &bodyHighEff[],
                                      const int n, const int upto_j)
{
   if(!g_fsms_sw_up_active || !g_sw_guard_after_u.active) return;

   __SW_OppCtx S = g_sw_guard_after_u;

   if(S.idx < 0)
   {
      S.idx   = __SW_FindIndexAtOrAfter(rates, n, g_fsms_sw_up_seed_time);
      S.state = __SW_OP_SEARCH_W2;
   }

   int limit = MathMin(upto_j, n-1);
   while(S.idx <= limit)
   {
      if(S.state == __SW_OP_SEARCH_W2)
      {
         bool found = false;
         for(int i=S.idx; i<=limit; ++i)
         {
            if(rates[i].time < g_fsms_sw_up_seed_time) continue;
            if(insideHL[i]) continue;

            // pre-lock: فقط اگر Low جدید، L1 قبلی را بشکند ⇒ C1 جدید
            if(!S.prelock_active){ S.prelock_active=true; S.prelock_idx=i; S.prelock_level=rates[i].low; }
            else if(i == S.prelock_idx){} 
            else if(i > S.prelock_idx)
            {
               if(rates[i].low < S.prelock_level){ S.prelock_idx=i; S.prelock_level=rates[i].low; }
               else continue;
            } else continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4))
               continue;

            // W2 مخالف (DOWN) یافت شد
            S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

            // ریست W3(DN)
            S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
            S.w3_cand=-1;   S.w3_cand_high=-DBL_MAX;

            // مدیریت body-break (DOWN)
            S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
            S.bodyBreakLevel=rates[S.c1].low; S.breakAchieved=false; S.bodyBreakIdx=-1;

            S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

            S.idx=S.cend; S.state=__SW_OP_WAIT_CONFIRM;
            S.prelock_active=false;
            found=true; break;
         }
         if(!found){ S.idx=limit+1; break; }
      }
      else // __SW_OP_WAIT_CONFIRM (DOWN)
      {
         bool progressed=false;
         for(int j=S.idx; j<=limit; ++j)
         {
            if(rates[j].time < g_fsms_sw_up_seed_time) continue;
            if(insideHL[j]) continue;

            // Wick escalation (DOWN)
            if(!S.breakAchieved)
            {
               if(rates[j].low < S.bodyBreakLevel)
               {
                  if(rates[j].close < S.bodyBreakLevel)
                  {
                     S.breakAchieved=true; S.bodyBreakIdx=j;
                     int __c1_eff=(S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
                     S.postBreak_c1_ref=__c1_eff; S.postBreak_c1_lock=(__c1_eff>=0);
                  }
                  else
                  {
                     S.bodyBreakLevel=rates[j].low;
                     if(S.firstWickIdx<0)
                     {
                        S.firstWickIdx=j; S.wickBreakIdx=j; S.wickActive=true;
                        int anchorC1 = __SW_LeftmostMaxHigh_ExInside(rates, insideHL, S.cend, S.firstWickIdx);
                        S.have_w3=false; S.w3_c1=anchorC1; S.w3_cand=-1; S.w3_cand_high=-DBL_MAX;
                     }
                  }
               }
            }

            // Chain-Invalidation (pre-body, wick-window, DOWN)
            {
               int __rew=-1;
               if(ChainInv_PreBody_WickWindow_DN_OnBar(rates,insideHL,n,j,
                     S.breakAchieved,S.wickActive,S.firstWickIdx,S.w3_c1,S.w3_cand,__rew))
               {
                  S.idx=__rew; S.state=__SW_OP_SEARCH_W2;
                  S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
                  progressed=true; break;
               }
            }

            // RESET W3 (pre-body, non-wick): H > H(C1_W3)
            if(!S.wickActive && !S.breakAchieved)
            {
               int c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
               if(c1_eff>=0 && rates[j].high > rates[c1_eff].high)
               { S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1=-1; S.w3_cand=j; S.w3_cand_high=rates[j].high; continue; }
            }

            // direct-path candidate: بزرگ‌ترین High از cend به بعد
            if(!S.wickActive)
            {
               if(j>=S.cend && (S.w3_cand<0 || rates[j].high > S.w3_cand_high))
               { S.w3_cand=j; S.w3_cand_high=rates[j].high; S.have_w3=false; }
            }

            // شمارش W3 (DOWN)
            int startIdx=-1;
            if(S.w3_c1>=0) startIdx=S.w3_c1; else if(S.w3_cand>=0) startIdx=S.w3_cand;
            if(!S.have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1,w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
               { S.have_w3=true; if(S.w3_c1<0) S.w3_c1=startIdx; S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e; }
            }

            // Guard: تغییر C1_W3 پس از body-break ⇒ ابطال W2
            if(S.breakAchieved && !S.have_w3)
            {
               int __c1_now=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
               if(!S.postBreak_c1_lock && __c1_now>=0){ S.postBreak_c1_ref=__c1_now; S.postBreak_c1_lock=true; }
               else if(S.postBreak_c1_lock && __c1_now>=0 && __c1_now!=S.postBreak_c1_ref)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=__SW_OP_SEARCH_W2;
                  S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
                  progressed=true; break;
               }
            }

            // POST body-break و قبل از اتمام W3: H > H(C1_W3) ⇒ ابطال W2
            if(S.breakAchieved && !S.have_w3)
            {
               int c1e=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
               if(c1e>=0 && rates[j].high > rates[c1e].high)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=__SW_OP_SEARCH_W2;
                  S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
                  progressed=true; break;
               }
            }

            // نهایی: تکمیل جفت DOWN بعد از FSMS ⇒ ابطال FSMS–SW (UP)
            if(S.have_w3 && S.breakAchieved)
            {
               const datetime bt  = rates[(S.bodyBreakIdx>=0?S.bodyBreakIdx:j)].time;
               const datetime c1t = rates[S.c1].time;
               if(bt >= g_fsms_sw_up_seed_time && c1t >= g_fsms_sw_up_seed_time)
               {
                  if(InpDebugPrints)
                     Print("[FSMS–SW] Disarmed (UP) due to the 2nd opposite pair DOWN after FSMS.",
                           " FSMS=",T(g_fsms_sw_up_seed_time)," | W2_C1=",T(c1t)," | BB=",T(bt));
                  
                  // NEW: mark + log the minor W2/W3 that invalidates FSMS–SW (UP)
                  FSMS_SW_RecordMinorPair_DN(rates, n, S);
      
                  // NEW: تبدیل کندل FSMS همین سناریو به FSMS_Minor + Textهای C1_W2/W3_Minor_U_#
                  FSMS_SW_ConvertFSMS_U_ToMinor(rates, n);
                  
                  __SW_Disarm_UP();
                  g_sw_guard_after_u = S; // برای ثبات حالت (هرچند inactive می‌شود)
                  return;
               }
               // اگر C1 قبل از FSMS بوده، این جفت معتبرِ «پس از FSMS» نیست ⇒ دوباره جستجو
               S.idx=j; S.state=__SW_OP_SEARCH_W2;
               S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
               progressed=true; break;
            }
         }
         if(!progressed) break;
      }
   }
   g_sw_guard_after_u = S;
}

// --- اسکن «UP دوم» پس از FSMS_D ---
inline void __SW_Scan_UP_After_FSMS_D(const MqlRates &rates[], const bool &insideHL[],
                                      const double &bodyLowEff[], const double &bodyHighEff[],
                                      const int n, const int upto_j)
{
   if(!g_fsms_sw_dn_active || !g_sw_guard_after_d.active) return;

   __SW_OppCtx S = g_sw_guard_after_d;

   if(S.idx < 0)
   {
      S.idx   = __SW_FindIndexAtOrAfter(rates, n, g_fsms_sw_dn_seed_time);
      S.state = __SW_OP_SEARCH_W2;
   }

   int limit = MathMin(upto_j, n-1);
   while(S.idx <= limit)
   {
      if(S.state == __SW_OP_SEARCH_W2)
      {
         bool found=false;
         for(int i=S.idx; i<=limit; ++i)
         {
            if(rates[i].time < g_fsms_sw_dn_seed_time) continue;
            if(insideHL[i]) continue;

            // pre-lock: فقط اگر High جدید، H1 قبلی را بشکند ⇒ C1 جدید
            if(!S.prelock_active){ S.prelock_active=true; S.prelock_idx=i; S.prelock_level=rates[i].high; }
            else if(i == S.prelock_idx){}
            else if(i > S.prelock_idx)
            {
               if(rates[i].high > S.prelock_level){ S.prelock_idx=i; S.prelock_level=rates[i].high; }
               else continue;
            } else continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4))
               continue;

            // W2 مخالف (UP) یافت شد
            S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

            // ریست W3(UP)
            S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
            S.w3_cand=-1;   S.w3_cand_low=DBL_MAX;

            // مدیریت body-break (UP)
            S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
            S.bodyBreakLevel=rates[S.c1].high; S.breakAchieved=false; S.bodyBreakIdx=-1;

            S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

            S.idx=S.cend; S.state=__SW_OP_WAIT_CONFIRM;
            S.prelock_active=false;
            found=true; break;
         }
         if(!found){ S.idx=limit+1; break; }
      }
      else // __SW_OP_WAIT_CONFIRM (UP)
      {
         bool progressed=false;
         for(int j=S.idx; j<=limit; ++j)
         {
            if(rates[j].time < g_fsms_sw_dn_seed_time) continue;
            if(insideHL[j]) continue;

            // Wick escalation (UP)
            if(!S.breakAchieved)
            {
               if(rates[j].high > S.bodyBreakLevel)
               {
                  if(rates[j].close > S.bodyBreakLevel)
                  {
                     S.breakAchieved=true; S.bodyBreakIdx=j;
                     int __c1_eff=(S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
                     S.postBreak_c1_ref=__c1_eff; S.postBreak_c1_lock=(__c1_eff>=0);
                  }
                  else
                  {
                     S.bodyBreakLevel=rates[j].high;
                     if(S.firstWickIdx<0)
                     {
                        S.firstWickIdx=j; S.wickBreakIdx=j; S.wickActive=true;
                        int anchorC1 = __SW_LeftmostMinLow_ExInside(rates, insideHL, S.cend, S.firstWickIdx);
                        S.have_w3=false; S.w3_c1=anchorC1; S.w3_cand=-1; S.w3_cand_low=DBL_MAX;
                     }
                  }
               }
            }

            // Chain-Invalidation (pre-body, wick-window, UP)
            {
               int __rew=-1;
               if(ChainInv_PreBody_WickWindow_UP_OnBar(rates,insideHL,n,j,
                     S.breakAchieved,S.wickActive,S.firstWickIdx,S.w3_c1,S.w3_cand,__rew))
               {
                  S.idx=__rew; S.state=__SW_OP_SEARCH_W2;
                  S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
                  progressed=true; break;
               }
            }

            // RESET W3 (pre-body, non-wick): L < L(C1_W3)
            if(!S.wickActive && !S.breakAchieved)
            {
               int c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
               if(c1_eff>=0 && rates[j].low < rates[c1_eff].low)
               { S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1=-1; S.w3_cand=j; S.w3_cand_low=rates[j].low; continue; }
            }

            // direct-path: کمترین Low از cend به بعد
            if(!S.wickActive)
            {
               if(j>=S.cend && (S.w3_cand<0 || rates[j].low < S.w3_cand_low))
               { S.w3_cand=j; S.w3_cand_low=rates[j].low; S.have_w3=false; }
            }

            // شمارش W3 (UP)
            int startIdx=-1;
            if(S.w3_c1>=0) startIdx=S.w3_c1; else if(S.w3_cand>=0) startIdx=S.w3_cand;
            if(!S.have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1,w3e=-1;
               if(CheckWave3CountOnly_Local(rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
               { S.have_w3=true; if(S.w3_c1<0) S.w3_c1=startIdx; S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e; }
            }

            // Guard: تغییر C1_W3 پس از body-break ⇒ ابطال W2
            if(S.breakAchieved && !S.have_w3)
            {
               int __c1_now=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
               if(!S.postBreak_c1_lock && __c1_now>=0){ S.postBreak_c1_ref=__c1_now; S.postBreak_c1_lock=true; }
               else if(S.postBreak_c1_lock && __c1_now>=0 && __c1_now!=S.postBreak_c1_ref)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=__SW_OP_SEARCH_W2;
                  S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
                  progressed=true; break;
               }
            }

            // POST body-break و قبل از پایان W3: L < L(C1_W3) ⇒ ابطال W2
            if(S.breakAchieved && !S.have_w3)
            {
               int c1e=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
               if(c1e>=0 && rates[j].low < rates[c1e].low)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=__SW_OP_SEARCH_W2;
                  S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
                  progressed=true; break;
               }
            }

            // نهایی: تکمیل جفت UP بعد از FSMS ⇒ ابطال FSMS–SW (DOWN)
            if(S.have_w3 && S.breakAchieved)
            {
               const datetime bt  = rates[(S.bodyBreakIdx>=0?S.bodyBreakIdx:j)].time;
               const datetime c1t = rates[S.c1].time;
               if(bt >= g_fsms_sw_dn_seed_time && c1t >= g_fsms_sw_dn_seed_time)
               {
                  if(InpDebugPrints)
                     Print("[FSMS–SW] Disarmed (DOWN) due to the 2nd opposite pair UP after FSMS.",
                           " FSMS=",T(g_fsms_sw_dn_seed_time)," | W2_C1=",T(c1t)," | BB=",T(bt));
                  
                  // NEW: mark + log the minor W2/W3 that invalidates FSMS–SW (DOWN)
                  FSMS_SW_RecordMinorPair_UP(rates, n, S);

                  // NEW: تبدیل کندل FSMS همین سناریو به FSMS_Minor + Textهای C1_W2/W3_Minor_D_#
                  FSMS_SW_ConvertFSMS_D_ToMinor(rates, n);

                  __SW_Disarm_DN();
                  g_sw_guard_after_d = S;
                  return;
               }
               S.idx=j; S.state=__SW_OP_SEARCH_W2;
               S.prelock_active=false; S.prelock_idx=-1; S.prelock_level=0.0;
               progressed=true; break;
            }
         }
         if(!progressed) break;
      }
   }
   g_sw_guard_after_d = S;
}

// ============================================================================
//  MinorOff detection: اولین عبور از سطوح زون مخالف بعد از MinorStarter
//  + NEW: شمارش و شماره‌گذاری کندل‌ها بین MinorStarter_U/D و MinorOff_U/D
// ============================================================================
inline void FSMS_SW_DrawMinorSequenceArchive(const MqlRates &rates[],
                                             const int n,
                                             const Direction dir,
                                             const string tag,
                                             const int starter_idx,
                                             const int off_idx)
{
   if(!InpDrawMarkers) return;
   if(starter_idx < 0 || starter_idx >= n) return;
   if(off_idx <= starter_idx) return;

   int last = off_idx;
   if(last >= n) last = n - 1;

   int seq = 0;
   for(int i = starter_idx + 1; i <= last; ++i)
   {
      const MqlRates r = rates[i];
      double span = r.high - r.low;
      if(span <= 0.0) span = 10.0 * _Point;
      double pad = span * 0.25;
      if(pad < 3.0 * _Point) pad = 3.0 * _Point;

      double y = (dir == DIR_UP ? (r.high + pad) : (r.low - pad));
      ++seq;

      string base = (dir == DIR_UP ? "MinorSeq_U_" : "MinorSeq_D_");
      string name = base + tag + "_" + IntegerToString(seq);
      MarkCandleText(name, r.time, y, IntegerToString(seq), clrWhite);
   }
}

inline void FSMS_SW_CheckMinorOff(const MqlRates &rates[], const int n, const int upto_j)
{
   if(!g_minor_starter_u_active && !g_minor_starter_d_active)
   {
      g_minor_off_last_j = upto_j;
      return;
   }

   int from = g_minor_off_last_j + 1;
   if(from < 0) from = 0;
   if(from > upto_j)
      return;

   for(int j = from; j <= upto_j && j < n; ++j)
   {
      const MqlRates r   = rates[j];
      const double   low = r.low;
      const double   high= r.high;

      // --- MinorStarter_U active ---
      if(g_minor_starter_u_active && !g_minor_off_u_done && j > g_minor_starter_u_idx)
      {
         ++g_minor_u_seq;

         bool crossed = false;

         if(g_minor_starter_u_LowW2_D > 0.0)
         {
            if(low <= g_minor_starter_u_LowW2_D && high >= g_minor_starter_u_LowW2_D)
               crossed = true;
         }

         if(!crossed && g_minor_starter_u_HighW3_D > 0.0)
         {
            if(low <= g_minor_starter_u_HighW3_D && high >= g_minor_starter_u_HighW3_D)
               crossed = true;
         }

         if(crossed)
         {
            double span = high - low;
            if(span <= 0.0) span = 10.0 * _Point;
            double pad = span * 0.25;
            if(pad < 3.0 * _Point) pad = 3.0 * _Point;
            double y = high + pad;

            string tag = (g_minor_starter_u_tag == "" ? "0" : g_minor_starter_u_tag);

            FSMS_SW_DrawMinorSequenceArchive(rates, n, DIR_UP, tag, g_minor_starter_u_idx, j);

            if(InpDrawMarkers)
               MarkCandleText("MinorOff_U_" + tag, r.time, y, "MinorOff", clrRed);

            // NEW (WB15 bridge): if MAJ MinorOff breaks low of C1-W2 Minorzone D, stop MIN-start M15 session
            if(g_minor_starter_u_LowW2_D > 0.0 && low <= g_minor_starter_u_LowW2_D)
               WB15_PublishStopMinorOffZone_MAJONLY(InpSymbol, DIR_DOWN, r.time);

            // -------- NEW: close session --------
            FSMS_SW_Session_Close(tag, DIR_UP, j, r.time, g_minor_u_seq);

            g_minor_off_u_done       = true;
            g_minor_starter_u_active = false;

            if(InpDebugPrints)
               Print("[FSMS–MINOR-OFF-UP] #", tag,
                     " | bars_between=", g_minor_u_seq,
                     " | MinorOff at=", T(r.time),
                     " | L(C1_W2_Zone_D)=", DoubleToString(g_minor_starter_u_LowW2_D,_Digits),
                     " | H(C1_W3_Zone_D)=", DoubleToString(g_minor_starter_u_HighW3_D,_Digits));
         }
      }

      // --- MinorStarter_D active ---
      if(g_minor_starter_d_active && !g_minor_off_d_done && j > g_minor_starter_d_idx)
      {
         ++g_minor_d_seq;

         bool crossed = false;

         if(g_minor_starter_d_HighW2_U > 0.0)
         {
            if(low <= g_minor_starter_d_HighW2_U && high >= g_minor_starter_d_HighW2_U)
               crossed = true;
         }

         if(!crossed && g_minor_starter_d_LowW3_U > 0.0)
         {
            if(low <= g_minor_starter_d_LowW3_U && high >= g_minor_starter_d_LowW3_U)
               crossed = true;
         }

         if(crossed)
         {
            double span = high - low;
            if(span <= 0.0) span = 10.0 * _Point;
            double pad = span * 0.25;
            if(pad < 3.0 * _Point) pad = 3.0 * _Point;
            double y = r.low - pad;

            string tag = (g_minor_starter_d_tag == "" ? "0" : g_minor_starter_d_tag);

            FSMS_SW_DrawMinorSequenceArchive(rates, n, DIR_DOWN, tag, g_minor_starter_d_idx, j);

            if(InpDrawMarkers)
               MarkCandleText("MinorOff_D_" + tag, r.time, y, "MinorOff", clrRed);

            // NEW (WB15 bridge): if MAJ MinorOff breaks high of C1-W2 Minorzone U, stop MIN-start M15 session
            if(g_minor_starter_d_HighW2_U > 0.0 && high >= g_minor_starter_d_HighW2_U)
               WB15_PublishStopMinorOffZone_MAJONLY(InpSymbol, DIR_UP, r.time);

            // -------- NEW: close session --------
            FSMS_SW_Session_Close(tag, DIR_DOWN, j, r.time, g_minor_d_seq);

            g_minor_off_d_done       = true;
            g_minor_starter_d_active = false;

            if(InpDebugPrints)
               Print("[FSMS–MINOR-OFF-DN] #", tag,
                     " | bars_between=", g_minor_d_seq,
                     " | MinorOff at=", T(r.time),
                     " | H(C1_W2_Zone_U)=", DoubleToString(g_minor_starter_d_HighW2_U,_Digits),
                     " | L(C1_W3_Zone_U)=", DoubleToString(g_minor_starter_d_LowW3_U,_Digits));
         }
      }
   }

   g_minor_off_last_j = upto_j;
}


// ------------------------------
// Context snapshot for FSMS–SW (seeds + SW guard + Minor logging)
// ------------------------------
struct FSMS_SWContext
{
   // -------- Seed اصلی FSMS–SW --------
   bool     up_active;
   int      up_c1_idx;
   double   up_level;
   datetime up_seed_time;
   int      up_counter;

   bool     dn_active;
   int      dn_c1_idx;
   double   dn_level;
   datetime dn_seed_time;
   int      dn_counter;

   // C1_W3 هم‌جهت منبع FSMS
   int      up_w3_c1_idx;
   int      dn_w3_c1_idx;

   // آخرین سطح C1_W2/W3_Minor
   double   C1_W2_Minor_U_Value;
   double   C1_W3_Minor_U_Value;
   double   C1_W2_Minor_D_Value;
   double   C1_W3_Minor_D_Value;

   // نگهبان موازی: جفت خلاف‌جهت دوم بعد از FSMS
   __SW_OppCtx sw_guard_after_u;
   __SW_OppCtx sw_guard_after_d;

   //  لاگ w2_minor بعد از FSMS / FSMS–SW
   datetime minor_w2_times[];
   int      minor_w2_count;

   // وضعیت MinorStarter / MinorOff
   bool   minor_starter_u_active;
   bool   minor_starter_d_active;
   int    minor_starter_u_idx;
   int    minor_starter_d_idx;
   string minor_starter_u_tag;
   string minor_starter_d_tag;
   double minor_starter_u_LowW2_D;
   double minor_starter_u_HighW3_D;
   double minor_starter_d_HighW2_U;
   double minor_starter_d_LowW3_U;
   bool   minor_off_u_done;
   bool   minor_off_d_done;
   int    minor_off_last_j;
   int    minor_u_seq;
   int    minor_d_seq;
      // --- MinorWindow session registry ---
   FSMS_SW_MinorSession sessions[];
   int sessions_count;

};

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
inline void FSMS_SW_ContextInit(FSMS_SWContext &ctx)
{
   // Seed UP
   ctx.up_active    = false;
   ctx.up_c1_idx    = -1;
   ctx.up_level     = 0.0;
   ctx.up_seed_time = 0;
   ctx.up_counter   = 0;
   ctx.up_w3_c1_idx = -1;

   // Seed DOWN
   ctx.dn_active    = false;
   ctx.dn_c1_idx    = -1;
   ctx.dn_level     = 0.0;
   ctx.dn_seed_time = 0;
   ctx.dn_counter   = 0;
   ctx.dn_w3_c1_idx = -1;

   // آخرین سطح C1_W2/W3_Minor
   ctx.C1_W2_Minor_U_Value = 0.0;
   ctx.C1_W3_Minor_U_Value = 0.0;
   ctx.C1_W2_Minor_D_Value = 0.0;
   ctx.C1_W3_Minor_D_Value = 0.0;

   // نگهبان موازی
   __SW_ResetOppCtx(ctx.sw_guard_after_u);
   __SW_ResetOppCtx(ctx.sw_guard_after_d);

   // لاگ مینور
   ArrayResize(ctx.minor_w2_times, 0);
   ctx.minor_w2_count = 0;

   // وضعیت MinorStarter / MinorOff
   ctx.minor_starter_u_active = false;
   ctx.minor_starter_d_active = false;
   ctx.minor_starter_u_idx    = -1;
   ctx.minor_starter_d_idx    = -1;
   ctx.minor_starter_u_tag    = "";
   ctx.minor_starter_d_tag    = "";
   ctx.minor_starter_u_LowW2_D  = 0.0;
   ctx.minor_starter_u_HighW3_D = 0.0;
   ctx.minor_starter_d_HighW2_U = 0.0;
   ctx.minor_starter_d_LowW3_U  = 0.0;
   ctx.minor_off_u_done   = false;
   ctx.minor_off_d_done   = false;
   ctx.minor_off_last_j   = -1;
   ctx.minor_u_seq        = 0;
   ctx.minor_d_seq        = 0;
   
   // --- MinorWindow session registry
   ArrayResize(ctx.sessions, 0);
   ctx.sessions_count = 0;
}

// Export: کپی وضعیت فعلی globalها به داخل کانتکست
// Export: کپی وضعیت فعلی globalها به داخل کانتکست
inline void FSMS_SW_ContextExport(FSMS_SWContext &ctx)
{
   // Seed UP
   ctx.up_active    = g_fsms_sw_up_active;
   ctx.up_c1_idx    = g_fsms_sw_up_c1_idx;
   ctx.up_level     = g_fsms_sw_up_level;
   ctx.up_seed_time = g_fsms_sw_up_seed_time;
   ctx.up_counter   = g_fsms_sw_u_counter;
   ctx.up_w3_c1_idx = g_fsms_sw_up_w3_c1_idx;

   // Seed DOWN
   ctx.dn_active    = g_fsms_sw_dn_active;
   ctx.dn_c1_idx    = g_fsms_sw_dn_c1_idx;
   ctx.dn_level     = g_fsms_sw_dn_level;
   ctx.dn_seed_time = g_fsms_sw_dn_seed_time;
   ctx.dn_counter   = g_fsms_sw_d_counter;
   ctx.dn_w3_c1_idx = g_fsms_sw_dn_w3_c1_idx;

   // آخرین سطح C1_W2/W3_Minor
   ctx.C1_W2_Minor_U_Value = g_C1_W2_Minor_U_Value;
   ctx.C1_W3_Minor_U_Value = g_C1_W3_Minor_U_Value;
   ctx.C1_W2_Minor_D_Value = g_C1_W2_Minor_D_Value;
   ctx.C1_W3_Minor_D_Value = g_C1_W3_Minor_D_Value;

   // نگهبان موازی
   ctx.sw_guard_after_u = g_sw_guard_after_u;
   ctx.sw_guard_after_d = g_sw_guard_after_d;

   // لاگ مینور
   ArrayCopy(ctx.minor_w2_times, g_fsms_sw_minor_w2_times);
   ctx.minor_w2_count = g_fsms_sw_minor_w2_count;

   // وضعیت MinorStarter / MinorOff
   ctx.minor_starter_u_active = g_minor_starter_u_active;
   ctx.minor_starter_d_active = g_minor_starter_d_active;
   ctx.minor_starter_u_idx    = g_minor_starter_u_idx;
   ctx.minor_starter_d_idx    = g_minor_starter_d_idx;
   ctx.minor_starter_u_tag    = g_minor_starter_u_tag;
   ctx.minor_starter_d_tag    = g_minor_starter_d_tag;
   ctx.minor_starter_u_LowW2_D  = g_minor_starter_u_LowW2_D;
   ctx.minor_starter_u_HighW3_D = g_minor_starter_u_HighW3_D;
   ctx.minor_starter_d_HighW2_U = g_minor_starter_d_HighW2_U;
   ctx.minor_starter_d_LowW3_U  = g_minor_starter_d_LowW3_U;
   ctx.minor_off_u_done   = g_minor_off_u_done;
   ctx.minor_off_d_done   = g_minor_off_d_done;
   ctx.minor_off_last_j   = g_minor_off_last_j;
   ctx.minor_u_seq        = g_minor_u_seq;
   ctx.minor_d_seq        = g_minor_d_seq;

   // --- Session registry (manual copy; ArrayCopy not allowed for structs with string) ---
   const int ssz = ArraySize(g_fsms_sw_sessions);
   ArrayResize(ctx.sessions, ssz);
   for(int i=0; i<ssz; ++i)
      ctx.sessions[i] = g_fsms_sw_sessions[i];
   ctx.sessions_count = ssz;
}


// Import: برگرداندن وضعیت ذخیره‌شدهٔ کانتکست به متغیرهای global
inline void FSMS_SW_ContextImport(const FSMS_SWContext &ctx)
{
   // Seed UP
   g_fsms_sw_up_active    = ctx.up_active;
   g_fsms_sw_up_c1_idx    = ctx.up_c1_idx;
   g_fsms_sw_up_level     = ctx.up_level;
   g_fsms_sw_up_seed_time = ctx.up_seed_time;
   g_fsms_sw_u_counter    = ctx.up_counter;
   g_fsms_sw_up_w3_c1_idx = ctx.up_w3_c1_idx;

   // Seed DOWN
   g_fsms_sw_dn_active    = ctx.dn_active;
   g_fsms_sw_dn_c1_idx    = ctx.dn_c1_idx;
   g_fsms_sw_dn_level     = ctx.dn_level;
   g_fsms_sw_dn_seed_time = ctx.dn_seed_time;
   g_fsms_sw_d_counter    = ctx.dn_counter;
   g_fsms_sw_dn_w3_c1_idx = ctx.dn_w3_c1_idx;

   // آخرین سطح C1_W2/W3_Minor
   g_C1_W2_Minor_U_Value = ctx.C1_W2_Minor_U_Value;
   g_C1_W3_Minor_U_Value = ctx.C1_W3_Minor_U_Value;
   g_C1_W2_Minor_D_Value = ctx.C1_W2_Minor_D_Value;
   g_C1_W3_Minor_D_Value = ctx.C1_W3_Minor_D_Value;

   // نگهبان موازی
   g_sw_guard_after_u = ctx.sw_guard_after_u;
   g_sw_guard_after_d = ctx.sw_guard_after_d;

   // لاگ مینور
   ArrayCopy(g_fsms_sw_minor_w2_times, ctx.minor_w2_times);
   g_fsms_sw_minor_w2_count = ctx.minor_w2_count;

   // وضعیت MinorStarter / MinorOff
   g_minor_starter_u_active = ctx.minor_starter_u_active;
   g_minor_starter_d_active = ctx.minor_starter_d_active;
   g_minor_starter_u_idx    = ctx.minor_starter_u_idx;
   g_minor_starter_d_idx    = ctx.minor_starter_d_idx;
   g_minor_starter_u_tag    = ctx.minor_starter_u_tag;
   g_minor_starter_d_tag    = ctx.minor_starter_d_tag;
   g_minor_starter_u_LowW2_D  = ctx.minor_starter_u_LowW2_D;
   g_minor_starter_u_HighW3_D = ctx.minor_starter_u_HighW3_D;
   g_minor_starter_d_HighW2_U = ctx.minor_starter_d_HighW2_U;
   g_minor_starter_d_LowW3_U  = ctx.minor_starter_d_LowW3_U;
   g_minor_off_u_done   = ctx.minor_off_u_done;
   g_minor_off_d_done   = ctx.minor_off_d_done;
   g_minor_off_last_j   = ctx.minor_off_last_j;
   g_minor_u_seq        = ctx.minor_u_seq;
   g_minor_d_seq        = ctx.minor_d_seq;

   // --- Session registry (manual copy; ArrayCopy not allowed for structs with string) ---
   const int ssz = ArraySize(ctx.sessions);
   ArrayResize(g_fsms_sw_sessions, ssz);
   for(int i=0; i<ssz; ++i)
      g_fsms_sw_sessions[i] = ctx.sessions[i];
   g_fsms_sw_sessions_count = ssz;
}


// ریست کامل وضعیت FSMS–SW در world فعلی
inline void FSMS_SW_ResetGlobals()
{
   // ریست Seedها و نگهبان موازی طبق منطق فعلی
   FSMS_SW_DisarmAll();        // g_fsms_sw_*_active/c1/level/seed_time و گاردها

   // ریست کامل لاگ و مینور استارتر / آُف
   FSMS_SW_MinorLog_Reset();

   // ریست شمارنده‌های مارکر FSMS–SW
   g_fsms_sw_u_counter = 0;
   g_fsms_sw_d_counter = 0;

   // ریست آخرین مقادیر C1_W2/W3_Minor
   g_C1_W2_Minor_U_Value = 0.0;
   g_C1_W3_Minor_U_Value = 0.0;
   g_C1_W2_Minor_D_Value = 0.0;
   g_C1_W3_Minor_D_Value = 0.0;
}

// ---------- فراخوانیِ موازی روی هر کندل (UP/DOWN) ----------
inline void FSMS_SW_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                             const double &bodyLowEff[], const double &bodyHighEff[],
                             const int n, const int upto_j)
{
   // ابطال فوری با HWX یا HWBB پس از FSMS
   if(g_fsms_sw_up_active)
   {
      if(__SW_ShouldDisarmOnHWMarkersSince(g_fsms_sw_up_seed_time))
      {
         if(InpDebugPrints) Print("[FSMS–SW] Disarm (UP) due to HWX/HWBB after FSMS.");
         __SW_Disarm_UP();
      }
   }
   if(g_fsms_sw_dn_active)
   {
      if(__SW_ShouldDisarmOnHWMarkersSince(g_fsms_sw_dn_seed_time))
      {
         if(InpDebugPrints) Print("[FSMS–SW] Disarm (DOWN) due to HWX/HWBB after FSMS.");
         __SW_Disarm_DN();
      }
   }

   // پایش «جفت خلاف‌جهت دوم»
   if(g_fsms_sw_up_active)   __SW_Scan_DN_After_FSMS_U(rates, insideHL, bodyLowEff, bodyHighEff, n, upto_j);
   if(g_fsms_sw_dn_active)   __SW_Scan_UP_After_FSMS_D(rates, insideHL, bodyLowEff, bodyHighEff, n, upto_j);
      // --- NEW: پایش MinorOff بعد از MinorStarter (مستقل از فعال بودن FSMS–SW)
   FSMS_SW_CheckMinorOff(rates, n, upto_j);
}

#endif // WAVEBOT_FSMS_SW_MQH
