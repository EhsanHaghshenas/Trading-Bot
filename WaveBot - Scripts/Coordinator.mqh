#ifndef WAVEBOT_COORDINATOR_MQH
#define WAVEBOT_COORDINATOR_MQH

// Analysis-only M15 -> M1 coordination.  This module consumes callbacks from
// the existing analytical engines; it does not redefine their predicates and
// it does not contain any trade or position-management path.

enum WB_COORD_PARENT_STAGE
{
   WB_COORD_PARENT_WAIT_TC = 0,
   WB_COORD_PARENT_WAIT_HW = 1,
   WB_COORD_PARENT_WAIT_IMB = 2,
   WB_COORD_PARENT_ACTIVE = 3
};

enum WB_COORD_CHILD_STAGE
{
   WB_COORD_CHILD_WAIT_PARENT = 0,
   WB_COORD_CHILD_WAIT_TC = 1,
   WB_COORD_CHILD_WAIT_HW = 2,
   WB_COORD_CHILD_WAIT_IMB = 3,
   WB_COORD_CHILD_TRIGGER_READY = 4
};

struct WBCoordRecord
{
   string kind;
   long seq;
   datetime event_time;
   Direction direction;
   string generation;
   string zone_id;
   datetime first_time;
   datetime third_time;
   double base;
   double edge;
   datetime filled_time;
   bool active;
   datetime tc_time;
   datetime hw_time;
};

static bool g_wbc_instance_ready=false;
static string g_wbc_scan_symbol="";
static ENUM_TIMEFRAMES g_wbc_scan_tf=PERIOD_CURRENT;
static bool g_wbc_parent_role=false;

static WB_COORD_PARENT_STAGE g_wbc_parent_stage=WB_COORD_PARENT_WAIT_TC;
static Direction g_wbc_parent_direction=DIR_UP;
static datetime g_wbc_parent_mtc_time=0;
static datetime g_wbc_parent_tc_time=0;
static datetime g_wbc_parent_hw_time=0;
static datetime g_wbc_parent_imb_time=0;
static string g_wbc_parent_zone_id="";
static string g_wbc_parent_generation="";

static WB_COORD_CHILD_STAGE g_wbc_child_stage=WB_COORD_CHILD_WAIT_PARENT;
static bool g_wbc_child_parent_active=false;
static Direction g_wbc_child_direction=DIR_UP;
static string g_wbc_child_generation="";
static datetime g_wbc_child_handoff_time=0;
static datetime g_wbc_child_tc_time=0;
static datetime g_wbc_child_hw_time=0;
static datetime g_wbc_child_last_trigger_time=0;

static WBCoordRecord g_wbc_parent_records[];
static int g_wbc_parent_record_count=0;
static int g_wbc_parent_record_index=0;
static long g_wbc_parent_loaded_revision=-1;
static long g_wbc_parent_loaded_size=-1;
static long g_wbc_parent_sequence=0;
static bool g_wbc_parent_transport_active=false;
static Direction g_wbc_parent_transport_direction=DIR_UP;
static string g_wbc_parent_transport_generation="";
static datetime g_wbc_parent_transport_handoff=0;

static string g_wbc_child_seen_generation="";

inline string WBC_SafeKey(string value)
{
   StringReplace(value,"/","_");
   StringReplace(value,"\\","_");
   StringReplace(value,".","_");
   StringReplace(value,"#","_");
   StringReplace(value,":","_");
   if(StringLen(value)>28) value=StringSubstr(value,0,28);
   return value;
}

inline string WBC_LogName(const string sym)
{
   return "WaveBot_M15_COORD_"+WBC_SafeKey(sym)+".tsv";
}

inline string WBC_HeartbeatName(const string sym)
{
   return "WaveBot_M15_COORD_HB_"+WBC_SafeKey(sym);
}

inline string WBC_RevisionName(const string sym)
{
   return "WaveBot_M15_COORD_REV_"+WBC_SafeKey(sym);
}

inline bool WBC_IsM15(const ENUM_TIMEFRAMES tf)
{
   return (tf==PERIOD_M15);
}

inline bool WBC_IsM1(const ENUM_TIMEFRAMES tf)
{
   return (tf==PERIOD_M1);
}

inline string WBC_DirectionText(const Direction dir)
{
   return (dir==DIR_UP ? "UP" : "DOWN");
}

