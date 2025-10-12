//+------------------------------------------------------------------+
//| WaveBot - RaceCoordinator                                        |
//| پس از نمایش HWBB: قفل مسابقه + پایش دو مسیر A/B تا تعیین برنده |
//| مسیر A (تداوم): SW هم‌جهت  /  مسیر B (چرخش): W2→W3 خلاف‌جهت     |
//+------------------------------------------------------------------+
#ifndef WAVEBOT_RACECOORDINATOR_MQH
#define WAVEBOT_RACECOORDINATOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Utils.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>          // UP W2
#include <WaveBot/Wave3.mqh>          // UP W3
#include <WaveBot/Wave2_Down.mqh>     // DOWN W2
#include <WaveBot/Wave3_Down.mqh>     // DOWN W3
#include <WaveBot/W2W3_ChainInvalidation.mqh>

//------------------------------ وضعیت کلی مسابقه ------------------------------
static bool      g_race_locked       = false;
static Direction g_race_mode         = DIR_UP;   // Mode لحظهٔ شروع مسابقه
static int       g_race_hwbb_idx     = -1;       // ایندکس کندل HWBB
static datetime  g_race_hwbb_time    = 0;        // زمان HWBB
static string    g_race_winner       = "";       // "A" یا "B"
static datetime  g_race_winner_time  = 0;
static int       g_race_counter      = 0;        // برای نام‌گذاری مارکرها
// نقطهٔ مرجع برای ترسیم بعد از MTC
static double   g_race_ref_mtc_up   = 0.0;  // mtc_up ⇒ Lowِ C1ِ Hunter(DOWN)
static double   g_race_ref_mtc_down = 0.0;  // mtc_down ⇒ Highِ C1ِ Hunter(UP)

// ست‌کننده‌ها (از Hunter_BodyBreak فراخوانی می‌شوند)
inline void Race_SetRefLevelForMTC_Up(const double price)   { g_race_ref_mtc_up   = price; }
inline void Race_SetRefLevelForMTC_Down(const double price) { g_race_ref_mtc_down = price; }

enum RState { R_IDLE=0, R_SEARCH_W2=1, R_WAIT_CONFIRM=2 };

// وضعیت داخلی مسیر B برای هر حالت
struct RacePathBState
{
   bool     init;
   int      state;            // R_SEARCH_W2 / R_WAIT_CONFIRM
   int      idx;              // نشانگر پیشروی محلی

   // W2 جاری
   int      c1,c2,c3,c4,cend;

   // وضعیت W3
   bool     have_w3;
   int      w3_c1, k2,k3,k4, w3_end;

   // کاندید C1 برای مسیر مستقیم
   int      w3_cand;
   double   w3_cand_low;      // برای اسکن UP
   double   w3_cand_high;     // برای اسکن DOWN

   // مدیریت wick/body-break
   bool     wickActive;
   int      firstWickIdx, wickBreakIdx;
   double   bodyBreakLevel;
   bool     breakAchieved;
   int      bodyBreakIdx;
   
   // --- NEW: MTC candidate tracking (mirrored for both directions)
   int      mtc_c1_cand;     // current C1 candidate index (starts at HWBB)
   double   mtc_c1_level;    // invalidation level: LOW for DOWN-scan, HIGH for UP-scan
};

static RacePathBState g_pb_up;    // وقتی Mode=UP است (مسیر B = اسکن DOWN)
static RacePathBState g_pb_down;  // وقتی Mode=DOWN است (مسیر B = اسکن UP)

inline void Race_ResetPathB(RacePathBState &S)
{
   S.init=false; S.state=R_IDLE; S.idx=-1;
   S.c1=S.c2=S.c3=S.c4=S.cend=-1;
   S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
   S.w3_cand=-1; S.w3_cand_low=DBL_MAX; S.w3_cand_high=-DBL_MAX;
   S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
   S.bodyBreakLevel=0.0; S.breakAchieved=false; S.bodyBreakIdx=-1;
   S.mtc_c1_cand = -1;
   S.mtc_c1_level = 0.0;
}

