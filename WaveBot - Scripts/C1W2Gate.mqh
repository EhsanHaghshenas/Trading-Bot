// C1W2Gate.mqh

#ifndef WAVEBOT_C1W2GATE_MQH
#define WAVEBOT_C1W2GATE_MQH

// ------------------------------
// Context for C1–W2 and Path-B
// ------------------------------
struct C1W2GateCtx
{
   // Main c1–w2 hard gate (after base pair)
   bool   up_active;
   int    up_idx;
   double up_level;

   bool   dn_active;
   int    dn_idx;
   double dn_level;

   // Path-B strict gate (after HWBB)
   // PB_DN  => scanning DOWN (Mode=UP)
   bool   pb_dn_active;
   int    pb_dn_idx;
   double pb_dn_level;

   // PB_UP  => scanning UP (Mode=DOWN)
   bool   pb_up_active;
   int    pb_up_idx;
   double pb_up_level;
};

// کانتکست پیش‌فرض که تمام کدهای قدیمی (بدون ctx) از آن استفاده می‌کنند
static C1W2GateCtx g_c1w2_default_ctx;

// --- helpers برای یک کانتکست ---

inline void C1W2Gate_InitCtx(C1W2GateCtx &ctx)
{
   ctx.up_active  = false;
   ctx.up_idx     = -1;
   ctx.up_level   = 0.0;

   ctx.dn_active  = false;
   ctx.dn_idx     = -1;
   ctx.dn_level   = 0.0;

   ctx.pb_dn_active = false;
   ctx.pb_dn_idx    = -1;
   ctx.pb_dn_level  = 0.0;

   ctx.pb_up_active = false;
   ctx.pb_up_idx    = -1;
   ctx.pb_up_level  = 0.0;
}

// ریست کامل state داخلی ماژول (جهت شروع اسکن جدید / تغییر سمبل / تایم‌فریم)
inline void C1W2Gate_ResetGlobals()
{
   C1W2Gate_InitCtx(g_c1w2_default_ctx);
}

// snapshot helpers برای دنیای ماژور/مینور
inline void C1W2Gate_ExportCtx(C1W2GateCtx &dst)
{
   dst = g_c1w2_default_ctx;
}

inline void C1W2Gate_ImportCtx(const C1W2GateCtx &src)
{
   g_c1w2_default_ctx = src;
}

// =====================================================
//   UP: بعد از جفت صعودی  (Mode = UP; scan W2-UP)
// =====================================================

// نسخهٔ کانتکست‌محور
inline void C1W2_UP_Start_Ctx(C1W2GateCtx &ctx,
                              const MqlRates &rates[],
                              const int idx)
{
   ctx.up_active = true;
   ctx.up_idx    = idx;
   ctx.up_level  = rates[idx].high; // بعدِ جفتِ صعودی: پایشِ High
}

// نسخهٔ بدون ctx (سازگار با کد فعلی) ⇒ روی کانتکست پیش‌فرض
inline void C1W2_UP_Start(const MqlRates &rates[], const int idx)
{
   C1W2_UP_Start_Ctx(g_c1w2_default_ctx, rates, idx);
}

inline void C1W2_UP_OnW2Locked_Ctx(C1W2GateCtx &ctx)
{
   // به‌محض قفل‌شدن W2 (ورود به WAIT_CONFIRM)، قانون c1_w2 برای این سیکل تمام است
   ctx.up_active = false;
}

inline void C1W2_UP_OnW2Locked()
{
   C1W2_UP_OnW2Locked_Ctx(g_c1w2_default_ctx);
}

inline bool C1W2_UP_ShouldAllowAt_Ctx(C1W2GateCtx &ctx,
                                      const MqlRates &rates[],
                                      const int i,
                                      bool &reanchored)
{
   reanchored = false;
   if(!ctx.up_active) return true;        // گِیت خاموش ⇒ اجازهٔ بررسی
   if(i <  ctx.up_idx) return true;       // قبل از کاندید ⇒ بی‌اثر
   if(i == ctx.up_idx) return true;       // خودِ کندلِ کاندید ⇒ مجاز

   // i > کاندید: داخل «پنجرهٔ ممنوعه» هستیم مگر اینکه شکست رخ دهد:
   if(rates[i].high > ctx.up_level)       // شکست با wick یا body (STRICT: >)
   {
      // ابطال کاندید قبلی و ری‌انکر روی همین کندل
      ctx.up_idx   = i;
      ctx.up_level = rates[i].high;
      reanchored   = true;
      return true;                         // از همین کندل، شمارش W2 از نو مجاز است
   }
   // هنوز شکست روی سطح پایش رخ نداده ⇒ ممنوعیت
   return false;
}

