
#ifndef WAVEBOT_C1W2GATE_MQH
#define WAVEBOT_C1W2GATE_MQH

// ????? ???? ????? W2 ?????? ??? ?? ?? ???? ?????
static bool   g_c1w2_up_active = false;
static int    g_c1w2_up_idx    = -1;     // ????? ????? ?????? ????
static double g_c1w2_up_level  = 0.0;    // ??? ???? ????? = High(c1)

// ????? ???? ????? W2 ?????? ??? ?? ?? ???? ?????
static bool   g_c1w2_dn_active = false;
static int    g_c1w2_dn_idx    = -1;     // ????? ????? ?????? ????
static double g_c1w2_dn_level  = 0.0;    // ??? ???? ????? = Low(c1)

// ---------- UP ----------
inline void C1W2_UP_Start(const MqlRates &rates[], const int idx)
{
   g_c1w2_up_active = true;
   g_c1w2_up_idx    = idx;
   g_c1w2_up_level  = rates[idx].high; // ???? ???? ?????: ????? High
}

inline void C1W2_UP_OnW2Locked()
{
   // ?????? ??????? W2 (???? ?? WAIT_CONFIRM)? ????? c1_w2 ???? ??? ???? ???? ???
   g_c1w2_up_active = false;
}
inline bool   C1W2_UP_IsActive(){ return g_c1w2_up_active; }
inline int    C1W2_UP_CurrentIndex(){ return g_c1w2_up_idx; }
inline double C1W2_UP_CurrentLevel(){ return g_c1w2_up_level; }

inline bool C1W2_UP_ShouldAllowAt(const MqlRates &rates[], const int i, bool &reanchored)
{
   reanchored = false;
   if(!g_c1w2_up_active) return true;        // ???? ????? ? ?????? ?????
   if(i <  g_c1w2_up_idx) return true;       // ??? ?? ?????? (?? ??? ?????) ? ??????
   if(i == g_c1w2_up_idx) return true;       // ???? ????? ?????? ? ???? ????

   // i > ??????: ???? «?????? ??????» ????? ??? ????? ???? ?? ???:
   if(rates[i].high > g_c1w2_up_level)       // ???? ?? wick ?? body (STRICT: >)
   {
      // ????? ?????? ???? ? ??????? ??? ???? ????
      g_c1w2_up_idx   = i;
      g_c1w2_up_level = rates[i].high;
      reanchored      = true;
      return true;                           // ?? ???? ????? ????? W2 ?? ?? ???? ???
   }
   // ???? ???? ??? ??? ???? ?? ????? ? ???????
   return false;
}

// ---------- DOWN ----------
inline void C1W2_DN_Start(const MqlRates &rates[], const int idx)
{
   g_c1w2_dn_active = true;
   g_c1w2_dn_idx    = idx;
   g_c1w2_dn_level  = rates[idx].low; // ???? ???? ?????: ????? Low
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

   // i > ??????: ????? ??? ??? Low ?? ?? ??? ???? ????? ???
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
inline void C1W2_PB_DN_Reanchor(const MqlRates &rates[], const int i)
{
   if(i<0) return;
   g_pb_dn_idx   = i;
   g_pb_dn_level = rates[i].low;
}

// ??????? ????? C1 ???? ?? Path-B ??? ??? «????? ?? Low/Close ???????? ?? ???? C1 ????» ?? ???? ????
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

// ???????? ?????? ?? ??????? ???? (???? ???? world ????: ?????/?????)
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

// Export: ??? ????? ???? global?? ?? ???? ???????
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

// Import: ????????? ????? ?????????? ??????? ?? ???????? global
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

// ???? ???? ????? ???? C1–W2 ? Path-B ?? world ????
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
