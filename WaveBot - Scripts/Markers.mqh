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

#endif // WAVEBOT_MARKERS_MQH
