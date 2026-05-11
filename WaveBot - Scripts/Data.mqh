
#ifndef WAVEBOT_DATA_MQH
#define WAVEBOT_DATA_MQH

#include <WaveBot/Bodies.mqh>   // بدنهٔ مؤثر (body+gap)

// --- Data loading ---
int LoadRates(const string sym, const ENUM_TIMEFRAMES tf, const int bars, MqlRates &out[])
{
   ArrayFree(out);
   int copied=CopyRates(sym,tf,0,bars,out);
   if(copied<=0) return 0;
   ArraySetAsSeries(out,false);
   return copied;
}
int LoadRatesRange(const string sym, const ENUM_TIMEFRAMES tf, const datetime from, const datetime to, MqlRates &out[])
{
   ArrayFree(out);
   int copied=CopyRates(sym,tf,from,to,out);
   if(copied<=0) return 0;
   ArraySetAsSeries(out,false);
   return copied;
}

// --- Global Inside-Bar Gate using Effective Envelope (body+gap fused with wick range) ---
// insideFlag[i] = true اگر کندل i درون «پوشش مؤثرِ مادرِ جاری» باشد.
void BuildInsideClusterFlagsEffective(const MqlRates &rates[], const int n,
                                      const double &bodyLowEff[], const double &bodyHighEff[],
                                      bool &insideFlag[])
{
   ArrayResize(insideFlag, n);
   if(n<=0){ return; }

   // پوشش مؤثر مادر (بدنهٔ مؤثر + ویک‌های خودش)
   double motherHighEnv = MathMax(bodyHighEff[0], rates[0].high);
   double motherLowEnv  = MathMin(bodyLowEff[0],  rates[0].low);

   insideFlag[0]=false;

   for(int i=1;i<n;++i)
   {
      bool inside = (rates[i].high <= motherHighEnv && rates[i].low >= motherLowEnv);
      insideFlag[i] = inside;

      // خروج از inside ⇒ مادر جدید = همین کندل با پوشش مؤثر خودش
      if(!inside)
      {
         motherHighEnv = MathMax(bodyHighEff[i], rates[i].high);
         motherLowEnv  = MathMin(bodyLowEff[i],  rates[i].low);
      }
   }
}

// --- Date helpers ---
int DaysInMonth(int y,int m)
{
   if(m==1||m==3||m==5||m==7||m==8||m==10||m==12) return 31;
   if(m==4||m==6||m==9||m==11) return 30;
   bool leap=((y%4==0 && y%100!=0)||(y%400==0));
   return (leap?29:28);
}
datetime MonthsAgoDT(const int months)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int y=dt.year, m=dt.mon-months; while(m<=0){ m+=12; y--; }
   int d=MathMin(dt.day, DaysInMonth(y,m));
   dt.year=y; dt.mon=m; dt.day=d; dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
}
datetime ResolveScanStart(const bool useMonthsAgo, const int monthsAgo, const datetime scanFrom)
{
   if(useMonthsAgo) return MonthsAgoDT(monthsAgo);
   MqlDateTime d; TimeToStruct(scanFrom,d); d.hour=0; d.min=0; d.sec=0; return StructToTime(d);
}

#endif // WAVEBOT_DATA_MQH