inline void Race_InternalClearAll()
{
   g_race_locked=false;
   g_race_mode=DIR_UP;
   g_race_hwbb_idx=-1; g_race_hwbb_time=0;
   g_race_winner=""; g_race_winner_time=0;
   Race_ResetPathB(g_pb_up);
   Race_ResetPathB(g_pb_down);
   g_race_ref_mtc_up   = 0.0;
   g_race_ref_mtc_down = 0.0;
}

inline bool Race_IsLocked() { return g_race_locked; }

// --- NEW: fail-safe unlock on new ext LQ (called by Hunter side)
// اگر مسابقه قفل باشد و از سمت مقابلِ مود فعلی ext lq جدیدی با زمان بعد از HWBB برسد، قفل را باز کن.
inline void Race_TryUnlockOnNewLQ_Notify(const Direction lq_side, const datetime lq_time)
{
   if(!g_race_locked) return;
   if(lq_time <= 0 || lq_time < g_race_hwbb_time) return;

   // اگر مسابقه با Mode=UP شروع شده، ext lq معتبرِ سمت DOWN نشانه‌ی برنده بودن B است (و بالعکس)
   if(g_race_mode == DIR_UP  && lq_side == DIR_DOWN){ Race_InternalClearAll(); return; }
   if(g_race_mode == DIR_DOWN&& lq_side == DIR_UP  ){ Race_InternalClearAll(); return; }
}

// مارکرهای خروجی مسابقه
inline void Race_MarkStart(const Direction mode, const datetime t)
{
   ++g_race_counter;
   const string tag = IntegerToString(g_race_counter);
   MarkV( (mode==DIR_UP ? "RACE_START_HWBB_U_" : "RACE_START_HWBB_D_") + tag, t, clrYellow );
}

inline void Race_MarkWin_A(const Direction mode, const datetime t)
{
   const string tag = IntegerToString(g_race_counter);
   MarkV( (mode==DIR_UP ? "RACE_A_SW_WIN_U_" : "RACE_A_SW_WIN_D_") + tag, t, (mode==DIR_UP?clrAqua:clrDarkOrange) );
}

inline void Race_MarkWin_B(const Direction mode, const datetime t)
{
   const string tag = IntegerToString(g_race_counter);
   MarkV( (mode==DIR_UP ? "MTC_D_" : "MTC_U_") + tag, t, (mode==DIR_UP?clrFireBrick:clrLime) );
}

//--------------------------- شروع مسابقه از HWBB ------------------------------
inline void Race_Start_UP(const MqlRates &rates[], const int n, const int hwbb_idx)
{
   if(g_race_locked) return; // امنیت
   g_race_locked     = true;
   g_race_mode       = DIR_UP;
   g_race_hwbb_idx   = hwbb_idx;
   g_race_hwbb_time  = (hwbb_idx>=0 && hwbb_idx<n? rates[hwbb_idx].time : TimeCurrent());
   g_race_winner     = ""; g_race_winner_time=0;
   Race_ResetPathB(g_pb_up);
   g_pb_up.init=true; g_pb_up.state=R_SEARCH_W2; g_pb_up.idx = MathMax(0, hwbb_idx);
      // NEW: start C1 candidate from the HWBB bar (Mode=UP ⇒ scanning DOWN)
   g_pb_up.mtc_c1_cand = hwbb_idx;
   g_pb_up.mtc_c1_level = (hwbb_idx>=0 && hwbb_idx<n ? rates[hwbb_idx].low : 0.0);

   Race_MarkStart(DIR_UP, g_race_hwbb_time);
}

