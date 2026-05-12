#ifndef WAVEBOT_RACECOORDINATOR_MQH
#define WAVEBOT_RACECOORDINATOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Utils.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>          // UP W2
#include <WaveBot/Wave3.mqh>          // UP W3
#include <WaveBot/Wave2_Down.mqh>     // DOWN W2
#include <WaveBot/Wave3_Down.mqh>     // DOWN W3
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/C1W2Gate.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/ShadowBreaker.mqh>
#include <WaveBot/SR_Gate.mqh>     // NEW: SR direction gating after MTC
#include <WaveBot/Hunter.mqh>      // for SW_UP_ClearSeed()
#include <WaveBot/Hunter_Down.mqh> // for SW_DOWN_ClearSeed()
#include <WaveBot/FSMS_SW.mqh>   // for FSMS_SW_DisarmAll()

inline ENUM_TIMEFRAMES __Race_RuntimeTF()
{
   ENUM_TIMEFRAMES tf = InpTF;
   ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();

   if(chart_tf == PERIOD_M15)     tf = PERIOD_M15;
   else if(chart_tf == PERIOD_M1) tf = PERIOD_M1;

   return tf;
}


//------------------------------ ????? ??? ?????? ------------------------------
static bool      g_race_locked       = false;
static Direction g_race_mode         = DIR_UP;   // Mode ????? ???? ??????
static int       g_race_hwbb_idx     = -1;       // ?????? ???? HWBB
static datetime  g_race_hwbb_time    = 0;        // ???? HWBB
static datetime  g_world_hwbb_time   = 0;        // ???? ????? HWBB ?? ??? world (???? ??????? ?? ?? HWBB)
static string    g_race_winner       = "";       // "A" ?? "B"
static datetime  g_race_winner_time  = 0;
static int       g_race_counter      = 0;        // ???? ????????? ???????
// ????? ???? ???? ????? ??? ?? MTC
static double   g_race_ref_mtc_up   = 0.0;  // mtc_up ? Low? C1? Hunter(DOWN)
static double   g_race_ref_mtc_down = 0.0;  // mtc_down ? High? C1? Hunter(UP)

// -----[ Reference History (draw immediately when created) ]-----
static int g_ref_hist_up_counter   = 0;
static int g_ref_hist_down_counter = 0;

// --- Active reference tracking (the "currently active ref" is the one from the latest MTC) ---
static double   g_active_ref_up        = 0.0;
static datetime g_active_ref_up_time   = 0;
static double   g_active_ref_down      = 0.0;
static datetime g_active_ref_down_time = 0;

inline datetime Race_ActiveRef_Up_Time()   { return g_active_ref_up_time; }
inline datetime Race_ActiveRef_Down_Time() { return g_active_ref_down_time; }
// setters: called when an MTC_* is finalized (ref becomes the new active one)
inline void Race_ActivateRef_Up(const double price, const datetime t)
{
   if(price <= 0.0) return;
   g_active_ref_up      = price;
   g_active_ref_up_time = t;
}
inline void Race_ActivateRef_Down(const double price, const datetime t)
{
   if(price <= 0.0) return;
   g_active_ref_down      = price;
   g_active_ref_down_time = t;
}

// which ref is currently active? (latest timestamp wins)
inline bool Race_RefUp_IsActive()   { return (g_active_ref_up_time   > g_active_ref_down_time) && (g_active_ref_up   > 0.0); }
inline bool Race_RefDown_IsActive() { return (g_active_ref_down_time > g_active_ref_up_time)   && (g_active_ref_down > 0.0); }

// getters for checks
inline double Race_ActiveRef_Up()   { return g_active_ref_up; }
inline double Race_ActiveRef_Down() { return g_active_ref_down; }

inline bool Race_ShouldDrawRefVisuals()
{
   return false;
}

inline void Race_DeleteRefVisuals_AllScans()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "") continue;

      bool is_ref =
         (StringFind(on, "MTC_UP_REF_")   >= 0) ||
         (StringFind(on, "MTC_DN_REF_")   >= 0) ||
         (StringFind(on, "REF_UP_HIST_")  >= 0) ||
         (StringFind(on, "REF_DN_HIST_")  >= 0) ||
         (StringFind(on, "REF_UP_HIST_T_")>= 0) ||
         (StringFind(on, "REF_DN_HIST_T_")>= 0);

      if(is_ref)
         ObjectDelete(0, on);
   }
}

// ??? ???? ????????? ???? ???? MTC_UP (???? ?? ??? DOWN ??????)
inline void Race_DrawRefHistory_Up(const double price, const datetime t)
{
   if(price <= 0.0) return;

   if(!Race_ShouldDrawRefVisuals())
      return;

   ++g_ref_hist_up_counter;

   const string base = "REF_UP_HIST_" + IntegerToString(g_ref_hist_up_counter);
   const string name = __ScanPrefix() + base;

   if(ObjectFind(0, name) == -1)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);

   if(InpDrawMarkers && t > 0)
      MarkV("REF_UP_HIST_T_" + IntegerToString(g_ref_hist_up_counter), t, clrWhite);
}


// ??? ???? ????????? ???? ???? MTC_DOWN (???? ?? ??? UP ??????)
inline void Race_DrawRefHistory_Down(const double price, const datetime t)
{
   if(price <= 0.0) return;

   if(!Race_ShouldDrawRefVisuals())
      return;

   ++g_ref_hist_down_counter;

   const string base = "REF_DN_HIST_" + IntegerToString(g_ref_hist_down_counter);
   const string name = __ScanPrefix() + base;

   if(ObjectFind(0, name) == -1)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);

   if(InpDrawMarkers && t > 0)
      MarkV("REF_DN_HIST_T_" + IntegerToString(g_ref_hist_down_counter), t, clrWhite);
}

// ??????????? (?? Hunter_BodyBreak ???????? ???????)
inline void Race_SetRefLevelForMTC_Up(const double price)   { g_race_ref_mtc_up   = price; }
inline void Race_SetRefLevelForMTC_Down(const double price) { g_race_ref_mtc_down = price; }

enum RState { R_IDLE=0, R_SEARCH_W2=1, R_WAIT_CONFIRM=2 };

// ????? ????? ???? B ???? ?? ????
struct RacePathBState
{
   bool     init;
   int      state;            // R_SEARCH_W2 / R_WAIT_CONFIRM
   int      idx;

   // W2 ????
   int      c1,c2,c3,c4,cend;

   // ????? W3
   bool     have_w3;
   int      w3_c1, k2,k3,k4, w3_end;

   // ?????? C1 ???? ???? ??????
   int      w3_cand;
   double   w3_cand_low;      // ???? ???? UP
   double   w3_cand_high;     // ???? ???? DOWN

   // ?????? wick/body-break
   bool     wickActive;
   int      firstWickIdx, wickBreakIdx;
   double   bodyBreakLevel;
   bool     breakAchieved;
   int      bodyBreakIdx;

   // --- MTC candidate tracking (?? HWBB)
   int      mtc_c1_cand;
   double   mtc_c1_level;