inline bool C1W2_UP_ShouldAllowAt(const MqlRates &rates[],
                                  const int i,
                                  bool &reanchored)
{
   return C1W2_UP_ShouldAllowAt_Ctx(g_c1w2_default_ctx, rates, i, reanchored);
}

// =====================================================
//   DOWN: بعد از جفت نزولی  (Mode = DOWN; scan W2-DOWN)
// =====================================================

inline void C1W2_DN_Start_Ctx(C1W2GateCtx &ctx,
                              const MqlRates &rates[],
                              const int idx)
{
   ctx.dn_active = true;
   ctx.dn_idx    = idx;
   ctx.dn_level  = rates[idx].low; // بعدِ جفتِ نزولی: پایشِ Low
}

inline void C1W2_DN_Start(const MqlRates &rates[], const int idx)
{
   C1W2_DN_Start_Ctx(g_c1w2_default_ctx, rates, idx);
}

inline void C1W2_DN_OnW2Locked_Ctx(C1W2GateCtx &ctx)
{
   ctx.dn_active = false;
}

inline void C1W2_DN_OnW2Locked()
{
   C1W2_DN_OnW2Locked_Ctx(g_c1w2_default_ctx);
}

inline bool C1W2_DN_ShouldAllowAt_Ctx(C1W2GateCtx &ctx,
                                      const MqlRates &rates[],
                                      const int i,
                                      bool &reanchored)
{
   reanchored = false;
   if(!ctx.dn_active) return true;
   if(i <  ctx.dn_idx) return true;
   if(i == ctx.dn_idx) return true;

   // i > کاندید: اجازه فقط اگر Low با هر نوع عبور شکسته شود
   if(rates[i].low < ctx.dn_level)        // STRICT: <
   {
      ctx.dn_idx   = i;
      ctx.dn_level = rates[i].low;
      reanchored   = true;
      return true;
   }
   return false;
}

inline bool C1W2_DN_ShouldAllowAt(const MqlRates &rates[],
                                  const int i,
                                  bool &reanchored)
{
   return C1W2_DN_ShouldAllowAt_Ctx(g_c1w2_default_ctx, rates, i, reanchored);
}

// =====================================================
//   Path-B Strict Gate (after HWBB)
//   NOTE: "PB_DN" => Path-B while scanning DOWN (Mode=UP)
//         "PB_UP" => Path-B while scanning UP   (Mode=DOWN)
// =====================================================

// ---- DOWN scan (Mode=UP) ----

inline void C1W2_PB_DN_Enable_Ctx(C1W2GateCtx &ctx)
{
   ctx.pb_dn_active = true;
   ctx.pb_dn_idx    = -1;
   ctx.pb_dn_level  = 0.0;
}

inline void C1W2_PB_DN_Disable_Ctx(C1W2GateCtx &ctx)
{
   ctx.pb_dn_active = false;
   ctx.pb_dn_idx    = -1;
   ctx.pb_dn_level  = 0.0;
}

inline void C1W2_PB_DN_OnW2Locked_Ctx(C1W2GateCtx &ctx)
{
   C1W2_PB_DN_Disable_Ctx(ctx);
}

inline void C1W2_PB_DN_Reanchor_Ctx(C1W2GateCtx &ctx,
                                    const MqlRates &rates[],
                                    const int i)
{
   if(i < 0) return;
   ctx.pb_dn_idx   = i;
   ctx.pb_dn_level = rates[i].low;
}

