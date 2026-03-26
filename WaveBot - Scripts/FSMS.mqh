// WaveBot/FSMS.mqh
#ifndef WAVEBOT_FSMS_MQH
#define WAVEBOT_FSMS_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/FSMS_Lifecycle.mqh>
#include <WaveBot/FSMS_SW.mqh>   // NEW: FSMS–SW

// وضعیت داخلی: اسکن DOWN پس از W3-UP و برعکس
enum FSMSState { FSMS_SEARCH_W2=0, FSMS_WAIT_CONFIRM=1 };

struct FSMSCtx
{
   // چارچوب کلی
   bool     w3_seen;          // W3 قبلاً تایید شده؟
   bool     c1_active;        // C1 هم‌جهت جاری فعال است؟
   bool     fired;            // FSMS برای این W3 ثبت شده؟
   datetime c1_time;          // زمان C1 هم‌جهت (از همین‌جا پایش شروع می‌شود)
   int      c1_index;         // اندیس C1 هم‌جهت
   int      idx;              // اندیس پیشروی حلقهٔ داخلی
   int      state;            // FSMS_SEARCH_W2 | FSMS_WAIT_CONFIRM

   // موج۲ مخالف که دنبال آنیم
   int      c1,c2,c3,c4,cend;

   // موج۳ مخالف
   bool     have_w3;
   int      w3_c1, k2,k3,k4, w3_end;
   int      w3_cand;
   double   w3_cand_low, w3_cand_high;

   // مدیریت body-break (مسیر مخالف)
   bool     wickActive;
   int      firstWickIdx, wickBreakIdx;
   double   bodyBreakLevel;
   bool     breakAchieved;
   int      bodyBreakIdx;

   // نگهبان پس از body-break تا تکمیل W3
   bool     postBreak_c1_lock;
   int      postBreak_c1_ref;

   // وفاداری به C1 موج۲ مخالف در پنجره‌ی FSMS (کاملاً مشابه C1Pre_* نرمال)
   bool   prelock_active;
   int    prelock_idx;
   double prelock_level;  // برای DOWN: L1(C1) | برای UP: H1(C1)
   
      // موج‌های هم‌جهت که FSMS بر اساس آن‌ها شکل گرفته
   int      same_w3_c1_index;   // اندیس C1 موج۳ هم‌جهت (W3 اصلی)
   datetime same_w3_c1_time;    // زمان C1 موج۳ هم‌جهت
};

// دو زمینه: پس از W3-UP، اسکن DOWN ⇒ FSMS_U؛ پس از W3-DOWN، اسکن UP ⇒ FSMS_D
static FSMSCtx g_fsms_from_up;
static FSMSCtx g_fsms_from_dn;

static int g_fsms_u_counter=0, g_fsms_d_counter=0;
// ------------------------------
// Context snapshot for FSMS (W3-based cross-direction scans)
// ------------------------------
struct FSMSContext
{
   // پس از W3-UP: اسکن موج‌های مخالف در جهت DOWN
   FSMSCtx from_up;

   // پس از W3-DOWN: اسکن موج‌های مخالف در جهت UP
   FSMSCtx from_dn;

   // شمارنده‌های مارکر برای دیباگ
   int     u_counter;   // FSMS_U_*
   int     d_counter;   // FSMS_D_*
};

inline void __FSMS_Reset(FSMSCtx &S)
{
   S.w3_seen=false; S.c1_active=false; S.fired=false; S.c1_time=0; S.c1_index=-1;
   S.idx=-1; S.state=FSMS_SEARCH_W2;

   S.c1=S.c2=S.c3=S.c4=S.cend=-1;

   S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
   S.w3_cand=-1; S.w3_cand_low=DBL_MAX; S.w3_cand_high=-DBL_MAX;

   S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
   S.bodyBreakLevel=0.0; S.breakAchieved=false; S.bodyBreakIdx=-1;

   S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

   S.prelock_active = false;
   S.prelock_idx    = -1;
   S.prelock_level  = 0.0;

   // NEW: ریست اطلاعات موج۳ هم‌جهت
   S.same_w3_c1_index = -1;
   S.same_w3_c1_time  = 0;
}

