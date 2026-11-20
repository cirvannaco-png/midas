//+------------------------------------------------------------------+
//| BrokerSpecSnapshot.mq5                                           |
//| Read-only export of the connected MT5 account and symbol contract|
//| No orders are submitted and no account number/name is exported.  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input string InpCaptureSymbol = "XAUUSD";      // Exact Market Watch symbol, including any suffix
input string InpCaptureTag    = "ICMarketsKE"; // Descriptive label only; not used for broker identification

string g_capture_symbol = "";

string SafeFileToken(string value)
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
   if(StringLen(value)==0) value="capture";
   return value;
  }

string Stamp(datetime value)
  {
   string result=TimeToString(value,TIME_DATE|TIME_SECONDS);
   StringReplace(result,".","-");
   StringReplace(result," ","T");
   return result;
  }

void WriteRow(const int handle,const string key,const string value,
              const string unit,const string note="")
  {
   FileWrite(handle,key,value,unit,note);
  }

void WriteDoubleProperty(const int handle,const string key,
                         const ENUM_SYMBOL_INFO_DOUBLE property,const string unit)
  {
   double value=0.0;
   ResetLastError();
   if(!SymbolInfoDouble(g_capture_symbol,property,value))
     {
      int error=GetLastError();
      WriteRow(handle,key,"UNAVAILABLE",unit,StringFormat("SymbolInfoDouble error %d",error));
      return;
     }
   WriteRow(handle,key,DoubleToString(value,10),unit,"");
  }

void WriteIntegerProperty(const int handle,const string key,
                          const ENUM_SYMBOL_INFO_INTEGER property,const string unit)
  {
   long value=0;
   ResetLastError();
   if(!SymbolInfoInteger(g_capture_symbol,property,value))
     {
      int error=GetLastError();
      WriteRow(handle,key,"UNAVAILABLE",unit,StringFormat("SymbolInfoInteger error %d",error));
      return;
     }
   WriteRow(handle,key,IntegerToString(value),unit,"");
  }

void WriteStringProperty(const int handle,const string key,
                         const ENUM_SYMBOL_INFO_STRING property)
  {
   string value="";
   ResetLastError();
   if(!SymbolInfoString(g_capture_symbol,property,value))
     {
      int error=GetLastError();
      WriteRow(handle,key,"UNAVAILABLE","",StringFormat("SymbolInfoString error %d",error));
      return;
     }
   WriteRow(handle,key,value,"","");
  }

