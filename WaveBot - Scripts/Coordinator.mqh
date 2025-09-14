#ifndef WAVEBOT_COORDINATOR_MQH
#define WAVEBOT_COORDINATOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Bootstrap.mqh>
#include <WaveBot/Switch.mqh>
#include <WaveBot/Hunter.mqh>
#include <WaveBot/Hunter_Down.mqh>
#include <WaveBot/API.mqh>
#include <WaveBot/API_Down.mqh>

// -----------------------------------------------------------------------------
// اعلان‌هایی که در فایل‌های دیگر باید پیاده‌سازی شده باشند
// -----------------------------------------------------------------------------

// از Bootstrap: بازگرداندن اولین جفت W2→W3 تکمیل‌شده با جزئیات
bool Boot_FindFirstPair_UP_Details(const string sym, const ENUM_TIMEFRAMES tf,
                                   const datetime from_time, const datetime to_time,
                                   int &out_w3_c1_idx, datetime &out_w3_c1_time,
                                   int &out_bodyBreakIdx, datetime &out_bodyBreakTime, double &out_bodyBreakClose);

bool Boot_FindFirstPair_DOWN_Details(const string sym, const ENUM_TIMEFRAMES tf,
                                     const datetime from_time, const datetime to_time,
                                     int &out_w3_c1_idx, datetime &out_w3_c1_time,
                                     int &out_bodyBreakIdx, datetime &out_bodyBreakTime, double &out_bodyBreakClose);

// از Hunter: پاک‌سازی آرم ترنزیشن و بذر SW
void Hunter_ClearTransitionArm_UP();
void Hunter_ClearTransitionArm_DOWN();
void SW_UP_ClearSeed();
void SW_DOWN_ClearSeed();

// -----------------------------------------------------------------------------
// یافتن نخستین SW هم‌جهت بعد از شروع ترنزیشن
// -----------------------------------------------------------------------------

// UP: اولین جفت W2→W3 صعودی که کندل بریکِ بدنه‌اش، SeedLevel را با بدنه بشکند
inline bool FindFirstSW_UP_After(const string sym, const ENUM_TIMEFRAMES tf,
                                 const datetime start_t, const datetime seed_time, const double seed_lvl,
                                 datetime &out_sw_time)
{
   datetime cursor = start_t;
   while(true)
   {
      int w3c1=-1, bb=-1;
      datetime w3c1t=0, bbt=0;
      double bbClose=0.0;

      if(!Boot_FindFirstPair_UP_Details(sym, tf, cursor, TimeCurrent(),
                                        w3c1, w3c1t, bb, bbt, bbClose))
         return false; // چیزی پیدا نشد

      // باید C1_W3 بعد از فعال‌شدن Seed باشد و بریک با بدنه از SeedLevel بالاتر باشد
      if(w3c1t >= seed_time && bbClose > seed_lvl)
      {
         out_sw_time = bbt;
         return true;
      }

      // ادامهٔ جست‌وجو از بعدِ همین بریک
      cursor = bbt + PeriodSeconds(tf);
   }
}

// DOWN: اولین جفت W2→W3 نزولی که کندل بریکِ بدنه‌اش، SeedLevel را با بدنه به پایین بشکند
inline bool FindFirstSW_DOWN_After(const string sym, const ENUM_TIMEFRAMES tf,
                                   const datetime start_t, const datetime seed_time, const double seed_lvl,
                                   datetime &out_sw_time)
{
   datetime cursor = start_t;
   while(true)
   {
      int w3c1=-1, bb=-1;
      datetime w3c1t=0, bbt=0;
      double bbClose=0.0;

      if(!Boot_FindFirstPair_DOWN_Details(sym, tf, cursor, TimeCurrent(),
                                          w3c1, w3c1t, bb, bbt, bbClose))
         return false;

      if(w3c1t >= seed_time && bbClose < seed_lvl)
      {
         out_sw_time = bbt;
         return true;
      }

      cursor = bbt + PeriodSeconds(tf);
   }
}

// -----------------------------------------------------------------------------
// حل ترنزیشن: تعیین برندهٔ مسابقه و ادامه با API مناسب
// -----------------------------------------------------------------------------