// -------------------------------------------------------------------------
// Pipeline visualization layer.  These functions never decide whether a
// strategic event is valid; they only render events already accepted by the
// coordinator.  This keeps TC/MTC/HW/IMB engines authoritative.
// -------------------------------------------------------------------------
inline bool WBC_ShouldDrawPipeline()
{
   return Markers_ShouldRender() && g_wbc_scan_symbol==_Symbol;
}

inline string WBC_VisualKey(string value)
{
   StringReplace(value,"|","_");
   StringReplace(value,"/","_");
   StringReplace(value,"\\","_");
   StringReplace(value," ","_");
   StringReplace(value,":","_");
   if(StringLen(value)>48) value=StringSubstr(value,0,48);
   return value;
}

inline void WB_Coord_DeletePipelineVisuals()
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      const string obj=ObjectName(0,i);
      if(StringFind(obj,"_MAJ_PIPE_")>=0 || StringFind(obj,"_MAJ_PIPEIMB_")>=0)
         ObjectDelete(0,obj);
   }
}

inline double WBC_StageY(const datetime event_time,const Direction dir,const int slot)
{
   int shift=iBarShift(g_wbc_scan_symbol,g_wbc_scan_tf,event_time,false);
   double high=0.0,low=0.0;
   if(shift>=0)
   {
      high=iHigh(g_wbc_scan_symbol,g_wbc_scan_tf,shift);
      low=iLow(g_wbc_scan_symbol,g_wbc_scan_tf,shift);
   }
   if(high<=0.0 || low<=0.0)
   {
      const double bid=SymbolInfoDouble(g_wbc_scan_symbol,SYMBOL_BID);
      high=bid; low=bid;
   }
   double point=SymbolInfoDouble(g_wbc_scan_symbol,SYMBOL_POINT);
   if(point<=0.0) point=_Point;
   const double candle=MathMax(0.0,high-low);
   const double step=MathMax(12.0*point,candle*0.22);
   return (dir==DIR_UP ? low-step*(slot+1) : high+step*(slot+1));
}

inline void WBC_DrawStage(const string stage,const datetime event_time,
                          const Direction dir,const int slot,const color tone,
                          const string detail="")
{
   if(!WBC_ShouldDrawPipeline() || event_time<=0) return;
   const string obj=__ScanPrefix()+"PIPE_"+WBC_VisualKey(stage)+"_"+
                    IntegerToString((int)(long)event_time);
   if(ObjectFind(0,obj)!=-1) ObjectDelete(0,obj);
   const double y=WBC_StageY(event_time,dir,slot);
   if(!ObjectCreate(0,obj,OBJ_TEXT,0,event_time,y)) return;
   ObjectSetString(0,obj,OBJPROP_TEXT,stage);
   ObjectSetString(0,obj,OBJPROP_TOOLTIP,
                   stage+(detail=="" ? "" : " | "+detail)+
                   " | "+TimeToString(event_time,TIME_DATE|TIME_MINUTES));
   ObjectSetInteger(0,obj,OBJPROP_COLOR,tone);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,obj,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);
   ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
}

inline string WBC_ParentFile(const string sym)
{
   return WBC_LogName(sym);
}

inline void WBC_SetHeartbeat(const string sym,const bool alive)
{
   const string name=WBC_HeartbeatName(sym);
   if(alive)
      GlobalVariableSet(name,(double)TimeLocal());
   else if(GlobalVariableCheck(name))
      GlobalVariableSet(name,0.0);
}

inline bool WBC_HeartbeatAlive(const string sym)
{
   const string name=WBC_HeartbeatName(sym);
   if(!GlobalVariableCheck(name)) return false;
   const double stamp=GlobalVariableGet(name);
   if(stamp<=0.0) return false;
   // A long enough lease tolerates a historical scan while still making a
   // terminal-crash/reload stale handoff fail closed.
   return ((double)TimeLocal()-stamp <= 180.0);
}

inline long WBC_ReadRevision(const string sym)
{
   const string name=WBC_RevisionName(sym);
   if(!GlobalVariableCheck(name)) return 0;
   return (long)GlobalVariableGet(name);
}

inline long WBC_ReadFileSize(const string sym)
{
   const string file=WBC_ParentFile(sym);
   const int h=FileOpen(file,FILE_COMMON|FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI,'\t');
   if(h==INVALID_HANDLE) return -1;
   const long size=(long)FileGetInteger(h,FILE_SIZE);
   FileClose(h);
   return size;
}

