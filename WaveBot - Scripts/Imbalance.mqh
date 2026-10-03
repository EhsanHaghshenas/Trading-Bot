// WaveBot/Imbalance.mqh
#ifndef WAVEBOT_IMBALANCE_MQH
#define WAVEBOT_IMBALANCE_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>

// Market analysis only. On a TC event, backfill IMB candidates from the
// ACTUAL reference candle that anchors that MTC's opposite-special-break
// level. Newly discovered retro zones become active at TC, and ALL surviving
// zones (including pre-existing zones across any number of intervening MTC/TC
// changes) respond to PARTIAL touches ONLY under a matching confirmed TC.
// Full penetration ALWAYS invalidates, even outside a matching TC. Examine
// every rolling three-CLOSED-bar window, including overlapping candidates.
// UP: candle 2 CLOSE > candle 1 HIGH, and candle 3 LOW > candle 1 HIGH.
//     Fixed/base boundary = candle 1 LOW; moving/top boundary = candle 3 LOW.
// DOWN: candle 2 CLOSE < candle 1 LOW, and candle 3 HIGH < candle 1 LOW.
//       Fixed/base boundary = candle 1 HIGH; moving/bottom = candle 3 HIGH.
// Candle 1 and candle 3 can be red OR green in EITHER direction. Only the
// breaker's close direction is relevant. Candles may participate in multiple
// independent, overlapping IMBs: never skip ahead after a formation.
//
// Filled zones are ARCHIVED, not removed: all BASE, initial EDGE, touch
// markers and every update EDGE remain drawn after mitigation. A FILLED tag identifies their
// terminal candle. Only a re-attach/full historical rebuild clears old visual
// objects before reconstructing the entire visible history from scratch.

struct IMBTrendEvent
{
   datetime  time;
   datetime  mtc_time;
   Direction direction;
   bool      is_mtc;
   datetime  reference_time; // real C1/extreme candle of the active MTC reference
};

struct IMBZone
{
   string    id;             // unique per symbol / direction / sequence
   string    symbol;
   string    tag;            // readable: U001, D002, ...
   Direction direction;
   color     tone;           // same identifying color on ALL this zone's levels
   int       serial;
   datetime  first_time;
   datetime  third_time;
   datetime  filled_time;    // 0 while active; historical archive otherwise
   double    base;           // immutable: first LOW (UP) or first HIGH (DOWN)
   double    edge;           // latest partial-fill boundary
   int       edge_count;     // 1 initial segment + one per partial update
   int       touch_count;    // every aligned-TC encounter (even without new low/high)
   datetime  first_tc_time;  // distinguishes later TC returns from initial touches
   datetime  source_ref_time; // actual MTC reference candle anchoring retro scan
   datetime  last_touch_time;
   bool      active;
};

static IMBTrendEvent g_imb_events[];
static IMBZone       g_imb_zones[];        // COMPLETE archive, including fills
static int           g_imb_active_indices[]; // only still-active zones are scanned
static int           g_imb_event_count=0;
static int           g_imb_zone_count=0;
static int           g_imb_active_count=0;
static int           g_imb_event_capacity=0;
static int           g_imb_zone_capacity=0;
static int           g_imb_active_capacity=0;
static int           g_imb_created_count=0;
static int           g_imb_updated_count=0;
static int           g_imb_filled_count=0;
static int           g_imb_touch_count=0;
static int           g_imb_return_touch_count=0;
static int           g_imb_retro_created_count=0;
static int           g_imb_duplicate_count=0;
// One chronological CopyRates() pass: each third-bar index uniquely identifies
// a 3-bar formation; bit 1=UP, bit 2=DOWN. Dedupe is O(1), not O(all zones).
static int           g_imb_seen_third[];

inline void IMB_ResetGlobals()
{
   ArrayFree(g_imb_events);
   ArrayFree(g_imb_zones);
   ArrayFree(g_imb_active_indices);
   ArrayFree(g_imb_seen_third);
   g_imb_event_count=0;
   g_imb_zone_count=0;
   g_imb_active_count=0;
   g_imb_event_capacity=0;
   g_imb_zone_capacity=0;
   g_imb_active_capacity=0;
   g_imb_created_count=0;
   g_imb_updated_count=0;
   g_imb_filled_count=0;
   g_imb_touch_count=0;
   g_imb_return_touch_count=0;
   g_imb_retro_created_count=0;
   g_imb_duplicate_count=0;
}

