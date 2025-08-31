#ifndef WAVEBOT_API_MQH
#define WAVEBOT_API_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>

#include <WaveBot/Wave2.mqh>        // W2 ↑
#include <WaveBot/Wave3.mqh>        // W3 ↑ (CountOnly + ConfirmWithBreak)
#include <WaveBot/Wave2Down.mqh>    // W2 ↓
#include <WaveBot/Wave3Down.mqh>    // W3 ↓ (CountOnly + ConfirmWithBreak) + MaxHigh_ExInside ONLY here

#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/Hunter.mqh>
#include <WaveBot/HunterDown.mqh>

// ===================== Helper =====================
enum Mode  { MODE_UNKNOWN=0, MODE_BULL=1, MODE_BEAR=2 };
enum State {
   BULL_SEARCH_W2=10, BULL_WAIT_W3, BULL_MONITOR,
   BEAR_SEARCH_W2=20, BEAR_WAIT_W3, BEAR_MONITOR,
   SEEK_W2DOWN_AFTER_HUNTER=30, SEEK_W3DOWN_CONFIRM,
   SEEK_W2UP_AFTER_HUNTER=40,   SEEK_W3UP_CONFIRM
};

inline void MarkMTC(const string side, const datetime t, const color col)
{
   if(!InpDrawMarkers) return;
   string name = "MTC_"+side+"_"+IntegerToString((int)t);
   if(ObjectFind(0,name)!=-1) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
}

// کمترین Low چپ‌چین با اسکیپ inside (برای لنگر W3↑)
inline int IndexOfLeftmostMinLow_ExInside(const MqlRates &rates[],
                                          const bool &insideHL[],
                                          int from, int to)
{
   if(from>to) return -1;
   double mn=DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i){
      if(insideHL[i]) continue;
      double l=rates[i].low;
      if(l<mn){ mn=l; idx=i; }
   }
   if(idx<0) idx=from;
   return idx;
}

inline bool IsHunterBodyBreakDown(const MqlRates &r){ return (ExtLQ_Has() && r.close < ExtLQ_Get()); }
inline bool IsHunterBodyBreakUp  (const MqlRates &r){ return (ExtLQ_Has() && r.close > ExtLQ_Get()); }

