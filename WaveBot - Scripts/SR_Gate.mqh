// WaveBot/SR_Gate.mqh
#ifndef WAVEBOT_SR_GATE_MQH
#define WAVEBOT_SR_GATE_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>  // برای __ScanPrefix()
#include <WaveBot/SR_Mitigator.mqh>   // NEW: reset states on cleanup
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>

// -1: both allowed, 0: UP only, 1: DOWN only
static int g_sr_allowed = -1;

// ------------------------------
// Context snapshot for SR_Gate (direction allow state)
// ------------------------------
struct SRGateContext
{
   int allowed;   // -1 both, 0 UP, 1 DOWN
};

inline void SRGate_ContextInit(SRGateContext &ctx)      { ctx.allowed = -1; }
inline void SRGate_ContextExport(SRGateContext &ctx)    { ctx.allowed = g_sr_allowed; }
inline void SRGate_ContextImport(const SRGateContext &ctx){ g_sr_allowed = ctx.allowed; }
inline void SRGate_ResetGlobals(){ g_sr_allowed = -1; }
// آیا الان در دنیای ماژور هستیم؟ (namespace خالی یا MAJ)
inline bool __SR_IsMajorWorld()
{
   const string ns = Markers_GetNamespace();
   return (ns=="" || ns=="MAJ");
}

inline void SR_AllowBoth(){ g_sr_allowed = -1; }
inline void SR_AllowOnly(const Direction dir)
{
   g_sr_allowed = (dir==DIR_UP ? 0 : 1);

   // جلوگیری از «first mitigator» دیرهنگام/اشتباه از سمت مقابل پس از رجیم‌چنج
   if(dir==DIR_UP)  SRMIT_Reset_DN();
   else             SRMIT_Reset_UP();

   // *** NEW: در دنیای MAJOR فقط ExtLQ های مربوط به روند فعلی معتبر باشند
   // تا ExtLQ های باقی‌مانده از روند مخالف، باعث تشخیص HWBB/مسابقه‌ی اشتباه نشوند.
   if(__SR_IsMajorWorld())
   {
      if(dir==DIR_UP)
         ExtLQ_Down_ClearAll(true); // حذف کامل ExtLQ نزولیِ قبلی
      else
         ExtLQ_ClearAll(true);      // حذف کامل ExtLQ صعودیِ قبلی
   }
}


inline bool SR_ShouldProcess_UP(){   return (g_sr_allowed==-1 || g_sr_allowed==0); }
inline bool SR_ShouldProcess_DOWN(){ return (g_sr_allowed==-1 || g_sr_allowed==1); }

// حذف همه آبجکت‌های Strong Range روی چارت (نمایش SR)
// حذف همه آبجکت‌های Strong Range فقط برای اسکن فعلی
inline void SR_DeleteAllObjects()
{
   const long   chart_id = 0;
   const string prefix   = __ScanPrefix();
   const int    plen     = StringLen(prefix);

   const int total = ObjectsTotal(chart_id);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(chart_id, i);
      if(name == NULL || name == "") continue;

      if(plen > 0)
      {
         if(StringLen(name) < plen)        continue;
         if(StringSubstr(name, 0, plen) != prefix) continue;
      }

      string tail = (plen > 0 ? StringSubstr(name, plen) : name);
      bool is_sr = (StringFind(tail, "SR_")==0) ||
                   (StringFind(tail, "STRONG_RANGE_")==0) ||
                   (StringFind(tail, "StrongRange_")==0) ||
                   (StringFind(tail, "SRANGE_")==0);
      if(!is_sr)
      {
         if(StringFind(tail, "SR_")>=0 || StringFind(tail, "STRONG_RANGE")>=0 ||
            StringFind(tail, "StrongRange")>=0 || StringFind(tail, "SRANGE")>=0)
            is_sr = true;
      }
      if(is_sr) ObjectDelete(chart_id, name);
   }

   // NEW: همگام با پاک کردن آبجکت‌های SR، وضعیت Mitigator را هم صفر کن
   SRMIT_Reset_UP();
   SRMIT_Reset_DN();
   SR_GoozBaghali_ResetAll();
}
#endif // WAVEBOT_SR_GATE_MQH