// Record REAL MTC/TC events independently of the possibly non-chronological
// recursive market-world traversal. Ignore duplicates on a replayed event.
inline void __IMB_RecordEvent(const bool is_mtc, const Direction direction,
                              const datetime mtc_time, const datetime event_time,
                              const datetime reference_time)
{
   if(event_time<=0 || mtc_time<=0) return;
   for(int k=0;k<g_imb_event_count;k++)
   {
      if(g_imb_events[k].is_mtc==is_mtc &&
         g_imb_events[k].mtc_time==mtc_time &&
         g_imb_events[k].time==event_time &&
         g_imb_events[k].direction==direction)
         return;
   }
   if(g_imb_event_count>=g_imb_event_capacity)
   {
      g_imb_event_capacity=(g_imb_event_capacity==0 ? 32 : g_imb_event_capacity*2);
      ArrayResize(g_imb_events,g_imb_event_capacity);
   }
   const int pos=g_imb_event_count++;
   g_imb_events[pos].time=event_time;
   g_imb_events[pos].mtc_time=mtc_time;
   g_imb_events[pos].direction=direction;
   g_imb_events[pos].is_mtc=is_mtc;
   g_imb_events[pos].reference_time=(reference_time>0 && reference_time<=mtc_time ?
                                     reference_time : mtc_time);
}

inline void IMB_RecordMTC(const Direction direction, const datetime mtc_time,
                          const datetime reference_time)
{
   __IMB_RecordEvent(true,direction,mtc_time,mtc_time,reference_time);
}

inline void IMB_RecordTC(const Direction direction,
                         const datetime mtc_time, const datetime confirmation_time,
                         const datetime reference_time)
{
   if(confirmation_time<=mtc_time) return;
   __IMB_RecordEvent(false,direction,mtc_time,confirmation_time,reference_time);
}

// Stable distinct colors cycle through five shades per direction. The zone ID
// is printed on EVERY label, so non-adjacent same-shade zones stay identifiable.
inline color __IMB_ZoneTone(const Direction direction, const int serial)
{
   const int shade=(serial-1)%5;
   if(direction==DIR_UP)
   {
      if(shade==0) return clrLimeGreen;
      if(shade==1) return clrAqua;
      if(shade==2) return clrMediumSeaGreen;
      if(shade==3) return clrGreenYellow;
      return clrSpringGreen;
   }
   if(shade==0) return clrTomato;
   if(shade==1) return clrGold;
   if(shade==2) return clrOrangeRed;
   if(shade==3) return clrCoral;
   return clrOrange;
}

// Extend five ACTUAL chart candles when they exist; at the dataset's far
// right edge use five slots of the selected M1/M15 chart timeframe.
inline datetime __IMB_FiveBarsForward(const MqlRates &rates[], const int n,
                                      const int origin, const int tf_seconds)
{
   if(origin+5<n) return rates[origin+5].time;
   return rates[origin].time+(datetime)(5*tf_seconds);
}

// Exact role is available on mouse hover even with many adjacent labels.
inline string __IMB_Tooltip(const IMBZone &zone, const string role,
                            const datetime time, const double price)
{
   const int digits=(int)SymbolInfoInteger(zone.symbol,SYMBOL_DIGITS);
   return "IMB "+zone.symbol+" | "+zone.tag+" | "+role+
          " | at "+TimeToString(time,TIME_DATE|TIME_MINUTES)+
          " | price="+DoubleToString(price,digits)+
          " | first="+TimeToString(zone.first_time,TIME_DATE|TIME_MINUTES)+
          " | reference="+TimeToString(zone.source_ref_time,TIME_DATE|TIME_MINUTES)+
          " | activated_TC="+TimeToString(zone.first_tc_time,TIME_DATE|TIME_MINUTES);
}