inline void __FSMS_ResetKeepW3(FSMSCtx &S)
{
   const bool     had_w3  = S.w3_seen;
   const int      w3_idx  = S.same_w3_c1_index;
   const datetime w3_time = S.same_w3_c1_time;

   __FSMS_Reset(S);

   S.w3_seen          = had_w3;
   S.same_w3_c1_index = w3_idx;
   S.same_w3_c1_time  = w3_time;
}

inline void __FSMS_ApplyLifecycleTransition()
{
   if(!FSMSLC_HasTerminalRequest())
      return;

   int owner = FSMSLC_OWNER_NONE;
   int term_kind = FSMSLC_TERM_NONE;
   datetime term_time = 0;
   FSMSLC_PeekTerminal(owner, term_kind, term_time);

   if(owner == FSMSLC_OWNER_UP)
   {
      if(term_kind == FSMSLC_TERM_HWBB)
         __FSMS_Reset(g_fsms_from_up);
      else
         __FSMS_ResetKeepW3(g_fsms_from_up);
   }
   else if(owner == FSMSLC_OWNER_DN)
   {
      if(term_kind == FSMSLC_TERM_HWBB)
         __FSMS_Reset(g_fsms_from_dn);
      else
         __FSMS_ResetKeepW3(g_fsms_from_dn);
   }
   else
   {
      __FSMS_Reset(g_fsms_from_up);
      __FSMS_Reset(g_fsms_from_dn);
   }

   FSMSLC_FinishTerminal(term_time);
}

inline bool __FSMS_CanOpenAt(const datetime t)
{
   __FSMS_ApplyLifecycleTransition();
   return FSMSLC_CanOpenAt(t);
}

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
inline void FSMS_ContextInit(FSMSContext &ctx)
{
   __FSMS_Reset(ctx.from_up);
   __FSMS_Reset(ctx.from_dn);
   ctx.u_counter = 0;
   ctx.d_counter = 0;
}

// Export: کپی وضعیت فعلی globalها به داخل کانتکست
inline void FSMS_ContextExport(FSMSContext &ctx)
{
   ctx.from_up   = g_fsms_from_up;
   ctx.from_dn   = g_fsms_from_dn;
   ctx.u_counter = g_fsms_u_counter;
   ctx.d_counter = g_fsms_d_counter;
}

// Import: برگرداندن کانتکست ذخیره‌شده به متغیرهای global
inline void FSMS_ContextImport(const FSMSContext &ctx)
{
   g_fsms_from_up   = ctx.from_up;
   g_fsms_from_dn   = ctx.from_dn;
   g_fsms_u_counter = ctx.u_counter;
   g_fsms_d_counter = ctx.d_counter;
}

// ریست کامل وضعیت FSMS در world فعلی
inline void FSMS_ResetGlobals()
{
   __FSMS_Reset(g_fsms_from_up);
   __FSMS_Reset(g_fsms_from_dn);
   g_fsms_u_counter = 0;
   g_fsms_d_counter = 0;
   FSMSLC_ResetGlobals();
}

inline void FSMS_DisarmAll()
{
   __FSMS_Reset(g_fsms_from_up);
   __FSMS_Reset(g_fsms_from_dn);
   FSMSLC_ResetGlobals();
}

// --- مرحله 1: ثبت W3 (هنوز پایش FSMS شروع نمی‌شود)
inline void FSMS_OnW3Confirmed_UP(const MqlRates &rates[], const int n, const int w3_c1_index)
{
   datetime evt_t = TimeCurrent();
   if(w3_c1_index >= 0 && w3_c1_index < n)
      evt_t = rates[w3_c1_index].time;

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   FSMS_DisarmAll();
   g_fsms_from_up.w3_seen = true;

   if(w3_c1_index >= 0 && w3_c1_index < n)
   {
      g_fsms_from_up.same_w3_c1_index = w3_c1_index;
      g_fsms_from_up.same_w3_c1_time  = rates[w3_c1_index].time;
   }
   else
   {
      g_fsms_from_up.same_w3_c1_index = -1;
      g_fsms_from_up.same_w3_c1_time  = 0;
   }
}

