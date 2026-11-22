//+------------------------------------------------------------------+
//| EA/tests/PipCalculatorGeometry.mq5                               |
//| Deterministic broker price-geometry and tick-value fixtures.     |
//+------------------------------------------------------------------+
#property strict

#include "../includes/Core/PipCalculator.mqh"
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

   PrintFormat("PipCalculatorGeometry tests: %d failure(s)",failures);
   MidasTestFinish("PipCalculatorGeometry-tests.txt",failures);
  }
//+------------------------------------------------------------------+
