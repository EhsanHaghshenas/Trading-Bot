#ifndef WAVEBOT_SWGATE_MQH
#define WAVEBOT_SWGATE_MQH

// ------------------------------
// Context for SWGate (UP / DOWN)
// ------------------------------
struct SWGateCtx
{
   // UP cycle
   bool     up_cycle_open;
   datetime up_w2lock_time;

   // DOWN cycle
   bool     dn_cycle_open;
   datetime dn_w2lock_time;
};

// کانتکست پیش‌فرض (دنیای فعلی – ماژور)
static SWGateCtx g_swg_ctx;

// مقداردهی اولیهٔ یک کانتکست
inline void SWGate_InitCtx(SWGateCtx &ctx)
{
   ctx.up_cycle_open  = false;
   ctx.up_w2lock_time = 0;

   ctx.dn_cycle_open  = false;
   ctx.dn_w2lock_time = 0;
}

// ریست کامل گلوبال (برای شروع اسکن جدید در دنیای پیش‌فرض)
inline void SWGate_ResetGlobals()
{
   SWGate_InitCtx(g_swg_ctx);
}

// Export/Import برای استفادهٔ ماژور/مینور
inline void SWGate_ExportCtx(SWGateCtx &dst)
{
   dst = g_swg_ctx;
}

inline void SWGate_ImportCtx(const SWGateCtx &src)
{
   g_swg_ctx = src;
}

// ===================== UP =====================

// نسخهٔ کانتکست‌محور
inline void SWGate_UP_OnW2Locked_Ctx(SWGateCtx &ctx,
                                     const MqlRates &rates[],
                                     const int c1_idx)
{
   ctx.up_cycle_open  = true;
   ctx.up_w2lock_time = (c1_idx >= 0 ? rates[c1_idx].time : 0);
}

inline void SWGate_UP_OnPairFinalized_Ctx(SWGateCtx &ctx)
{
   ctx.up_cycle_open  = false;
   ctx.up_w2lock_time = 0;
}

inline bool SWGate_UP_IsOpen_Ctx(const SWGateCtx &ctx)
{
   return ctx.up_cycle_open;
}

inline datetime SWGate_UP_W2Time_Ctx(const SWGateCtx &ctx)
{
   return ctx.up_w2lock_time;
}

// نسخه‌های بدون ctx (سازگار با کد فعلی – روی کانتکست پیش‌فرض)

inline void SWGate_UP_OnW2Locked(const MqlRates &rates[],
                                 const int c1_idx)
{
   SWGate_UP_OnW2Locked_Ctx(g_swg_ctx, rates, c1_idx);
}

inline void SWGate_UP_OnPairFinalized()
{
   SWGate_UP_OnPairFinalized_Ctx(g_swg_ctx);
}

inline bool SWGate_UP_IsOpen()
{
   return SWGate_UP_IsOpen_Ctx(g_swg_ctx);
}

inline datetime SWGate_UP_W2Time()
{
   return SWGate_UP_W2Time_Ctx(g_swg_ctx);
}

// ===================== DOWN =====================

inline void SWGate_DN_OnW2Locked_Ctx(SWGateCtx &ctx,
                                     const MqlRates &rates[],
                                     const int c1_idx)
{
   ctx.dn_cycle_open  = true;
   ctx.dn_w2lock_time = (c1_idx >= 0 ? rates[c1_idx].time : 0);
}

inline void SWGate_DN_OnPairFinalized_Ctx(SWGateCtx &ctx)
{
   ctx.dn_cycle_open  = false;
   ctx.dn_w2lock_time = 0;
}

inline bool SWGate_DN_IsOpen_Ctx(const SWGateCtx &ctx)
{
   return ctx.dn_cycle_open;
}

inline datetime SWGate_DN_W2Time_Ctx(const SWGateCtx &ctx)
{
   return ctx.dn_w2lock_time;
}

// نسخه‌های بدون ctx (سازگار با کد فعلی – روی کانتکست پیش‌فرض)

inline void SWGate_DN_OnW2Locked(const MqlRates &rates[],
                                 const int c1_idx)
{
   SWGate_DN_OnW2Locked_Ctx(g_swg_ctx, rates, c1_idx);
}

inline void SWGate_DN_OnPairFinalized()
{
   SWGate_DN_OnPairFinalized_Ctx(g_swg_ctx);
}

inline bool SWGate_DN_IsOpen()
{
   return SWGate_DN_IsOpen_Ctx(g_swg_ctx);
}

inline datetime SWGate_DN_W2Time()
{
   return SWGate_DN_W2Time_Ctx(g_swg_ctx);
}

#endif // WAVEBOT_SWGATE_MQH