inline void FSMS_OnW3Confirmed_DOWN(const MqlRates &rates[], const int n, const int w3_c1_index)
{
   datetime evt_t = TimeCurrent();
   if(w3_c1_index >= 0 && w3_c1_index < n)
      evt_t = rates[w3_c1_index].time;

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   FSMS_DisarmAll();
   g_fsms_from_dn.w3_seen = true;

   if(w3_c1_index >= 0 && w3_c1_index < n)
   {
      g_fsms_from_dn.same_w3_c1_index = w3_c1_index;
      g_fsms_from_dn.same_w3_c1_time  = rates[w3_c1_index].time;
   }
   else
   {
      g_fsms_from_dn.same_w3_c1_index = -1;
      g_fsms_from_dn.same_w3_c1_time  = 0;
   }
}

// --- مرحله 2: اولین C1 موج۲ هم‌جهت ظاهر شد ⇒ آغـاز پنجرهٔ FSMS از همین کندل
inline void FSMS_OnSameDirC1_First_UP(const MqlRates &rates[], const int n, const int idx)
{
   const int safe_idx = (idx>=0 && idx<n ? idx : 0);
   const datetime evt_t = (n>0 ? rates[safe_idx].time : TimeCurrent());

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   // شروع تازه از C1 جدید؛ وضعیت W3 هم‌جهت را نگه می‌داریم
   const bool     was_w3        = g_fsms_from_up.w3_seen;
   const int      was_w3_c1_idx = g_fsms_from_up.same_w3_c1_index;
   const datetime was_w3_c1_t   = g_fsms_from_up.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_up);

   g_fsms_from_up.w3_seen           = was_w3;
   g_fsms_from_up.same_w3_c1_index  = was_w3_c1_idx;
   g_fsms_from_up.same_w3_c1_time   = was_w3_c1_t;

   g_fsms_from_up.c1_active = true;
   g_fsms_from_up.c1_index  = safe_idx;
   g_fsms_from_up.c1_time   = evt_t;
   g_fsms_from_up.idx       = g_fsms_from_up.c1_index;
   g_fsms_from_up.state     = FSMS_SEARCH_W2;

   g_fsms_from_up.prelock_active = false;
   g_fsms_from_up.prelock_idx    = -1;
   g_fsms_from_up.prelock_level  = 0.0;
}

inline void FSMS_OnSameDirC1_First_DOWN(const MqlRates &rates[], const int n, const int idx)
{
   const int safe_idx = (idx>=0 && idx<n ? idx : 0);
   const datetime evt_t = (n>0 ? rates[safe_idx].time : TimeCurrent());

   if(!__FSMS_CanOpenAt(evt_t))
      return;

   const bool     was_w3        = g_fsms_from_dn.w3_seen;
   const int      was_w3_c1_idx = g_fsms_from_dn.same_w3_c1_index;
   const datetime was_w3_c1_t   = g_fsms_from_dn.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_dn);

   g_fsms_from_dn.w3_seen           = was_w3;
   g_fsms_from_dn.same_w3_c1_index  = was_w3_c1_idx;
   g_fsms_from_dn.same_w3_c1_time   = was_w3_c1_t;

   g_fsms_from_dn.c1_active = true;
   g_fsms_from_dn.c1_index  = safe_idx;
   g_fsms_from_dn.c1_time   = evt_t;
   g_fsms_from_dn.idx       = g_fsms_from_dn.c1_index;
   g_fsms_from_dn.state     = FSMS_SEARCH_W2;

   g_fsms_from_dn.prelock_active = false;
   g_fsms_from_dn.prelock_idx    = -1;
   g_fsms_from_dn.prelock_level  = 0.0;
}

// --- مرحله 3: ابطال C1 هم‌جهت (re-anchor) ⇒ ریست و شروع از C1 جدید
inline void FSMS_OnSameDirC1_Reanchor_UP(const MqlRates &rates[], const int n, const int i)
{
   FSMS_OnSameDirC1_First_UP(rates,n,i);
}

inline void FSMS_OnSameDirC1_Reanchor_DOWN(const MqlRates &rates[], const int n, const int i)
{
   FSMS_OnSameDirC1_First_DOWN(rates,n,i);
}

