//+------------------------------------------------------------------+
//| EA/tests/BrokerQuoteValidator.mq5                                 |
//| Deterministic quote freshness, sanity and spread policy fixtures. |
//+------------------------------------------------------------------+
#property strict
#include "../includes/Execution/BrokerQuoteValidator.mqh"
#include "TestHarness.mqh"

int failures=0;
void Expect(const bool condition,const string label)
  {
   if(!condition) { Print("FAIL: ",label); failures++; }
  }
void ExpectNear(const double actual,const double expected,const double epsilon,const string label)
  {
   if(!MathIsValidNumber(actual) || MathAbs(actual-expected)>epsilon)
     { PrintFormat("FAIL: %s actual=%.8f expected=%.8f",label,actual,expected); failures++; }
  }
void OnStart()
  {
   double reference=0.0,spread=0.0;
   Expect(CBrokerQuoteValidator::IsTimestampFresh(1000,995,10),"fresh quote accepted");
   Expect(!CBrokerQuoteValidator::IsTimestampFresh(1000,989,10),"stale quote rejected");
   Expect(!CBrokerQuoteValidator::IsTimestampFresh(1000,1001,10),"future quote timestamp rejected");
   Expect(!CBrokerQuoteValidator::IsTimestampFresh(1000,0,10),"missing quote timestamp rejected");
   Expect(!CBrokerQuoteValidator::IsTimestampFresh(1000,995,0),"disabled freshness gate rejected");

   Expect(CBrokerQuoteValidator::Validate(1.1000,1.1002,0.0001,1000,995,10,3,true,reference,spread),"valid BUY quote accepted");
   ExpectNear(reference,1.1002,1e-10,"BUY uses ask");
   ExpectNear(spread,2.0,1e-10,"spread points calculated from point size");
   Expect(CBrokerQuoteValidator::Validate(1.1000,1.1002,0.0001,1000,995,10,3,false,reference,spread),"valid SELL quote accepted");
   ExpectNear(reference,1.1000,1e-10,"SELL uses bid");
   Expect(!CBrokerQuoteValidator::Validate(1.1002,1.1000,0.0001,1000,995,10,3,true,reference,spread),"crossed market rejected");
   Expect(!CBrokerQuoteValidator::Validate(0.0,1.1002,0.0001,1000,995,10,3,true,reference,spread),"missing bid rejected");
   Expect(!CBrokerQuoteValidator::Validate(1.1000,1.1002,0.0,1000,995,10,3,true,reference,spread),"invalid point rejected");
   Expect(!CBrokerQuoteValidator::Validate(1.1000,1.1005,0.0001,1000,995,10,3,true,reference,spread),"excessive spread rejected");
   Expect(CBrokerQuoteValidator::Validate(1.1000,1.1005,0.0001,1000,995,10,0,true,reference,spread),"zero max spread disables only spread cap");

   PrintFormat("BrokerQuoteValidator tests: %d failure(s)",failures);
   MidasTestFinish("BrokerQuoteValidator-tests.txt",failures);
  }
//+------------------------------------------------------------------+