inline void Race_Start_DOWN(const MqlRates &rates[], const int n, const int hwbb_idx)
{
   if(g_race_locked) return;
   g_race_locked     = true;
   g_race_mode       = DIR_DOWN;
   g_race_hwbb_idx   = hwbb_idx;
   g_race_hwbb_time  = (hwbb_idx>=0 && hwbb_idx<n? rates[hwbb_idx].time : TimeCurrent());
   g_race_winner     = ""; g_race_winner_time=0;
   Race_ResetPathB(g_pb_down);
   g_pb_down.init=true; g_pb_down.state=R_SEARCH_W2; g_pb_down.idx = MathMax(0, hwbb_idx);
      // NEW: start C1 candidate from the HWBB bar (Mode=DOWN ⇒ scanning UP)
   g_pb_down.mtc_c1_cand = hwbb_idx;
   g_pb_down.mtc_c1_level = (hwbb_idx>=0 && hwbb_idx<n ? rates[hwbb_idx].high : 0.0);
   Race_MarkStart(DIR_DOWN, g_race_hwbb_time);
}

//--------------------------- اعلام مسیر A (SW هم‌جهت) -------------------------
inline void Race_OnSWConfirmed_UP(const MqlRates &rates[], const int n, const int w3_c1, const int bodyBreakIdx)
{
   if(!g_race_locked || g_race_mode!=DIR_UP) return;
   if(bodyBreakIdx<0 || bodyBreakIdx>=n) return;
   const datetime t = rates[bodyBreakIdx].time;
   if(t < g_race_hwbb_time) return; // حتما بعد از HWBB

   // اگر هنوز برنده‌ای تعیین نشده یا این زودتر است:
   if(g_race_winner=="" || t < g_race_winner_time)
   {
      g_race_winner="A"; g_race_winner_time=t;
      Race_MarkWin_A(DIR_UP, t);
      Race_InternalClearAll();
   }
}

inline void Race_OnSWConfirmed_DOWN(const MqlRates &rates[], const int n, const int w3_c1, const int bodyBreakIdx)
{
   if(!g_race_locked || g_race_mode!=DIR_DOWN) return;
   if(bodyBreakIdx<0 || bodyBreakIdx>=n) return;
   const datetime t = rates[bodyBreakIdx].time;
   if(t < g_race_hwbb_time) return;

   if(g_race_winner=="" || t < g_race_winner_time)
   {
      g_race_winner="A"; g_race_winner_time=t;
      Race_MarkWin_A(DIR_DOWN, t);
      Race_InternalClearAll();
   }
}