inline void __IMB_DrawText(const IMBZone &zone, const string suffix,
                            const datetime when, const double level,
                            const string message, const string tooltip,
                            const bool archival=false)
{
   if(!Markers_ShouldRender()) return;
   const string obj=__ScanPrefix()+zone.id+suffix;
   if(ObjectFind(0,obj)!=-1) ObjectDelete(0,obj);
   if(!ObjectCreate(0,obj,OBJ_TEXT,0,when,level))
   {
      if(InpDebugPrints) Print("[IMB] Unable to create label: ",obj);
      return;
   }
   ObjectSetString(0,obj,OBJPROP_TEXT,message);
   ObjectSetString(0,obj,OBJPROP_TOOLTIP,tooltip);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,(archival ? clrSilver : zone.tone));
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,obj,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);
   ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
}

inline void __IMB_DrawLevel(const IMBZone &zone, const string suffix,
                             const datetime from, const datetime to,
                             const double price, const string role,
                             const string visible_label, const bool is_base,
                             const int revision)
{
   if(!Markers_ShouldRender()) return;
   const string obj=__ScanPrefix()+zone.id+suffix;
   if(ObjectFind(0,obj)!=-1) ObjectDelete(0,obj);
   if(!ObjectCreate(0,obj,OBJ_TREND,0,from,price,to,price))
   {
      if(InpDebugPrints) Print("[IMB] Unable to create level: ",obj);
      return;
   }
   const string tip=__IMB_Tooltip(zone,role,from,price);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,zone.tone);
   ObjectSetInteger(0,obj,OBJPROP_STYLE,STYLE_DASH);
   // MT5 dash pattern is reliable at width 1; distinguish roles using labels.
   ObjectSetInteger(0,obj,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,obj,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,obj,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);
   ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,obj,OBJPROP_TOOLTIP,tip);

   double point=SymbolInfoDouble(zone.symbol,SYMBOL_POINT);
   if(point<=0) point=_Point;
   const double offset=MathMax(6.0*point,MathAbs(zone.edge-zone.base)*0.03);
   const bool up=(zone.direction==DIR_UP);
   // Base labels lie OUTSIDE the fixed boundary. Initial and updated edge
   // labels lie outside the moving boundary, with light ordinal staggering.
   double y=price;
   if(is_base)
      y+=(up ? -offset : offset);
   else
      y+=(up ? offset : -offset)+(up ? 1.0 : -1.0)*
         ((revision%3)*4.0*point);
   __IMB_DrawText(zone,suffix+"_LABEL",from,y,visible_label,tip);
}

// Only stale WaveBot IMB visuals are removed during a *full historical*
// rebuild. Never call this on a partial fill, full fill, or TC/MTC transition.
inline void IMB_DeletePreviousMarkers()
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      const string obj=ObjectName(0,i);
      if(StringLen(obj)<8 || StringSubstr(obj,0,1)!="S") continue;
      if(StringFind(obj,"_IMB_U_")>=0 || StringFind(obj,"_IMB_D_")>=0)
         ObjectDelete(0,obj);
   }
}