   // --- NEW: Guard ?? ?? body-break: ??? C1_W3
   bool     postBreak_c1_lock;   // ??? C1_W3 ??? ????
   int      postBreak_c1_ref;    // ???? C1_W3 ?? ?? body-break
};
// =======================[ RaceContext: snapshot ???? ????? ?????? ]=======================
//
// ??? struct ???? state ????? RaceCoordinator ?? ?? ??? ??? ?????? ?? ???????
// ?? ?? ???? ????? ?????/????? ??????? ??? ????? ? ?? ???? ???? ??? ????/???? ????.
struct RaceContext
{
   bool      locked;             // ????? g_race_locked
   Direction mode;               // ????? g_race_mode
   int       hwbb_idx;           // ????? g_race_hwbb_idx
   datetime  hwbb_time;          // ????? g_race_hwbb_time
   datetime  world_hwbb_time;    // ???? HWBB ?? ??? world (????? g_world_hwbb_time)
   string    winner;             // ????? g_race_winner
   datetime  winner_time;        // ????? g_race_winner_time
   
   int       race_counter;          // g_race_counter
   int       ref_hist_up_counter;   // g_ref_hist_up_counter
   int       ref_hist_down_counter; // g_ref_hist_down_counter

   // ?????? ???? ???? MTC (LOW/HIGH C1 Hunter ?? ?? ???)
   double    ref_mtc_up;         // ????? g_race_ref_mtc_up
   double    ref_mtc_down;       // ????? g_race_ref_mtc_down

   // Active ref (????? ???? MTC ?? ???? ???)
   double    active_ref_up;         // ????? g_active_ref_up
   datetime  active_ref_up_time;    // ????? g_active_ref_up_time
   double    active_ref_down;       // ????? g_active_ref_down
   datetime  active_ref_down_time;  // ????? g_active_ref_down_time

   // ????? ????? Path-B ???? Mode=UP ? Mode=DOWN
   RacePathBState pb_up;         // snapshot ?? g_pb_up
   RacePathBState pb_down;       // snapshot ?? g_pb_down
};

static RacePathBState g_pb_up;    // ???? Mode=UP ??? (???? B = ???? DOWN)
static RacePathBState g_pb_down;  // ???? Mode=DOWN ??? (???? B = ???? UP)

inline void Race_ResetPathB(RacePathBState &S)
{
   S.init=false; S.state=R_IDLE; S.idx=-1;
   S.c1=S.c2=S.c3=S.c4=S.cend=-1;
   S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
   S.w3_cand=-1; S.w3_cand_low=DBL_MAX; S.w3_cand_high=-DBL_MAX;
   S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
   S.bodyBreakLevel=0.0; S.breakAchieved=false; S.bodyBreakIdx=-1;
   S.mtc_c1_cand = -1;
   S.mtc_c1_level = 0.0;
   S.postBreak_c1_lock = false;
   S.postBreak_c1_ref  = -1;
}

inline void Race_InternalClearAll()
{
   g_race_locked=false;
   g_race_mode=DIR_UP;
   g_race_hwbb_idx=-1; g_race_hwbb_time=0;
   g_race_winner=""; g_race_winner_time=0;
   Race_ResetPathB(g_pb_up);
   Race_ResetPathB(g_pb_down);
   g_race_ref_mtc_up   = 0.0;
   g_race_ref_mtc_down = 0.0;
}
// ---------------------- Helper??? ??????? ?????? ----------------------

// ???????? ?????? ?? ??????? ???? (???? ???? world ????: ?????/?????)
inline void Race_ContextReset(RaceContext &ctx)
{
   ctx.locked      = false;
   ctx.mode        = DIR_UP;
   ctx.hwbb_idx    = -1;
   ctx.hwbb_time   = 0;
   ctx.world_hwbb_time = 0;
   ctx.winner      = "";
   ctx.winner_time = 0;

   ctx.race_counter          = 0;
   ctx.ref_hist_up_counter   = 0;
   ctx.ref_hist_down_counter = 0;

   ctx.ref_mtc_up   = 0.0;
   ctx.ref_mtc_down = 0.0;

   ctx.active_ref_up        = 0.0;
   ctx.active_ref_up_time   = 0;
   ctx.active_ref_down      = 0.0;
   ctx.active_ref_down_time = 0;

   Race_ResetPathB(ctx.pb_up);
   Race_ResetPathB(ctx.pb_down);
}

// ???????? state ???? global ?? ???? ?? ??????? (Export)
inline void Race_ContextExport(RaceContext &ctx)
{
   ctx.locked      = g_race_locked;
   ctx.mode        = g_race_mode;
   ctx.hwbb_idx    = g_race_hwbb_idx;
   ctx.hwbb_time   = g_race_hwbb_time;
   ctx.world_hwbb_time = g_world_hwbb_time;
   ctx.winner      = g_race_winner;
   ctx.winner_time = g_race_winner_time;
   
   ctx.race_counter          = g_race_counter;
   ctx.ref_hist_up_counter   = g_ref_hist_up_counter;
   ctx.ref_hist_down_counter = g_ref_hist_down_counter;

   ctx.ref_mtc_up   = g_race_ref_mtc_up;
   ctx.ref_mtc_down = g_race_ref_mtc_down;

   ctx.active_ref_up        = g_active_ref_up;
   ctx.active_ref_up_time   = g_active_ref_up_time;
   ctx.active_ref_down      = g_active_ref_down;
   ctx.active_ref_down_time = g_active_ref_down_time;

   ctx.pb_up   = g_pb_up;
   ctx.pb_down = g_pb_down;
}

// ????????? ?? snapshot ????????? ?? ???? global?? (Import)
inline void Race_ContextImport(const RaceContext &ctx)
{
   g_race_locked      = ctx.locked;
   g_race_mode        = ctx.mode;
   g_race_hwbb_idx    = ctx.hwbb_idx;
   g_race_hwbb_time   = ctx.hwbb_time;
   g_world_hwbb_time  = ctx.world_hwbb_time;
   g_race_winner      = ctx.winner;
   g_race_winner_time = ctx.winner_time;
   
   g_race_counter          = ctx.race_counter;
   g_ref_hist_up_counter   = ctx.ref_hist_up_counter;
   g_ref_hist_down_counter = ctx.ref_hist_down_counter;

   g_race_ref_mtc_up   = ctx.ref_mtc_up;
   g_race_ref_mtc_down = ctx.ref_mtc_down;

   g_active_ref_up        = ctx.active_ref_up;
   g_active_ref_up_time   = ctx.active_ref_up_time;
   g_active_ref_down      = ctx.active_ref_down;
   g_active_ref_down_time = ctx.active_ref_down_time;

   g_pb_up   = ctx.pb_up;
   g_pb_down = ctx.pb_down;
}

inline bool Race_IsLocked() { return g_race_locked; }
inline bool     Race_WorldHWBBSeen()  { return (g_world_hwbb_time > 0); }
inline datetime Race_WorldHWBBTime()  { return g_world_hwbb_time; }
// FSMS is an early (pre-HWBB) detector; in MIN world we stop it after the first HWBB is seen
inline bool Race_ShouldAllowFSMS(){ return !g_race_locked; }
// --------------------[ API execution / abort handoff ]--------------------
// این state فقط runtime است و جزو snapshot world نیست.
// هدف: وقتی MTC در میانه‌ی یک API scan رخ می‌دهد و همان‌جا nested-scan جدید
// برای روند جدید launch می‌شود، invocation فعلیِ API باید بعد از بازگشت
// فوراً terminate شود تا دیگر منطق روند قبلی ادامه پیدا نکند.
#define RACE_API_EXEC_MAX 64