void OnStart()
  {
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      Print("BrokerSpecSnapshot: run this script on a connected demo terminal, not inside Strategy Tester.");
      return;
     }

   g_capture_symbol=InpCaptureSymbol;
   if(StringLen(g_capture_symbol)==0)
     {
      Print("BrokerSpecSnapshot: InpCaptureSymbol is required.");
      return;
     }

   if(!SymbolSelect(g_capture_symbol,true))
     {
      PrintFormat("BrokerSpecSnapshot: cannot select exact symbol '%s'; check its Market Watch name.",g_capture_symbol);
      return;
     }

   MqlTick tick;
   bool has_tick=SymbolInfoTick(g_capture_symbol,tick);
   double point=0.0;
   SymbolInfoDouble(g_capture_symbol,SYMBOL_POINT,point);

   string filename=StringFormat("MidasBrokerSpec_%s_%s_%I64d.csv",
                                SafeFileToken(InpCaptureTag),
                                SafeFileToken(g_capture_symbol),
                                (long)TimeLocal());
   int handle=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("BrokerSpecSnapshot: FileOpen failed; error=%d",GetLastError());
      return;
     }

   FileWrite(handle,"field","value","unit","notes");
   WriteRow(handle,"capture_purpose","read_only_broker_and_symbol_specification","","No trading actions are performed.");
   WriteRow(handle,"capture_tag",InpCaptureTag,"","Label only; verify broker identity using account_company and account_server.");
   WriteRow(handle,"account_company",AccountInfoString(ACCOUNT_COMPANY),"","");
   WriteRow(handle,"account_server",AccountInfoString(ACCOUNT_SERVER),"","");
   WriteRow(handle,"account_currency",AccountInfoString(ACCOUNT_CURRENCY),"","");
   WriteRow(handle,"account_leverage",IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)),"ratio","");
   WriteRow(handle,"account_margin_mode",IntegerToString(AccountInfoInteger(ACCOUNT_MARGIN_MODE)),"enum","");
   WriteRow(handle,"terminal_build",IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)),"build","");
   WriteRow(handle,"symbol",g_capture_symbol,"","");
   WriteRow(handle,"server_time_current",Stamp(TimeCurrent()),"broker clock","Latest quote time; not a UTC timestamp.");
   WriteRow(handle,"server_time_trade_server",Stamp(TimeTradeServer()),"broker clock","Estimated server clock; not historical timezone proof.");
   WriteRow(handle,"pc_time_gmt",Stamp(TimeGMT()),"PC-derived GMT","Depends on local PC clock and timezone configuration.");
   long approximate_offset=(long)MathRound((double)(TimeTradeServer()-TimeGMT())/60.0);
   WriteRow(handle,"current_server_minus_pc_gmt_minutes_approx",IntegerToString(approximate_offset),"minutes","DIAGNOSTIC ONLY. Do not use as historical server UTC offset or DST evidence.");

   WriteStringProperty(handle,"description",SYMBOL_DESCRIPTION);
   WriteStringProperty(handle,"currency_base",SYMBOL_CURRENCY_BASE);
   WriteStringProperty(handle,"currency_profit",SYMBOL_CURRENCY_PROFIT);
   WriteStringProperty(handle,"currency_margin",SYMBOL_CURRENCY_MARGIN);

   WriteIntegerProperty(handle,"digits",SYMBOL_DIGITS,"decimal places");
   WriteDoubleProperty(handle,"point",SYMBOL_POINT,"price units");
   WriteDoubleProperty(handle,"tick_size",SYMBOL_TRADE_TICK_SIZE,"price units");
   WriteDoubleProperty(handle,"tick_value",SYMBOL_TRADE_TICK_VALUE,"account currency per lot per tick");
   WriteDoubleProperty(handle,"tick_value_profit",SYMBOL_TRADE_TICK_VALUE_PROFIT,"account currency per lot per profitable tick");
   WriteDoubleProperty(handle,"tick_value_loss",SYMBOL_TRADE_TICK_VALUE_LOSS,"account currency per lot per losing tick");
   WriteDoubleProperty(handle,"contract_size",SYMBOL_TRADE_CONTRACT_SIZE,"contract units per lot");
   WriteDoubleProperty(handle,"volume_min",SYMBOL_VOLUME_MIN,"lots");
   WriteDoubleProperty(handle,"volume_max",SYMBOL_VOLUME_MAX,"lots");
   WriteDoubleProperty(handle,"volume_step",SYMBOL_VOLUME_STEP,"lots");
   WriteDoubleProperty(handle,"volume_limit",SYMBOL_VOLUME_LIMIT,"lots");
   WriteDoubleProperty(handle,"margin_initial",SYMBOL_MARGIN_INITIAL,"account currency");
   WriteDoubleProperty(handle,"margin_maintenance",SYMBOL_MARGIN_MAINTENANCE,"account currency");
   WriteDoubleProperty(handle,"margin_hedged",SYMBOL_MARGIN_HEDGED,"account currency");
   WriteDoubleProperty(handle,"swap_long",SYMBOL_SWAP_LONG,"broker-defined swap units");
   WriteDoubleProperty(handle,"swap_short",SYMBOL_SWAP_SHORT,"broker-defined swap units");

   WriteIntegerProperty(handle,"trade_calc_mode",SYMBOL_TRADE_CALC_MODE,"enum");
   WriteIntegerProperty(handle,"trade_mode",SYMBOL_TRADE_MODE,"enum");
   WriteIntegerProperty(handle,"execution_mode",SYMBOL_TRADE_EXEMODE,"enum");
   WriteIntegerProperty(handle,"filling_mode",SYMBOL_FILLING_MODE,"flags");
   WriteIntegerProperty(handle,"order_mode",SYMBOL_ORDER_MODE,"flags");
   WriteIntegerProperty(handle,"stops_level_points",SYMBOL_TRADE_STOPS_LEVEL,"points");
   WriteIntegerProperty(handle,"freeze_level_points",SYMBOL_TRADE_FREEZE_LEVEL,"points");
   WriteIntegerProperty(handle,"swap_mode",SYMBOL_SWAP_MODE,"enum");
   WriteIntegerProperty(handle,"swap_rollover_3days",SYMBOL_SWAP_ROLLOVER3DAYS,"day-of-week enum");

   if(has_tick)
     {
      WriteRow(handle,"quote_bid",DoubleToString(tick.bid,10),"price","");
      WriteRow(handle,"quote_ask",DoubleToString(tick.ask,10),"price","");
      WriteRow(handle,"quote_time_msc",IntegerToString(tick.time_msc),"milliseconds since epoch","Retain as emitted by MT5; do not relabel without timezone validation.");
      if(point>0.0 && tick.ask>=tick.bid)
         WriteRow(handle,"quote_spread_points",DoubleToString((tick.ask-tick.bid)/point,4),"points","Single observed quote only; not a spread distribution.");
     }
   else
      WriteRow(handle,"quote_snapshot","UNAVAILABLE","","SymbolInfoTick failed; refresh Market Watch and rerun.");

   FileFlush(handle);
   FileClose(handle);
   PrintFormat("BrokerSpecSnapshot: wrote Common\\Files\\%s",filename);
   Print("BrokerSpecSnapshot: read-only capture complete. No account login, account holder name, password or trading action was exported.");
  }
//+------------------------------------------------------------------+
