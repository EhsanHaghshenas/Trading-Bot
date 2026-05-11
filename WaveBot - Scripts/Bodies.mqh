
#ifndef WAVEBOT_BODIES_MQH
#define WAVEBOT_BODIES_MQH

// بدنه‌ی مؤثر با لحاظ گپ: بدنه‌ی کندل i گسترده تا Open[i+1]
// اگر i آخرین کندل باشد، از Close[i] استفاده می‌کنیم
void BuildEffectiveBodies(const MqlRates &rates[], const int n,
                          double &bodyLowEff[], double &bodyHighEff[])
{
   ArrayResize(bodyLowEff,  n);
   ArrayResize(bodyHighEff, n);
   if(n<=0) return;

   for(int i=0; i<n; ++i)
   {
      const double o  = rates[i].open;
      const double c  = rates[i].close;
      const double o1 = (i+1<n ? rates[i+1].open : c); // برای آخرین کندل

      double hi = MathMax(o, c);
      double lo = MathMin(o, c);

      // افزودن گپ به بدنه
      if(o1 > hi) hi = o1;
      if(o1 < lo) lo = o1;

      bodyHighEff[i] = hi;
      bodyLowEff[i]  = lo;
   }
}

// پرچم inside خوشه‌ای سراسری بر مبنای High/Low کندل مادر
// تا وقتی کندل‌ها داخل بازه MotherBar باشند، insideFlagHL[i]=true
void BuildInsideClusterFlagsHL(const MqlRates &rates[], const int n,
                               bool &insideFlagHL[])
{
   ArrayResize(insideFlagHL, n);
   ArrayInitialize(insideFlagHL, false);
   if(n<2) return;

   double motherHigh = 0.0, motherLow = 0.0;
   bool   clusterOn  = false;

   for(int i=1; i<n; ++i)
   {
      const MqlRates prev = rates[i-1];
      const MqlRates cur  = rates[i];

      if(!clusterOn)
      {
         if(cur.high <= prev.high && cur.low >= prev.low)
         {
            motherHigh = prev.high;
            motherLow  = prev.low;
            clusterOn  = true;
            insideFlagHL[i] = true;
         }
      }
      else
      {
         if(cur.high <= motherHigh && cur.low >= motherLow)
         {
            insideFlagHL[i] = true; // ادامه خوشه
         }
         else
         {
            clusterOn = false;
            if(cur.high <= prev.high && cur.low >= prev.low)
            {
               motherHigh = prev.high;
               motherLow  = prev.low;
               clusterOn  = true;
               insideFlagHL[i] = true; // شروع خوشه جدید
            }
         }
      }
   }
}

#endif // WAVEBOT_BODIES_MQH