// Only SAME-DIRECTION TC registers partial encounters/updates. Physical FULL
// fills invalidate at any time, regardless of MTC/TC direction, as in the
// original immutable-base rule. A surviving zone can cross arbitrarily many
// opposite TCs and receive fresh RETURN HIT labels on a later matching TC.
inline void __IMB_UpdateExisting(const MqlRates &rates[], const int n,
                                  const int bar_index, const int tf_seconds,
                                  const Direction confirmed_direction,
                                  const datetime confirmed_tc)
{
   for(int a=g_imb_active_count-1;a>=0;a--)
   {
      const int z=g_imb_active_indices[a];
      if(!g_imb_zones[z].active ||
         rates[bar_index].time<=g_imb_zones[z].third_time ||
         rates[bar_index].time<=g_imb_zones[z].last_touch_time)
         continue;

      const bool up=(g_imb_zones[z].direction==DIR_UP);
      const double price=(up ? rates[bar_index].low : rates[bar_index].high);
      const bool fully_filled=(up ? price<=g_imb_zones[z].base
                                   : price>=g_imb_zones[z].base);
      const bool aligned=(confirmed_tc>0 &&
                          g_imb_zones[z].direction==confirmed_direction);
      const bool touched=(up ? price<=g_imb_zones[z].edge
                               : price>=g_imb_zones[z].edge);
      if(!aligned && !fully_filled) continue;
      if(!touched && !fully_filled) continue;

      // An off-direction full fill is still a REAL invalidation, but it must
      // not be reported as a matching-TC touch or change any partial edge.
      if(!aligned && fully_filled)
      {
         g_imb_zones[z].active=false;
         g_imb_zones[z].filled_time=rates[bar_index].time;
         g_imb_filled_count++;
         __IMB_DrawText(g_imb_zones[z],"_FILLED_LABEL",rates[bar_index].time,
                        g_imb_zones[z].base,g_imb_zones[z].tag+" FILLED",
                        __IMB_Tooltip(g_imb_zones[z],
                           "FULL FILL OUTSIDE MATCHING TC - ARCHIVED",
                           rates[bar_index].time,g_imb_zones[z].base),true);
         for(int t=a;t<g_imb_active_count-1;t++)
            g_imb_active_indices[t]=g_imb_active_indices[t+1];
         g_imb_active_count--;
         continue;
      }

      const bool is_return=(g_imb_zones[z].first_tc_time<confirmed_tc);
      const int encounter=++g_imb_zones[z].touch_count;
      g_imb_zones[z].last_touch_time=rates[bar_index].time;
      g_imb_touch_count++;
      if(is_return) g_imb_return_touch_count++;
      const string encounter_role=(is_return ? "RETURN TOUCH #" : "TOUCH #")+
                                  IntegerToString(encounter);
      const string encounter_label=g_imb_zones[z].tag+" "+
                                  (is_return ? "REHIT" : "HIT")+
                                  IntegerToString(encounter);
      double point=SymbolInfoDouble(g_imb_zones[z].symbol,SYMBOL_POINT);
      if(point<=0.0) point=_Point;
      const double text_y=price+(up ? -9.0 : 9.0)*point;
      __IMB_DrawText(g_imb_zones[z],"_HIT_"+IntegerToString(encounter),
                     rates[bar_index].time,text_y,encounter_label,
                     __IMB_Tooltip(g_imb_zones[z],encounter_role,
                                    rates[bar_index].time,price));

      if(fully_filled)
      {
         // Never destroy any drawn zone history, even at final invalidation.
         g_imb_zones[z].active=false;
         g_imb_zones[z].filled_time=rates[bar_index].time;
         g_imb_filled_count++;
         __IMB_DrawText(g_imb_zones[z],"_FILLED_LABEL",rates[bar_index].time,
                        g_imb_zones[z].base,g_imb_zones[z].tag+" FILLED",
                        __IMB_Tooltip(g_imb_zones[z],
                          "FULLY FILLED - ARCHIVED",rates[bar_index].time,
                          g_imb_zones[z].base),true);
         for(int t=a;t<g_imb_active_count-1;t++)
            g_imb_active_indices[t]=g_imb_active_indices[t+1];
         g_imb_active_count--;
         continue;
      }
      // Every deeper aligned-TC penetration gets a NEW five-candle dashed
      // edge; shallower touches have a hit label but keep the prior edge.
      const bool deeper=(up ? price<g_imb_zones[z].edge
                            : price>g_imb_zones[z].edge);
      if(!deeper) continue;
      g_imb_zones[z].edge=price;
      const int ordinal=g_imb_zones[z].edge_count;
      const string segment="_EDGE_"+IntegerToString(ordinal);
      const string role=(up ? "UPDATED TOP #" : "UPDATED BOTTOM #")+
                         IntegerToString(ordinal);
      __IMB_DrawLevel(g_imb_zones[z],segment,rates[bar_index].time,
                      __IMB_FiveBarsForward(rates,n,bar_index,tf_seconds),
                      g_imb_zones[z].edge,role,
                      g_imb_zones[z].tag+" "+(up ? "TOP" : "BOT")+
                      " UPD"+IntegerToString(ordinal),false,ordinal);
      g_imb_zones[z].edge_count++;
      g_imb_updated_count++;
   }
}