static int g_race_api_exec_stack[RACE_API_EXEC_MAX];
static int g_race_api_exec_size   = 0;
static int g_race_api_exec_seq    = 0;

static int g_race_api_abort_tokens[RACE_API_EXEC_MAX];
static int g_race_api_abort_count = 0;

inline int __Race_CurrentAPIToken()
{
   if(g_race_api_exec_size <= 0) return 0;
   return g_race_api_exec_stack[g_race_api_exec_size - 1];
}

inline void __Race_RemoveAbortToken(const int token)
{
   if(token <= 0) return;

   for(int i=0; i<g_race_api_abort_count; ++i)
   {
      if(g_race_api_abort_tokens[i] != token) continue;

      for(int j=i+1; j<g_race_api_abort_count; ++j)
         g_race_api_abort_tokens[j-1] = g_race_api_abort_tokens[j];

      --g_race_api_abort_count;
      break;
   }
}

inline void __Race_RemoveExecToken(const int token)
{
   if(token <= 0) return;
   if(g_race_api_exec_size <= 0) return;

   for(int i=g_race_api_exec_size-1; i>=0; --i)
   {
      if(g_race_api_exec_stack[i] != token) continue;

      for(int j=i+1; j<g_race_api_exec_size; ++j)
         g_race_api_exec_stack[j-1] = g_race_api_exec_stack[j];

      --g_race_api_exec_size;
      break;
   }
}

inline int Race_EnterAPIScan()
{
   ++g_race_api_exec_seq;
   const int token = g_race_api_exec_seq;

   if(g_race_api_exec_size < RACE_API_EXEC_MAX)
      g_race_api_exec_stack[g_race_api_exec_size++] = token;

   return token;
}

inline void Race_LeaveAPIScan(const int token)
{
   __Race_RemoveAbortToken(token);
   __Race_RemoveExecToken(token);
}

inline void Race_RequestAbortCurrentAPIScan()
{
   const int token = __Race_CurrentAPIToken();
   if(token <= 0) return;

   for(int i=0; i<g_race_api_abort_count; ++i)
      if(g_race_api_abort_tokens[i] == token)
         return;

   if(g_race_api_abort_count >= RACE_API_EXEC_MAX)
      return;

   g_race_api_abort_tokens[g_race_api_abort_count++] = token;
}

inline bool Race_ShouldAbortAPIScan(const int token)
{
   if(token <= 0) return false;

   for(int i=0; i<g_race_api_abort_count; ++i)
      if(g_race_api_abort_tokens[i] == token)
         return true;

   return false;
}

inline bool Race_ConsumeAbortAPIScan(const int token)
{
   if(!Race_ShouldAbortAPIScan(token))
      return false;

   __Race_RemoveAbortToken(token);
   return true;
}

// --------------------[ Nested Scan Helpers (World-Aware) ]--------------------
// ??? helper?? ???? ??????? ???????? ?? ?? ?? (?? ?? ???? RaceCoordinator ???????? ???????)
// ?? ????? MIN? namespace/scan_id ?? ?? MAJ ????? ????? ? ?????? ?? ??????? ???? ????
// ????? ????? (??? ??????? ?? TimeCurrent ?? ??????/???????? ????????).
inline bool __Race_IsMajorWorld()
{
   const string ns = Markers_GetNamespace();
   return (ns == "" || ns == "MAJ");
}

inline datetime __Race_ScanToTime(const MqlRates &rates[], const int n)
{
   if(n > 0) return rates[n-1].time;
   return TimeCurrent();
}

// --- NEW: fail-safe unlock on new ext LQ (called by Hunter side)
// ??? ?????? ??? ???? ? ?? ??? ?????? ??? ???? ext lq ????? ?? ???? ??? ?? HWBB ????? ??? ?? ??? ??.
inline void Race_TryUnlockOnNewLQ_Notify(const Direction lq_side, const datetime lq_time)
{
   if(!g_race_locked) return;
   if(lq_time <= 0 || lq_time < g_race_hwbb_time) return;

   // ??? ?????? ?? Mode=UP ???? ???? ext lq ?????? ??? DOWN ??????? ????? ???? B ??? (? ??????)
   if(g_race_mode == DIR_UP  && lq_side == DIR_DOWN){ Race_InternalClearAll(); return; }
   if(g_race_mode == DIR_DOWN&& lq_side == DIR_UP  ){ Race_InternalClearAll(); return; }
}

// ???????? ????? ??????
inline void Race_MarkStart(const Direction mode, const datetime t)
{
   ++g_race_counter;
   const string tag = IntegerToString(g_race_counter);
   MarkV( (mode==DIR_UP ? "RACE_START_HWBB_U_" : "RACE_START_HWBB_D_") + tag, t, clrYellow );
}

inline void Race_MarkWin_A(const Direction mode, const datetime t)
{
   const string tag = IntegerToString(g_race_counter);
   MarkV( (mode==DIR_UP ? "RACE_A_SW_WIN_U_" : "RACE_A_SW_WIN_D_") + tag, t, (mode==DIR_UP?clrAqua:clrDarkOrange) );
}

inline void Race_MarkWin_B(const Direction mode, const datetime t)
{
   const string tag = IntegerToString(g_race_counter);
   MarkV( (mode==DIR_UP ? "MTC_D_" : "MTC_U_") + tag, t, (mode==DIR_UP?clrFireBrick:clrLime) );
}

inline void __Race_ClearRegimeArtifacts()
{
   // هیچ seed یا guard قدیمی نباید بعد از رجیم‌چنج در ادامه‌ی موتور اثر بگذارد.
   SW_UP_ClearSeed();
   SW_DOWN_ClearSeed();
   SWGate_ResetGlobals();
   FSMS_SW_DisarmAll();
}

//--------------------------- ???? ?????? ?? HWBB ------------------------------
inline void Race_Start_UP(const MqlRates &rates[], const int n, const int hwbb_idx)
{
   if(g_race_locked) return; // ?????
   g_race_locked     = true;
   g_race_mode       = DIR_UP;
   g_race_hwbb_idx   = hwbb_idx;
   g_race_hwbb_time  = (hwbb_idx>=0 && hwbb_idx<n ? rates[hwbb_idx].time : TimeCurrent());

   // remember: HWBB happened in this world-run (do NOT clear inside Race_InternalClearAll)
   if(g_world_hwbb_time <= 0 || g_race_hwbb_time > g_world_hwbb_time)
      g_world_hwbb_time = g_race_hwbb_time;

   g_race_winner     = ""; 
   g_race_winner_time= 0;

   Race_ResetPathB(g_pb_up);
   g_pb_up.init=true;
   g_pb_up.state=R_SEARCH_W2;
   g_pb_up.idx = MathMax(0, hwbb_idx);

   g_pb_up.mtc_c1_cand  = -1;
   g_pb_up.mtc_c1_level = 0.0;

   Race_MarkStart(DIR_UP, g_race_hwbb_time);

   // Enable strict C1-W2 gate for Path-B (scanning DOWN)
   C1W2_PB_DN_Enable();
}

