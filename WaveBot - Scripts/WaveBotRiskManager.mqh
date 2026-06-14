#ifndef WAVEBOT_RISK_MANAGER_MQH
#define WAVEBOT_RISK_MANAGER_MQH

#include <Trade/Trade.mqh>

// ============================================================================
// WaveBotRiskManager.mqh
// Central account-level risk guard for the Central Multi-Symbol EA.
// Phase-1 policy:
//   - One central EA can scan several symbols.
//   - All symbols share the same max-open-trades limit.
//   - Default is one open WaveBot trade across the whole account.
//   - The module is intentionally independent from the wave/trigger scanners.
// ============================================================================

#define WBRM_DEFAULT_MAGIC_BASE 260600

struct WBRMDecision
{
   bool   allowed;
   string reason;
   int    open_total;
   int    open_same_symbol;
   double margin_level;
   double equity;
   double balance;
};

inline void WBRM_ClearDecision(WBRMDecision &d)
{
   d.allowed          = false;
   d.reason           = "UNSET";
   d.open_total       = 0;
   d.open_same_symbol = 0;
   d.margin_level     = 0.0;
   d.equity           = 0.0;
   d.balance          = 0.0;
}

inline string WBRM_SanitizeSymbol(const string sym)
{
   string s = sym;
   StringReplace(s, ".", "_");
   StringReplace(s, "#", "_");
   StringReplace(s, "/", "_");
   StringReplace(s, "\\", "_");
   StringReplace(s, ":", "_");
   return s;
}

inline int WBRM_SymbolCode(const string sym)
{
   string s = WBRM_SanitizeSymbol(sym);
   int h = 0;
   for(int i=0; i<StringLen(s); ++i)
      h = (h * 31 + StringGetCharacter(s, i)) % 9000;
   return h;
}

inline long WBRM_MagicForSymbol(const string sym, const int strategy_code=15)
{
   return (long)(WBRM_DEFAULT_MAGIC_BASE + (strategy_code * 10000) + WBRM_SymbolCode(sym));
}

inline bool WBRM_IsWaveBotMagic(const long magic)
{
   return (magic >= WBRM_DEFAULT_MAGIC_BASE && magic < (WBRM_DEFAULT_MAGIC_BASE + 999999));
}

inline int WBRM_CountOpenWaveBotPositions(const string symbol_filter="")
{
   int count = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(!WBRM_IsWaveBotMagic(magic)) continue;

      string psym = PositionGetString(POSITION_SYMBOL);
      if(symbol_filter != "" && psym != symbol_filter) continue;
      count++;
   }
   return count;
}

inline bool WBRM_CanOpenTrade(const string symbol,
                              const int max_open_total,
                              const int max_open_per_symbol,
                              const double max_margin_usage_pct,
                              WBRMDecision &decision)
{
   WBRM_ClearDecision(decision);
   decision.equity       = AccountInfoDouble(ACCOUNT_EQUITY);
   decision.balance      = AccountInfoDouble(ACCOUNT_BALANCE);
   decision.margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   decision.open_total   = WBRM_CountOpenWaveBotPositions("");
   decision.open_same_symbol = WBRM_CountOpenWaveBotPositions(symbol);

   int max_total = max_open_total;
   if(max_total < 1) max_total = 1;

   int max_sym = max_open_per_symbol;
   if(max_sym < 1) max_sym = 1;

   if(decision.open_total >= max_total)
   {
      decision.allowed = false;
      decision.reason  = "CENTRAL_MAX_OPEN_TRADES_REACHED";
      return false;
   }

   if(decision.open_same_symbol >= max_sym)
   {
      decision.allowed = false;
      decision.reason  = "SYMBOL_MAX_OPEN_TRADES_REACHED";
      return false;
   }

   if(max_margin_usage_pct > 0.0)
   {
      double margin = AccountInfoDouble(ACCOUNT_MARGIN);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double used_pct = 0.0;
      if(equity > 0.0)
         used_pct = (margin / equity) * 100.0;

      if(used_pct >= max_margin_usage_pct)
      {
         decision.allowed = false;
         decision.reason  = "CENTRAL_MARGIN_USAGE_LIMIT_REACHED";
         return false;
      }
   }

   decision.allowed = true;
   decision.reason  = "OK";
   return true;
}

#endif // WAVEBOT_RISK_MANAGER_MQH