//--------------------------- مسیر B برای Mode=UP (اسکن DOWN) ------------------
// از خود HWBB: W2(DOWN) -> W3(DOWN)+body-break. هرکدام زودتر از SW هم‌جهت رخ دهد، برنده است.
inline void Race_OnBar_UP(const MqlRates &rates[], const bool &insideHL[], const double &bodyLowEff[], const double &bodyHighEff[], const int n, const int upto_j)
{
   if(!g_race_locked || g_race_mode!=DIR_UP) return;
   RacePathBState S = g_pb_up;
   if(!S.init) return;

   // از نقطهٔ HWBB به بعد
   int limit = MathMin(upto_j, n-1);
   while(S.idx <= limit)
   {
      if(S.state==R_SEARCH_W2)
      {
         bool found=false;
         // --- NEW: candidate update (any wick/body break DOWN invalidates prior candidate)
         if(S.mtc_c1_cand >= 0) // initialized from HWBB
         {
            if( (rates[upto_j].low < S.mtc_c1_level) || (rates[upto_j].close < S.mtc_c1_level) )
            {
               S.mtc_c1_cand = upto_j;
               S.mtc_c1_level = rates[upto_j].low;
               S.idx = S.mtc_c1_cand;  // move search pointer to the new candidate
            }
         }
         for(int i=S.idx; i<=limit; ++i)
         {
            // --- NEW: allow scanning only at the current candidate index
            if(S.mtc_c1_cand >= 0 && i != S.mtc_c1_cand) { continue; }

            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            // تضمین شروع از خود HWBB (همان کُد فعلی)
            if(i < g_race_hwbb_idx){ S.idx = (i4>=0?i4:i3)+1; continue; }

            S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

            // ریست W3 و مدیریت‌های فعلی (بدون تغییر)
            S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
            S.w3_cand=-1;   S.w3_cand_high=-DBL_MAX;

            S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
            S.bodyBreakLevel = rates[S.c1].low;
            S.breakAchieved  = false;
            S.bodyBreakIdx   = -1;

            // از این‌جا به بعد وارد WAIT_CONFIRM می‌شویم
            S.idx=S.cend; S.state=R_WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // R_WAIT_CONFIRM (DOWN)
      {
         bool progressed=false;
         for(int j=S.idx; j<=limit; ++j)
         {
            if(insideHL[j]) continue;

            // wick escalation (DOWN): ابتدا شدو، سپس اگر بدنه زیر سطح بسته شد => breakAchieved
            if(!S.breakAchieved)
            {
               if(rates[j].low < S.bodyBreakLevel)
               {
                  if(rates[j].close < S.bodyBreakLevel)
                  { S.breakAchieved = true; S.bodyBreakIdx = j; }
                  else
                  {
                     S.bodyBreakLevel = rates[j].low;
                     if(S.firstWickIdx < 0)
                     {
                        S.firstWickIdx = j; S.wickBreakIdx = j; S.wickActive = true;

                        // قفل C1 در مسیر ویکی: بیشترین High در [cend..firstWickIdx] بدون inside
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, S.cend, S.firstWickIdx);
                        S.have_w3=false; S.w3_c1 = anchorC1;

                        S.w3_cand=-1; S.w3_cand_high=-DBL_MAX;
                     }
                  }
               }
            }

            // --- NEW: Chain-Invalidation (DOWN) in wick-window (pre body-break)
            {
               int __rew = -1;
               if(ChainInv_PreBody_WickWindow_DN_OnBar(
                     rates, insideHL, n, j,
                     S.breakAchieved, S.wickActive, S.firstWickIdx,
                     S.w3_c1, S.w3_cand, __rew))
               {
                  S.idx = __rew; S.state = R_SEARCH_W2; progressed = true; break;
               }
            }
            
            // NEW (pre body-break, non-wick): H > H(C1_W3) => RESET W3 از همان کندل
            if(!S.wickActive && !S.breakAchieved)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1 = -1;
                  S.w3_cand      = j;
                  S.w3_cand_high = rates[j].high;
                  continue;
               }
            }

            // مسیر مستقیم: بزرگ‌ترین High از cend به بعد
            if(!S.wickActive)
            {
               if(j >= S.cend && (S.w3_cand < 0 || rates[j].high > S.w3_cand_high))
               {
                  S.w3_cand      = j;
                  S.w3_cand_high = rates[j].high;
                  S.have_w3      = false;
               }
            }

            // انتخاب استارت شمارش W3(DOWN)
            int startIdx = -1;
            if(S.w3_c1  >= 0)       startIdx = S.w3_c1;     // مسیر ویکی
            else if(S.w3_cand >= 0) startIdx = S.w3_cand;   // مسیر مستقیم

            // شمارش W3 (DOWN)
            if(!S.have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates, insideHL, bodyLowEff, bodyHighEff, n,
                                                 startIdx, a2, a3, a4, w3e))
               {
                  S.have_w3=true;
                  if(S.w3_c1 < 0) S.w3_c1 = startIdx;
                  S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e;
               }
            }

            // نهایی‌سازی: هر دو شرط لازم (شمارش W3 + بریک با بدنه)
            if(S.have_w3 && S.breakAchieved)
            {
               const datetime bt = rates[(S.bodyBreakIdx>=0?S.bodyBreakIdx:j)].time;
               // اگر SW هم‌جهت هم در همین کندل رخ دهد، تقدم با هر کدام که زودتر ثبت شده باشد؛
               // پیش‌فرض: اگر هم‌زمان باشد و هنوز برنده‌ای ثبت نشده باشد، مسیر B پذیرفته می‌شود.
               if(g_race_winner=="" || bt < g_race_winner_time)
               {                  
                  g_race_winner="B"; g_race_winner_time=bt;
                  Race_MarkWin_B(DIR_UP, bt);
                  // >>> NEW: run DOWN-side API to display the exact W2/W3 pair that caused MTC_D
                  const int __c1 = (S.c1>=0 ? S.c1 : g_race_hwbb_idx);
                  datetime __from = rates[__c1].time - (PeriodSeconds(InpTF)*5);
                  datetime __to   = TimeCurrent();
                  if (g_race_mode == DIR_UP) API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, __from, __to);
                  //API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, __from, __to);
                  Race_DrawW2W3_MTC_Down(rates, n, S);
                  Race_InternalClearAll();
               }
               progressed=true; break;
            }
         }
         if(!progressed) break;
      }
   }
   g_pb_up = S;   // حفظ وضعیت به‌روز شده
}

