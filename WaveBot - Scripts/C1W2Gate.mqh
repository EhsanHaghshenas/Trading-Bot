// WaveBot/C1W2Gate.mqh
#ifndef WAVEBOT_C1W2GATE_MQH
#define WAVEBOT_C1W2GATE_MQH

// وضعیت برای اسکنِ W2 صعودیِ بعد از یک جفتِ صعودی
static bool   g_c1w2_up_active = false;
static int    g_c1w2_up_idx    = -1;     // اندیس کندلِ کاندید جاری
static double g_c1w2_up_level  = 0.0;    // سطح پایش ابطال = High(c1)

// وضعیت برای اسکنِ W2 نزولیِ بعد از یک جفتِ نزولی
static bool   g_c1w2_dn_active = false;
static int    g_c1w2_dn_idx    = -1;     // اندیس کندلِ کاندید جاری
static double g_c1w2_dn_level  = 0.0;    // سطح پایش ابطال = Low(c1)

// ---------- UP ----------
inline void C1W2_UP_Start(const MqlRates &rates[], const int idx)
{
   g_c1w2_up_active = true;
   g_c1w2_up_idx    = idx;
   g_c1w2_up_level  = rates[idx].high; // بعدِ جفتِ صعودی: پایشِ High
}

inline void C1W2_UP_OnW2Locked()
{
   // به‌محض قفل‌شدن W2 (ورود به WAIT_CONFIRM)، قانون c1_w2 برای این سیکل تمام است
   g_c1w2_up_active = false;
}

inline bool C1W2_UP_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored = false;
   if(!g_c1w2_up_active) return true;        // گِیت خاموش ⇒ اجازهٔ بررسی
   if(i <  g_c1w2_up_idx) return true;       // قبل از کاندید (از نظر زمانی) ⇒ بی‌اثر
   if(i == g_c1w2_up_idx) return true;       // خودِ کندلِ کاندید ⇒ شروع مجاز

   // i > کاندید: داخل «پنجرهٔ ممنوعه» هستیم مگر اینکه شکست رخ دهد:
   if(rates[i].high > g_c1w2_up_level)       // شکست با wick یا body (STRICT: >)
   {
      // ابطال کاندید قبلی و ری‌انکر روی همین کندل
      g_c1w2_up_idx   = i;
      g_c1w2_up_level = rates[i].high;
      reanchored      = true;
      return true;                           // از همین کندل، شمارش W2 از نو مجاز است
   }
   // هنوز شکست روی سطح پایش رخ نداده ⇒ ممنوعیت
   return false;
}

// ---------- DOWN ----------
inline void C1W2_DN_Start(const MqlRates &rates[], const int idx)
{
   g_c1w2_dn_active = true;
   g_c1w2_dn_idx    = idx;
   g_c1w2_dn_level  = rates[idx].low; // بعدِ جفتِ نزولی: پایشِ Low
}

inline void C1W2_DN_OnW2Locked()
{
   g_c1w2_dn_active = false;
}

inline bool C1W2_DN_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored = false;
   if(!g_c1w2_dn_active) return true;
   if(i <  g_c1w2_dn_idx) return true;
   if(i == g_c1w2_dn_idx) return true;

   // i > کاندید: اجازه فقط اگر Low با هر نوع عبور شکسته شود
   if(rates[i].low < g_c1w2_dn_level)        // STRICT: <
   {
      g_c1w2_dn_idx   = i;
      g_c1w2_dn_level = rates[i].low;
      reanchored      = true;
      return true;
   }
   return false;
}

#endif // WAVEBOT_C1W2GATE_MQH