// Dedupe for another TC is indexed by chronological third-bar index in the
// sole sorted CopyRates() buffer. Archived and still-active zones both count.
inline bool __IMB_ValidThreeBars(const MqlRates &rates[],const int n,
                                 const int third,const Direction dir)
{
   if(third<2 || third>=n) return false;
   if(dir==DIR_UP)
      return (rates[third-1].close>rates[third-2].high &&
              rates[third].low>rates[third-2].high);
   return (rates[third-1].close<rates[third-2].low &&
           rates[third].high<rates[third-2].low);
}

inline void __IMB_Create(const Direction direction, const string sym,
                         const MqlRates &rates[], const int n,
                         const int first_index, const int third_index,
                         const int tf_seconds, const datetime activated_tc,
                         const datetime ref_time, const bool retrospective)
{
   if(g_imb_zone_count>=g_imb_zone_capacity)
   {
      g_imb_zone_capacity=(g_imb_zone_capacity==0 ? 32 : g_imb_zone_capacity*2);
      ArrayResize(g_imb_zones,g_imb_zone_capacity);
   }
   if(g_imb_active_count>=g_imb_active_capacity)
   {
      g_imb_active_capacity=(g_imb_active_capacity==0 ? 32 : g_imb_active_capacity*2);
      ArrayResize(g_imb_active_indices,g_imb_active_capacity);
   }
   const int z=g_imb_zone_count++;
   const bool up=(direction==DIR_UP);
   const int serial=g_imb_created_count+1;
   g_imb_zones[z].symbol=sym;
   g_imb_zones[z].serial=serial;
   g_imb_zones[z].tag=(up ? "U" : "D")+IntegerToString(serial,3,'0');
   // Short object names also accommodate broker-suffixed symbols and updates.
   g_imb_zones[z].id=(up ? "IMB_U_" : "IMB_D_")+sym+"_"+
                      IntegerToString(serial);
   g_imb_zones[z].tone=__IMB_ZoneTone(direction,serial);
   g_imb_zones[z].direction=direction;
   g_imb_zones[z].first_time=rates[first_index].time;
   g_imb_zones[z].third_time=rates[third_index].time;
   g_imb_zones[z].filled_time=0;
   g_imb_zones[z].base=(up ? rates[first_index].low : rates[first_index].high);
   g_imb_zones[z].edge=(up ? rates[third_index].low : rates[third_index].high);
   g_imb_zones[z].edge_count=1;
   g_imb_zones[z].touch_count=0;
   g_imb_zones[z].last_touch_time=0;
   g_imb_zones[z].first_tc_time=activated_tc;
   g_imb_zones[z].source_ref_time=ref_time;
   g_imb_zones[z].active=true;
   g_imb_active_indices[g_imb_active_count++]=z;

   __IMB_DrawLevel(g_imb_zones[z],"_BASE",rates[first_index].time,
                   __IMB_FiveBarsForward(rates,n,first_index,tf_seconds),
                   g_imb_zones[z].base,
                   (up ? "ORIGINAL FIRST-CANDLE LOW" : "ORIGINAL FIRST-CANDLE HIGH"),
                   g_imb_zones[z].tag+" "+(up ? "START LOW" : "START HIGH"),
                   true,0);
   __IMB_DrawLevel(g_imb_zones[z],"_EDGE_0",rates[third_index].time,
                   __IMB_FiveBarsForward(rates,n,third_index,tf_seconds),
                   g_imb_zones[z].edge,
                   (up ? "INITIAL TOP" : "INITIAL BOTTOM"),
                   g_imb_zones[z].tag+" "+(retrospective ? "RETRO " : "NEW ")+
                   (up ? "TOP" : "BOT"),
                   false,0);
   g_imb_created_count++;
   if(retrospective) g_imb_retro_created_count++;
}

// Register a complete three-candle pattern without stealing any candle from
// another possible pattern, and without cloning an existing historical zone.
inline void __IMB_TryCreate(const Direction dir, const string sym,
                            const MqlRates &rates[],const int n,
                            const int third,const int tf_seconds,
                            const datetime activated_tc,
                            const datetime ref_time,const bool retrospective)
{
   if(!__IMB_ValidThreeBars(rates,n,third,dir)) return;
   const int bit=(dir==DIR_UP ? 1 : 2);
   if((g_imb_seen_third[third] & bit)!=0)
   {
      g_imb_duplicate_count++;
      return;
   }
   g_imb_seen_third[third] |= bit;
   __IMB_Create(dir,sym,rates,n,third-2,third,tf_seconds,
                activated_tc,ref_time,retrospective);
}