//--------------------------- مسیر B برای Mode=DOWN (اسکن UP) -------------------
inline void Race_OnBar_DOWN(const MqlRates &rates[], const bool &insideHL[], const double &bodyLowEff[], const double &bodyHighEff[], const int n, const int upto_j)
{
   if(!g_race_locked || g_race_mode!=DIR_DOWN) return;
   RacePathBState S = g_pb_down;
   if(!S.init) return;

   int limit = MathMin(upto_j, n-1);
   while(S.idx <= limit)
   {
      if(S.state==R_SEARCH_W2)
      {
         bool found=false;
         // --- NEW: candidate update (any wick/body break UP invalidates prior candidate)
         if(S.mtc_c1_cand >= 0)
         {
            if( (rates[upto_j].high > S.mtc_c1_level) || (rates[upto_j].close > S.mtc_c1_level) )
            {
               S.mtc_c1_cand = upto_j;
               S.mtc_c1_level = rates[upto_j].high;
               S.idx = S.mtc_c1_cand;
            }
         }
         for(int i=S.idx; i<=limit; ++i)
         {
            // --- NEW: allow scanning only at the current candidate index
            if(S.mtc_c1_cand >= 0 && i != S.mtc_c1_cand) { continue; }

            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            if(i < g_race_hwbb_idx){ S.idx=(i4>=0?i4:i3)+1; continue; }

            S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

            // ریستِ W3/wick و… (همان کُد فعلی)
            S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
            S.w3_cand=-1;   S.w3_cand_low=DBL_MAX;

            S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
            S.bodyBreakLevel = rates[S.c1].high;
            S.breakAchieved  = false;
            S.bodyBreakIdx   = -1;

            S.idx=S.cend; S.state=R_WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // R_WAIT_CONFIRM (UP)
      {
         bool progressed=false;
         for(int j=S.idx; j<=limit; ++j)
         {
            if(insideHL[j]) continue;

            // ارتقای سطح بریک با شدو (UP)
            if(!S.breakAchieved)
            {
               if(rates[j].high > S.bodyBreakLevel)
               {
                  if(rates[j].close > S.bodyBreakLevel)
                  { S.breakAchieved = true; S.bodyBreakIdx = j; }
                  else
                  {
                     S.bodyBreakLevel = rates[j].high; // wick escalation
                     if(S.firstWickIdx < 0)
                     {
                        S.firstWickIdx = j; S.wickBreakIdx = j; S.wickActive = true;

                        int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, S.cend, S.firstWickIdx);
                        S.have_w3=false; S.w3_c1 = anchorC1;

                        S.w3_cand=-1; S.w3_cand_low=DBL_MAX;
                     }
                  }
               }
            }

            // --- NEW: Chain-Invalidation (UP) in wick-window (pre body-break)
            {
               int __rew = -1;
               if(ChainInv_PreBody_WickWindow_UP_OnBar(
                     rates, insideHL, n, j,
                     S.breakAchieved, S.wickActive, S.firstWickIdx,
                     S.w3_c1, S.w3_cand, __rew))
               {
                  S.idx = __rew; S.state = R_SEARCH_W2; progressed = true; break;
               }
            }

            // NEW (pre body-break, non-wick): L < L(C1_W3) => RESET W3 از همان کندل
            if(!S.wickActive && !S.breakAchieved)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1 = -1;
                  S.w3_cand     = j;
                  S.w3_cand_low = rates[j].low;
                  continue;
               }
            }

            // مسیر مستقیم: کم‌ترین Low از cend به بعد
            if(!S.wickActive)
            {
               if(j >= S.cend && (S.w3_cand < 0 || rates[j].low < S.w3_cand_low))
               {
                  S.w3_cand     = j;
                  S.w3_cand_low = rates[j].low;
                  S.have_w3     = false;
               }
            }

            // انتخاب startIdx برای شمارش W3 (UP)
            int startIdx = -1;
            if(S.w3_c1  >= 0)       startIdx = S.w3_c1;     // مسیر ویکی
            else if(S.w3_cand >= 0) startIdx = S.w3_cand;   // مسیر مستقیم

            if(!S.have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, w3e))
               {
                  S.have_w3=true;
                  if(S.w3_c1 < 0) S.w3_c1 = startIdx;
                  S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e;
               }
            }

            if(S.breakAchieved && !S.have_w3)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  S.idx = (S.bodyBreakIdx>=0 ? S.bodyBreakIdx : j);
                  S.state = R_SEARCH_W2; progressed = true; break;
               }
            }

            if(S.have_w3 && S.breakAchieved)
            {
               const datetime bt = rates[(S.bodyBreakIdx>=0?S.bodyBreakIdx:j)].time;
               if(g_race_winner=="" || bt < g_race_winner_time)
               {
                  g_race_winner="B"; g_race_winner_time=bt;
                  Race_MarkWin_B(DIR_DOWN, bt);
                  // >>> NEW: run UP-side API to display the exact W2/W3 pair that caused MTC_U
                  const int __c1 = (S.c1>=0 ? S.c1 : g_race_hwbb_idx);
                  datetime __from = rates[__c1].time - (PeriodSeconds(InpTF)*5);
                  datetime __to   = TimeCurrent();
                  if (g_race_mode == DIR_DOWN) API_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, __from, __to);
                  //API_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, __from, __to);
                  Race_DrawW2W3_MTC_Up(rates, n, S);
                  Race_InternalClearAll();
               }
               progressed=true; break;
            }
         }
         if(!progressed) break;
      }
   }
   g_pb_down = S;
}

