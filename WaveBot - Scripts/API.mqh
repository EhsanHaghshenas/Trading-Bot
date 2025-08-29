#ifndef WAVEBOT_API_MQH
#define WAVEBOT_API_MQH

#include <WaveBot/Wave3.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/Hunter.mqh>   // NEW

// نزدیک‌ترین موج۲ (بدون تغییر رفتاری نسبت به قبل؛ مبتنی بر گپ/inside)
bool FindMostRecentWave2(const string sym, const ENUM_TIMEFRAMES tf,
                         const int lookback, int &c1, int &c2, int &c3, int &c4,
                         MqlRates &rates[], int &n)
{
   n=LoadRates(sym,tf,lookback,rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRates failed"); return false; }

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates,n,bodyLowEff,bodyHighEff);
   bool insideFlag[]; BuildInsideClusterFlagsEffective(rates,n,bodyLowEff,bodyHighEff,insideFlag);

   int lastEnd=-1; int bc1=-1,bc2=-1,bc3=-1,bc4=-1;

   for(int i=InpPivotLeft;i<=n-1-InpPivotRight;++i)
   {
      if(insideFlag[i]) continue;
      if(!IsPivotHigh(rates,n,i,InpPivotLeft,InpPivotRight)) continue;

      int a2=-1,a3=-1,a4=-1;
      if(!CheckWave2FromIndex(rates,insideFlag,bodyLowEff,bodyHighEff,n,i,a2,a3,a4)) continue;

      int end=(a4>=0?a4:a3);
      int from=MathMax(0,i-InpExtendLeftForMax);
      int c1max=IndexOfLeftmostMaxHigh(rates,from,end);
      if(insideFlag[c1max]){ i=end; continue; }

      int b2=-1,b3=-1,b4=-1;
      if(!CheckWave2FromIndex(rates,insideFlag,bodyLowEff,bodyHighEff,n,c1max,b2,b3,b4)) continue;

      end=(b4>=0?b4:b3);
      if(end>lastEnd){ lastEnd=end; bc1=c1max; bc2=b2; bc3=b3; bc4=b4; }
      if(end>i) i=end;
   }
   if(lastEnd<0) return false;
   c1=bc1; c2=bc2; c3=bc3; c4=bc4; return true;
}