// A reference-backfilled pattern has a historical formation time; check
// whether it had already been completely filled BEFORE TC. Complete fills
// invalidate independently of TC, while pre-TC PARTIAL contacts are not
// registered as aligned encounters. Preserve the pre-TC filled zone in the
// archive (no active zone can be resurrected by a subsequent TC).
inline void __IMB_CheckPreTCFullFill(const int z,
                                    const MqlRates &rates[],const int from_index,
                                    const int before_index)
{
   if(z<0 || z>=g_imb_zone_count || !g_imb_zones[z].active) return;
   const bool up=(g_imb_zones[z].direction==DIR_UP);
   for(int b=from_index;b<before_index;b++)
   {
      const bool filled=(up ? rates[b].low<=g_imb_zones[z].base
                            : rates[b].high>=g_imb_zones[z].base);
      if(!filled) continue;
      g_imb_zones[z].active=false;
      g_imb_zones[z].filled_time=rates[b].time;
      g_imb_filled_count++;
      __IMB_DrawText(g_imb_zones[z],"_FILLED_LABEL",rates[b].time,
                     g_imb_zones[z].base,g_imb_zones[z].tag+" FILLED",
                     __IMB_Tooltip(g_imb_zones[z],
                       "PRE-TC HISTORICAL FULL FILL - ARCHIVED",rates[b].time,
                       g_imb_zones[z].base),true);
      // Retro zones are appended to the END of the active-index array, so
      // remove the last entry in O(1), without rescanning old archives.
      if(g_imb_active_count>0 &&
         g_imb_active_indices[g_imb_active_count-1]==z)
         g_imb_active_count--;
      return;
   }
}

