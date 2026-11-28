//+------------------------------------------------------------------+
//| EA/tests/SessionFilterUtc.mq5                                     |
//| Deterministic UTC offset and London/New York DST classification. |
//+------------------------------------------------------------------+
#property strict
#include "../includes/Core/SessionFilter.mqh"
#include "TestHarness.mqh"

int failures=0;
void Expect(const bool condition,const string label)
  {
   if(!condition) { Print("FAIL: ",label); failures++; }
  }

void OnStart()
  {
   datetime serverTime=D'2026.01.15 15:00';
   Expect(CSessionFilter::ServerTimeToGMT(serverTime,180)==D'2026.01.15 12:00',
          "UTC+3 broker server time converts to UTC");
   Expect(CSessionFilter::ServerTimeToGMT(serverTime,-300)==D'2026.01.15 20:00',
          "UTC-5 broker server time converts to UTC");
   Expect(CSessionFilter::ServerTimeToGMT(serverTime,99999)==0,
          "missing broker UTC offset remains unknown");
   Expect(CSessionFilter::ServerTimeToGMT(serverTime,841)==0,
          "out-of-range broker UTC offset remains unknown");

   Expect(CSessionFilter::SessionAtGMT(D'2026.01.15 04:00')==SESSION_TOKYO,
          "Tokyo session in winter UTC");
   Expect(CSessionFilter::SessionAtGMT(D'2026.01.15 09:00')==SESSION_LONDON,
          "London winter session");
   Expect(CSessionFilter::SessionAtGMT(D'2026.01.15 14:00')==SESSION_LONDON_NY_OVERLAP,
          "London/New York winter overlap");
   Expect(CSessionFilter::SessionAtGMT(D'2026.01.15 18:00')==SESSION_NEWYORK,
          "New York winter session");
   Expect(CSessionFilter::SessionAtGMT(D'2026.01.15 23:00')==SESSION_DEAD,
          "dead hours remain separate from active sessions");
   Expect(CSessionFilter::SessionAtGMT(D'2026.03.15 12:30')==SESSION_LONDON_NY_OVERLAP,
          "US DST begins before EU DST; overlap shifts independently");
   Expect(CSessionFilter::SessionAtGMT(D'2026.04.15 07:30')==SESSION_LONDON,
          "London open follows EU DST");
   Expect(CSessionFilter::SessionAtGMT(D'2026.04.15 16:30')==SESSION_NEWYORK,
          "London close follows EU DST while New York remains open");
   Expect(CSessionFilter::SessionAtGMT(D'2026.11.15 12:30')==SESSION_LONDON,
          "EU and US standard-time windows are restored independently");
   Expect(CSessionFilter::SessionAtGMT(0)==SESSION_UNKNOWN,
          "invalid UTC timestamp is explicitly unknown");

   PrintFormat("SessionFilterUtc tests: %d failure(s)",failures);
   MidasTestFinish("SessionFilterUtc-tests.txt",failures);
  }
//+------------------------------------------------------------------+