// --- مرحله 3.5: ابطال W2/C1 هم‌جهت ⇒ پنجرهٔ FSMS از نو (در همان W3)
// نکته: اگر FSMS برای همین W3 قبلاً فایر شده، «فایر بودن» حفظ می‌شود و re-arm نمی‌شویم.

inline void FSMS_OnSameDirW2Invalidated_UP()
{
   __FSMS_ApplyLifecycleTransition();
   if(FSMSLC_HasPending()) return;

   bool     fired_prev      = g_fsms_from_up.fired;
   bool     w3_prev         = g_fsms_from_up.w3_seen;
   int      w3_c1_prev_idx  = g_fsms_from_up.same_w3_c1_index;
   datetime w3_c1_prev_time = g_fsms_from_up.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_up);

   g_fsms_from_up.w3_seen          = w3_prev;
   g_fsms_from_up.fired            = fired_prev;
   g_fsms_from_up.same_w3_c1_index = w3_c1_prev_idx;
   g_fsms_from_up.same_w3_c1_time  = w3_c1_prev_time;
}

inline void FSMS_OnSameDirW2Invalidated_DOWN()
{
   __FSMS_ApplyLifecycleTransition();
   if(FSMSLC_HasPending()) return;

   bool     fired_prev      = g_fsms_from_dn.fired;
   bool     w3_prev         = g_fsms_from_dn.w3_seen;
   int      w3_c1_prev_idx  = g_fsms_from_dn.same_w3_c1_index;
   datetime w3_c1_prev_time = g_fsms_from_dn.same_w3_c1_time;

   __FSMS_Reset(g_fsms_from_dn);

   g_fsms_from_dn.w3_seen          = w3_prev;
   g_fsms_from_dn.fired            = fired_prev;
   g_fsms_from_dn.same_w3_c1_index = w3_c1_prev_idx;
   g_fsms_from_dn.same_w3_c1_time  = w3_c1_prev_time;
}

// مارک‌ها
inline void __FSMS_Mark_UP(const datetime t)
{
   ++g_fsms_u_counter;
   if(InpDrawMarkers)
      MarkV("FSMS_U_"+IntegerToString(g_fsms_u_counter), t, clrWhite);

   FSMSLC_OnFormed(DIR_UP, t);

   // NEW (H4->M15 bridge): FSMS (MAJ-only) is a START trigger (on close)
   WB15_PublishStartFSMS_MAJONLY(InpSymbol, DIR_UP, t);
}
inline void __FSMS_Mark_DN(const datetime t)
{
   ++g_fsms_d_counter;
   if(InpDrawMarkers)
      MarkV("FSMS_D_"+IntegerToString(g_fsms_d_counter), t, clrWhite);

   FSMSLC_OnFormed(DIR_DOWN, t);

   // NEW (H4->M15 bridge): FSMS (MAJ-only) is a START trigger (on close)
   WB15_PublishStartFSMS_MAJONLY(InpSymbol, DIR_DOWN, t);
}

// --- NEW: Text روی C1 موج۲ و C1 موج۳ هم‌جهتِ منبع FSMS (UP) ---
inline void __FSMS_DrawSourceTexts_UP(const MqlRates &rates[], const int n,
                                      const FSMSCtx &S, const int fsms_id)
{
   if(!InpDrawMarkers) return;

   // C1 موج۲ هم‌جهت (W2 اصلی که بعداً FSMS را فعال می‌کند)
   if(S.c1_index >= 0 && S.c1_index < n)
   {
      const MqlRates r = rates[S.c1_index];
      double span = r.high - r.low;
      if(span <= 0.0) span = 10 * _Point;
      double pad = span * 0.25;
      if(pad < 3 * _Point) pad = 3 * _Point;
      double y = r.high + pad;

      string name = "FSMS_SRC_U_W2_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name, r.time, y, "FSMS_W2", clrYellow);
   }

   // C1 موج۳ هم‌جهت (W3 اصلیِ قبل از FSMS)
   if(S.same_w3_c1_index >= 0 && S.same_w3_c1_index < n)
   {
      const MqlRates r2 = rates[S.same_w3_c1_index];
      double span2 = r2.high - r2.low;
      if(span2 <= 0.0) span2 = 10 * _Point;
      double pad2 = span2 * 0.25;
      if(pad2 < 3 * _Point) pad2 = 3 * _Point;
      double y2 = r2.high + pad2;

      string name2 = "FSMS_SRC_U_W3_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name2, r2.time, y2, "FSMS_W3", clrOrange);
   }
}

