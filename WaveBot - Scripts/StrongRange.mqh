// WaveBot/StrongRange.mqh
#ifndef WAVEBOT_STRONGRANGE_MQH
#define WAVEBOT_STRONGRANGE_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/SWGate.mqh>
#include <WaveBot/Hunter.mqh>        // SW_UP_* و سطح High(C1-HW)
#include <WaveBot/Hunter_Down.mqh>   // SW_DOWN_* و سطح Low(C1-HW)
#include <WaveBot/FSMS_SW.mqh>       // FSMS_SW_* دسترسی به C1-W2 و SeedTime
#include <WaveBot/SR_Mitigator.mqh>  // NEW: مدیریت first SR mitigator

// شمارنده‌ها و جلوگیری از رسم تکراری در هر Seed
static int      g_sr_up_counter = 0;
static int      g_sr_dn_counter = 0;
static datetime g_sr_sw_up_drawn_seed   = 0;
static datetime g_sr_fsms_up_drawn_seed = 0;
static datetime g_sr_sw_dn_drawn_seed   = 0;
static datetime g_sr_fsms_dn_drawn_seed = 0;

// رسم مستطیل SR
inline void __SR_DrawRect(const string base, const datetime t1, const double p_top,
                          const datetime t2, const double p_bottom)
{
   if(!InpDrawMarkers) return;

   datetime a=t1, b=t2;
   if(b<a){ datetime tmp=a; a=b; b=tmp; }

   const string full = __ScanPrefix() + base;
   if(ObjectFind(0, full) != -1) ObjectDelete(0, full);

   ObjectCreate(0, full, OBJ_RECTANGLE, 0, a, p_top, b, p_bottom);
   ObjectSetInteger(0, full, OBJPROP_COLOR, clrPowderBlue);
   ObjectSetInteger(0, full, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, full, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, full, OBJPROP_BACK,  true);
   ObjectSetInteger(0, full, OBJPROP_FILL,  false);
}

// --- سناریوی صعودی: هنگام شکل‌گیری SW یا FSMS-SW ---
inline void SR_OnBar_UP(const MqlRates &rates[], const int n, const int j, const int w3_start_idx)
{
   if(j<0 || j>=n) return;
   if(w3_start_idx < 0 || w3_start_idx >= n) return;

   // 1) ابتدا اگر FSMS–SW فعال است (اولویت بالاتر)
   if(FSMS_SW_UP_SeedActive())
   {
      const datetime seed_t = FSMS_SW_UP_SeedTime();
      if(rates[j].time >= seed_t && g_sr_fsms_up_drawn_seed != seed_t)
      {
         const double level_top = FSMS_SW_UP_Level();       // High(C1-W2 هم‌جهت FSMS)
         if(rates[j].high > level_top)                      // شکست با شدو یا بدنه
         {
            const int    c1_top_idx = FSMS_SW_UP_C1Index();   // اندیس همان C1-W2
            const int    t_idx      = (c1_top_idx>=0 && c1_top_idx<n ? c1_top_idx : w3_start_idx);
            const double p_top      = level_top;
            const double p_bottom   = rates[w3_start_idx].low; // Low(C1-FSMS-SW)
            ++g_sr_up_counter;

            __SR_DrawRect("SR_U_"+IntegerToString(g_sr_up_counter),
                          rates[t_idx].time, p_top,
                          rates[j].time,    p_bottom);
            g_sr_fsms_up_drawn_seed = seed_t;

            // NEW: ثبت وضعیت SR برای first SR mitigator + ناحیه unmitigated SR
            const bool created_by_body = (rates[j].close > level_top);
            SRMIT_OnNewSR_UP(g_sr_up_counter,
                             p_top,
                             p_bottom,
                             rates[j].time,            // زمان کندل سازنده SR
                             created_by_body,
                             rates[w3_start_idx].time  // زمان C1-FSMS-SW = لبه چپ ناحیه SR و unmit
                             );
         }
      }
      return; // اگر FSMS‑SW فعال است، دیگر به حالت SW معمولی نمی‌رویم
   }

   // 2) SW معمولی (Hunter) — فقط وقتی Seed پس از قفل W2 است
   if(SWGate_UP_IsOpen() && SW_UP_SeedActive() && SW_UP_SeedTime() >= SWGate_UP_W2Time())
   {
      const datetime seed_t = SW_UP_SeedTime();
      if(rates[j].time >= seed_t && g_sr_sw_up_drawn_seed != seed_t)
      {
         const double level_top = SW_UP_Level();            // High(C1-HW)
         if(rates[j].high > level_top)
         {
            const int    c1_top_idx = SW_UP_C1Index();
            const int    t_idx      = (c1_top_idx>=0 && c1_top_idx<n ? c1_top_idx : w3_start_idx);
            const double p_top      = level_top;              // High(C1-HW)
            const double p_bottom   = rates[w3_start_idx].low;// Low(C1-SW)
            ++g_sr_up_counter;

            __SR_DrawRect("SR_U_"+IntegerToString(g_sr_up_counter),
                          rates[t_idx].time, p_top,
                          rates[j].time,    p_bottom);
            g_sr_sw_up_drawn_seed = seed_t;

            // NEW: ثبت وضعیت SR برای first SR mitigator + ناحیه unmitigated SR
            const bool created_by_body = (rates[j].close > level_top);
            SRMIT_OnNewSR_UP(g_sr_up_counter,
                             p_top,
                             p_bottom,
                             rates[j].time,            // زمان کندل سازنده SR
                             created_by_body,
                             rates[w3_start_idx].time  // زمان C1-SW = لبه چپ ناحیه SR و unmit
                             );
         }
      }
   }
}

