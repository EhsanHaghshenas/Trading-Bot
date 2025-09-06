#ifndef WAVEBOT_EXTLQ_DOWN_MQH
#define WAVEBOT_EXTLQ_DOWN_MQH

// -------------------- وضعیت ext lq فعلی (Down) --------------------
static bool     g_extD_has   = false;
static double   g_extD_price = 0.0;
static datetime g_extD_time  = 0;

// -------------------- تاریخچهٔ ext lq های قبلی --------------------
struct LQLevel_D
{
   double   price;
   datetime t;
   bool     broken;
};

// آرایهٔ تاریخچه (از قدیمی به جدید)
static LQLevel_D g_histD[];
static int       g_prev_idxD = -1;

#define EXTLQ_D_LINE_CURR  "EXTLQ_D_CURR"
#define EXTLQ_D_LINE_PREV  "EXTLQ_D_PREV"

inline void ExtLQ_Down_DeleteLine(const string name)
{
   if(ObjectFind(0,name)!=-1) ObjectDelete(0,name);
}

inline void ExtLQ_Down_DrawLine(const string name, const double price, const color col, const ENUM_LINE_STYLE st)
{
   if(ObjectFind(0,name)==-1) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,st);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
}

inline bool ExtLQ_Down_Has(){ return g_extD_has; }
inline double ExtLQ_Down_Get(){ return g_extD_price; }
inline datetime ExtLQ_Down_Time(){ return g_extD_time; }

// آخرین رزرویِ دست‌نخورده
int ExtLQ_Down_FindLatestUntouchedIndex()
{
   int sz = ArraySize(g_histD);
   for(int i=sz-1;i>=0;--i)
      if(!g_histD[i].broken) return i;
   return -1;
}

// تنظیم سطح جدید (Down = Highِ C1_W3)
inline void ExtLQ_Down_Set(const double price, const datetime t)
{
   g_extD_has   = true;
   g_extD_price = price;
   g_extD_time  = t;

   // به تاریخچه اضافه کن و قبلی‌ها را نمایش/رزرو کن
   int sz = ArraySize(g_histD);
   ArrayResize(g_histD, sz+1);
   g_histD[sz].price  = price;
   g_histD[sz].t      = t;
   g_histD[sz].broken = false;

   // خط فعلی
   if(InpDrawExtLQ) ExtLQ_Down_DrawLine(EXTLQ_D_LINE_CURR, price, InpExtLQColor, STYLE_SOLID);

   // رزروی جدید را پیدا و رسم کن
   int idx = ExtLQ_Down_FindLatestUntouchedIndex();
   if(g_prev_idxD != idx)
   {
      if(g_prev_idxD>=0) ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_PREV);
      g_prev_idxD = idx;
      if(g_prev_idxD>=0 && InpDrawExtLQ)
         ExtLQ_Down_DrawLine(EXTLQ_D_LINE_PREV, g_histD[g_prev_idxD].price, clrViolet, STYLE_DOT);
   }
}

// آپدیت روی هر کندل (cross-up)
inline void ExtLQ_Down_OnBar(const MqlRates &r)
{
   int sz = ArraySize(g_histD);
   if(sz>0)
   {
      for(int i=0;i<sz;++i)
      {
         if(!g_histD[i].broken)
         {
            if(r.high >= g_histD[i].price || r.close > g_histD[i].price)
               g_histD[i].broken = true;
         }
      }
      int idx = ExtLQ_Down_FindLatestUntouchedIndex();
      if(idx != g_prev_idxD)
      {
         if(g_prev_idxD>=0) ExtLQ_Down_DeleteLine(EXTLQ_D_LINE_PREV);
         g_prev_idxD = idx;
         if(g_prev_idxD>=0 && InpDrawExtLQ)
            ExtLQ_Down_DrawLine(EXTLQ_D_LINE_PREV, g_histD[g_prev_idxD].price, clrViolet, STYLE_DOT);
      }
   }
}

#endif // WAVEBOT_EXTLQ_DOWN_MQH
