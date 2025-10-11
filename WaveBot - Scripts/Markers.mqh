#ifndef WAVEBOT_MARKERS_MQH
#define WAVEBOT_MARKERS_MQH

void MarkV(const string name, const datetime t, const color col)
{
   if(!InpDrawMarkers) return;
   if(ObjectFind(0,name)!=-1) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
}

// --- Helpers to clear stale W2 markers for a given tag ---
void ClearIfExists(const string name)
{
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
}

void W2_ClearTag(const string tag)
{
   if(!InpDrawMarkers) return;
   ClearIfExists("W2_" + tag + "_C1");
   ClearIfExists("W2_" + tag + "_C2");
   ClearIfExists("W2_" + tag + "_C3");
   ClearIfExists("W2_" + tag + "_C4");   // ???: ???????? C4 ?????
}

#endif // WAVEBOT_MARKERS_MQH