// --- NEW: Text روی C1 موج۲ و موج۳ هم‌جهتِ منبع FSMS (DOWN) ---
inline void __FSMS_DrawSourceTexts_DN(const MqlRates &rates[], const int n,
                                      const FSMSCtx &S, const int fsms_id)
{
   if(!InpDrawMarkers) return;

   // C1 موج۲ هم‌جهت (جفت نزولی)
   if(S.c1_index >= 0 && S.c1_index < n)
   {
      const MqlRates r = rates[S.c1_index];
      double span = r.high - r.low;
      if(span <= 0.0) span = 10 * _Point;
      double pad = span * 0.25;
      if(pad < 3 * _Point) pad = 3 * _Point;
      double y = r.low - pad;

      string name = "FSMS_SRC_D_W2_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name, r.time, y, "FSMS_W2", clrYellow);
   }

   // C1 موج۳ هم‌جهت (W3 نزولی منبع FSMS_D)
   if(S.same_w3_c1_index >= 0 && S.same_w3_c1_index < n)
   {
      const MqlRates r2 = rates[S.same_w3_c1_index];
      double span2 = r2.high - r2.low;
      if(span2 <= 0.0) span2 = 10 * _Point;
      double pad2 = span2 * 0.25;
      if(pad2 < 3 * _Point) pad2 = 3 * _Point;
      double y2 = r2.low - pad2;

      string name2 = "FSMS_SRC_D_W3_C1_" + IntegerToString(fsms_id);
      MarkCandleText(name2, r2.time, y2, "FSMS_W3", clrOrange);
   }
}

// کمک‌کارهای اکسترمای موضعی (با اسکیپ inside)
inline int __LeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[], const int from, const int to){
   if(from>to) return -1; double mx=-DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){ if(insideHL[i]) continue; if(rates[i].high>mx){mx=rates[i].high; idx=i;} }
   if(idx<0) idx=from; return idx;
}
inline int __LeftmostMinLow_ExInside(const MqlRates &rates[], const bool &insideHL[], const int from, const int to){
   if(from>to) return -1; double mn=DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){ if(insideHL[i]) continue; if(rates[i].low<mn){mn=rates[i].low; idx=i;} }
   if(idx<0) idx=from; return idx;
}