// ===================== API Core =====================
int API_RunScanSequential_BullBear_MTC(const string sym, const ENUM_TIMEFRAMES tf,
                                       const datetime from_time, const datetime to_time)
{
   const int tfsec = PeriodSeconds(tf);
   const int HISTORY_SKIP_BARS = 3;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj        = from_time - tfsec*10;

   // --- load data
   MqlRates rates[]; int n=LoadRatesRange(sym,tf,from_adj,to_time,rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRatesRange failed"); return 0; }

   // --- bodies & inside-cluster
   double bodyLowEff[], bodyHighEff[];
   BuildEffectiveBodies(rates,n,bodyLowEff,bodyHighEff);

   bool insideHL[];
   BuildInsideClusterFlagsHL(rates,n,insideHL);

   // --- start index
   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) ++first_eff;
   int idx = MathMax(0, first_eff-2);

   Mode  mode  = MODE_UNKNOWN;
   State state = BULL_SEARCH_W2;

   // track
   int pairs=0;

   // bullish slots
   int c1U=-1,c2U=-1,c3U=-1,c4U=-1, cendU=-1;
   bool have_w3U=false, have_breakU=false;
   int  w3U_c1=-1,u2=-1,u3=-1,u4=-1, w3U_end=-1;
   int  firstWickU=-1, anchorU=-1; bool wickU=false; double bodyLevelU=0.0;

   // bearish slots
   int c1D=-1,c2D=-1,c3D=-1,c4D=-1, cendD=-1;
   bool have_w3D=false, have_breakD=false;
   int  w3D_c1=-1,d2=-1,d3=-1,d4=-1, w3D_end=-1, idxBreakD=-1;
   int  firstWickD=-1, anchorD=-1; bool wickD=false; double bodyLevelD=0.0;

   // hunter/extlq init
   Hunter_OnExtLQUpdated();
   HunterDown_OnExtLQUpdated();

   // ================== main loop ==================
   while(idx < n)
   {
      // ========== decide initial mode: try bull then bear ==========
      if(mode==MODE_UNKNOWN)
      {
         bool decided=false;

         // try BULL pair
         for(int i=idx;i<n && !decided;++i)
         {
            ExtLQ_OnBar(rates[i]);
            if(insideHL[i]) continue;

            int a2=-1,a3=-1,a4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,a2,a3,a4)) continue;

            const double H1_W2=rates[i].high;
            int w3c1=-1,b2=-1,b3=-1,b4=-1,w3e=-1, idxBreak=-1;
            if(ConfirmWave3Bullish_WithBreak(rates,insideHL,bodyLowEff,bodyHighEff,n,(a4>=0?a4:a3),H1_W2,
                                             w3c1,b2,b3,b4,w3e,idxBreak))
            {
               string tag=IntegerToString(++pairs);
               MarkV("W2U_"+tag+"_C1", rates[i].time, clrDeepSkyBlue);
               MarkV("W2U_"+tag+"_C2", rates[a2].time, clrYellow);
               MarkV("W2U_"+tag+"_C3", rates[a3].time, clrOrange);
               if(a4>=0) MarkV("W2U_"+tag+"_C4", rates[a4].time, clrTomato);

               MarkV("W3U_"+tag+"_C1", rates[w3c1].time,  clrLime);
               MarkV("W3U_"+tag+"_C2", rates[b2].time,     clrGreen);
               MarkV("W3U_"+tag+"_C3", rates[b3].time,     clrTeal);
               if(b4>=0) MarkV("W3U_"+tag+"_C4", rates[b4].time, clrSeaGreen);

               ExtLQ_Set(rates[w3c1].low, rates[w3c1].time);
               Hunter_OnExtLQUpdated();

               mode=MODE_BULL; state=BULL_MONITOR; idx=idxBreak; decided=true;
            }
         }
         if(decided) continue;

         // try BEAR pair
         for(int i=idx;i<n && !decided;++i)
         {
            ExtLQ_OnBar(rates[i]);
            if(insideHL[i]) continue;

            int a2=-1,a3=-1,a4=-1;
            if(!CheckWave2Down_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,a2,a3,a4)) continue;

            const double L1_W2=rates[i].low;
            int w3c1=-1,b2=-1,b3=-1,b4=-1,w3e=-1, idxBreak=-1;
            if(ConfirmWave3Down_WithBreak(rates,insideHL,bodyLowEff,bodyHighEff,n,(a4>=0?a4:a3),L1_W2,
                                          w3c1,b2,b3,b4,w3e,idxBreak))
            {
               string tag=IntegerToString(++pairs);
               MarkV("W2D_"+tag+"_C1", rates[i].time, clrDarkOrange);
               MarkV("W2D_"+tag+"_C2", rates[a2].time, clrKhaki);
               MarkV("W2D_"+tag+"_C3", rates[a3].time, clrBisque);
               if(a4>=0) MarkV("W2D_"+tag+"_C4", rates[a4].time, clrWheat);

               MarkV("W3D_"+tag+"_C1", rates[w3c1].time,  clrTomato);
               MarkV("W3D_"+tag+"_C2", rates[b2].time,     clrIndianRed);
               MarkV("W3D_"+tag+"_C3", rates[b3].time,     clrFireBrick);
               if(b4>=0) MarkV("W3D_"+tag+"_C4", rates[b4].time, clrMaroon);

               MarkMTC("BEAR", rates[idxBreak].time, clrRed);

               ExtLQ_Set(rates[w3c1].high, rates[w3c1].time);
               HunterDown_OnExtLQUpdated();

               mode=MODE_BEAR; state=BEAR_MONITOR; idx=idxBreak; decided=true;
            }
         }
         if(!decided) break;
         continue;
      }

      // ================== BULL mode ==================
      if(mode==MODE_BULL)
      {
         if(state==BULL_MONITOR)
         {
            bool progressed=false;
            for(int j=idx;j<n;++j)
            {
               ExtLQ_OnBar(rates[j]);

               // Hunter cross (نمایش)
               if(Hunter_IsExtLQCross(rates[j])) Hunter_MarkWithC1(rates,n,(c1U>=0?c1U:j),j);

               // Hunter body break ⇒ آماده ورود نزولی
               if(IsHunterBodyBreakDown(rates[j])){ state=SEEK_W2DOWN_AFTER_HUNTER; idx=j; progressed=true; break; }

               if(insideHL[j]) continue;
               state=BULL_SEARCH_W2; idx=j; progressed=true; break;
            }
            if(!progressed) break;
            continue;
         }
         else if(state==BULL_SEARCH_W2)
         {
            bool found=false;
            for(int i=idx;i<n;++i)
            {
               ExtLQ_OnBar(rates[i]);
               if(Hunter_IsExtLQCross(rates[i])) Hunter_MarkWithC1(rates,n,(c1U>=0?c1U:i),i);
               if(IsHunterBodyBreakDown(rates[i])){ state=SEEK_W2DOWN_AFTER_HUNTER; idx=i; found=true; break; }

               if(insideHL[i]) continue;

               int a2=-1,a3=-1,a4=-1;
               if(!CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,a2,a3,a4)) continue;

               c1U=i; c2U=a2; c3U=a3; c4U=a4; cendU=(c4U>=0?c4U:c3U);

               string tag=IntegerToString(pairs+1);
               MarkV("W2U_"+tag+"_C1", rates[c1U].time, clrDeepSkyBlue);
               MarkV("W2U_"+tag+"_C2", rates[c2U].time, clrYellow);
               MarkV("W2U_"+tag+"_C3", rates[c3U].time, clrOrange);
               if(c4U>=0) MarkV("W2U_"+tag+"_C4", rates[c4U].time, clrTomato);

               have_w3U=false; have_breakU=false; firstWickU=-1; anchorU=-1; wickU=false; bodyLevelU=rates[c1U].high;
               idx=cendU; state=BULL_WAIT_W3; found=true; break;
            }
            if(!found) break;
            continue;
         }
         else if(state==BULL_WAIT_W3)
         {
            string tag=IntegerToString(pairs+1);
            bool progressed=false;
            int cand=-1; double cand_low=DBL_MAX;

            for(int j=idx;j<n;++j)
            {
               ExtLQ_OnBar(rates[j]);

               if(Hunter_IsExtLQCross(rates[j])) Hunter_MarkWithC1(rates,n,c1U,j);
               if(IsHunterBodyBreakDown(rates[j])){ state=SEEK_W2DOWN_AFTER_HUNTER; idx=j; progressed=true; break; }
               if(insideHL[j]) continue;

               // body-break با شدو-ارتقایی
               if(!have_breakU && rates[j].high > bodyLevelU)
               {
                  if(rates[j].close > bodyLevelU) have_breakU=true;
                  else{
                     bodyLevelU=rates[j].high;
                     if(firstWickU<0){
                        firstWickU=j; wickU=true;
                        anchorU=IndexOfLeftmostMinLow_ExInside(rates,insideHL,cendU,firstWickU);
                     }
                  }
               }

               int startIdx = -1;
               if(anchorU>=0) startIdx=anchorU;
               else{
                  if(j>cendU && (cand<0 || rates[j].low<cand_low)){ cand=j; cand_low=rates[j].low; }
                  startIdx=cand;
               }

               if(startIdx>=0 && !insideHL[startIdx] && !have_w3U)
               {
                  int a2=-1,a3=-1,a4=-1,e=-1;
                  if(CheckWave3CountOnly_Local(rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,e))
                  { have_w3U=true; w3U_c1=startIdx; u2=a2; u3=a3; u4=a4; w3U_end=e; }
               }

               if(have_breakU && have_w3U)
               {
                  MarkV("W3U_"+tag+"_C1", rates[w3U_c1].time,  clrLime);
                  MarkV("W3U_"+tag+"_C2", rates[u2].time,       clrGreen);
                  MarkV("W3U_"+tag+"_C3", rates[u3].time,       clrTeal);
                  if(u4>=0) MarkV("W3U_"+tag+"_C4", rates[u4].time, clrSeaGreen);

                  ExtLQ_Set(rates[w3U_c1].low, rates[w3U_c1].time);
                  Hunter_OnExtLQUpdated();

                  state=BULL_MONITOR; ++pairs; idx=j; progressed=true; break;
               }
            }
            if(!progressed) break;
            continue;
         }
         else if(state==SEEK_W2DOWN_AFTER_HUNTER)
         {
            bool found=false;
            for(int i=idx;i<n;++i)
            {
               ExtLQ_OnBar(rates[i]);
               if(insideHL[i]) continue;

               int a2=-1,a3=-1,a4=-1;
               if(!CheckWave2Down_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,a2,a3,a4)) continue;

               c1D=i; c2D=a2; c3D=a3; c4D=a4; cendD=(c4D>=0?c4D:c3D);

               string tag="D"+IntegerToString(pairs+1);
               MarkV("W2D_"+tag+"_C1", rates[c1D].time, clrDarkOrange);
               MarkV("W2D_"+tag+"_C2", rates[c2D].time, clrKhaki);
               MarkV("W2D_"+tag+"_C3", rates[c3D].time, clrBisque);
               if(c4D>=0) MarkV("W2D_"+tag+"_C4", rates[c4D].time, clrWheat);

               have_w3D=false; have_breakD=false; firstWickD=-1; anchorD=-1; wickD=false; bodyLevelD=rates[c1D].low;
               idx=cendD; state=SEEK_W3DOWN_CONFIRM; found=true; break;
            }
            if(!found) break;
            continue;
         }
         else if(state==SEEK_W3DOWN_CONFIRM)
         {
            string tag="D"+IntegerToString(pairs+1);
            bool progressed=false;
            int cand=-1; double cand_high=-DBL_MAX;

            for(int j=idx;j<n;++j)
            {
               ExtLQ_OnBar(rates[j]);
               if(insideHL[j]) continue;

               if(!have_breakD && rates[j].low < bodyLevelD)
               {
                  if(rates[j].close < bodyLevelD){ have_breakD=true; idxBreakD=j; }
                  else{
                     bodyLevelD=rates[j].low;
                     if(firstWickD<0){
                        firstWickD=j; wickD=true;
                        // توجه: MaxHigh_ExInside فقط در Wave3Down.mqh تعریف شده
                        anchorD = IndexOfLeftmostMaxHigh_ExInside(rates,insideHL,cendD,firstWickD);
                     }
                  }
               }

               int startIdx=-1;
               if(anchorD>=0) startIdx=anchorD;
               else{
                  if(j>cendD && (cand<0 || rates[j].high>cand_high)){ cand=j; cand_high=rates[j].high; }
                  startIdx=cand;
               }

               if(startIdx>=0 && !insideHL[startIdx] && !have_w3D)
               {
                  int a2=-1,a3=-1,a4=-1,e=-1;
                  if(CheckWave3DownCountOnly_Local(rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,e))
                  { have_w3D=true; w3D_c1=startIdx; d2=a2; d3=a3; d4=a4; w3D_end=e; }
               }

               if(have_breakD && have_w3D)
               {
                  MarkV("W3D_"+tag+"_C1", rates[w3D_c1].time,  clrTomato);
                  MarkV("W3D_"+tag+"_C2", rates[d2].time,       clrIndianRed);
                  MarkV("W3D_"+tag+"_C3", rates[d3].time,       clrFireBrick);
                  if(d4>=0) MarkV("W3D_"+tag+"_C4", rates[d4].time, clrMaroon);

                  MarkMTC("BEAR", rates[idxBreakD].time, clrRed);

                  ExtLQ_Set(rates[w3D_c1].high, rates[w3D_c1].time);
                  HunterDown_OnExtLQUpdated();

                  mode=MODE_BEAR; state=BEAR_MONITOR; ++pairs; idx=idxBreakD; progressed=true; break;
               }
            }
            if(!progressed) break;
            continue;
         }
      }

      // ================== BEAR mode (آینهٔ ساده‌شده) ==================
      if(mode==MODE_BEAR)
      {
         // برای کوتاهی، فقط به مانیتور و بازگشت به SEARCH_W2↓ سوئیچ می‌کنیم
         bool progressed=false;
         for(int j=idx;j<n;++j)
         {
            ExtLQ_OnBar(rates[j]);
            if(IsHunterBodyBreakUp(rates[j])){ state=SEEK_W2UP_AFTER_HUNTER; idx=j; progressed=true; break; }
            if(insideHL[j]) continue;
            state=BEAR_SEARCH_W2; idx=j; progressed=true; break;
         }
         if(!progressed) break;
         continue;
      }

      ++idx;
   }

   if(InpDebugPrints)
      Print("Scan done | pairs=",pairs,(ExtLQ_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Get()):" | ext lq:N/A"));

   return pairs;
}

// شورتکات: برای MostRecentOnly
void API_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int lookback)
{
   datetime stop = TimeCurrent();
   int sec = PeriodSeconds(tf);
   datetime start = stop - (datetime)((long)sec * (long)lookback);
   API_RunScanSequential_BullBear_MTC(sym, tf, start, stop);
}

#endif // WAVEBOT_API_MQH