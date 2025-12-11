// WaveBot/W3ChainGuard.mqh
#ifndef WAVEBOT_W3CHAINGUARD_MQH
#define WAVEBOT_W3CHAINGUARD_MQH

// ------------------------------
// Context for W3 Chain Guard
// ------------------------------
struct W3ChainGuardCtx
{
   // UP (پس از جفت صعودی)
   bool g_w3_up_active;
   bool g_w3_up_rollback_needed;
   int  g_w3_up_bodybreak_idx;
   int  g_w3_up_c1_idx;

   // DOWN (پس از جفت نزولی)
   bool g_w3_dn_active;
   bool g_w3_dn_rollback_needed;
   int  g_w3_dn_bodybreak_idx;
   int  g_w3_dn_c1_idx;
};

// کانتکست پیش‌فرض (دنیای فعلی – ماژور)
static W3ChainGuardCtx g_w3chain_ctx;

// مقداردهی اولیهٔ یک کانتکست
inline void W3Chain_InitCtx(W3ChainGuardCtx &ctx)
{
   ctx.g_w3_up_active          = false;
   ctx.g_w3_up_rollback_needed = false;
   ctx.g_w3_up_bodybreak_idx   = -1;
   ctx.g_w3_up_c1_idx          = -1;

   ctx.g_w3_dn_active          = false;
   ctx.g_w3_dn_rollback_needed = false;
   ctx.g_w3_dn_bodybreak_idx   = -1;
   ctx.g_w3_dn_c1_idx          = -1;
}

// ریست کامل گلوبال (برای شروع اسکن جدید در دنیای پیش‌فرض)
inline void W3Chain_ResetGlobals()
{
   W3Chain_InitCtx(g_w3chain_ctx);
}

// Export/Import برای استفادهٔ ماژور/مینور
inline void W3Chain_ExportCtx(W3ChainGuardCtx &dst)
{
   dst = g_w3chain_ctx;
}

inline void W3Chain_ImportCtx(const W3ChainGuardCtx &src)
{
   g_w3chain_ctx = src;
}

// ==========================
//   UP (پس از جفت صعودی)
// ==========================

// نسخهٔ کانتکست‌محور
inline void W3Chain_UP_Start_Ctx(W3ChainGuardCtx &ctx,
                                 const MqlRates &rates[],
                                 const int bodyBreakIdx,
                                 const int c1_idx)
{
   // (rates[] فعلاً فقط برای سازگاری امضا است و استفاده نمی‌شود)
   ctx.g_w3_up_active          = true;
   ctx.g_w3_up_rollback_needed = false;
   ctx.g_w3_up_bodybreak_idx   = bodyBreakIdx;
   ctx.g_w3_up_c1_idx          = c1_idx;
}

inline void W3Chain_UP_OnC1Invalidated_Ctx(W3ChainGuardCtx &ctx)
{
   if(ctx.g_w3_up_active)
      ctx.g_w3_up_rollback_needed = true;
}

inline bool W3Chain_UP_ShouldRollback_Ctx(W3ChainGuardCtx &ctx,
                                          int &rewind_to_idx)
{
   if(ctx.g_w3_up_active && ctx.g_w3_up_rollback_needed)
   {
      rewind_to_idx = ctx.g_w3_up_bodybreak_idx;
      return true;
   }
   return false;
}

inline void W3Chain_UP_OnW3Completed_Ctx(W3ChainGuardCtx &ctx)
{
   ctx.g_w3_up_active          = false;
   ctx.g_w3_up_rollback_needed = false;
   ctx.g_w3_up_bodybreak_idx   = -1;
   ctx.g_w3_up_c1_idx          = -1;
}

inline void W3Chain_UP_ClearAfterRollback_Ctx(W3ChainGuardCtx &ctx)
{
   ctx.g_w3_up_active          = false;
   ctx.g_w3_up_rollback_needed = false;
   ctx.g_w3_up_bodybreak_idx   = -1;
   ctx.g_w3_up_c1_idx          = -1;
}

