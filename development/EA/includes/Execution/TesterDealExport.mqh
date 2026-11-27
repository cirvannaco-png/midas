//+------------------------------------------------------------------+
//| Execution/TesterDealExport.mqh                                   |
//| Test-only export of native MT5 broker-deal history.              |
//| This component is inert outside MQL_TESTER.                       |
//+------------------------------------------------------------------+
#ifndef MIDAS_TESTERDEALEXPORT_MQH
#define MIDAS_TESTERDEALEXPORT_MQH

struct TesterDealExportRow
  {
   ulong deal_id;
   ulong order_id;
   ulong position_id;
   datetime deal_time;
   string symbol;
   string entry;
   double volume;
   double price;
   double profit;
   double commission;
   double swap;
   double fee;
   long decision_id;
   string strategy;
   string regime;
   string direction;
   string session;
   double initial_stop_price;
   double initial_stop_distance_points;
   string deal_reason;
   double spread_points_observed;
   bool spread_observed;
   double requested_price;
   double slippage_points;
   double slippage_cost_cash;
   bool slippage_known;
  };

struct TesterPositionAttribution
  {
   ulong position_id;
   long decision_id;
   string strategy;
   string regime;
   string direction;
   string session;
   double initial_stop_price;
   double initial_stop_distance_points;
  };