inline void WBC_TruncateParentLog(const string sym)
{
   const string file=WBC_ParentFile(sym);
   const int h=FileOpen(file,FILE_COMMON|FILE_CSV|FILE_WRITE|FILE_ANSI,'\t');
   if(h!=INVALID_HANDLE)
   {
      FileFlush(h);
      FileClose(h);
   }
   GlobalVariableSet(WBC_RevisionName(sym),0.0);
}

inline void WBC_AppendParentRecord(const string kind,const datetime event_time,
                                   const Direction dir,const string generation,
                                   const string zone_id,const datetime first_time,
                                   const datetime third_time,const double base,
                                   const double edge,const datetime filled_time,
                                   const bool active,const datetime tc_time,
                                   const datetime hw_time)
{
   if(!g_wbc_parent_role || g_wbc_scan_symbol=="") return;
   const string file=WBC_ParentFile(g_wbc_scan_symbol);
   const int h=FileOpen(file,FILE_COMMON|FILE_CSV|FILE_READ|FILE_WRITE|
                        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI,'\t');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   ++g_wbc_parent_sequence;
   FileWrite(h,kind,(long)g_wbc_parent_sequence,(long)event_time,(int)dir,
             generation,zone_id,(long)first_time,(long)third_time,base,edge,
             (long)filled_time,(active ? 1 : 0),(long)tc_time,(long)hw_time);
   FileFlush(h);
   FileClose(h);
   GlobalVariableSet(WBC_RevisionName(g_wbc_scan_symbol),(double)g_wbc_parent_sequence);
}

inline void WBC_ResetParentTransportCache()
{
   ArrayResize(g_wbc_parent_records,0);
   g_wbc_parent_record_count=0;
   g_wbc_parent_record_index=0;
   g_wbc_parent_loaded_revision=-1;
   g_wbc_parent_loaded_size=-1;
   g_wbc_parent_transport_active=false;
   g_wbc_parent_transport_generation="";
   g_wbc_parent_transport_handoff=0;
}

inline bool WBC_RecordBefore(const WBCoordRecord &a,const WBCoordRecord &b)
{
   if(a.event_time!=b.event_time) return (a.event_time<b.event_time);
   return (a.seq<b.seq);
}

inline void WBC_InsertParentRecord(const WBCoordRecord &record)
{
   int pos=g_wbc_parent_record_count;
   ArrayResize(g_wbc_parent_records,g_wbc_parent_record_count+1);
   while(pos>0 && WBC_RecordBefore(record,g_wbc_parent_records[pos-1]))
   {
      g_wbc_parent_records[pos]=g_wbc_parent_records[pos-1];
      --pos;
   }
   g_wbc_parent_records[pos]=record;
   ++g_wbc_parent_record_count;
}

inline bool WBC_LoadParentRecords(const string sym)
{
   if(!WBC_HeartbeatAlive(sym))
   {
      WBC_ResetParentTransportCache();
      return false;
   }

   const long revision=WBC_ReadRevision(sym);
   const long file_size=WBC_ReadFileSize(sym);
   if(revision==g_wbc_parent_loaded_revision && file_size==g_wbc_parent_loaded_size)
      return true;

   WBC_ResetParentTransportCache();
   const string file=WBC_ParentFile(sym);
   const int h=FileOpen(file,FILE_COMMON|FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI,'\t');
   if(h==INVALID_HANDLE)
   {
      g_wbc_parent_loaded_revision=revision;
      g_wbc_parent_loaded_size=file_size;
      return false;
   }

   while(!FileIsEnding(h))
   {
      const string kind=FileReadString(h);
      if(kind=="") break;
      WBCoordRecord r;
      r.kind=kind;
      r.seq=(long)StringToInteger(FileReadString(h));
      r.event_time=(datetime)StringToInteger(FileReadString(h));
      r.direction=(Direction)StringToInteger(FileReadString(h));
      r.generation=FileReadString(h);
      r.zone_id=FileReadString(h);
      r.first_time=(datetime)StringToInteger(FileReadString(h));
      r.third_time=(datetime)StringToInteger(FileReadString(h));
      r.base=StringToDouble(FileReadString(h));
      r.edge=StringToDouble(FileReadString(h));
      r.filled_time=(datetime)StringToInteger(FileReadString(h));
      r.active=(StringToInteger(FileReadString(h))!=0);
      r.tc_time=(datetime)StringToInteger(FileReadString(h));
      r.hw_time=(datetime)StringToInteger(FileReadString(h));
      WBC_InsertParentRecord(r);
   }
   FileClose(h);

   g_wbc_parent_loaded_revision=revision;
   g_wbc_parent_loaded_size=file_size;
   return true;
}

