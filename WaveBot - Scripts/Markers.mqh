
#ifndef WAVEBOT_MARKERS_MQH
#define WAVEBOT_MARKERS_MQH

extern int g_scan_id;  // defined in WaveBot.mq5

// Optional extra namespace for parallel worlds (e.g., "MAJ", "MIN").
// Empty => legacy behavior (no extra namespace).
static string g_markers_ns = "";

// Preview mode is used by WorldManager while a MIN session is still open.
// In preview mode, chart objects stay silent.
// Bridge publication is still allowed for MIN-origin H4 signal on/off events,
// so the live M15 trigger engine can react immediately.
static bool   g_markers_preview_mode = false;

// set/get world namespace (used later by WorldManager)
inline void   Markers_SetNamespace(const string ns){ g_markers_ns = ns; }
inline string Markers_GetNamespace(){ return g_markers_ns; }

inline void Markers_SetPreviewMode(const bool enabled){ g_markers_preview_mode = enabled; }
inline bool Markers_IsPreviewMode(){ return g_markers_preview_mode; }
inline bool Markers_ShouldRender()
{
   if(!InpDrawMarkers) return false;
   if(g_markers_preview_mode) return false;
   return true;
}

// Scan prefix (unique per scan) + optional world namespace
inline string __ScanPrefix()
{
   if(g_markers_ns == "")
      return "S" + IntegerToString(g_scan_id) + "_";
   return "S" + IntegerToString(g_scan_id) + "_" + g_markers_ns + "_";
}

void MarkV(const string name, const datetime t, const color col)
{
   if(!Markers_ShouldRender()) return;
   const string full = __ScanPrefix() + name;
   if(ObjectFind(0,full)!=-1) ObjectDelete(0,full);
   ObjectCreate(0,full,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,full,OBJPROP_COLOR,col);
   ObjectSetInteger(0,full,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,full,OBJPROP_WIDTH,1);
}

// ماکر متنی روی نمودار (کنار کندل – بر اساس time و price)
void MarkCandleText(const string name,
                    const datetime t,
                    const double   price,
                    const string   text,
                    const color    col)
{
   if(!Markers_ShouldRender()) return;

   const string full = __ScanPrefix() + name;

   if(ObjectFind(0, full) != -1)
      ObjectDelete(0, full);

   if(!ObjectCreate(0, full, OBJ_TEXT, 0, t, price))
   {
      Print(__FUNCTION__,": ObjectCreate failed for ", full);
      return;
   }

   ObjectSetString (0, full, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, full, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, full, OBJPROP_FONTSIZE,  8);
   ObjectSetInteger(0, full, OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetInteger(0, full, OBJPROP_BACK,      false);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE,false);
}

void ClearIfExists(const string name)
{
   const string full = __ScanPrefix() + name;
   if(ObjectFind(0, full) != -1) ObjectDelete(0, full);
}

void W2_ClearTag(const string tag)
{
   if(!InpDrawMarkers) return;
   ClearIfExists("W2_" + tag + "_C1");
   ClearIfExists("W2_" + tag + "_C2");
   ClearIfExists("W2_" + tag + "_C3");
   ClearIfExists("W2_" + tag + "_C4");
}

// پاک‌سازی همه‌ی مارکرهای موج در همین اسکن (W2/W3/HW/HWBB/SW) –
// مارکرهای Shadow Breaker/temp/invalidator حذف نمی‌شوند.
inline void Markers_Clear_Waves_CurrentScan()
{
   const string p   = __ScanPrefix();
   const int    plen= StringLen(p);

   for(int i=ObjectsTotal(0)-1; i>=0; --i)
   {
      string on = ObjectName(0,i);
      if(on=="" || StringLen(on)<plen) continue;
      if(StringSubstr(on,0,plen)!=p)   continue;

      string tail = StringSubstr(on, plen);
      bool isWave =
         (StringFind(tail,"W2_")   == 0) ||
         (StringFind(tail,"W3_")   == 0) ||
         (StringFind(tail,"HW_")   == 0) ||
         (StringFind(tail,"HWBB_") == 0) ||
         (StringFind(tail,"SW_")   == 0);

      if(isWave) ObjectDelete(0,on);
   }
}

#endif // WAVEBOT_MARKERS_MQH