class CTesterDealExport
  {
private:
   bool   m_enabled;
   bool   m_writeFailed;
   string m_symbol;
   string m_runId;
   string m_dealsName;
   string m_openName;
   ulong  m_magic;
   double m_spreadSum;
   double m_spreadMax;
   ulong  m_spreadSamples;
   double m_point;
   double m_tickSize;
   double m_tickValueProfit;
   double m_tickValueLoss;
   double m_initialBalance;
   string m_currency;
   string m_server;
   int    m_serverUtcOffsetMinutes;
   long   m_leverage;
   long   m_terminalBuild;
   long   m_fillMode;
   TesterDealExportRow m_rows[];
   ulong  m_seenDeals[];
   ulong  m_riskPositions[];
   double m_positionRiskCash[];
   TesterPositionAttribution m_attributions[];

   int AttributionIndex(const ulong positionId) const
     {
      for(int i=0;i<ArraySize(m_attributions);i++)
         if(m_attributions[i].position_id==positionId) return i;
      return -1;
     }

   void RememberAttribution(const ulong positionId,const long decisionId,
                            const string strategy,const string regime,
                            const string direction,const string session,
                            const double initialStopPrice,const double initialStopDistancePoints)
     {
      if(positionId==0) return;
      int index=AttributionIndex(positionId);
      if(index<0)
        {
         index=ArraySize(m_attributions);
         if(ArrayResize(m_attributions,index+1)!=index+1)
           {
            m_writeFailed=true;
            return;
           }
         m_attributions[index].position_id=positionId;
         m_attributions[index].decision_id=decisionId;
         m_attributions[index].strategy=(StringLen(strategy)>0?strategy:"UNTAGGED");
         m_attributions[index].regime=(StringLen(regime)>0?regime:"UNTAGGED");
         m_attributions[index].direction=(StringLen(direction)>0?direction:"UNTAGGED");
         m_attributions[index].session=(StringLen(session)>0?session:"UNTAGGED");
         m_attributions[index].initial_stop_price=initialStopPrice;
         m_attributions[index].initial_stop_distance_points=initialStopDistancePoints;
         return;
        }
      if(m_attributions[index].strategy=="CONFLICT" ||
         m_attributions[index].regime=="CONFLICT") return;
      bool conflict=(decisionId>0 && m_attributions[index].decision_id>0 &&
                     decisionId!=m_attributions[index].decision_id) ||
                    (StringLen(strategy)>0 && strategy!="UNTAGGED" &&
                     m_attributions[index].strategy!="UNTAGGED" &&
                     strategy!=m_attributions[index].strategy) ||
                    (StringLen(regime)>0 && regime!="UNTAGGED" &&
                     m_attributions[index].regime!="UNTAGGED" &&
                     regime!=m_attributions[index].regime) ||
                    (StringLen(direction)>0 && direction!="UNTAGGED" &&
                     m_attributions[index].direction!="UNTAGGED" &&
                     direction!=m_attributions[index].direction);
      if(conflict)
        {
         m_attributions[index].decision_id=0;
         m_attributions[index].strategy="CONFLICT";
         m_attributions[index].regime="CONFLICT";
         return;
        }
      if(m_attributions[index].decision_id<=0 && decisionId>0)
         m_attributions[index].decision_id=decisionId;
      if(m_attributions[index].strategy=="UNTAGGED" && StringLen(strategy)>0 && strategy!="UNTAGGED")
         m_attributions[index].strategy=strategy;
      if(m_attributions[index].regime=="UNTAGGED" && StringLen(regime)>0 && regime!="UNTAGGED")
         m_attributions[index].regime=regime;
      if(m_attributions[index].direction=="UNTAGGED" && StringLen(direction)>0 && direction!="UNTAGGED")
         m_attributions[index].direction=direction;
      if(m_attributions[index].session=="UNTAGGED" && StringLen(session)>0 && session!="UNTAGGED")
         m_attributions[index].session=session;
      if(m_attributions[index].initial_stop_price<=0.0 && initialStopPrice>0.0)
         m_attributions[index].initial_stop_price=initialStopPrice;
      if(m_attributions[index].initial_stop_distance_points<=0.0 && initialStopDistancePoints>0.0)
         m_attributions[index].initial_stop_distance_points=initialStopDistancePoints;
     }

   string SafeName(string value)
     {
      StringReplace(value,"/","_");
      StringReplace(value,"\\","_");
      StringReplace(value,":","_");
      StringReplace(value,"*","_");
      StringReplace(value,"?","_");
      StringReplace(value,"\"","_");
      StringReplace(value,"<","_");
      StringReplace(value,">","_");
      StringReplace(value,"|","_");
      StringReplace(value," ","_");
      if(StringLen(value)==0) value="manual";
      if(StringLen(value)>32) value=StringSubstr(value,0,32);
      return value;
     }

   string JsonEscape(string value) const
     {
      StringReplace(value,"\\","\\\\");
      StringReplace(value,"\"","\\\"");
      StringReplace(value,"\r","\\r");
      StringReplace(value,"\n","\\n");
      StringReplace(value,"\t","\\t");
      return value;
     }

   string TimeIsoWithOffset(datetime value) const
     {
      // Tester deal timestamps use the historical broker server's wall clock.
      // They are not intrinsically UTC; preserve the verified server offset.
      string stamp=TimeToString(value,TIME_DATE|TIME_SECONDS);
      StringReplace(stamp,".","-");
      StringReplace(stamp," ","T");
      int absoluteOffset=m_serverUtcOffsetMinutes;
      string sign="+";
      if(absoluteOffset<0)
        {
         sign="-";
         absoluteOffset=-absoluteOffset;
        }
      string zone=StringFormat("%s%02d:%02d",sign,absoluteOffset/60,absoluteOffset%60);
      return stamp+zone;
     }

   bool ValidateHistoryCoverage(int &expectedDeals,int &missingDeals)
     {
      expectedDeals=0;
      missingDeals=0;
      if(!HistorySelect(0,TimeCurrent()))
        {
         m_writeFailed=true;
         missingDeals=1;
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=history_select error=%d",GetLastError());
         return false;
        }

      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         ulong dealId=HistoryDealGetTicket(i);
         if(dealId==0)
           {
            m_writeFailed=true;
            missingDeals++;
            continue;
           }
         if(HistoryDealGetString(dealId,DEAL_SYMBOL)!=m_symbol) continue;
         if((ulong)HistoryDealGetInteger(dealId,DEAL_MAGIC)!=m_magic) continue;

         expectedDeals++;
         if(!DealWasSeen(dealId))
            missingDeals++;
        }

      int recordedDeals=ArraySize(m_rows);
      if(recordedDeals!=expectedDeals)
        {
         if(recordedDeals>expectedDeals)
            missingDeals+=recordedDeals-expectedDeals;
         m_writeFailed=true;
        }
      if(missingDeals>0)
         m_writeFailed=true;

      return (!m_writeFailed && missingDeals==0 && recordedDeals==expectedDeals);
     }

   bool WriteDealsFile()
     {
      int handle=FileOpen(m_dealsName,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(handle==INVALID_HANDLE)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=deals file=%s error=%d",
                     m_dealsName,GetLastError());
         m_writeFailed=true;
         return false;
        }

      bool ok=true;
      ResetLastError();
      if(FileWrite(handle,"position_id","time","entry","volume","profit","commission",
                   "swap","fee","risk_cash","lane","deal_id","order_id","symbol",
                   "decision_id","strategy","regime","direction","session","initial_stop_price",
                   "initial_stop_distance_points","deal_reason","spread_points_observed",
                   "spread_observed","requested_price","slippage_points",
                   "slippage_cost_cash","slippage_known")==0)
         ok=false;

      for(int i=0;i<ArraySize(m_rows);i++)
        {
         TesterDealExportRow row=m_rows[i];
         if(FileWrite(handle,
                      IntegerToString((long)row.position_id),
                      TimeIsoWithOffset(row.deal_time),
                      row.entry,
                      DoubleToString(row.volume,8),
                      DoubleToString(row.profit,8),
                      DoubleToString(row.commission,8),
                      DoubleToString(row.swap,8),
                      DoubleToString(row.fee,8),
                      DoubleToString(RiskCash(row.position_id),8),
                      "EA",
                      IntegerToString((long)row.deal_id),
                      IntegerToString((long)row.order_id),
                      row.symbol,
                      IntegerToString(row.decision_id),
                      row.strategy,
                      row.regime,
                      row.direction,
                      row.session,
                      (row.initial_stop_price>0.0?DoubleToString(row.initial_stop_price,10):""),
                      (row.initial_stop_distance_points>0.0?DoubleToString(row.initial_stop_distance_points,8):""),
                      row.deal_reason,
                      (row.spread_observed?DoubleToString(row.spread_points_observed,8):""),
                      (row.spread_observed?"true":"false"),
                      (row.slippage_known?DoubleToString(row.requested_price,10):""),
                      (row.slippage_known?DoubleToString(row.slippage_points,8):""),
                      (row.slippage_known?DoubleToString(row.slippage_cost_cash,8):""),
                      (row.slippage_known?"true":"false"))==0)
            ok=false;
        }

      FileFlush(handle);
      int writeError=GetLastError();
      FileClose(handle);
      if(!ok || writeError!=0)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=deals_write file=%s error=%d",
                     m_dealsName,writeError);
         m_writeFailed=true;
         return false;
        }
      return true;
     }

   bool WriteOpenPositions(int &exportedCount)
     {
      exportedCount=0;
      int handle=FileOpen(m_openName,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(handle==INVALID_HANDLE)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=open_positions file=%s error=%d",
                     m_openName,GetLastError());
         m_writeFailed=true;
         return false;
        }

      bool ok=true;
      ResetLastError();
      if(FileWrite(handle,"position_id")==0)
         ok=false;
      for(int p=PositionsTotal()-1;p>=0;p--)
        {
         ulong ticket=PositionGetTicket(p);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(positionId==0) continue;
         if(FileWrite(handle,IntegerToString((long)positionId))==0)
            ok=false;
         else
            exportedCount++;
        }

      FileFlush(handle);
      int writeError=GetLastError();
      FileClose(handle);
      if(!ok || writeError!=0)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=open_positions_write file=%s error=%d",
                     m_openName,writeError);
         m_writeFailed=true;
         return false;
        }
      return true;
     }

   bool WriteMetadata(const bool complete,const int historyExpectedDeals,
                      const int historyMissingDeals,const int openPositionsExported,
                      const bool dealsWritten,const bool openPositionsWritten)
     {
      string filename="MidasTesterMeta_"+m_runId+".json";
      int handle=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=metadata file=%s error=%d",
                     filename,GetLastError());
         return false;
        }
      double cashPerPoint=0.0;
      if(m_point>0.0 && m_tickSize>0.0 && m_tickValueLoss>0.0)
         cashPerPoint=m_tickValueLoss*m_point/m_tickSize;
      double averageSpread=(m_spreadSamples>0 ? m_spreadSum/(double)m_spreadSamples : 0.0);
      int recordedDeals=ArraySize(m_rows);
      int exportedDeals=(dealsWritten?recordedDeals:0);
      double dealProfitTotal=0.0;
      double dealCommissionTotal=0.0;
      double dealSwapTotal=0.0;
      double dealFeeTotal=0.0;
      for(int i=0;i<exportedDeals;i++)
        {
         dealProfitTotal+=m_rows[i].profit;
         dealCommissionTotal+=m_rows[i].commission;
         dealSwapTotal+=m_rows[i].swap;
         dealFeeTotal+=m_rows[i].fee;
        }
      double dealNetCashflowTotal=dealProfitTotal+dealCommissionTotal+
                                   dealSwapTotal+dealFeeTotal;
      string status=(complete?"complete":"incomplete");
      string json=StringFormat(
         "{\"run_id\":\"%s\",\"symbol\":\"%s\",\"server\":\"%s\","
         "\"account_currency\":\"%s\",\"leverage\":%I64d,"
         "\"initial_balance\":%.8f,\"terminal_build\":%I64d,"
         "\"point\":%.10f,\"tick_size\":%.10f,\"tick_value\":%.8f,"
         "\"tick_value_profit\":%.8f,\"tick_value_loss\":%.8f,"
         "\"cash_per_point_per_lot\":%.8f,\"spread_points_mean\":%.8f,"
         "\"spread_points_max\":%.8f,\"spread_samples\":%I64u,"
         "\"fill_mode\":%I64d,\"server_utc_offset_minutes\":%d,"
         "\"timestamp_basis\":\"broker_wall_clock_with_explicit_offset\","
         "\"export_status\":\"%s\",\"history_expected_deals\":%d,"
         "\"history_recorded_deals\":%d,\"history_missing_deals\":%d,"
         "\"deals_exported\":%d,\"open_positions_exported\":%d,"
         "\"deal_profit_total\":%.8f,\"deal_commission_total\":%.8f,"
         "\"deal_swap_total\":%.8f,\"deal_fee_total\":%.8f,"
         "\"deal_net_cashflow_total\":%.8f,"
         "\"deals_file_written\":%s,\"open_positions_file_written\":%s}",
         JsonEscape(m_runId),JsonEscape(m_symbol),JsonEscape(m_server),JsonEscape(m_currency),
         m_leverage,m_initialBalance,m_terminalBuild,m_point,m_tickSize,m_tickValueLoss,
         m_tickValueProfit,m_tickValueLoss,cashPerPoint,averageSpread,m_spreadMax,m_spreadSamples,m_fillMode,m_serverUtcOffsetMinutes,
         status,historyExpectedDeals,recordedDeals,historyMissingDeals,exportedDeals,
         (openPositionsWritten?openPositionsExported:0),
         dealProfitTotal,dealCommissionTotal,dealSwapTotal,dealFeeTotal,dealNetCashflowTotal,
         (dealsWritten?"true":"false"),(openPositionsWritten?"true":"false"));

      ResetLastError();
      uint written=FileWriteString(handle,json);
      FileFlush(handle);
      int writeError=GetLastError();
      FileClose(handle);
      if(written==0 || writeError!=0)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=metadata_write file=%s bytes=%u error=%d",
                     filename,written,writeError);
         return false;
        }
      return true;
     }

   string EntryName(const ENUM_DEAL_ENTRY entry) const
     {
      if(entry==DEAL_ENTRY_IN) return "IN";
      if(entry==DEAL_ENTRY_OUT) return "OUT";
      if(entry==DEAL_ENTRY_OUT_BY) return "OUT_BY";
      if(entry==DEAL_ENTRY_INOUT) return "INOUT";
      return "UNKNOWN";
     }

   int RiskIndex(const ulong positionId) const
     {
      for(int i=0;i<ArraySize(m_riskPositions);i++)
         if(m_riskPositions[i]==positionId) return i;
      return -1;
     }

   void AddEntryRisk(const ulong positionId,const double riskCash)
     {
      if(positionId==0 || !MathIsValidNumber(riskCash) || riskCash<=0.0)
        {
         m_writeFailed=true;
         return;
        }
      int index=RiskIndex(positionId);
      if(index<0)
        {
         index=ArraySize(m_riskPositions);
         if(ArrayResize(m_riskPositions,index+1)!=index+1)
           {
            m_writeFailed=true;
            return;
           }
         if(ArrayResize(m_positionRiskCash,index+1)!=index+1)
           {
            ArrayResize(m_riskPositions,index);
            m_writeFailed=true;
            return;
           }
         m_riskPositions[index]=positionId;
         m_positionRiskCash[index]=0.0;
        }
      m_positionRiskCash[index]+=riskCash;
     }

   double RiskCash(const ulong positionId) const
     {
      int index=RiskIndex(positionId);
      return index>=0 ? m_positionRiskCash[index] : 0.0;
     }

   bool DealWasSeen(const ulong dealId) const
     {
      for(int i=0;i<ArraySize(m_seenDeals);i++)
         if(m_seenDeals[i]==dealId) return true;
      return false;
     }