// =====================[ MTC Drawing Helpers ]=====================
inline void Race_DrawW2W3_MTC_Down(const MqlRates &rates[], const int n, const RacePathBState &S)
{
   const string tag = IntegerToString(g_race_counter);

   // --- W2 (DOWN): C1..C4/Cend
   if(S.c1 >= 0 && S.c1 < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_C1_"+tag, rates[S.c1].time, clrFireBrick);
   if(S.c2 >= 0 && S.c2 < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_C2_"+tag, rates[S.c2].time, clrFireBrick);
   if(S.c3 >= 0 && S.c3 < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_C3_"+tag, rates[S.c3].time, clrFireBrick);
   int cend = (S.c4>=0 ? S.c4 : S.c3);
   if(cend >= 0 && cend < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_CEND_"+tag, rates[cend].time, clrFireBrick);

   // --- W3 (DOWN): C1..K2/K3/K4..END
   if(S.w3_c1 >= 0 && S.w3_c1 < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_C1_"+tag, rates[S.w3_c1].time, clrOrangeRed);
   if(S.k2    >= 0 && S.k2    < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_K2_"+tag, rates[S.k2].time,    clrOrangeRed);
   if(S.k3    >= 0 && S.k3    < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_K3_"+tag, rates[S.k3].time,    clrOrangeRed);
   if(S.k4    >= 0 && S.k4    < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_K4_"+tag, rates[S.k4].time,    clrOrangeRed);
   if(S.w3_end>= 0 && S.w3_end< n) if(InpDrawMarkers) MarkV("MTC_DN_W3_END_"+tag,rates[S.w3_end].time,clrOrangeRed);

   // --- Body-Break (DOWN): کندل بریک + خط افقی سطح بریک (بعد از wick-escalation)
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n && InpDrawMarkers)
      MarkV("MTC_DN_BB_"+tag, rates[S.bodyBreakIdx].time, clrRed);

   if(S.bodyBreakLevel > 0.0) // خط افقی سطح بریک
   {
      const string hname = "MTC_DN_BB_LEVEL_"+tag;
      if(ObjectFind(0, hname) == -1)
         ObjectCreate(0, hname, OBJ_HLINE, 0, 0, S.bodyBreakLevel);
      ObjectSetInteger(0, hname, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, hname, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, hname, OBJPROP_STYLE, STYLE_DOT);
   }
   // --- Reference (DOWN): Highِ C1ِ Hunter(UP) که HWBBِ منجر به این MTC را ساخته بود
   if(g_race_ref_mtc_down > 0.0)
   {
      const string rname = "MTC_DN_REF_"+tag;
      if(ObjectFind(0, rname) == -1)
         ObjectCreate(0, rname, OBJ_HLINE, 0, 0, g_race_ref_mtc_down);
      ObjectSetInteger(0, rname, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, rname, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, rname, OBJPROP_STYLE, STYLE_SOLID);
   }
}

inline void Race_DrawW2W3_MTC_Up(const MqlRates &rates[], const int n, const RacePathBState &S)
{
   const string tag = IntegerToString(g_race_counter);

   // --- W2 (UP): C1..C4/Cend
   if(S.c1 >= 0 && S.c1 < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_C1_"+tag, rates[S.c1].time, clrLime);
   if(S.c2 >= 0 && S.c2 < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_C2_"+tag, rates[S.c2].time, clrLime);
   if(S.c3 >= 0 && S.c3 < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_C3_"+tag, rates[S.c3].time, clrLime);
   int cend = (S.c4>=0 ? S.c4 : S.c3);
   if(cend >= 0 && cend < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_CEND_"+tag, rates[cend].time, clrLime);

   // --- W3 (UP): C1..K2/K3/K4..END
   if(S.w3_c1 >= 0 && S.w3_c1 < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_C1_"+tag, rates[S.w3_c1].time, clrDeepSkyBlue);
   if(S.k2    >= 0 && S.k2    < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_K2_"+tag, rates[S.k2].time,    clrDeepSkyBlue);
   if(S.k3    >= 0 && S.k3    < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_K3_"+tag, rates[S.k3].time,    clrDeepSkyBlue);
   if(S.k4    >= 0 && S.k4    < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_K4_"+tag, rates[S.k4].time,    clrDeepSkyBlue);
   if(S.w3_end>= 0 && S.w3_end< n) if(InpDrawMarkers) MarkV("MTC_UP_W3_END_"+tag,rates[S.w3_end].time,clrDeepSkyBlue);

   // --- Body-Break (UP)
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n && InpDrawMarkers)
      MarkV("MTC_UP_BB_"+tag, rates[S.bodyBreakIdx].time, clrBlue);

   if(S.bodyBreakLevel > 0.0)
   {
      const string hname = "MTC_UP_BB_LEVEL_"+tag;
      if(ObjectFind(0, hname) == -1)
         ObjectCreate(0, hname, OBJ_HLINE, 0, 0, S.bodyBreakLevel);
      ObjectSetInteger(0, hname, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, hname, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, hname, OBJPROP_STYLE, STYLE_DOT);
   }
   // --- Reference (UP): Lowِ C1ِ Hunter(DOWN) که HWBBِ منجر به این MTC را ساخته بود
   if(g_race_ref_mtc_up > 0.0)
   {
      const string rname = "MTC_UP_REF_"+tag;
      if(ObjectFind(0, rname) == -1)
         ObjectCreate(0, rname, OBJ_HLINE, 0, 0, g_race_ref_mtc_up);
      ObjectSetInteger(0, rname, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, rname, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, rname, OBJPROP_STYLE, STYLE_SOLID);
   }
}

#endif // WAVEBOT_RACECOORDINATOR_MQH
