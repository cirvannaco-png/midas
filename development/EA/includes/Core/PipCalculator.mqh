//+------------------------------------------------------------------+
//|                                          Core/PipCalculator.mqh   |
//+------------------------------------------------------------------+
#ifndef PIPCALCULATOR_MQH
#define PIPCALCULATOR_MQH

// A pip is a display convention for FX, not a universal price unit.
// For non-FX instruments the returned point-scaled unit is informational;
// execution and risk logic must use tick size / OrderCalcProfit instead.
class CPipCalculator
  {
public:
   static bool       ValidPriceGeometry(const int digits,const double point)
     {
      return (digits>=0 && digits<=8 &&
              MathIsValidNumber(point) && point>0.0);
     }

   static double     PipSizeFromSpec(const int digits,const double point)
     {
      if(!ValidPriceGeometry(digits,point))
         return 0.0;
      double pip=(digits==3 || digits==5) ? point*10.0 : point;
      return MathIsValidNumber(pip) && pip>0.0 ? pip : 0.0;
     }

   static double     PipSize(string symbol)
     {
      long digits=0;
      double point=0.0;
      if(!SymbolInfoInteger(symbol,SYMBOL_DIGITS,digits) ||
         !SymbolInfoDouble(symbol,SYMBOL_POINT,point))
         return 0.0;
      return PipSizeFromSpec((int)digits,point);
     }

   static double     PointSize(string symbol)
     {
      double point=0.0;
      if(!SymbolInfoDouble(symbol,SYMBOL_POINT,point) ||
         !MathIsValidNumber(point) || point<=0.0)
         return 0.0;
      return point;
     }

   static double     Pips(string symbol,double priceDistance)
     {
      double pip=PipSize(symbol);
      if(pip<=0.0 || !MathIsValidNumber(priceDistance))
         return 0.0;
      return MathAbs(priceDistance)/pip;
     }

   static double     Points(string symbol,double priceDistance)
     {
      double point=PointSize(symbol);
      if(point<=0.0 || !MathIsValidNumber(priceDistance))
         return 0.0;
      return MathAbs(priceDistance)/point;
     }

   // The caller must choose the direction: some instruments expose
   // asymmetric profit and loss tick values. No synthetic fallback is used.
   static double     PipValueFromSpec(const double pipSize,
                                      const double tickSize,
                                      const double directionalTickValue,
                                      const double lots)
     {
      if(!MathIsValidNumber(pipSize) || pipSize<=0.0 ||
         !MathIsValidNumber(tickSize) || tickSize<=0.0 ||
         !MathIsValidNumber(directionalTickValue) || directionalTickValue<=0.0 ||
         !MathIsValidNumber(lots) || lots<=0.0)
         return 0.0;
      double value=(pipSize/tickSize)*directionalTickValue*lots;
      return MathIsValidNumber(value) ? value : 0.0;
     }

   // Convert aggregate price-distance x lots into account-currency stop risk.
   // Stop risk must use the broker's loss-side tick value, never the generic or
   // profit-side value: some instruments expose asymmetric directional values.
   static double     MonetaryLossRiskFromSpec(const double riskLotsDistance,
                                               const double tickSize,
                                               const double lossTickValue)
     {
      if(!MathIsValidNumber(riskLotsDistance) || riskLotsDistance<=0.0 ||
         !MathIsValidNumber(tickSize) || tickSize<=0.0 ||
         !MathIsValidNumber(lossTickValue) || lossTickValue<=0.0)
         return 0.0;
      double risk=(riskLotsDistance/tickSize)*lossTickValue;
      return MathIsValidNumber(risk) && risk>0.0 ? risk : 0.0;
     }

   static double     PipValue(string symbol,double lots,bool forProfit=true)
     {
      double pip=PipSize(symbol);
      double tickSize=0.0;
      double tickValue=0.0;
      if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE,tickSize))
         return 0.0;
      ENUM_SYMBOL_INFO_DOUBLE property=forProfit
                                       ? SYMBOL_TRADE_TICK_VALUE_PROFIT
                                       : SYMBOL_TRADE_TICK_VALUE_LOSS;
      if(!SymbolInfoDouble(symbol,property,tickValue) ||
         !MathIsValidNumber(tickValue) || tickValue<=0.0)
         return 0.0;
      return PipValueFromSpec(pip,tickSize,tickValue,lots);
     }

   static string     FormatDistance(string symbol,double priceDistance)
     {
      return StringFormat("%.1f pips / %.0f pts",
                          Pips(symbol,priceDistance),
                          Points(symbol,priceDistance));
     }
  };
#endif
//+------------------------------------------------------------------+

