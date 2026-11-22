//+------------------------------------------------------------------+
//| Execution/BrokerQuoteValidator.mqh                               |
//| Deterministic quote integrity gates shared by all entry routes.   |
//+------------------------------------------------------------------+
#ifndef MIDAS_BROKERQUOTEVALIDATOR_MQH
#define MIDAS_BROKERQUOTEVALIDATOR_MQH

class CBrokerQuoteValidator
  {
public:
   static bool IsTimestampFresh(const datetime serverNow,const datetime tickTime,
                                const int maxAgeSeconds)
     {
      if(serverNow<=0 || tickTime<=0 || maxAgeSeconds<=0) return false;
      long age=(long)serverNow-(long)tickTime;
      return age>=0 && age<=(long)maxAgeSeconds;
     }

   static bool Validate(const double bid,const double ask,const double point,
                        const datetime serverNow,const datetime tickTime,
                        const int maxAgeSeconds,const int maxSpreadPoints,
                        const bool isBuy,double &referencePrice,double &spreadPoints)
     {
      referencePrice=0.0;
      spreadPoints=0.0;
      if(!MathIsValidNumber(bid) || !MathIsValidNumber(ask) ||
         !MathIsValidNumber(point) || bid<=0.0 || ask<=0.0 ||
         point<=0.0 || ask<bid || maxSpreadPoints<0 ||
         !IsTimestampFresh(serverNow,tickTime,maxAgeSeconds)) return false;
      double spread=(ask-bid)/point;
      if(!MathIsValidNumber(spread) || spread<0.0 ||
         (maxSpreadPoints>0 && spread>(double)maxSpreadPoints)) return false;
      referencePrice=isBuy ? ask : bid;
      spreadPoints=spread;
      return true;
     }
  };
#endif
//+------------------------------------------------------------------+