inline void WBC_ApplyParentRecord(const WBCoordRecord &r)
{
   // M15 IMB geometry is intentionally NOT imported into the M1 child.
   // The parent still transports HANDOFF/CANCEL generation state, but C4 may
   // be completed only by a qualifying local M1 IMB interaction.  Ignore
   // historical ZONE records here so an M15 zone can never become a child
   // trigger source through cross-chart transport.
   if(r.kind=="ZONE")
      return;
   if(r.kind=="CANCEL")
   {
      if(g_wbc_parent_transport_active &&
         (r.generation=="" || r.generation==g_wbc_parent_transport_generation))
      {
         g_wbc_parent_transport_active=false;
         g_wbc_parent_transport_generation="";
         g_wbc_parent_transport_handoff=0;
      }
      return;
   }
   if(r.kind=="HANDOFF")
   {
      g_wbc_parent_transport_active=true;
      g_wbc_parent_transport_direction=r.direction;
      g_wbc_parent_transport_generation=r.generation;
      g_wbc_parent_transport_handoff=r.event_time;
   }
}

inline bool WBC_RefreshParentAt(const string sym,const datetime bar_time)
{
   const bool loaded=WBC_LoadParentRecords(sym);
   if(!loaded) return false;
   while(g_wbc_parent_record_index<g_wbc_parent_record_count)
   {
      const WBCoordRecord r=g_wbc_parent_records[g_wbc_parent_record_index];
      if(r.event_time>bar_time) break;
      WBC_ApplyParentRecord(r);
      ++g_wbc_parent_record_index;
   }
   if(!WBC_HeartbeatAlive(sym))
      g_wbc_parent_transport_active=false;
   return g_wbc_parent_transport_active;
}

inline string WBC_MakeGeneration(const Direction dir,const datetime tc_time,
                                  const datetime hw_time,const datetime imb_time,
                                  const string zone_id)
{
   return WBC_DirectionText(dir)+"|"+(string)(long)tc_time+"|"+
          (string)(long)hw_time+"|"+(string)(long)imb_time+"|"+zone_id;
}

inline void WBC_ClearChildState(const bool keep_parent)
{
   g_wbc_child_stage=(keep_parent && g_wbc_child_parent_active ?
                      WB_COORD_CHILD_WAIT_TC : WB_COORD_CHILD_WAIT_PARENT);
   g_wbc_child_tc_time=0;
   g_wbc_child_hw_time=0;
   g_wbc_child_last_trigger_time=0;
   if(!keep_parent)
      g_wbc_child_generation="";
}

inline void WBC_InitializeChildForParent(const datetime bar_time)
{
   T1_OnPipelineReset(bar_time,"NEW_PARENT_GENERATION");
   g_wbc_child_direction=g_wbc_parent_transport_direction;
   g_wbc_child_handoff_time=g_wbc_parent_transport_handoff;
   g_wbc_child_generation=g_wbc_parent_transport_generation;
   g_wbc_child_parent_active=true;
   g_wbc_child_last_trigger_time=0;
   WBC_DrawStage("C1 PARENT READY",bar_time,g_wbc_child_direction,0,clrAqua,
                 "generation="+g_wbc_child_generation);

   // A handoff can arrive after M1 has already entered the same confirmed
   // trend.  That current TC state satisfies the child trend stage; only HW
   // events delivered after the handoff may advance the next stage.
   if(TC_IsConfirmed() && TC_ConfirmationTime()>0 &&
      TC_ConfirmationTime()<=bar_time &&
      g_tc_mtc_direction==g_wbc_child_direction)
   {
      g_wbc_child_tc_time=TC_ConfirmationTime();
      g_wbc_child_hw_time=0;
      g_wbc_child_stage=WB_COORD_CHILD_WAIT_HW;
      WBC_DrawStage("C2 TC ALIGNED",bar_time,g_wbc_child_direction,1,clrDeepSkyBlue,
                    "existing TC="+TimeToString(g_wbc_child_tc_time,TIME_DATE|TIME_MINUTES));
      return;
   }

   g_wbc_child_tc_time=0;
   g_wbc_child_hw_time=0;
   g_wbc_child_stage=WB_COORD_CHILD_WAIT_TC;
}