// --- اسکن ترتیبی STRICT با موج۳ و تبصرهٔ شَدو ---
int API_RunScanSequential_W2W3_ShadowClause(const string sym, const ENUM_TIMEFRAMES tf,
                                            const datetime from_time, const datetime to_time)
{
   const int tfsec = PeriodSeconds(tf);
   const int HISTORY_SKIP_BARS = 3;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj = from_time - tfsec*(InpPivotLeft + InpExtendLeftForMax + 5);

   MqlRates rates[]; int n=LoadRatesRange(sym,tf,from_adj,to_time,rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRatesRange failed"); return 0; }

   // بدنهٔ مؤثر + inside سراسری
   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates,n,bodyLowEff,bodyHighEff);
   bool insideFlag[]; BuildInsideClusterFlagsEffective(rates,n,bodyLowEff,bodyHighEff,insideFlag);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(InpPivotLeft, first_eff - (InpPivotLeft + InpExtendLeftForMax + 2));

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   int pairs=0;
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // وضعیت‌های فاز WAIT_CONFIRM
   bool have_w3=false, have_break=false;
   int  w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;
   double L1_W3=0.0;

   // «تبصرهٔ شدو»
   bool   wickBreakActive=false;
   int    wickBreakIdx=-1;
   double wickBreakHigh=DBL_MIN;

   while(idx <= n-1-InpPivotRight)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx;i<=n-1-InpPivotRight;++i)
         {
            if(insideFlag[i]) continue;
            if(!IsPivotHigh(rates,n,i,InpPivotLeft,InpPivotRight)) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2FromIndex(rates,insideFlag,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;

            const int tmp_end=(i4>=0? i4:i3);

            int from=MathMax(0,i-InpExtendLeftForMax);
            int c1max=IndexOfLeftmostMaxHigh(rates,from,tmp_end);
            if(insideFlag[c1max]){ i=tmp_end; continue; }

            int j2=-1,j3=-1,j4=-1;
            if(!CheckWave2FromIndex(rates,insideFlag,bodyLowEff,bodyHighEff,n,c1max,j2,j3,j4)) { i=tmp_end; continue; }

            c1=c1max; c2=j2; c3=j3; c4=j4;
            cend=(c4>=0? c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time) { idx=cend+1; continue; }

            string tag=IntegerToString(pairs+1);
            MarkV("W2_"+tag+"_C1", rates[c1].time, clrDeepSkyBlue);
            MarkV("W2_"+tag+"_C2", rates[c2].time, clrYellow);
            MarkV("W2_"+tag+"_C3", rates[c3].time, clrOrange);
            if(c4>=0) MarkV("W2_"+tag+"_C4", rates[c4].time, clrTomato);
            if(InpDebugPrints) Print("#",tag," W2 found @ ",T(rates[c1].time));

            // ریست فاز تأیید
            have_w3=false; have_break=false;
            w3_c1=-1; k2=k3=k4=-1; w3_end=-1; L1_W3=0.0;
            wickBreakActive=false; wickBreakIdx=-1; wickBreakHigh=DBL_MIN;

            idx = cend;   // از انتهای W2 وارد WAIT_CONFIRM می‌شویم
            state = WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // WAIT_CONFIRM
      {
         const double H1_W2 = rates[c1].high;
         string tag=IntegerToString(pairs+1);
         bool progressed=false;

         // کاندیدای آغاز W3 = «آخرین پیوت لو که کمترین Low را تا این لحظه دارد»
         int    cand_c1 = w3_c1;
         double cand_low = (w3_c1>=0 ? rates[w3_c1].low : DBL_MAX);

         for(int j=idx; j<=n-1-InpPivotRight; ++j)
         {
            // 1) پیوت لو جدید با Low پایین‌تر ⇒ بروزرسانی آغاز W3
            if(IsPivotLow(rates,n,j,InpPivotLeft,InpPivotRight) && !insideFlag[j])
            {
               if(cand_c1<0 || rates[j].low < cand_low)
               {
                  cand_c1 = j;
                  cand_low = rates[j].low;

                  int a2=-1,a3=-1,a4=-1, w3e=-1; double L1tmp=0.0;
                  if(CheckWave3CountOnly(rates,insideFlag,n,cand_c1,a2,a3,a4,w3e,L1tmp))
                  { have_w3=true; w3_c1=cand_c1; k2=a2; k3=a3; k4=a4; w3_end=w3e; L1_W3=L1tmp; }
                  else
                  { have_w3=false; w3_c1=cand_c1; k2=k3=k4=-1; w3_end=-1; L1_W3=rates[cand_c1].low; }
               }
            }

            // 2) اگر شمارش کامل نبود، با cand_c1 بررسی CountOnly را به‌روز نگه دار
            if(cand_c1>=0 && !have_w3)
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1; double L1tmp=0.0;
               if(CheckWave3CountOnly(rates,insideFlag,n,cand_c1,a2,a3,a4,w3e,L1tmp))
               { have_w3=true; w3_c1=cand_c1; k2=a2; k3=a3; k4=a4; w3_end=w3e; L1_W3=L1tmp; }
            }

            // --- تبصرهٔ شدو (فقط اگر C1_W3 داریم) ---
            if(w3_c1>=0)
            {
               if(!wickBreakActive && rates[j].high > H1_W2 && rates[j].close <= H1_W2)
               { wickBreakActive=true; wickBreakIdx=j; wickBreakHigh=rates[j].high; }

               if(wickBreakActive)
               {
                  if(rates[j].low < rates[w3_c1].low)
                  { // باطل شد ⇒ ext lq تغییری نمی‌کند
                     if(InpDebugPrints) Print("#",tag," W2 invalidated (shadow clause). Restart from ",T(rates[wickBreakIdx].time));
                     idx = wickBreakIdx; state = SEARCH_W2; progressed=true; break;
                  }
                  if(rates[j].close > wickBreakHigh)
                  { have_break=true; wickBreakActive=false; }
               }
            }

            // 3) بریک بدنهٔ استاندارد
            if(!have_break && rates[j].close > H1_W2) have_break=true;

            // 4) اگر هر دو شرط برقرار شد ⇒ تایید جفت و به‌روزرسانی ext lq
            if(have_break && have_w3)
            {
               // ext lq = Lowِ C1_W3 همین جفت
               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);

               // مارکرهای W3 (کندل بریک مارک نمی‌شود)
               MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrLime);
               MarkV("W3_"+tag+"_C2", rates[k2].time,     clrGreen);
               MarkV("W3_"+tag+"_C3", rates[k3].time,     clrTeal);
               if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrSeaGreen);

               if(InpDebugPrints) Print("#",tag," Pair OK | ext lq updated to ",DoubleToString(ExtLQ_Get(),_Digits),
                                         " @ ",T(ExtLQ_Time())," | break-by-body @ ",T(rates[j].time));
               idx = j; state = SEARCH_W2; ++pairs; progressed=true; break;
            }
         }

         if(!progressed) break;
      }
   }

   if(InpDebugPrints) Print("STRICT pairs: ",pairs,
                            (ExtLQ_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Get()) : " | ext lq: n/a"));
   return pairs;
}

