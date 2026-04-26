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
inline bool   C1W2_UP_IsActive(){ return g_c1w2_up_active; }
inline int    C1W2_UP_CurrentIndex(){ return g_c1w2_up_idx; }
inline double C1W2_UP_CurrentLevel(){ return g_c1w2_up_level; }

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
inline bool   C1W2_DN_IsActive(){ return g_c1w2_dn_active; }
inline int    C1W2_DN_CurrentIndex(){ return g_c1w2_dn_idx; }
inline double C1W2_DN_CurrentLevel(){ return g_c1w2_dn_level; }

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

// ===== Path-B Strict Gate (after HWBB) =====
// NOTE: "PB_DN" => Path-B while scanning DOWN (Mode=UP)
//       "PB_UP" => Path-B while scanning UP   (Mode=DOWN)

// ---- DOWN scan (Mode=UP) ----
static bool   g_pb_dn_active = false;
static int    g_pb_dn_idx    = -1;
static double g_pb_dn_level  = 0.0;    // monitor: Low of locked C1

inline void C1W2_PB_DN_Enable()  { g_pb_dn_active=true;  g_pb_dn_idx=-1; g_pb_dn_level=0.0; }
inline void C1W2_PB_DN_Disable() { g_pb_dn_active=false; g_pb_dn_idx=-1; g_pb_dn_level=0.0; }
inline void C1W2_PB_DN_OnW2Locked(){ C1W2_PB_DN_Disable(); }
inline bool   C1W2_PB_DN_IsActive(){ return g_pb_dn_active; }
inline int    C1W2_PB_DN_CurrentIndex(){ return g_pb_dn_idx; }
inline double C1W2_PB_DN_CurrentLevel(){ return g_pb_dn_level; }
inline void C1W2_PB_DN_Reanchor(const MqlRates &rates[], const int i)
{
   if(i<0) return;
   g_pb_dn_idx   = i;
   g_pb_dn_level = rates[i].low;
}

// اجازه‌ی بررسی C1 جدید در Path-B فقط اگر «ابطال با Low/Close پایین‌تر از سطحِ C1 فعلی» رخ داده باشد
inline bool C1W2_PB_DN_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored=false;
   if(!g_pb_dn_active) return true;

   if(g_pb_dn_idx < 0){ g_pb_dn_idx=i; g_pb_dn_level=rates[i].low; return true; }
   if(i==g_pb_dn_idx)  return true;

   if(rates[i].low < g_pb_dn_level || rates[i].close < g_pb_dn_level)
   {
      g_pb_dn_idx   = i;
      g_pb_dn_level = rates[i].low;
      reanchored    = true;
      return true;
   }
   return false;
}

// ---- UP scan (Mode=DOWN) ----
static bool   g_pb_up_active = false;
static int    g_pb_up_idx    = -1;
static double g_pb_up_level  = 0.0;    // monitor: High of locked C1
// ------------------------------
// Context snapshot for C1W2Gate (C1–W2 + Path-B)
// ------------------------------
struct C1W2GateContext
{
   // Main C1–W2 hard gate state (after base pair)
   bool   c1w2_up_active;
   int    c1w2_up_idx;
   double c1w2_up_level;

   bool   c1w2_dn_active;
   int    c1w2_dn_idx;
   double c1w2_dn_level;

   // Path-B strict gate (after HWBB)
   bool   pb_dn_active;
   int    pb_dn_idx;
   double pb_dn_level;

   bool   pb_up_active;
   int    pb_up_idx;
   double pb_up_level;
};

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
inline void C1W2Gate_ContextInit(C1W2GateContext &ctx)
{
   ctx.c1w2_up_active = false;
   ctx.c1w2_up_idx    = -1;
   ctx.c1w2_up_level  = 0.0;

   ctx.c1w2_dn_active = false;
   ctx.c1w2_dn_idx    = -1;
   ctx.c1w2_dn_level  = 0.0;

   ctx.pb_dn_active   = false;
   ctx.pb_dn_idx      = -1;
   ctx.pb_dn_level    = 0.0;

   ctx.pb_up_active   = false;
   ctx.pb_up_idx      = -1;
   ctx.pb_up_level    = 0.0;
}