// --- حلقهٔ اصلی پایش: حتماً قبل از HWBB صدا بزنید ---
inline void FSMS_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                          const double &bodyLowEff[], const double &bodyHighEff[],
                          const int n, const int upto_j)
{
   if(n <= 0 || upto_j < 0 || upto_j >= n) return;

   __FSMS_ApplyLifecycleTransition();
   if(!FSMSLC_CanOpenAt(rates[upto_j].time)) return;

   // ===== پس از W3-UP: دنبال DOWN (FSMS_U) وقتی C1-UP فعال است =====
   if(g_fsms_from_up.w3_seen && g_fsms_from_up.c1_active && !g_fsms_from_up.fired)
   {
      FSMSCtx S=g_fsms_from_up;
      if(upto_j>=0 && upto_j<n && rates[upto_j].time >= S.c1_time)
      {
         const int limit=upto_j;
         while(S.idx<=limit)
         {
            if(S.state==FSMS_SEARCH_W2)
            {
               bool found=false;
               for(int i=S.idx;i<=limit;++i)
               {
                  if(insideHL[i]) continue;
                  int i2=-1,i3=-1,i4=-1;
         
                  // --- FSMS pre-lock for C1 (DOWN) — عینا مثل C1Pre_DN -------------------
                  if(!S.prelock_active)
                  {
                     S.prelock_active = true;
                     S.prelock_idx    = i;
                     S.prelock_level  = rates[i].low;   // L1(C1)
                  }
                  else
                  {
                     if(i == S.prelock_idx)
                     {
                        // همان C1 قبلی؛ مجاز به بررسی هستیم
                     }
                     else if(i > S.prelock_idx)
                     {
                        // فقط اگر Low جدید، L1 قبلی را بشکند ⇒ C1 جدید
                        if(rates[i].low < S.prelock_level)
                        {
                           S.prelock_idx   = i;
                           S.prelock_level = rates[i].low;
                        }
                        else
                        {
                           // وفاداری به C1 قبلی ⇒ این i اصلا کاندید C1 نیست
                           continue;
                        }
                     }
                     else
                     {
                        // i < prelock_idx در عمل نباید رخ دهد (حلقه رو به جلو)؛
                        // برای ایمنی، ردش می‌کنیم
                        continue;
                     }
                  }
                  // -----------------------------------------------------------------------

                  if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;

                  S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

                  // ریست وضعیت W3 (DOWN)
                  S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
                  S.w3_cand=-1;   S.w3_cand_high=-DBL_MAX;

                  // مدیریت بریک با بدنه (DOWN)
                  S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
                  S.bodyBreakLevel=rates[S.c1].low; S.breakAchieved=false; S.bodyBreakIdx=-1;

                  S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

                  S.idx=S.cend; S.state=FSMS_WAIT_CONFIRM;
                  S.prelock_active = false;  // NEW: قفل FSMS تا تکلیف این W2 مشخص شود
                  found=true; break;
               }
               if(!found){ S.idx=limit+1; break; }
            }
            else // FSMS_WAIT_CONFIRM (DOWN)
            {
               bool progressed=false;
               for(int j=S.idx;j<=limit;++j)
               {
                  if(insideHL[j]) continue;

                  // wick escalation (DOWN)
                  if(!S.breakAchieved)
                  {
                     if(rates[j].low < S.bodyBreakLevel)
                     {
                        if(rates[j].close < S.bodyBreakLevel)
                        {
                           S.breakAchieved=true; S.bodyBreakIdx=j;
                           int __c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                           S.postBreak_c1_ref=__c1_eff; S.postBreak_c1_lock=(__c1_eff>=0);
                        }
                        else
                        {
                           S.bodyBreakLevel=rates[j].low;
                           if(S.firstWickIdx<0)
                           {
                              S.firstWickIdx=j; S.wickBreakIdx=j; S.wickActive=true;
                              int anchorC1=__LeftmostMaxHigh_ExInside(rates,insideHL,S.cend,S.firstWickIdx);
                              S.have_w3=false; S.w3_c1=anchorC1; S.w3_cand=-1; S.w3_cand_high=-DBL_MAX;
                           }
                        }
                     }
                  }

                  // ChainInvalidation (pre-body, wick-window, DOWN)
                  { int __rew=-1;
                    if(ChainInv_PreBody_WickWindow_DN_OnBar(rates,insideHL,n,j,S.breakAchieved,S.wickActive,S.firstWickIdx,S.w3_c1,S.w3_cand,__rew))
                     { 
                          S.idx  = __rew; 
                          S.state= FSMS_SEARCH_W2; 
                     
                          // --- NEW: ریست کامل prelock برای پنجره‌ی بعدی FSMS ---
                          S.prelock_active = false;
                          S.prelock_idx    = -1;
                          S.prelock_level  = 0.0;
                          // -------------------------------------------------------
                     
                          progressed = true; 
                          break; 
                       }
                     }

                  // RESET W3 (non-wick, pre-body): H > H(C1_W3)
                  if(!S.wickActive && !S.breakAchieved)
                  {
                     int c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1_eff>=0 && rates[j].high > rates[c1_eff].high)
                     { S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1=-1; S.w3_cand=j; S.w3_cand_high=rates[j].high; continue; }
                  }

                  // direct-path anchor: بزرگ‌ترین High پس از cend
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

                  // نگهبان: تغییر C1_W3 بعد از body-break ⇒ ابطال W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1n=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(!S.postBreak_c1_lock && c1n>=0){ S.postBreak_c1_ref=c1n; S.postBreak_c1_lock=true; }
                     else if(S.postBreak_c1_lock && c1n>=0 && c1n!=S.postBreak_c1_ref)
                     { 
                        S.idx   = (S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j); 
                        S.state = FSMS_SEARCH_W2;
                  
                        // --- NEW: ریست کامل prelock این پنجره ---
                        S.prelock_active = false;
                        S.prelock_idx    = -1;
                        S.prelock_level  = 0.0;
                        // -----------------------------------------
                  
                        progressed = true; 
                        break; 
                     }

                  }

                  // پس از body-break تا قبل از پایان W3: H > H(C1_W3) ⇒ ابطال W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1e=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1e>=0 && rates[j].high > rates[c1e].high)
                     { S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; }
                  }

                  // نهایی: اولین جفتِ DOWN با body-break ⇒ FSMS_U
                  if(S.have_w3 && S.breakAchieved)
                  {
                     datetime bt = rates[(S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j)].time;

                     // بذر FSMS–SW (UP) بر اساس C1 موج۲ + C1 موج۳ هم‌جهت منبع FSMS
                     FSMS_SW_UP_ActivateSeed(rates, n,
                                             S.c1_index,          // C1 موج۲ اصلی
                                             S.same_w3_c1_index,  // C1 موج۳ اصلی
                                             bt);

                     // مارکر FSMS_U روی کندل FSMS
                     __FSMS_Mark_UP(bt);

                     // از این به بعد FSMS_W2 / FSMS_W3 دیگر روی چارت نمایش داده نمی‌شوند؛
                     // فقط در لحظه‌ای که همین FSMS به FSMS_Minor تبدیل شد،
                     // Textهای C1_W2_Minor_* و C1_W3_Minor_* در FSMS_SW رسم خواهند شد.

                     S.fired      = true;
                     S.c1_active  = false;
                     g_fsms_from_up = S;
                     return;
                  }
               }
               if(!progressed){ S.idx=limit+1; }
            }
         }
      }
      g_fsms_from_up=S;
   }

   // ===== پس از W3-DOWN: دنبال UP (FSMS_D) وقتی C1-DN فعال است =====
   if(g_fsms_from_dn.w3_seen && g_fsms_from_dn.c1_active && !g_fsms_from_dn.fired)
   {
      FSMSCtx S=g_fsms_from_dn;
      if(upto_j>=0 && upto_j<n && rates[upto_j].time >= S.c1_time)
      {
         const int limit=upto_j;
         while(S.idx<=limit)
         {
            if(S.state==FSMS_SEARCH_W2)
            {
               bool found=false;
               for(int i=S.idx;i<=limit;++i)
               {
                  if(insideHL[i]) continue;
                  int i2=-1,i3=-1,i4=-1;

                  // --- FSMS pre-lock for C1 (UP) — عینا مثل C1Pre_UP --------------------
                  if(!S.prelock_active)
                  {
                     S.prelock_active = true;
                     S.prelock_idx    = i;
                     S.prelock_level  = rates[i].high;  // H1(C1)
                  }
                  else
                  {
                     if(i == S.prelock_idx)
                     {
                        // همان C1 قبلی
                     }
                     else if(i > S.prelock_idx)
                     {
                        // فقط اگر High جدید، H1 قبلی را بشکند ⇒ C1 جدید
                        if(rates[i].high > S.prelock_level)
                        {
                           S.prelock_idx   = i;
                           S.prelock_level = rates[i].high;
                        }
                        else
                        {
                           // وفاداری به C1 قبلی
                           continue;
                        }
                     }
                     else
                     {
                        // i < prelock_idx ⇒ برای ایمنی رد می‌کنیم
                        continue;
                     }
                  }
                  // -----------------------------------------------------------------------
         
                  if(!CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;
                  
                  S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

                  S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
                  S.w3_cand=-1;   S.w3_cand_low=DBL_MAX;

                  S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
                  S.bodyBreakLevel=rates[S.c1].high; S.breakAchieved=false; S.bodyBreakIdx=-1;

                  S.postBreak_c1_lock=false; S.postBreak_c1_ref=-1;

                  S.idx=S.cend; S.state=FSMS_WAIT_CONFIRM;
                  S.prelock_active = false;  // NEW: قفل FSMS تا تکلیف این W2 مشخص شود
                  found=true; break;
               }
               if(!found){ S.idx=limit+1; break; }
            }
            else // FSMS_WAIT_CONFIRM (UP)
            {
               bool progressed=false;
               for(int j=S.idx;j<=limit;++j)
               {
                  if(insideHL[j]) continue;

                  // wick escalation (UP)
                  if(!S.breakAchieved)
                  {
                     if(rates[j].high > S.bodyBreakLevel)
                     {
                        if(rates[j].close > S.bodyBreakLevel)
                        {
                           S.breakAchieved=true; S.bodyBreakIdx=j;
                           int __c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                           S.postBreak_c1_ref=__c1_eff; S.postBreak_c1_lock=(__c1_eff>=0);
                        }
                        else
                        {
                           S.bodyBreakLevel=rates[j].high;
                           if(S.firstWickIdx<0)
                           {
                              S.firstWickIdx=j; S.wickBreakIdx=j; S.wickActive=true;
                              int anchorC1=__LeftmostMinLow_ExInside(rates,insideHL,S.cend,S.firstWickIdx);
                              S.have_w3=false; S.w3_c1=anchorC1; S.w3_cand=-1; S.w3_cand_low=DBL_MAX;
                           }
                        }
                     }
                  }

                  // ChainInvalidation (pre-body, wick-window, UP)
                  { int __rew=-1;
                    if(ChainInv_PreBody_WickWindow_UP_OnBar(rates,insideHL,n,j,S.breakAchieved,S.wickActive,S.firstWickIdx,S.w3_c1,S.w3_cand,__rew))
                    { S.idx=__rew; S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; } }

                  // RESET W3 (non-wick, pre-body): L < L(C1_W3)
                  if(!S.wickActive && !S.breakAchieved)
                  {
                     int c1_eff=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1_eff>=0 && rates[j].low < rates[c1_eff].low)
                     { S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_cand=j; S.w3_cand_low=rates[j].low; S.w3_c1=-1; continue; }
                  }

                  // direct-path anchor: کمترین Low پس از cend
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

                  // نگهبان: تغییر C1_W3 بعد از body-break ⇒ ابطال W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1n=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(!S.postBreak_c1_lock && c1n>=0){ S.postBreak_c1_ref=c1n; S.postBreak_c1_lock=true; }
                     else if(S.postBreak_c1_lock && c1n>=0 && c1n!=S.postBreak_c1_ref)
                     { S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; }
                  }

                  // پس از body-break تا قبل از پایان W3: L < L(C1_W3) ⇒ ابطال W2
                  if(S.breakAchieved && !S.have_w3)
                  {
                     int c1e=(S.w3_c1>=0?S.w3_c1:S.w3_cand);
                     if(c1e>=0 && rates[j].low < rates[c1e].low)
                     { S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j); S.state=FSMS_SEARCH_W2;
                     S.prelock_active = false;  // NEW
                     S.prelock_idx    = -1;
                     S.prelock_level  = 0.0;
                     progressed=true; break; }
                  }

                  // نهایی: اولین جفتِ UP با body-break ⇒ FSMS_D
                  if(S.have_w3 && S.breakAchieved)
                  {
                     datetime bt = rates[(S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j)].time;

                     // بذر FSMS–SW (DOWN) بر اساس C1 موج۲ + C1 موج۳ هم‌جهت منبع FSMS
                     FSMS_SW_DN_ActivateSeed(rates, n,
                                             S.c1_index,          // C1 موج۲ اصلی نزولی
                                             S.same_w3_c1_index,  // C1 موج۳ اصلی نزولی
                                             bt);

                     // مارکر FSMS_D
                     __FSMS_Mark_DN(bt);

                     // هیچ Text با نام FSMS_W2 / FSMS_W3 دیگر رسم نمی‌شود

                     S.fired      = true;
                     S.c1_active  = false;
                     g_fsms_from_dn = S;
                     return;
                  }
               }
               if(!progressed){ S.idx=limit+1; }
            }
         }
      }
      g_fsms_from_dn=S;
   }
}

#endif // WAVEBOT_FSMS_MQH