// نسخه‌های بدون ctx (سازگار با کد فعلی – روی کانتکست پیش‌فرض)

inline void W3Chain_UP_Start(const MqlRates &rates[],
                             const int bodyBreakIdx,
                             const int c1_idx)
{
   W3Chain_UP_Start_Ctx(g_w3chain_ctx, rates, bodyBreakIdx, c1_idx);
}

inline void W3Chain_UP_OnC1Invalidated()
{
   W3Chain_UP_OnC1Invalidated_Ctx(g_w3chain_ctx);
}

inline bool W3Chain_UP_ShouldRollback(int &rewind_to_idx)
{
   return W3Chain_UP_ShouldRollback_Ctx(g_w3chain_ctx, rewind_to_idx);
}

inline void W3Chain_UP_OnW3Completed()
{
   W3Chain_UP_OnW3Completed_Ctx(g_w3chain_ctx);
}

inline void W3Chain_UP_ClearAfterRollback()
{
   W3Chain_UP_ClearAfterRollback_Ctx(g_w3chain_ctx);
}

// ==========================
//   DOWN (پس از جفت نزولی)
// ==========================

inline void W3Chain_DN_Start_Ctx(W3ChainGuardCtx &ctx,
                                 const MqlRates &rates[],
                                 const int bodyBreakIdx,
                                 const int c1_idx)
{
   ctx.g_w3_dn_active          = true;
   ctx.g_w3_dn_rollback_needed = false;
   ctx.g_w3_dn_bodybreak_idx   = bodyBreakIdx;
   ctx.g_w3_dn_c1_idx          = c1_idx;
}

inline void W3Chain_DN_OnC1Invalidated_Ctx(W3ChainGuardCtx &ctx)
{
   if(ctx.g_w3_dn_active)
      ctx.g_w3_dn_rollback_needed = true;
}

inline bool W3Chain_DN_ShouldRollback_Ctx(W3ChainGuardCtx &ctx,
                                          int &rewind_to_idx)
{
   if(ctx.g_w3_dn_active && ctx.g_w3_dn_rollback_needed)
   {
      rewind_to_idx = ctx.g_w3_dn_bodybreak_idx;
      return true;
   }
   return false;
}

inline void W3Chain_DN_OnW3Completed_Ctx(W3ChainGuardCtx &ctx)
{
   ctx.g_w3_dn_active          = false;
   ctx.g_w3_dn_rollback_needed = false;
   ctx.g_w3_dn_bodybreak_idx   = -1;
   ctx.g_w3_dn_c1_idx          = -1;
}

inline void W3Chain_DN_ClearAfterRollback_Ctx(W3ChainGuardCtx &ctx)
{
   ctx.g_w3_dn_active          = false;
   ctx.g_w3_dn_rollback_needed = false;
   ctx.g_w3_dn_bodybreak_idx   = -1;
   ctx.g_w3_dn_c1_idx          = -1;
}

// نسخه‌های بدون ctx (سازگار با کد فعلی – روی کانتکست پیش‌فرض)

inline void W3Chain_DN_Start(const MqlRates &rates[],
                             const int bodyBreakIdx,
                             const int c1_idx)
{
   W3Chain_DN_Start_Ctx(g_w3chain_ctx, rates, bodyBreakIdx, c1_idx);
}

inline void W3Chain_DN_OnC1Invalidated()
{
   W3Chain_DN_OnC1Invalidated_Ctx(g_w3chain_ctx);
}

inline bool W3Chain_DN_ShouldRollback(int &rewind_to_idx)
{
   return W3Chain_DN_ShouldRollback_Ctx(g_w3chain_ctx, rewind_to_idx);
}

inline void W3Chain_DN_OnW3Completed()
{
   W3Chain_DN_OnW3Completed_Ctx(g_w3chain_ctx);
}

inline void W3Chain_DN_ClearAfterRollback()
{
   W3Chain_DN_ClearAfterRollback_Ctx(g_w3chain_ctx);
}

#endif // WAVEBOT_W3CHAINGUARD_MQH