inline void Race_Start_DOWN(const MqlRates &rates[], const int n, const int hwbb_idx)
{
   if(g_race_locked) return;
   g_race_locked     = true;
   g_race_mode       = DIR_DOWN;
   g_race_hwbb_idx   = hwbb_idx;
   g_race_hwbb_time  = (hwbb_idx>=0 && hwbb_idx<n ? rates[hwbb_idx].time : TimeCurrent());

   // remember: HWBB happened in this world-run
   if(g_world_hwbb_time <= 0 || g_race_hwbb_time > g_world_hwbb_time)
      g_world_hwbb_time = g_race_hwbb_time;

   g_race_winner     = "";
   g_race_winner_time= 0;

   Race_ResetPathB(g_pb_down);
   g_pb_down.init=true;
   g_pb_down.state=R_SEARCH_W2;
   g_pb_down.idx = MathMax(0, hwbb_idx);

   g_pb_down.mtc_c1_cand  = -1;
   g_pb_down.mtc_c1_level = 0.0;

   Race_MarkStart(DIR_DOWN, g_race_hwbb_time);

   // Enable strict C1-W2 gate for Path-B (scanning UP)
   C1W2_PB_UP_Enable();
}


//--------------------------- ????? ???? A (SW ??????) -------------------------
inline void Race_OnSWConfirmed_UP(const MqlRates &rates[], const int n, const int w3_c1, const int bodyBreakIdx)
{
   if(!g_race_locked || g_race_mode!=DIR_UP) return;
   if(bodyBreakIdx<0 || bodyBreakIdx>=n) return;
   const datetime t = rates[bodyBreakIdx].time;
   if(t < g_race_hwbb_time) return; // ???? ??? ?? HWBB

   // ??? ???? ???????? ????? ???? ?? ??? ????? ???:
   if(g_race_winner=="" || t < g_race_winner_time)
   {
      g_race_winner="A"; g_race_winner_time=t;
      Race_MarkWin_A(DIR_UP, t);
      Race_InternalClearAll();
   }
}

inline void Race_OnSWConfirmed_DOWN(const MqlRates &rates[], const int n, const int w3_c1, const int bodyBreakIdx)
{
   if(!g_race_locked || g_race_mode!=DIR_DOWN) return;
   if(bodyBreakIdx<0 || bodyBreakIdx>=n) return;
   const datetime t = rates[bodyBreakIdx].time;
   if(t < g_race_hwbb_time) return;

   if(g_race_winner=="" || t < g_race_winner_time)
   {
      g_race_winner="A"; g_race_winner_time=t;
      Race_MarkWin_A(DIR_DOWN, t);
      Race_InternalClearAll();
   }
}

//--------------------------- ???? B ???? Mode=UP (???? DOWN) ------------------
// ?? ??? HWBB: W2(DOWN) -> W3(DOWN)+body-break. ?????? ????? ?? SW ?????? ?? ???? ????? ???.
inline void Race_OnBar_UP(const MqlRates &rates[], const bool &insideHL[], const double &bodyLowEff[], const double &bodyHighEff[], const int n, const int upto_j)
{
   if(!g_race_locked || g_race_mode!=DIR_UP) return;
   RacePathBState S = g_pb_up;
   if(!S.init) return;

   int limit = MathMin(upto_j, n-1);
   while(S.idx <= limit)
   {
      if(S.state==R_SEARCH_W2)
      {
         bool found=false;

         for(int i=S.idx; i<=limit; ++i)
         {  
            // --- SPECIAL: active ref-up body-break after HWBB (Mode=UP -> Path-B=MTC_DOWN)
            if(Race_RefUp_IsActive() && i >= g_race_hwbb_idx)
            {
               if(rates[i].close < Race_ActiveRef_Up())
               {
                  // ??????? B ?? MTC_DOWN (???? ???? ?? W2/W3)
                  Race_SpecialRefBreak_MTC_Down(rates, n, i);
                  return;   // Race_* ???? ??? ?? ???? ? ???? ???? ?? ???? ??????
               }
            }
            
            // --- STRICT Path-B Gate (DOWN scan) ---
            bool __re=false;
            if(!C1W2_PB_DN_ShouldAllowAt(rates, i, __re)) continue;
            if(__re) S.idx=i;    // re-anchor ??? ???? ????

            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4))
               continue;

            if(i < g_race_hwbb_idx){ S.idx=(i4>=0?i4:i3)+1; continue; }

            // --- Lock W2 context (W2 found) ---
            S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

            // ?? ?? ??? W2? ??? Path-B ???? ????? ????
            C1W2_PB_DN_OnW2Locked();

            // reset W3 state
            S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
            S.w3_cand=-1;   S.w3_cand_high=-DBL_MAX;

            // body-break management
            S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
            S.bodyBreakLevel = rates[S.c1].low;
            S.breakAchieved  = false;
            S.bodyBreakIdx   = -1;

            // post body-break guard
            S.postBreak_c1_lock=false;
            S.postBreak_c1_ref =-1;

            S.idx=S.cend; S.state=R_WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ------------------------ R_WAIT_CONFIRM (DOWN counting) ------------------------
      {
         bool progressed=false;

         for(int j=S.idx; j<=limit; ++j)
         {
            // --- SPECIAL: active ref-up body-break after HWBB (Mode=UP -> Path-B=MTC_DOWN)
            if(Race_RefUp_IsActive() && j >= g_race_hwbb_idx)
            {
               if(rates[j].close < Race_ActiveRef_Up())
               {
                  Race_SpecialRefBreak_MTC_Down(rates, n, j);
                  return;
               }
            }

            if(insideHL[j]) continue;

            // Wick escalation (DOWN)
            if(!S.breakAchieved)
            {
               if(rates[j].low < S.bodyBreakLevel)
               {
                  if(rates[j].close < S.bodyBreakLevel)
                  {
                     S.breakAchieved = true; S.bodyBreakIdx = j;

                     int __c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
                     S.postBreak_c1_ref  = __c1_eff;
                     S.postBreak_c1_lock = (__c1_eff >= 0);
                  }
                  else
                  {
                     S.bodyBreakLevel = rates[j].low;
                     if(S.firstWickIdx < 0)
                     {
                        S.firstWickIdx = j; S.wickBreakIdx = j; S.wickActive = true;
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, S.cend, S.firstWickIdx);
                        S.have_w3=false; S.w3_c1 = anchorC1;
                        S.w3_cand=-1; S.w3_cand_high=-DBL_MAX;
                     }
                  }
               }
            }

            // Chain-Invalidation ?? ??????? ???? (pre-body): rewind ? ?????? re-anchor ??? Path-B
            {
               int __rew=-1;
               if(ChainInv_PreBody_WickWindow_DN_OnBar(rates,insideHL,n,j,
                     S.breakAchieved,S.wickActive,S.firstWickIdx,
                     S.w3_c1,S.w3_cand,__rew))
               {
                  C1W2_PB_DN_Reanchor(rates, __rew); // ??? ?? ?????? ??? ???? ??? ??? ???
                  S.idx          = __rew;
                  S.state        = R_SEARCH_W2;
                  progressed     = true;
                  break;
               }
            }

            // RESET W3 (non-wick, pre-body): H > H(C1_W3)
            if(!S.wickActive && !S.breakAchieved)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff>=0 && rates[j].high > rates[c1_eff].high)
               {
                  S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1=-1;
                  S.w3_cand=j; S.w3_cand_high=rates[j].high;
                  continue;
               }
            }

            // direct path: take largest High from cend onward
            if(!S.wickActive)
            {
               if(j>=S.cend && (S.w3_cand<0 || rates[j].high > S.w3_cand_high))
               { S.w3_cand=j; S.w3_cand_high=rates[j].high; S.have_w3=false; }
            }

            // Count W3 (DOWN)
            int startIdx=-1;
            if(S.w3_c1>=0) startIdx=S.w3_c1; else if(S.w3_cand>=0) startIdx=S.w3_cand;
            if(!S.have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1,w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
               { S.have_w3=true; if(S.w3_c1<0) S.w3_c1=startIdx; S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e; }
            }

            // Guard: change of C1_W3 after body-break ? invalidate W2
            if(S.breakAchieved && !S.have_w3)
            {
               int __c1_now = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(!S.postBreak_c1_lock && __c1_now>=0)
               { S.postBreak_c1_ref=__c1_now; S.postBreak_c1_lock=true; }
               else if(S.postBreak_c1_lock && __c1_now>=0 && __c1_now!=S.postBreak_c1_ref)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j);
                  S.state=R_SEARCH_W2; progressed=true; break;
               }
            }

            // Invalidate W2 after body-break but before W3 finishes: H > H(C1_W3)
            if(S.breakAchieved && !S.have_w3)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff>=0 && rates[j].high > rates[c1_eff].high)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j);
                  S.state=R_SEARCH_W2; progressed=true; break;
               }
            }

            // Finalize Path-B (MTC_DOWN)
            if(S.have_w3 && S.breakAchieved)
            {
               const datetime bt = rates[(S.bodyBreakIdx>=0?S.bodyBreakIdx:j)].time;

               if(g_race_winner=="" || bt < g_race_winner_time)
               {
                  g_race_winner      = "B";
                  g_race_winner_time = bt;

                  Race_MarkWin_B(DIR_UP, bt);
                  Race_DrawW2W3_MTC_Down(rates, n, S);

                  // Compute scan window before clearing race state
                  const int __c1=(S.c1>=0?S.c1:g_race_hwbb_idx);
                  const ENUM_TIMEFRAMES runtime_tf = __Race_RuntimeTF();
                  datetime __from = rates[__c1].time - (PeriodSeconds(runtime_tf)*5);
                  datetime __to   = __Race_ScanToTime(rates, n);
                  const bool __bump = __Race_IsMajorWorld();
                  Direction __prev_mode = g_race_mode;

                  // current API invocation must stop after this regime handoff
                  Race_RequestAbortCurrentAPIScan();

                  // IMPORTANT: nested scan must run with race unlocked
                  Race_InternalClearAll();

                  // Fail-safe cleanup (in case ref was missing)
                  SR_AllowOnly(DIR_DOWN);
                  __Race_ClearRegimeArtifacts();

                  if(__prev_mode==DIR_UP && !Trigger_M1HardStopFinalizeRequested())
                     API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf, __from, __to,
                                                           false, 0.0, 0, "", __bump);
               }
               else
               {
                  if(g_race_locked)
                     Race_InternalClearAll();
               }

               // terminal
               return;
            }
         }

         if(!progressed)
            break;
      }
   }

   g_pb_up = S;
}