inline bool C1W2_PB_DN_ShouldAllowAt_Ctx(C1W2GateCtx &ctx,
                                         const MqlRates &rates[],
                                         const int i,
                                         bool &reanchored)
{
   reanchored = false;
   if(!ctx.pb_dn_active) return true;

   if(ctx.pb_dn_idx < 0)
   {
      ctx.pb_dn_idx   = i;
      ctx.pb_dn_level = rates[i].low;
      return true;
   }
   if(i == ctx.pb_dn_idx)
      return true;

   if(rates[i].low < ctx.pb_dn_level || rates[i].close < ctx.pb_dn_level)
   {
      ctx.pb_dn_idx   = i;
      ctx.pb_dn_level = rates[i].low;
      reanchored      = true;
      return true;
   }
   return false;
}

// نسخه‌های بدون ctx برای سازگاری با کد فعلی
inline void C1W2_PB_DN_Enable()      { C1W2_PB_DN_Enable_Ctx(g_c1w2_default_ctx); }
inline void C1W2_PB_DN_Disable()     { C1W2_PB_DN_Disable_Ctx(g_c1w2_default_ctx); }
inline void C1W2_PB_DN_OnW2Locked()  { C1W2_PB_DN_OnW2Locked_Ctx(g_c1w2_default_ctx); }

inline void C1W2_PB_DN_Reanchor(const MqlRates &rates[], const int i)
{
   C1W2_PB_DN_Reanchor_Ctx(g_c1w2_default_ctx, rates, i);
}

inline bool C1W2_PB_DN_ShouldAllowAt(const MqlRates &rates[],
                                     const int i,
                                     bool &reanchored)
{
   return C1W2_PB_DN_ShouldAllowAt_Ctx(g_c1w2_default_ctx, rates, i, reanchored);
}

// ---- UP scan (Mode=DOWN) ----

inline void C1W2_PB_UP_Enable_Ctx(C1W2GateCtx &ctx)
{
   ctx.pb_up_active = true;
   ctx.pb_up_idx    = -1;
   ctx.pb_up_level  = 0.0;
}

inline void C1W2_PB_UP_Disable_Ctx(C1W2GateCtx &ctx)
{
   ctx.pb_up_active = false;
   ctx.pb_up_idx    = -1;
   ctx.pb_up_level  = 0.0;
}

inline void C1W2_PB_UP_OnW2Locked_Ctx(C1W2GateCtx &ctx)
{
   C1W2_PB_UP_Disable_Ctx(ctx);
}

inline void C1W2_PB_UP_Reanchor_Ctx(C1W2GateCtx &ctx,
                                    const MqlRates &rates[],
                                    const int i)
{
   if(i < 0) return;
   ctx.pb_up_idx   = i;
   ctx.pb_up_level = rates[i].high;
}

inline bool C1W2_PB_UP_ShouldAllowAt_Ctx(C1W2GateCtx &ctx,
                                         const MqlRates &rates[],
                                         const int i,
                                         bool &reanchored)
{
   reanchored = false;
   if(!ctx.pb_up_active) return true;

   if(ctx.pb_up_idx < 0)
   {
      ctx.pb_up_idx   = i;
      ctx.pb_up_level = rates[i].high;
      return true;
   }
   if(i == ctx.pb_up_idx)
      return true;

   if(rates[i].high > ctx.pb_up_level || rates[i].close > ctx.pb_up_level)
   {
      ctx.pb_up_idx   = i;
      ctx.pb_up_level = rates[i].high;
      reanchored      = true;
      return true;
   }
   return false;
}

// نسخه‌های بدون ctx
inline void C1W2_PB_UP_Enable()      { C1W2_PB_UP_Enable_Ctx(g_c1w2_default_ctx); }
inline void C1W2_PB_UP_Disable()     { C1W2_PB_UP_Disable_Ctx(g_c1w2_default_ctx); }
inline void C1W2_PB_UP_OnW2Locked()  { C1W2_PB_UP_OnW2Locked_Ctx(g_c1w2_default_ctx); }

inline void C1W2_PB_UP_Reanchor(const MqlRates &rates[], const int i)
{
   C1W2_PB_UP_Reanchor_Ctx(g_c1w2_default_ctx, rates, i);
}

inline bool C1W2_PB_UP_ShouldAllowAt(const MqlRates &rates[],
                                     const int i,
                                     bool &reanchored)
{
   return C1W2_PB_UP_ShouldAllowAt_Ctx(g_c1w2_default_ctx, rates, i, reanchored);
}

#endif // WAVEBOT_C1W2GATE_MQH