inline bool WBC_ChildTriggerReady(const datetime event_time,const string source)
{
   // One-shot belongs to the CURRENT child attempt, not to the lifetime of
   // the M15 parent generation.  WAIT_IMB -> TRIGGER_READY is atomic.
   // While TRIGGER_READY is active, duplicate C4 events are impossible
   // because WB_Coord_OnIMBInteraction accepts only WAIT_IMB.  After a
   // CHILD RESTART the same parent generation is intentionally allowed to
   // build a fresh C2/C3/C4 sequence and activate TRIGGER_READY again.
   if(g_wbc_child_stage!=WB_COORD_CHILD_WAIT_IMB)
      return false;

   g_wbc_child_stage=WB_COORD_CHILD_TRIGGER_READY;
   g_wbc_child_last_trigger_time=event_time;
   T1_OnTriggerReady(g_wbc_child_direction,event_time,g_wbc_child_generation);
   WBC_DrawStage("TRIGGER READY",event_time,g_wbc_child_direction,4,clrMagenta,
                 "source="+source+" generation="+g_wbc_child_generation);
   if(InpDebugPrints)
      Print("[WB-COORD] TRIGGER_READY generation=",g_wbc_child_generation,
            " direction=",WBC_DirectionText(g_wbc_child_direction),
            " source=",source," time=",TimeToString(event_time,TIME_DATE|TIME_MINUTES));
   return true;
}

// Read-only state for the future trigger engine.  No trading or trigger
// predicate is implemented here; these helpers only expose whether the
// analytical pipeline is currently allowed to begin trigger evaluation.
inline bool WB_Coord_IsTriggerReady()
{
   return (g_wbc_instance_ready && WBC_IsM1(g_wbc_scan_tf) &&
           g_wbc_child_parent_active &&
           g_wbc_child_stage==WB_COORD_CHILD_TRIGGER_READY);
}

inline datetime WB_Coord_TriggerReadyTime()
{
   return (WB_Coord_IsTriggerReady() ? g_wbc_child_last_trigger_time : 0);
}

inline Direction WB_Coord_TriggerReadyDirection()
{
   return g_wbc_child_direction;
}

inline string WB_Coord_TriggerReadyGeneration()
{
   return (WB_Coord_IsTriggerReady() ? g_wbc_child_generation : "");
}

inline void WBC_ResetChildScan()
{
   T1_OnPipelineReset(0,"CHILD_SCAN_RESET");
   g_wbc_child_stage=WB_COORD_CHILD_WAIT_PARENT;
   g_wbc_child_parent_active=false;
   g_wbc_child_generation="";
   g_wbc_child_handoff_time=0;
   g_wbc_child_tc_time=0;
   g_wbc_child_hw_time=0;
   g_wbc_child_last_trigger_time=0;
   g_wbc_child_seen_generation="";
   WBC_ResetParentTransportCache();
}

inline void WB_Coord_ResetScan(const string sym,const ENUM_TIMEFRAMES tf)
{
   g_wbc_scan_symbol=sym;
   g_wbc_scan_tf=tf;
   g_wbc_parent_role=WBC_IsM15(tf);
   g_wbc_parent_stage=WB_COORD_PARENT_WAIT_TC;
   g_wbc_parent_direction=DIR_UP;
   g_wbc_parent_mtc_time=0;
   g_wbc_parent_tc_time=0;
   g_wbc_parent_hw_time=0;
   g_wbc_parent_imb_time=0;
   g_wbc_parent_zone_id="";
   g_wbc_parent_generation="";
   g_wbc_parent_sequence=0;

   if(g_wbc_parent_role)
   {
      WBC_TruncateParentLog(sym);
      WBC_SetHeartbeat(sym,true);
   }
   else if(WBC_IsM1(tf))
      WBC_ResetChildScan();
}

