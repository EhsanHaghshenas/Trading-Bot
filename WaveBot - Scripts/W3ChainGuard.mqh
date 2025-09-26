// WaveBot/W3ChainGuard.mqh
#ifndef WAVEBOT_W3CHAINGUARD_MQH
#define WAVEBOT_W3CHAINGUARD_MQH

// ---------- UP (پس از جفت صعودی) ----------
static bool g_w3_up_active          = false;  // W3 در حال شمارش (بعد از Body-Break)
static bool g_w3_up_rollback_needed = false;  // درخواست بازگردانی فعال
static int  g_w3_up_bodybreak_idx   = -1;     // اندیس کندلی که W2 را با بدنه شکست
static int  g_w3_up_c1_idx          = -1;     // اندیس c1_w3 جاری (صرفاً برای لاگ/دیباگ)

inline void W3Chain_UP_Start(const MqlRates &rates[], const int bodyBreakIdx, const int c1_idx)
{
   g_w3_up_active          = true;
   g_w3_up_rollback_needed = false;
   g_w3_up_bodybreak_idx   = bodyBreakIdx;
   g_w3_up_c1_idx          = c1_idx;
}

inline void W3Chain_UP_OnC1Invalidated()
{
   if(g_w3_up_active)      // فقط اگر W3 واقعاً در جریان است
      g_w3_up_rollback_needed = true;
}

inline bool W3Chain_UP_ShouldRollback(int &rewind_to_idx)
{
   if(g_w3_up_active && g_w3_up_rollback_needed)
   {
      rewind_to_idx = g_w3_up_bodybreak_idx;
      return true;
   }
   return false;
}

inline void W3Chain_UP_OnW3Completed()
{
   // تکمیل موفق W3 ⇒ زنجیره بسته شود
   g_w3_up_active          = false;
   g_w3_up_rollback_needed = false;
   g_w3_up_bodybreak_idx   = -1;
   g_w3_up_c1_idx          = -1;
}

inline void W3Chain_UP_ClearAfterRollback()
{
   // پس از اجرای بازگردانی در حلقه‌ی اصلی، گارد را پاک کن
   g_w3_up_active          = false;
   g_w3_up_rollback_needed = false;
   g_w3_up_bodybreak_idx   = -1;
   g_w3_up_c1_idx          = -1;
}

// ---------- DOWN (پس از جفت نزولی) ----------
static bool g_w3_dn_active          = false;
static bool g_w3_dn_rollback_needed = false;
static int  g_w3_dn_bodybreak_idx   = -1;
static int  g_w3_dn_c1_idx          = -1;

inline void W3Chain_DN_Start(const MqlRates &rates[], const int bodyBreakIdx, const int c1_idx)
{
   g_w3_dn_active          = true;
   g_w3_dn_rollback_needed = false;
   g_w3_dn_bodybreak_idx   = bodyBreakIdx;
   g_w3_dn_c1_idx          = c1_idx;
}

inline void W3Chain_DN_OnC1Invalidated()
{
   if(g_w3_dn_active)
      g_w3_dn_rollback_needed = true;
}

inline bool W3Chain_DN_ShouldRollback(int &rewind_to_idx)
{
   if(g_w3_dn_active && g_w3_dn_rollback_needed)
   {
      rewind_to_idx = g_w3_dn_bodybreak_idx;
      return true;
   }
   return false;
}

inline void W3Chain_DN_OnW3Completed()
{
   g_w3_dn_active          = false;
   g_w3_dn_rollback_needed = false;
   g_w3_dn_bodybreak_idx   = -1;
   g_w3_dn_c1_idx          = -1;
}

inline void W3Chain_DN_ClearAfterRollback()
{
   g_w3_dn_active          = false;
   g_w3_dn_rollback_needed = false;
   g_w3_dn_bodybreak_idx   = -1;
   g_w3_dn_c1_idx          = -1;
}

#endif // WAVEBOT_W3CHAINGUARD_MQH
