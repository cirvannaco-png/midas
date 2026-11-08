#property strict
#include "../includes/Portfolio/AccountRiskProfilePolicy.mqh"

int failures=0;

void AssertTrue(bool value,string label)
  {
   if(value) PrintFormat("PASS: %s",label);
   else { PrintFormat("FAIL: %s",label); failures++; }
  }

void SetLimits(AccountRiskLimits &v,double risk,int openTrades,double daily,double drawdown,
               double derisk,double floor,double portfolio,int perSymbol,int perGroup)
  {
   v.profile=ACCOUNT_RISK_PROFILE_LEGACY_INPUTS;
   v.profileName="fixture";
   v.riskPercentPerTrade=risk;
   v.maxOpenTrades=openTrades;
   v.maxDailyLossPercent=daily;
   v.maxDrawdownPercent=drawdown;
   v.deriskStartPercent=derisk;
   v.deriskFloor=floor;
   v.maxPortfolioRiskPercent=portfolio;
   v.maxPositionsPerSymbol=perSymbol;
   v.maxPositionsPerGroup=perGroup;
  }

int OnInit()
  {
   AccountRiskLimits legacy,smallAccount,propFirm,selected;
   SetLimits(legacy,0.50,3,3.0,10.0,5.0,0.25,3.0,3,3);
   SetLimits(smallAccount,0.45,5,2.5,9.0,4.0,0.20,2.5,3,3);
   SetLimits(propFirm,0.25,3,1.5,5.0,2.0,0.25,1.0,2,2);
   string reason="";

   // Hard safety ceiling is independent of the operator-configured daily and
   // portfolio caps. A 30% setup must not become valid by raising those caps.
   AccountRiskLimits unsafeRisk;
   SetLimits(unsafeRisk,30.0,3,40.0,60.0,20.0,0.25,35.0,3,3);
   AssertTrue(!ValidateAccountRiskLimits(unsafeRisk,reason),
      "30 percent per-trade risk is rejected by the hard safety ceiling");
   AssertTrue(StringFind(reason,"hard safety ceiling")>=0,
      "excessive risk reports the hard-ceiling remediation");
   SetLimits(unsafeRisk,20.0,3,25.0,35.0,10.0,0.75,20.0,3,3);
   reason="";
   AssertTrue(ValidateAccountRiskLimits(unsafeRisk,reason),
      "risk at the 20 percent hard ceiling remains valid when other limits are coherent");
   SetLimits(unsafeRisk,20.01,3,30.0,40.0,10.0,0.75,20.01,3,3);
   reason="";
   AssertTrue(!ValidateAccountRiskLimits(unsafeRisk,reason),
      "risk above the 20 percent hard ceiling is rejected");

   AssertTrue(ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_LEGACY_INPUTS,
      legacy,smallAccount,propFirm,selected,reason),"legacy profile resolves");
   AssertTrue(selected.riskPercentPerTrade==0.50 && selected.maxOpenTrades==3 &&
      selected.maxDrawdownPercent==10.0,"legacy profile preserves its independent limits");

   reason="";
   AssertTrue(ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,selected,reason),"small-account profile resolves");
   AssertTrue(selected.profileName=="small_account" && selected.riskPercentPerTrade==0.45 &&
      selected.maxOpenTrades==5 && selected.maxPortfolioRiskPercent==2.5,
      "small-account values are selected without inheriting legacy values");

   reason="";
   AssertTrue(ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_PROP_FIRM,
      legacy,smallAccount,propFirm,selected,reason),"prop-firm profile resolves");
   AssertTrue(selected.profileName=="prop_firm" && selected.riskPercentPerTrade==0.25 &&
      selected.maxDrawdownPercent==5.0 && selected.maxPositionsPerSymbol==2,
      "prop-firm values are isolated from the small-account profile");

   reason="";
   AssertTrue(ResolveConfiguredAccountRiskLimits(ACCOUNT_RISK_PROFILE_LEGACY_INPUTS,
      legacy,smallAccount,propFirm,false,false,selected,reason),
      "legacy profile remains available without non-legacy setup flags");

   reason="";
   AssertTrue(!ResolveConfiguredAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,false,false,selected,reason),
      "small-account profile fails closed before its settings are configured");
   AssertTrue(StringFind(reason,"must be configured")>=0,
      "unconfigured small-account profile reports explicit remediation");

   reason="";
   AssertTrue(!ResolveConfiguredAccountRiskLimits(ACCOUNT_RISK_PROFILE_PROP_FIRM,
      legacy,smallAccount,propFirm,true,false,selected,reason),
      "prop-firm profile fails closed before exact firm rules are configured");
   AssertTrue(StringFind(reason,"exact prop-firm limits")>=0,
      "unconfigured prop-firm profile reports explicit remediation");

   reason="";
   AssertTrue(ResolveConfiguredAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,true,false,selected,reason),
      "configured small-account profile resolves normally");
   AssertTrue(selected.profileName=="small_account" && selected.riskPercentPerTrade==0.45,
      "configured small-account profile retains its own selected values");

   reason="";
   AssertTrue(ResolveConfiguredAccountRiskLimits(ACCOUNT_RISK_PROFILE_PROP_FIRM,
      legacy,smallAccount,propFirm,true,true,selected,reason),
      "configured prop-firm profile resolves normally");
   AssertTrue(selected.profileName=="prop_firm" && selected.riskPercentPerTrade==0.25,
      "configured prop-firm profile retains its own selected values");

   reason="";
   smallAccount.deriskStartPercent=smallAccount.maxDrawdownPercent;
   AssertTrue(!ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,selected,reason),
      "profile fails closed when de-risking starts at or after hard drawdown");
   AssertTrue(StringLen(reason)>0,"invalid profile returns a diagnostic reason");

   reason="";
   SetLimits(smallAccount,0.50,3,0.25,5.0,2.0,0.20,1.0,2,2);
   AssertTrue(!ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,selected,reason),
      "profile fails closed when one trade can equal or exceed the daily-loss cap");

   reason="";
   SetLimits(smallAccount,0.40,3,2.0,8.0,3.0,0.20,2.5,3,3);
   AssertTrue(!ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,selected,reason),
      "profile fails closed when portfolio open risk exceeds daily-loss cap");

   reason="";
   SetLimits(smallAccount,0.40,2,2.0,8.0,3.0,0.20,1.5,3,2);
   AssertTrue(!ResolveAccountRiskLimits(ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,
      legacy,smallAccount,propFirm,selected,reason),
      "profile fails closed when per-symbol positions exceed max open trades");

   // Gold cash-risk exception: the $7.50 KES-equivalent ceiling
   // supersedes the general 15% small-account minimum only for Gold.
   double effectiveRisk=0.0;
   reason="";
   AssertTrue(IsGoldRiskLimitedSymbol("XAUUSD.a") &&
      IsGoldRiskLimitedSymbol("GOLDmicro") &&
      !IsGoldRiskLimitedSymbol("EURUSD"),
      "Gold symbols are identified without classifying ordinary FX pairs");

   AssertTrue(ResolveRiskPercentWithCashCap(1500.0,20.0,7.50,true,
      effectiveRisk,reason) && MathAbs(effectiveRisk-0.50)<0.000001,
      "KES 7.50 cash cap limits a KES 1,500 Gold account to 0.50% risk");

   reason="";
   AssertTrue(ResolveRiskPercentWithCashCap(1500.0,20.0,7.50,false,
      effectiveRisk,reason) && MathAbs(effectiveRisk-20.0)<0.000001,
      "Gold-specific cap does not change the 20% small-account profile for other assets");

   AssertTrue(SmallAccountRiskFloorSatisfied(0.50,15.0,true),
      "Gold cash-risk exception permits a safe capped budget below the general minimum");
   AssertTrue(!SmallAccountRiskFloorSatisfied(0.50,15.0,false),
      "non-Gold small-account trades still obey the configured minimum risk floor");
   AssertTrue(!SmallAccountRiskFloorSatisfied(0.0,15.0,true),
      "Gold exception never permits a zero or invalid budget");

   AssertTrue(GoldStopRiskWithinCashCap(7.49,7.50),
      "Gold stop risk below the KES cash cap is accepted");
   AssertTrue(GoldStopRiskWithinCashCap(7.50,7.50),
      "Gold stop risk exactly at the KES cash cap is accepted");
   AssertTrue(!GoldStopRiskWithinCashCap(7.51,7.50),
      "Gold stop risk above the KES cash cap is rejected");
   AssertTrue(!GoldStopRiskWithinCashCap(7.50,0.0),
      "missing Gold cash cap fails closed");

   double accountCurrencyPerKES=0.0;
   AssertTrue(ResolveKESConversionFactorFromQuote(0.0065,0.0066,true,
      D'2026.11.08 10:00:00',D'2026.11.08 10:05:00',3600,accountCurrencyPerKES) &&
      MathAbs(accountCurrencyPerKES-0.0065)<0.0000001,
      "direct KES/account-currency conversion uses the conservative bid");

   accountCurrencyPerKES=0.0;
   AssertTrue(ResolveKESConversionFactorFromQuote(150.0,151.0,false,
      D'2026.11.08 10:00:00',D'2026.11.08 10:05:00',3600,accountCurrencyPerKES) &&
      MathAbs(accountCurrencyPerKES-(1.0/151.0))<0.0000001,
      "inverse account-currency/KES conversion uses the conservative inverse ask");

   accountCurrencyPerKES=0.0;
   AssertTrue(!ResolveKESConversionFactorFromQuote(0.0065,0.0066,true,
      D'2026.11.08 08:00:00',D'2026.11.08 10:05:00',3600,accountCurrencyPerKES),
      "stale KES conversion ticks are rejected");
   AssertTrue(!ResolveKESConversionFactorFromQuote(0.0,0.0066,true,
      D'2026.11.08 10:00:00',D'2026.11.08 10:05:00',3600,accountCurrencyPerKES),
      "direct conversion without a positive bid is rejected");
   AssertTrue(!ResolveKESConversionFactorFromQuote(150.0,0.0,false,
      D'2026.11.08 10:00:00',D'2026.11.08 10:05:00',3600,accountCurrencyPerKES),
      "inverse conversion without a positive ask is rejected");
   AssertTrue(!ResolveKESConversionFactorFromQuote(150.0,151.0,false,
      D'2026.11.08 10:06:00',D'2026.11.08 10:05:00',3600,accountCurrencyPerKES),
      "future-dated conversion ticks are rejected");

   PrintFormat("AccountRiskProfilePolicy tests: %d failure(s)",failures);
   return failures==0 ? INIT_SUCCEEDED : INIT_FAILED;
  }