inline void WB_Coord_OnMTC(const Direction dir,const datetime event_time)
{
   if(!g_wbc_instance_ready || event_time<=0) return;
   if(g_wbc_parent_role)
   {
      const bool opposite_restart=(g_wbc_parent_mtc_time>0 && dir!=g_wbc_parent_direction);
      if(opposite_restart)
         WBC_DrawStage("PARENT RESTART",event_time,dir,0,clrRed,
                       "opposite MTC invalidated current parent pipeline");
      if(g_wbc_parent_stage==WB_COORD_PARENT_ACTIVE && g_wbc_parent_generation!="")
         WBC_AppendParentRecord("CANCEL",event_time,dir,g_wbc_parent_generation,"",0,0,0.0,0.0,0,false,g_wbc_parent_tc_time,g_wbc_parent_hw_time);
      g_wbc_parent_direction=dir;
      g_wbc_parent_mtc_time=event_time;
      g_wbc_parent_tc_time=0;
      g_wbc_parent_hw_time=0;
      g_wbc_parent_imb_time=0;
      g_wbc_parent_zone_id="";
      g_wbc_parent_generation="";
      g_wbc_parent_stage=WB_COORD_PARENT_WAIT_TC;
      WBC_AppendParentRecord("MTC",event_time,dir,"","",0,0,0.0,0.0,0,false,0,0);
      return;
   }
   if(!WBC_IsM1(g_wbc_scan_tf)) return;
   if(!g_wbc_child_parent_active) return;
   if(dir!=g_wbc_child_direction)
      WBC_DrawStage("CHILD RESTART",event_time,dir,0,clrRed,
                    "opposite M1 MTC; parent generation remains active");
   if(dir==g_wbc_child_direction)
   {
      // Desired-direction MTC means the child must obtain a fresh TC before
      // continuing.  Any prior TRIGGER_READY permission is no longer active.
      T1_OnPipelineReset(event_time,"CHILD_MTC_RESET");
      g_wbc_child_stage=WB_COORD_CHILD_WAIT_TC;
      g_wbc_child_tc_time=0;
      g_wbc_child_hw_time=0;
      g_wbc_child_last_trigger_time=0;
   }
   else
   {
      // CHILD RESTART keeps the valid M15 parent generation but rearms the
      // child attempt.  A later fresh C2/C3/C4 may therefore produce a new
      // TRIGGER_READY within this same parent generation.
      T1_OnPipelineReset(event_time,"CHILD_RESTART");
      WBC_ClearChildState(true);
   }
}

inline void WB_Coord_OnTC(const Direction dir,const datetime event_time)
{
   if(!g_wbc_instance_ready || event_time<=0) return;
   if(g_wbc_parent_role)
   {
      if(dir!=g_wbc_parent_direction || g_wbc_parent_mtc_time<=0 ||
         event_time<=g_wbc_parent_mtc_time) return;
      g_wbc_parent_tc_time=event_time;
      g_wbc_parent_stage=WB_COORD_PARENT_WAIT_HW;
      WBC_DrawStage("P1 TC "+WBC_DirectionText(dir),event_time,dir,0,clrDeepSkyBlue,
                    "parent trend confirmed");
      return;
   }
   if(!WBC_IsM1(g_wbc_scan_tf) || !g_wbc_child_parent_active ||
      dir!=g_wbc_child_direction || event_time<=g_wbc_child_handoff_time)
      return;
   g_wbc_child_tc_time=event_time;
   g_wbc_child_hw_time=0;
   g_wbc_child_stage=WB_COORD_CHILD_WAIT_HW;
   WBC_DrawStage("C2 TC ALIGNED",event_time,dir,1,clrDeepSkyBlue,
                 "generation="+g_wbc_child_generation);
}

inline void WBC_OnHWAccepted(const Direction dir,const datetime event_time,
                             const string hw_kind)
{
   if(!g_wbc_instance_ready || event_time<=0) return;
   if(g_wbc_parent_role)
   {
      if(g_wbc_parent_stage!=WB_COORD_PARENT_WAIT_HW ||
         dir!=g_wbc_parent_direction || event_time<=g_wbc_parent_tc_time) return;
      g_wbc_parent_hw_time=event_time;
      g_wbc_parent_stage=WB_COORD_PARENT_WAIT_IMB;
      WBC_DrawStage("P2 "+hw_kind+" "+WBC_DirectionText(dir),event_time,dir,1,clrDodgerBlue,
                    "parent HW stage complete");
      return;
   }
   if(!WBC_IsM1(g_wbc_scan_tf) || !g_wbc_child_parent_active ||
      g_wbc_child_stage!=WB_COORD_CHILD_WAIT_HW || dir!=g_wbc_child_direction ||
      event_time<=g_wbc_child_tc_time || event_time<=g_wbc_child_handoff_time)
      return;
   g_wbc_child_hw_time=event_time;
   g_wbc_child_stage=WB_COORD_CHILD_WAIT_IMB;
   WBC_DrawStage("C3 "+hw_kind+" "+WBC_DirectionText(dir),event_time,dir,2,clrDodgerBlue,
                 "generation="+g_wbc_child_generation);
}

