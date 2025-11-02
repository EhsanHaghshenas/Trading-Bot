#ifndef WAVEBOT_MARKERS_MQH
#define WAVEBOT_MARKERS_MQH

extern int g_scan_id;  // defined in WaveBot.mq5
inline string __ScanPrefix(){ return "S"+IntegerToString(g_scan_id)+"_"; }

void MarkV(const string name, const datetime t, const color col)
{
   if(!InpDrawMarkers) return;
   const string full = __ScanPrefix() + name;        // NEW: namespaced
   if(ObjectFind(0,full)!=-1) ObjectDelete(0,full);
   ObjectCreate(0,full,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,full,OBJPROP_COLOR,col);
   ObjectSetInteger(0,full,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,full,OBJPROP_WIDTH,1);
}

void ClearIfExists(const string name)
{
   const string full = __ScanPrefix() + name;        // NEW: namespaced
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

#endif // WAVEBOT_MARKERS_MQH
