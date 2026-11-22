//+------------------------------------------------------------------+
//| EA/tests/TickHistoryQualityPolicy.mq5                              |
//| Deterministic trade-tick ordering, duplicates and gap fixtures.    |
//+------------------------------------------------------------------+
#property strict
#include "../includes/Execution/TickHistoryQualityPolicy.mqh"
#include "TestHarness.mqh"

int failures=0;
void Expect(const bool condition,const string label)
  {
   if(!condition) { Print("FAIL: ",label); failures++; }
  }

void OnStart()
  {
   long first=0,last=0,maxGap=0,previous=0;
   int sameMillisecond=0;

   Expect(CTickHistoryQualityPolicy::Observe(1000,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"lower-bound trade timestamp accepted");
   previous=1000;
   Expect(first==1000 && last==1000,"first and last timestamps initialized");

   Expect(CTickHistoryQualityPolicy::Observe(1000,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"same-millisecond trade record accepted");
   previous=1000;
   Expect(sameMillisecond==1,"same-millisecond record counted without deduplication");

   Expect(CTickHistoryQualityPolicy::Observe(1900,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"large inter-trade gap is diagnostic, not rejected");
   previous=1900;
   Expect(maxGap==900,"maximum inter-trade gap measured in milliseconds");
   Expect(last==1900,"last timestamp advances after sparse interval");

   Expect(CTickHistoryQualityPolicy::Observe(2000,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"upper-bound trade timestamp accepted");
   previous=2000;

   Expect(!CTickHistoryQualityPolicy::Observe(999,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"timestamp before requested history range rejected");
   Expect(!CTickHistoryQualityPolicy::Observe(2001,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"timestamp after requested history range rejected");
   Expect(!CTickHistoryQualityPolicy::Observe(0,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"missing timestamp rejected");
   Expect(!CTickHistoryQualityPolicy::Observe(1999,1000,2000,previous,
      first,last,maxGap,sameMillisecond),"out-of-order timestamp rejected");

   PrintFormat("TickHistoryQualityPolicy tests: %d failure(s)",failures);
   MidasTestFinish("TickHistoryQualityPolicy-tests.txt",failures);
  }
//+------------------------------------------------------------------+
