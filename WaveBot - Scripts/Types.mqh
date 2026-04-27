
#ifndef WAVEBOT_TYPES_MQH
#define WAVEBOT_TYPES_MQH

// Types.mqh — انواع داده و قراردادهای مشترک
// نقش: تعریف ساختارهای خروجی/ورودی مشترک بین ماژول‌ها (فعلاً W2Result برای موج۲).
// بدون وابستگی اجرایی؛ فقط قرارداد نوع داده برای استفاده‌ی ماژول‌ها.

struct W2Result
{
   int  c1, c2, c3, c4;  // c4 ممکن است -1 باشد
   int  end_index;       // (c4>=0? c4 : c3)
   bool ok;
};

// جهت اسکن/مود
enum Direction
{
   DIR_UP   = 0,
   DIR_DOWN = 1
};

#endif // WAVEBOT_TYPES_MQH