//--------------------------- ???? B ???? Mode=DOWN (???? UP) -------------------
inline void Race_OnBar_DOWN(const MqlRates &rates[], const bool &insideHL[], const double &bodyLowEff[], const double &bodyHighEff[], const int n, const int upto_j)
{
   if(!g_race_locked || g_race_mode!=DIR_DOWN) return;
   RacePathBState S = g_pb_down;
   if(!S.init) return;

   int limit = MathMin(upto_j, n-1);
   while(S.idx <= limit)
   {
      if(S.state==R_SEARCH_W2)
      {
         bool found=false;

         for(int i=S.idx; i<=limit; ++i)
         {
            // --- SPECIAL: active ref-down body-break after HWBB (Mode=DOWN -> Path-B=MTC_UP)
            if(Race_RefDown_IsActive() && i >= g_race_hwbb_idx)
            {
               if(rates[i].close > Race_ActiveRef_Down())
               {
                  Race_SpecialRefBreak_MTC_Up(rates, n, i);
                  return;
               }
            }

            // --- STRICT Path-B Gate (UP scan) ---
            bool __re=false;
            if(!C1W2_PB_UP_ShouldAllowAt(rates, i, __re)) continue;
            if(__re) S.idx=i;

            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4))
               continue;

            if(i < g_race_hwbb_idx){ S.idx=(i4>=0?i4:i3)+1; continue; }

            // --- Lock W2 ---
            S.c1=i; S.c2=i2; S.c3=i3; S.c4=i4; S.cend=(S.c4>=0?S.c4:S.c3);

            C1W2_PB_UP_OnW2Locked();

            // reset W3
            S.have_w3=false; S.w3_c1=-1; S.k2=S.k3=S.k4=-1; S.w3_end=-1;
            S.w3_cand=-1;   S.w3_cand_low=DBL_MAX;

            // body-break management
            S.wickActive=false; S.firstWickIdx=-1; S.wickBreakIdx=-1;
            S.bodyBreakLevel = rates[S.c1].high;
            S.breakAchieved  = false;
            S.bodyBreakIdx   = -1;

            S.postBreak_c1_lock=false;
            S.postBreak_c1_ref =-1;

            S.idx=S.cend; S.state=R_WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ------------------------ R_WAIT_CONFIRM (UP counting) ------------------------
      {
         bool progressed=false;

         for(int j=S.idx; j<=limit; ++j)
         {
            if(Race_RefDown_IsActive() && j >= g_race_hwbb_idx)
            {
               if(rates[j].close > Race_ActiveRef_Down())
               {
                  Race_SpecialRefBreak_MTC_Up(rates, n, j);
                  return;
               }
            }

            if(insideHL[j]) continue;

            // Wick escalation (UP)
            if(!S.breakAchieved)
            {
               if(rates[j].high > S.bodyBreakLevel)
               {
                  if(rates[j].close > S.bodyBreakLevel)
                  {
                     S.breakAchieved = true; S.bodyBreakIdx = j;

                     int __c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
                     S.postBreak_c1_ref  = __c1_eff;
                     S.postBreak_c1_lock = (__c1_eff >= 0);
                  }
                  else
                  {
                     S.bodyBreakLevel = rates[j].high;
                     if(S.firstWickIdx < 0)
                     {
                        S.firstWickIdx = j; S.wickBreakIdx = j; S.wickActive = true;
                        int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, S.cend, S.firstWickIdx);
                        S.have_w3=false; S.w3_c1 = anchorC1;
                        S.w3_cand=-1; S.w3_cand_low=DBL_MAX;
                     }
                  }
               }
            }

            // Chain-Invalidation (pre-body, wick-window): rewind + re-anchor gate
            {
               int __rew=-1;
               if(ChainInv_PreBody_WickWindow_UP_OnBar(rates,insideHL,n,j,
                     S.breakAchieved,S.wickActive,S.firstWickIdx,
                     S.w3_c1,S.w3_cand,__rew))
               {
                  C1W2_PB_UP_Reanchor(rates, __rew);
                  S.idx          = __rew;
                  S.state        = R_SEARCH_W2;
                  progressed     = true;
                  break;
               }
            }

            // RESET W3 (non-wick, pre-body): L < L(C1_W3)
            if(!S.wickActive && !S.breakAchieved)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff>=0 && rates[j].low < rates[c1_eff].low)
               {
                  S.have_w3=false; S.w3_end=-1; S.k2=S.k3=S.k4=-1; S.w3_c1=-1;
                  S.w3_cand=j; S.w3_cand_low=rates[j].low;
                  continue;
               }
            }

            // direct path: take smallest Low from cend onward
            if(!S.wickActive)
            {
               if(j>=S.cend && (S.w3_cand<0 || rates[j].low < S.w3_cand_low))
               { S.w3_cand=j; S.w3_cand_low=rates[j].low; S.have_w3=false; }
            }

            // Count W3 (UP)
            int startIdx=-1;
            if(S.w3_c1>=0) startIdx=S.w3_c1; else if(S.w3_cand>=0) startIdx=S.w3_cand;
            if(!S.have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1,w3e=-1;
               if(CheckWave3CountOnly_Local(rates,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
               { S.have_w3=true; if(S.w3_c1<0) S.w3_c1=startIdx; S.k2=a2; S.k3=a3; S.k4=a4; S.w3_end=w3e; }
            }

            // Guard: change of C1_W3 after body-break ? invalidate W2
            if(S.breakAchieved && !S.have_w3)
            {
               int __c1_now = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(!S.postBreak_c1_lock && __c1_now>=0)
               { S.postBreak_c1_ref=__c1_now; S.postBreak_c1_lock=true; }
               else if(S.postBreak_c1_lock && __c1_now>=0 && __c1_now!=S.postBreak_c1_ref)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j);
                  S.state=R_SEARCH_W2; progressed=true; break;
               }
            }

            // Invalidate after body-break (UP): L < L(C1_W3)
            if(S.breakAchieved && !S.have_w3)
            {
               int c1_eff = (S.w3_c1>=0 ? S.w3_c1 : S.w3_cand);
               if(c1_eff>=0 && rates[j].low < rates[c1_eff].low)
               {
                  S.idx=(S.bodyBreakIdx>=0?S.bodyBreakIdx:j);
                  S.state=R_SEARCH_W2; progressed=true; break;
               }
            }

            // Finalize Path-B (MTC_UP)
            if(S.have_w3 && S.breakAchieved)
            {
               const datetime bt = rates[(S.bodyBreakIdx>=0?S.bodyBreakIdx:j)].time;

               if(g_race_winner=="" || bt < g_race_winner_time)
               {
                  g_race_winner      = "B";
                  g_race_winner_time = bt;

                  Race_MarkWin_B(DIR_DOWN, bt);
                  Race_DrawW2W3_MTC_Up(rates, n, S);

                  const int __c1=(S.c1>=0?S.c1:g_race_hwbb_idx);
                  const ENUM_TIMEFRAMES runtime_tf = __Race_RuntimeTF();
                  datetime __from = rates[__c1].time - (PeriodSeconds(runtime_tf)*5);
                  datetime __to   = __Race_ScanToTime(rates, n);
                  const bool __bump = __Race_IsMajorWorld();
                  Direction __prev_mode = g_race_mode;

                  // current API invocation must stop after this regime handoff
                  Race_RequestAbortCurrentAPIScan();

                  Race_InternalClearAll();

                  SR_AllowOnly(DIR_UP);
                  __Race_ClearRegimeArtifacts();

                  if(__prev_mode==DIR_DOWN && !Trigger_M1HardStopFinalizeRequested())
                     API_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf, __from, __to,
                                                      false, 0.0, 0, "", __bump);
               }
               else
               {
                  if(g_race_locked)
                     Race_InternalClearAll();
               }

               return;
            }
         }

         if(!progressed)
            break;
      }
   }

   g_pb_down = S;
}


