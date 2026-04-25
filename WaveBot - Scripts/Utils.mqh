#ifndef WAVEBOT_UTILS_MQH
#define WAVEBOT_UTILS_MQH

// Utils.mqh — توابع کمکی عمومی
// نقش: ابزارهای کوچک و بدون حالت (مثل IsBullish/IsBearish و قالب‌دهی زمان) که در ماژول‌های مختلف استفاده می‌شوند.

inline bool IsBullish(const MqlRates &r){ return (r.close > r.open); }
inline bool IsBearish(const MqlRates &r){ return (r.close < r.open); }
inline string T(datetime t){ return TimeToString(t, TIME_DATE|TIME_MINUTES); }

#endif // WAVEBOT_UTILS_MQH