inline void Switch_Resolve_And_Continue(const string sym, const ENUM_TIMEFRAMES tf,
                                        Direction &io_mode, datetime &io_cursor, const datetime stop)
{
   if(!Switch_IsActive()) return;

   const int tfsec = PeriodSeconds(tf);

   if(Switch_FromUP())
   {
      // رقابت: SW_UP earliest vs. اولین جفت DOWN (سوییچ)
      datetime sw_t=0, pair_t=0, pair_c1_t=0;
      bool have_sw=false, have_pair=false;

      if(SW_UP_SeedActive())
         have_sw = FindFirstSW_UP_After(sym, tf, Switch_StartTime(),
                                        SW_UP_SeedTime(), SW_UP_Level(), sw_t);

      {
         int w3c1=-1, bb=-1; datetime w3c1t=0, bbt=0; double bbClose=0.0;
         if(Boot_FindFirstPair_DOWN_Details(sym, tf, Switch_StartTime(), stop,
                                            w3c1, w3c1t, bb, bbt, bbClose))
         {
            have_pair = true;
            pair_t    = bbt;      // کندل بریکِ بدنه
            pair_c1_t = w3c1t;    // زمان C1_W3 نزولی
         }
      }

      if(have_sw && (!have_pair || sw_t <= pair_t))
      {
         // A) SW هم‌جهت ⇒ ادامه با UP
         io_mode   = DIR_UP;
         io_cursor = (sw_t - tfsec); if(io_cursor < 0) io_cursor = 0;

         // پاک‌سازی برای مسابقه‌های بعدی
         Hunter_ClearTransitionArm_UP();
         // در صورت نیاز: SW_UP_ClearSeed();  // معمولاً با ثبت SW پاک می‌شود
      }
      else if(have_pair)
      {
         // B) جفت خلاف‌جهت ⇒ سوییچ به DOWN
         Mark_MTC_Down(pair_t);

         // کمی عقب‌تر از C1_W3 شروع می‌کنیم تا W2/W3 روی چارت رندر شوند
         datetime back = pair_c1_t - (2*tfsec);
         if(back < 0) back = 0;

         io_mode   = DIR_DOWN;
         io_cursor = back;

         Hunter_ClearTransitionArm_UP();
         SW_UP_ClearSeed();
      }

      Switch_Clear();
   }
   else if(Switch_FromDOWN())
   {
      datetime sw_t=0, pair_t=0, pair_c1_t=0;
      bool have_sw=false, have_pair=false;

      if(SW_DOWN_SeedActive())
         have_sw = FindFirstSW_DOWN_After(sym, tf, Switch_StartTime(),
                                          SW_DOWN_SeedTime(), SW_DOWN_Level(), sw_t);

      {
         int w3c1=-1, bb=-1; datetime w3c1t=0, bbt=0; double bbClose=0.0;
         if(Boot_FindFirstPair_UP_Details(sym, tf, Switch_StartTime(), stop,
                                          w3c1, w3c1t, bb, bbt, bbClose))
         {
            have_pair = true;
            pair_t    = bbt;
            pair_c1_t = w3c1t;
         }
      }

      if(have_sw && (!have_pair || sw_t <= pair_t))
      {
         io_mode   = DIR_DOWN;
         io_cursor = (sw_t - tfsec); if(io_cursor < 0) io_cursor = 0;

         Hunter_ClearTransitionArm_DOWN();
         // SW_DOWN_ClearSeed(); // در صورت نیاز
      }
      else if(have_pair)
      {
         Mark_MTC_Up(pair_t);

         datetime back = pair_c1_t - (2*tfsec);
         if(back < 0) back = 0;

         io_mode   = DIR_UP;
         io_cursor = back;

         Hunter_ClearTransitionArm_DOWN();
         SW_DOWN_ClearSeed();
      }

      Switch_Clear();
   }
}

// -----------------------------------------------------------------------------
// حلقهٔ راننده
// -----------------------------------------------------------------------------

inline void Coordinator_RunAutoSwitch(const string sym, const ENUM_TIMEFRAMES tf,
                                      const Direction initialMode,
                                      datetime start_t, const datetime stop_t)
{
   Direction mode = initialMode;
   datetime  cursor = start_t;

   while(cursor < stop_t)
   {
      if(mode == DIR_UP)
      {
         API_RunScanSequential_W2W3_Hunter(sym, tf, cursor, stop_t);
         if(!Switch_IsActive()) break;
         Switch_Resolve_And_Continue(sym, tf, mode, cursor, stop_t);
      }
      else
      {
         API_Down_RunScanSequential_W2W3_Hunter(sym, tf, cursor, stop_t);
         if(!Switch_IsActive()) break;
         Switch_Resolve_And_Continue(sym, tf, mode, cursor, stop_t);
      }
   }
}

#endif // WAVEBOT_COORDINATOR_MQH
