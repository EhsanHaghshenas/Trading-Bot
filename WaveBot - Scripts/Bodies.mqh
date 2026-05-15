#ifndef WAVEBOT_BODIES_MQH
#define WAVEBOT_BODIES_MQH

// ============================================================================
// Bodies.mqh
// Safe effective-body / inside-bar builders.
//
// Important:
// MQL5 dynamic arrays do not have unlimited capacity. ArrayResize() can fail
// under heavy memory pressure, especially on very large M1 ranges or nested
// rescans. The old code ignored the ArrayResize() return value and then wrote
// bodyHighEff[i] / bodyLowEff[i], which could produce:
//    array out of range in 'Bodies.mqh' (26,19)
//
// These builders now validate the real rates[] size and the ArrayResize()
// result before writing to output arrays. Normal successful paths keep exactly
// the same candle/body/inside-bar logic.
// ============================================================================

static bool g_wb_bodies_last_build_ok = true;

inline bool WB_Bodies_LastBuildOK()
{
   return g_wb_bodies_last_build_ok;
}

inline int __WB_BodiesSafeCount(const MqlRates &rates[], const int requested_n)
{
   if(requested_n <= 0)
      return 0;

   const int rates_n = ArraySize(rates);
   if(rates_n <= 0)
      return 0;

   if(requested_n < rates_n)
      return requested_n;

   return rates_n;
}

inline bool __WB_BodiesResizeDouble(double &arr[], const int target_n, const string label)
{
   if(target_n <= 0)
   {
      ArrayResize(arr, 0);
      return false;
   }

   ResetLastError();
   int resized = ArrayResize(arr, target_n);
   if(resized == target_n)
      return true;

   const int first_result = resized;
   const int err1 = GetLastError();

   // Retry once after releasing any old buffer that may be attached to the
   // caller's dynamic array. This is cheap for fresh locals and helps reused
   // arrays under fragmented memory.
   ArrayFree(arr);
   ResetLastError();
   resized = ArrayResize(arr, target_n);
   if(resized == target_n)
      return true;

   const int retry_result = resized;
   const int err2 = GetLastError();
   Print("[WB-BODIES-ERROR] ArrayResize failed for ", label,
         " | requested=", target_n,
         " | first_result=", first_result,
         " | retry_result=", retry_result,
         " | first_error=", err1,
         " | retry_error=", err2,
         ". This is memory/allocation pressure, not a candle-logic error.");

   ArrayFree(arr);
   return false;
}

inline bool __WB_BodiesResizeBool(bool &arr[], const int target_n, const string label)
{
   if(target_n <= 0)
   {
      ArrayResize(arr, 0);
      return false;
   }

   ResetLastError();
   int resized = ArrayResize(arr, target_n);
   if(resized == target_n)
      return true;

   const int first_result = resized;
   const int err1 = GetLastError();

   ArrayFree(arr);
   ResetLastError();
   resized = ArrayResize(arr, target_n);
   if(resized == target_n)
      return true;

   const int retry_result = resized;
   const int err2 = GetLastError();
   Print("[WB-BODIES-ERROR] ArrayResize failed for ", label,
         " | requested=", target_n,
         " | first_result=", first_result,
         " | retry_result=", retry_result,
         " | first_error=", err1,
         " | retry_error=", err2,
         ". This is memory/allocation pressure, not a candle-logic error.");

   ArrayFree(arr);
   return false;
}

// بدنه‌ی مؤثر با لحاظ گپ: بدنه‌ی کندل i گسترده تا Open[i+1]
// اگر i آخرین کندل باشد، از Close[i] استفاده می‌کنیم
bool BuildEffectiveBodies(const MqlRates &rates[], const int n,
                          double &bodyLowEff[], double &bodyHighEff[])
{
   g_wb_bodies_last_build_ok = false;

   const int safe_n = __WB_BodiesSafeCount(rates, n);
   if(safe_n <= 0)
   {
      ArrayResize(bodyLowEff,  0);
      ArrayResize(bodyHighEff, 0);
      return false;
   }

   if(safe_n != n)
   {
      Print("[WB-BODIES-ERROR] BuildEffectiveBodies received inconsistent count",
            " | requested_n=", n,
            " | rates_size=", ArraySize(rates),
            " | safe_n=", safe_n,
            ". Aborting this scan segment to avoid downstream array access with mismatched sizes.");
      ArrayResize(bodyLowEff, 0);
      ArrayResize(bodyHighEff, 0);
      return false;
   }

   if(!__WB_BodiesResizeDouble(bodyLowEff, safe_n, "bodyLowEff") ||
      !__WB_BodiesResizeDouble(bodyHighEff, safe_n, "bodyHighEff"))
   {
      // Keep both arrays empty together. This prevents the old immediate
      // out-of-range write in Bodies.mqh and makes the allocation failure
      // explicit in the Experts log.
      ArrayFree(bodyLowEff);
      ArrayFree(bodyHighEff);
      return false;
   }

   for(int i=0; i<safe_n; ++i)
   {
      const double o  = rates[i].open;
      const double c  = rates[i].close;
      const double o1 = (i + 1 < safe_n ? rates[i+1].open : c); // برای آخرین کندل

      double hi = MathMax(o, c);
      double lo = MathMin(o, c);

      // افزودن گپ به بدنه
      if(o1 > hi) hi = o1;
      if(o1 < lo) lo = o1;

      bodyHighEff[i] = hi;
      bodyLowEff[i]  = lo;
   }

   g_wb_bodies_last_build_ok = true;
   return true;
}

// پرچم inside خوشه‌ای سراسری بر مبنای High/Low کندل مادر
// تا وقتی کندل‌ها داخل بازه MotherBar باشند، insideFlagHL[i]=true
bool BuildInsideClusterFlagsHL(const MqlRates &rates[], const int n,
                               bool &insideFlagHL[])
{
   const int safe_n = __WB_BodiesSafeCount(rates, n);
   if(safe_n <= 0)
   {
      ArrayResize(insideFlagHL, 0);
      return false;
   }

   if(safe_n != n)
   {
      Print("[WB-BODIES-ERROR] BuildInsideClusterFlagsHL received inconsistent count",
            " | requested_n=", n,
            " | rates_size=", ArraySize(rates),
            " | safe_n=", safe_n,
            ". Aborting this scan segment to avoid downstream array access with mismatched sizes.");
      ArrayResize(insideFlagHL, 0);
      return false;
   }

   if(!__WB_BodiesResizeBool(insideFlagHL, safe_n, "insideFlagHL"))
      return false;

   ArrayInitialize(insideFlagHL, false);
   if(safe_n < 2)
      return true;

   double motherHigh = 0.0, motherLow = 0.0;
   bool   clusterOn  = false;

   for(int i=1; i<safe_n; ++i)
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

   return true;
}

#endif // WAVEBOT_BODIES_MQH