inline void WB_Coord_OnHW(const Direction dir,const datetime event_time)
{
   WBC_OnHWAccepted(dir,event_time,"HWX");
}

inline void WB_Coord_OnHWBB(const Direction dir,const datetime event_time)
{
   // HW and HWBB are two existing representations of the same logical stage.
   // The first accepted event advances the state; later same-direction events
   // are ignored while WAIT_IMB/ACTIVE, preventing duplicate pipelines.
   WBC_OnHWAccepted(dir,event_time,"HWBB");
}

inline void WB_Coord_OnIMBZoneState(const string zone_id,const Direction dir,
                                    const datetime event_time,const datetime first_time,
                                    const datetime third_time,const double base,
                                    const double edge,const datetime filled_time,
                                    const bool active)
{
   if(!g_wbc_instance_ready || !g_wbc_parent_role || zone_id=="" || event_time<=0)
      return;
   WBC_AppendParentRecord("ZONE",event_time,dir,"",zone_id,first_time,third_time,
                         base,edge,filled_time,active,0,0);
}

inline bool WB_Coord_OnIMBInteraction(const Direction dir,const datetime event_time,
                                      const ENUM_TIMEFRAMES source_tf,const string zone_id,
                                      const datetime zone_third_time)
{
   if(!g_wbc_instance_ready || event_time<=0) return false;
   if(g_wbc_parent_role && source_tf==PERIOD_M15)
   {
      // P3 starts checking on the HW candle itself and then on EVERY
      // later candle until a valid touch or reset.  The touched IMB must
      // have been fully formed before that accepted HW candle; an IMB born
      // on the HW candle or afterwards cannot satisfy this parent stage.
      if(g_wbc_parent_stage!=WB_COORD_PARENT_WAIT_IMB ||
         dir!=g_wbc_parent_direction || g_wbc_parent_hw_time<=0 ||
         event_time<g_wbc_parent_hw_time || zone_third_time<=0 ||
         zone_third_time>=g_wbc_parent_hw_time)
         return false;
      g_wbc_parent_imb_time=event_time;
      g_wbc_parent_zone_id=zone_id;
      g_wbc_parent_generation=WBC_MakeGeneration(dir,g_wbc_parent_tc_time,
                                                  g_wbc_parent_hw_time,event_time,zone_id);
      g_wbc_parent_stage=WB_COORD_PARENT_ACTIVE;
      WBC_DrawStage("P3 IMB HIT",event_time,dir,2,clrGold,
                    "zone="+zone_id);
      WBC_DrawStage("PARENT HANDOFF",event_time,dir,3,clrAqua,
                    "generation="+g_wbc_parent_generation);
      WBC_AppendParentRecord("HANDOFF",event_time,dir,g_wbc_parent_generation,
                             zone_id,0,0,0.0,0.0,0,true,
                             g_wbc_parent_tc_time,g_wbc_parent_hw_time);
      if(InpDebugPrints)
         Print("[WB-COORD] PARENT_HANDOFF_ACTIVE generation=",
               g_wbc_parent_generation," symbol=",g_wbc_scan_symbol);
      return true;
   }
   // Child C4 is M1-local by design.  Cross-timeframe M15 IMB touches are
   // never eligible here; only the M1 IMB engine may advance WAIT_IMB.
   if(!WBC_IsM1(g_wbc_scan_tf) || source_tf!=PERIOD_M1) return false;
   if(!g_wbc_child_parent_active || g_wbc_child_stage!=WB_COORD_CHILD_WAIT_IMB)
      return false;
   // Refresh before accepting a child touch so a same-timestamp parent MTC
   // cancellation wins over this event.
   if(!WBC_RefreshParentAt(g_wbc_scan_symbol,event_time) ||
      !g_wbc_child_parent_active || g_wbc_child_stage!=WB_COORD_CHILD_WAIT_IMB)
      return false;
   // Same rule for a local M1 IMB: the zone must pre-date the accepted
   // child HW.  IMB_ProcessChronologicalBar runs on every bar after market
   // structure callbacks, so a touch on the HW candle itself is accepted,
   // and if absent the next candle, then the next, are all evaluated.
   if(dir!=g_wbc_child_direction || g_wbc_child_hw_time<=0 ||
      event_time<g_wbc_child_hw_time || zone_third_time<=0 ||
      zone_third_time>=g_wbc_child_hw_time)
      return false;
   // C4 and TRIGGER_READY are one atomic state transition.  If C4 is
   // accepted, trigger evaluation permission MUST become active immediately.
   if(!WBC_ChildTriggerReady(event_time,"M1_IMB_"+zone_id))
      return false;
   WBC_DrawStage("C4 M1 IMB HIT",event_time,dir,3,clrGold,
                 "zone="+zone_id+" generation="+g_wbc_child_generation);
   return true;
}