public:
   void Init(const string runId,const string symbol,const ulong magic,const bool enabled,
             const int serverUtcOffsetMinutes)
     {
      bool validOffset=(serverUtcOffsetMinutes>=-840 && serverUtcOffsetMinutes<=840);
      m_serverUtcOffsetMinutes=serverUtcOffsetMinutes;
      m_enabled=(enabled && (bool)MQLInfoInteger(MQL_TESTER) && validOffset);
      m_writeFailed=false;
      if(enabled && (bool)MQLInfoInteger(MQL_TESTER) && !validOffset)
         PrintFormat("MIDAS_TEST_EXPORT_DISABLED reason=INVALID_SERVER_UTC_OFFSET value=%d; set the verified broker server offset for this test window.",serverUtcOffsetMinutes);
      m_symbol=symbol;
      m_magic=magic;
      m_runId=SafeName(runId+"_"+IntegerToString((long)GetTickCount()));
      m_dealsName="MidasTesterDeals_"+m_runId+".csv";
      m_openName="MidasTesterOpen_"+m_runId+".csv";
      m_spreadSum=0.0;
      m_spreadMax=0.0;
      m_spreadSamples=0;
      m_point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      m_tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      m_tickValueProfit=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT);
      m_tickValueLoss=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
      m_initialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_currency=AccountInfoString(ACCOUNT_CURRENCY);
      m_server=AccountInfoString(ACCOUNT_SERVER);
      m_leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);
      m_terminalBuild=TerminalInfoInteger(TERMINAL_BUILD);
      m_fillMode=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      bool arraysReady=true;
      if(ArrayResize(m_rows,0)!=0) arraysReady=false;
      if(ArrayResize(m_seenDeals,0)!=0) arraysReady=false;
      if(ArrayResize(m_riskPositions,0)!=0) arraysReady=false;
      if(ArrayResize(m_positionRiskCash,0)!=0) arraysReady=false;
      if(ArrayResize(m_attributions,0)!=0) arraysReady=false;
      if(!arraysReady) m_writeFailed=true;
      if(m_enabled)
         PrintFormat("MIDAS_TEST_EXPORT_READY run=%s symbol=%s magic=%I64u",
                     m_runId,m_symbol,m_magic);
     }

   bool Enabled() const { return m_enabled; }

   void ObserveSpread(const string symbol)
     {
      if(!m_enabled) return;
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick)) return;
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0 || tick.ask<=0.0 || tick.bid<=0.0 || tick.ask<tick.bid) return;
      double spread=(tick.ask-tick.bid)/point;
      if(!MathIsValidNumber(spread) || spread<0.0) return;
      m_spreadSum+=spread;
      if(spread>m_spreadMax) m_spreadMax=spread;
      m_spreadSamples++;
     }

   bool Record(const ulong dealId,const ulong orderId,const ulong positionId,
               const datetime dealTime,const string symbol,
               const ENUM_DEAL_ENTRY entry,const double volume,const double price,
               const double profit,const double commission,const double swap,
               const double fee,const double entryRiskCash,
               const long decisionId,const string strategy,const string regime,
               const string direction,const string session,
               const double initialStopPrice,const double initialStopDistancePoints,
               const string dealReason,const double spreadPointsObserved,const bool spreadObserved,
               const double requestedPrice,const double slippagePoints,
               const double slippageCostCash,const bool slippageKnown)
     {
      if(!m_enabled) return true;
      if(dealId==0 || orderId==0 || positionId==0 || symbol=="")
        {
         m_writeFailed=true;
         return false;
        }
      if(DealWasSeen(dealId)) return true;
      double values[]={volume,price,profit,commission,swap,fee,entryRiskCash};
      for(int i=0;i<ArraySize(values);i++)
         if(!MathIsValidNumber(values[i]))
           {
            m_writeFailed=true;
            return false;
           }
      if(volume<=0.0 || price<=0.0)
        {
         m_writeFailed=true;
         return false;
        }
      if(spreadObserved && (!MathIsValidNumber(spreadPointsObserved) || spreadPointsObserved<0.0))
        {
         m_writeFailed=true;
         return false;
        }
      if(slippageKnown &&
         (!MathIsValidNumber(requestedPrice) || requestedPrice<=0.0 ||
          !MathIsValidNumber(slippagePoints) || !MathIsValidNumber(slippageCostCash) ||
          slippageCostCash<0.0))
        {
         m_writeFailed=true;
         return false;
        }

      int attribution=AttributionIndex(positionId);
      if(entry==DEAL_ENTRY_IN)
         RememberAttribution(positionId,decisionId,strategy,regime,direction,session,
                             initialStopPrice,initialStopDistancePoints);
      else if(entry==DEAL_ENTRY_INOUT)
        {
         // A netting reversal preserves DEAL_POSITION_ID while changing exposure.
         // One stable position ID can therefore span multiple decision lineages.
         if(attribution<0)
            RememberAttribution(positionId,0,"CONFLICT","CONFLICT");
         else
           {
            m_attributions[attribution].decision_id=0;
            m_attributions[attribution].strategy="CONFLICT";
            m_attributions[attribution].regime="CONFLICT";
            m_attributions[attribution].direction="CONFLICT";
            m_attributions[attribution].session="CONFLICT";
           }
        }
      else if(attribution<0 && decisionId>0)
         RememberAttribution(positionId,decisionId,strategy,regime);
      attribution=AttributionIndex(positionId);
      long resolvedDecisionId=decisionId;
      string resolvedStrategy=strategy;
      string resolvedRegime=regime;
      string resolvedDirection=direction;
      string resolvedSession=session;
      double resolvedInitialStopPrice=initialStopPrice;
      double resolvedInitialStopDistancePoints=initialStopDistancePoints;
      if(attribution>=0)
        {
         // Once a netting reversal has made this identifier ambiguous, do not
         // allow a later IN fill to overwrite the conflict with a new label.
         if(m_attributions[attribution].strategy=="CONFLICT" ||
            m_attributions[attribution].regime=="CONFLICT")
           {
            resolvedDecisionId=0;
            resolvedStrategy="CONFLICT";
            resolvedRegime="CONFLICT";
            resolvedDirection="CONFLICT";
            resolvedSession="CONFLICT";
           }
         else
           {
            if(resolvedDecisionId<=0) resolvedDecisionId=m_attributions[attribution].decision_id;
            if(StringLen(resolvedStrategy)==0 || resolvedStrategy=="UNTAGGED")
               resolvedStrategy=m_attributions[attribution].strategy;
            if(StringLen(resolvedRegime)==0 || resolvedRegime=="UNTAGGED")
               resolvedRegime=m_attributions[attribution].regime;
            if(StringLen(resolvedDirection)==0 || resolvedDirection=="UNTAGGED")
               resolvedDirection=m_attributions[attribution].direction;
            if(StringLen(resolvedSession)==0 || resolvedSession=="UNTAGGED")
               resolvedSession=m_attributions[attribution].session;
            if(resolvedInitialStopPrice<=0.0)
               resolvedInitialStopPrice=m_attributions[attribution].initial_stop_price;
            if(resolvedInitialStopDistancePoints<=0.0)
               resolvedInitialStopDistancePoints=m_attributions[attribution].initial_stop_distance_points;
           }
        }
      if(StringLen(resolvedStrategy)==0) resolvedStrategy="UNTAGGED";
      if(StringLen(resolvedRegime)==0) resolvedRegime="UNTAGGED";
      if(StringLen(resolvedDirection)==0) resolvedDirection="UNTAGGED";
      if(StringLen(resolvedSession)==0) resolvedSession="UNTAGGED";

      int seen=ArraySize(m_seenDeals);
      if(ArrayResize(m_seenDeals,seen+1)!=seen+1)
        {
         m_writeFailed=true;
         return false;
        }
      m_seenDeals[seen]=dealId;
      if(entry==DEAL_ENTRY_IN) AddEntryRisk(positionId,entryRiskCash);

      int count=ArraySize(m_rows);
      if(ArrayResize(m_rows,count+1)!=count+1)
        {
         m_writeFailed=true;
         ArrayResize(m_seenDeals,seen);
         return false;
        }
      m_rows[count].deal_id=dealId;
      m_rows[count].order_id=orderId;
      m_rows[count].position_id=positionId;
      m_rows[count].deal_time=dealTime;
      m_rows[count].symbol=symbol;
      m_rows[count].entry=EntryName(entry);
      m_rows[count].volume=volume;
      m_rows[count].price=price;
      m_rows[count].profit=profit;
      m_rows[count].commission=commission;
      m_rows[count].swap=swap;
      m_rows[count].fee=fee;
      m_rows[count].decision_id=resolvedDecisionId;
      m_rows[count].strategy=resolvedStrategy;
      m_rows[count].regime=resolvedRegime;
      m_rows[count].direction=resolvedDirection;
      m_rows[count].session=resolvedSession;
      m_rows[count].initial_stop_price=resolvedInitialStopPrice;
      m_rows[count].initial_stop_distance_points=resolvedInitialStopDistancePoints;
      m_rows[count].deal_reason=(StringLen(dealReason)>0?dealReason:"UNKNOWN");
      m_rows[count].spread_points_observed=(spreadObserved?spreadPointsObserved:0.0);
      m_rows[count].spread_observed=spreadObserved;
      m_rows[count].requested_price=(slippageKnown?requestedPrice:0.0);
      m_rows[count].slippage_points=(slippageKnown?slippagePoints:0.0);
      m_rows[count].slippage_cost_cash=(slippageKnown?slippageCostCash:0.0);
      m_rows[count].slippage_known=slippageKnown;
      return true;
     }

   void Finalize()
     {
      if(!m_enabled) return;

      int expectedDeals=0;
      int missingDeals=0;
      bool historyComplete=ValidateHistoryCoverage(expectedDeals,missingDeals);
      bool dealsWritten=WriteDealsFile();
      int openPositionsExported=0;
      bool openPositionsWritten=WriteOpenPositions(openPositionsExported);
      bool exportComplete=(historyComplete && dealsWritten && openPositionsWritten && !m_writeFailed);
      bool metadataWritten=WriteMetadata(exportComplete,expectedDeals,missingDeals,
                                         openPositionsExported,dealsWritten,openPositionsWritten);

      if(exportComplete && metadataWritten)
         PrintFormat("MIDAS_TEST_EXPORT_COMPLETE run=%s deals=%d open_positions=%d deals_file=%s open_file=%s",
                     m_runId,ArraySize(m_rows),openPositionsExported,m_dealsName,m_openName);
      else
         PrintFormat("MIDAS_TEST_EXPORT_INCOMPLETE run=%s history_expected=%d history_recorded=%d history_missing=%d deals_written=%s open_positions_written=%s metadata_written=%s",
                     m_runId,expectedDeals,ArraySize(m_rows),missingDeals,
                     (dealsWritten?"true":"false"),(openPositionsWritten?"true":"false"),
                     (metadataWritten?"true":"false"));
     }
  };

#endif
//+------------------------------------------------------------------+