// نمایش نزدیک‌ترین جفت (W2→W3) — از همان اسکن ترتیبی استفاده می‌کنیم
void API_ShowMostRecentW2W3(const string sym, const ENUM_TIMEFRAMES tf, const int lookback)
{
   datetime start = 0;
   datetime stop  = TimeCurrent();
   API_RunScanSequential_W2W3_ShadowClause(sym, tf, start, stop);
}

int API_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
                                      const datetime from_time, const datetime to_time)
{
   const int tfsec = PeriodSeconds(tf);
   const int HISTORY_SKIP_BARS = 3;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj = from_time - tfsec*(InpPivotLeft + InpExtendLeftForMax + 5);

   MqlRates rates[]; int n=LoadRatesRange(sym,tf,from_adj,to_time,rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRatesRange failed"); return 0; }

   // گپ/inside سراسری
   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates,n,bodyLowEff,bodyHighEff);
   bool insideFlag[]; BuildInsideClusterFlagsEffective(rates,n,bodyLowEff,bodyHighEff,insideFlag);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(InpPivotLeft, first_eff - (InpPivotLeft + InpExtendLeftForMax + 2));

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   int pairs=0;
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // وضعیت‌های فاز WAIT_CONFIRM (منطق سابق)
   bool have_w3=false, have_break=false;
   int  w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;
   double L1_W3=0.0;

   // «تبصرهٔ شدو» (منطق سابق)
   bool   wickBreakActive=false;
   int    wickBreakIdx=-1;
   double wickBreakHigh=DBL_MIN;

   // Hunter در شروع اسکن غیرفعال است
   Hunter_ResetState();

   while(idx <= n-1-InpPivotRight)
   {
      // اگر Hunter فعال است، فقط Hunter را پردازش کن
      if(Hunter_IsActive())
      {
         // اسکن کندل‌ها در Hunter: از idx تا وقتی Hunter پایان یابد یا داده تمام شود
         bool progressed=false;
         for(int j=idx; j<=n-1-InpPivotRight; ++j)
         {
            // پایان Hunter؟
            if(Hunter_ProcessBar(rates,insideFlag,n,j))
            {
               // Hunter تمام شد → جفت جدید تایید شد و ext lq آپدیت شد.
               // نقطه‌ی شروع اسکن عادی بعدی: خودِ کندل بریکِ بدنه
               Hunter_OnPairConfirmed(j);  // تایید اخیر برای Hunter/تکرار بعدی
               idx = j; state = SEARCH_W2; ++pairs;
               progressed=true;
               break;
            }
         }
         if(!progressed) break; // داده تمام شد
         continue;              // برگرد به حلقه اصلی
      }

      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx;i<=n-1-InpPivotRight;++i)
         {
            // قبل از هر چیز: اگر تریگر Hunter رخ دهد، تلاش به فعال‌سازی
            if(Hunter_IsExtLQCross(rates[i]))
            {
               if(Hunter_TryActivateOnCross(rates,insideFlag,bodyLowEff,bodyHighEff,n,i))
               {
                  idx=i; found=true; break; // Hunter فعال شد؛ در iteration بعدی وارد بلوک Hunter می‌شویم
               }
            }

            if(insideFlag[i]) continue;
            if(!IsPivotHigh(rates,n,i,InpPivotLeft,InpPivotRight)) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2FromIndex(rates,insideFlag,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;

            const int tmp_end=(i4>=0? i4:i3);

            int from=MathMax(0,i-InpExtendLeftForMax);
            int c1max=IndexOfLeftmostMaxHigh(rates,from,tmp_end);
            if(insideFlag[c1max]){ i=tmp_end; continue; }

            int j2=-1,j3=-1,j4=-1;
            if(!CheckWave2FromIndex(rates,insideFlag,bodyLowEff,bodyHighEff,n,c1max,j2,j3,j4)) { i=tmp_end; continue; }

            c1=c1max; c2=j2; c3=j3; c4=j4;
            cend=(c4>=0? c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time) { idx=cend+1; continue; }

            string tag=IntegerToString(pairs+1);
            MarkV("W2_"+tag+"_C1", rates[c1].time, clrDeepSkyBlue);
            MarkV("W2_"+tag+"_C2", rates[c2].time, clrYellow);
            MarkV("W2_"+tag+"_C3", rates[c3].time, clrOrange);
            if(c4>=0) MarkV("W2_"+tag+"_C4", rates[c4].time, clrTomato);
            if(InpDebugPrints) Print("#",tag," W2 found @ ",T(rates[c1].time));

            // ریست فاز تایید
            have_w3=false; have_break=false;
            w3_c1=-1; k2=k3=k4=-1; w3_end=-1; L1_W3=0.0;
            wickBreakActive=false; wickBreakIdx=-1; wickBreakHigh=DBL_MIN;

            idx = cend;   // از انتهای W2 وارد WAIT_CONFIRM می‌شویم
            state = WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // WAIT_CONFIRM
      {
         const double H1_W2 = rates[c1].high;
         string tag=IntegerToString(pairs+1);
         bool progressed=false;

         for(int j=idx; j<=n-1-InpPivotRight; ++j)
         {
            // تریگر Hunter در حین WAIT_CONFIRM (قبل از اتمام تایید)؟
            if(Hunter_IsExtLQCross(rates[j]))
            {
               if(Hunter_TryActivateOnCross(rates,insideFlag,bodyLowEff,bodyHighEff,n,j))
               {
                  idx=j; progressed=true; break; // Hunter فعال شد؛ بلاک Hunter را پردازش می‌کنیم
               }
            }

            // منطق قبلی W3 + تبصرهٔ شدو (بدون تغییر)
            if(w3_c1<0 && IsPivotLow(rates,n,j,InpPivotLeft,InpPivotRight))
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1; double L1tmp=0.0;
               if(CheckWave3CountOnly(rates,insideFlag,n,j,a2,a3,a4,w3e,L1tmp))
               {
                  w3_c1=j; k2=a2; k3=a3; k4=a4; w3_end=w3e; L1_W3=L1tmp; have_w3=true;

                  MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrLime);
                  MarkV("W3_"+tag+"_C2", rates[k2].time,     clrGreen);
                  MarkV("W3_"+tag+"_C3", rates[k3].time,     clrTeal);
                  if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrSeaGreen);
               }
            }

            if(w3_c1>=0 && rates[j].high > H1_W2 && rates[j].close <= H1_W2 && !wickBreakActive)
            { wickBreakActive=true; wickBreakIdx=j; wickBreakHigh=rates[j].high; }

            if(wickBreakActive)
            {
               if(rates[j].low < rates[w3_c1].low)
               { // باطل: به کندل شَدو برگرد و W2 را از نو
                  if(InpDebugPrints) Print("#",tag," W2 invalidated by W3 C1 low. Restart from ",T(rates[wickBreakIdx].time));
                  idx = wickBreakIdx; state = SEARCH_W2; progressed=true; break;
               }
               if(rates[j].close > wickBreakHigh)
               { have_break=true; wickBreakActive=false; }
            }

            if(!have_break && rates[j].close > H1_W2) have_break=true;

            if(have_break && have_w3)
            {
               // ext lq = Lowِ C1_W3 همین جفت
               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);

               if(InpDebugPrints) Print("#",tag," Pair OK | ext lq=",DoubleToString(ExtLQ_Get(),_Digits),
                                        " @ ",T(ExtLQ_Time())," | break-by-body @ ",T(rates[j].time));

               // به Hunter اطلاع بده «کندل تایید» کدام است
               Hunter_OnPairConfirmed(j);

               idx   = j;                 // شروع W2 بعدی از خودِ کندل بریک
               state = SEARCH_W2; ++pairs; progressed=true; break;
            }
         }

         if(!progressed) break;
      }
   }

   if(InpDebugPrints) Print("STRICT pairs (with Hunter): ",pairs,
                            (ExtLQ_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Get()) : " | ext lq: n/a"));
   return pairs;
}

// (اختیاری) نمایش فوری — از اسکن Hunter استفاده می‌کند
void API_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int lookback)
{
   datetime start = 0;
   datetime stop  = TimeCurrent();
   API_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_MQH