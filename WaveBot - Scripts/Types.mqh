#ifndef WAVEBOT_TYPES_MQH
#define WAVEBOT_TYPES_MQH

// Types.mqh — انواع داده و قراردادهای مشترک
// نقش: تعریف ساختارهای خروجی/ورودی مشترک بین ماژول‌ها (فعلاً W2Result برای موج۲).
// بدون وابستگی اجرایی؛ فقط قرارداد نوع داده برای استفاده‌ی ماژول‌ها.

struct W2Result
{
   int  c1, c2, c3, c4;  // c4 ممکن است -1 باشد
   int  end_index;       // (c4>=0? c4 : c3)
   bool ok;
};

// جهت اسکن/مود
enum Direction
{
   DIR_UP   = 0,
   DIR_DOWN = 1
};

// Trigger Type 1 completed-event contract.  Level names are direction-neutral:
// UP => validation=InitialValidationLow, start=PullbackStartHigh,
//       extreme=PullbackLow, final=FinalTriggerHigh.
// DOWN is the exact High/Low mirror.
struct T1TriggerEvent
{
   int candidate_id;
   int parent_candidate_id;
   string generation;
   Direction direction;
   datetime trigger_time;
   ulong trigger_msc;       // exact completion tick when available; 0 = OHLC-only
   double validation_level;
   double pullback_start_level;
   double pullback_extreme;
   double final_trigger_level;
};

// Central M15 -> M1 analytical coordination callbacks.  The declarations live
// here so the authoritative analytical modules can emit their existing events
// without depending on the coordinator implementation or changing ownership
// of TC/MTC/HW/HWBB/IMB detection.
void WB_Coord_OnMTC(const Direction dir,const datetime event_time);
void WB_Coord_OnTC(const Direction dir,const datetime event_time);
void WB_Coord_OnHW(const Direction dir,const datetime event_time);
void WB_Coord_OnHWBB(const Direction dir,const datetime event_time);
void WB_Coord_OnIMBZoneState(const string zone_id,const Direction dir,
                             const datetime event_time,const datetime first_time,
                             const datetime third_time,const double base,
                             const double edge,const datetime filled_time,
                             const bool active);
bool WB_Coord_OnIMBInteraction(const Direction dir,const datetime event_time,
                               const ENUM_TIMEFRAMES source_tf,const string zone_id,
                               const datetime zone_third_time);
void WB_Coord_OnBarAfterIMB(const string sym,const ENUM_TIMEFRAMES tf,
                            const datetime bar_time);
void WB_Coord_ResetScan(const string sym,const ENUM_TIMEFRAMES tf);
void WB_Coord_OnInstanceInit();
void WB_Coord_OnInstanceDeinit();
bool WB_Coord_OnTimer();

// Trigger Type 1 analytical engine.  It is armed only by the coordinator's
// TRIGGER_READY state and is stopped by child/parent pipeline resets.
void T1_ResetGlobals();
void T1_OnTriggerReady(const Direction dir,const datetime event_time,
                       const string generation);
void T1_OnPipelineReset(const datetime event_time,const string reason);
bool T1_IsArmed();
int T1_TriggerEventCount();
bool T1_GetTriggerEvent(const int index,T1TriggerEvent &out);
int T1_PrimaryCandidateID();
void T1_ProcessBar(const string sym,const ENUM_TIMEFRAMES tf,
                   const MqlRates &rates[],const int n,const int i);

#endif // WAVEBOT_TYPES_MQH