// Process MTC/TC events by candle time (the market scanner itself can rewind).
// On every TC, scan EVERY qualifying triple from its matching MTC reference
// origin, including those completed BEFORE the TC; activate them at TC. Do
// not backdate mitigation: by design encounters/invalidations are only
// registered while a same-direction TC is confirmed. All old valid zones
// remain alive through unrelated MTC/TC epochs, with immutable archive lines.
inline void IMB_RunConfirmedTrendScan(const string sym, const ENUM_TIMEFRAMES tf,
                                      const datetime from_time, const datetime to_time)
{
   if(g_imb_event_count<=0 || to_time<from_time) return;

   IMBTrendEvent events[];
   ArrayResize(events,g_imb_event_count);
   for(int i=0;i<g_imb_event_count;i++) events[i]=g_imb_events[i];

   // At identical time TC comes before MTC so the newer MTC wins.
   for(int i=1;i<g_imb_event_count;i++)
   {
      IMBTrendEvent temp=events[i];
      int j=i-1;
      while(j>=0 && (events[j].time>temp.time ||
           (events[j].time==temp.time && events[j].is_mtc && !temp.is_mtc)))
      {
         events[j+1]=events[j];
         j--;
      }
      events[j+1]=temp;
   }

   // The reference candle can precede the scan window; load real data for it.
   datetime load_from=from_time;
   for(int k=0;k<g_imb_event_count;k++)
      if(!events[k].is_mtc && events[k].reference_time>0 &&
         events[k].reference_time<load_from)
         load_from=events[k].reference_time;

   MqlRates rates[];
   ArrayFree(rates);
   const datetime extended_stop=to_time+(datetime)(7*86400);
   const int n=CopyRates(sym,tf,load_from,extended_stop,rates);
   if(n<=0)
   {
      if(InpDebugPrints) Print("[IMB] Rates unavailable for ",sym);
      return;
   }
   ArraySetAsSeries(rates,false);
   ArrayResize(g_imb_seen_third,n);
   ArrayInitialize(g_imb_seen_third,0);
   const int tf_seconds=PeriodSeconds(tf);
   int event_cursor=0;
   datetime active_mtc=0,active_tc=0,active_ref=0;
   Direction active_direction=DIR_UP;
   int retro_epochs=0;

   for(int i=0;i<n;i++)
   {
      if(rates[i].time>to_time) break;
      while(event_cursor<g_imb_event_count && events[event_cursor].time<=rates[i].time)
      {
         IMBTrendEvent e=events[event_cursor++];
         if(e.is_mtc)
         {
            active_mtc=e.mtc_time;
            active_direction=e.direction;
            active_tc=0;
            active_ref=(e.reference_time>0 && e.reference_time<=e.mtc_time ?
                        e.reference_time : e.mtc_time);
         }
         else if(e.mtc_time==active_mtc && e.direction==active_direction)
         {
            // TC superseded by a newer MTC on the same bar is not actionable.
            if(event_cursor<g_imb_event_count &&
               events[event_cursor].is_mtc &&
               events[event_cursor].time==e.time)
               continue;
            active_tc=e.time;
            if(e.reference_time>0 && e.reference_time<=active_mtc)
               active_ref=e.reference_time;
            if(active_ref<rates[0].time && InpDebugPrints)
               Print("[IMB] Missing earlier anchor history for ",sym,
                    " ref=",TimeToString(active_ref,TIME_DATE|TIME_MINUTES),
                    " first_loaded=",TimeToString(rates[0].time,TIME_DATE|TIME_MINUTES));
            // Backfill candidates whose FIRST candle is at/after the actual
            // reference origin, ending strictly BEFORE the confirmation bar.
            // No before-TC price action is silently treated as an aligned hit.
            int retro_in_epoch=0;
            int lo=0,hi=i-1,first=i;
            while(lo<=hi) // binary search: first loaded candle >= reference
            {
               const int mid=lo+(hi-lo)/2;
               if(rates[mid].time>=active_ref){first=mid;hi=mid-1;}
               else lo=mid+1;
            }
            for(int j=first+2;j<i;j++)
            {
               if(rates[j-2].time<active_ref) continue;
               if(!__IMB_ValidThreeBars(rates,n,j,active_direction)) continue;
               const int prior=g_imb_created_count;
               __IMB_TryCreate(active_direction,sym,rates,n,j,tf_seconds,
                               active_tc,active_ref,true);
               if(g_imb_created_count>prior)
               {
                  retro_in_epoch++;
                  __IMB_CheckPreTCFullFill(g_imb_zone_count-1,rates,j+1,i);
               }
            }
            retro_epochs++;
            if(InpDebugPrints)
               Print("[IMB] TC=",TimeToString(active_tc,TIME_DATE|TIME_MINUTES),
                     " ",(active_direction==DIR_UP ? "UP" : "DOWN"),
                     " ref_from=",TimeToString(active_ref,TIME_DATE|TIME_MINUTES),
                     " retro_new=",retro_in_epoch);
         }
      }

      // Global full-fill invalidations are ALWAYS checked; partial touches
      // are only registered under the corresponding confirmed TC.
      __IMB_UpdateExisting(rates,n,i,tf_seconds,active_direction,active_tc);
      if(active_tc<=0) continue;

      // Include triples which start at the reference BEFORE confirmation and
      // finish later; each candle can concurrently start unrelated patterns.
      if(i<2 || rates[i-2].time<active_ref) continue;
      __IMB_TryCreate(active_direction,sym,rates,n,i,tf_seconds,
                      active_tc,active_ref,false);
   }
   if(InpDebugPrints)
      Print("[IMB] ",sym," | created=",g_imb_created_count,
            " | reference-backfilled=",g_imb_retro_created_count,
            " | TC epochs=",retro_epochs,
            " | aligned touches=",g_imb_touch_count,
            " | return touches=",g_imb_return_touch_count,
            " | new edge levels=",g_imb_updated_count,
            " | archived filled=",g_imb_filled_count,
            " | active=",g_imb_active_count,
            " | total zone records=",g_imb_zone_count,
            " | reused historical triples=",g_imb_duplicate_count,
            " | trend events=",g_imb_event_count);
}

#endif // WAVEBOT_IMBALANCE_MQH