// --- سناریوی نزولی (آینه‌ای): هنگام شکل‌گیری SW یا FSMS-SW ---
inline void SR_OnBar_DOWN(const MqlRates &rates[], const int n, const int j, const int w3_start_idx)
{
   if(j<0 || j>=n) return;
   if(w3_start_idx < 0 || w3_start_idx >= n) return;

   // 1) اولویت: FSMS–SW نزولی
   if(FSMS_SW_DN_SeedActive())
   {
      const datetime seed_t = FSMS_SW_DN_SeedTime();
      if(rates[j].time >= seed_t && g_sr_fsms_dn_drawn_seed != seed_t)
      {
         const double level_bottom = FSMS_SW_DN_Level();    // Low(C1-W2 هم‌جهت FSMS)
         if(rates[j].low < level_bottom)                    // شکست با شدو یا بدنه
         {
            const int    c1_bot_idx = FSMS_SW_DN_C1Index();
            const int    t_idx      = (c1_bot_idx>=0 && c1_bot_idx<n ? c1_bot_idx : w3_start_idx);
            const double p_top      = rates[w3_start_idx].high; // High(C1-FSMS-SW)
            const double p_bottom   = level_bottom;             // Low(C1-W2 یا C1-HW)
            ++g_sr_dn_counter;

            __SR_DrawRect("SR_D_"+IntegerToString(g_sr_dn_counter),
                          rates[t_idx].time, p_top,
                          rates[j].time,    p_bottom);
            g_sr_fsms_dn_drawn_seed = seed_t;

            // NEW: ثبت وضعیت SR برای first SR mitigator + ناحیه unmitigated SR
            const bool created_by_body = (rates[j].close < level_bottom);
            SRMIT_OnNewSR_DN(g_sr_dn_counter,
                             p_top,
                             p_bottom,
                             rates[j].time,            // زمان کندل سازنده SR
                             created_by_body,
                             rates[w3_start_idx].time  // زمان C1-FSMS-SW = لبه چپ ناحیه SR و unmit (DOWN)
                             );
         }
      }
      return;
   }

   // 2) SW معمولی نزولی
   if(SW_DOWN_SeedActive())
   {
      const datetime seed_t = SW_DOWN_SeedTime();
      if(rates[j].time >= seed_t && g_sr_sw_dn_drawn_seed != seed_t)
      {
         const double level_bottom = SW_DOWN_Level();       // Low(C1-HW)
         if(rates[j].low < level_bottom)
         {
            const int    c1_bot_idx = SW_DOWN_C1Index();
            const int    t_idx      = (c1_bot_idx>=0 && c1_bot_idx<n ? c1_bot_idx : w3_start_idx);
            const double p_top      = rates[w3_start_idx].high; // High(C1-SW)
            const double p_bottom   = level_bottom;             // Low(C1-HW)
            ++g_sr_dn_counter;

            __SR_DrawRect("SR_D_"+IntegerToString(g_sr_dn_counter),
                          rates[t_idx].time, p_top,
                          rates[j].time,    p_bottom);
            g_sr_sw_dn_drawn_seed = seed_t;

            // NEW: ثبت وضعیت SR برای first SR mitigator + ناحیه unmitigated SR
            const bool created_by_body = (rates[j].close < level_bottom);
            SRMIT_OnNewSR_DN(g_sr_dn_counter,
                             p_top,
                             p_bottom,
                             rates[j].time,            // زمان کندل سازنده SR
                             created_by_body,
                             rates[w3_start_idx].time  // زمان C1-SW = لبه چپ ناحیه SR و unmit (DOWN)
                             );
         }
      }
   }
}

#endif // WAVEBOT_STRONGRANGE_MQH
