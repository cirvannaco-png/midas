//+------------------------------------------------------------------+
//| Execution/TickHistoryQualityPolicy.mqh                            |
//| Deterministic chronology and coverage metrics for trade history.  |
//+------------------------------------------------------------------+
#ifndef MIDAS_TICKHISTORYQUALITYPOLICY_MQH
#define MIDAS_TICKHISTORYQUALITYPOLICY_MQH

class CTickHistoryQualityPolicy
  {
public:
   // Same-millisecond records are counted, not deduplicated. A long gap is
   // measured but never rejected by itself: illiquid symbols and closed
   // sessions legitimately have sparse trade prints.
   static bool Observe(const long timestampMsc,const long fromMsc,const long toMsc,
                       const long previousTimestampMsc,long &firstTimestampMsc,
                       long &lastTimestampMsc,long &maxGapMsc,
                       int &sameMillisecondRecords)
     {
      if(timestampMsc<=0 || fromMsc<=0 || toMsc<fromMsc ||
         timestampMsc<fromMsc || timestampMsc>toMsc ||
         (previousTimestampMsc>0 && timestampMsc<previousTimestampMsc))
         return false;

      if(firstTimestampMsc==0)
         firstTimestampMsc=timestampMsc;

      if(previousTimestampMsc>0)
        {
         if(timestampMsc==previousTimestampMsc)
            sameMillisecondRecords++;
         else
           {
            long gapMsc=timestampMsc-previousTimestampMsc;
            if(gapMsc>maxGapMsc)
               maxGapMsc=gapMsc;
           }
        }

      lastTimestampMsc=timestampMsc;
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