inline void WB_Coord_OnBarAfterIMB(const string sym,const ENUM_TIMEFRAMES tf,
                                   const datetime bar_time)
{
   if(!g_wbc_instance_ready || bar_time<=0) return;
   // Historical scans run inside one serialized EA event.  Refresh the
   // parent lease from the same per-bar callback so a valid long scan does
   // not look stale merely because timer events cannot interleave with it.
   if(g_wbc_parent_role && WBC_IsM15(tf))
   {
      WBC_SetHeartbeat(sym,true);
      return;
   }
   if(!WBC_IsM1(tf)) return;
   const bool had_parent_before_refresh=g_wbc_child_parent_active;
   if(!WBC_RefreshParentAt(sym,bar_time))
   {
      if(had_parent_before_refresh)
         WBC_DrawStage("PARENT CANCEL / CHILD RESET",bar_time,g_wbc_child_direction,0,clrRed,
                       "M15 parent generation invalidated");
      T1_OnPipelineReset(bar_time,"PARENT_CANCEL");
      if(g_wbc_child_parent_active)
         WBC_ClearChildState(false);
      g_wbc_child_parent_active=false;
      g_wbc_child_stage=WB_COORD_CHILD_WAIT_PARENT;
      return;
   }

   if(g_wbc_child_generation!=g_wbc_parent_transport_generation)
   {
      WBC_InitializeChildForParent(bar_time);
      g_wbc_child_seen_generation=g_wbc_child_generation;
   }
   g_wbc_child_parent_active=true;
   // No M15-zone price test belongs here.  After C3 HWX/HWBB, the local M1
   // IMB engine evaluates the HW candle and every later M1 candle and calls
   // WB_Coord_OnIMBInteraction only for M1 zones.
}

inline void WB_Coord_OnInstanceInit()
{
   g_wbc_instance_ready=true;
   g_wbc_scan_symbol=WB_PrimaryInputSymbol();
   g_wbc_scan_tf=WB_RuntimeTF();
   g_wbc_parent_role=WBC_IsM15(g_wbc_scan_tf);
   if(g_wbc_parent_role) WBC_SetHeartbeat(g_wbc_scan_symbol,true);
}

inline void WB_Coord_OnInstanceDeinit()
{
   if(g_wbc_parent_role && g_wbc_scan_symbol!="")
      WBC_SetHeartbeat(g_wbc_scan_symbol,false);
   g_wbc_instance_ready=false;
}

inline bool WB_Coord_OnTimer()
{
   if(!g_wbc_instance_ready) return false;
   if(g_wbc_parent_role)
   {
      WBC_SetHeartbeat(g_wbc_scan_symbol,true);
      return false;
   }
   if(!WBC_IsM1(g_wbc_scan_tf)) return false;
   const long revision=WBC_ReadRevision(g_wbc_scan_symbol);
   const long file_size=WBC_ReadFileSize(g_wbc_scan_symbol);
   if(revision==g_wbc_parent_loaded_revision && file_size==g_wbc_parent_loaded_size)
      return false;
   // A changed parent log (including cancellation) requires a fresh child
   // chronological pass.  The pass itself decides whether a current handoff
   // exists; it never manufactures a parent signal.
   return WBC_HeartbeatAlive(g_wbc_scan_symbol);
}

#endif // WAVEBOT_COORDINATOR_MQH
