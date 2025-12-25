#ifndef WAVEBOT_RUNTIME_MQH
#define WAVEBOT_RUNTIME_MQH

// Runtime scan context (symbol/timeframe) so nested modules never rely on static inputs like InpTF
// - Set once at the start of every API scan via WBRT_Set(sym,tf)
// - Read via WBRT_Symbol()/WBRT_TF() inside modules (RaceCoordinator, WorldManager, ...)

static string          g_wbrt_symbol = "";
static ENUM_TIMEFRAMES g_wbrt_tf     = PERIOD_CURRENT;

inline void WBRT_Set(const string sym, const ENUM_TIMEFRAMES tf)
{
   g_wbrt_symbol = sym;
   g_wbrt_tf     = tf;
}

inline string WBRT_Symbol()
{
   if(g_wbrt_symbol != "") return g_wbrt_symbol;
   return _Symbol;
}

inline ENUM_TIMEFRAMES WBRT_TF()
{
   if(g_wbrt_tf != PERIOD_CURRENT) return g_wbrt_tf;
   return (ENUM_TIMEFRAMES)Period();
}

#endif // WAVEBOT_RUNTIME_MQH