// Export: کپی وضعیت فعلی globalها به داخل کانتکست
inline void C1W2Gate_ContextExport(C1W2GateContext &ctx)
{
   ctx.c1w2_up_active = g_c1w2_up_active;
   ctx.c1w2_up_idx    = g_c1w2_up_idx;
   ctx.c1w2_up_level  = g_c1w2_up_level;

   ctx.c1w2_dn_active = g_c1w2_dn_active;
   ctx.c1w2_dn_idx    = g_c1w2_dn_idx;
   ctx.c1w2_dn_level  = g_c1w2_dn_level;

   ctx.pb_dn_active   = g_pb_dn_active;
   ctx.pb_dn_idx      = g_pb_dn_idx;
   ctx.pb_dn_level    = g_pb_dn_level;

   ctx.pb_up_active   = g_pb_up_active;
   ctx.pb_up_idx      = g_pb_up_idx;
   ctx.pb_up_level    = g_pb_up_level;
}

// Import: برگرداندن وضعیت ذخیره‌شدهٔ کانتکست به متغیرهای global
inline void C1W2Gate_ContextImport(const C1W2GateContext &ctx)
{
   g_c1w2_up_active = ctx.c1w2_up_active;
   g_c1w2_up_idx    = ctx.c1w2_up_idx;
   g_c1w2_up_level  = ctx.c1w2_up_level;

   g_c1w2_dn_active = ctx.c1w2_dn_active;
   g_c1w2_dn_idx    = ctx.c1w2_dn_idx;
   g_c1w2_dn_level  = ctx.c1w2_dn_level;

   g_pb_dn_active   = ctx.pb_dn_active;
   g_pb_dn_idx      = ctx.pb_dn_idx;
   g_pb_dn_level    = ctx.pb_dn_level;

   g_pb_up_active   = ctx.pb_up_active;
   g_pb_up_idx      = ctx.pb_up_idx;
   g_pb_up_level    = ctx.pb_up_level;
}

// ریست کامل وضعیت گِیت C1–W2 و Path-B در world فعلی
inline void C1W2Gate_ResetGlobals()
{
   g_c1w2_up_active = false;
   g_c1w2_up_idx    = -1;
   g_c1w2_up_level  = 0.0;

   g_c1w2_dn_active = false;
   g_c1w2_dn_idx    = -1;
   g_c1w2_dn_level  = 0.0;

   g_pb_dn_active   = false;
   g_pb_dn_idx      = -1;
   g_pb_dn_level    = 0.0;

   g_pb_up_active   = false;
   g_pb_up_idx      = -1;
   g_pb_up_level    = 0.0;
}

inline void C1W2_PB_UP_Enable()  { g_pb_up_active=true;  g_pb_up_idx=-1; g_pb_up_level=0.0; }
inline void C1W2_PB_UP_Disable() { g_pb_up_active=false; g_pb_up_idx=-1; g_pb_up_level=0.0; }
inline void C1W2_PB_UP_OnW2Locked(){ C1W2_PB_UP_Disable(); }
inline bool   C1W2_PB_UP_IsActive(){ return g_pb_up_active; }
inline int    C1W2_PB_UP_CurrentIndex(){ return g_pb_up_idx; }
inline double C1W2_PB_UP_CurrentLevel(){ return g_pb_up_level; }
inline void C1W2_PB_UP_Reanchor(const MqlRates &rates[], const int i)
{
   if(i<0) return;
   g_pb_up_idx   = i;
   g_pb_up_level = rates[i].high;
}

inline bool C1W2_PB_UP_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored=false;
   if(!g_pb_up_active) return true;

   if(g_pb_up_idx < 0){ g_pb_up_idx=i; g_pb_up_level=rates[i].high; return true; }
   if(i==g_pb_up_idx)  return true;

   if(rates[i].high > g_pb_up_level || rates[i].close > g_pb_up_level)
   {
      g_pb_up_idx   = i;
      g_pb_up_level = rates[i].high;
      reanchored    = true;
      return true;
   }
   return false;
}

#endif // WAVEBOT_C1W2GATE_MQH