// =====================[ MTC Drawing Helpers ]=====================
inline void Race_DrawW2W3_MTC_Down(const MqlRates &rates[], const int n, const RacePathBState &S)
{
   const string tag = IntegerToString(g_race_counter);

   // --- W2 (DOWN): C1..C4/Cend
   if(S.c1 >= 0 && S.c1 < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_C1_"+tag, rates[S.c1].time, clrFireBrick);
   if(S.c2 >= 0 && S.c2 < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_C2_"+tag, rates[S.c2].time, clrFireBrick);
   if(S.c3 >= 0 && S.c3 < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_C3_"+tag, rates[S.c3].time, clrFireBrick);
   int cend = (S.c4>=0 ? S.c4 : S.c3);
   if(cend >= 0 && cend < n) if(InpDrawMarkers) MarkV("MTC_DN_W2_CEND_"+tag, rates[cend].time, clrFireBrick);

   // --- W3 (DOWN)
   if(S.w3_c1 >= 0 && S.w3_c1 < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_C1_"+tag, rates[S.w3_c1].time, clrOrangeRed);
   if(S.k2    >= 0 && S.k2    < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_K2_"+tag, rates[S.k2].time,    clrOrangeRed);
   if(S.k3    >= 0 && S.k3    < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_K3_"+tag, rates[S.k3].time,    clrOrangeRed);
   if(S.k4    >= 0 && S.k4    < n) if(InpDrawMarkers) MarkV("MTC_DN_W3_K4_"+tag, rates[S.k4].time,    clrOrangeRed);
   if(S.w3_end>= 0 && S.w3_end< n) if(InpDrawMarkers) MarkV("MTC_DN_W3_END_"+tag,rates[S.w3_end].time,clrOrangeRed);

   // --- Body-Break (DOWN)
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n && InpDrawMarkers)
      MarkV("MTC_DN_BB_"+tag, rates[S.bodyBreakIdx].time, clrRed);

   // NEW (M15->M1 bridge): MTC is a STOP trigger (use body-break candle time)
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
      WB15_PublishStopMTC(InpSymbol, DIR_DOWN, rates[S.bodyBreakIdx].time);

   // --- Reference for this MTC_DOWN
   if(g_race_ref_mtc_down > 0.0)
   {
      Race_DeleteRefVisuals_AllScans();

      if(Race_ShouldDrawRefVisuals())
      {
         const string base_rname = "MTC_DN_REF_" + tag;
         const string rname      = __ScanPrefix() + base_rname;

         if(ObjectFind(0, rname) == -1)
            ObjectCreate(0, rname, OBJ_HLINE, 0, 0, g_race_ref_mtc_down);

         ObjectSetInteger(0, rname, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, rname, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rname, OBJPROP_STYLE, STYLE_SOLID);
      }

      datetime tbb = (S.bodyBreakIdx>=0 && S.bodyBreakIdx<n ? rates[S.bodyBreakIdx].time : TimeCurrent());
      Race_ActivateRef_Down(g_race_ref_mtc_down, tbb);

      SB_UP_BringToFront();
      SB_DN_BringToFront();
   }

   // --- IMPORTANT cleanup after MTC
   SR_AllowOnly(DIR_DOWN);
   __Race_ClearRegimeArtifacts();
}


inline void Race_DrawW2W3_MTC_Up(const MqlRates &rates[], const int n, const RacePathBState &S)
{
   const string tag = IntegerToString(g_race_counter);

   // --- W2 (UP): C1..C4/Cend
   if(S.c1 >= 0 && S.c1 < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_C1_"+tag, rates[S.c1].time, clrLime);
   if(S.c2 >= 0 && S.c2 < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_C2_"+tag, rates[S.c2].time, clrLime);
   if(S.c3 >= 0 && S.c3 < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_C3_"+tag, rates[S.c3].time, clrLime);
   int cend = (S.c4>=0 ? S.c4 : S.c3);
   if(cend >= 0 && cend < n) if(InpDrawMarkers) MarkV("MTC_UP_W2_CEND_"+tag, rates[cend].time, clrLime);

   // --- W3 (UP)
   if(S.w3_c1 >= 0 && S.w3_c1 < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_C1_"+tag, rates[S.w3_c1].time, clrDeepSkyBlue);
   if(S.k2    >= 0 && S.k2    < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_K2_"+tag, rates[S.k2].time,    clrDeepSkyBlue);
   if(S.k3    >= 0 && S.k3    < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_K3_"+tag, rates[S.k3].time,    clrDeepSkyBlue);
   if(S.k4    >= 0 && S.k4    < n) if(InpDrawMarkers) MarkV("MTC_UP_W3_K4_"+tag, rates[S.k4].time,    clrDeepSkyBlue);
   if(S.w3_end>= 0 && S.w3_end< n) if(InpDrawMarkers) MarkV("MTC_UP_W3_END_"+tag,rates[S.w3_end].time,clrDeepSkyBlue);

   // --- Body-Break (UP)
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n && InpDrawMarkers)
      MarkV("MTC_UP_BB_"+tag, rates[S.bodyBreakIdx].time, clrBlue);

   // NEW (M15->M1 bridge): MTC is a STOP trigger (use body-break candle time)
   if(S.bodyBreakIdx >= 0 && S.bodyBreakIdx < n)
      WB15_PublishStopMTC(InpSymbol, DIR_UP, rates[S.bodyBreakIdx].time);

   // --- Reference for this MTC_UP
   if(g_race_ref_mtc_up > 0.0)
   {
      Race_DeleteRefVisuals_AllScans();

      if(Race_ShouldDrawRefVisuals())
      {
         const string base_rname = "MTC_UP_REF_" + tag;
         const string rname      = __ScanPrefix() + base_rname;

         if(ObjectFind(0, rname) == -1)
            ObjectCreate(0, rname, OBJ_HLINE, 0, 0, g_race_ref_mtc_up);

         ObjectSetInteger(0, rname, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, rname, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rname, OBJPROP_STYLE, STYLE_SOLID);
      }

      datetime tbb = (S.bodyBreakIdx>=0 && S.bodyBreakIdx<n ? rates[S.bodyBreakIdx].time : TimeCurrent());
      Race_ActivateRef_Up(g_race_ref_mtc_up, tbb);

      SB_UP_BringToFront();
      SB_DN_BringToFront();
   }

   SR_AllowOnly(DIR_UP);
   __Race_ClearRegimeArtifacts();
}


// Draw MTC_DOWN only (special-case): just BB + REF, no W2/W3
inline void __Race_LaunchSpecialDirectionScan(const Direction dir,
                                             const MqlRates &rates[],
                                             const int n,
                                             const datetime from_time)
{
   const datetime __from = from_time;
   const datetime __to   = __Race_ScanToTime(rates, n);
   const bool     __bump = __Race_IsMajorWorld();
   const ENUM_TIMEFRAMES runtime_tf = __Race_RuntimeTF();

   if(Trigger_M1HardStopFinalizeRequested())
      return;

   if(dir == DIR_UP)
      API_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf, __from, __to,
                                       false, 0.0, 0, "", __bump);
   else
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, runtime_tf, __from, __to,
                                            false, 0.0, 0, "", __bump);
}

inline void Race_DrawMTCOnly_Down_ByRef(const MqlRates &rates[],
                                        const int n,
                                        const int bodyIdx,
                                        const double ref_price)
{
   const string tag = IntegerToString(g_race_counter);

   if(bodyIdx >= 0 && bodyIdx < n && InpDrawMarkers)
      MarkV("MTC_DN_BB_"+tag, rates[bodyIdx].time, clrRed);

   // NEW (M15->M1 bridge): MTC is a STOP trigger (special-case)
   if(bodyIdx >= 0 && bodyIdx < n)
      WB15_PublishStopMTC(InpSymbol, DIR_DOWN, rates[bodyIdx].time);

   if(ref_price > 0.0)
   {
      Race_DeleteRefVisuals_AllScans();

      if(Race_ShouldDrawRefVisuals())
      {
         const string base_rname = "MTC_DN_REF_" + tag;
         const string rname      = __ScanPrefix() + base_rname;

         if(ObjectFind(0, rname) == -1)
            ObjectCreate(0, rname, OBJ_HLINE, 0, 0, ref_price);

         ObjectSetInteger(0, rname, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, rname, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rname, OBJPROP_STYLE, STYLE_SOLID);
      }

      Race_ActivateRef_Down(ref_price, (bodyIdx>=0 && bodyIdx<n ? rates[bodyIdx].time : TimeCurrent()));
      SB_UP_BringToFront();
      SB_DN_BringToFront();
   }
   else
   {
      Race_DeleteRefVisuals_AllScans();
      g_active_ref_down      = 0.0;
      g_active_ref_down_time = (bodyIdx>=0 && bodyIdx<n ? rates[bodyIdx].time : TimeCurrent());
   }

   SR_AllowOnly(DIR_DOWN);
   __Race_ClearRegimeArtifacts();
}

inline void Race_DrawMTCOnly_Down(const MqlRates &rates[], const int n, const int bodyIdx)
{
   Race_DrawMTCOnly_Down_ByRef(rates, n, bodyIdx, g_race_ref_mtc_down);
}

// Draw MTC_UP only (special-case): just BB + REF, no W2/W3
inline void Race_DrawMTCOnly_Up_ByRef(const MqlRates &rates[],
                                      const int n,
                                      const int bodyIdx,
                                      const double ref_price)
{
   const string tag = IntegerToString(g_race_counter);

   if(bodyIdx >= 0 && bodyIdx < n && InpDrawMarkers)
      MarkV("MTC_UP_BB_"+tag, rates[bodyIdx].time, clrBlue);

   // NEW (M15->M1 bridge): MTC is a STOP trigger (special-case)
   if(bodyIdx >= 0 && bodyIdx < n)
      WB15_PublishStopMTC(InpSymbol, DIR_UP, rates[bodyIdx].time);

   if(ref_price > 0.0)
   {
      Race_DeleteRefVisuals_AllScans();

      if(Race_ShouldDrawRefVisuals())
      {
         const string base_rname = "MTC_UP_REF_" + tag;
         const string rname      = __ScanPrefix() + base_rname;

         if(ObjectFind(0, rname) == -1)
            ObjectCreate(0, rname, OBJ_HLINE, 0, 0, ref_price);

         ObjectSetInteger(0, rname, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, rname, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rname, OBJPROP_STYLE, STYLE_SOLID);
      }

      Race_ActivateRef_Up(ref_price, (bodyIdx>=0 && bodyIdx<n ? rates[bodyIdx].time : TimeCurrent()));
      SB_UP_BringToFront();
      SB_DN_BringToFront();
   }
   else
   {
      Race_DeleteRefVisuals_AllScans();
      g_active_ref_up      = 0.0;
      g_active_ref_up_time = (bodyIdx>=0 && bodyIdx<n ? rates[bodyIdx].time : TimeCurrent());
   }

   SR_AllowOnly(DIR_UP);
   __Race_ClearRegimeArtifacts();
}

inline void Race_DrawMTCOnly_Up(const MqlRates &rates[], const int n, const int bodyIdx)
{
   Race_DrawMTCOnly_Up_ByRef(rates, n, bodyIdx, g_race_ref_mtc_up);
}

// SPECIAL: ref-up body-break by HWBB(UP) => immediate MTC_DOWN win (Path B)
inline void Race_SpecialRefBreak_MTC_Down(const MqlRates &rates[], const int n, const int j)
{
   const datetime bt = (j>=0 && j<n ? rates[j].time : TimeCurrent());
   g_race_winner      = "B";
   g_race_winner_time = bt;

   // 0) ست‌کردن ext lq اولیهٔ جهت جدید از ref همین race
   if(g_race_ref_mtc_down > 0.0)
      ExtLQ_Down_Set(g_race_ref_mtc_down, bt);

   // 1) ثبت MTC
   Race_MarkWin_B(DIR_UP, bt);
   Race_DrawMTCOnly_Down_ByRef(rates, n, j, g_race_ref_mtc_down);

   // 2) handoff کامل به روند جدید
   Race_RequestAbortCurrentAPIScan();
   Race_InternalClearAll();
   SR_AllowOnly(DIR_DOWN);
   __Race_ClearRegimeArtifacts();

   // 3) launch اسکن DOWN از همین کندل
   __Race_LaunchSpecialDirectionScan(DIR_DOWN, rates, n, bt);
}

// SPECIAL: ref-down body-break by HWBB(DOWN) => immediate MTC_UP win (Path B)
inline void Race_SpecialRefBreak_MTC_Up(const MqlRates &rates[], const int n, const int j)
{
   const datetime bt = (j>=0 && j<n ? rates[j].time : TimeCurrent());
   g_race_winner      = "B";
   g_race_winner_time = bt;

   if(g_race_ref_mtc_up > 0.0)
      ExtLQ_Set(g_race_ref_mtc_up, bt);

   Race_MarkWin_B(DIR_DOWN, bt);
   Race_DrawMTCOnly_Up_ByRef(rates, n, j, g_race_ref_mtc_up);

   Race_RequestAbortCurrentAPIScan();
   Race_InternalClearAll();
   SR_AllowOnly(DIR_UP);
   __Race_ClearRegimeArtifacts();

   __Race_LaunchSpecialDirectionScan(DIR_UP, rates, n, bt);
}

// SPECIAL (global, post-MTC): اگر خط مرجع active شکسته شود، همان کندل باید
// بلافاصله تغییر روندِ MTC special را بسازد؛ حتی اگر race قفل نباشد و ext lq هم
// دیگر active نباشد.
inline void Race_SpecialRefBreak_ActiveRef_MTC_Down(const MqlRates &rates[], const int n, const int j)
{
   const datetime bt = (j>=0 && j<n ? rates[j].time : TimeCurrent());
   const double   ref_price = g_active_ref_down;

   ++g_race_counter;
   g_race_winner      = "B";
   g_race_winner_time = bt;

   // برای DOWN، اگر آخرین ref نزولیِ ذخیره‌شده موجود باشد آن را به‌عنوان ext lq اولیه می‌گذاریم.
   if(ref_price > 0.0)
      ExtLQ_Down_Set(ref_price, bt);

   Race_MarkWin_B(DIR_UP, bt);
   Race_DrawMTCOnly_Down_ByRef(rates, n, j, ref_price);

   Race_RequestAbortCurrentAPIScan();
   Race_InternalClearAll();
   SR_AllowOnly(DIR_DOWN);
   __Race_ClearRegimeArtifacts();

   __Race_LaunchSpecialDirectionScan(DIR_DOWN, rates, n, bt);
}

inline void Race_SpecialRefBreak_ActiveRef_MTC_Up(const MqlRates &rates[], const int n, const int j)
{
   const datetime bt = (j>=0 && j<n ? rates[j].time : TimeCurrent());
   const double   ref_price = g_active_ref_up;

   ++g_race_counter;
   g_race_winner      = "B";
   g_race_winner_time = bt;

   if(ref_price > 0.0)
      ExtLQ_Set(ref_price, bt);

   Race_MarkWin_B(DIR_DOWN, bt);
   Race_DrawMTCOnly_Up_ByRef(rates, n, j, ref_price);

   Race_RequestAbortCurrentAPIScan();
   Race_InternalClearAll();
   SR_AllowOnly(DIR_UP);
   __Race_ClearRegimeArtifacts();

   __Race_LaunchSpecialDirectionScan(DIR_UP, rates, n, bt);
}

inline bool Race_CheckActiveRefBreak_Global(const MqlRates &rates[], const int n, const int bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n) return false;
   if(g_race_locked) return false;

   const datetime bt = rates[bar_idx].time;

   // روند فعال UP => اگر ref-up شکسته شود، باید MTC_DOWN special رخ بدهد
   if(Race_RefUp_IsActive())
   {
      if(bt > Race_ActiveRef_Up_Time() && rates[bar_idx].close < Race_ActiveRef_Up())
      {
         Race_SpecialRefBreak_ActiveRef_MTC_Down(rates, n, bar_idx);
         return true;
      }
   }

   // روند فعال DOWN => اگر ref-down شکسته شود، باید MTC_UP special رخ بدهد
   if(Race_RefDown_IsActive())
   {
      if(bt > Race_ActiveRef_Down_Time() && rates[bar_idx].close > Race_ActiveRef_Down())
      {
         Race_SpecialRefBreak_ActiveRef_MTC_Up(rates, n, bar_idx);
         return true;
      }
   }

   return false;
}

#endif // WAVEBOT_RACECOORDINATOR_MQH