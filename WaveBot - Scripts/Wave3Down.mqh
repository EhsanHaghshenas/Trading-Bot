#ifndef WAVEBOT_WAVE3DOWN_MQH
#define WAVEBOT_WAVE3DOWN_MQH

// ===== آینهٔ موج۳ صعودی، برای نزولی =====

bool CheckWave3DownCountOnly_Local(const MqlRates &rates[], const bool &insideHL[],
                                   const double &/*bodyLowEff*/[], const double &/*bodyHighEff*/[],
                                   const int n, const int startIdx,
                                   int &k2, int &k3, int &k4, int &w3_end)
{
   k2=k3=k4=-1; w3_end=-1;
   if(startIdx<0 || startIdx>=n-1) return false;

   const double H1 = rates[startIdx].high;
   const double L1 = rates[startIdx].low;
   const bool   c1Bear = (rates[startIdx].close < rates[startIdx].open);
   const int    stepsNeeded = (c1Bear ? 2 : 3);

   int found=0; double lastLow=L1;

   for(int j=startIdx+1; j<n; ++j)
   {
      if(insideHL[j]) continue;
      if(rates[j].close >= rates[j].open) continue; // فقط قرمز

      if(rates[j].low < lastLow)
      {
         ++found; lastLow=rates[j].low;
         if(found==1) k2=j;
         if(found==2) k3=j;
         if(found==3) k4=j;
         if(found>=stepsNeeded){ w3_end=(k4>=0?k4:k3); return true; }
      }
   }
   return false;
}

// بیشترین High چپ‌چین در بازه (با اسکیپ inside) — فقط اینجا تعریف شود
inline int IndexOfLeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[],
                                           const int from, const int to)
{
   if(from>to) return -1;
   double mx=-DBL_MAX; int idx=-1;
   for(int i=from;i<=to;++i)
   {
      if(insideHL[i]) continue;
      const double h=rates[i].high;
      if(h>mx){ mx=h; idx=i; }
   }
   if(idx<0) idx=from;
   return idx;
}

// === confirm W3 bearish: body-break with wick escalation + 3-step count
bool ConfirmWave3Down_WithBreak(const MqlRates &rates[],
                                const bool      &insideHL[],
                                const double    &bodyLowEff[],
                                const double    &bodyHighEff[],
                                const int        n,
                                const int        start_after,   // last bar of W2↓
                                const double     L1_W2,
                                int             &w3_c1,
                                int             &k2,
                                int             &k3,
                                int             &k4,
                                int             &end_idx,
                                int             &idxBreak)
{
   w3_c1=-1; k2=k3=k4=-1; end_idx=-1; idxBreak=-1;

   double bodyLevel = L1_W2;
   bool   haveBreak = false;
   int    firstWick = -1;
   int    anchor    = -1;

   int    cand = -1; double cand_high = -DBL_MAX;

   for(int j=start_after+1; j<n; ++j)
   {
      // ---- body-break زیر سطح با ارتقای سطح توسط شدو
      if(!haveBreak && rates[j].low < bodyLevel)
      {
         if(rates[j].close < bodyLevel) { haveBreak = true; idxBreak = j; }
         else {
            bodyLevel = rates[j].low;
            if(firstWick < 0){
               firstWick = j;
               anchor    = LeftmostMaxNoInside(rates, insideHL, n, start_after, firstWick);
            }
         }
      }

      if(insideHL[j]) continue;

      int startIdx = -1;
      if(anchor >= 0) startIdx = anchor;
      else{
         if(j > start_after){
            if(cand < 0 || rates[j].high > cand_high){ cand = j; cand_high = rates[j].high; }
            startIdx = cand;
         }
      }

      bool haveCount=false; int e=-1, a2=-1, a3=-1, a4=-1;
      if(startIdx >= 0 && !insideHL[startIdx])
      {
         if(CheckWave3DownCountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, e))
         {
            haveCount=true; w3_c1=startIdx; k2=a2; k3=a3; k4=a4; end_idx=e;
         }
      }

      if(haveBreak && haveCount) return true;
   }
   return false;
}

// === helpers (no lambda) ==========================================
int LeftmostMaxNoInside(const MqlRates &rates[], const bool &insideHL[], const int n,
                        const int from, const int to)
{
   if(from>to) return -1;
   double mx = -DBL_MAX; int idx = -1;
   int last = (to < n ? to : n-1);
   for(int i=from; i<=last; ++i){
      if(insideHL[i]) continue;
      double h = rates[i].high;
      if(h > mx){ mx = h; idx = i; }
   }
   if(idx < 0) idx = from;
   return idx;
}

#endif // WAVEBOT_WAVE3DOWN_MQH
