//+------------------------------------------------------------------+
//| EA/tests/PipCalculatorGeometry.mq5                               |
//| Deterministic broker price-geometry and tick-value fixtures.     |
//+------------------------------------------------------------------+
#property strict

#include "../includes/Core/PipCalculator.mqh"
#include "../includes/Execution/PriceGridNormalizer.mqh"
#include "TestHarness.mqh"

int failures=0;

void Expect(const bool condition,const string label)
  {
   if(!condition)
     {
      Print("FAIL: ",label);
      failures++;
     }
  }

void ExpectNear(const double actual,const double expected,const double epsilon,const string label)
  {
   if(!MathIsValidNumber(actual) || MathAbs(actual-expected)>epsilon)
     {
      PrintFormat("FAIL: %s actual=%.12f expected=%.12f",label,actual,expected);
      failures++;
     }
  }

void OnStart()
  {
   // Common FX geometry across broker precision conventions.
   ExpectNear(CPipCalculator::PipSizeFromSpec(5,0.00001),0.0001,1e-12,"5-digit FX pip");
   ExpectNear(CPipCalculator::PipSizeFromSpec(3,0.001),0.01,1e-12,"3-digit JPY pip");
   ExpectNear(CPipCalculator::PipSizeFromSpec(4,0.0001),0.0001,1e-12,"4-digit FX pip");
   ExpectNear(CPipCalculator::PipSizeFromSpec(2,0.01),0.01,1e-12,"2-digit price point convention");

   // Missing, zero, negative, NaN and impossible precision must fail closed.
   Expect(CPipCalculator::PipSizeFromSpec(5,0.0)==0.0,"zero point rejected");
   Expect(CPipCalculator::PipSizeFromSpec(5,-0.00001)==0.0,"negative point rejected");
   Expect(CPipCalculator::PipSizeFromSpec(9,0.00001)==0.0,"unsupported digits rejected");
   Expect(CPipCalculator::PipSizeFromSpec(5,DBL_MAX)==0.0,"overflowing pip geometry rejected");

   // Directional tick values are not interchangeable.
   ExpectNear(CPipCalculator::PipValueFromSpec(0.0001,0.00001,1.20,1.0),12.0,1e-10,"profit-side tick value");
   ExpectNear(CPipCalculator::PipValueFromSpec(0.0001,0.00001,0.80,1.0),8.0,1e-10,"loss-side tick value");
   Expect(CPipCalculator::PipValueFromSpec(0.0001,0.0,1.0,1.0)==0.0,"missing tick size rejected");
   Expect(CPipCalculator::PipValueFromSpec(0.0001,0.00001,0.0,1.0)==0.0,"missing directional tick value rejected");
   Expect(CPipCalculator::PipValueFromSpec(0.0001,0.00001,1.0,0.0)==0.0,"zero lot size rejected");

   // Live R-value denominator must use loss-side tick value, not generic/profit value.
   ExpectNear(CPipCalculator::MonetaryLossRiskFromSpec(0.002,0.00001,0.80),160.0,1e-10,"asymmetric loss-side monetary risk");
   ExpectNear(CPipCalculator::MonetaryLossRiskFromSpec(0.002,0.00001,1.20),240.0,1e-10,"profit-side value would produce a different denominator");
   Expect(CPipCalculator::MonetaryLossRiskFromSpec(0.002,0.00001,0.0)==0.0,"missing loss tick value fails closed");
   Expect(CPipCalculator::MonetaryLossRiskFromSpec(0.002,0.0,0.80)==0.0,"missing tick size fails closed for R-value");
   Expect(CPipCalculator::MonetaryLossRiskFromSpec(DBL_MAX,0.00001,DBL_MAX)==0.0,"overflowing monetary risk fails closed");

   // Non-decimal tick grids: indices/CFDs and instruments with coarse ticks.
   double normalized=0.0;
   Expect(NormalizePriceToTickGrid(100.13,0.25,2,true,normalized),"index tick-grid round-up succeeds");
   ExpectNear(normalized,100.25,1e-10,"index tick-grid round-up");
   Expect(NormalizePriceToTickGrid(100.13,0.25,2,false,normalized),"index tick-grid round-down succeeds");
   ExpectNear(normalized,100.00,1e-10,"index tick-grid round-down");
   Expect(NormalizePriceToTickGrid(1.234,0.05,2,true,normalized),"coarse metal tick-grid round-up succeeds");
   ExpectNear(normalized,1.25,1e-10,"coarse metal tick-grid round-up");
   Expect(NormalizePriceToTickGrid(1.234,0.05,2,false,normalized),"coarse metal tick-grid round-down succeeds");
   ExpectNear(normalized,1.20,1e-10,"coarse metal tick-grid round-down");
   Expect(NormalizePriceToTickGrid(1.23456,0.00001,5,true,normalized),"FX tick-grid normalization succeeds");
   ExpectNear(normalized,1.23456,1e-10,"FX tick-grid exact price");
   Expect(!NormalizePriceToTickGrid(100.13,0.0,2,true,normalized),"missing tick grid rejected");

   PrintFormat("PipCalculatorGeometry tests: %d failure(s)",failures);
   MidasTestFinish("PipCalculatorGeometry-tests.txt",failures);
  }
//+------------------------------------------------------------------+

