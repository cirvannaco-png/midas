// MidasTouch2 single-file production build
// Package version: 1.0.0-rc.1
// Upstream baseline: cirvannaco-png/Midas-touch2-@3622ed5a434c36f0c05ab9c9863d17b6fd743e9a
// Staged EA source snapshot: cirvannaco-png/midas@142bf7d477b527c01b4a717af7f33f85f5e284ce
// Modular source is preserved under development/EA/.
// Regenerate with: python scripts/build_single_file.py
// Do not hand-edit this generated file.

#property copyright "Medis Touch"
#property version   "2.81"
#property strict

// BEGIN INLINED MODULE: includes/Core/Config.mqh
#property copyright "Medis Touch"
#property version   "2.00"

#ifndef CONFIG_MQH
#define CONFIG_MQH

// BEGIN INLINED MODULE: includes/Core/NewsFilter.mqh
//+------------------------------------------------------------------+
//|                                            Core/NewsFilter.mqh    |
//+------------------------------------------------------------------+
#ifndef NEWSFILTER_MQH
#define NEWSFILTER_MQH

// v2.9: soft-risk tier, in addition to the existing hard-block IsLocked()
// gate. NEWS_NONE = no high-impact event within the warning window at
// all. NEWS_WARNING = inside the (wider) warning window but outside the
// (narrower) block window — CScoringEngine can use this to soft-discount
// confidence rather than the EA hard-blocking every entry, matching the
// review's "don't just block, let news context feed the probability
// model" idea. NEWS_BLOCKED = inside the existing hard-block window;
// IsLocked() already fully prevents new entries in this case at the EA
// level, this enum value exists so a single call can report which tier
// applied, for the dashboard/signal card.
enum ENUM_NEWS_RISK { NEWS_NONE, NEWS_WARNING, NEWS_BLOCKED };

// Blocks NEW trade entries in a window around high-impact economic
// events, read from a CSV the operator maintains themselves — this does
// NOT scrape ForexFactory or anything else at runtime (MT5's WebRequest
// is allow-listed per-domain by the terminal and scraping a site that
// doesn't offer a real feed is fragile and liable to break silently).
// Expected file format, one event per line, in the terminal's
// MQL5/Files directory (or Files/Common if opened with FILE_COMMON):
//   2026.08.15,12:30,HIGH,US Nonfarm Payrolls
//   2026.08.20,18:00,HIGH,FOMC Rate Decision
// Only rows with impact == "HIGH" (case-sensitive, by design — don't
// silently widen the block window by loosely matching "medium" too)
// are loaded. Malformed rows are skipped, not fatal.
//
// FAILS OPEN: a missing or empty file disables the filter (logs once,
// trading continues) rather than blocking every trade because a CSV
// wasn't found — the same fail-safe posture SessionFilter and
// PortfolioManager use elsewhere in this codebase for "gate not
// configured".
class CNewsFilter
  {
private:
   datetime   m_times[];
   string     m_labels[];
   int        m_count;
   int        m_minutesBefore;
   int        m_minutesAfter;
   bool       m_enabled;
   // v2.9 — warning window, wider than the block window by definition
   // (if it were narrower/equal, WARNING would never be reachable).
   int        m_warnMinutesBefore;
   int        m_warnMinutesAfter;

public:
              CNewsFilter() : m_count(0), m_minutesBefore(15), m_minutesAfter(5), m_enabled(false),
                              m_warnMinutesBefore(60), m_warnMinutesAfter(30) {}
   bool       Load(string filename, int minutesBefore, int minutesAfter, bool useCommonFolder = false);
   bool       IsLocked(string &reasonOut);
   int        Count() const { return m_count; }
   // v2.9. Call after Load(). Values below the existing block window are
   // clamped up to it, so WARNING is always a superset of BLOCKED, never
   // a gap next to it.
   void       ConfigureWarningWindow(int warnMinutesBefore, int warnMinutesAfter)
     {
      m_warnMinutesBefore = MathMax(warnMinutesBefore, m_minutesBefore);
      m_warnMinutesAfter = MathMax(warnMinutesAfter, m_minutesAfter);
     }
   // v2.9. Returns the risk tier for "now", the label of the nearest
   // event driving that tier (if any), and minutes until/since it
   // (negative = already passed, still inside the after-window).
   ENUM_NEWS_RISK GetRiskTier(string &labelOut, int &minutesToEventOut);
  };
//+------------------------------------------------------------------+
bool CNewsFilter::Load(string filename, int minutesBefore, int minutesAfter, bool useCommonFolder)
  {
   m_count = 0;
   m_enabled = false;
   m_minutesBefore = MathMax(0, minutesBefore);
   m_minutesAfter = MathMax(0, minutesAfter);

   int flags = FILE_CSV | FILE_READ | FILE_SHARE_READ | FILE_ANSI;
   if(useCommonFolder) flags |= FILE_COMMON;
   int handle = FileOpen(filename, flags, ',');
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("MedisTouch NewsFilter: %s not found — news filter disabled (this is not an error; create the file to enable it).", filename);
      return false;
     }

   ArrayResize(m_times, 0);
   ArrayResize(m_labels, 0);
   int loaded = 0, skipped = 0;

   while(!FileIsEnding(handle))
     {
      string dateStr = FileReadString(handle);
      if(FileIsEnding(handle)) break; // trailing blank line at EOF
      string timeStr = FileReadString(handle);
      string impact  = FileReadString(handle);
      string label   = FileReadString(handle);

      if(impact != "HIGH") { skipped++; continue; }
      datetime dt = StringToTime(dateStr + " " + timeStr);
      if(dt <= 0) { skipped++; continue; } // unparseable row — skip, don't crash the load

      int n = ArraySize(m_times);
      ArrayResize(m_times, n + 1);
      ArrayResize(m_labels, n + 1);
      m_times[n] = dt;
      m_labels[n] = label;
      loaded++;
     }
   FileClose(handle);

   m_count = loaded;
   m_enabled = (loaded > 0);
   PrintFormat("MedisTouch NewsFilter: loaded %d high-impact event(s) from %s (%d row(s) skipped/malformed).",
               loaded, filename, skipped);
   return m_enabled;
  }
//+------------------------------------------------------------------+
bool CNewsFilter::IsLocked(string &reasonOut)
  {
   reasonOut = "";
   if(!m_enabled) return false;
   datetime now = TimeCurrent();
   for(int i = 0; i < m_count; i++)
     {
      datetime windowStart = m_times[i] - m_minutesBefore * 60;
      datetime windowEnd   = m_times[i] + m_minutesAfter * 60;
      if(now >= windowStart && now <= windowEnd)
        {
         reasonOut = StringFormat("news lock — \"%s\" at %s (blocking %d min before / %d min after)",
                                   m_labels[i], TimeToString(m_times[i], TIME_DATE | TIME_MINUTES),
                                   m_minutesBefore, m_minutesAfter);
         return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
ENUM_NEWS_RISK CNewsFilter::GetRiskTier(string &labelOut, int &minutesToEventOut)
  {
   labelOut = "";
   minutesToEventOut = 0;
   if(!m_enabled) return NEWS_NONE;
   datetime now = TimeCurrent();
   ENUM_NEWS_RISK best = NEWS_NONE;
   int bestAbsMinutes = INT_MAX;

   for(int i = 0; i < m_count; i++)
     {
      datetime blockStart = m_times[i] - m_minutesBefore * 60;
      datetime blockEnd   = m_times[i] + m_minutesAfter * 60;
      datetime warnStart  = m_times[i] - m_warnMinutesBefore * 60;
      datetime warnEnd    = m_times[i] + m_warnMinutesAfter * 60;

      ENUM_NEWS_RISK tier = NEWS_NONE;
      if(now >= blockStart && now <= blockEnd) tier = NEWS_BLOCKED;
      else if(now >= warnStart && now <= warnEnd) tier = NEWS_WARNING;
      if(tier == NEWS_NONE) continue;

      int minutesToEvent = (int)((m_times[i] - now) / 60);
      int absMinutes = (int)MathAbs(minutesToEvent);
      // prefer BLOCKED over WARNING regardless of distance, then nearest event
      if(tier > best || (tier == best && absMinutes < bestAbsMinutes))
        {
         best = tier;
         bestAbsMinutes = absMinutes;
         labelOut = m_labels[i];
         minutesToEventOut = minutesToEvent;
        }
     }
   return best;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Core/NewsFilter.mqh

enum ENUM_TREND_STATE { TREND_BULL_STRONG, TREND_BULL, TREND_NEUTRAL, TREND_BEAR, TREND_BEAR_STRONG };
enum ENUM_FVG_DIR { FVG_BULL, FVG_BEAR };
enum ENUM_FVG_STATE { FVG_FRESH, FVG_TESTED, FVG_MITIGATED, FVG_INVALIDATED };
enum ENUM_LIQ_TYPE { LIQ_BUY_SIDE, LIQ_SELL_SIDE };
enum ENUM_BIAS { BIAS_BULLISH, BIAS_BEARISH, BIAS_NEUTRAL };
enum ENUM_SR_TYPE { SR_MAJOR_RESISTANCE, SR_MINOR_RESISTANCE, SR_MAJOR_SUPPORT, SR_MINOR_SUPPORT };
enum ENUM_FILL_POLICY { FILL_CONSERVATIVE, FILL_OPTIMISTIC, FILL_NEAREST, FILL_INTRABAR_REPLAY, FILL_AMBIGUOUS };
enum ENUM_MARKET_PHASE { PHASE_UNDEFINED, PHASE_ACCUMULATION, PHASE_MANIPULATION, PHASE_DISTRIBUTION };
enum ENUM_FIB_ZONE { FIB_ZONE_UNDEFINED, FIB_ZONE_DISCOUNT, FIB_ZONE_NEUTRAL, FIB_ZONE_PREMIUM };
enum ENUM_VALUE_AREA_ZONE { VA_ZONE_UNDEFINED, VA_ZONE_BELOW, VA_ZONE_INSIDE, VA_ZONE_ABOVE };
enum ENUM_VALUE_PROFILE_SOURCE { VA_SOURCE_UNDEFINED, VA_SOURCE_REAL_TRADE_TICKS, VA_SOURCE_BROKER_TRADE_TICKS, VA_SOURCE_REAL_VOLUME_BARS, VA_SOURCE_TICK_VOLUME_BARS };
enum ENUM_VALUE_PROFILE_STATE { VA_STATE_UNDEFINED, VA_STATE_BALANCED, VA_STATE_ACCEPTED_ABOVE, VA_STATE_ACCEPTED_BELOW, VA_STATE_REJECTED_ABOVE, VA_STATE_REJECTED_BELOW };
enum ENUM_OB_STATE { OB_FRESH, OB_TESTED, OB_MITIGATED };
enum ENUM_VOL_REGIME { VOL_REGIME_UNDEFINED, VOL_REGIME_LOW, VOL_REGIME_NORMAL, VOL_REGIME_HIGH };
enum ENUM_TRADING_SESSION { SESSION_DEAD, SESSION_TOKYO, SESSION_LONDON, SESSION_NEWYORK, SESSION_LONDON_NY_OVERLAP };
enum ENUM_MARKET_REGIME { REGIME_UNDEFINED, REGIME_TRENDING, REGIME_RANGING, REGIME_TRANSITION };
enum ENUM_SMC_STRUCTURE_STATE { SMC_WAIT, SMC_INVALID, SMC_VALID, SMC_STALE, SMC_INVALIDATED };
enum ENUM_BREAKOUT_CLASS { BREAKOUT_NONE, BREAKOUT_EXPANSION, BREAKOUT_LIQUIDITY, BREAKOUT_FAILED, BREAKOUT_EXHAUSTION };
enum ENUM_REVERSION_CLASS { REVERSION_NONE, REVERSION_VALUE_FADE, REVERSION_LEVEL_REJECTION, REVERSION_TREND_CONFLICT };
enum ENUM_KEYLEVEL_SOURCE { LEVEL_NONE, LEVEL_SR, LEVEL_ORDER_BLOCK, LEVEL_VALUE_AREA, LEVEL_LIQUIDITY_POOL, LEVEL_PREV_WEEK, LEVEL_SESSION, LEVEL_PSYCHOLOGICAL };
enum ENUM_KEYLEVEL_REACTION { REACTION_NONE, REACTION_REJECTION, REACTION_BREAK, REACTION_RETEST, REACTION_FAILED_BREAK, REACTION_ACCEPTANCE, REACTION_ABSORPTION };
enum ENUM_SELECTED_STRATEGY { STRATEGY_NONE, STRATEGY_SMC, STRATEGY_MOMENTUM_BREAKOUT, STRATEGY_MEAN_REVERSION, STRATEGY_KEY_LEVEL };
enum ENUM_SWEEP_GRADE { SWEEP_GRADE_NONE, SWEEP_GRADE_C, SWEEP_GRADE_B, SWEEP_GRADE_A };

struct ImpulseLeg { bool valid; datetime start_time; datetime end_time; int start_bar; int end_bar; int displacement_bar; double start_price; double end_price; bool bullish; double strength; };
struct InducementResult { bool valid; bool impulseFound; bool internalStructureFound; bool sweepFound; bool bosConfirmed; double impulseScore; double structureScore; double sweepScore; double bosScore; double totalScore; ImpulseLeg leg; string reason; ENUM_SWEEP_GRADE sweepGrade; double sweepGradeScore; double bosStrength; int barsSinceSweep; int barsSinceBOS; double timeDecay; double bosClosePrice; int bosBarIndex; int sweepBarIndex; int displacementBarIndex; double sweepPoolPrice; };
struct SMCStructuralValidation { ENUM_SMC_STRUCTURE_STATE state; bool structural_valid; bool htf_structure_valid; bool regime_applicable; bool liquidity_target_valid; bool sweep_valid; bool displacement_valid; bool bos_valid; bool fvg_causal; bool order_block_causal; bool htf_ob_present; bool premium_discount_valid; bool freshness_valid; bool invalidation_clear; double protected_level; double invalidation_level; int sweep_bar_index; int bos_bar_index; int displacement_bar_index; int entry_fvg_bar_index; int causal_ob_bar_index; string failure_reason; };
struct OutcomeStats { int wins; int losses; int scratches; int ambiguous; double netPnL; double grossProfit; double grossLoss; double totalCommission; double totalSpreadCost; double totalSlippageCost; double sumRMultiple; int resolvedCount; int ExcludingAmbiguousTotal() const { return wins + losses; } double WinRateExcludingAmbiguous() const { int t=wins+losses; return t>0?100.0*wins/t:0.0; } double WinRateAmbiguousAsLoss() const { int t=wins+losses+ambiguous; return t>0?100.0*wins/t:0.0; } double WinRateAmbiguousAsWin() const { int t=wins+losses+ambiguous; return t>0?100.0*(wins+ambiguous)/t:0.0; } double ProfitFactor() const { if(grossLoss>0)return grossProfit/grossLoss; return grossProfit>0?-1.0:0.0; } double ExpectancyPerTrade() const { return resolvedCount>0?netPnL/resolvedCount:0.0; } double AverageRMultiple() const { return resolvedCount>0?sumRMultiple/resolvedCount:0.0; } };
struct CandleData { datetime time; double open; double high; double low; double close; long tick_volume; long real_volume; double atr; };
struct SwingPoint { datetime time; double price; bool is_high; int bar_index; double strength; };
struct BOSEvent { datetime time; double price; bool is_bullish; double strength; int bar_index; string label; };
struct CHOCHPoint { datetime time; double price; bool bullish; int bar_index; };
struct FVGZone { datetime time; double top; double bottom; ENUM_FVG_DIR dir; ENUM_FVG_STATE state; double width; int bar_index; };
struct OrderBlockZone { datetime time; double top; double bottom; ENUM_FVG_DIR dir; ENUM_OB_STATE state; double displacement_atr; int bar_index; };
struct LiquidityPool { double price_top; double price_bottom; ENUM_LIQ_TYPE type; int touches; bool external; int confirmed_at_shift; };
struct LiquidityEvent { datetime time; double price; ENUM_LIQ_TYPE type; double strength; bool swept; int bar_index; bool external; };
struct SRZone { double top; double bottom; ENUM_SR_TYPE type; int touches; datetime startTime; };

struct SetupReasons {
   bool trend_aligned; bool bos_confirmed; bool liquidity_swept; bool fresh_fvg; bool sr_confluence; bool inducement_valid; bool premium_discount_ok;
   ENUM_MARKET_PHASE phase; string risk_warning; double rvol; bool volume_confirmed; ENUM_FIB_ZONE fib_zone; bool fib_in_zone; double fib_nearest_level;
   bool value_area_ok; ENUM_VALUE_AREA_ZONE va_zone; double va_poc; double va_high; double va_low; ENUM_VALUE_PROFILE_SOURCE value_profile_source; ENUM_VALUE_PROFILE_STATE value_profile_state; double va_poc_migration_atr; double va_source_quality; double va_score; bool value_area_contradiction; bool htf_ob_confluence; ENUM_OB_STATE htf_ob_state;
   ENUM_VOL_REGIME vol_regime; ENUM_TRADING_SESSION session; bool session_ok; ENUM_SWEEP_GRADE sweep_grade; double bos_strength; double time_decay;
   double chase_dist_atr; bool chase_ok; ENUM_NEWS_RISK news_risk; string news_label; int news_minutes_to_event; double contradiction_penalty; double env_score;
   double exec_score; double env_exec_confidence; ENUM_MARKET_REGIME regime; double momentum_score; double breakout_score; ENUM_BREAKOUT_CLASS breakout_class;
   double reversion_score; ENUM_REVERSION_CLASS reversion_class; ENUM_KEYLEVEL_SOURCE keylevel_source; ENUM_KEYLEVEL_REACTION keylevel_reaction; double keylevel_score;
   ENUM_SELECTED_STRATEGY selected_strategy; double selected_strategy_score;
   // SMC structural-validation telemetry. Diagnostic only until explicitly promoted by a validated policy.
   // Authoritative inducement evidence reused by structural diagnostics; prevents a second reconstruction of sweep/BOS provenance.
   InducementResult smc_inducement;
   ENUM_SMC_STRUCTURE_STATE smc_state; bool smc_structural_valid; bool smc_htf_structure_valid; bool smc_regime_applicable;
   bool smc_liquidity_target_valid; bool smc_sweep_valid; bool smc_displacement_valid; bool smc_bos_valid;
   bool smc_fvg_causal; bool smc_order_block_causal; bool smc_htf_ob_present; bool smc_premium_discount_valid;
   bool smc_freshness_valid; bool smc_invalidation_clear; double smc_protected_level; double smc_invalidation_level;
   int smc_sweep_bar_index; int smc_bos_bar_index; int smc_displacement_bar_index; int smc_entry_fvg_bar_index; int smc_causal_ob_bar_index; string smc_failure_reason;
   // Environment telemetry. These are observations only and never act as
   // standalone trading gates.
   double trend_strength; double liquidity_score; int liquidity_bucket;
   double spread_points; double point_size; double atr_value;
   string environment_memory_status; int environment_memory_sample;
   double environment_memory_win_rate; double environment_memory_avg_r;
   double environment_memory_profit_factor; double environment_memory_adjustment;
};

struct TradeSetup {
   ENUM_ORDER_TYPE type;
   double entry_top;
   double entry_bottom;
   double invalidation;
   double stop_loss;
   double tp1;
   double tp2;
   double final_tp;
   double confidence;
   datetime creation_time;
   bool active;
   SetupReasons reasons;
   double calibrated_probability;
   int calibration_sample;
   bool calibration_has_enough_data;
};

double ResolveExecutionEntry(const TradeSetup &setup) { return setup.type==ORDER_TYPE_BUY?setup.entry_top:setup.entry_bottom; }

struct PendingSetup {
   TradeSetup setup; double entryRef; double riskDist; double mfePrice; double maePrice; bool tp1Hit; bool tp2Hit; int barsElapsed; datetime lastBarTime; bool filled; datetime fillTime; int barsToFill; bool sameBarCollision;
   double sizingEntryPrice; double mgmtRiskDist; double weightedRiskDistLots; double lots; double entryFillPrice; double currentSL; bool beDone; bool partialDone; double remainingLots; double realizedPnL; double totalCommission; double totalSpreadCost; double totalSlippageCost;
   // Signed broker cashflows stay distinct from positive cost magnitudes. Restored
   // snapshots are not history-complete unless their deals are replayed from broker history.
   double totalCommissionCashflow; double totalSwapCashflow; double totalBrokerFeeCashflow;
   bool cashflowsKnown; bool spreadCostKnown; bool slippageCostKnown; bool outcomeHistoryComplete; bool excursionHistoryComplete;
   double confidenceAtSignal; double confidenceDecayed; int decayBars; long decisionId; string decision_fingerprint;
};

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Core/Config.mqh
// BEGIN INLINED MODULE: includes/Core/CandleData.mqh
//+------------------------------------------------------------------+
//|                                                Core/CandleData.mqh |
//+------------------------------------------------------------------+
#ifndef CANDLEDATA_MQH
#define CANDLEDATA_MQH

// already inlined once under include guard: includes/Core/Config.mqh

class CCandleData
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_maxBars;
   CandleData        m_data[];
   int               m_size;
   int               m_atrHandle;
   double            m_atrBuffer[];

   // FIX: was named CopyRates(), same name as the built-in MQL5 function
   // it calls internally — legal but a real footgun (shadowing/ambiguity).
   void              FetchRates();
   void              UpdateATR();

public:
                     CCandleData();
                    ~CCandleData();

   bool              Init(string symbol, ENUM_TIMEFRAMES tf, int maxBars = 500);
   int               Total() const { return m_size; }
   string            Symbol() const { return m_symbol; }
   ENUM_TIMEFRAMES   Timeframe() const { return m_timeframe; }
   CandleData        GetCandle(int shift) const;  // shift 0=current
   double            GetATR(int shift) const;
   bool              IsReady() const { return m_size > 0 && m_atrHandle != INVALID_HANDLE; }
   void              Refresh();                    // call each OnCalculate to keep in sync
  };
//+------------------------------------------------------------------+
CCandleData::CCandleData()
  {
   m_size = 0;
   m_maxBars = 500;
   m_atrHandle = INVALID_HANDLE;
  }
CCandleData::~CCandleData()
  {
   if(m_atrHandle != INVALID_HANDLE)
      IndicatorRelease(m_atrHandle);
  }
//+------------------------------------------------------------------+
bool CCandleData::Init(string symbol, ENUM_TIMEFRAMES tf, int maxBars)
  {
   m_symbol = symbol;
   m_timeframe = tf;
   m_maxBars = MathMax(50, maxBars);
   m_atrHandle = iATR(symbol, tf, 14);
   if(m_atrHandle == INVALID_HANDLE)
      return false;
   ArraySetAsSeries(m_data, true);
   FetchRates();
   return m_size > 0;
  }
//+------------------------------------------------------------------+
void CCandleData::FetchRates()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_timeframe, 0, m_maxBars, rates);
   if(copied <= 0)
      return;
   m_size = copied;
   ArrayResize(m_data, m_size);
   for(int i = 0; i < m_size; i++)
     {
      m_data[i].time = rates[i].time;
      m_data[i].open = rates[i].open;
      m_data[i].high = rates[i].high;
      m_data[i].low  = rates[i].low;
      m_data[i].close = rates[i].close;
      m_data[i].tick_volume = rates[i].tick_volume;
      m_data[i].real_volume = rates[i].real_volume;
      m_data[i].atr = 0.0;
     }
   UpdateATR();
  }
//+------------------------------------------------------------------+
void CCandleData::UpdateATR()
  {
   if(m_atrHandle == INVALID_HANDLE || m_size <= 0) return;
   ArraySetAsSeries(m_atrBuffer, true);
   int copied = CopyBuffer(m_atrHandle, 0, 0, m_size, m_atrBuffer);
   if(copied <= 0) return;
   for(int i = 0; i < m_size && i < ArraySize(m_atrBuffer); i++)
      m_data[i].atr = m_atrBuffer[i];
  }
//+------------------------------------------------------------------+
CandleData CCandleData::GetCandle(int shift) const
  {
   CandleData empty;
   ZeroMemory(empty);
   if(shift < 0 || shift >= m_size) return empty;
   return m_data[shift];
  }
//+------------------------------------------------------------------+
double CCandleData::GetATR(int shift) const
  {
   if(shift < 0 || shift >= m_size) return 0.0;
   return m_data[shift].atr;
  }
//+------------------------------------------------------------------+
void CCandleData::Refresh()
  {
   // Full refresh each tick — correct for the bar counts this indicator
   // targets (default 500). If you push maxBars into the thousands,
   // switch this to an incremental append-only update.
   FetchRates();
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Core/CandleData.mqh
// BEGIN INLINED MODULE: includes/Core/SessionFilter.mqh
//+------------------------------------------------------------------+
//|                                          Core/SessionFilter.mqh   |
//+------------------------------------------------------------------+
#ifndef SESSIONFILTER_MQH
#define SESSIONFILTER_MQH

// already inlined once under include guard: includes/Core/Config.mqh

// v2.8 addition. Pre-v2.8 the only session-aware code was
// CSignalLogger::SessionLabel() — a string used purely for CSV bucketing
// after the fact. It was never read by anything that decides whether to
// trade. This class is the actual gate: classifies the current GMT hour
// into a named session and exposes IsAllowed() so Scoring can block
// entries generated during configured-off windows (default: Tokyo-only
// and dead hours off, London/NY/overlap on) instead of trading every
// session uniformly regardless of liquidity.
//
// FIX (audit #20 — DST): London and New York's real trading hours are
// fixed in LOCAL time (roughly 08:00-16:30 London local, 08:00-17:00 NY
// local) — their GMT-hour equivalents shift by exactly 1 hour twice a
// year as each city's own DST turns on/off, AND London/NY don't switch
// on the same calendar date (EU DST: last Sunday of March -> last Sunday
// of October; US DST: second Sunday of March -> first Sunday of
// November — there are multi-week windows every spring and fall where
// one is on DST and the other isn't). The old code used one fixed GMT
// window per session year-round, which was quietly wrong for roughly
// half the year. This now computes each city's own DST status per tick
// and shifts that city's window accordingly, independently.
class CSessionFilter
  {
private:
   bool              m_enabled;
   bool              m_allowTokyo;
   bool              m_allowLondon;
   bool              m_allowNewYork;
   bool              m_allowOverlap;   // London/NY overlap — highest-liquidity window, allowed even if
                                        // m_allowLondon/m_allowNewYork are individually off

   static int        DaysInMonth(int year, int month);
   static datetime   NthSunday(int year, int month, int n); // n>0: nth Sunday; n<0: last Sunday
   static bool       IsEUDST(datetime gmtNow);   // London/EU: last Sun Mar - last Sun Oct
   static bool       IsUSDST(datetime gmtNow);   // New York/US: 2nd Sun Mar - 1st Sun Nov

public:
                     CSessionFilter();
   void              Configure(bool enabled, bool allowTokyo = false, bool allowLondon = true,
                               bool allowNewYork = true, bool allowOverlap = true);
   ENUM_TRADING_SESSION CurrentSession();
   // v2.17 addition — for CExtendedKeyLevels::NearestSessionLevel(),
   // which needs to know WHEN the current session opened, not just
   // which one is active. Reuses the exact same DST-aware start-hour
   // math CurrentSession() already computes, so the two can never
   // silently disagree about where a session's boundary sits. Returns 0
   // during SESSION_DEAD — there is no "current session" to report a
   // start for.
   datetime          CurrentSessionStartGMT();
   bool              IsAllowed(); // true if gate disabled, or current session is in the allow-list
  };
//+------------------------------------------------------------------+
CSessionFilter::CSessionFilter() : m_enabled(false), m_allowTokyo(false), m_allowLondon(true),
                                    m_allowNewYork(true), m_allowOverlap(true) {}
//+------------------------------------------------------------------+
void CSessionFilter::Configure(bool enabled, bool allowTokyo, bool allowLondon, bool allowNewYork, bool allowOverlap)
  {
   m_enabled = enabled;
   m_allowTokyo = allowTokyo;
   m_allowLondon = allowLondon;
   m_allowNewYork = allowNewYork;
   m_allowOverlap = allowOverlap;
  }
//+------------------------------------------------------------------+
int CSessionFilter::DaysInMonth(int year, int month)
  {
   static int dim[] = {31,28,31,30,31,30,31,31,30,31,30,31};
   if(month == 2)
     {
      bool leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return leap ? 29 : 28;
     }
   return dim[month - 1];
  }
//+------------------------------------------------------------------+
// n > 0: the n-th Sunday of the month. n < 0: the last Sunday of the month.
datetime CSessionFilter::NthSunday(int year, int month, int n)
  {
   MqlDateTime t;
   ZeroMemory(t);
   t.year = year; t.mon = month; t.day = 1; t.hour = 0; t.min = 0; t.sec = 0;
   datetime firstOfMonth = StructToTime(t);
   MqlDateTime t1;
   TimeToStruct(firstOfMonth, t1);
   int dow = t1.day_of_week; // 0 = Sunday
   int firstSundayDay = 1 + ((7 - dow) % 7);

   if(n > 0)
     {
      t.day = firstSundayDay + (n - 1) * 7;
      return StructToTime(t);
     }
   // last Sunday: walk back from the last day of the month
   int lastDay = DaysInMonth(year, month);
   t.day = lastDay;
   datetime lastOfMonth = StructToTime(t);
   MqlDateTime tl;
   TimeToStruct(lastOfMonth, tl);
   t.day = lastDay - tl.day_of_week;
   return StructToTime(t);
  }
//+------------------------------------------------------------------+
bool CSessionFilter::IsEUDST(datetime gmtNow)
  {
   MqlDateTime t;
   TimeToStruct(gmtNow, t);
   datetime start = NthSunday(t.year, 3, -1);   // last Sunday of March, 01:00 UTC transition
   datetime end   = NthSunday(t.year, 10, -1);  // last Sunday of October, 01:00 UTC transition
   return (gmtNow >= start && gmtNow < end);
  }
//+------------------------------------------------------------------+
bool CSessionFilter::IsUSDST(datetime gmtNow)
  {
   MqlDateTime t;
   TimeToStruct(gmtNow, t);
   datetime start = NthSunday(t.year, 3, 2);    // 2nd Sunday of March, ~07:00 UTC transition (2am EST)
   datetime end   = NthSunday(t.year, 11, 1);   // 1st Sunday of November, ~06:00 UTC transition (2am EDT)
   return (gmtNow >= start && gmtNow < end);
  }
//+------------------------------------------------------------------+
// London local session ~08:00-16:30; New York local session ~08:00-17:00.
// Each city's own DST state shifts its GMT window by exactly one hour.
ENUM_TRADING_SESSION CSessionFilter::CurrentSession()
  {
   datetime nowGmt = TimeGMT();
   MqlDateTime t;
   TimeToStruct(nowGmt, t);
   int h = t.hour;

   bool londonDST = IsEUDST(nowGmt);
   bool nyDST     = IsUSDST(nowGmt);

   int londonStart = londonDST ? 7  : 8;
   int londonEnd   = londonDST ? 16 : 17;
   int nyStart     = nyDST     ? 12 : 13;
   int nyEnd       = nyDST     ? 21 : 22;

   bool tokyo   = (h >= 0 && h < 9); // Tokyo doesn't observe DST — fixed window, unaffected
   bool london  = (h >= londonStart && h < londonEnd);
   bool newyork = (h >= nyStart && h < nyEnd);

   if(london && newyork) return SESSION_LONDON_NY_OVERLAP;
   if(london)  return SESSION_LONDON;
   if(newyork) return SESSION_NEWYORK;
   if(tokyo)   return SESSION_TOKYO;
   return SESSION_DEAD;
  }
//+------------------------------------------------------------------+
// Same start-hour derivation CurrentSession() uses, just returning the
// GMT timestamp of today's boundary instead of a bool membership test.
// SESSION_LONDON_NY_OVERLAP starts when the LATER of the two opens (NY,
// in every real-world case here) — the overlap by definition can't have
// begun before both sides are open.
datetime CSessionFilter::CurrentSessionStartGMT()
  {
   datetime nowGmt = TimeGMT();
   MqlDateTime t;
   TimeToStruct(nowGmt, t);

   bool londonDST = IsEUDST(nowGmt);
   bool nyDST     = IsUSDST(nowGmt);
   int londonStart = londonDST ? 7  : 8;
   int nyStart     = nyDST     ? 12 : 13;

   ENUM_TRADING_SESSION s = CurrentSession();
   int startHour;
   switch(s)
     {
      case SESSION_LONDON_NY_OVERLAP: startHour = nyStart;     break;
      case SESSION_LONDON:            startHour = londonStart; break;
      case SESSION_NEWYORK:           startHour = nyStart;     break;
      case SESSION_TOKYO:             startHour = 0;           break; // Tokyo doesn't observe DST — fixed window, unaffected
      default:                        return 0;                       // SESSION_DEAD — no boundary to report
     }

   MqlDateTime st = t;
   st.hour = startHour;
   st.min = 0;
   st.sec = 0;
   return StructToTime(st);
  }
//+------------------------------------------------------------------+
bool CSessionFilter::IsAllowed()
  {
   if(!m_enabled) return true; // fail-open when the gate itself is off — matches the
                                // Config.mqh LOCATION-filter convention: "no filter configured" != "wrong side"
   ENUM_TRADING_SESSION s = CurrentSession();
   switch(s)
     {
      case SESSION_LONDON_NY_OVERLAP: return m_allowOverlap;
      case SESSION_LONDON:            return m_allowLondon;
      case SESSION_NEWYORK:           return m_allowNewYork;
      case SESSION_TOKYO:             return m_allowTokyo;
      default:                        return false; // SESSION_DEAD — off by design, no allow flag for it
     }
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Core/SessionFilter.mqh
// BEGIN INLINED MODULE: includes/Core/SignalLogger.mqh
//+------------------------------------------------------------------+
//|                                          Core/SignalLogger.mqh    |
//+------------------------------------------------------------------+
#ifndef SIGNALLOGGER_MQH
#define SIGNALLOGGER_MQH

// already inlined once under include guard: includes/Core/Config.mqh

// Session labeling: v4 bucketed by raw server-clock hour, which drifts
// wrong by however many hours the broker's server sits from GMT (and
// worse across DST changes). This version computes the live server-to-GMT
// offset via TimeTradeServer()/TimeGMT() and buckets by real GMT session
// windows (Sydney/Tokyo/London/New York + overlaps) instead.
class CSignalLogger
  {
private:
   string            m_filename;
   string            m_outcomeFilename;
   string            m_smcFilename;
   bool              m_smcHeaderWritten;
   bool              m_headerWritten;
   bool              m_outcomeHeaderWritten;
   int               m_gmtOffsetOverrideHours; // 999 = auto-detect

   string            SessionForGMTHour(int h);
   int               ServerToGMTOffsetHours();
   string            SessionLabel(datetime serverTime);
   string            ReasonString(SetupReasons &r);
   string            FillPolicyLabel(ENUM_FILL_POLICY fp);
   string            FibZoneLabel(ENUM_FIB_ZONE z);
   string            VAZoneLabel(ENUM_VALUE_AREA_ZONE z);
   string            VolRegimeLabel(ENUM_VOL_REGIME v);
   string            OBStateLabel(ENUM_OB_STATE s);
   string            RegimeLabel(ENUM_MARKET_REGIME r);       // v2.12
   string            BreakoutClassLabel(ENUM_BREAKOUT_CLASS c); // v2.12
   string            ReversionClassLabel(ENUM_REVERSION_CLASS c); // v2.13
   string            KeyLevelSourceLabel(ENUM_KEYLEVEL_SOURCE s);     // v2.14
   string            KeyLevelReactionLabel(ENUM_KEYLEVEL_REACTION r); // v2.14
   string            SelectedStrategyLabel(ENUM_SELECTED_STRATEGY s); // v2.15
   string            SMCStateLabel(ENUM_SMC_STRUCTURE_STATE s);

public:
                     CSignalLogger();
   void              Init(string symbol, int gmtOffsetOverrideHours = 999);
   bool              LogSetup(TradeSetup &setup, string symbol, ENUM_TIMEFRAMES entryTF, string trendLabel);
   bool              LogSMCStructure(TradeSetup &setup, string symbol, ENUM_TIMEFRAMES entryTF);
   bool              LogOutcome(PendingSetup &p, string symbol, ENUM_TIMEFRAMES entryTF, string outcome,
                                double exitPrice, ENUM_FILL_POLICY fillPolicy = FILL_CONSERVATIVE,
                                datetime outcomeTime = 0);
  };
//+------------------------------------------------------------------+
CSignalLogger::CSignalLogger() : m_headerWritten(false), m_outcomeHeaderWritten(false), m_smcHeaderWritten(false), m_gmtOffsetOverrideHours(999) {}
//+------------------------------------------------------------------+
void CSignalLogger::Init(string symbol, int gmtOffsetOverrideHours)
  {
   m_filename = "MedisTouch_Signals_" + symbol + ".csv";
    m_smcFilename = "MedisTouch_SMC_Structures_" + symbol + ".csv";
    m_smcHeaderWritten = FileIsExist(m_smcFilename);
   // Version the outcome stream because the new OutcomeEpoch column is required by the
   // chronological evidence builder. Never append new-schema rows to a legacy header.
   m_outcomeFilename = "MedisTouch_Outcomes_v2_" + symbol + ".csv";
   m_headerWritten = FileIsExist(m_filename);
   m_outcomeHeaderWritten = FileIsExist(m_outcomeFilename);
   m_gmtOffsetOverrideHours = gmtOffsetOverrideHours;
  }
//+------------------------------------------------------------------+
// FIX: v4 used the raw server hour as a proxy for session, which is only
// correct if the broker's server clock happens to run on GMT — most
// don't (common offsets are GMT+2/+3, sometimes with their own DST
// schedule that doesn't match any real session's DST). This computes the
// actual live offset each call via TimeTradeServer() - TimeGMT(), so it
// self-corrects across DST transitions instead of drifting for months.
//
// CAVEAT: TimeGMT() depends on the terminal's Windows GMT/timezone
// database being current, and can behave inconsistently inside the
// Strategy Tester on some builds. InpSessionGMTOffsetOverride exists
// specifically so you can pin a known-correct offset if you ever see the
// auto-detected value look wrong for your broker.
int CSignalLogger::ServerToGMTOffsetHours()
  {
   if(m_gmtOffsetOverrideHours != 999)
      return m_gmtOffsetOverrideHours;
   datetime srv = TimeTradeServer();
   datetime gmt = TimeGMT();
   double hours = (double)(srv - gmt) / 3600.0;
   return (int)MathRound(hours);
  }
//+------------------------------------------------------------------+
string CSignalLogger::SessionForGMTHour(int h)
  {
   h = ((h % 24) + 24) % 24; // normalize
   bool sydney = (h >= 21 || h < 6);
   bool tokyo  = (h >= 0  && h < 9);
   bool london = (h >= 7  && h < 16);
   bool ny     = (h >= 12 && h < 21);

   if(london && ny)    return "London/NY Overlap";
   if(tokyo && london) return "Tokyo/London Overlap";
   if(sydney && tokyo) return "Sydney/Tokyo Overlap";
   if(london) return "London";
   if(ny)     return "New York";
   if(tokyo)  return "Tokyo";
   if(sydney) return "Sydney";
   return "Off-hours";
  }
//+------------------------------------------------------------------+
string CSignalLogger::SessionLabel(datetime serverTime)
  {
   int offset = ServerToGMTOffsetHours();
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int gmtHour = dt.hour - offset;
   return SessionForGMTHour(gmtHour);
  }
//+------------------------------------------------------------------+
string CSignalLogger::ReasonString(SetupReasons &r)
  {
   string s = "";
   if(r.trend_aligned)   s += "Trend|";
   if(r.bos_confirmed)   s += "BOS|";
   if(r.liquidity_swept) s += "Liquidity|";
   if(r.fresh_fvg)       s += "FVG|";
   if(r.sr_confluence)   s += "SR|";
   if(r.inducement_valid) s += "Inducement|";
   if(r.premium_discount_ok) s += "PremDisc|";
   if(r.volume_confirmed) s += "Volume|";
   if(r.fib_in_zone) s += "FibZone|";
   if(r.value_area_ok) s += "ValueArea|";
   if(r.value_area_contradiction) s += "ValueAreaConflict|";
   if(r.htf_ob_confluence) s += "HtfOB|";
   if(!r.session_ok) s += "OffSession|";
   if(StringLen(s) == 0) return "None";
   return s;
  }
//+------------------------------------------------------------------+
string CSignalLogger::VolRegimeLabel(ENUM_VOL_REGIME v)
  {
   switch(v)
     {
      case VOL_REGIME_LOW:    return "Low";
      case VOL_REGIME_NORMAL: return "Normal";
      case VOL_REGIME_HIGH:   return "High";
      default:                return "Undefined";
     }
  }
//+------------------------------------------------------------------+
string CSignalLogger::OBStateLabel(ENUM_OB_STATE s)
  {
   switch(s)
     {
      case OB_FRESH:     return "Fresh";
      case OB_TESTED:     return "Tested";
      case OB_MITIGATED:  return "Mitigated";
      default:            return "None";
     }
  }
//+------------------------------------------------------------------+
// v2.12
string CSignalLogger::RegimeLabel(ENUM_MARKET_REGIME r)
  {
   switch(r)
     {
      case REGIME_TRENDING:    return "Trending";
      case REGIME_RANGING:     return "Ranging";
      case REGIME_TRANSITION:  return "Transition";
      default:                 return "Undefined";
     }
  }
//+------------------------------------------------------------------+
// v2.12
string CSignalLogger::BreakoutClassLabel(ENUM_BREAKOUT_CLASS c)
  {
   switch(c)
     {
      case BREAKOUT_EXPANSION:  return "Expansion";
      case BREAKOUT_LIQUIDITY:  return "Liquidity";
      case BREAKOUT_FAILED:     return "Failed";
      case BREAKOUT_EXHAUSTION: return "Exhaustion";
      default:                  return "None";
     }
  }
//+------------------------------------------------------------------+
// v2.13
string CSignalLogger::ReversionClassLabel(ENUM_REVERSION_CLASS c)
  {
   switch(c)
     {
      case REVERSION_VALUE_FADE:      return "ValueFade";
      case REVERSION_LEVEL_REJECTION: return "LevelRejection";
      case REVERSION_TREND_CONFLICT:  return "TrendConflict";
      default:                        return "None";
     }
  }
//+------------------------------------------------------------------+
// v2.14. v2.17: added the three sources that pass added — see
// Core/Config.mqh's ENUM_KEYLEVEL_SOURCE and SmartMoney/ExtendedKeyLevels.mqh.
// Without these three cases here, LEVEL_PREV_WEEK/LEVEL_SESSION/
// LEVEL_PSYCHOLOGICAL would silently fall through to "None" in the CSV —
// a level WAS found and acted on, but the log would say otherwise.
string CSignalLogger::KeyLevelSourceLabel(ENUM_KEYLEVEL_SOURCE s)
  {
   switch(s)
     {
      case LEVEL_SR:              return "SR";
      case LEVEL_ORDER_BLOCK:      return "OrderBlock";
      case LEVEL_VALUE_AREA:       return "ValueArea";
      case LEVEL_LIQUIDITY_POOL:   return "LiquidityPool";
      case LEVEL_PREV_WEEK:        return "PrevWeek";
      case LEVEL_SESSION:          return "Session";
      case LEVEL_PSYCHOLOGICAL:    return "Psychological";
      default:                     return "None";
     }
  }
//+------------------------------------------------------------------+
// v2.14
string CSignalLogger::KeyLevelReactionLabel(ENUM_KEYLEVEL_REACTION r)
  {
   switch(r)
     {
      case REACTION_REJECTION:     return "Rejection";
      case REACTION_BREAK:         return "Break";
      case REACTION_RETEST:        return "Retest";
      case REACTION_FAILED_BREAK:  return "FailedBreak";
      case REACTION_ACCEPTANCE:    return "Acceptance";
      case REACTION_ABSORPTION:    return "Absorption";
      default:                     return "None";
     }
  }
//+------------------------------------------------------------------+
// v2.15
string CSignalLogger::SelectedStrategyLabel(ENUM_SELECTED_STRATEGY s)
  {
   switch(s)
     {
      case STRATEGY_SMC:                return "SMC";
      case STRATEGY_MOMENTUM_BREAKOUT:   return "MomentumBreakout";
      case STRATEGY_MEAN_REVERSION:      return "MeanReversion";
      case STRATEGY_KEY_LEVEL:           return "KeyLevel";
      default:                           return "None";
     }
  }
//+------------------------------------------------------------------+
string CSignalLogger::VAZoneLabel(ENUM_VALUE_AREA_ZONE z)
  {
   switch(z)
     {
      case VA_ZONE_BELOW:  return "Below";
      case VA_ZONE_INSIDE: return "Inside";
      case VA_ZONE_ABOVE:  return "Above";
      default:             return "Undefined";
     }
  }
//+------------------------------------------------------------------+
string CSignalLogger::FibZoneLabel(ENUM_FIB_ZONE z)
  {
   switch(z)
     {
      case FIB_ZONE_DISCOUNT: return "Discount";
      case FIB_ZONE_NEUTRAL:  return "Neutral";
      case FIB_ZONE_PREMIUM:  return "Premium";
      default:                return "Undefined";
     }
  }
//+------------------------------------------------------------------+
string CSignalLogger::FillPolicyLabel(ENUM_FILL_POLICY fp)
  {
   string s = EnumToString(fp);
   StringReplace(s, "FILL_", "");
   return s;
  }
//+------------------------------------------------------------------+
string CSignalLogger::SMCStateLabel(ENUM_SMC_STRUCTURE_STATE s)
  {
   switch(s)
     {
      case SMC_VALID:       return "Valid";
      case SMC_INVALID:     return "Invalid";
      case SMC_STALE:       return "Stale";
      case SMC_INVALIDATED: return "Invalidated";
      default:              return "Wait";
     }
  }
//+------------------------------------------------------------------+
bool CSignalLogger::LogSetup(TradeSetup &setup, string symbol, ENUM_TIMEFRAMES entryTF, string trendLabel)
  {
   if(!setup.active) return false;

   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_ANSI;
   int handle = FileOpen(m_filename, flags, ',');
   if(handle == INVALID_HANDLE)
     {
      Print("MedisTouch SignalLogger: failed to open ", m_filename, " err=", GetLastError());
      return false;
     }

   if(!m_headerWritten)
     {
      FileWrite(handle, "SignalID", "Symbol", "EntryTF", "DateTime", "Session", "Trend", "Direction",
               "Confidence", "EntryTop", "EntryBottom", "StopLoss", "TP1", "TP2", "FinalTP",
               "Reasons", "RiskWarning", "RVOL", "VolumeConfirmed", "FibZone", "FibInZone", "FibNearestLevel",
               "VAZone", "ValueAreaOK", "POC", "VAH", "VAL",
               "VAProfileSource", "VAProfileState", "VAPOCMigrationATR", "VASourceQuality", "VAScore", "VAContradiction",
               "HtfOBConfluence", "HtfOBState", "VolRegime", "SessionOK",
               // v2.10 diagnostics. Appended, never inserted: parsers keyed
               // on column position keep working.
               "ContradictionPenalty", "EnvScore", "ExecScore", "EnvExecConfidence",
               // v2.12 diagnostics — same append-only discipline.
               "Regime", "MomentumScore", "BreakoutScore", "BreakoutClass",
               // v2.13 diagnostics — same append-only discipline.
               "ReversionScore", "ReversionClass",
               // v2.14 diagnostics — same append-only discipline.
               "KeyLevelSource", "KeyLevelReaction", "KeyLevelScore",
               // v2.15 diagnostics — same append-only discipline.
               "SelectedStrategy", "SelectedStrategyScore");
      m_headerWritten = true;
     }

   FileSeek(handle, 0, SEEK_END);
   string session = SessionLabel(setup.creation_time);
   string dir = (setup.type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   string risk = (StringLen(setup.reasons.risk_warning) > 0) ? setup.reasons.risk_warning : "None";
   // SignalID joins this row to its eventual outcome row in the Outcomes
   // CSV — just the creation timestamp + direction, unique enough for a
   // single-symbol, single-instance signal stream.
   string signalId = StringFormat("%s_%s_%d", symbol, dir, (long)setup.creation_time);

   FileWrite(handle, signalId, symbol, EnumToString(entryTF), TimeToString(setup.creation_time, TIME_DATE | TIME_MINUTES),
            session, trendLabel, dir, DoubleToString(setup.confidence, 1),
            DoubleToString(setup.entry_top, _Digits), DoubleToString(setup.entry_bottom, _Digits),
            DoubleToString(setup.stop_loss, _Digits), DoubleToString(setup.tp1, _Digits),
            DoubleToString(setup.tp2, _Digits), DoubleToString(setup.final_tp, _Digits),
            ReasonString(setup.reasons), risk,
            DoubleToString(setup.reasons.rvol, 2), setup.reasons.volume_confirmed ? "Yes" : "No",
            FibZoneLabel(setup.reasons.fib_zone), setup.reasons.fib_in_zone ? "Yes" : "No",
            DoubleToString(setup.reasons.fib_nearest_level, _Digits),
            VAZoneLabel(setup.reasons.va_zone), setup.reasons.value_area_ok ? "Yes" : "No",
            DoubleToString(setup.reasons.va_poc, _Digits), DoubleToString(setup.reasons.va_high, _Digits),
            DoubleToString(setup.reasons.va_low, _Digits),
            EnumToString(setup.reasons.value_profile_source), EnumToString(setup.reasons.value_profile_state),
            DoubleToString(setup.reasons.va_poc_migration_atr, 3), DoubleToString(setup.reasons.va_source_quality, 2),
            DoubleToString(setup.reasons.va_score, 3), setup.reasons.value_area_contradiction ? "Yes" : "No",
            setup.reasons.htf_ob_confluence ? "Yes" : "No", OBStateLabel(setup.reasons.htf_ob_state),
            VolRegimeLabel(setup.reasons.vol_regime), setup.reasons.session_ok ? "Yes" : "No",
            DoubleToString(setup.reasons.contradiction_penalty, 3),
            DoubleToString(setup.reasons.env_score, 3),
            DoubleToString(setup.reasons.exec_score, 3),
            DoubleToString(setup.reasons.env_exec_confidence, 1),
            RegimeLabel(setup.reasons.regime),
            DoubleToString(setup.reasons.momentum_score, 1),
            DoubleToString(setup.reasons.breakout_score, 1),
            BreakoutClassLabel(setup.reasons.breakout_class),
            DoubleToString(setup.reasons.reversion_score, 1),
            ReversionClassLabel(setup.reasons.reversion_class),
            KeyLevelSourceLabel(setup.reasons.keylevel_source),
            KeyLevelReactionLabel(setup.reasons.keylevel_reaction),
            DoubleToString(setup.reasons.keylevel_score, 1),
            SelectedStrategyLabel(setup.reasons.selected_strategy),
            DoubleToString(setup.reasons.selected_strategy_score, 1));

   FileClose(handle);
   return true;
  }
//+------------------------------------------------------------------+
bool CSignalLogger::LogOutcome(PendingSetup &p, string symbol, ENUM_TIMEFRAMES entryTF, string outcome,
                               double exitPrice, ENUM_FILL_POLICY fillPolicy, datetime outcomeTime)
  {
   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_ANSI;
   int handle = FileOpen(m_outcomeFilename, flags, ',');
   if(handle == INVALID_HANDLE)
     {
      Print("MedisTouch SignalLogger: failed to open ", m_outcomeFilename, " err=", GetLastError());
      return false;
     }

   if(!m_outcomeHeaderWritten)
     {
      FileWrite(handle, "SignalID", "Symbol", "EntryTF", "Direction", "Outcome", "ExitPrice",
               "EntryRef", "RiskDistance", "Filled", "FillTime", "BarsToFill", "MFE_Price", "MAE_Price",
               "MFE_R", "MAE_R", "TP1_Hit", "TP2_Hit", "BarsHeld", "SameBarSLTPCollision", "FillPolicy",
               "Lots", "EntryFillPrice", "BreakEvenDone", "PartialDone", "RealizedNetPnL", "RealizedR",
               "Commission", "SpreadCost", "SlippageCost",
               // v2.10 - the decay diagnostic, paired with the resolved
               // outcome so the retraining pipeline can test whether
               // staleness actually predicts a worse result.
               "ConfidenceAtSignal", "ConfidenceDecayed", "DecayBars",
               // v2.20 — repeated from the signal row for self-contained outcome analysis.
               "VAProfileSource", "VAProfileState", "VAPOCMigrationATR", "VASourceQuality", "VAScore", "VAContradiction",
               // Repeated from the signal row so an outcomes file is
               // self-sufficient for fitting the multiplicative model.
               "ContradictionPenalty", "EnvScore", "ExecScore", "EnvExecConfidence",
               // v2.12 — same "repeated from the signal row" rationale.
               "Regime", "MomentumScore", "BreakoutScore", "BreakoutClass",
               // v2.13 — same rationale.
               "ReversionScore", "ReversionClass",
               // v2.14 — same rationale.
               "KeyLevelSource", "KeyLevelReaction", "KeyLevelScore",
               // v2.15 — same rationale. OutcomeEpoch is appended so legacy
               // positional columns remain stable in this versioned outcome file.
               "SelectedStrategy", "SelectedStrategyScore", "OutcomeEpoch");
      m_outcomeHeaderWritten = true;
     }

   FileSeek(handle, 0, SEEK_END);
   string dir = (p.setup.type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   string signalId = StringFormat("%s_%s_%d", symbol, dir, (long)p.setup.creation_time);

   double mfeR = 0.0, maeR = 0.0;
   if(p.filled && p.riskDist > 0)
     {
      double mfeDist = (p.setup.type == ORDER_TYPE_BUY) ? (p.mfePrice - p.entryRef) : (p.entryRef - p.mfePrice);
      double maeDist = (p.setup.type == ORDER_TYPE_BUY) ? (p.entryRef - p.maePrice) : (p.maePrice - p.entryRef);
      mfeR = mfeDist / p.riskDist;
      maeR = maeDist / p.riskDist;
     }

   // Realized R uses mgmtRiskDist (the same basis the simulator's
   // breakeven/partial triggers are computed against) converted to a
   // dollar risk-per-1R for this trade's actual lot size — 0 if the
   // trade was never sized (lots<=0, e.g. risk% below broker minimum).
   double realizedR = 0.0;
   if(p.lots > 0 && p.mgmtRiskDist > 0)
     {
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize > 0 && tickValue > 0)
        {
         double oneRDollar = p.mgmtRiskDist * (tickValue / tickSize) * p.lots;
         if(oneRDollar > 0) realizedR = p.realizedPnL / oneRDollar;
        }
     }

   datetime resolvedAt = outcomeTime;
   // Do not infer a resolution timestamp from the last bar's opening time.
   // A caller without an explicit resolution epoch leaves zero; the strict
   // evidence builder rejects the row rather than inventing chronology.
   FileWrite(handle, signalId, symbol, EnumToString(entryTF), dir, outcome,
            DoubleToString(exitPrice, _Digits), DoubleToString(p.entryRef, _Digits),
            DoubleToString(p.riskDist, _Digits), p.filled ? "Yes" : "No",
            p.filled ? TimeToString(p.fillTime, TIME_DATE | TIME_MINUTES) : "",
            p.filled ? p.barsToFill : 0,
            DoubleToString(p.mfePrice, _Digits), DoubleToString(p.maePrice, _Digits),
            DoubleToString(mfeR, 2), DoubleToString(maeR, 2),
            p.tp1Hit ? "Yes" : "No", p.tp2Hit ? "Yes" : "No", p.barsElapsed,
            p.sameBarCollision ? "Yes" : "No", FillPolicyLabel(fillPolicy),
            DoubleToString(p.lots, 2), DoubleToString(p.entryFillPrice, _Digits),
            p.beDone ? "Yes" : "No", p.partialDone ? "Yes" : "No",
            DoubleToString(p.realizedPnL, 2), DoubleToString(realizedR, 2),
            DoubleToString(p.totalCommission, 2), DoubleToString(p.totalSpreadCost, 2),
            DoubleToString(p.totalSlippageCost, 2),
            DoubleToString(p.confidenceAtSignal, 1), DoubleToString(p.confidenceDecayed, 1),
            p.decayBars,
            EnumToString(p.setup.reasons.value_profile_source), EnumToString(p.setup.reasons.value_profile_state),
            DoubleToString(p.setup.reasons.va_poc_migration_atr, 3), DoubleToString(p.setup.reasons.va_source_quality, 2),
            DoubleToString(p.setup.reasons.va_score, 3), p.setup.reasons.value_area_contradiction ? "Yes" : "No",
            DoubleToString(p.setup.reasons.contradiction_penalty, 3),
            DoubleToString(p.setup.reasons.env_score, 3),
            DoubleToString(p.setup.reasons.exec_score, 3),
            DoubleToString(p.setup.reasons.env_exec_confidence, 1),
            RegimeLabel(p.setup.reasons.regime),
            DoubleToString(p.setup.reasons.momentum_score, 1),
            DoubleToString(p.setup.reasons.breakout_score, 1),
            BreakoutClassLabel(p.setup.reasons.breakout_class),
            DoubleToString(p.setup.reasons.reversion_score, 1),
            ReversionClassLabel(p.setup.reasons.reversion_class),
            KeyLevelSourceLabel(p.setup.reasons.keylevel_source),
            KeyLevelReactionLabel(p.setup.reasons.keylevel_reaction),
            DoubleToString(p.setup.reasons.keylevel_score, 1),
            SelectedStrategyLabel(p.setup.reasons.selected_strategy),
            DoubleToString(p.setup.reasons.selected_strategy_score, 1),
            (long)resolvedAt);

   FileClose(handle);
   return true;
  }
bool CSignalLogger::LogSMCStructure(TradeSetup &setup, string symbol, ENUM_TIMEFRAMES entryTF)
  {
   if(setup.reasons.selected_strategy != STRATEGY_SMC || setup.creation_time <= 0) return false;

   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_ANSI;
   int handle = FileOpen(m_smcFilename, flags, ',');
   if(handle == INVALID_HANDLE)
     {
      Print("MedisTouch SignalLogger: failed to open ", m_smcFilename, " err=", GetLastError());
      return false;
     }

   if(!m_smcHeaderWritten)
     {
      FileWrite(handle, "SignalID", "Symbol", "EntryTF", "DateTime", "Direction",
               "State", "StructuralValid", "HTFStructureValid", "RegimeApplicable",
               "LiquidityTargetValid", "SweepValid", "DisplacementValid", "BOSValid",
               "FVGCausal", "OrderBlockCausal", "HTFOBPresent", "PremiumDiscountValid",
               "FreshnessValid", "InvalidationClear", "ProtectedLevel", "InvalidationLevel",
               "SweepBarIndex", "BOSBarIndex", "DisplacementBarIndex", "EntryFVGBarIndex", "CausalOBBarIndex",
               "FailureReason");
      m_smcHeaderWritten = true;
     }

   FileSeek(handle, 0, SEEK_END);
   string dir = (setup.type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   string signalId = StringFormat("%s_%s_%d", symbol, dir, (long)setup.creation_time);

   FileWrite(handle, signalId, symbol, EnumToString(entryTF),
             TimeToString(setup.creation_time, TIME_DATE | TIME_MINUTES), dir,
             SMCStateLabel(setup.reasons.smc_state),
             setup.reasons.smc_structural_valid ? "Yes" : "No",
             setup.reasons.smc_htf_structure_valid ? "Yes" : "No",
             setup.reasons.smc_regime_applicable ? "Yes" : "No",
             setup.reasons.smc_liquidity_target_valid ? "Yes" : "No",
             setup.reasons.smc_sweep_valid ? "Yes" : "No",
             setup.reasons.smc_displacement_valid ? "Yes" : "No",
             setup.reasons.smc_bos_valid ? "Yes" : "No",
             setup.reasons.smc_fvg_causal ? "Yes" : "No",
             setup.reasons.smc_order_block_causal ? "Yes" : "No",
             setup.reasons.smc_htf_ob_present ? "Yes" : "No",
             setup.reasons.smc_premium_discount_valid ? "Yes" : "No",
             setup.reasons.smc_freshness_valid ? "Yes" : "No",
             setup.reasons.smc_invalidation_clear ? "Yes" : "No",
             DoubleToString(setup.reasons.smc_protected_level, _Digits),
             DoubleToString(setup.reasons.smc_invalidation_level, _Digits),
             setup.reasons.smc_sweep_bar_index,
             setup.reasons.smc_bos_bar_index,
             setup.reasons.smc_displacement_bar_index,
             setup.reasons.smc_entry_fvg_bar_index,
             setup.reasons.smc_causal_ob_bar_index,
             setup.reasons.smc_failure_reason);

   FileClose(handle);
   return true;
  }
//+------------------------------------------------------------------+
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Core/SignalLogger.mqh
// BEGIN INLINED MODULE: includes/Analysis/TFContext.mqh
//+------------------------------------------------------------------+
//|                                            Analysis/TFContext.mqh |
//+------------------------------------------------------------------+
#ifndef TFCONTEXT_MQH
#define TFCONTEXT_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// BEGIN INLINED MODULE: includes/Structure/SwingDetector.mqh
//+------------------------------------------------------------------+
//|                                        Structure/SwingDetector.mqh |
//+------------------------------------------------------------------+
#ifndef SWINGDETECTOR_MQH
#define SWINGDETECTOR_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh

class CSwingDetector
  {
private:
   CCandleData*      m_candles;
   int               m_strength;
   SwingPoint        m_swingHighs[];
   SwingPoint        m_swingLows[];
   int               m_highCount;
   int               m_lowCount;

   bool              IsSwingHigh(int idx);
   bool              IsSwingLow(int idx);
   double            CalcStrength(int idx);

public:
                     CSwingDetector();
   void              SetParameters(CCandleData* candleData, int strength = 3);
   void              Detect();

   int               HighCount() const { return m_highCount; }
   int               LowCount() const { return m_lowCount; }
   int               Strength() const { return m_strength; }
   SwingPoint        GetHigh(int i) const;
   SwingPoint        GetLow(int i) const;
  };
//+------------------------------------------------------------------+
CSwingDetector::CSwingDetector()
  {
   m_candles = NULL;
   m_strength = 3;
   m_highCount = 0;
   m_lowCount = 0;
  }
//+------------------------------------------------------------------+
void CSwingDetector::SetParameters(CCandleData* candleData, int strength)
  {
   m_candles = candleData;
   m_strength = MathMax(1, strength);
  }
//+------------------------------------------------------------------+
// Series convention: 0 is the currently forming bar, 1 is the most
// recently completed bar. A confirmed swing must NEVER use shift 0.
bool CSwingDetector::IsSwingHigh(int idx)
  {
   if(m_candles == NULL) return false;
   int total = m_candles.Total();
   if(idx <= m_strength || idx >= total - m_strength) return false;
   double high = m_candles.GetCandle(idx).high;
   for(int i = 1; i <= m_strength; i++)
     {
      if(m_candles.GetCandle(idx - i).high >= high) return false;
      if(m_candles.GetCandle(idx + i).high >= high) return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
bool CSwingDetector::IsSwingLow(int idx)
  {
   if(m_candles == NULL) return false;
   int total = m_candles.Total();
   if(idx <= m_strength || idx >= total - m_strength) return false;
   double low = m_candles.GetCandle(idx).low;
   for(int i = 1; i <= m_strength; i++)
     {
      if(m_candles.GetCandle(idx - i).low <= low) return false;
      if(m_candles.GetCandle(idx + i).low <= low) return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
double CSwingDetector::CalcStrength(int idx)
  {
   CandleData cd = m_candles.GetCandle(idx);
   double range = cd.high - cd.low;
   double atr = cd.atr;
   if(atr <= 0) return 0.5;
   return MathMin(range / atr, 1.0);
  }
//+------------------------------------------------------------------+
void CSwingDetector::Detect()
  {
   m_highCount = 0;
   m_lowCount = 0;
   if(m_candles == NULL) return;
   int total = m_candles.Total();
   // +1 excludes any swing whose confirmation window reaches shift 0.
   if(total < 2 * m_strength + 2) return;
   ArrayResize(m_swingHighs, total);
   ArrayResize(m_swingLows, total);

   // Oldest -> newest. The newest eligible swing is at least `strength`
   // completed bars behind shift 1, so it is fully confirmed.
   for(int i = total - m_strength - 1; i >= m_strength + 1; i--)
     {
      if(IsSwingHigh(i))
        {
         SwingPoint sp;
         sp.time = m_candles.GetCandle(i).time;
         sp.price = m_candles.GetCandle(i).high;
         sp.is_high = true;
         sp.bar_index = i;
         sp.strength = CalcStrength(i);
         m_swingHighs[m_highCount++] = sp;
        }
      if(IsSwingLow(i))
        {
         SwingPoint sp;
         sp.time = m_candles.GetCandle(i).time;
         sp.price = m_candles.GetCandle(i).low;
         sp.is_high = false;
         sp.bar_index = i;
         sp.strength = CalcStrength(i);
         m_swingLows[m_lowCount++] = sp;
        }
     }
   ArrayResize(m_swingHighs, m_highCount);
   ArrayResize(m_swingLows, m_lowCount);

   // Public contract: index 0 = most recent.
   for(int j = 0; j < m_highCount / 2; j++)
     {
      SwingPoint t = m_swingHighs[j];
      m_swingHighs[j] = m_swingHighs[m_highCount - 1 - j];
      m_swingHighs[m_highCount - 1 - j] = t;
     }
   for(int j = 0; j < m_lowCount / 2; j++)
     {
      SwingPoint t = m_swingLows[j];
      m_swingLows[j] = m_swingLows[m_lowCount - 1 - j];
      m_swingLows[m_lowCount - 1 - j] = t;
     }
  }
//+------------------------------------------------------------------+
SwingPoint CSwingDetector::GetHigh(int i) const
  {
   SwingPoint empty;
   ZeroMemory(empty);
   if(i < 0 || i >= m_highCount) return empty;
   return m_swingHighs[i];
  }
//+------------------------------------------------------------------+
SwingPoint CSwingDetector::GetLow(int i) const
  {
   SwingPoint empty;
   ZeroMemory(empty);
   if(i < 0 || i >= m_lowCount) return empty;
   return m_swingLows[i];
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Structure/SwingDetector.mqh
// BEGIN INLINED MODULE: includes/Structure/BOS.mqh
//+------------------------------------------------------------------+
//|                                                   Structure/BOS.mqh |
//+------------------------------------------------------------------+
#ifndef BOS_MQH
#define BOS_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh

class CBOS
  {
private:
   CSwingDetector*   m_swings;
   CCandleData*      m_candles;
   BOSEvent          m_bosList[];
   int               m_bosCount;

   double            BreakoutStrength(int shift, double atr, const CandleData &cd, double brokenLevel) const;

public:
                     CBOS();
   void              Init(CSwingDetector* swingDetector, CCandleData* candleData);
   void              Detect();
   int               Count() const { return m_bosCount; }
   BOSEvent          GetBOS(int i) const;  // 0 = most recent
  };
//+------------------------------------------------------------------+
CBOS::CBOS() : m_swings(NULL), m_candles(NULL), m_bosCount(0) {}
void CBOS::Init(CSwingDetector* swingDetector, CCandleData* candleData)
  {
   m_swings = swingDetector;
   m_candles = candleData;
  }
//+------------------------------------------------------------------+
// (a) how far price closed beyond the broken level, relative to ATR, and
// (b) whether the breakout candle traded on above-average volume vs the
// prior 10 bars.
double CBOS::BreakoutStrength(int shift, double atr, const CandleData &cd, double brokenLevel) const
  {
   double breakoutDistATR = MathAbs(cd.close - brokenLevel) / atr;
   double avgVol = 0.0;
   int n = 0;
   for(int b = shift + 1; b <= shift + 10 && b < m_candles.Total(); b++)
     {
      avgVol += (double)m_candles.GetCandle(b).tick_volume;
      n++;
     }
   double volRatio = (n > 0 && avgVol > 0) ? ((double)cd.tick_volume / (avgVol / n)) : 1.0;
   double s = 0.6 * MathMin(breakoutDistATR / 1.0, 1.0) + 0.4 * MathMin(volRatio / 2.0, 1.0);
   return MathMax(0.0, MathMin(s, 1.0));
  }
//+------------------------------------------------------------------+
// FIX (audit #7 — lookahead bias): the previous implementation picked
// ONE swing — "the most recent lower high in TODAY's fully up-to-date
// swing list" — and then scanned every historical bar (i = 1..total-1)
// checking whether ITS close broke THAT SAME swing. Two bars from
// entirely different points in history were being judged against a
// single "lower high" that may not have existed, or even been
// CONFIRMED yet (a swing needs `strength` bars of later data before
// it's a swing at all), at the time those older bars actually printed.
// That's lookahead: a historical BOS could be "confirmed" using
// structure the market didn't have yet.
//
// This rewrite is a single chronological forward pass (oldest bar to
// newest). It tracks the currently active, not-yet-broken "lower high" /
// "higher low" candidate, but only ever promotes a swing into that role
// once the swing itself is CONFIRMED as of the current bar (bar_index -
// strength >= current shift — i.e. `strength` bars have already printed
// after it). A BOS event is only recorded on the bar that closes beyond
// an ALREADY-CONFIRMED candidate, in time order. This is chronologically
// sound: every BOS event only ever depends on data that existed on or
// before its own bar.
void CBOS::Detect()
  {
   m_bosCount = 0;
   if(m_swings == NULL || m_candles == NULL) return;
   int total = m_candles.Total();
   if(total < 2) return;
   int strength = m_swings.Strength();

   int nHighs = m_swings.HighCount();
   int nLows  = m_swings.LowCount();

   // GetHigh(0)/GetLow(0) = newest, larger index = older. Reverse into
   // oldest-first order so we can walk them alongside the chronological
   // (oldest -> newest) candle scan below.
   SwingPoint highsChrono[];
   ArrayResize(highsChrono, nHighs);
   for(int i = 0; i < nHighs; i++) highsChrono[i] = m_swings.GetHigh(nHighs - 1 - i);
   SwingPoint lowsChrono[];
   ArrayResize(lowsChrono, nLows);
   for(int i = 0; i < nLows; i++) lowsChrono[i] = m_swings.GetLow(nLows - 1 - i);

   int highPtr = 0, lowPtr = 0;
   bool havePrevHigh = false, havePrevLow = false;
   SwingPoint prevHigh, prevLow;
   ZeroMemory(prevHigh); ZeroMemory(prevLow);
   bool haveActiveLowerHigh = false, haveActiveHigherLow = false;
   SwingPoint activeLowerHigh, activeHigherLow;
   ZeroMemory(activeLowerHigh); ZeroMemory(activeHigherLow);

   BOSEvent chrono[]; // built oldest -> newest, reversed into m_bosList at the end
   ArrayResize(chrono, total);
   int chronoCount = 0;

   for(int shift = total - 1; shift >= 1; shift--) // oldest -> newest
     {
      // Confirm any swings whose confirmation point has now arrived
      // (chronologically: a swing at bar_index needs `strength` later
      // bars to exist before it counts as confirmed structure).
      while(highPtr < nHighs && (highsChrono[highPtr].bar_index - strength) >= shift)
        {
         SwingPoint h = highsChrono[highPtr];
         if(havePrevHigh && h.price < prevHigh.price) // freshly-confirmed lower high
           {
            activeLowerHigh = h;
            haveActiveLowerHigh = true;
           }
         prevHigh = h;
         havePrevHigh = true;
         highPtr++;
        }
      while(lowPtr < nLows && (lowsChrono[lowPtr].bar_index - strength) >= shift)
        {
         SwingPoint l = lowsChrono[lowPtr];
         if(havePrevLow && l.price > prevLow.price) // freshly-confirmed higher low
           {
            activeHigherLow = l;
            haveActiveHigherLow = true;
           }
         prevLow = l;
         havePrevLow = true;
         lowPtr++;
        }

      double atr = m_candles.GetATR(shift);
      if(atr <= 0) continue;
      CandleData cd = m_candles.GetCandle(shift);

      if(haveActiveLowerHigh)
        {
         double threshold = activeLowerHigh.price + 0.1 * atr;
         if(cd.close > threshold)
           {
            BOSEvent ev;
            ev.time = cd.time;
            ev.price = cd.close;
            ev.is_bullish = true;
            ev.strength = BreakoutStrength(shift, atr, cd, activeLowerHigh.price);
            ev.bar_index = shift;
            ev.label = "BOS UP";
            chrono[chronoCount++] = ev;
            haveActiveLowerHigh = false; // consumed — next lower high (if any) becomes the new candidate
           }
        }
      if(haveActiveHigherLow)
        {
         double threshold = activeHigherLow.price - 0.1 * atr;
         if(cd.close < threshold)
           {
            BOSEvent ev;
            ev.time = cd.time;
            ev.price = cd.close;
            ev.is_bullish = false;
            ev.strength = BreakoutStrength(shift, atr, cd, activeHigherLow.price);
            ev.bar_index = shift;
            ev.label = "BOS DOWN";
            chrono[chronoCount++] = ev;
            haveActiveHigherLow = false;
           }
        }
     }

   // chrono[] is oldest -> newest; GetBOS(0) must return the newest, so reverse on the way out.
   ArrayResize(m_bosList, chronoCount);
   for(int i = 0; i < chronoCount; i++)
      m_bosList[i] = chrono[chronoCount - 1 - i];
   m_bosCount = chronoCount;
  }
//+------------------------------------------------------------------+
BOSEvent CBOS::GetBOS(int i) const
  {
   BOSEvent empty;
   ZeroMemory(empty);
   if(i < 0 || i >= m_bosCount) return empty;
   return m_bosList[i];
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Structure/BOS.mqh
// BEGIN INLINED MODULE: includes/Structure/CHOCH.mqh
//+------------------------------------------------------------------+
//|                                                 Structure/CHOCH.mqh |
//+------------------------------------------------------------------+
#ifndef CHOCH_MQH
#define CHOCH_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh

class CCHOCH
  {
private:
   CSwingDetector*   m_swings;
   CCandleData*      m_candles;
   CHOCHPoint        m_choch[];
   int               m_count;

public:
                     CCHOCH();
   void              Init(CSwingDetector* swings, CCandleData* candles);
   void              Detect();
   int               Count() const { return m_count; }
   CHOCHPoint        Get(int i) const;
  };
//+------------------------------------------------------------------+
CCHOCH::CCHOCH() : m_swings(NULL), m_candles(NULL), m_count(0) {}
void CCHOCH::Init(CSwingDetector* swings, CCandleData* candles)
  {
   m_swings = swings;
   m_candles = candles;
  }
//+------------------------------------------------------------------+
void CCHOCH::Detect()
  {
   m_count = 0;
   if(m_swings == NULL || m_candles == NULL) return;
   ArrayResize(m_choch, 2);

   CHOCHPoint bull, bear;
   ZeroMemory(bull);
   ZeroMemory(bear);
   bool haveBull = false, haveBear = false;

   // Bearish -> Bullish CHoCH: a confirmed lower high is broken by a
   // completed candle. Shift 0 is deliberately excluded: a forming bar
   // must never manufacture a structure-shift event.
   int highCount = m_swings.HighCount();
   if(highCount >= 2)
     {
      for(int i = 0; i < highCount - 1; i++)
        {
         SwingPoint curr = m_swings.GetHigh(i);
         SwingPoint prev = m_swings.GetHigh(i + 1);
         if(curr.price < prev.price)
           {
            for(int bar = curr.bar_index - 1; bar >= 1; bar--)
              {
               CandleData cd = m_candles.GetCandle(bar);
               if(cd.close > curr.price)
                 {
                  bull.time = cd.time;
                  bull.price = curr.price;
                  bull.bullish = true;
                  bull.bar_index = bar;
                  haveBull = true;
                  break;
                 }
              }
            break;
           }
        }
     }

   // Bullish -> Bearish CHoCH: a confirmed higher low is broken by a
   // completed candle. Shift 0 is deliberately excluded for causality.
   int lowCount = m_swings.LowCount();
   if(lowCount >= 2)
     {
      for(int i = 0; i < lowCount - 1; i++)
        {
         SwingPoint curr = m_swings.GetLow(i);
         SwingPoint prev = m_swings.GetLow(i + 1);
         if(curr.price > prev.price)
           {
            for(int bar = curr.bar_index - 1; bar >= 1; bar--)
              {
               CandleData cd = m_candles.GetCandle(bar);
               if(cd.close < curr.price)
                 {
                  bear.time = cd.time;
                  bear.price = curr.price;
                  bear.bullish = false;
                  bear.bar_index = bar;
                  haveBear = true;
                  break;
                 }
              }
            break;
           }
        }
     }

   if(haveBull && haveBear)
     {
      if(bull.bar_index <= bear.bar_index)
        {
         m_choch[0] = bull;
         m_choch[1] = bear;
        }
      else
        {
         m_choch[0] = bear;
         m_choch[1] = bull;
        }
      m_count = 2;
     }
   else if(haveBull)
     {
      m_choch[0] = bull;
      m_count = 1;
     }
   else if(haveBear)
     {
      m_choch[0] = bear;
      m_count = 1;
     }
   ArrayResize(m_choch, m_count);
  }
//+------------------------------------------------------------------+
CHOCHPoint CCHOCH::Get(int i) const
  {
   CHOCHPoint empty;
   ZeroMemory(empty);
   if(i < 0 || i >= m_count) return empty;
   return m_choch[i];
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Structure/CHOCH.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/FVG.mqh
//+------------------------------------------------------------------+
//|                                                SmartMoney/FVG.mqh |
//+------------------------------------------------------------------+
#ifndef FVG_MQH
#define FVG_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh

class CFVG
  {
private:
   CCandleData*      m_candles;
   FVGZone           m_zones[];
   int               m_zoneCount;

   double            m_minSizeATR;

   void              UpdateState(FVGZone &zone);

public:
                     CFVG();
   void              Init(CCandleData* candleData, double minSizeATR = 0.1);
   void              Detect();
   int               Count() const { return m_zoneCount; }
   FVGZone           GetZone(int i) const;
   void              UpdateAllStates();
  };
//+------------------------------------------------------------------+
CFVG::CFVG() : m_candles(NULL), m_zoneCount(0), m_minSizeATR(0.1) {}
void CFVG::Init(CCandleData* candleData, double minSizeATR)
  {
   m_candles = candleData;
   m_minSizeATR = minSizeATR;
  }
//+------------------------------------------------------------------+
void CFVG::Detect()
  {
   m_zoneCount = 0;
   if(m_candles == NULL) return;
   ArrayFree(m_zones);
   int total = m_candles.Total();
   // A 3-candle FVG needs three completed candles. With series indexing,
   // shift 0 is forming, so the newest usable triplet is shifts 3,2,1.
   if(total < 4) return;

   // Scan newest completed triplets first. The newest candle in each
   // triplet is shift i-2 and must remain >= 1; this guarantees that a
   // forming candle can never create or resize an FVG.
   for(int i = 3; i < total; i++)
     {
      CandleData cd0 = m_candles.GetCandle(i - 2); // newest, completed
      CandleData cd1 = m_candles.GetCandle(i - 1); // middle, completed
      CandleData cd2 = m_candles.GetCandle(i);     // oldest, completed
      double atr = cd1.atr;
      if(atr <= 0) continue;

      if(cd0.low > cd2.high)
        {
         double gap = cd0.low - cd2.high;
         if(gap >= m_minSizeATR * atr)
           {
            FVGZone zone;
            zone.time = cd1.time;
            zone.top = cd0.low;
            zone.bottom = cd2.high;
            zone.dir = FVG_BULL;
            zone.state = FVG_FRESH;
            zone.width = gap / atr;
            zone.bar_index = i - 1;
            int n = m_zoneCount++;
            ArrayResize(m_zones, m_zoneCount);
            m_zones[n] = zone;
           }
        }
      else if(cd0.high < cd2.low)
        {
         double gap = cd2.low - cd0.high;
         if(gap >= m_minSizeATR * atr)
           {
            FVGZone zone;
            zone.time = cd1.time;
            zone.top = cd2.low;
            zone.bottom = cd0.high;
            zone.dir = FVG_BEAR;
            zone.state = FVG_FRESH;
            zone.width = gap / atr;
            zone.bar_index = i - 1;
            int n = m_zoneCount++;
            ArrayResize(m_zones, m_zoneCount);
            m_zones[n] = zone;
           }
        }
     }
  }
//+------------------------------------------------------------------+
void CFVG::UpdateAllStates()
  {
   for(int i = 0; i < m_zoneCount; i++)
      UpdateState(m_zones[i]);
  }
//+------------------------------------------------------------------+
void CFVG::UpdateState(FVGZone &zone)
  {
   if(zone.state == FVG_MITIGATED || zone.state == FVG_INVALIDATED)
      return;
   int total = m_candles.Total();
   for(int bar = 1; bar < total; bar++)
     {
      CandleData cd = m_candles.GetCandle(bar);
      if(cd.time < zone.time)
         break;
      if(zone.dir == FVG_BULL)
        {
         if(cd.low <= zone.top && cd.high >= zone.bottom)
           {
            // Bullish FVG:
            //   close >= top    -> imbalance has been fully reclaimed/mitigated
            //   close < bottom  -> price closed through the far edge; invalidate
            //   otherwise       -> the zone was only tested
            if(cd.close < zone.bottom)
              {
               zone.state = FVG_INVALIDATED;
               return; // newest decisive event wins; do not replay older candles
              }
            else if(cd.close >= zone.top)
              {
               zone.state = FVG_MITIGATED;
               return; // newest decisive event wins; do not replay older candles
              }
            else if(zone.state == FVG_FRESH)
               zone.state = FVG_TESTED;
           }
        }
      else
        {
         if(cd.high >= zone.bottom && cd.low <= zone.top)
           {
            // Bearish FVG is the exact mirror image:
            //   close <= bottom  -> imbalance has been fully reclaimed/mitigated
            //   close > top      -> price closed through the far edge; invalidate
            //   otherwise        -> the zone was only tested
            if(cd.close > zone.top)
              {
               zone.state = FVG_INVALIDATED;
               return; // newest decisive event wins; do not replay older candles
              }
            else if(cd.close <= zone.bottom)
              {
               zone.state = FVG_MITIGATED;
               return; // newest decisive event wins; do not replay older candles
              }
            else if(zone.state == FVG_FRESH)
               zone.state = FVG_TESTED;
           }
        }
     }
  }
//+------------------------------------------------------------------+
FVGZone CFVG::GetZone(int i) const
  {
   FVGZone empty;
   ZeroMemory(empty);
   if(i < 0 || i >= m_zoneCount) return empty;
   return m_zones[i];
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/FVG.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/Liquidity.mqh
//+------------------------------------------------------------------+
//|                                            SmartMoney/Liquidity.mqh |
//+------------------------------------------------------------------+
#ifndef LIQUIDITY_MQH
#define LIQUIDITY_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh

class CLiquidity
  {
private:
   CCandleData*      m_candles;
   CSwingDetector*   m_swings;
   double            m_internalThresholdATR;

   LiquidityPool     m_pools[];   // FINAL/current-state pools (all data known) — for display/GetPool() only
   int               m_poolCount;
   LiquidityEvent    m_events[];
   int               m_eventCount;

   void              BuildInternalPools();  // final-state pools, for GetPool()/dashboard display
   void              BuildExternalPools();  // final-state "yesterday" pool, for GetPool()/dashboard display
   void              DetectSweeps();

public:
                     CLiquidity();
   void              Init(CCandleData* candles, CSwingDetector* swings, double internalThresholdATR = 0.2);
   void              Detect();
   int               PoolCount() const { return m_poolCount; }
   LiquidityPool     GetPool(int i) const;
   int               EventCount() const { return m_eventCount; }
   LiquidityEvent    GetEvent(int i) const; // 0 = most recent
   // Convenience wrappers for the Inducement/Scoring engines — "was the
   // most recent sweep of this kind within N bars?" without every caller
   // re-deriving it from raw events.
   bool              HasInternalSweep(int recencyBars, ENUM_LIQ_TYPE &outType, double &outStrength, int &outBarIndex);
   bool              HasExternalSweep(int recencyBars, ENUM_LIQ_TYPE &outType, double &outStrength, int &outBarIndex);
  };
//+------------------------------------------------------------------+
CLiquidity::CLiquidity() : m_candles(NULL), m_swings(NULL), m_internalThresholdATR(0.2), m_poolCount(0), m_eventCount(0) {}
void CLiquidity::Init(CCandleData* candles, CSwingDetector* swings, double internalThresholdATR)
  {
   m_candles = candles;
   m_swings = swings;
   m_internalThresholdATR = internalThresholdATR;
  }
//+------------------------------------------------------------------+
// FINAL-STATE pool list, built from the complete, current swing data —
// this is intentionally "everything we know today" and is only used for
// GetPool()/PoolCount() (dashboard, current-analysis display). It is NOT
// used for historical sweep detection — see DetectSweeps() below, which
// rebuilds pools chronologically bar-by-bar to avoid lookahead.
void CLiquidity::BuildInternalPools()
  {
   int hc = m_swings.HighCount();
   for(int i = 0; i < hc - 1; i++)
     {
      SwingPoint a = m_swings.GetHigh(i);
      double atr = m_candles.GetATR(a.bar_index);
      double band = m_internalThresholdATR * atr;
      for(int j = i + 1; j < hc; j++)
        {
         SwingPoint b = m_swings.GetHigh(j);
         if(MathAbs(a.price - b.price) <= band)
           {
            LiquidityPool pool;
            pool.price_top = MathMax(a.price, b.price);
            pool.price_bottom = MathMin(a.price, b.price);
            pool.type = LIQ_BUY_SIDE;
            pool.touches = 2;
            pool.external = false;
            pool.confirmed_at_shift = 0;
            bool exists = false;
            for(int k = 0; k < m_poolCount; k++)
              {
               if(!m_pools[k].external && m_pools[k].type == pool.type &&
                  MathAbs(m_pools[k].price_top - pool.price_top) < band)
                 {
                  m_pools[k].touches++;
                  exists = true;
                  break;
                 }
              }
            if(!exists)
              {
               int n = m_poolCount++;
               ArrayResize(m_pools, m_poolCount);
               m_pools[n] = pool;
              }
           }
        }
     }
   int lc = m_swings.LowCount();
   for(int i = 0; i < lc - 1; i++)
     {
      SwingPoint a = m_swings.GetLow(i);
      double atr = m_candles.GetATR(a.bar_index);
      double band = m_internalThresholdATR * atr;
      for(int j = i + 1; j < lc; j++)
        {
         SwingPoint b = m_swings.GetLow(j);
         if(MathAbs(a.price - b.price) <= band)
           {
            LiquidityPool pool;
            pool.price_top = MathMax(a.price, b.price);
            pool.price_bottom = MathMin(a.price, b.price);
            pool.type = LIQ_SELL_SIDE;
            pool.touches = 2;
            pool.external = false;
            pool.confirmed_at_shift = 0;
            bool exists = false;
            for(int k = 0; k < m_poolCount; k++)
              {
               if(!m_pools[k].external && m_pools[k].type == pool.type &&
                  MathAbs(m_pools[k].price_bottom - pool.price_bottom) < band)
                 {
                  m_pools[k].touches++;
                  exists = true;
                  break;
                 }
              }
            if(!exists)
              {
               int n = m_poolCount++;
               ArrayResize(m_pools, m_poolCount);
               m_pools[n] = pool;
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
void CLiquidity::BuildExternalPools()
  {
   if(m_candles == NULL) return;
   string sym = m_candles.Symbol();
   double dayHigh = iHigh(sym, PERIOD_D1, 1);
   double dayLow  = iLow(sym, PERIOD_D1, 1);
   if(dayHigh > 0)
     {
      LiquidityPool pool;
      pool.price_top = dayHigh;
      pool.price_bottom = dayHigh;
      pool.type = LIQ_BUY_SIDE;
      pool.touches = 1;
      pool.external = true;
      pool.confirmed_at_shift = 0;
      int n = m_poolCount++;
      ArrayResize(m_pools, m_poolCount);
      m_pools[n] = pool;
     }
   if(dayLow > 0)
     {
      LiquidityPool pool;
      pool.price_top = dayLow;
      pool.price_bottom = dayLow;
      pool.type = LIQ_SELL_SIDE;
      pool.touches = 1;
      pool.external = true;
      pool.confirmed_at_shift = 0;
      int n = m_poolCount++;
      ArrayResize(m_pools, m_poolCount);
      m_pools[n] = pool;
     }
  }
//+------------------------------------------------------------------+
// FIX (audit #11 — lookahead bias): the previous version built pools
// from the CURRENT, fully up-to-date swing list — "swing A + swing B
// exist" using every swing ever detected, including ones that formed
// AFTER a given historical bar — and then scanned ALL of history for
// sweeps of those pools. A candle from months ago could get flagged as
// "sweeping" a pool that, at the time, didn't exist yet (its second
// component swing hadn't happened). Correct chronology is: swing A +
// swing B both confirmed -> pool exists -> THEN a later bar can sweep
// it. This function enforces exactly that using LiquidityPool's new
// confirmed_at_shift field: a candidate sweep at `bar` is only tested
// against an internal pool if `bar <= pool.confirmed_at_shift` (the pool
// must already have existed as of that bar).
//
// External (daily high/low) pools have the SAME problem in a different
// form: a single static "yesterday's high/low" computed from TODAY's
// perspective was being used to test sweep candles from arbitrary points
// in history — but "yesterday" is a different level every day. Fixed by
// computing each candle's own actual prior trading day's D1 high/low at
// scan time instead of using one fixed pair of levels for all of history.
void CLiquidity::DetectSweeps()
  {
   m_eventCount = 0;
   if(m_candles == NULL || m_swings == NULL) return;
   ArrayFree(m_events);
   int total = m_candles.Total();
   int strength = m_swings.Strength();
   string sym = m_candles.Symbol();

   // --- Internal pools: rebuild WITH confirmation-shift tagging ---
   LiquidityPool internalPools[];
   int internalCount = 0;
   int hc = m_swings.HighCount();
   for(int i = 0; i < hc - 1; i++)
     {
      SwingPoint a = m_swings.GetHigh(i);
      double atrA = m_candles.GetATR(a.bar_index);
      double band = m_internalThresholdATR * atrA;
      for(int j = i + 1; j < hc; j++)
        {
         SwingPoint b = m_swings.GetHigh(j);
         if(MathAbs(a.price - b.price) <= band)
           {
            LiquidityPool pool;
            pool.price_top = MathMax(a.price, b.price);
            pool.price_bottom = MathMin(a.price, b.price);
            pool.type = LIQ_BUY_SIDE;
            pool.touches = 2;
            pool.external = false;
            // Pool only valid once BOTH swings are confirmed — that's the
            // LATER of the two confirmations, i.e. the smaller (more
            // recent) confirm_shift value.
            pool.confirmed_at_shift = MathMin(a.bar_index - strength, b.bar_index - strength);
            int n = internalCount++;
            ArrayResize(internalPools, internalCount);
            internalPools[n] = pool;
           }
        }
     }
   int lc = m_swings.LowCount();
   for(int i = 0; i < lc - 1; i++)
     {
      SwingPoint a = m_swings.GetLow(i);
      double atrA = m_candles.GetATR(a.bar_index);
      double band = m_internalThresholdATR * atrA;
      for(int j = i + 1; j < lc; j++)
        {
         SwingPoint b = m_swings.GetLow(j);
         if(MathAbs(a.price - b.price) <= band)
           {
            LiquidityPool pool;
            pool.price_top = MathMax(a.price, b.price);
            pool.price_bottom = MathMin(a.price, b.price);
            pool.type = LIQ_SELL_SIDE;
            pool.touches = 2;
            pool.external = false;
            pool.confirmed_at_shift = MathMin(a.bar_index - strength, b.bar_index - strength);
            int n = internalCount++;
            ArrayResize(internalPools, internalCount);
            internalPools[n] = pool;
           }
        }
     }

   for(int i = 0; i < internalCount; i++)
     {
      for(int bar = 1; bar < total - 2; bar++)
        {
         if(bar > internalPools[i].confirmed_at_shift) continue; // FIX #11: pool didn't exist yet at this bar
         CandleData cd = m_candles.GetCandle(bar);
         double atr = m_candles.GetATR(bar);
         if(atr <= 0) continue;

         if(internalPools[i].type == LIQ_BUY_SIDE)
           {
            if(cd.high > internalPools[i].price_top && cd.close < internalPools[i].price_bottom)
              {
               double penetration = (cd.high - internalPools[i].price_top) / atr;
               LiquidityEvent ev;
               ev.time = cd.time;
               ev.price = internalPools[i].price_top;
               ev.type = LIQ_BUY_SIDE;
               ev.strength = MathMax(0.0, MathMin(penetration / 0.5, 1.0));
               ev.swept = true;
               ev.bar_index = bar;
               ev.external = false;
               int n = m_eventCount++;
               ArrayResize(m_events, m_eventCount);
               m_events[n] = ev;
               break;
              }
           }
         else
           {
            if(cd.low < internalPools[i].price_bottom && cd.close > internalPools[i].price_top)
              {
               double penetration = (internalPools[i].price_bottom - cd.low) / atr;
               LiquidityEvent ev;
               ev.time = cd.time;
               ev.price = internalPools[i].price_bottom;
               ev.type = LIQ_SELL_SIDE;
               ev.strength = MathMax(0.0, MathMin(penetration / 0.5, 1.0));
               ev.swept = true;
               ev.bar_index = bar;
               ev.external = false;
               int n = m_eventCount++;
               ArrayResize(m_events, m_eventCount);
               m_events[n] = ev;
               break;
              }
           }
        }
     }

   // --- External pools: each candle tested against ITS OWN prior trading
   // day's D1 high/low, not today's, via iBarShift — chronologically
   // correct by construction, no static level reused across all of history.
   int lastD1Shift = -1;
   double d1High = 0.0, d1Low = 0.0;
   for(int bar = 1; bar < total - 2; bar++)
     {
      CandleData cd = m_candles.GetCandle(bar);
      double atr = m_candles.GetATR(bar);
      if(atr <= 0) continue;

      int d1Shift = iBarShift(sym, PERIOD_D1, cd.time);
      if(d1Shift < 0) continue; // no daily data this far back
      if(d1Shift != lastD1Shift) // only refetch when we cross a day boundary — cheap
        {
         d1High = iHigh(sym, PERIOD_D1, d1Shift + 1); // the PRIOR day relative to this bar's own day
         d1Low  = iLow(sym, PERIOD_D1, d1Shift + 1);
         lastD1Shift = d1Shift;
        }

      if(d1High > 0 && cd.high > d1High && cd.close < d1High)
        {
         double penetration = (cd.high - d1High) / atr;
         LiquidityEvent ev;
         ev.time = cd.time;
         ev.price = d1High;
         ev.type = LIQ_BUY_SIDE;
         ev.strength = MathMax(0.0, MathMin(penetration / 0.5, 1.0));
         ev.swept = true;
         ev.bar_index = bar;
         ev.external = true;
         int n = m_eventCount++;
         ArrayResize(m_events, m_eventCount);
         m_events[n] = ev;
        }
      if(d1Low > 0 && cd.low < d1Low && cd.close > d1Low)
        {
         double penetration = (d1Low - cd.low) / atr;
         LiquidityEvent ev;
         ev.time = cd.time;
         ev.price = d1Low;
         ev.type = LIQ_SELL_SIDE;
         ev.strength = MathMax(0.0, MathMin(penetration / 0.5, 1.0));
         ev.swept = true;
         ev.bar_index = bar;
         ev.external = true;
         int n = m_eventCount++;
         ArrayResize(m_events, m_eventCount);
         m_events[n] = ev;
        }
     }

   // Order events most-recent-first for downstream consumers (Scoring
   // wants "did a sweep just happen", not "did one ever happen").
   for(int a = 0; a < m_eventCount - 1; a++)
      for(int b = a + 1; b < m_eventCount; b++)
         if(m_events[b].bar_index < m_events[a].bar_index)
           {
            LiquidityEvent t = m_events[a];
            m_events[a] = m_events[b];
            m_events[b] = t;
           }
  }
//+------------------------------------------------------------------+
void CLiquidity::Detect()
  {
   m_poolCount = 0;
   if(m_candles == NULL || m_swings == NULL) return;
   ArrayFree(m_pools);
   BuildInternalPools();   // final-state, for display only
   BuildExternalPools();   // final-state, for display only
   DetectSweeps();         // chronologically rebuilt internally — see above
  }
LiquidityPool CLiquidity::GetPool(int i) const { if(i<0||i>=m_poolCount) { LiquidityPool e; ZeroMemory(e); return e; } return m_pools[i]; }
LiquidityEvent CLiquidity::GetEvent(int i) const { if(i<0||i>=m_eventCount) { LiquidityEvent e; ZeroMemory(e); return e; } return m_events[i]; }
//+------------------------------------------------------------------+
bool CLiquidity::HasInternalSweep(int recencyBars, ENUM_LIQ_TYPE &outType, double &outStrength, int &outBarIndex)
  {
   for(int i = 0; i < m_eventCount; i++)
     {
      if(m_events[i].external) continue;
      if(m_events[i].bar_index > recencyBars) continue;
      outType = m_events[i].type;
      outStrength = m_events[i].strength;
      outBarIndex = m_events[i].bar_index;
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
bool CLiquidity::HasExternalSweep(int recencyBars, ENUM_LIQ_TYPE &outType, double &outStrength, int &outBarIndex)
  {
   for(int i = 0; i < m_eventCount; i++)
     {
      if(!m_events[i].external) continue;
      if(m_events[i].bar_index > recencyBars) continue;
      outType = m_events[i].type;
      outStrength = m_events[i].strength;
      outBarIndex = m_events[i].bar_index;
      return true;
     }
   return false;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/Liquidity.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/SupportResistance.mqh
//+------------------------------------------------------------------+
//|                                     SmartMoney/SupportResistance.mqh |
//+------------------------------------------------------------------+
#ifndef SUPPORTRESISTANCE_MQH
#define SUPPORTRESISTANCE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh

class CSupportResistance
  {
private:
   CCandleData*      m_candles;
   CSwingDetector*   m_swings;
   SRZone            m_zones[];
   int               m_zoneCount;

public:
                     CSupportResistance();
   void              Init(CCandleData* candles, CSwingDetector* swings);
   void              Detect();
   int               Count() const { return m_zoneCount; }
   SRZone            GetZone(int i) const; // 0 = strongest (most touches)
  };
//+------------------------------------------------------------------+
CSupportResistance::CSupportResistance() : m_candles(NULL), m_swings(NULL), m_zoneCount(0) {}
void CSupportResistance::Init(CCandleData* candles, CSwingDetector* swings)
  {
   m_candles = candles;
   m_swings = swings;
  }
//+------------------------------------------------------------------+
void CSupportResistance::Detect()
  {
   m_zoneCount = 0;
   if(m_swings == NULL || m_candles == NULL) return;
   ArrayFree(m_zones);

   // Cluster swing highs into resistance zones
   int hc = m_swings.HighCount();
   for(int i = 0; i < hc; i++)
     {
      SwingPoint sp = m_swings.GetHigh(i);
      double atr = m_candles.GetATR(sp.bar_index);
      double band = 0.3 * atr;
      bool added = false;
      for(int j = 0; j < m_zoneCount; j++)
        {
         // FIX: original didn't check zone type here, so this only
         // worked "by accident" because support zones hadn't been added
         // yet at this point in execution. Explicit type check now.
         bool isResistance = (m_zones[j].type == SR_MAJOR_RESISTANCE || m_zones[j].type == SR_MINOR_RESISTANCE);
         if(isResistance && MathAbs(sp.price - m_zones[j].top) <= band)
           {
            m_zones[j].touches++;
            m_zones[j].top = MathMax(m_zones[j].top, sp.price);
            m_zones[j].bottom = MathMin(m_zones[j].bottom, sp.price);
            if(m_zones[j].touches >= 3)
               m_zones[j].type = SR_MAJOR_RESISTANCE;
            added = true;
            break;
           }
        }
      if(!added)
        {
         SRZone zone;
         zone.top = sp.price;
         zone.bottom = sp.price;
         zone.type = (sp.strength > 0.5) ? SR_MAJOR_RESISTANCE : SR_MINOR_RESISTANCE;
         zone.touches = 1;
         zone.startTime = sp.time;
         int n = m_zoneCount++;
         ArrayResize(m_zones, m_zoneCount);
         m_zones[n] = zone;
        }
     }
   // Cluster swing lows into support zones
   int lc = m_swings.LowCount();
   for(int i = 0; i < lc; i++)
     {
      SwingPoint sp = m_swings.GetLow(i);
      double atr = m_candles.GetATR(sp.bar_index);
      double band = 0.3 * atr;
      bool added = false;
      for(int j = 0; j < m_zoneCount; j++)
        {
         bool isSupport = (m_zones[j].type == SR_MAJOR_SUPPORT || m_zones[j].type == SR_MINOR_SUPPORT);
         if(isSupport && MathAbs(sp.price - m_zones[j].bottom) <= band)
           {
            m_zones[j].touches++;
            m_zones[j].top = MathMax(m_zones[j].top, sp.price);
            m_zones[j].bottom = MathMin(m_zones[j].bottom, sp.price);
            if(m_zones[j].touches >= 3)
               m_zones[j].type = SR_MAJOR_SUPPORT;
            added = true;
            break;
           }
        }
      if(!added)
        {
         SRZone zone;
         zone.top = sp.price;
         zone.bottom = sp.price;
         zone.type = (sp.strength > 0.5) ? SR_MAJOR_SUPPORT : SR_MINOR_SUPPORT;
         zone.touches = 1;
         zone.startTime = sp.time;
         int n = m_zoneCount++;
         ArrayResize(m_zones, m_zoneCount);
         m_zones[n] = zone;
        }
     }
   // FIX: original did an unconditional "reverse to have most recent
   // first" here, but S/R zones aren't a time-ordered event log — the
   // touches accumulate across the whole scan, so "most recent" isn't a
   // meaningful concept for them. Sorting by touch count puts the
   // strongest, most confluence-backed zones first, which is what
   // scoring/trade logic actually wants.
   for(int a = 0; a < m_zoneCount - 1; a++)
      for(int b = a + 1; b < m_zoneCount; b++)
         if(m_zones[b].touches > m_zones[a].touches)
           {
            SRZone t = m_zones[a];
            m_zones[a] = m_zones[b];
            m_zones[b] = t;
           }
  }
SRZone CSupportResistance::GetZone(int i) const { if(i<0||i>=m_zoneCount) { SRZone e; ZeroMemory(e); return e; } return m_zones[i]; }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/SupportResistance.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/VolumeEngine.mqh
//+------------------------------------------------------------------+
//|                                       SmartMoney/VolumeEngine.mqh |
//+------------------------------------------------------------------+
#ifndef VOLUMEENGINE_MQH
#define VOLUMEENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh

// Volume Engine — answers "is this move supported by participation?"
// Per spec: volume is a FILTER/VALIDATOR, never a signal generator on its
// own. Relative Volume (RVOL) compares a bar's volume against its own
// recent average; a breakout with low RVOL is treated as unsupported and
// gated out in Scoring.mqh rather than scored up.
//
// CAVEAT: MT5's tick_volume is a count of price changes, not necessarily
// broker-reported traded volume (real Volume is feed-dependent and often
// absent on FX symbols). RVOL here is always computed from tick_volume —
// a reasonable participation proxy on most FX/CFD symbols, but treat it
// as directional evidence, not an exact volume reading.
class CVolumeEngine
  {
private:
   CCandleData*      m_candles;
   int               m_lookback;      // bars averaged for the RVOL baseline

public:
                     CVolumeEngine();
   void              Init(CCandleData* candles, int lookback = 20);

   // Mean tick_volume over the `lookback` bars immediately BEFORE `shift`
   // (i.e. [shift+1 .. shift+lookback]) — deliberately excludes the bar
   // being measured so a spike can't inflate its own baseline.
   double            AverageVolume(int shift, int lookback) const;
   double            RVOL(int shift = 0) const;                 // tick_volume[shift] / AverageVolume(shift, m_lookback)
   bool              IsSpike(int shift = 0, double thresholdMult = 1.5) const;

   // Mirrors the spec's BOS validation rule: "Body > 0.5*ATR AND RVOL >= threshold"
   // CONFIRMATION filter (see gate convention, Core/Config.mqh) — fails
   // closed on purpose: no candles/ATR means nothing to confirm.
   bool              ConfirmsBreakout(int shift, double atr, double bodyRatioMin = 0.5, double rvolThreshold = 1.5) const;

   // 0-1 normalized score for confluence ranking/diagnostics only — NOT
   // used to manufacture confidence on its own. See the gating discipline
   // note in Analysis/Scoring.mqh.
   double            Score(int shift = 0, double rvolThreshold = 1.5) const;
  };
//+------------------------------------------------------------------+
CVolumeEngine::CVolumeEngine() : m_candles(NULL), m_lookback(20) {}
//+------------------------------------------------------------------+
void CVolumeEngine::Init(CCandleData* candles, int lookback)
  {
   m_candles = candles;
   m_lookback = MathMax(5, lookback);
  }
//+------------------------------------------------------------------+
double CVolumeEngine::AverageVolume(int shift, int lookback) const
  {
   if(m_candles == NULL) return 0.0;
   int total = m_candles.Total();
   double sum = 0.0;
   int count = 0;
   for(int i = shift + 1; i <= shift + lookback && i < total; i++)
     {
      sum += (double)m_candles.GetCandle(i).tick_volume;
      count++;
     }
   if(count == 0) return 0.0;
   return sum / count;
  }
//+------------------------------------------------------------------+
double CVolumeEngine::RVOL(int shift) const
  {
   if(m_candles == NULL || shift < 0 || shift >= m_candles.Total()) return 0.0;
   double avg = AverageVolume(shift, m_lookback);
   if(avg <= 0) return 0.0;
   double v = (double)m_candles.GetCandle(shift).tick_volume;
   return v / avg;
  }
//+------------------------------------------------------------------+
bool CVolumeEngine::IsSpike(int shift, double thresholdMult) const
  {
   return RVOL(shift) >= thresholdMult;
  }
//+------------------------------------------------------------------+
bool CVolumeEngine::ConfirmsBreakout(int shift, double atr, double bodyRatioMin, double rvolThreshold) const
  {
   if(m_candles == NULL || atr <= 0) return false;
   CandleData cd = m_candles.GetCandle(shift);
   double body = MathAbs(cd.close - cd.open);
   if(body < bodyRatioMin * atr) return false;
   return RVOL(shift) >= rvolThreshold;
  }
//+------------------------------------------------------------------+
double CVolumeEngine::Score(int shift, double rvolThreshold) const
  {
   double r = RVOL(shift);
   if(r <= 0 || rvolThreshold <= 0) return 0.0;
   // Linear ramp: 0 at RVOL=0, 1.0 at RVOL == 2x threshold, capped —
   // gives a smooth confluence weight instead of a hard step once past
   // the gating threshold.
   double score = r / (2.0 * rvolThreshold);
   return MathMin(MathMax(score, 0.0), 1.0);
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/VolumeEngine.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/FibonacciEngine.mqh
//+------------------------------------------------------------------+
//|                                    SmartMoney/FibonacciEngine.mqh |
//+------------------------------------------------------------------+
#ifndef FIBONACCIENGINE_MQH
#define FIBONACCIENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh

// Fibonacci Engine — a LOCATION filter, never a signal generator. Anchors
// come only from confirmed swing highs/lows produced by CSwingDetector;
// manual anchor selection is deliberately not exposed anywhere in this
// class. For an uptrend leg: 0% retracement = the confirmed swing high,
// 100% = the confirmed swing low it retraced from (mirrored for a
// downtrend leg). Levels are always computed fresh from the live swing
// series — nothing here is cached or hand-placed.
struct FibLeg
  {
   bool              valid;
   bool              bullish;     // true = uptrend leg (retracement measured down from the high)
   double            lowPrice;
   double            highPrice;
   datetime          lowTime;
   datetime          highTime;
   int               lowBar;
   int               highBar;
  };

class CFibonacciEngine
  {
private:
   CSwingDetector*   m_swings;
   CCandleData*      m_candles;

   bool              FindLeg(bool forBuy, FibLeg &out) const;
   double            LevelPrice(const FibLeg &leg, double pct) const;

public:
                     CFibonacciEngine();
   void              Init(CSwingDetector* swings, CCandleData* candles);

   // CONFIRMATION filter (see gate convention, Core/Config.mqh) — fails
   // closed on purpose: no confirmed swing pair means no leg to measure.
   bool              GetLeg(bool forBuy, FibLeg &out) const { return FindLeg(forBuy, out); }
   double            RetracementPct(bool forBuy, double price) const; // 0 at the impulse extreme, 100 at the leg's origin, -1 if no leg
   ENUM_FIB_ZONE     Zone(bool forBuy, double price) const;
   bool              InPullbackZone(bool forBuy, double price, double zoneMinPct = 50.0, double zoneMaxPct = 61.8) const;
   double            NearestLevel(bool forBuy, double price, double &pctOut) const; // price of nearest of {38.2, 50, 61.8, 78.6}

   // 0-1 confluence score: 1.0 inside [zoneMinPct, zoneMaxPct], decaying
   // to 0 by the 38.2%/78.6% guard rails outside it. Diagnostic/ranking
   // only — see the gating discipline note in Analysis/Scoring.mqh.
   double            Score(bool forBuy, double price, double zoneMinPct = 50.0, double zoneMaxPct = 61.8) const;
  };
//+------------------------------------------------------------------+
CFibonacciEngine::CFibonacciEngine() : m_swings(NULL), m_candles(NULL) {}
//+------------------------------------------------------------------+
void CFibonacciEngine::Init(CSwingDetector* swings, CCandleData* candles)
  {
   m_swings = swings;
   m_candles = candles;
  }
//+------------------------------------------------------------------+
// forBuy (uptrend leg): anchor on the most recent confirmed swing high,
// then the nearest confirmed swing low OLDER than it (the low that
// started the impulse leg ending at that high).
// forBuy == false (downtrend leg): mirrored — most recent swing low, and
// the nearest older swing high that started the down-leg.
// NOTE: series convention (matches SwingDetector.mqh) — index 0 is the
// most recent point, and a LARGER bar_index means an OLDER bar.
bool CFibonacciEngine::FindLeg(bool forBuy, FibLeg &out) const
  {
   ZeroMemory(out);
   if(m_swings == NULL) return false;
   if(m_swings.HighCount() == 0 || m_swings.LowCount() == 0) return false;

   if(forBuy)
     {
      SwingPoint hi = m_swings.GetHigh(0);
      bool found = false;
      SwingPoint bestLow;
       ZeroMemory(bestLow);
      for(int i = 0; i < m_swings.LowCount(); i++)
        {
         SwingPoint lo = m_swings.GetLow(i);
         if(lo.bar_index > hi.bar_index)          // older than the high
           {
            if(!found || lo.bar_index < bestLow.bar_index) { bestLow = lo; found = true; }
           }
        }
      if(!found) return false;
      out.valid = true;
      out.bullish = true;
      out.lowPrice = bestLow.price;
      out.highPrice = hi.price;
      out.lowTime = bestLow.time;
      out.highTime = hi.time;
      out.lowBar = bestLow.bar_index;
      out.highBar = hi.bar_index;
      return true;
     }
   else
     {
      SwingPoint lo = m_swings.GetLow(0);
      bool found = false;
      SwingPoint bestHigh;
       ZeroMemory(bestHigh);
      for(int i = 0; i < m_swings.HighCount(); i++)
        {
         SwingPoint hi2 = m_swings.GetHigh(i);
         if(hi2.bar_index > lo.bar_index)         // older than the low
           {
            if(!found || hi2.bar_index < bestHigh.bar_index) { bestHigh = hi2; found = true; }
           }
        }
      if(!found) return false;
      out.valid = true;
      out.bullish = false;
      out.lowPrice = lo.price;
      out.highPrice = bestHigh.price;
      out.lowTime = lo.time;
      out.highTime = bestHigh.time;
      out.lowBar = lo.bar_index;
      out.highBar = bestHigh.bar_index;
      return true;
     }
  }
//+------------------------------------------------------------------+
// pct is a retracement percentage (0-100): 0 = the impulse extreme (the
// high in an uptrend leg, the low in a downtrend leg), 100 = the leg's
// origin.
double CFibonacciEngine::LevelPrice(const FibLeg &leg, double pct) const
  {
   double range = leg.highPrice - leg.lowPrice;
   double frac = pct / 100.0;
   if(leg.bullish)
      return leg.highPrice - frac * range;   // retracing down from the high
   else
      return leg.lowPrice + frac * range;    // retracing up from the low
  }
//+------------------------------------------------------------------+
double CFibonacciEngine::RetracementPct(bool forBuy, double price) const
  {
   FibLeg leg;
   if(!FindLeg(forBuy, leg)) return -1.0;
   double range = leg.highPrice - leg.lowPrice;
   if(range <= 0) return -1.0;
   double pct = leg.bullish ? (leg.highPrice - price) / range * 100.0
                            : (price - leg.lowPrice) / range * 100.0;
   return pct;
  }
//+------------------------------------------------------------------+
// Discount = price has pulled back deep into the leg (cheap relative to
// the impulse — favorable for the trend direction). Premium = still
// shallow / close to the impulse extreme (expensive). Matches the same
// discount/premium vocabulary SmartMoney/PremiumDiscount.mqh uses for the
// (separate) inducement-leg gate — this one is swing-anchored, that one
// is impulse-anchored; they will usually agree but are not the same leg.
ENUM_FIB_ZONE CFibonacciEngine::Zone(bool forBuy, double price) const
  {
   double pct = RetracementPct(forBuy, price);
   if(pct < 0) return FIB_ZONE_UNDEFINED;
   if(pct >= 61.8) return FIB_ZONE_DISCOUNT;
   if(pct >= 38.2) return FIB_ZONE_NEUTRAL;
   return FIB_ZONE_PREMIUM;
  }
//+------------------------------------------------------------------+
bool CFibonacciEngine::InPullbackZone(bool forBuy, double price, double zoneMinPct, double zoneMaxPct) const
  {
   double pct = RetracementPct(forBuy, price);
   if(pct < 0) return false;
   double lo = MathMin(zoneMinPct, zoneMaxPct);
   double hi = MathMax(zoneMinPct, zoneMaxPct);
   return (pct >= lo && pct <= hi);
  }
//+------------------------------------------------------------------+
double CFibonacciEngine::NearestLevel(bool forBuy, double price, double &pctOut) const
  {
   FibLeg leg;
   if(!FindLeg(forBuy, leg)) { pctOut = -1.0; return 0.0; }
   double levels[4] = {38.2, 50.0, 61.8, 78.6};
   double bestDist = -1.0;
   double bestPrice = 0.0;
   double bestPct = -1.0;
   for(int i = 0; i < 4; i++)
     {
      double lvlPrice = LevelPrice(leg, levels[i]);
      double dist = MathAbs(price - lvlPrice);
      if(bestDist < 0 || dist < bestDist) { bestDist = dist; bestPrice = lvlPrice; bestPct = levels[i]; }
     }
   pctOut = bestPct;
   return bestPrice;
  }
//+------------------------------------------------------------------+
double CFibonacciEngine::Score(bool forBuy, double price, double zoneMinPct, double zoneMaxPct) const
  {
   double pct = RetracementPct(forBuy, price);
   if(pct < 0) return 0.0;
   double lo = MathMin(zoneMinPct, zoneMaxPct);
   double hi = MathMax(zoneMinPct, zoneMaxPct);
   if(pct >= lo && pct <= hi) return 1.0;

   if(pct < lo)
     {
      double floor = 38.2;
      if(pct <= floor) return 0.0;
      return (pct - floor) / (lo - floor);
     }
   else
     {
      double ceilPct = 78.6;
      if(pct >= ceilPct) return 0.0;
      return (ceilPct - pct) / (ceilPct - hi);
     }
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/FibonacciEngine.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/ValueAreaEngine.mqh
//+------------------------------------------------------------------+
//|                                    SmartMoney/ValueAreaEngine.mqh |
//+------------------------------------------------------------------+
#ifndef VALUEAREAENGINE_MQH
#define VALUEAREAENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh

// Cross-asset Value Area / Volume Profile engine.
//
// Data hierarchy:
//   1. COPY_TICKS_TRADE + MqlTick.volume_real  -> real trade-by-price when
//      the connected feed actually exposes trade ticks and real volume.
//   2. COPY_TICKS_TRADE + MqlTick.volume       -> broker trade-tick profile.
//   3. MqlRates.real_volume                    -> real-volume bar proxy.
//   4. MqlRates.tick_volume                    -> broker tick-volume proxy.
//
// The engine is symbol-agnostic. It therefore supports exchange-listed
// futures/stocks/ETFs/indices when traded-volume data is available, and
// OTC/CFD/FX symbols when only broker volume data is available.
//
// It never labels a bar approximation as exchange trade volume.
//
// Trade-tick data is bounded to a recent 7-day window to prevent pathological
// CopyTicksRange allocations. Longer profile horizons use the best available
// bar volume source and record the provenance.
//
// The hard gate is contradiction-based, not "outside Value Area = reject":
// an accepted breakout above VAH can remain valid for a BUY, while a failed
// move above VAH can invalidate that BUY when the profile evidence is strong
// enough. Low-quality tick-volume proxies fail open.

#define VALUEAREA_TICK_PROFILE_MAX_DAYS 7

class CValueAreaEngine
  {
private:
   CCandleData*               m_candles;
   int                        m_lookbackBars;
   int                        m_numBins;
   double                     m_valueAreaPercent;
   int                        m_acceptanceBars;
   int                        m_rejectionLookbackBars;

   bool                       m_valid;
   double                     m_poc;
   double                     m_vah;
   double                     m_val;
   double                     m_pocMigrationATR;
   double                     m_sourceQuality;
   ENUM_VALUE_PROFILE_SOURCE  m_source;
   ENUM_VALUE_PROFILE_STATE   m_state;
   datetime                   m_lastBarTime;
   bool                       m_havePreviousPOC;

   int                        BinForPrice(double price, double rangeLow, double binSize) const;
   bool                       BuildTickProfile(double rangeLow, double binSize, double &volumes[]);
   bool                       BuildBarProfile(double rangeLow, double binSize, double &volumes[], ENUM_VALUE_PROFILE_SOURCE &source);
   void                       ComputeValueArea(double rangeLow, double binSize, double &volumes[]);
   void                       ComputeState();
   double                     ComputeSourceQuality() const;

public:
                              CValueAreaEngine();
   void                       Init(CCandleData* candles, int lookbackBars = 100, int numBins = 24, double valueAreaPercent = 0.70);
   void                       Compute(bool forceRecompute = false);

   bool                       IsValid() const { return m_valid; }
   double                     POC() const { return m_poc; }
   double                     VAH() const { return m_vah; }
   double                     VAL() const { return m_val; }
   double                     POCMigrationATR() const { return m_pocMigrationATR; }
   double                     SourceQuality() const { return m_sourceQuality; }
   ENUM_VALUE_PROFILE_SOURCE  Source() const { return m_source; }
   ENUM_VALUE_PROFILE_STATE   State() const { return m_state; }

   ENUM_VALUE_AREA_ZONE       Zone(double price) const;
   bool                       LocationOK(bool forBuy, double price) const;
   double                     Score(bool forBuy, double price) const;

   // True only when profile evidence actively contradicts this thesis.
   bool                       HardConflict(bool forBuy, double price) const;
  };

//+------------------------------------------------------------------+
CValueAreaEngine::CValueAreaEngine() :
   m_candles(NULL),
   m_lookbackBars(100),
   m_numBins(24),
   m_valueAreaPercent(0.70),
   m_acceptanceBars(3),
   m_rejectionLookbackBars(3),
   m_valid(false),
   m_poc(0.0),
   m_vah(0.0),
   m_val(0.0),
   m_pocMigrationATR(0.0),
   m_sourceQuality(0.0),
   m_source(VA_SOURCE_UNDEFINED),
   m_state(VA_STATE_UNDEFINED),
   m_lastBarTime(0),
   m_havePreviousPOC(false)
  {
  }

//+------------------------------------------------------------------+
void CValueAreaEngine::Init(CCandleData* candles, int lookbackBars, int numBins, double valueAreaPercent)
  {
   m_candles = candles;
   m_lookbackBars = MathMax(10, lookbackBars);
   m_numBins = MathMax(5, numBins);
   m_valueAreaPercent = (valueAreaPercent > 0.0 && valueAreaPercent < 1.0) ? valueAreaPercent : 0.70;
   m_acceptanceBars = 3;
   m_rejectionLookbackBars = 3;
   m_valid = false;
   m_poc = 0.0;
   m_vah = 0.0;
   m_val = 0.0;
   m_pocMigrationATR = 0.0;
   m_sourceQuality = 0.0;
   m_source = VA_SOURCE_UNDEFINED;
   m_state = VA_STATE_UNDEFINED;
   m_lastBarTime = 0;
   m_havePreviousPOC = false;
  }

//+------------------------------------------------------------------+
int CValueAreaEngine::BinForPrice(double price, double rangeLow, double binSize) const
  {
   if(binSize <= 0.0) return 0;
   int b = (int)((price - rangeLow) / binSize);
   return (int)MathMax(0, MathMin(m_numBins - 1, b));
  }

//+------------------------------------------------------------------+
bool CValueAreaEngine::BuildTickProfile(double rangeLow, double binSize, double &volumes[])
  {
   if(m_candles == NULL || m_candles.Total() < 2 || binSize <= 0.0)
      return false;

   int bars = MathMin(m_lookbackBars, m_candles.Total());
   datetime oldest = m_candles.GetCandle(bars - 1).time;
   datetime newest = m_candles.GetCandle(0).time;
   if(oldest <= 0 || newest <= 0)
      return false;

   long spanSeconds = (long)newest - (long)oldest;
   if(spanSeconds <= 0 || spanSeconds > (long)VALUEAREA_TICK_PROFILE_MAX_DAYS * 86400)
      return false;

   ulong fromMsc = (ulong)oldest * 1000;
   ulong toMsc = ((ulong)TimeCurrent() * 1000) + 999;

   MqlTick ticks[];
   int copied = CopyTicksRange(m_candles.Symbol(), ticks, COPY_TICKS_TRADE, fromMsc, toMsc);
   if(copied <= 0)
      return false;

   bool sawRealTradeVolume = false;
   bool sawBrokerTradeVolume = false;
   double totalObservedVolume = 0.0;

   for(int i = 0; i < copied; i++)
     {
      MqlTick tick = ticks[i];
      if((tick.flags & TICK_FLAG_LAST) == 0 || tick.last <= 0.0)
         continue;

      double volume = tick.volume_real;
      if(volume > 0.0)
         sawRealTradeVolume = true;
      else
         volume = (double)tick.volume;

      if(volume > 0.0)
         sawBrokerTradeVolume = true;
      else
         continue;

      int bin = BinForPrice(tick.last, rangeLow, binSize);
      volumes[bin] += volume;
      totalObservedVolume += volume;
     }

   if(totalObservedVolume <= 0.0)
      return false;

   if(sawRealTradeVolume)
      m_source = VA_SOURCE_REAL_TRADE_TICKS;
   else if(sawBrokerTradeVolume)
      m_source = VA_SOURCE_BROKER_TRADE_TICKS;
   else
      return false;

   return true;
  }

//+------------------------------------------------------------------+
bool CValueAreaEngine::BuildBarProfile(double rangeLow, double binSize, double &volumes[],
                                       ENUM_VALUE_PROFILE_SOURCE &source)
  {
   if(m_candles == NULL || binSize <= 0.0)
      return false;

   int bars = MathMin(m_lookbackBars, m_candles.Total());
   bool hasRealVolume = false;

   for(int i = 0; i < bars; i++)
     {
      if(m_candles.GetCandle(i).real_volume > 0)
        {
         hasRealVolume = true;
         break;
        }
     }

   source = hasRealVolume ? VA_SOURCE_REAL_VOLUME_BARS : VA_SOURCE_TICK_VOLUME_BARS;

   for(int i = 0; i < bars; i++)
     {
      CandleData cd = m_candles.GetCandle(i);
      double vol = hasRealVolume ? (double)cd.real_volume : (double)cd.tick_volume;
      if(vol <= 0.0)
         continue;

      if(cd.high <= cd.low)
        {
         volumes[BinForPrice(cd.close, rangeLow, binSize)] += vol;
         continue;
        }

      int startBin = BinForPrice(cd.low, rangeLow, binSize);
      int endBin = BinForPrice(cd.high, rangeLow, binSize);
      if(endBin < startBin)
        {
         int t = startBin;
         startBin = endBin;
         endBin = t;
        }

      int touched = endBin - startBin + 1;
      double volPerBin = vol / touched;

      for(int b = startBin; b <= endBin; b++)
         volumes[b] += volPerBin;
     }

   return true;
  }

//+------------------------------------------------------------------+
void CValueAreaEngine::ComputeValueArea(double rangeLow, double binSize, double &volumes[])
  {
   double totalVol = 0.0;
   int pocBin = 0;
   double pocVol = -1.0;

   for(int b = 0; b < m_numBins; b++)
     {
      totalVol += volumes[b];
      if(volumes[b] > pocVol)
        {
         pocVol = volumes[b];
         pocBin = b;
        }
     }

   if(totalVol <= 0.0 || pocVol <= 0.0)
     {
      m_valid = false;
      return;
     }

   int lowIdx = pocBin;
   int highIdx = pocBin;
   double cumVol = volumes[pocBin];
   double targetVol = totalVol * m_valueAreaPercent;

   while(cumVol < targetVol && (lowIdx > 0 || highIdx < m_numBins - 1))
     {
      double volBelow = (lowIdx > 0) ? volumes[lowIdx - 1] : -1.0;
      double volAbove = (highIdx < m_numBins - 1) ? volumes[highIdx + 1] : -1.0;

      if(volBelow < 0.0 && volAbove < 0.0)
         break;

      if(volBelow >= volAbove)
        {
         lowIdx--;
         cumVol += volumes[lowIdx];
        }
      else
        {
         highIdx++;
         cumVol += volumes[highIdx];
        }
     }

   double previousPOC = m_poc;
   bool hadPrevious = m_havePreviousPOC;

   m_poc = rangeLow + (pocBin + 0.5) * binSize;
   m_val = rangeLow + lowIdx * binSize;
   m_vah = rangeLow + (highIdx + 1) * binSize;

   double atr = m_candles.GetATR(0);
   if(hadPrevious && atr > 0.0)
      m_pocMigrationATR = (m_poc - previousPOC) / atr;
   else
      m_pocMigrationATR = 0.0;

   m_havePreviousPOC = true;
   m_valid = true;
  }

//+------------------------------------------------------------------+
void CValueAreaEngine::ComputeState()
  {
   m_state = VA_STATE_BALANCED;

   if(!m_valid || m_candles == NULL)
     {
      m_state = VA_STATE_UNDEFINED;
      return;
     }

   int inspectBars = MathMin(m_candles.Total() - 1, m_acceptanceBars + 1);
   int maxRejectBars = MathMin(m_candles.Total() - 1, m_rejectionLookbackBars);
   double atr = m_candles.GetATR(1);
   double tolerance = (atr > 0.0) ? atr * 0.05 : 0.0;

   int above = 0;
   int below = 0;
   bool rejectedAbove = false;
   bool rejectedBelow = false;

   for(int shift = 1; shift <= inspectBars; shift++)
     {
      CandleData cd = m_candles.GetCandle(shift);
      if(cd.close > m_vah + tolerance) above++;
      if(cd.close < m_val - tolerance) below++;
     }

   for(int shift = 1; shift <= maxRejectBars; shift++)
     {
      CandleData cd = m_candles.GetCandle(shift);

      if(cd.high > m_vah + tolerance && cd.close <= m_vah + tolerance)
         rejectedAbove = true;

      if(cd.low < m_val - tolerance && cd.close >= m_val - tolerance)
         rejectedBelow = true;
     }

   if(rejectedAbove)
      m_state = VA_STATE_REJECTED_ABOVE;
   else if(rejectedBelow)
      m_state = VA_STATE_REJECTED_BELOW;
   else if(above >= m_acceptanceBars)
      m_state = VA_STATE_ACCEPTED_ABOVE;
   else if(below >= m_acceptanceBars)
      m_state = VA_STATE_ACCEPTED_BELOW;
  }

//+------------------------------------------------------------------+
double CValueAreaEngine::ComputeSourceQuality() const
  {
   switch(m_source)
     {
      case VA_SOURCE_REAL_TRADE_TICKS:   return 1.00;
      case VA_SOURCE_BROKER_TRADE_TICKS: return 0.85;
      case VA_SOURCE_REAL_VOLUME_BARS:   return 0.70;
      case VA_SOURCE_TICK_VOLUME_BARS:   return 0.50;
      default:                            return 0.00;
     }
  }

//+------------------------------------------------------------------+
void CValueAreaEngine::Compute(bool forceRecompute)
  {
   m_valid = false;

   if(m_candles == NULL || m_candles.Total() < 10)
      return;

   datetime barTime = m_candles.GetCandle(0).time;
   if(!forceRecompute && barTime == m_lastBarTime && m_poc != 0.0)
     {
      m_valid = true;
      return;
     }

   int bars = MathMin(m_lookbackBars, m_candles.Total());
   if(bars < 10)
      return;

   double rangeHigh = -DBL_MAX;
   double rangeLow = DBL_MAX;

   for(int i = 0; i < bars; i++)
     {
      CandleData cd = m_candles.GetCandle(i);
      if(cd.high > rangeHigh) rangeHigh = cd.high;
      if(cd.low < rangeLow) rangeLow = cd.low;
     }

   double range = rangeHigh - rangeLow;
   if(range <= 0.0)
      return;

   double binSize = range / m_numBins;
   if(binSize <= 0.0)
      return;

   double volumes[];
   ArrayResize(volumes, m_numBins);
   ArrayInitialize(volumes, 0.0);

   m_source = VA_SOURCE_UNDEFINED;
   bool built = BuildTickProfile(rangeLow, binSize, volumes);

   if(!built)
     {
      ArrayInitialize(volumes, 0.0);
      ENUM_VALUE_PROFILE_SOURCE fallbackSource = VA_SOURCE_UNDEFINED;
      built = BuildBarProfile(rangeLow, binSize, volumes, fallbackSource);
      m_source = fallbackSource;
     }

   if(!built)
      return;

   ComputeValueArea(rangeLow, binSize, volumes);
   if(!m_valid)
      return;

   m_sourceQuality = ComputeSourceQuality();
   m_valid = true;
   ComputeState();
   m_lastBarTime = barTime;
  }

//+------------------------------------------------------------------+
ENUM_VALUE_AREA_ZONE CValueAreaEngine::Zone(double price) const
  {
   if(!m_valid)
      return VA_ZONE_UNDEFINED;

   if(price > m_vah) return VA_ZONE_ABOVE;
   if(price < m_val) return VA_ZONE_BELOW;
   return VA_ZONE_INSIDE;
  }

//+------------------------------------------------------------------+
bool CValueAreaEngine::LocationOK(bool forBuy, double price) const
  {
   if(!m_valid)
      return true;

   ENUM_VALUE_AREA_ZONE z = Zone(price);

   if(forBuy)
      return (z == VA_ZONE_INSIDE || z == VA_ZONE_BELOW);

   return (z == VA_ZONE_INSIDE || z == VA_ZONE_ABOVE);
  }

//+------------------------------------------------------------------+
double CValueAreaEngine::Score(bool forBuy, double price) const
  {
   if(!m_valid || price <= 0.0)
      return 0.0;

   ENUM_VALUE_AREA_ZONE z = Zone(price);

   if(z == VA_ZONE_INSIDE)
     {
      double half = (m_vah - m_val) / 2.0;
      if(half <= 0.0)
         return 0.5;

      double distFromPOC = MathAbs(price - m_poc);
      return MathMax(0.5, MathMin(1.0, 1.0 - 0.5 * distFromPOC / half));
     }

   double atr = m_candles.GetATR(0);
   if(atr <= 0.0)
      return 0.0;

   if(forBuy)
     {
      if(z == VA_ZONE_BELOW)
        {
         double distATR = (m_val - price) / atr;
         return MathMax(0.0, MathMin(0.90, 0.90 * (1.0 - distATR / 2.0)));
        }

      if(z == VA_ZONE_ABOVE)
         return (m_state == VA_STATE_ACCEPTED_ABOVE) ? 0.65 : 0.0;
     }
   else
     {
      if(z == VA_ZONE_ABOVE)
        {
         double distATR = (price - m_vah) / atr;
         return MathMax(0.0, MathMin(0.90, 0.90 * (1.0 - distATR / 2.0)));
        }

      if(z == VA_ZONE_BELOW)
         return (m_state == VA_STATE_ACCEPTED_BELOW) ? 0.65 : 0.0;
     }

   return 0.0;
  }

//+------------------------------------------------------------------+
bool CValueAreaEngine::HardConflict(bool forBuy, double price) const
  {
   if(!m_valid || price <= 0.0 || m_sourceQuality < 0.70)
      return false;

   ENUM_VALUE_AREA_ZONE z = Zone(price);

   if(forBuy && z == VA_ZONE_ABOVE)
     {
      if(m_state == VA_STATE_REJECTED_ABOVE)
         return true;

      if(m_state != VA_STATE_ACCEPTED_ABOVE && m_pocMigrationATR <= -0.25)
         return true;
     }

   if(!forBuy && z == VA_ZONE_BELOW)
     {
      if(m_state == VA_STATE_REJECTED_BELOW)
         return true;

      if(m_state != VA_STATE_ACCEPTED_BELOW && m_pocMigrationATR >= 0.25)
         return true;
     }

   return false;
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/ValueAreaEngine.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/OrderBlock.mqh
//+------------------------------------------------------------------+
//|                                         SmartMoney/OrderBlock.mqh |
//+------------------------------------------------------------------+
#ifndef ORDERBLOCK_MQH
#define ORDERBLOCK_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/BOS.mqh

// v2.8 addition, closing the gap flagged in the pre-rewrite audit: the
// codebase had Inducement/FVG/Liquidity/SR confluence but nothing reading
// Order Blocks on a higher timeframe, even though the point-table spec's
// "HTF Alignment" bucket implicitly assumes one. This engine is meant to
// run on an HTF CTFContext (H4/D1) separate from the entry-timeframe FVG
// context — same "own candle series per timeframe" discipline as
// CTFContext itself.
//
// Definition used (standard SMC OB, not a proprietary variant):
//   Bullish OB = the last down-close candle immediately before a
//                displacement leg that breaks structure upward.
//   Bearish OB = the last up-close candle immediately before a
//                displacement leg that breaks structure downward.
// Zone = candle's [open, low] for a bullish OB, [open, high] for a
// bearish OB — the body-to-wick-extreme range, which is where the
// original imbalance/inefficiency actually sits, not the full [high,low]
// wick range (that overstates the zone and generates false confluence).
class COrderBlock
  {
private:
   CCandleData*      m_candles;
   OrderBlockZone     m_zones[];
   int                m_zoneCount;
   double             m_displacementATRMult;   // min range/ATR to count as a displacement leg
   double             m_minBodyRatio;          // min body/range of the displacement candle
   int                m_maxZones;              // cap so old HTF zones don't accumulate forever

   bool              IsDisplacement(int idx, bool &bullish);
   // FIX (audit #18): checks whether a genuine, chronologically-confirmed
   // BOS event (from the already-fixed CBOS engine — see Structure/BOS.mqh)
   // exists at or near this candle, in the matching direction.
   bool              CoincidesWithStructureBreak(int idx, bool bullish);
   void              UpdateState(OrderBlockZone &z);
   CBOS*             m_bos;

public:
                     COrderBlock();
   void              Init(CCandleData* candleData, CBOS* bos, double displacementATRMult = 1.5,
                          double minBodyRatio = 0.5, int maxZones = 15);
   void              Detect();
   void              UpdateAllStates();
   int               Count() const { return m_zoneCount; }
   OrderBlockZone     GetZone(int i) const; // 0 = most recent
   // Nearest fresh/tested zone in `dir` within distATRMax of price; returns
   // false if none. Used by Scoring::ObScore()/ObGate().
   bool              NearestZone(ENUM_FVG_DIR dir, double price, double atr, double distATRMax, OrderBlockZone &out);
  };
//+------------------------------------------------------------------+
COrderBlock::COrderBlock() : m_candles(NULL), m_bos(NULL), m_zoneCount(0), m_displacementATRMult(1.5),
                              m_minBodyRatio(0.5), m_maxZones(15) {}
//+------------------------------------------------------------------+
void COrderBlock::Init(CCandleData* candleData, CBOS* bos, double displacementATRMult, double minBodyRatio, int maxZones)
  {
   m_candles = candleData;
   m_bos = bos;
   m_displacementATRMult = displacementATRMult;
   m_minBodyRatio = minBodyRatio;
   m_maxZones = MathMax(3, maxZones);
  }
//+------------------------------------------------------------------+
bool COrderBlock::IsDisplacement(int idx, bool &bullish)
  {
   if(m_candles == NULL) return false;
   CandleData cd = m_candles.GetCandle(idx);
   double atr = cd.atr;
   if(atr <= 0) return false;
   double range = cd.high - cd.low;
   if(range <= 0) return false;
   double body = MathAbs(cd.close - cd.open);
   if(range / atr < m_displacementATRMult) return false;
   if(body / range < m_minBodyRatio) return false;
   bullish = (cd.close > cd.open);
   return true;
  }
//+------------------------------------------------------------------+
// FIX (audit #18): "large directional candle" alone was standing in for
// "order block confirmed by displacement + structure break" — the docstring
// at the top of this file promised the latter but IsDisplacement() only
// ever checked the former (range/ATR, body/range, direction). A large
// candle in the middle of a trading range with no structure broken is not
// an institutional order block by any SMC definition; it's just a big
// candle. This cross-checks against CBOS's already-corrected, non-
// lookahead event list: a real BOS event of the matching direction must
// exist within a small tolerance of this bar for the displacement to
// count as genuine. Tolerance of 2 bars covers the close that actually
// triggers the BOS landing 1-2 bars after the visually "big" candle
// starts the move (common when displacement spans multiple candles).
bool COrderBlock::CoincidesWithStructureBreak(int idx, bool bullish)
  {
   if(m_bos == NULL) return true; // no BOS engine wired in — fail open rather than silently disabling OB detection entirely
   int n = m_bos.Count();
   for(int i = 0; i < n; i++)
     {
      BOSEvent ev = m_bos.GetBOS(i);
      if(ev.is_bullish != bullish) continue;
      if(MathAbs(ev.bar_index - idx) <= 2) return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
// Series-indexed like FVG.mqh: shift 0 = current bar, i grows toward the
// past. For a displacement at idx, the "last opposite-close candle before
// it" is walked backward from idx+1 (older bars) until a candle whose
// close/open sign is opposite the displacement direction is found. This
// mirrors the standard SMC OB definition rather than blindly taking
// idx+1, which would misfire whenever two displacement-direction candles
// print back to back.
void COrderBlock::Detect()
  {
   m_zoneCount = 0;
   if(m_candles == NULL) return;
   ArrayFree(m_zones);
   int total = m_candles.Total();
   if(total < 5) return;

   int lookback = MathMin(total - 2, 300); // HTF context, doesn't need the full buffer
   for(int i = 1; i < lookback && m_zoneCount < m_maxZones; i++)
     {
      bool dispBullish;
      if(!IsDisplacement(i, dispBullish)) continue;
      if(!CoincidesWithStructureBreak(i, dispBullish)) continue; // FIX #18: displacement alone isn't enough

      // walk backward (older bars) from the displacement candle for the
      // nearest candle of the opposite close direction, within 5 bars —
      // beyond that it's no longer "the" originating candle.
      for(int j = i + 1; j < MathMin(i + 6, total); j++)
        {
         CandleData ob = m_candles.GetCandle(j);
         bool obUp = (ob.close > ob.open);
         if(dispBullish && obUp) continue;       // want a DOWN candle before a bullish leg
         if(!dispBullish && !obUp) continue;      // want an UP candle before a bearish leg

         OrderBlockZone z;
         ZeroMemory(z);
         z.time = ob.time;
         z.bar_index = j;
         z.dir = dispBullish ? FVG_BULL : FVG_BEAR;
         z.state = OB_FRESH;
         z.displacement_atr = (m_candles.GetCandle(i).high - m_candles.GetCandle(i).low) / m_candles.GetCandle(i).atr;
         if(dispBullish) { z.top = ob.open; z.bottom = ob.low; }
         else             { z.top = ob.high; z.bottom = ob.open; }
         if(z.top < z.bottom) { double t = z.top; z.top = z.bottom; z.bottom = t; }

         UpdateState(z);
         if(z.state != OB_MITIGATED)
           {
            int n = ArraySize(m_zones);
            ArrayResize(m_zones, n + 1);
            m_zones[n] = z;
            m_zoneCount++;
           }
         break; // only the nearest opposite-close candle counts as THE origin
        }
     }
  }
//+------------------------------------------------------------------+
// Re-derives state by replaying candles newer than the zone (bar_index-1
// down to 0) against its top/bottom — same touched/mitigated logic FVG
// uses, kept local here since OB mitigation rule differs slightly (a
// CLOSE through the far edge invalidates; a wick-only touch just tests).
void COrderBlock::UpdateState(OrderBlockZone &z)
  {
   if(m_candles == NULL) return;
   bool bullish = (z.dir == FVG_BULL);
   for(int k = z.bar_index - 1; k >= 0; k--)
     {
      CandleData cd = m_candles.GetCandle(k);
      bool touched = (cd.low <= z.top && cd.high >= z.bottom);
      if(!touched) continue;
      bool closedThrough = bullish ? (cd.close < z.bottom) : (cd.close > z.top);
      if(closedThrough) { z.state = OB_MITIGATED; return; }
      if(z.state == OB_FRESH) z.state = OB_TESTED;
     }
  }
//+------------------------------------------------------------------+
void COrderBlock::UpdateAllStates()
  {
   for(int i = 0; i < m_zoneCount; i++)
      UpdateState(m_zones[i]);
  }
//+------------------------------------------------------------------+
OrderBlockZone COrderBlock::GetZone(int i) const
  {
   OrderBlockZone empty;
   ZeroMemory(empty);
   if(i < 0 || i >= m_zoneCount) return empty;
   // m_zones is filled oldest-displacement-first per outer loop order
   // (i ascends = older); present most-recent-first to match every other
   // engine's GetZone(0)==newest convention.
   return m_zones[m_zoneCount - 1 - i];
  }
//+------------------------------------------------------------------+
bool COrderBlock::NearestZone(ENUM_FVG_DIR dir, double price, double atr, double distATRMax, OrderBlockZone &out)
  {
   if(atr <= 0) return false;
   double bestDist = -1.0;
   for(int i = 0; i < m_zoneCount; i++)
     {
      OrderBlockZone z = GetZone(i);
      if(z.dir != dir) continue;
      if(z.state == OB_MITIGATED) continue;
      double mid = (z.top + z.bottom) / 2.0;
      double dist = MathAbs(price - mid) / atr;
      if(dist > distATRMax) continue;
      if(bestDist < 0 || dist < bestDist) { bestDist = dist; out = z; }
     }
   return bestDist >= 0;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/OrderBlock.mqh
// BEGIN INLINED MODULE: includes/Analysis/TrendEngine.mqh
//+------------------------------------------------------------------+
//|                                             Analysis/TrendEngine.mqh |
//+------------------------------------------------------------------+
#ifndef TRENDENGINE_MQH
#define TRENDENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh
// already inlined once under include guard: includes/Structure/BOS.mqh
// already inlined once under include guard: includes/Structure/CHOCH.mqh

class CTrendEngine
  {
private:
   CSwingDetector*   m_swings;
   CBOS*             m_bos;
   CCHOCH*           m_choch;
   CCandleData*      m_candles;

   ENUM_TREND_STATE  DetermineTrend();

public:
                     CTrendEngine();
   void              Init(CSwingDetector* swings, CBOS* bos, CCHOCH* choch, CCandleData* candles);
   ENUM_TREND_STATE  GetCurrentTrend();
  };
//+------------------------------------------------------------------+
CTrendEngine::CTrendEngine() : m_swings(NULL), m_bos(NULL), m_choch(NULL), m_candles(NULL) {}
void CTrendEngine::Init(CSwingDetector* swings, CBOS* bos, CCHOCH* choch, CCandleData* candles)
  {
   m_swings = swings;
   m_bos = bos;
   m_choch = choch;
   m_candles = candles;
  }
//+------------------------------------------------------------------+
ENUM_TREND_STATE CTrendEngine::DetermineTrend()
  {
   if(m_swings == NULL || m_bos == NULL) return TREND_NEUTRAL;
   int hc = m_swings.HighCount();
   int lc = m_swings.LowCount();
   if(hc < 2 || lc < 2) return TREND_NEUTRAL;

   SwingPoint lastHigh = m_swings.GetHigh(0);
   SwingPoint prevHigh = m_swings.GetHigh(1);
   SwingPoint lastLow  = m_swings.GetLow(0);
   SwingPoint prevLow  = m_swings.GetLow(1);

   bool higherHigh = (lastHigh.price > prevHigh.price);
   bool higherLow  = (lastLow.price > prevLow.price);

   bool bullishBOS = false, bearishBOS = false;
   if(m_bos.Count() > 0)
     {
      BOSEvent recent = m_bos.GetBOS(0);
      bullishBOS = recent.is_bullish;
      bearishBOS = !recent.is_bullish;
     }

   if(higherHigh && higherLow && bullishBOS) return TREND_BULL_STRONG;
   if(higherHigh && higherLow) return TREND_BULL;
   if(!higherHigh && !higherLow && bearishBOS) return TREND_BEAR_STRONG;
   if(!higherHigh && !higherLow) return TREND_BEAR;
   return TREND_NEUTRAL;
  }
//+------------------------------------------------------------------+
ENUM_TREND_STATE CTrendEngine::GetCurrentTrend()
  {
   return DetermineTrend();
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Analysis/TrendEngine.mqh

// One full SMC detection pipeline, scoped to a single timeframe. Building
// this was the actual fix for "real per-timeframe BOS/liquidity/FVG" —
// previously every concept ran on whatever timeframe the chart happened
// to be on, so labeling a signal "H4 BOS" while running on M15 would have
// been a lie. Each CTFContext owns its own candle series for its own TF.
class CTFContext
  {
private:
   datetime          m_lastBarTime; // FIX: per-context new-bar gate — see Detect() below

public:
   ENUM_TIMEFRAMES   tf;
   CCandleData       candles;
   CSwingDetector    swings;
   CBOS              bos;
   CCHOCH            choch;
   CFVG              fvg;
   CLiquidity        liquidity;
   CSupportResistance sr;
   CTrendEngine      trend;
   CVolumeEngine     volume;      // v2.6 — RVOL / breakout-volume confirmation on this TF
   CFibonacciEngine  fibonacci;   // v2.6 — swing-anchored retracement zone on this TF
   CValueAreaEngine  valueArea;   // v2.6 — volume-profile POC/VAH/VAL location filter on this TF
   COrderBlock       orderBlock;  // v2.8 — HTF Order Block zones; meaningful when this context's tf is a higher TF than the entry FVG context

   bool              Init(string symbol, ENUM_TIMEFRAMES timeframe, int maxBars,
                          int swingStrength, double fvgMinSizeATR, double liqThresholdATR,
                          int rvolLookback = 20, int vaLookbackBars = 100, int vaNumBins = 24,
                          double vaPercent = 0.70, double obDisplacementATRMult = 1.5, double obMinBodyRatio = 0.5);
   // FIX (perf trap flagged during the v2.8 audit): "refreshes the entire
   // historical buffer on every tick... acceptable for 500 bars [but] not
   // a scalable architecture." Detect() now only actually does the
   // Refresh()+redetect work when THIS context's own timeframe has
   // printed a new bar since the last call — a context on H4 doesn't
   // need CopyRates/swings/BOS/liquidity/etc. recomputed on every M15
   // tick just because the chart TF ticked. force=true bypasses the gate
   // (used once at EA/indicator startup so the first pass always runs).
   void              Detect(bool force = false);
  }; // FIX: this closing brace was dropped during the event-driven-refresh edit —
     // everything below (both method bodies, plus the entire CTFContextPool class)
     // was accidentally left nested inside CTFContext. Caught by manual brace-balance
     // review since no MQL5 compiler is available in this environment; would have been
     // a hard compile failure in MetaEditor.
//+------------------------------------------------------------------+
bool CTFContext::Init(string symbol, ENUM_TIMEFRAMES timeframe, int maxBars,
                      int swingStrength, double fvgMinSizeATR, double liqThresholdATR,
                      int rvolLookback, int vaLookbackBars, int vaNumBins, double vaPercent,
                      double obDisplacementATRMult, double obMinBodyRatio)
  {
   tf = timeframe;
   m_lastBarTime = 0; // 0 guarantees the very first Detect() call always runs, force or not
   if(!candles.Init(symbol, tf, maxBars))
      return false;
   swings.SetParameters(&candles, swingStrength);
   bos.Init(&swings, &candles);
   choch.Init(&swings, &candles);
   fvg.Init(&candles, fvgMinSizeATR);
   liquidity.Init(&candles, &swings, liqThresholdATR);
   sr.Init(&candles, &swings);
   trend.Init(&swings, &bos, &choch, &candles);
   volume.Init(&candles, rvolLookback);
   fibonacci.Init(&swings, &candles);
   valueArea.Init(&candles, vaLookbackBars, vaNumBins, vaPercent);
   orderBlock.Init(&candles, &bos, obDisplacementATRMult, obMinBodyRatio);
   return true;
  }
//+------------------------------------------------------------------+
void CTFContext::Detect(bool force)
  {
   datetime barTime = iTime(candles.Symbol(), tf, 0);
   if(!force && barTime != 0 && barTime == m_lastBarTime)
      return; // no new bar on THIS context's own timeframe — nothing has changed since the last full pass
   m_lastBarTime = barTime;

   candles.Refresh();
   if(!candles.IsReady()) return;
   swings.Detect();
   bos.Detect();
   choch.Detect();
   fvg.Detect();
   fvg.UpdateAllStates();
   liquidity.Detect();
   sr.Detect();
   valueArea.Compute();
   orderBlock.Detect();
  }
//+------------------------------------------------------------------+
#define TFPOOL_MAX 16

// Dedupes contexts by timeframe: if Trend=D1 and someone else also asks
// for D1, they get the SAME context (and the same, single Detect() call
// per bar) rather than two redundant pipelines computing identical data.
class CTFContextPool
  {
private:
   CTFContext*       m_ctx[TFPOOL_MAX];
   int               m_count;
   string            m_symbol;
   int               m_maxBars;
   int               m_swingStrength;
   double            m_fvgMinSizeATR;
   double            m_liqThresholdATR;
   int               m_rvolLookback;
   int               m_vaLookbackBars;
   int               m_vaNumBins;
   double            m_vaPercent;
   double            m_obDisplacementATRMult;
   double            m_obMinBodyRatio;

public:
                     CTFContextPool();
                    ~CTFContextPool();
   void              Configure(string symbol, int maxBars, int swingStrength,
                               double fvgMinSizeATR, double liqThresholdATR, int rvolLookback = 20,
                               int vaLookbackBars = 100, int vaNumBins = 24, double vaPercent = 0.70,
                               double obDisplacementATRMult = 1.5, double obMinBodyRatio = 0.5);
   CTFContext*       Get(ENUM_TIMEFRAMES tf); // creates on first request, reuses after
   void              DetectAll(bool force = false);
  };
//+------------------------------------------------------------------+
CTFContextPool::CTFContextPool() : m_count(0), m_rvolLookback(20), m_vaLookbackBars(100),
                                    m_vaNumBins(24), m_vaPercent(0.70),
                                    m_obDisplacementATRMult(1.5), m_obMinBodyRatio(0.5)
  {
   for(int i = 0; i < TFPOOL_MAX; i++) m_ctx[i] = NULL;
  }
CTFContextPool::~CTFContextPool()
  {
   for(int i = 0; i < m_count; i++)
      if(m_ctx[i] != NULL) delete m_ctx[i];
  }
//+------------------------------------------------------------------+
void CTFContextPool::Configure(string symbol, int maxBars, int swingStrength,
                               double fvgMinSizeATR, double liqThresholdATR, int rvolLookback,
                               int vaLookbackBars, int vaNumBins, double vaPercent,
                               double obDisplacementATRMult, double obMinBodyRatio)
  {
   m_symbol = symbol;
   m_maxBars = maxBars;
   m_swingStrength = swingStrength;
   m_fvgMinSizeATR = fvgMinSizeATR;
   m_liqThresholdATR = liqThresholdATR;
   m_rvolLookback = MathMax(5, rvolLookback);
   m_vaLookbackBars = MathMax(10, vaLookbackBars);
   m_vaNumBins = MathMax(5, vaNumBins);
   m_vaPercent = (vaPercent > 0.0 && vaPercent < 1.0) ? vaPercent : 0.70;
   m_obDisplacementATRMult = (obDisplacementATRMult > 0) ? obDisplacementATRMult : 1.5;
   m_obMinBodyRatio = (obMinBodyRatio > 0 && obMinBodyRatio <= 1.0) ? obMinBodyRatio : 0.5;
  }
//+------------------------------------------------------------------+
CTFContext* CTFContextPool::Get(ENUM_TIMEFRAMES tf)
  {
   for(int i = 0; i < m_count; i++)
      if(m_ctx[i] != NULL && m_ctx[i].tf == tf)
         return m_ctx[i];

   if(m_count >= TFPOOL_MAX)
     {
      Print("MedisTouch: TFContextPool full (", TFPOOL_MAX, " timeframes) — refusing to return a context for the wrong timeframe.");
      return NULL;
     }
   CTFContext* c = new CTFContext();
   if(!c.Init(m_symbol, tf, m_maxBars, m_swingStrength, m_fvgMinSizeATR, m_liqThresholdATR, m_rvolLookback,
             m_vaLookbackBars, m_vaNumBins, m_vaPercent, m_obDisplacementATRMult, m_obMinBodyRatio))
     {
      Print("MedisTouch: failed to init TFContext for timeframe ", EnumToString(tf));
      delete c;
      return NULL;
     }
   m_ctx[m_count++] = c;
   return c;
  }
//+------------------------------------------------------------------+
void CTFContextPool::DetectAll(bool force)
  {
   for(int i = 0; i < m_count; i++)
      if(m_ctx[i] != NULL)
         m_ctx[i].Detect(force);
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Analysis/TFContext.mqh
// BEGIN INLINED MODULE: includes/Analysis/TopDownMTFEngine.mqh
//+------------------------------------------------------------------+
//| Analysis/TopDownMTFEngine.mqh                                    |
//| Direction-agnostic D1 -> H4 -> H1 -> M30 -> M15 -> M5 -> M1     |
//| Confidence arbitration only: never creates or forces a trade.      |
//+------------------------------------------------------------------+
#ifndef TOPDOWNMTFENGINE_MQH
#define TOPDOWNMTFENGINE_MQH

// already inlined once under include guard: includes/Analysis/TFContext.mqh

class CTopDownMTFEngine
  {
private:
   CTFContext* m_d1;
   CTFContext* m_h4;
   CTFContext* m_h1;
   CTFContext* m_m30;
   CTFContext* m_m15;
   CTFContext* m_m5;
   CTFContext* m_m1;
   double      m_maxConfidenceAdjustment;
   int         m_chochLookbackBars;
   bool        m_ready;
   double      m_longScore;
   double      m_shortScore;
   string      m_summary;

   double TrendStrength(const ENUM_TREND_STATE state) const;
   void AddContext(CTFContext* ctx,const double weight,
                   double &longScore,double &shortScore) const;
   double ClampScore(const double value) const;

public:
   CTopDownMTFEngine();
   bool Init(CTFContext* d1,CTFContext* h4,CTFContext* h1,
             CTFContext* m30,CTFContext* m15,CTFContext* m5,CTFContext* m1);
   void Configure(const double maxConfidenceAdjustment=8.0,
                  const int chochLookbackBars=8);
   bool Evaluate();
   bool IsReady() const { return m_ready; }
   double LongScore() const { return m_longScore; }
   double ShortScore() const { return m_shortScore; }
   double AdjustConfidence(const bool isBuy,const double rawConfidence) const;
   void AdjustSetup(TradeSetup &setup) const;
   string Summary() const { return m_summary; }
  };

CTopDownMTFEngine::CTopDownMTFEngine() :
   m_d1(NULL),m_h4(NULL),m_h1(NULL),m_m30(NULL),m_m15(NULL),m_m5(NULL),m_m1(NULL),
   m_maxConfidenceAdjustment(8.0),m_chochLookbackBars(8),m_ready(false),
   m_longScore(0.0),m_shortScore(0.0),m_summary("top-down context not evaluated")
  {
  }

bool CTopDownMTFEngine::Init(CTFContext* d1,CTFContext* h4,CTFContext* h1,
                             CTFContext* m30,CTFContext* m15,CTFContext* m5,CTFContext* m1)
  {
   if(d1==NULL || h4==NULL || h1==NULL || m30==NULL ||
      m15==NULL || m5==NULL || m1==NULL)
      return false;
   if(d1.tf!=PERIOD_D1 || h4.tf!=PERIOD_H4 || h1.tf!=PERIOD_H1 ||
      m30.tf!=PERIOD_M30 || m15.tf!=PERIOD_M15 ||
      m5.tf!=PERIOD_M5 || m1.tf!=PERIOD_M1)
      return false;
   m_d1=d1;
   m_h4=h4;
   m_h1=h1;
   m_m30=m30;
   m_m15=m15;
   m_m5=m5;
   m_m1=m1;
   m_ready=true;
   return true;
  }

void CTopDownMTFEngine::Configure(const double maxConfidenceAdjustment,
                                  const int chochLookbackBars)
  {
   // A confidence modifier is deliberately bounded; it is never a standalone
   // reason to create, invalidate, or force an order.
   m_maxConfidenceAdjustment=MathMax(0.0,MathMin(15.0,maxConfidenceAdjustment));
   m_chochLookbackBars=MathMax(1,MathMin(100,chochLookbackBars));
  }

double CTopDownMTFEngine::TrendStrength(const ENUM_TREND_STATE state) const
  {
   if(state==TREND_BULL_STRONG || state==TREND_BEAR_STRONG) return 1.0;
   if(state==TREND_BULL || state==TREND_BEAR) return 0.75;
   return 0.0;
  }

double CTopDownMTFEngine::ClampScore(const double value) const
  {
   if(!MathIsValidNumber(value)) return 0.0;
   return MathMax(0.0,MathMin(100.0,value));
  }

void CTopDownMTFEngine::AddContext(CTFContext* ctx,const double weight,
                                   double &longScore,double &shortScore) const
  {
   if(ctx==NULL || !ctx.candles.IsReady()) return;
   ENUM_TREND_STATE trend=ctx.trend.GetCurrentTrend();
   double strength=TrendStrength(trend);
   if(trend==TREND_BULL || trend==TREND_BULL_STRONG)
      longScore+=weight*strength;
   else if(trend==TREND_BEAR || trend==TREND_BEAR_STRONG)
      shortScore+=weight*strength;

   // A recent confirmed CHoCH can surface a genuine reversal candidate even
   // when the trend classification has not yet flipped. It modifies both
   // sides symmetrically and is limited to a small share of that TF's weight.
   if(ctx.choch.Count()>0)
     {
      CHOCHPoint change=ctx.choch.Get(0);
      int shift=iBarShift(ctx.candles.Symbol(),ctx.tf,change.time,false);
      if(shift>=0 && shift<=m_chochLookbackBars)
        {
         double reversalWeight=weight*0.15;
         if(change.bullish)
           {
            longScore+=reversalWeight;
            shortScore-=reversalWeight;
           }
         else
           {
            shortScore+=reversalWeight;
            longScore-=reversalWeight;
           }
        }
     }
  }

bool CTopDownMTFEngine::Evaluate()
  {
   m_ready=(m_d1!=NULL && m_h4!=NULL && m_h1!=NULL &&
            m_m30!=NULL && m_m15!=NULL && m_m5!=NULL && m_m1!=NULL);
   if(!m_ready) return false;
   if(!m_d1.candles.IsReady() || !m_h4.candles.IsReady() ||
      !m_h1.candles.IsReady() || !m_m30.candles.IsReady() ||
      !m_m15.candles.IsReady() || !m_m5.candles.IsReady() ||
      !m_m1.candles.IsReady())
     {
      m_ready=false;
      m_summary="top-down context unavailable: one or more timeframes lack sufficient history";
      return false;
     }

   double longScore=0.0,shortScore=0.0;
   // Weights sum to 100: higher timeframes establish context while entry
   // timeframes refine it. M1 is deliberately a small contributor, not the
   // authority to override a valid higher-timeframe thesis by itself.
   AddContext(m_d1,30.0,longScore,shortScore);
   AddContext(m_h4,24.0,longScore,shortScore);
   AddContext(m_h1,18.0,longScore,shortScore);
   AddContext(m_m30,10.0,longScore,shortScore);
   AddContext(m_m15,8.0,longScore,shortScore);
   AddContext(m_m5,6.0,longScore,shortScore);
   AddContext(m_m1,4.0,longScore,shortScore);
   m_longScore=ClampScore(longScore);
   m_shortScore=ClampScore(shortScore);
   m_summary=StringFormat("MTF long=%.1f short=%.1f [D1/H4/H1/M30/M15/M5/M1]",m_longScore,m_shortScore);
   m_ready=true;
   return true;
  }

double CTopDownMTFEngine::AdjustConfidence(const bool isBuy,const double rawConfidence) const
  {
   if(!m_ready || !MathIsValidNumber(rawConfidence))
      return ClampScore(rawConfidence);
   double directionalEdge=m_longScore-m_shortScore;
   if(!isBuy) directionalEdge=-directionalEdge;
   double adjusted=rawConfidence+m_maxConfidenceAdjustment*directionalEdge/100.0;
   return ClampScore(adjusted);
  }

void CTopDownMTFEngine::AdjustSetup(TradeSetup &setup) const
  {
   if(!setup.active) return;
   if(setup.type==ORDER_TYPE_BUY)
      setup.confidence=AdjustConfidence(true,setup.confidence);
   else if(setup.type==ORDER_TYPE_SELL)
      setup.confidence=AdjustConfidence(false,setup.confidence);
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Analysis/TopDownMTFEngine.mqh
// BEGIN INLINED MODULE: includes/Analysis/Scoring.mqh
//+------------------------------------------------------------------+
//|                                                Analysis/Scoring.mqh |
//+------------------------------------------------------------------+
#ifndef SCORING_MQH
#define SCORING_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Analysis/TFContext.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/Inducement.mqh
//+------------------------------------------------------------------+
//|                                          SmartMoney/Inducement.mqh |
//+------------------------------------------------------------------+
#ifndef INDUCEMENT_MQH
#define INDUCEMENT_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh

// Validates the sequence: Impulse -> Internal pullback structure ->
// Internal liquidity sweep (inducement) -> minor BOS -> only then is a
// setup "confirmed". This turns the indicator from a feature detector
// (does an FVG exist near price?) into a decision engine (did price
// actually get manipulated into a stop run before the real move?).
//
// SCOPE / HONEST LIMITATIONS:
//  - All detection here runs on ONE timeframe (whatever CCandleData this
//    is Init()'d with — normally the FVG/entry timeframe, since that's
//    where the setup actually triggers). It does not cross-check the
//    impulse against a higher timeframe.
//  - "Minor" structure is a local 1-bar fractal (compare each bar only to
//    its immediate left/right neighbor), deliberately looser than the
//    swing detector used elsewhere (which defaults to 3 bars) — the whole
//    point of this module is to see the SMALL structure inside a pullback
//    that the main SwingDetector is tuned to ignore.
//  - "Equal" highs/lows use the same ATR-fraction tolerance band as
//    Liquidity.mqh's internal pools, passed in as equalTolATR, so the two
//    concepts stay consistent with each other.
class CInducement
  {
private:
   CCandleData*      m_candles;
   int               m_lookbackBars;
   double            m_impulseATRMult;   // min (bar range / ATR) to qualify as a displacement bar
   double            m_impulseBodyRatio; // min body/range ratio for a displacement bar
   double            m_equalTolATR;      // tolerance band for "equal" highs/lows, as a fraction of ATR
   int               m_maxLegExtend;     // how many bars a leg can be extended outward while still qualifying

   bool              IsDisplacementBar(int idx, bool bullish);
   bool              FindImpulse(bool bullish, ImpulseLeg &leg);
   bool              FindMinorSwing(int idx, bool wantHigh); // local 1-bar fractal
   bool              FindEqualPair(bool wantLows, int scanFrom, int scanTo, double atr,
                                   double &poolPrice, int &nearIdx, int &farIdx);

   // --- v2.9 additions ---------------------------------------------
   bool              m_requireMinSweepGrade; // OFF by default — see Configure()
   ENUM_SWEEP_GRADE  m_minSweepGrade;
   bool              m_requireFreshSetup;    // OFF by default — hard-reject when TimeDecay() hits 0
   int               m_maxBarsSinceBOS;      // decay-to-zero cutoff, default 5 per the 0/90/75/55/0 curve

   ENUM_SWEEP_GRADE  GradeSweep(int sweepBarIdx, bool forBuy, double poolPrice, double &gradeScore);
   double            BOSStrength(int bosBarIdx, double breakLevel, bool forBuy);
   double            TimeDecay(int barsSinceBOS);

public:
                     CInducement();
   void              Init(CCandleData* candles, int lookbackBars = 40, double impulseATRMult = 1.2,
                          double impulseBodyRatio = 0.6, double equalTolATR = 0.2, int maxLegExtend = 10);
   // v2.9 addition. Both gates default OFF/lenient — same "unvalidated
   // until proven on this instrument via ablation testing" discipline as
   // every other v2.6/v2.8 filter in this codebase (see Scoring.mqh's
   // class-level comment). sweepGrade/bosStrength/timeDecay are computed
   // and returned on every call regardless of these flags; only whether
   // a sub-B-grade or fully-decayed setup gets hard-rejected is gated.
   void              ConfigureQualityGates(bool requireMinSweepGrade, ENUM_SWEEP_GRADE minSweepGrade,
                                            bool requireFreshSetup, int maxBarsSinceBOS = 5);
   InducementResult  Validate(bool forBuy);
  };
//+------------------------------------------------------------------+
CInducement::CInducement() : m_candles(NULL), m_lookbackBars(40), m_impulseATRMult(1.2),
                              m_impulseBodyRatio(0.6), m_equalTolATR(0.2), m_maxLegExtend(10),
                              m_requireMinSweepGrade(false), m_minSweepGrade(SWEEP_GRADE_B),
                              m_requireFreshSetup(false), m_maxBarsSinceBOS(5) {}
//+------------------------------------------------------------------+
void CInducement::Init(CCandleData* candles, int lookbackBars, double impulseATRMult,
                       double impulseBodyRatio, double equalTolATR, int maxLegExtend)
  {
   m_candles = candles;
   m_lookbackBars = MathMax(10, lookbackBars);
   m_impulseATRMult = impulseATRMult;
   m_impulseBodyRatio = impulseBodyRatio;
   m_equalTolATR = equalTolATR;
   m_maxLegExtend = MathMax(2, maxLegExtend);
  }
//+------------------------------------------------------------------+
void CInducement::ConfigureQualityGates(bool requireMinSweepGrade, ENUM_SWEEP_GRADE minSweepGrade,
                                        bool requireFreshSetup, int maxBarsSinceBOS)
  {
   m_requireMinSweepGrade = requireMinSweepGrade;
   m_minSweepGrade = minSweepGrade;
   m_requireFreshSetup = requireFreshSetup;
   m_maxBarsSinceBOS = MathMax(1, maxBarsSinceBOS);
  }
//+------------------------------------------------------------------+
bool CInducement::IsDisplacementBar(int idx, bool bullish)
  {
   if(m_candles == NULL) return false;
   CandleData cd = m_candles.GetCandle(idx);
   double atr = m_candles.GetATR(idx);
   if(atr <= 0) return false;
   double range = cd.high - cd.low;
   if(range <= 0) return false;
   double body = MathAbs(cd.close - cd.open);
   double bodyRatio = body / range;
   bool directional = bullish ? (cd.close > cd.open) : (cd.close < cd.open);
   if(!directional) return false;
   if(range / atr < m_impulseATRMult) return false;
   if(bodyRatio < m_impulseBodyRatio) return false;
   // Opposite wick should be small — a big rejection wick against the
   // move undercuts the "displacement" read even if the body qualifies.
   double oppWick = bullish ? (cd.open - cd.low) : (cd.high - cd.open);
   if(oppWick > 0.3 * range) return false;
   return true;
  }
//+------------------------------------------------------------------+
// Scans the lookback window for a qualifying displacement bar, then
// extends the leg outward (toward more-recent AND toward older bars)
// while price keeps making new extremes in the same direction, so the
// leg's start/end prices bound the whole impulse move, not just the one
// bar that tripped the threshold.
bool CInducement::FindImpulse(bool bullish, ImpulseLeg &leg)
  {
   ZeroMemory(leg);
   if(m_candles == NULL) return false;
   int total = m_candles.Total();
   int scanLimit = MathMin(m_lookbackBars, total - 1);

   for(int i = 1; i <= scanLimit; i++)
     {
      if(!IsDisplacementBar(i, bullish)) continue;

      int newerBar = i; // extend toward index 0 (more recent)
      int olderBar = i; // extend toward higher index (older)
      double bestExtreme = bullish ? m_candles.GetCandle(i).high : m_candles.GetCandle(i).low;

      for(int k = i - 1; k >= MathMax(0, i - m_maxLegExtend); k--)
        {
         CandleData cd = m_candles.GetCandle(k);
         bool extends = bullish ? (cd.high >= bestExtreme) : (cd.low <= bestExtreme);
         if(!extends) break;
         bestExtreme = bullish ? cd.high : cd.low;
         newerBar = k;
        }
      double oldExtreme = bullish ? m_candles.GetCandle(i).low : m_candles.GetCandle(i).high;
      for(int k = i + 1; k <= MathMin(total - 1, i + m_maxLegExtend); k++)
        {
         CandleData cd = m_candles.GetCandle(k);
         bool extends = bullish ? (cd.low <= oldExtreme) : (cd.high >= oldExtreme);
         if(!extends) break;
         oldExtreme = bullish ? cd.low : cd.high;
         olderBar = k;
        }

      leg.valid = true;
      leg.start_bar = olderBar;
      leg.end_bar = newerBar;
      leg.displacement_bar = i;
      leg.start_time = m_candles.GetCandle(olderBar).time;
      leg.end_time = m_candles.GetCandle(newerBar).time;
      leg.start_price = oldExtreme;
      leg.end_price = bestExtreme;
      leg.bullish = bullish;

      double atr = m_candles.GetATR(i);
      double distATR = (atr > 0) ? MathAbs(leg.end_price - leg.start_price) / atr : 0.0;
      leg.strength = MathMax(0.0, MathMin(distATR / 3.0, 1.0));
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
// Local 1-bar fractal: idx is a minor swing high/low if it beats its
// immediate left AND right neighbor. Deliberately tighter than the main
// SwingDetector (strength 3) — this is meant to catch the small internal
// structure a pullback makes, not the major structure.
bool CInducement::FindMinorSwing(int idx, bool wantHigh)
  {
   if(m_candles == NULL) return false;
   int total = m_candles.Total();
   if(idx < 1 || idx >= total - 1) return false;
   if(wantHigh)
     {
      double h = m_candles.GetCandle(idx).high;
      return (h >= m_candles.GetCandle(idx - 1).high && h >= m_candles.GetCandle(idx + 1).high);
     }
   double l = m_candles.GetCandle(idx).low;
   return (l <= m_candles.GetCandle(idx - 1).low && l <= m_candles.GetCandle(idx + 1).low);
  }
//+------------------------------------------------------------------+
// Scans [scanFrom, scanTo] (series indices, scanFrom = more recent) for
// two minor swings of the requested type whose prices sit within
// m_equalTolATR * atr of each other — an "equal highs/lows" pool, the
// classic resting-liquidity signature.
bool CInducement::FindEqualPair(bool wantLows, int scanFrom, int scanTo, double atr,
                                double &poolPrice, int &nearIdx, int &farIdx)
  {
   poolPrice = 0.0; nearIdx = -1; farIdx = -1;
   if(m_candles == NULL || atr <= 0) return false;
   double band = m_equalTolATR * atr;

   int found[]; ArrayResize(found, 0);
   for(int i = scanFrom; i <= scanTo; i++)
     {
      if(!FindMinorSwing(i, wantLows ? false : true)) continue; // wantLows -> look for swing LOWS
      int n = ArraySize(found);
      ArrayResize(found, n + 1);
      found[n] = i;
     }
   int fc = ArraySize(found);
   for(int a = 0; a < fc - 1; a++)
     {
      double pa = wantLows ? m_candles.GetCandle(found[a]).low : m_candles.GetCandle(found[a]).high;
      for(int b = a + 1; b < fc; b++)
        {
         double pb = wantLows ? m_candles.GetCandle(found[b]).low : m_candles.GetCandle(found[b]).high;
         if(MathAbs(pa - pb) <= band)
           {
            nearIdx = MathMin(found[a], found[b]);
            farIdx  = MathMax(found[a], found[b]);
            poolPrice = wantLows ? MathMin(pa, pb) : MathMax(pa, pb);
            return true;
           }
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
// v2.9. Grades the sweep bar itself instead of just recording that
// price wicked past the pool and closed back inside it. Three
// components, each 0-1, blended 40/30/30:
//   - rejectionRatio: how much of the wick got reclaimed by the close
//     (a full reclaim reads 1.0; a close that barely got back inside
//     the pool reads near 0).
//   - penetration shape: penalizes both a near-zero poke (not enough of
//     a stop-run to mean anything) and a very deep wick (starts looking
//     like a breakout attempt, not a hunt) — full credit in the
//     0.03-0.60 ATR band, tapering outside it.
//   - followThrough: does the bar immediately after the sweep bar
//     qualify as its own displacement bar in the trade direction? This
//     is the "sweep -> rejection -> displacement -> BOS" causal chain
//     from the spec, not just "sweep -> tiny BOS".
// Thresholds (0.70 / 0.40) are starting points, not tuned constants —
// they need the same ablation-test treatment as everything else here
// before being trusted live.
ENUM_SWEEP_GRADE CInducement::GradeSweep(int sweepBarIdx, bool forBuy, double poolPrice, double &gradeScore)
  {
   gradeScore = 0.0;
   if(m_candles == NULL || sweepBarIdx < 0) return SWEEP_GRADE_NONE;
   CandleData cd = m_candles.GetCandle(sweepBarIdx);
   double atr = m_candles.GetATR(sweepBarIdx);
   if(atr <= 0) return SWEEP_GRADE_NONE;

   double wick = forBuy ? (poolPrice - cd.low) : (cd.high - poolPrice);
   if(wick <= 0) return SWEEP_GRADE_NONE; // shouldn't happen if sweepFound was true, but stay defensive

   double closeBack = forBuy ? (cd.close - poolPrice) : (poolPrice - cd.close);
   double rejectionRatio = MathMax(0.0, MathMin(closeBack / wick, 1.0));

   double penetrationATR = wick / atr;
   double shapeScore;
   if(penetrationATR >= 0.03 && penetrationATR <= 0.60)
      shapeScore = 1.0;
   else
      shapeScore = MathMax(0.0, 1.0 - MathAbs(penetrationATR - 0.30) / 0.60);

   bool followThrough = (sweepBarIdx - 1 >= 0) ? IsDisplacementBar(sweepBarIdx - 1, forBuy) : false;

   gradeScore = MathMax(0.0, MathMin(0.4 * rejectionRatio + 0.3 * shapeScore + 0.3 * (followThrough ? 1.0 : 0.0), 1.0));

   if(gradeScore >= 0.70) return SWEEP_GRADE_A;
   if(gradeScore >= 0.40) return SWEEP_GRADE_B;
   return SWEEP_GRADE_C;
  }
//+------------------------------------------------------------------+
// v2.9. Continuous replacement for the old binary bosConfirmed-only
// read: full credit at a 0.5 ATR break beyond the opposing minor swing
// (breakDist component), blended with the confirming bar's own
// body-dominance (a decisive close-through vs. a bar that barely
// tagged the level and closed unconvincingly). 60/40 weighting mirrors
// IsDisplacementBar()'s existing emphasis on range/ATR over raw body%.
double CInducement::BOSStrength(int bosBarIdx, double breakLevel, bool forBuy)
  {
   if(m_candles == NULL || bosBarIdx < 0) return 0.0;
   CandleData cd = m_candles.GetCandle(bosBarIdx);
   double atr = m_candles.GetATR(bosBarIdx);
   if(atr <= 0) return 0.0;

   double breakDist = forBuy ? (cd.close - breakLevel) : (breakLevel - cd.close);
   if(breakDist <= 0) return 0.0; // shouldn't happen if bosConfirmed was true

   double range = cd.high - cd.low;
   double bodyRatio = (range > 0) ? MathAbs(cd.close - cd.open) / range : 0.0;
   double distScore = MathMin(breakDist / (0.5 * atr), 1.0);
   return MathMax(0.0, MathMin(0.6 * distScore + 0.4 * bodyRatio, 1.0));
  }
//+------------------------------------------------------------------+
// v2.9. Item #18 from the review: a sweep/BOS 2 bars ago isn't the same
// setup as one 5 bars ago. Curve is a starting point (illustrative
// buckets from the spec), not learned from data yet.
double CInducement::TimeDecay(int barsSinceBOS)
  {
   if(barsSinceBOS <= 1) return 1.00;
   if(barsSinceBOS == 2) return 0.90;
   if(barsSinceBOS == 3) return 0.75;
   if(barsSinceBOS == 4) return 0.55;
   return 0.0;
  }
//+------------------------------------------------------------------+
InducementResult CInducement::Validate(bool forBuy)
  {
   InducementResult r;
   ZeroMemory(r);
   r.sweepBarIndex = -1;
   r.displacementBarIndex = -1;
   r.bosBarIndex = -1;
   if(m_candles == NULL || m_candles.Total() < 20)
     {
      r.reason = "Not enough bars";
      return r;
     }

   ImpulseLeg leg;
   if(!FindImpulse(forBuy, leg))
     {
      r.reason = "No qualifying impulse (displacement) found in lookback window";
      return r;
     }
   r.impulseFound = true;
   r.displacementBarIndex = leg.displacement_bar;
   r.impulseScore = 15.0;

   // Pullback/continuation region: everything more recent than the
   // impulse's newer edge, i.e. series indices [0, leg.end_bar - 1].
   int pullbackTo = leg.end_bar - 1;
   if(pullbackTo < 2)
     {
      r.reason = "Impulse too recent — no pullback bars to inspect yet";
      return r;
     }

   double atr = m_candles.GetATR(leg.end_bar);
   if(atr <= 0)
     {
      r.reason = "ATR unavailable at impulse edge";
      return r;
     }

   // Bullish impulse -> look for equal LOWS in the pullback (resting
   // sell-side liquidity that a stop-hunt would sweep before continuing
   // up). Bearish impulse -> equal HIGHS.
   double poolPrice; int nearIdx, farIdx;
   bool structureFound = FindEqualPair(forBuy /*wantLows*/, 0, pullbackTo, atr, poolPrice, nearIdx, farIdx);
   r.internalStructureFound = structureFound;
   r.structureScore = structureFound ? 10.0 : 0.0;
   if(!structureFound)
     {
      r.reason = "Impulse found, but no internal equal-highs/lows structure formed in the pullback";
      return r;
     }

   // Sweep: scan from the more-recent equal swing forward to now (index 0)
   // for a bar that wicks beyond the pool and closes back inside it.
   bool sweepFound = false;
   double sweepStrength = 0.0;
   int sweepBarIdx = -1;
   for(int i = nearIdx - 1; i >= 0; i--)
     {
      CandleData cd = m_candles.GetCandle(i);
      double barATR = m_candles.GetATR(i);
      if(barATR <= 0) continue;
      if(forBuy)
        {
         if(cd.low < poolPrice && cd.close > poolPrice)
           {
            sweepFound = true;
            sweepStrength = MathMax(0.0, MathMin(((poolPrice - cd.low) / barATR) / 0.5, 1.0));
            sweepBarIdx = i;
            break;
           }
        }
      else
        {
         if(cd.high > poolPrice && cd.close < poolPrice)
           {
            sweepFound = true;
            sweepStrength = MathMax(0.0, MathMin(((cd.high - poolPrice) / barATR) / 0.5, 1.0));
            sweepBarIdx = i;
            break;
           }
        }
     }
   r.sweepFound = sweepFound;
   r.sweepBarIndex = sweepBarIdx;
   r.sweepPoolPrice = poolPrice;
   r.sweepScore = sweepFound ? 25.0 : 0.0;
   if(!sweepFound)
     {
      r.reason = "Internal structure present, but liquidity was never swept — no inducement, no trade";
      return r;
     }

   // v2.9: grade the sweep instead of treating every sweepFound=true the
   // same way. Gate is OFF by default (see ConfigureQualityGates()); the
   // grade/score are always computed so the dashboard can show them even
   // when the gate isn't enforcing anything yet.
   double sweepGradeScore;
   ENUM_SWEEP_GRADE sweepGrade = GradeSweep(sweepBarIdx, forBuy, poolPrice, sweepGradeScore);
   r.sweepGrade = sweepGrade;
   r.sweepGradeScore = sweepGradeScore;
   r.barsSinceSweep = sweepBarIdx;
   // Sweep quality now WEIGHTS the 25-pt sweep score instead of it being
   // flat 0-or-25 — a barely-qualifying C sweep and a decisive A sweep no
   // longer score identically just because both technically passed.
   r.sweepScore = 25.0 * MathMax(sweepGradeScore, 0.15); // floor at 0.15 so a bare pass isn't scored as ~0
   if(m_requireMinSweepGrade && (int)sweepGrade < (int)m_minSweepGrade)
     {
      r.reason = StringFormat("Sweep found but graded %s (below required minimum) — weak penetration/reclaim/follow-through",
                               sweepGrade == SWEEP_GRADE_C ? "C" : "B");
      return r;
     }

   // Confirming minor BOS: after the sweep, price must close back beyond
   // the opposing minor swing formed during the pullback (a small
   // structure break confirming the reversal continues with the impulse).
   double minorOpp = forBuy ? -DBL_MAX : DBL_MAX;
   for(int i = sweepBarIdx; i <= pullbackTo; i++)
     {
      if(!FindMinorSwing(i, forBuy)) continue; // forBuy -> looking for a minor HIGH to break above
      double p = forBuy ? m_candles.GetCandle(i).high : m_candles.GetCandle(i).low;
      if(forBuy && p > minorOpp) minorOpp = p;
      if(!forBuy && p < minorOpp) minorOpp = p;
     }
   bool bosConfirmed = false;
   int bosBarIdx = -1;
   if((forBuy && minorOpp > -DBL_MAX) || (!forBuy && minorOpp < DBL_MAX))
     {
      for(int i = sweepBarIdx - 1; i >= 0; i--)
        {
         CandleData cd = m_candles.GetCandle(i);
         if(forBuy && cd.close > minorOpp) { bosConfirmed = true; bosBarIdx = i; break; }
         if(!forBuy && cd.close < minorOpp) { bosConfirmed = true; bosBarIdx = i; break; }
        }
     }
   r.bosConfirmed = bosConfirmed;
   if(!bosConfirmed)
     {
      r.bosScore = 0.0;
      r.reason = "Liquidity swept, but no confirming minor BOS yet — wait for structure to break";
      return r;
     }

   // v2.9: continuous BOS strength replaces the flat 20-or-0 score, plus
   // time decay on how stale the confirmed setup already is.
   double bosStrength = BOSStrength(bosBarIdx, minorOpp, forBuy);
   r.bosStrength = bosStrength;
   r.bosScore = 20.0 * MathMax(bosStrength, 0.15);
   r.barsSinceBOS = bosBarIdx;
   r.bosBarIndex = bosBarIdx;
   r.bosClosePrice = m_candles.GetCandle(bosBarIdx).close;
   double timeDecay = TimeDecay(bosBarIdx);
   r.timeDecay = timeDecay;
   if(m_requireFreshSetup && timeDecay <= 0.0)
     {
      r.reason = StringFormat("Sweep/BOS confirmed but setup is stale (%d bars since BOS, max %d)",
                               bosBarIdx, m_maxBarsSinceBOS);
      return r;
     }

   r.valid = true;
   r.leg = leg;
   r.totalScore = (r.impulseScore + r.structureScore + r.sweepScore + r.bosScore) * MathMax(timeDecay, 0.15);
   r.reason = StringFormat("Inducement sequence confirmed: impulse -> pullback structure -> %s sweep -> BOS (strength %.0f%%, decay %.0f%%)",
                            sweepGrade == SWEEP_GRADE_A ? "A-grade" : sweepGrade == SWEEP_GRADE_B ? "B-grade" : "C-grade",
                            bosStrength * 100.0, timeDecay * 100.0);
   return r;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/Inducement.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/PremiumDiscount.mqh
//+------------------------------------------------------------------+
//|                                      SmartMoney/PremiumDiscount.mqh |
//+------------------------------------------------------------------+
#ifndef PREMIUMDISCOUNT_MQH
#define PREMIUMDISCOUNT_MQH

// already inlined once under include guard: includes/Core/Config.mqh

// Static helper — no state, so no Init()/instance needed. Equilibrium is
// just the midpoint of a range; buys should only trigger below it
// (discount), sells only above it (premium). Deliberately takes a plain
// (high, low) pair rather than owning its own range source, so callers
// can feed it the impulse range (as the spec asks for), a swing range, or
// anything else without this file needing to know about ImpulseLeg.
class CPremiumDiscount
  {
public:
   static double     Equilibrium(double rangeHigh, double rangeLow) { return (rangeHigh + rangeLow) / 2.0; }
   static bool       IsDiscount(double price, double rangeHigh, double rangeLow)
     {
      if(rangeHigh <= rangeLow) return false;
      return price < Equilibrium(rangeHigh, rangeLow);
     }
   static bool       IsPremium(double price, double rangeHigh, double rangeLow)
     {
      if(rangeHigh <= rangeLow) return false;
      return price > Equilibrium(rangeHigh, rangeLow);
     }
   // Convenience wrapper for the impulse-range use case specifically.
   // LOCATION filter (see gate convention, Core/Config.mqh) — fails open
   // on purpose: with no range there's no "wrong side" to be on.
   static bool       OK(bool forBuy, double price, const ImpulseLeg &leg)
     {
      if(!leg.valid) return true; // no range to check against — don't block on missing data
      double hi = MathMax(leg.start_price, leg.end_price);
      double lo = MathMin(leg.start_price, leg.end_price);
      return forBuy ? IsDiscount(price, hi, lo) : IsPremium(price, hi, lo);
     }
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/PremiumDiscount.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/MarketPhase.mqh
//+------------------------------------------------------------------+
//|                                         SmartMoney/MarketPhase.mqh |
//+------------------------------------------------------------------+
#ifndef MARKETPHASE_MQH
#define MARKETPHASE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/SmartMoney/Liquidity.mqh

// HONEST CAVEAT: this is the least rigorously-defined concept in the
// v2.1 upgrade — "accumulation / manipulation / distribution" is a
// narrative description, not something with a single agreed-upon
// technical definition the way BOS or an FVG is. What follows is a
// reasonable, ATR-relative heuristic (range compression -> recent sweep
// -> recent displacement), not a claim that it detects "institutional
// intent". Treat it as a supplementary filter, not a ground truth signal
// — that's why it ships as an optional gate (default OFF) rather than a
// hard requirement like the Inducement engine's sweep+BOS check.
class CMarketPhase
  {
private:
   CCandleData*      m_candles;
   CLiquidity*       m_liquidity;
   int               m_rangeLookback;
   double            m_compressionATRMult;
   int               m_sweepRecencyBars;
   double            m_displacementATRMult;

   bool              IsDisplacementBar(int idx);

public:
                     CMarketPhase();
   void              Init(CCandleData* candles, CLiquidity* liquidity, int rangeLookback = 20,
                          double compressionATRMult = 2.5, int sweepRecencyBars = 6,
                          double displacementATRMult = 1.2);
   ENUM_MARKET_PHASE Detect();
  };
//+------------------------------------------------------------------+
CMarketPhase::CMarketPhase() : m_candles(NULL), m_liquidity(NULL), m_rangeLookback(20),
                                m_compressionATRMult(2.5), m_sweepRecencyBars(6), m_displacementATRMult(1.2) {}
//+------------------------------------------------------------------+
void CMarketPhase::Init(CCandleData* candles, CLiquidity* liquidity, int rangeLookback,
                        double compressionATRMult, int sweepRecencyBars, double displacementATRMult)
  {
   m_candles = candles;
   m_liquidity = liquidity;
   m_rangeLookback = MathMax(5, rangeLookback);
   m_compressionATRMult = compressionATRMult;
   m_sweepRecencyBars = MathMax(1, sweepRecencyBars);
   m_displacementATRMult = displacementATRMult;
  }
//+------------------------------------------------------------------+
bool CMarketPhase::IsDisplacementBar(int idx)
  {
   if(m_candles == NULL) return false;
   CandleData cd = m_candles.GetCandle(idx);
   double atr = m_candles.GetATR(idx);
   if(atr <= 0) return false;
   double range = cd.high - cd.low;
   if(range <= 0) return false;
   double body = MathAbs(cd.close - cd.open);
   return (range / atr >= m_displacementATRMult) && (body / range >= 0.5);
  }
//+------------------------------------------------------------------+
ENUM_MARKET_PHASE CMarketPhase::Detect()
  {
   if(m_candles == NULL || m_candles.Total() < m_rangeLookback + 2) return PHASE_UNDEFINED;
   double atr = m_candles.GetATR(0);
   if(atr <= 0) return PHASE_UNDEFINED;

   double hh = -DBL_MAX, ll = DBL_MAX;
   for(int i = 0; i < m_rangeLookback; i++)
     {
      CandleData cd = m_candles.GetCandle(i);
      if(cd.high > hh) hh = cd.high;
      if(cd.low  < ll) ll = cd.low;
     }
   bool compressed = ((hh - ll) / atr) <= m_compressionATRMult;

   bool recentSweep = false;
   if(m_liquidity != NULL && m_liquidity.EventCount() > 0)
     {
      LiquidityEvent ev = m_liquidity.GetEvent(0);
      if(ev.bar_index <= m_sweepRecencyBars) recentSweep = true;
     }

   bool recentDisplacement = false;
   for(int i = 0; i < MathMin(3, m_sweepRecencyBars); i++)
      if(IsDisplacementBar(i)) { recentDisplacement = true; break; }

   if(recentSweep && recentDisplacement) return PHASE_DISTRIBUTION;
   if(recentSweep) return PHASE_MANIPULATION;
   if(compressed) return PHASE_ACCUMULATION;
   return PHASE_UNDEFINED;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/MarketPhase.mqh
// already inlined once under include guard: includes/SmartMoney/OrderBlock.mqh
// BEGIN INLINED MODULE: includes/Analysis/VolatilityRegime.mqh
//+------------------------------------------------------------------+
//|                                     Analysis/VolatilityRegime.mqh |
//+------------------------------------------------------------------+
#ifndef VOLATILITYREGIME_MQH
#define VOLATILITYREGIME_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh

// v2.8 addition. CMarketPhase already answers "is price compressed into a
// range right now" (binary, range/ATR vs one threshold). This answers a
// different question: "is the CURRENT bar's ATR itself unusually low or
// high relative to its own recent history" — independent of whether price
// is trending or ranging. A trending market can still be in a low-vol
// grind (thin follow-through, bad R:R) or a high-vol expansion (news-leg,
// needs a wider stop than the static 1.5xATR default). Percentile-based,
// not a fixed multiple, so it self-calibrates per symbol/timeframe
// instead of needing a magic constant re-tuned per instrument.
class CVolatilityRegime
  {
private:
   CCandleData*      m_candles;
   int                m_lookback;
   double             m_lowPct;     // e.g. 0.25 -> bottom quartile = LOW
   double             m_highPct;    // e.g. 0.75 -> top quartile = HIGH

public:
                     CVolatilityRegime();
   void              Init(CCandleData* candleData, int lookback = 100, double lowPct = 0.25, double highPct = 0.75);
   ENUM_VOL_REGIME    Classify(int shift = 0);
   double             CurrentATRPercentile(int shift = 0); // 0..1, for diagnostics/CSV
  };
//+------------------------------------------------------------------+
CVolatilityRegime::CVolatilityRegime() : m_candles(NULL), m_lookback(100), m_lowPct(0.25), m_highPct(0.75) {}
//+------------------------------------------------------------------+
void CVolatilityRegime::Init(CCandleData* candleData, int lookback, double lowPct, double highPct)
  {
   m_candles = candleData;
   m_lookback = MathMax(20, lookback);
   m_lowPct = lowPct;
   m_highPct = highPct;
  }
//+------------------------------------------------------------------+
double CVolatilityRegime::CurrentATRPercentile(int shift)
  {
   if(m_candles == NULL) return -1.0;
   int total = m_candles.Total();
   if(total < 10) return -1.0;
   double current = m_candles.GetCandle(shift).atr;
   if(current <= 0) return -1.0;

   int n = MathMin(m_lookback, total - shift);
   if(n < 10) return -1.0;

   int below = 0;
   int counted = 0;
   for(int i = shift; i < shift + n; i++)
     {
      double a = m_candles.GetCandle(i).atr;
      if(a <= 0) continue;
      counted++;
      if(a <= current) below++;
     }
   if(counted < 10) return -1.0;
   return (double)below / (double)counted;
  }
//+------------------------------------------------------------------+
ENUM_VOL_REGIME CVolatilityRegime::Classify(int shift)
  {
   double pct = CurrentATRPercentile(shift);
   if(pct < 0) return VOL_REGIME_UNDEFINED;   // fail-closed: unverifiable claim, see Config.mqh gate convention
   if(pct <= m_lowPct) return VOL_REGIME_LOW;
   if(pct >= m_highPct) return VOL_REGIME_HIGH;
   return VOL_REGIME_NORMAL;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Analysis/VolatilityRegime.mqh
// already inlined once under include guard: includes/Core/SessionFilter.mqh
// BEGIN INLINED MODULE: includes/Core/PipCalculator.mqh
//+------------------------------------------------------------------+
//|                                          Core/PipCalculator.mqh   |
//+------------------------------------------------------------------+
#ifndef PIPCALCULATOR_MQH
#define PIPCALCULATOR_MQH

// v2.9 addition. Scoring.mqh already computed this correctly (from
// SYMBOL_DIGITS/SYMBOL_POINT, not a hardcoded 0.0001) — this doesn't fix
// a live bug, it centralizes the ONE place that logic lives so every new
// consumer (Telegram payload pip display, dashboard, future risk
// tooling) uses the same definition instead of each re-deriving it and
// risking divergence on JPY pairs / gold / indices / 3-5 digit brokers.
//
// Convention: a "pip" is the traditional 4th decimal for most FX pairs
// (2nd for JPY pairs) — i.e. point*10 on a 5-digit broker, point*10 on a
// 3-digit JPY broker, and point*1 on a classic 4-digit broker. This
// matches MetaTrader's own informal pip convention, NOT SYMBOL_POINT
// directly (which is one price increment, not one pip, on 5/3-digit
// brokers). For gold/indices there's no universal "pip" — PipSize()
// still returns something scaled off SYMBOL_POINT/DIGITS, but treat the
// *_Points() variants as the reliable ones for those symbols; Pips() on
// XAUUSD is informational, not a market-standard unit.
class CPipCalculator
  {
public:
   static double     PipSize(string symbol)
     {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0) return 0.0001; // defensive fallback only — should never trigger on a valid symbol
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
     }
   static double     PointSize(string symbol)
     {
      return SymbolInfoDouble(symbol, SYMBOL_POINT);
     }
   // Price distance -> pips (rounded to 1 decimal for display; callers
   // needing raw precision should divide by PipSize() themselves).
   static double     Pips(string symbol, double priceDistance)
     {
      double pip = PipSize(symbol);
      if(pip <= 0) return 0.0;
      return MathAbs(priceDistance) / pip;
     }
   static double     Points(string symbol, double priceDistance)
     {
      double pt = PointSize(symbol);
      if(pt <= 0) return 0.0;
      return MathAbs(priceDistance) / pt;
     }
   // Monetary value of one pip for `lots` lots on `symbol`. Uses
   // SYMBOL_TRADE_TICK_VALUE/TICK_SIZE so it's correct for FX, metals,
   // and indices alike, not just a "$10/pip/lot" FX assumption.
   static double     PipValue(string symbol, double lots)
     {
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0) return 0.0;
      double pip = PipSize(symbol);
      return (pip / tickSize) * tickValue * lots;
     }
   // Convenience formatter for signal cards / logs: "87 pips / 870 pts"
   // per the review's debugging recommendation (item #2 of the pips
   // batch) — showing both makes broker-digit mismatches visible instead
   // of silently wrong.
   static string     FormatDistance(string symbol, double priceDistance)
     {
      return StringFormat("%.1f pips / %.0f pts", Pips(symbol, priceDistance), Points(symbol, priceDistance));
     }
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Core/PipCalculator.mqh
// BEGIN INLINED MODULE: includes/Regime/RegimeDetector.mqh
//+------------------------------------------------------------------+
//|                                       Regime/RegimeDetector.mqh   |
//+------------------------------------------------------------------+
#ifndef REGIMEDETECTOR_MQH
#define REGIMEDETECTOR_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Analysis/TrendEngine.mqh
// already inlined once under include guard: includes/Analysis/VolatilityRegime.mqh
// already inlined once under include guard: includes/SmartMoney/MarketPhase.mqh

// v2.12 addition. Everything downstream in the multi-strategy design
// (Momentum/Breakout vs Mean Reversion vs Key-Level Price Action) is
// supposed to branch off "what kind of market is this", so this is
// built first, and deliberately reuses the three reads that already
// exist rather than inventing a fourth "is this trending" heuristic:
//   - CTrendEngine.GetCurrentTrend()   -> BOS-backed swing structure
//   - CVolatilityRegime.Classify()     -> ATR-percentile expansion/compression
//   - CMarketPhase.Detect()            -> range-compression + sweep/displacement read
//
// THE HONEST LIMIT: CMarketPhase's own header already flags itself as
// "the least rigorously-defined concept" in this codebase — a narrative
// heuristic, not a proven detector. This class inherits that limit
// rather than hiding it: REGIME_TRANSITION is deliberately the catch-all
// for everything that isn't a clean TRENDING or RANGING read, instead of
// forcing every bar into one of two buckets a weak signal can't actually
// support.
//
// DIAGNOSTIC ONLY. Nothing reads Classify()'s return value except
// CSV logging (see SetupReasons.regime in Core/Config.mqh) and, later,
// the strategy-selection engine this doc argues for — which does not
// exist yet. No entry filter, confidence calculation, or order path
// consults this today.
class CRegimeDetector
  {
private:
   CTrendEngine*        m_trend;
   CVolatilityRegime*   m_volRegime;
   CMarketPhase*        m_phase;

public:
                        CRegimeDetector() : m_trend(NULL), m_volRegime(NULL), m_phase(NULL) {}
   void                 Init(CTrendEngine* trend, CVolatilityRegime* volRegime, CMarketPhase* phase)
     {
      m_trend = trend;
      m_volRegime = volRegime;
      m_phase = phase;
     }
   ENUM_MARKET_REGIME   Classify();
  };
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CRegimeDetector::Classify()
  {
   if(m_trend == NULL || m_volRegime == NULL || m_phase == NULL)
      return REGIME_UNDEFINED;

   ENUM_TREND_STATE  trend = m_trend.GetCurrentTrend();
   ENUM_VOL_REGIME   vol   = m_volRegime.Classify(0);
   ENUM_MARKET_PHASE phase = m_phase.Detect();

   // Fail closed on an unverifiable volatility read, same convention as
   // every other percentile-based gate in this codebase (see
   // CVolatilityRegime::Classify's own comment).
   if(vol == VOL_REGIME_UNDEFINED)
      return REGIME_UNDEFINED;

   bool strongTrend = (trend == TREND_BULL_STRONG || trend == TREND_BEAR_STRONG);
   bool weakTrend    = (trend == TREND_BULL || trend == TREND_BEAR);

   // TRENDING: BOS-confirmed directional structure, and volatility is not
   // in a thin/choppy low-vol grind (LOW regime specifically flagged
   // elsewhere in this codebase as "thin, choppy, spread-risk-heavy" —
   // exactly the condition that makes a "trend" unreliable to trade).
   if(strongTrend && vol != VOL_REGIME_LOW)
      return REGIME_TRENDING;

   // RANGING: no directional structure at all, AND price is compressed
   // into a range with no recent sweep/displacement contaminating the
   // read (ACCUMULATION is CMarketPhase's own name for exactly this).
   if(trend == TREND_NEUTRAL && phase == PHASE_ACCUMULATION)
      return REGIME_RANGING;

   // Everything else is TRANSITION by construction: a weak/unconfirmed
   // trend, a strong trend fighting low volatility, a recent sweep or
   // displacement (MANIPULATION/DISTRIBUTION) that hasn't resolved into
   // either a clean trend or a clean range yet, or PHASE_UNDEFINED with
   // no compression to fall back on. This is not "figured it out and
   // it's ambiguous" — it's "the available reads don't support a
   // stronger claim", which is the same fail-closed posture the rest of
   // this class takes on VOL_REGIME_UNDEFINED above.
   return REGIME_TRANSITION;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Regime/RegimeDetector.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/SMCStructuralValidator.mqh
//+------------------------------------------------------------------+
//| SmartMoney/SMCStructuralValidator.mqh                           |
//+------------------------------------------------------------------+
#ifndef SMC_STRUCTURAL_VALIDATOR_MQH
#define SMC_STRUCTURAL_VALIDATOR_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Analysis/TFContext.mqh

// Diagnostic structural validator for the SMC chain.
//
// It does NOT modify confidence, strategy selection, risk, or execution.
// Its job is to make the causal structure measurable so backtests can
// compare structurally-valid and structurally-invalid SMC outcomes before
// any hard gate is promoted.
//
// Chain represented here:
//   trend/HTF structure -> liquidity target -> sweep -> displacement/BOS
//   -> causal entry origin (FVG or local OB) -> premium/discount
//   -> freshness -> structural invalidation.
//
// "HTF OB" is deliberately telemetry-only. A nearby HTF OB is context, not
// proof that the entry-timeframe structure is valid.

class CSMCStructuralValidator
  {
private:
   CTFContext* m_trendCtx;
   CTFContext* m_fvgCtx;
   CTFContext* m_htfObCtx;
   double       m_fvgMaxDistATR;
   double       m_obDistATRMax;

   bool FindCausalFVG(bool forBuy, int sweepBarIndex, int bosBarIndex, double price, int &barIndex);
   bool FindCausalOrderBlock(bool forBuy, int sweepBarIndex, int bosBarIndex, double price, int &barIndex);

public:
   CSMCStructuralValidator();
   void Init(CTFContext* trendCtx, CTFContext* fvgCtx, CTFContext* htfObCtx);
   void Configure(double fvgMaxDistATR = 1.25, double obDistATRMax = 2.0);
   SMCStructuralValidation Validate(bool forBuy, const InducementResult &ind,
                                     double price, ENUM_MARKET_REGIME regime,
                                     bool premiumDiscountValid);
  };

//+------------------------------------------------------------------+
CSMCStructuralValidator::CSMCStructuralValidator()
  : m_trendCtx(NULL), m_fvgCtx(NULL), m_htfObCtx(NULL),
    m_fvgMaxDistATR(1.25), m_obDistATRMax(2.0)
  {
  }

//+------------------------------------------------------------------+
void CSMCStructuralValidator::Init(CTFContext* trendCtx, CTFContext* fvgCtx,
                                    CTFContext* htfObCtx)
  {
   m_trendCtx = trendCtx;
   m_fvgCtx = fvgCtx;
   m_htfObCtx = htfObCtx;
  }

//+------------------------------------------------------------------+
void CSMCStructuralValidator::Configure(double fvgMaxDistATR, double obDistATRMax)
  {
   m_fvgMaxDistATR = (fvgMaxDistATR > 0.0) ? fvgMaxDistATR : 1.25;
   m_obDistATRMax = (obDistATRMax > 0.0) ? obDistATRMax : 2.0;
  }

//+------------------------------------------------------------------+
// Entry-origin causality is intentionally time-directional:
// a qualifying FVG must be at the BOS bar or newer (smaller series
// index), never older than the confirming BOS. Shift 0 is excluded because
// the current candle is still forming when the EA evaluates a new bar.
bool CSMCStructuralValidator::FindCausalFVG(bool forBuy, int sweepBarIndex, int bosBarIndex,
                                             double price, int &barIndex)
  {
   barIndex = -1;
   if(m_fvgCtx == NULL || sweepBarIndex <= 0 || bosBarIndex <= 0 || sweepBarIndex < bosBarIndex || price <= 0.0) return false;
   double atr = m_fvgCtx.candles.GetATR(1);
   if(atr <= 0.0) return false;

   ENUM_FVG_DIR wantDir = forBuy ? FVG_BULL : FVG_BEAR;
   double bestScore = -1.0;

   for(int i = 0; i < m_fvgCtx.fvg.Count(); i++)
     {
      FVGZone z = m_fvgCtx.fvg.GetZone(i);
      if(z.dir != wantDir) continue;
      if(z.state != FVG_FRESH && z.state != FVG_TESTED) continue;
      if(z.bar_index <= 0 || z.bar_index > sweepBarIndex || z.bar_index < bosBarIndex) continue;

      double mid = (z.top + z.bottom) / 2.0;
      double distATR = MathAbs(price - mid) / atr;
      if(distATR > m_fvgMaxDistATR) continue;

      double base = (z.state == FVG_FRESH) ? 1.0 : 0.6;
      double proximity = MathMax(0.0, 1.0 - distATR / m_fvgMaxDistATR);
      double score = base * (0.5 + 0.5 * proximity);
      if(score > bestScore)
        {
         bestScore = score;
         barIndex = z.bar_index;
        }
     }

   return barIndex > 0;
  }

//+------------------------------------------------------------------+
// A local/entry-timeframe OB is causal only when its originating candle
// is no older than the confirming BOS and the zone comes from the same
// timeframe as the entry FVG. The chart-TF SR context is deliberately not
// used for causal provenance; HTF OB is handled separately below.
bool CSMCStructuralValidator::FindCausalOrderBlock(bool forBuy, int sweepBarIndex, int bosBarIndex,
                                                    double price, int &barIndex)
  {
   barIndex = -1;
   // Causal/local OB provenance must come from the same timeframe as the
   // entry FVG. the chart-TF SR context may differ from m_fvgCtx;
   // using it here would mislabel a cross-timeframe zone as entry-causal.
   if(m_fvgCtx == NULL || sweepBarIndex <= 0 || bosBarIndex <= 0 || sweepBarIndex < bosBarIndex || price <= 0.0) return false;

   // Use a closed entry-TF bar for the distance normalization so the
   // diagnostic dataset does not depend on the still-forming bar's ATR.
   double atr = m_fvgCtx.candles.GetATR(1);
   if(atr <= 0.0) return false;

   ENUM_FVG_DIR wantDir = forBuy ? FVG_BULL : FVG_BEAR;
   double bestDist = DBL_MAX;

   for(int i = 0; i < m_fvgCtx.orderBlock.Count(); i++)
     {
      OrderBlockZone z = m_fvgCtx.orderBlock.GetZone(i);
      if(z.dir != wantDir || z.state == OB_MITIGATED) continue;
      if(z.bar_index <= 0 || z.bar_index > sweepBarIndex || z.bar_index < bosBarIndex) continue;

      double mid = (z.top + z.bottom) / 2.0;
      double distATR = MathAbs(price - mid) / atr;
      if(distATR > m_obDistATRMax) continue;
      if(distATR < bestDist)
        {
         bestDist = distATR;
         barIndex = z.bar_index;
        }
     }

   return barIndex > 0;
  }

//+------------------------------------------------------------------+
SMCStructuralValidation CSMCStructuralValidator::Validate(
   bool forBuy, const InducementResult &ind, double price,
   ENUM_MARKET_REGIME regime, bool premiumDiscountValid)
  {
   SMCStructuralValidation v;
   ZeroMemory(v);
   v.state = SMC_WAIT;
   v.sweep_bar_index = ind.sweepBarIndex;
   v.bos_bar_index = ind.bosBarIndex;
   v.displacement_bar_index = ind.displacementBarIndex;
   v.entry_fvg_bar_index = -1;
   v.causal_ob_bar_index = -1;
   v.premium_discount_valid = premiumDiscountValid;

   // Market state is applicability context, not a confidence bonus.
   v.regime_applicable = (regime != REGIME_UNDEFINED);

   // Treat the trend context as HTF only when it is actually slower
   // than the entry/FVG context. A parameter called "TrendTF" is not enough
   // proof by itself; the validator verifies the timeframe relationship.
   bool genuineHtf = (m_trendCtx != NULL && m_fvgCtx != NULL &&
                      PeriodSeconds(m_trendCtx.tf) > PeriodSeconds(m_fvgCtx.tf));
   if(genuineHtf)
     {
      ENUM_TREND_STATE trend = m_trendCtx.trend.GetCurrentTrend();
      v.htf_structure_valid = forBuy
                              ? (trend == TREND_BULL || trend == TREND_BULL_STRONG)
                              : (trend == TREND_BEAR || trend == TREND_BEAR_STRONG);
     }
   else
     {
      v.htf_structure_valid = false;
     }

   v.liquidity_target_valid = ind.internalStructureFound && ind.sweepFound;
   v.sweep_valid = ind.sweepFound;
   v.displacement_valid = ind.impulseFound && ind.leg.valid && ind.displacementBarIndex > ind.sweepBarIndex && ind.sweepBarIndex > ind.bosBarIndex && ind.bosBarIndex > 0;
   v.bos_valid = ind.bosConfirmed && ind.sweepBarIndex > ind.bosBarIndex && ind.bosBarIndex > 0;
   v.freshness_valid = (ind.timeDecay > 0.0);

   // Structural invalidation uses the protected extreme of the impulse leg.
   // Crossing it means the causal thesis that created the setup is no longer
   // intact, regardless of confidence.
   v.protected_level = ind.leg.start_price;
   v.invalidation_level = ind.leg.start_price;
   v.invalidation_clear = true;
   if(ind.leg.valid && price > 0.0)
      v.invalidation_clear = forBuy ? (price > v.invalidation_level)
                                    : (price < v.invalidation_level);

   if(ind.bosConfirmed && v.displacement_valid && price > 0.0)
     {
      v.fvg_causal = FindCausalFVG(forBuy, ind.sweepBarIndex, ind.bosBarIndex, price, v.entry_fvg_bar_index);
      v.order_block_causal = FindCausalOrderBlock(forBuy, ind.sweepBarIndex, ind.bosBarIndex, price, v.causal_ob_bar_index);
     }

   if(m_htfObCtx != NULL && price > 0.0)
     {
      double atr = m_htfObCtx.candles.GetATR(1);
      if(atr > 0.0)
        {
         OrderBlockZone z;
         if(m_htfObCtx.orderBlock.NearestZone(forBuy ? FVG_BULL : FVG_BEAR,
                                               price, atr, m_obDistATRMax, z))
            v.htf_ob_present = (z.state == OB_FRESH || z.state == OB_TESTED);
        }
     }

   if(!v.displacement_valid || !ind.internalStructureFound || !v.sweep_valid || !v.bos_valid)
     {
      v.state = SMC_WAIT;
      v.failure_reason = ind.reason;
      return v;
     }

   if(!v.invalidation_clear)
     {
      v.state = SMC_INVALIDATED;
      v.failure_reason = "Structural invalidation level breached";
      return v;
     }

   if(!v.freshness_valid)
     {
      v.state = SMC_STALE;
      v.failure_reason = "BOS/sweep chain is stale";
      return v;
     }

   if(!v.regime_applicable)
     {
      v.state = SMC_WAIT;
      v.failure_reason = "Market regime undefined";
      return v;
     }

   if(!v.htf_structure_valid)
     {
      v.state = SMC_INVALID;
      v.failure_reason = genuineHtf ? (forBuy ? "HTF structure is not bullish" : "HTF structure is not bearish") : "Trend context is not a genuine higher timeframe";
      return v;
     }

   if(!v.premium_discount_valid)
     {
      v.state = SMC_INVALID;
      v.failure_reason = forBuy ? "BUY is outside validated discount location"
                                : "SELL is outside validated premium location";
      return v;
     }

   if(!v.fvg_causal && !v.order_block_causal)
     {
      v.state = SMC_WAIT;
      v.failure_reason = "No causal entry FVG or order block linked to the confirming BOS";
      return v;
     }

   v.structural_valid = true;
   v.state = SMC_VALID;
   v.failure_reason = "Structural SMC chain validated";
   return v;
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/SMCStructuralValidator.mqh
// BEGIN INLINED MODULE: includes/Strategies/MomentumBreakout.mqh
//+------------------------------------------------------------------+
//|                                 Strategies/MomentumBreakout.mqh   |
//+------------------------------------------------------------------+
#ifndef MOMENTUMBREAKOUT_MQH
#define MOMENTUMBREAKOUT_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Structure/BOS.mqh
// already inlined once under include guard: includes/SmartMoney/Liquidity.mqh
// already inlined once under include guard: includes/Analysis/VolatilityRegime.mqh

// v2.12 addition. Strategy module #1 of the multi-strategy architecture
// (see docs/CHANGELOG.md v2.12 entry) — Mean Reversion and the Key-Level
// Price Action engine are next, not built yet. Deliberately reuses
// existing primitives instead of reimplementing them:
//   - CBOS already stores BOSEvent.strength (0-1, displacement/ATR +
//     volume ratio composite) and BOSEvent.bar_index (recency) per
//     event — that IS the "genuine displacement? volume abnormal?"
//     read the spec asked for, computed once by CBOS::Detect() and
//     reused here rather than recomputed.
//   - CLiquidity's own event list is reused to detect the overlap case
//     ("liquidity breakout... interesting because it overlaps with your
//     SMC engine") rather than guessing at a second sweep detector.
//
// CLASSIFICATION (BREAKOUT_*, see Core/Config.mqh for definitions):
//   FAILED     : checked first — price already closed back on the wrong
//                side of the broken level. Whatever else was true about
//                the break, it didn't hold, so this overrides every
//                other label.
//   LIQUIDITY  : the BOS bar coincides (within m_liqOverlapBars) with a
//                liquidity-sweep event. Checked before EXPANSION/
//                EXHAUSTION because a sweep-driven break and a pure
//                displacement break are different setups even when the
//                raw strength score looks similar.
//   EXHAUSTION : price was already extended (pre-break run measured over
//                m_extensionLookbackBars, in ATR) beyond m_exhaustionATR
//                BEFORE the break bar — a strong strength score here is
//                the doc's warning case ("do not chase"), not a green
//                light.
//   EXPANSION  : none of the above — fresh, displacement-and-volume-
//                backed, not already extended, not sweep-driven.
//   NONE       : no BOS in the setup direction within m_recencyBars.
//
// MOMENTUM SCORE is a separate, simpler read from BREAKOUT SCORE: net
// directional close-to-close movement over m_momentumLookbackBars,
// scaled by that window's own average ATR. This is a plain rate-of-
// change-over-volatility heuristic, not a proprietary momentum
// indicator — stated plainly per this codebase's convention of not
// overclaiming what a heuristic proves (see MarketPhase.mqh's own
// caveat for the precedent).
//
// DIAGNOSTIC ONLY. See Regime/RegimeDetector.mqh's header for the same
// disclosure: nothing here feeds CalculateConfidence(), CDecisionEngine,
// or order sizing. Read only by CSV logging today.
class CMomentumBreakoutEngine
  {
private:
   CCandleData*         m_candles;
   CBOS*                m_bos;
   CLiquidity*          m_liquidity;
   CVolatilityRegime*   m_volRegime;

   int                  m_recencyBars;            // how far back a BOS still counts as "recent" (default 10)
   int                  m_liqOverlapBars;          // BOS/liquidity bar_index gap allowed to call it LIQUIDITY (default 2)
   int                  m_extensionLookbackBars;   // window checked BEFORE the break bar for pre-existing extension (default 15)
   double               m_exhaustionATRMult;       // pre-break run, in ATR, above which a break counts as EXHAUSTION (default 3.0)
   int                  m_momentumLookbackBars;    // window for the momentum score (default 10)

   bool                 FindRecentBOS(bool forBuy, BOSEvent &out);
   bool                 HasNearbyLiquidityEvent(int barIndex);
   bool                 ClosedBackAcross(const BOSEvent &ev, bool forBuy);
   double               PreBreakExtensionATR(int barIndex, bool forBuy);

public:
                        CMomentumBreakoutEngine() : m_candles(NULL), m_bos(NULL), m_liquidity(NULL), m_volRegime(NULL),
                                                     m_recencyBars(10), m_liqOverlapBars(2),
                                                     m_extensionLookbackBars(15), m_exhaustionATRMult(3.0),
                                                     m_momentumLookbackBars(10) {}
   void                 Init(CCandleData* candles, CBOS* bos, CLiquidity* liquidity, CVolatilityRegime* volRegime)
     {
      m_candles = candles;
      m_bos = bos;
      m_liquidity = liquidity;
      m_volRegime = volRegime;
     }
   // All defaults above are starting points, not tuned constants — same
   // discipline note as every other Configure*() in this codebase
   // (e.g. CScoringEngine::ConfigureLearnedDiagnostics).
   void                 Configure(int recencyBars = 10, int liqOverlapBars = 2,
                                   int extensionLookbackBars = 15, double exhaustionATRMult = 3.0,
                                   int momentumLookbackBars = 10)
     {
      m_recencyBars = MathMax(1, recencyBars);
      m_liqOverlapBars = MathMax(0, liqOverlapBars);
      m_extensionLookbackBars = MathMax(1, extensionLookbackBars);
      m_exhaustionATRMult = (exhaustionATRMult > 0) ? exhaustionATRMult : 3.0;
      m_momentumLookbackBars = MathMax(1, momentumLookbackBars);
     }

   void                 Evaluate(bool forBuy, double &momentumScore, double &breakoutScore, ENUM_BREAKOUT_CLASS &breakoutClass);
  };
//+------------------------------------------------------------------+
// Scans most-recent-first for the first BOS event whose direction
// matches forBuy and whose bar_index is within m_recencyBars. GetBOS(0)
// alone isn't enough — the single most recent BOS overall may be in the
// OPPOSITE direction to the setup being evaluated.
bool CMomentumBreakoutEngine::FindRecentBOS(bool forBuy, BOSEvent &out)
  {
   if(m_bos == NULL) return false;
   int n = m_bos.Count();
   for(int i = 0; i < n; i++)
     {
      BOSEvent ev = m_bos.GetBOS(i);
      if(ev.bar_index > m_recencyBars) break; // events are stored most-recent-first; once we're past the window, nothing later helps
      if(ev.is_bullish == forBuy)
        {
         out = ev;
         return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
bool CMomentumBreakoutEngine::HasNearbyLiquidityEvent(int barIndex)
  {
   if(m_liquidity == NULL) return false;
   int n = m_liquidity.EventCount();
   for(int i = 0; i < n; i++)
     {
      LiquidityEvent ev = m_liquidity.GetEvent(i);
      if(MathAbs(ev.bar_index - barIndex) <= m_liqOverlapBars)
         return true;
      if(ev.bar_index - barIndex > m_liqOverlapBars + m_recencyBars) break; // sorted most-recent-first; far enough away we can stop
     }
   return false;
  }
//+------------------------------------------------------------------+
// Has price, since the break, closed back on the WRONG side of the
// level that was broken? ev.price is the level; a bullish BOS failing
// means a later (more recent, lower shift) candle closed back below it.
bool CMomentumBreakoutEngine::ClosedBackAcross(const BOSEvent &ev, bool forBuy)
  {
   if(m_candles == NULL) return false;
   for(int shift = 0; shift < ev.bar_index; shift++)
     {
      CandleData cd = m_candles.GetCandle(shift);
      if(forBuy && cd.close < ev.price) return true;
      if(!forBuy && cd.close > ev.price) return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
// How far, in ATR, price had already moved in the setup's direction
// over the m_extensionLookbackBars BEFORE the break bar — i.e. was the
// move already extended before this breakout even happened.
double CMomentumBreakoutEngine::PreBreakExtensionATR(int barIndex, bool forBuy)
  {
   if(m_candles == NULL) return 0.0;
   int startShift = barIndex + 1;
   int endShift = barIndex + m_extensionLookbackBars;
   if(endShift >= m_candles.Total()) endShift = m_candles.Total() - 1;
   if(startShift >= endShift) return 0.0;

   double atr = m_candles.GetATR(barIndex);
   if(atr <= 0) return 0.0;

   CandleData startCd = m_candles.GetCandle(endShift);   // older
   CandleData endCd   = m_candles.GetCandle(startShift); // just before the break
   double move = forBuy ? (endCd.close - startCd.close) : (startCd.close - endCd.close);
   return move / atr; // negative if price moved the "wrong" way before the break — not extended
  }
//+------------------------------------------------------------------+
void CMomentumBreakoutEngine::Evaluate(bool forBuy, double &momentumScore, double &breakoutScore, ENUM_BREAKOUT_CLASS &breakoutClass)
  {
   momentumScore = 0.0;
   breakoutScore = 0.0;
   breakoutClass = BREAKOUT_NONE;

   // --- momentum score: independent of whether a BOS exists at all ---
   if(m_candles != NULL && m_candles.Total() > m_momentumLookbackBars + 1)
     {
      double sumAtr = 0.0;
      int atrCount = 0;
      for(int i = 0; i < m_momentumLookbackBars; i++)
        {
         double a = m_candles.GetATR(i);
         if(a > 0) { sumAtr += a; atrCount++; }
        }
      if(atrCount > 0)
        {
         double avgAtr = sumAtr / atrCount;
         CandleData now = m_candles.GetCandle(0);
         CandleData then = m_candles.GetCandle(m_momentumLookbackBars);
         double netMove = forBuy ? (now.close - then.close) : (then.close - now.close);
         double raw = netMove / (avgAtr * m_momentumLookbackBars * 0.35); // 0.35 = expected fraction of ATR moved per bar in a genuine trend; empirical starting point, not fit
         momentumScore = MathMax(0.0, MathMin(raw * 100.0, 100.0));
        }
     }

   // --- breakout classification: requires a recent BOS in this direction ---
   BOSEvent ev;
   if(!FindRecentBOS(forBuy, ev))
      return; // stays BREAKOUT_NONE / breakoutScore 0.0

   breakoutScore = MathMax(0.0, MathMin(ev.strength * 100.0, 100.0));

   if(ClosedBackAcross(ev, forBuy))
     {
      breakoutClass = BREAKOUT_FAILED;
      return;
     }
   if(HasNearbyLiquidityEvent(ev.bar_index))
     {
      breakoutClass = BREAKOUT_LIQUIDITY;
      return;
     }
   if(PreBreakExtensionATR(ev.bar_index, forBuy) >= m_exhaustionATRMult)
     {
      breakoutClass = BREAKOUT_EXHAUSTION;
      return;
     }
   breakoutClass = BREAKOUT_EXPANSION;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Strategies/MomentumBreakout.mqh
// BEGIN INLINED MODULE: includes/Strategies/MeanReversion.mqh
//+------------------------------------------------------------------+
//|                                    Strategies/MeanReversion.mqh   |
//+------------------------------------------------------------------+
#ifndef MEANREVERSION_MQH
#define MEANREVERSION_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/SmartMoney/SupportResistance.mqh
// already inlined once under include guard: includes/SmartMoney/ValueAreaEngine.mqh
// already inlined once under include guard: includes/SmartMoney/Liquidity.mqh
// already inlined once under include guard: includes/Structure/BOS.mqh
// already inlined once under include guard: includes/Analysis/VolatilityRegime.mqh

// v2.13 addition. Strategy module #2 of the multi-strategy architecture
// (see Strategies/MomentumBreakout.mqh for module #1 and the same
// rationale for building one module at a time). Reuses existing
// primitives rather than reimplementing them:
//   - CValueAreaEngine.VAH()/VAL()   -> "statistically stretched price"
//   - CSupportResistance zones       -> "rejection at established level"
//   - CLiquidity's event list        -> "liquidity sweep"
//   - CBOS's stored BOSEvent.strength -> "declining momentum" read,
//     inverted: a STRONG opposing BOS means momentum is NOT declining,
//     which is this module's trend-conflict override.
//
// TWO QUALIFYING PATHS, not one bar:
//   VALUE_FADE       : price stretched beyond a value-area edge by at
//                      least m_minStretchATR, AND (a rejection wick OR
//                      a confirming liquidity sweep). The stronger path
//                      — the doc's primary case.
//   LEVEL_REJECTION  : price at a plain SR zone with a rejection wick,
//                      with no value-area stretch requirement. The
//                      weaker path — still a real setup, scored lower.
//   NONE             : neither path's minimum bar (wick OR SR touch) is
//                      met at all.
//   TREND_CONFLICT   : OVERRIDES either path above. A recent BOS in the
//                      direction the stretch is already moving (i.e.
//                      AGAINST the proposed fade) with strength at or
//                      above m_trendConflictMinStrength means the move
//                      being faded is still structurally confirmed.
//                      Per the doc: "mean reversion should not fight a
//                      strong trend merely because price looks
//                      expensive." The classification changes; the
//                      underlying reversion_score is left as computed
//                      rather than zeroed, so the CSV still shows "this
//                      looked like a fade, and here's why it's flagged
//                      risky" instead of erasing the read.
//
// TIMEFRAME NOTE (same disclosure as MomentumBreakout.mqh): candles/SR/
// value-area here are the chart-TF context (m_srCtx), so ATR and price
// distance are self-consistent. The liquidity and BOS pointers this
// class takes may belong to DIFFERENT timeframes if the EA is
// configured that way (InpLiquidityTF / InpBOSTF) — the same
// cross-timeframe caveat MomentumBreakout.mqh already carries, not a
// new one introduced here.
//
// "CONTROLLED VOLATILITY": the doc lists this as a qualifying condition,
// not just a bonus. Implemented as a simple gate — VOL_REGIME_HIGH
// suppresses the score's volatility component to 0 rather than
// disqualifying the setup outright, since a single percentile read
// shouldn't unilaterally veto a setup that's otherwise well-formed;
// scoring it low still lets it show up as a weak signal in the CSV
// rather than disappearing.
//
// DIAGNOSTIC ONLY. Same as every other v2.1x addition: nothing here
// feeds CalculateConfidence(), CDecisionEngine, or order sizing.
class CMeanReversionEngine
  {
private:
   CCandleData*         m_candles;      // chart-TF (m_srCtx.candles) — same context as m_sr/m_valueArea
   CSupportResistance*  m_sr;           // chart-TF SR zones
   CValueAreaEngine*    m_valueArea;    // chart-TF POC/VAH/VAL
   CLiquidity*          m_liquidity;    // see timeframe note above
   CVolatilityRegime*   m_volRegime;    // chart-TF instance — see Analysis/Scoring.mqh wiring note (deliberately separate from the BOS-TF instance Momentum/Regime use)
   CBOS*                m_opposingBos;  // see timeframe note above

   double               m_minStretchATR;            // VA-edge stretch, in ATR, required for the VALUE_FADE path (default 1.0)
   double               m_srZoneATRTolerance;        // how close price must be to an SR zone edge, in ATR, to count as "at" it (default 0.25)
   double               m_wickRejectionRatio;        // wick length / total range required to call a candle a rejection (default 0.55)
   int                  m_liqRecencyBars;            // how far back a sweep still counts as confirmation (default 10)
   int                  m_trendConflictRecencyBars;  // how far back an opposing BOS still counts as live conflict (default 10)
   double               m_trendConflictMinStrength;  // BOSEvent.strength (0-1) threshold to call it a real conflict (default 0.5)

   bool                 HasNearbySRZone(double price, double atr, bool forBuy);
   bool                 RejectionWickPresent(bool forBuy);
   bool                 HasRecentOpposingSweep(bool forBuy);
   bool                 HasTrendConflict(bool forBuy);

public:
                        CMeanReversionEngine() : m_candles(NULL), m_sr(NULL), m_valueArea(NULL), m_liquidity(NULL),
                                                  m_volRegime(NULL), m_opposingBos(NULL),
                                                  m_minStretchATR(1.0), m_srZoneATRTolerance(0.25),
                                                  m_wickRejectionRatio(0.55), m_liqRecencyBars(10),
                                                  m_trendConflictRecencyBars(10), m_trendConflictMinStrength(0.5) {}
   void                 Init(CCandleData* candles, CSupportResistance* sr, CValueAreaEngine* valueArea,
                              CLiquidity* liquidity, CVolatilityRegime* volRegime, CBOS* opposingBos)
     {
      m_candles = candles;
      m_sr = sr;
      m_valueArea = valueArea;
      m_liquidity = liquidity;
      m_volRegime = volRegime;
      m_opposingBos = opposingBos;
     }
   // Defaults are starting points from the spec's own reasoning, not
   // tuned constants — same discipline note as every other Configure()
   // in this codebase.
   void                 Configure(double minStretchATR = 1.0, double srZoneATRTolerance = 0.25,
                                   double wickRejectionRatio = 0.55, int liqRecencyBars = 10,
                                   int trendConflictRecencyBars = 10, double trendConflictMinStrength = 0.5)
     {
      m_minStretchATR = (minStretchATR > 0) ? minStretchATR : 1.0;
      m_srZoneATRTolerance = (srZoneATRTolerance >= 0) ? srZoneATRTolerance : 0.25;
      m_wickRejectionRatio = (wickRejectionRatio > 0 && wickRejectionRatio <= 1.0) ? wickRejectionRatio : 0.55;
      m_liqRecencyBars = MathMax(0, liqRecencyBars);
      m_trendConflictRecencyBars = MathMax(0, trendConflictRecencyBars);
      m_trendConflictMinStrength = (trendConflictMinStrength >= 0 && trendConflictMinStrength <= 1.0) ? trendConflictMinStrength : 0.5;
     }

   void                 Evaluate(bool forBuy, double &reversionScore, ENUM_REVERSION_CLASS &reversionClass);
  };
//+------------------------------------------------------------------+
// forBuy -> looking for a support zone AT/BELOW price (fading a downside
// stretch, expecting a bounce up). !forBuy -> resistance zone AT/ABOVE
// price. Price sitting inside a zone counts as "at" it (distance clamped
// to 0), same convention as the ATR-tolerance checks elsewhere in this
// codebase (e.g. OBScore's distance-to-zero-at-max decay).
bool CMeanReversionEngine::HasNearbySRZone(double price, double atr, bool forBuy)
  {
   if(m_sr == NULL) return false;
   int n = m_sr.Count();
   for(int i = 0; i < n; i++)
     {
      SRZone z = m_sr.GetZone(i);
      double dist = forBuy ? (price - z.top) : (z.bottom - price);
      if(dist < 0) dist = 0.0;
      if(dist <= atr * m_srZoneATRTolerance)
         return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
// Checked on shift 1 (the last fully CLOSED bar), not shift 0 — same
// "final, not still-forming" convention Scoring.mqh's RVOL check uses
// (see FIX #16 there): a wick on the still-printing bar can still grow
// or vanish, so it isn't yet evidence of anything.
bool CMeanReversionEngine::RejectionWickPresent(bool forBuy)
  {
   if(m_candles == NULL || m_candles.Total() < 2) return false;
   CandleData cd = m_candles.GetCandle(1);
   double range = cd.high - cd.low;
   if(range <= 0) return false;
   double lowerWick = MathMin(cd.open, cd.close) - cd.low;
   double upperWick = cd.high - MathMax(cd.open, cd.close);
   return forBuy ? ((lowerWick / range) >= m_wickRejectionRatio)
                 : ((upperWick / range) >= m_wickRejectionRatio);
  }
//+------------------------------------------------------------------+
// forBuy (fading a downside stretch) wants confirmation via a SELL-SIDE
// sweep (stops taken beneath the lows before the bounce); the bearish
// mirror wants a BUY-SIDE sweep.
bool CMeanReversionEngine::HasRecentOpposingSweep(bool forBuy)
  {
   if(m_liquidity == NULL) return false;
   ENUM_LIQ_TYPE target = forBuy ? LIQ_SELL_SIDE : LIQ_BUY_SIDE;
   int n = m_liquidity.EventCount();
   for(int i = 0; i < n; i++)
     {
      LiquidityEvent ev = m_liquidity.GetEvent(i);
      if(ev.bar_index > m_liqRecencyBars) break; // most-recent-first; nothing further back helps
      if(ev.type == target && ev.swept)
         return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
// A recent BOS in the direction the stretch is ALREADY moving (i.e.
// against the proposed fade) — is_bullish == !forBuy, since forBuy fades
// a bearish move and !forBuy fades a bullish one.
bool CMeanReversionEngine::HasTrendConflict(bool forBuy)
  {
   if(m_opposingBos == NULL) return false;
   int n = m_opposingBos.Count();
   for(int i = 0; i < n; i++)
     {
      BOSEvent ev = m_opposingBos.GetBOS(i);
      if(ev.bar_index > m_trendConflictRecencyBars) break; // most-recent-first
      if(ev.is_bullish == !forBuy && ev.strength >= m_trendConflictMinStrength)
         return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
void CMeanReversionEngine::Evaluate(bool forBuy, double &reversionScore, ENUM_REVERSION_CLASS &reversionClass)
  {
   reversionScore = 0.0;
   reversionClass = REVERSION_NONE;

   if(m_candles == NULL || m_candles.Total() < 2) return;
   double price = m_candles.GetCandle(0).close; // live/current-bar proxy, same convention MomentumBreakout.mqh uses
   double atr = m_candles.GetATR(0);
   if(atr <= 0) return;

   bool wickRejection = RejectionWickPresent(forBuy);
   bool srNear = HasNearbySRZone(price, atr, forBuy);

   // Neither qualifying bar is met at all — stay NONE rather than guess.
   if(!wickRejection && !srNear)
      return;

   bool volControlled = true; // fail OPEN here deliberately: an unavailable vol read shouldn't zero out an otherwise-scored setup, unlike the hard fail-closed on ATR<=0 above where the whole score is meaningless without it
   if(m_volRegime != NULL)
      volControlled = (m_volRegime.Classify(0) != VOL_REGIME_HIGH);

   double stretchATR = 0.0;
   bool vaStretched = false;
   if(m_valueArea != NULL && m_valueArea.IsValid())
     {
      stretchATR = forBuy ? (m_valueArea.VAL() - price) / atr : (price - m_valueArea.VAH()) / atr;
      vaStretched = (stretchATR >= m_minStretchATR);
     }

   bool sweepConfirmed = HasRecentOpposingSweep(forBuy);
   double score = 0.0;

   if(vaStretched)
     {
      score += MathMin(stretchATR / 3.0, 1.0) * 40.0; // stretch component, capped at 3 ATR beyond the VA edge
      if(wickRejection)   score += 25.0;
      if(sweepConfirmed)  score += 20.0;
      if(volControlled)   score += 15.0;
      reversionClass = REVERSION_VALUE_FADE;
     }
   else if(srNear)
     {
      if(wickRejection)   score += 35.0;
      if(sweepConfirmed)  score += 25.0;
      if(volControlled)   score += 15.0;
      reversionClass = REVERSION_LEVEL_REJECTION;
     }
   else
      return; // guarded above, kept here as an explicit fail-closed rather than falling through silently

   reversionScore = MathMax(0.0, MathMin(score, 100.0));

   if(HasTrendConflict(forBuy))
      reversionClass = REVERSION_TREND_CONFLICT; // score left as-is, see file header
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Strategies/MeanReversion.mqh
// BEGIN INLINED MODULE: includes/Strategies/KeyLevelReaction.mqh
//+------------------------------------------------------------------+
//|                                 Strategies/KeyLevelReaction.mqh   |
//+------------------------------------------------------------------+
#ifndef KEYLEVELREACTION_MQH
#define KEYLEVELREACTION_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Core/SessionFilter.mqh
// already inlined once under include guard: includes/SmartMoney/SupportResistance.mqh
// already inlined once under include guard: includes/SmartMoney/ValueAreaEngine.mqh
// already inlined once under include guard: includes/SmartMoney/Liquidity.mqh
// already inlined once under include guard: includes/SmartMoney/OrderBlock.mqh
// BEGIN INLINED MODULE: includes/SmartMoney/ExtendedKeyLevels.mqh
//+------------------------------------------------------------------+
//|                                SmartMoney/ExtendedKeyLevels.mqh   |
//+------------------------------------------------------------------+
#ifndef EXTENDEDKEYLEVELS_MQH
#define EXTENDEDKEYLEVELS_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Core/SessionFilter.mqh

// v2.17 addition. The three level sources v2.14's Strategies/
// KeyLevelReaction.mqh header explicitly flagged as unwired: "None of
// the three exist anywhere in the codebase yet — building three new
// level detectors in the same pass as everything above would be
// exactly the kind of unverified sprawl this codebase's own discipline
// argues against elsewhere." This is that new code, on its own pass.
//
// Grouped in one file/class rather than three, because all three are
// the same KIND of level — a raw price extreme or a round number — not
// a structure-derived zone the way SR/OrderBlock/ValueArea/Liquidity
// are. Each method is independent; nothing here depends on the others.
//
// DIAGNOSTIC ONLY, same as every level source before it — see
// Strategies/KeyLevelReaction.mqh for what actually reads these.
class CExtendedKeyLevels
  {
private:
   string            m_symbol;
   double            m_roundStep;   // psychological-level spacing in native price units; <= 0 disables it.

   // Previous WEEK high/low — cached, recomputed only when the week
   // rolls over. iHigh/iLow(PERIOD_W1, 1) is cheap, but there's no
   // reason to call it every tick for a value that only changes once
   // every 5 trading days.
   double            m_prevWeekHigh;
   double            m_prevWeekLow;
   datetime          m_prevWeekCachedForMonday; // Monday 00:00 (broker time) of the week this cache belongs to
   bool              m_prevWeekValid;

   void              RefreshPrevWeekIfStale();

public:
                     CExtendedKeyLevels() : m_roundStep(0.0), m_prevWeekHigh(0.0), m_prevWeekLow(0.0),
                                             m_prevWeekCachedForMonday(0), m_prevWeekValid(false) {}
   void              Init(string symbol) { m_symbol = symbol; }
   // A non-positive value deliberately disables psychological levels.
   // This avoids silently imposing an XAU/FX-specific price grid on other asset classes.
   void              Configure(double roundStep = 0.0) { m_roundStep = MathMax(0.0, roundStep); }

   // Previous WEEK high/low — the most recently CLOSED weekly bar
   // (shift 1; shift 0 is the current, still-forming week). Checks BOTH
   // the high and the low as candidates and keeps whichever is nearer
   // and on the requested side — same "either one can flip role"
   // treatment FindNearestLevel() already gives SR zones (a broken
   // previous-week high can act as support just as readily as the low
   // can), not a hardcoded "low=support, high=resistance" assumption.
   bool              NearestPrevWeekLevel(bool forBuy, double price, double maxDist, double &levelPrice);
   // Current SESSION's high/low so far: scans `candles` (pass the same
   // chart-TF series every other source in KeyLevelReaction.mqh uses,
   // for the same self-consistency reason) for CLOSED bars at or after
   // the session's own start, per CSessionFilter::CurrentSessionStartGMT().
   // Returns false during SESSION_DEAD (no boundary to measure from) or
   // if no closed bar has printed since the session opened yet — a
   // session that just opened has no range to speak of, and reporting
   // one bar's high==low as a "level" would be noise, not signal.
   bool              NearestSessionLevel(bool forBuy, double price, double maxDist, double &levelPrice,
                                          CCandleData* candles, CSessionFilter* sessionFilter);
   // Nearest round-number level at m_roundStep spacing. Unlike the two
   // above, a round level's side relative to price is unambiguous by
   // construction (the one below price is the support candidate, the
   // one above is the resistance candidate) — no "check both, keep
   // nearer" needed.
   bool              NearestRoundLevel(bool forBuy, double price, double maxDist, double &levelPrice);
  };
//+------------------------------------------------------------------+
void CExtendedKeyLevels::RefreshPrevWeekIfStale()
  {
   datetime now = TimeCurrent();
   MqlDateTime t;
   TimeToStruct(now, t);
   int dow = t.day_of_week; // 0 = Sunday
   int daysSinceMonday = (dow == 0) ? 6 : (dow - 1);
   MqlDateTime mon = t;
   mon.hour = 0; mon.min = 0; mon.sec = 0;
   datetime mondayThisWeek = (datetime)(StructToTime(mon) - daysSinceMonday * 86400);

   if(m_prevWeekValid && mondayThisWeek == m_prevWeekCachedForMonday)
      return; // still the same trading week as last time this was refreshed — cache holds

   double h = iHigh(m_symbol, PERIOD_W1, 1);
   double l = iLow(m_symbol, PERIOD_W1, 1);
   if(h <= 0.0 || l <= 0.0)
     {
      // Not enough weekly history yet (fresh account, or the broker
      // hasn't backfilled W1 history). Leave the cache invalid rather
      // than store a bogus 0.0 level that would silently pass every
      // downstream distance check.
      m_prevWeekValid = false;
      return;
     }
   m_prevWeekHigh = h;
   m_prevWeekLow = l;
   m_prevWeekCachedForMonday = mondayThisWeek;
   m_prevWeekValid = true;
  }
//+------------------------------------------------------------------+
bool CExtendedKeyLevels::NearestPrevWeekLevel(bool forBuy, double price, double maxDist, double &levelPrice)
  {
   levelPrice = 0.0;
   RefreshPrevWeekIfStale();
   if(!m_prevWeekValid) return false;

   double candidates[2];
   candidates[0] = m_prevWeekHigh;
   candidates[1] = m_prevWeekLow;

   bool found = false;
   double best = maxDist;
   for(int i = 0; i < 2; i++)
     {
      double lvl = candidates[i];
      double dist = forBuy ? (price - lvl) : (lvl - price); // forBuy -> level must sit at/below price to be a support candidate
      if(dist < 0) continue;
      if(dist <= best) { best = dist; levelPrice = lvl; found = true; }
     }
   return found;
  }
//+------------------------------------------------------------------+
bool CExtendedKeyLevels::NearestSessionLevel(bool forBuy, double price, double maxDist, double &levelPrice,
                                              CCandleData* candles, CSessionFilter* sessionFilter)
  {
   levelPrice = 0.0;
   if(candles == NULL || sessionFilter == NULL) return false;

   datetime sessionStart = sessionFilter.CurrentSessionStartGMT();
   if(sessionStart == 0) return false; // SESSION_DEAD

   double sessHigh = -1.0;
   double sessLow = -1.0;
   int total = candles.Total();
   // shift 1..total-1: closed bars only, matching the "not the
   // still-forming bar" convention every other source in this pipeline
   // uses. Candles are stored newest-first (ArraySetAsSeries), so the
   // first bar older than sessionStart means everything past it belongs
   // to a prior session — safe to stop scanning right there.
   for(int s = 1; s < total; s++)
     {
      CandleData cd = candles.GetCandle(s);
      if(cd.time < sessionStart) break;
      if(sessHigh < 0.0 || cd.high > sessHigh) sessHigh = cd.high;
      if(sessLow  < 0.0 || cd.low  < sessLow)  sessLow  = cd.low;
     }
   if(sessHigh < 0.0 || sessLow < 0.0) return false; // no closed bar since the session opened yet

   double candidates[2];
   candidates[0] = sessHigh;
   candidates[1] = sessLow;

   bool found = false;
   double best = maxDist;
   for(int i = 0; i < 2; i++)
     {
      double lvl = candidates[i];
      double dist = forBuy ? (price - lvl) : (lvl - price);
      if(dist < 0) continue;
      if(dist <= best) { best = dist; levelPrice = lvl; found = true; }
     }
   return found;
  }
//+------------------------------------------------------------------+
bool CExtendedKeyLevels::NearestRoundLevel(bool forBuy, double price, double maxDist, double &levelPrice)
  {
   levelPrice = 0.0;
   if(m_roundStep <= 0.0) return false;
   if(m_roundStep <= 0.0) return false;

   double below = MathFloor(price / m_roundStep) * m_roundStep;
   double above = below + m_roundStep;
   double lvl = forBuy ? below : above; // deterministic by construction — no "check both" needed like the two sources above

   double dist = forBuy ? (price - lvl) : (lvl - price);
   if(dist < 0.0 || dist > maxDist) return false;
   levelPrice = lvl;
   return true;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/SmartMoney/ExtendedKeyLevels.mqh

// v2.14 addition. Strategy module #3 of the multi-strategy architecture
// (see MomentumBreakout.mqh for module #1 and MeanReversion.mqh for
// module #2, and the shared "one module at a time" rationale). This is
// the doc's "Key-Level Reaction Engine": identify a level, then
// classify what price actually did there as structured data, instead
// of a discretionary "bearish engulfing candle" read.
//
// LEVEL SOURCES (ENUM_KEYLEVEL_SOURCE) — reused, not reinvented:
//   LEVEL_SR             : CSupportResistance zones (swing-based, chart TF)
//   LEVEL_ORDER_BLOCK     : COrderBlock zones (chart-TF instance — see
//                          the timeframe note below for why NOT the
//                          separate genuinely-HTF instance OBScore()
//                          uses)
//   LEVEL_VALUE_AREA      : CValueAreaEngine's POC/VAH/VAL
//   LEVEL_LIQUIDITY_POOL  : CLiquidity events flagged `external` — per
//                          that struct's own comment, "external = true
//                          = D1 high/low sweep", which IS the doc's
//                          "previous day high/low" entry, reused
//                          directly rather than recomputed.
//   LEVEL_PREV_WEEK       : CExtendedKeyLevels — previous week's high/low
//                          (v2.17, see that file's header)
//   LEVEL_SESSION         : CExtendedKeyLevels — current session's
//                          high/low so far (v2.17)
//   LEVEL_PSYCHOLOGICAL   : CExtendedKeyLevels — nearest round-number
//                          level (v2.17)
// v2.17: the three sources below are now wired in — see
// SmartMoney/ExtendedKeyLevels.mqh's header for why they were held back
// from the original v2.14 pass and built as their own pass instead.
//
// Of every candidate level across the four sources above, the NEAREST
// one to current price (within m_levelSearchATRMax) is picked — no
// source-type priority weighting. "Nearest, no favorites" is a
// deliberate, simple rule, not a gap.
//
// REACTION CLASSIFICATION (ENUM_KEYLEVEL_REACTION) — examines the last
// m_lookbackBars CLOSED bars (shift 1..N) relative to the chosen
// level's price, using "hold side" (the side price approached the
// level from, matching the setup's forBuy direction) and "far side"
// (the other side) rather than absolute up/down, so one classifier
// works for a support-side read and a resistance-side read alike:
//   ACCEPTANCE   : two or more of the most recent closes are on the far
//                  side — the level has flipped role, not just been
//                  poked at.
//   BREAK        : only the single most recent close is on the far
//                  side — fresh, unconfirmed by a second close.
//   RETEST       : price broke to the far side within the lookback
//                  window, has since come back, and is now sitting at
//                  the level again without having closed back past it.
//   FAILED_BREAK : price broke to the far side within the lookback
//                  window, then closed back on the hold side — the
//                  break didn't hold.
//   REJECTION    : price touched the level (candle range include it)
//                  but closed on the hold side with a rejection wick
//                  through the level.
//   ABSORPTION   : the level was touched at least m_absorptionMinTouches
//                  times in the window with no break and no strong
//                  rejection wick — repeated testing without resolving
//                  either way.
//   NONE         : no level within range, or a level was found but none
//                  of the above patterns fit.
//
// HONEST LIMIT ON THE SCORE: unlike MomentumBreakout's/MeanReversion's
// continuously computed 0-100 scores, `reaction_score` here is a FIXED
// per-classification conviction weight, not a composite calculated from
// multiple factors. The underlying signal this module produces is
// fundamentally categorical ("what happened"), and forcing a fake
// continuous score onto it to look consistent with the other two
// modules would misrepresent what's actually being measured.
//
// TIMEFRAME NOTE: candles/SR/value-area/order-block here are all the
// CHART-TF context (m_srCtx) — self-consistent. Liquidity reuses
// whichever timeframe InpLiquidityTF is configured to, same
// cross-timeframe caveat MomentumBreakout.mqh and MeanReversion.mqh
// already carry.
//
// DIAGNOSTIC ONLY, same as every v2.1x addition before it.
class CKeyLevelEngine
  {
private:
   CCandleData*         m_candles;
   CSupportResistance*  m_sr;
   CValueAreaEngine*    m_valueArea;
   CLiquidity*          m_liquidity;
   COrderBlock*         m_orderBlock;
   CExtendedKeyLevels*  m_extLevels;    // v2.17 — prev week / session / psychological
   CSessionFilter*      m_sessionFilter; // v2.17 — needed by m_extLevels.NearestSessionLevel() only

   int                  m_lookbackBars;           // closed bars examined for the reaction pattern (default 5)
   double               m_levelSearchATRMax;       // max distance, in ATR, for a level to count as "in range" (default 3.0)
   double               m_touchToleranceATRMult;   // how close a candle's range must come to the level, in ATR, to count as a touch (default 0.15)
   int                  m_absorptionMinTouches;    // touches required, with no break/rejection, to call it ABSORPTION (default 3)
   double               m_wickRejectionRatio;      // wick/range ratio required to call a candle a rejection (default 0.55, same default as MeanReversion.mqh)

   bool                 FindNearestLevel(bool forBuy, double atr, double price, double &levelPrice, ENUM_KEYLEVEL_SOURCE &source);
   bool                 CrossedFarSide(int shift, double levelPrice, double tol, bool forBuy);
   bool                 TouchedLevel(int shift, double levelPrice, double tol);
   bool                 RejectionWickAt(int shift, double levelPrice, bool forBuy);

public:
                        CKeyLevelEngine() : m_candles(NULL), m_sr(NULL), m_valueArea(NULL), m_liquidity(NULL), m_orderBlock(NULL),
                                             m_extLevels(NULL), m_sessionFilter(NULL),
                                             m_lookbackBars(5), m_levelSearchATRMax(3.0),
                                             m_touchToleranceATRMult(0.15), m_absorptionMinTouches(3),
                                             m_wickRejectionRatio(0.55) {}
   void                 Init(CCandleData* candles, CSupportResistance* sr, CValueAreaEngine* valueArea,
                              CLiquidity* liquidity, COrderBlock* orderBlock,
                              CExtendedKeyLevels* extLevels = NULL, CSessionFilter* sessionFilter = NULL)
     {
      m_candles = candles;
      m_sr = sr;
      m_valueArea = valueArea;
      m_liquidity = liquidity;
      m_orderBlock = orderBlock;
      // v2.17: both optional (default NULL) so existing call sites that
      // haven't been updated yet keep compiling and behave exactly as
      // before — FindNearestLevel() below skips these three sources
      // entirely when m_extLevels is NULL, same NULL-guard pattern
      // every other source here already follows.
      m_extLevels = extLevels;
      m_sessionFilter = sessionFilter;
     }
   // Defaults are starting points, not tuned constants — same
   // discipline note as every other Configure() in this codebase.
   void                 Configure(int lookbackBars = 5, double levelSearchATRMax = 3.0,
                                   double touchToleranceATRMult = 0.15, int absorptionMinTouches = 3,
                                   double wickRejectionRatio = 0.55)
     {
      m_lookbackBars = MathMax(2, lookbackBars);
      m_levelSearchATRMax = (levelSearchATRMax > 0) ? levelSearchATRMax : 3.0;
      m_touchToleranceATRMult = (touchToleranceATRMult >= 0) ? touchToleranceATRMult : 0.15;
      m_absorptionMinTouches = MathMax(2, absorptionMinTouches);
      m_wickRejectionRatio = (wickRejectionRatio > 0 && wickRejectionRatio <= 1.0) ? wickRejectionRatio : 0.55;
     }

   void                 Evaluate(bool forBuy, ENUM_KEYLEVEL_SOURCE &source, ENUM_KEYLEVEL_REACTION &reaction, double &reactionScore);
  };
//+------------------------------------------------------------------+
// forBuy -> nearest level ACTING AS SUPPORT (at/below price). !forBuy ->
// nearest level ACTING AS RESISTANCE (at/above price). "Nearest, no
// source-type favorites" — see file header.
bool CKeyLevelEngine::FindNearestLevel(bool forBuy, double atr, double price, double &levelPrice, ENUM_KEYLEVEL_SOURCE &source)
  {
   double bestDist = m_levelSearchATRMax * atr;
   bool found = false;
   levelPrice = 0.0;
   source = LEVEL_NONE;

   if(m_sr != NULL)
     {
      int n = m_sr.Count();
      for(int i = 0; i < n; i++)
        {
         SRZone z = m_sr.GetZone(i);
         double lvl = forBuy ? z.top : z.bottom;
         double dist = forBuy ? (price - lvl) : (lvl - price);
         if(dist < 0) dist = 0.0;
         if(dist <= bestDist) { bestDist = dist; levelPrice = lvl; source = LEVEL_SR; found = true; }
        }
     }
   if(m_orderBlock != NULL)
     {
      int n = m_orderBlock.Count();
      for(int i = 0; i < n; i++)
        {
         OrderBlockZone z = m_orderBlock.GetZone(i);
         // Demand (FVG_BULL) acts as support -> use its top as the
         // support line facing price from below. Supply (FVG_BEAR)
         // acts as resistance -> use its bottom.
         if(forBuy && z.dir != FVG_BULL) continue;
         if(!forBuy && z.dir != FVG_BEAR) continue;
         double lvl = forBuy ? z.top : z.bottom;
         double dist = forBuy ? (price - lvl) : (lvl - price);
         if(dist < 0) dist = 0.0;
         if(dist <= bestDist) { bestDist = dist; levelPrice = lvl; source = LEVEL_ORDER_BLOCK; found = true; }
        }
     }
   if(m_valueArea != NULL && m_valueArea.IsValid())
     {
      double lvl = forBuy ? m_valueArea.VAL() : m_valueArea.VAH();
      double dist = forBuy ? (price - lvl) : (lvl - price);
      if(dist < 0) dist = 0.0;
      if(dist <= bestDist) { bestDist = dist; levelPrice = lvl; source = LEVEL_VALUE_AREA; found = true; }
     }
   if(m_liquidity != NULL)
     {
      ENUM_LIQ_TYPE target = forBuy ? LIQ_SELL_SIDE : LIQ_BUY_SIDE; // sell-side pool = stops below lows = support-adjacent; mirror for resistance
      int n = m_liquidity.EventCount();
      for(int i = 0; i < n; i++)
        {
         LiquidityEvent ev = m_liquidity.GetEvent(i);
         if(!ev.external) continue; // doc's "previous day high/low" maps to external D1 sweeps specifically, not internal equal-highs/lows
         if(ev.type != target) continue;
         double dist = forBuy ? (price - ev.price) : (ev.price - price);
         if(dist < 0) dist = 0.0;
         if(dist <= bestDist) { bestDist = dist; levelPrice = ev.price; source = LEVEL_LIQUIDITY_POOL; found = true; }
        }
     }
   // v2.17 — the three sources v2.14 left unwired. Each returns its own
   // nearest-on-the-requested-side candidate already (see
   // ExtendedKeyLevels.mqh), so this just folds those three single
   // candidates into the same "nearest wins, no source-type favorites"
   // comparison every source above already participates in.
   if(m_extLevels != NULL)
     {
      double lvl;
      if(m_extLevels.NearestPrevWeekLevel(forBuy, price, bestDist, lvl))
        {
         double dist = forBuy ? (price - lvl) : (lvl - price);
         if(dist <= bestDist) { bestDist = dist; levelPrice = lvl; source = LEVEL_PREV_WEEK; found = true; }
        }
      if(m_candles != NULL && m_sessionFilter != NULL &&
         m_extLevels.NearestSessionLevel(forBuy, price, bestDist, lvl, m_candles, m_sessionFilter))
        {
         double dist = forBuy ? (price - lvl) : (lvl - price);
         if(dist <= bestDist) { bestDist = dist; levelPrice = lvl; source = LEVEL_SESSION; found = true; }
        }
      if(m_extLevels.NearestRoundLevel(forBuy, price, bestDist, lvl))
        {
         double dist = forBuy ? (price - lvl) : (lvl - price);
         if(dist <= bestDist) { bestDist = dist; levelPrice = lvl; source = LEVEL_PSYCHOLOGICAL; found = true; }
        }
     }
   return found;
  }
//+------------------------------------------------------------------+
bool CKeyLevelEngine::CrossedFarSide(int shift, double levelPrice, double tol, bool forBuy)
  {
   CandleData cd = m_candles.GetCandle(shift);
   return forBuy ? (cd.close < levelPrice - tol) : (cd.close > levelPrice + tol);
  }
//+------------------------------------------------------------------+
bool CKeyLevelEngine::TouchedLevel(int shift, double levelPrice, double tol)
  {
   CandleData cd = m_candles.GetCandle(shift);
   return (cd.low <= levelPrice + tol && cd.high >= levelPrice - tol);
  }
//+------------------------------------------------------------------+
// Same shift-1-only "final, not still-forming" convention MeanReversion.mqh
// uses for its own wick check, applied per-shift here since this scans a window.
bool CKeyLevelEngine::RejectionWickAt(int shift, double levelPrice, bool forBuy)
  {
   CandleData cd = m_candles.GetCandle(shift);
   double range = cd.high - cd.low;
   if(range <= 0) return false;
   double lowerWick = MathMin(cd.open, cd.close) - cd.low;
   double upperWick = cd.high - MathMax(cd.open, cd.close);
   // forBuy (support, hold side = above): rejection = long lower wick
   // poking through the level while the close stays above it.
   return forBuy ? ((lowerWick / range) >= m_wickRejectionRatio && cd.low <= levelPrice)
                 : ((upperWick / range) >= m_wickRejectionRatio && cd.high >= levelPrice);
  }
//+------------------------------------------------------------------+
void CKeyLevelEngine::Evaluate(bool forBuy, ENUM_KEYLEVEL_SOURCE &source, ENUM_KEYLEVEL_REACTION &reaction, double &reactionScore)
  {
   source = LEVEL_NONE;
   reaction = REACTION_NONE;
   reactionScore = 0.0;

   if(m_candles == NULL || m_candles.Total() < m_lookbackBars + 1) return;
   double atr = m_candles.GetATR(0);
   if(atr <= 0) return;
   double price = m_candles.GetCandle(0).close; // live/current-bar proxy, same convention as the other two strategy modules

   double levelPrice;
   if(!FindNearestLevel(forBuy, atr, price, levelPrice, source))
     {
      source = LEVEL_NONE;
      return; // no level in range at all — stays NONE/NONE/0
     }

   double tol = atr * m_touchToleranceATRMult;

   bool crossed1 = CrossedFarSide(1, levelPrice, tol, forBuy);
   bool crossed2 = CrossedFarSide(2, levelPrice, tol, forBuy);

   if(crossed1 && crossed2)
     {
      reaction = REACTION_ACCEPTANCE;
      reactionScore = 90.0;
      return;
     }
   if(crossed1)
     {
      reaction = REACTION_BREAK;
      reactionScore = 75.0;
      return;
     }

   // Not currently on the far side (crossed1 is false past this point).
   // Was it on the far side at any point earlier in the window?
   bool wasCrossedEarlier = false;
   for(int s = 2; s <= m_lookbackBars; s++)
      if(CrossedFarSide(s, levelPrice, tol, forBuy)) { wasCrossedEarlier = true; break; }

   if(wasCrossedEarlier)
     {
      if(TouchedLevel(1, levelPrice, tol))
        {
         reaction = REACTION_RETEST;
         reactionScore = 70.0;
        }
      else
        {
         reaction = REACTION_FAILED_BREAK;
         reactionScore = 60.0;
        }
      return;
     }

   if(RejectionWickAt(1, levelPrice, forBuy))
     {
      reaction = REACTION_REJECTION;
      reactionScore = 65.0;
      return;
     }

   int touchCount = 0;
   for(int s = 1; s <= m_lookbackBars; s++)
      if(TouchedLevel(s, levelPrice, tol)) touchCount++;

   if(touchCount >= m_absorptionMinTouches)
     {
      reaction = REACTION_ABSORPTION;
      reactionScore = 40.0;
      return;
     }
   // A level was found and possibly touched once, but no pattern above
   // fit cleanly — stays NONE rather than force a weak guess into one
   // of the six named buckets.
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Strategies/KeyLevelReaction.mqh
// BEGIN INLINED MODULE: includes/Strategies/StrategySelector.mqh
//+------------------------------------------------------------------+
//|                                  Strategies/StrategySelector.mqh  |
//+------------------------------------------------------------------+
#ifndef STRATEGYSELECTOR_MQH
#define STRATEGYSELECTOR_MQH

// already inlined once under include guard: includes/Core/Config.mqh

// Regime-aware strategy authority. This layer deliberately does not
// manufacture a setup: it decides whether a diagnostic strategy read is
// eligible to own the next executable setup. A selected strategy that has
// no dedicated builder must fail closed at the strategy/setup boundary.
//
// The selector never adds heterogeneous scores together. It compares a
// strategy's score with the SMC baseline only after applying strategy-
// specific eligibility rules. This keeps "strength of evidence" separate
// from "permission to act".
class CStrategySelector
  {
private:
   double m_minSelectionScore;

   bool MomentumEligible(const SetupReasons &r) const
     {
      // A failed breakout has explicitly invalidated its broken level.
      // Exhaustion is a chase condition, not continuation evidence. Do not
      // let a large raw score override either structural warning.
      if(r.breakout_class == BREAKOUT_FAILED || r.breakout_class == BREAKOUT_EXHAUSTION)
         return false;
      return (r.breakout_class == BREAKOUT_EXPANSION || r.breakout_class == BREAKOUT_LIQUIDITY ||
              r.momentum_score >= m_minSelectionScore);
     }

   bool ReversionEligible(const SetupReasons &r) const
     {
      // Mean reversion already exposes a structural trend-conflict class.
      // It must never become the owner while fading a confirmed opposing BOS.
      return r.reversion_class == REVERSION_VALUE_FADE ||
             r.reversion_class == REVERSION_LEVEL_REJECTION;
     }

   bool KeyLevelEligible(const SetupReasons &r) const
     {
      // A bare break/acceptance is not a reaction entry. Require evidence
      // that price actually rejected, retested, failed the break, or showed
      // absorption at the level before this strategy can challenge SMC.
      return r.keylevel_reaction == REACTION_REJECTION ||
             r.keylevel_reaction == REACTION_RETEST ||
             r.keylevel_reaction == REACTION_FAILED_BREAK ||
             r.keylevel_reaction == REACTION_ABSORPTION;
     }

public:
                     CStrategySelector() : m_minSelectionScore(60.0) {}

   void Configure(double minSelectionScore = 60.0)
     {
      m_minSelectionScore = (minSelectionScore >= 0.0 && minSelectionScore <= 100.0) ? minSelectionScore : 60.0;
     }

   void Select(const SetupReasons &r, double smcConfidence,
               ENUM_SELECTED_STRATEGY &selected, double &selectedScore);
  };
//+------------------------------------------------------------------+
void CStrategySelector::Select(const SetupReasons &r, double smcConfidence,
                               ENUM_SELECTED_STRATEGY &selected, double &selectedScore)
  {
   selected = STRATEGY_NONE;
   selectedScore = 0.0;

   // The regime classifier is authoritative for which challenger family is
   // allowed to compete. An undefined regime is an explicit abstention.
   if(r.regime == REGIME_UNDEFINED)
      return;

   // SMC remains the baseline only when it has a real candidate. The caller
   // is responsible for ensuring that its executable SMC setup is complete.
   if(smcConfidence > 0.0)
     {
      selected = STRATEGY_SMC;
      selectedScore = smcConfidence;
     }

   double challengerScore = -1.0;
   ENUM_SELECTED_STRATEGY challenger = STRATEGY_NONE;

   if(r.regime == REGIME_TRENDING)
     {
      if(MomentumEligible(r))
        {
         challengerScore = MathMax(r.momentum_score, r.breakout_score);
         challenger = STRATEGY_MOMENTUM_BREAKOUT;
        }
     }
   else if(r.regime == REGIME_RANGING)
     {
      if(ReversionEligible(r))
        {
         challengerScore = r.reversion_score;
         challenger = STRATEGY_MEAN_REVERSION;
        }
     }
   else if(r.regime == REGIME_TRANSITION)
     {
      if(KeyLevelEligible(r))
        {
         challengerScore = r.keylevel_score;
         challenger = STRATEGY_KEY_LEVEL;
        }
     }

   // No SMC candidate means a challenger can still be diagnostically
   // selected, but it remains non-executable until its own setup builder
   // exists. If SMC exists, the challenger must clear both the minimum
   // evidence threshold and the SMC baseline.
   if(challenger != STRATEGY_NONE && challengerScore >= m_minSelectionScore &&
      (selected == STRATEGY_NONE || challengerScore > smcConfidence))
     {
      selected = challenger;
      selectedScore = challengerScore;
     }

   if(selected == STRATEGY_NONE)
      selectedScore = 0.0;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Strategies/StrategySelector.mqh

// v2.1 SCORING MODEL — replaces the old flat weighted sum with the
// point table from the inducement-engine spec:
//   Strong Impulse             +15  \
//   Internal Structure Formed  +10   |  from CInducement.Validate() —
//   Internal Liquidity Sweep   +25   |  see SmartMoney/Inducement.mqh
//   BOS after Sweep            +20  /
//   Fresh FVG                  +15
//   HTF Alignment               +15
//   -------------------------------
//   Total                      100
//
// GATING, not just scoring: if the liquidity sweep (and its confirming
// minor BOS) never happens, confidence is 0 and CTradeDecision's existing
// "confidence < threshold" check blocks the setup outright — per your
// instruction, this removes false entries rather than just down-weighting
// them. Two further gates are available and OFF/ON as noted:
//   - Premium/Discount filter: ON by default. Buys must be in the lower
//     half (discount) of the impulse range, sells in the upper half.
//   - Market Phase (Distribution-only) filter: OFF by default, because
//     the phase read is the least rigorously defined of the additions
//     (see MarketPhase.mqh's caveat) — enable via RequireDistribution
//     if you want to test it.
//
// Evidence authority rule:
//   * Inducement is the sole authoritative entry-timeframe source for
//     impulse/structure/sweep/BOS evidence.
//   * FVG/Trend remain separate confluence dimensions.
//   * Legacy BOS/Liquidity point scorers are intentionally removed from
//     this class. Their old evidence is neither summed into confidence nor
//     recomputed for SetupReasons; the Inducement result is the single
//     representation used by the scoring/reason layer. This prevents the
//     same sweep/BOS event from acquiring two votes under different names.
//
// v2.8 additions (see ConfigureHtfOrderBlock/ConfigureVolatilityRegime/
// ConfigureSessionFilter below): HTF Order Block confluence and the
// low-volatility-regime block follow the same OFF-by-default,
// unvalidated-until-backtested discipline as the v2.6 gates. The session
// filter is the one exception — it defaults ON, because "trade every
// session with equal weight" was never a validated assumption in the
// first place; it was just what happens when nothing gates on session at
// all. See Core/SessionFilter.mqh.
class CScoringEngine
  {
private:
   CTFContext*       m_trendCtx;
   CTFContext*       m_bosCtx;
   CTFContext*       m_liqCtx;
   CTFContext*       m_fvgCtx;
   CTFContext*       m_srCtx;
   CCandleData*      m_priceRef;   // chart-TF candles, used only for "current price"
   bool              m_requireMtfStructureAlignment; // opt-in until matched backtests validate the gate
   int               m_mtfMaxBosAgeBars; // freshness is measured in each context's own bars

   CInducement       m_inducement;
   bool              m_requirePremiumDiscount;
   bool              m_requireDistribution;
   CMarketPhase      m_phase;

   // v2.6: Volume + Fibonacci — see ConfigureVolumeFibonacci() below for
   // why both default OFF.
   bool              m_requireVolumeConfirmation;
   double            m_rvolThreshold;
   bool              m_requireFibonacciZone;
   double            m_fibZoneMinPct;
   double            m_fibZoneMaxPct;
   bool              m_requireValueAreaLocation;
   bool              m_blockValueAreaContradictions;

   // --- v2.8 additions -------------------------------------------------
   CTFContext*       m_htfObCtx;             // separate, genuinely-higher timeframe context (e.g. H4/D1)
   bool              m_requireHtfOB;         // OFF by default — see class-level discipline note
   double            m_obDistATRMax;         // how far price may sit from an OB's midpoint and still count
   CVolatilityRegime m_volRegime;
   bool              m_blockLowVolRegime;    // OFF by default
   CSessionFilter    m_sessionFilter;        // ON by default (see Init()) — direct fix for
                                              // "trading time is across all sessions"

   // --- v2.9 additions ---------------------------------------------
   double            m_fvgMaxDistATR;        // was hardcoded 3.0; now 1.25 by default — see ConfigureFVGProximity()
   bool              m_requireChaseFilter;   // OFF by default — see ConfigureChaseFilter()
   double            m_maxChaseDistATR;

   // v2.9 — news-aware soft scoring. Distinct from the EA-level hard
   // IsLocked() block (which fully prevents entries in the narrow window
   // regardless of this). NULL pointer = feature inactive, same
   // fail-open-if-unconfigured convention as m_htfObCtx etc.
   CNewsFilter*      m_newsFilter;
   double            m_newsWarningMultiplier; // confidence *= this when in the WARNING tier

   // --- v2.10 diagnostic weights (see ConfigureLearnedDiagnostics()) ---
   // Used ONLY by the diagnostic block below; never enter
   // CalculateConfidence()'s arithmetic.
   double            m_contradictionWeight;  // scales the contradiction count into a 0-1 penalty
   double            m_envWeight;            // 0-1 blend: how much of env_score counts vs. assumed-neutral
   double            m_execWeight;           // 0-1 blend: same for exec_score

   // --- v2.12 strategy diagnostics (Regime/RegimeDetector.mqh,
   // Strategies/MomentumBreakout.mqh) — owned here rather than as
   // separate objects wired at the .mq5 level, because everything they
   // need (m_trendCtx.trend, m_bosCtx.bos, m_liqCtx.liquidity, m_phase,
   // m_volRegime) already exists on this class. Populated by
   // PopulateStrategyDiagnostics() only; never consulted by
   // CalculateConfidence() or anything that gates a trade.
   CRegimeDetector          m_regimeDetector;
   CSMCStructuralValidator  m_smcValidator;
   CMomentumBreakoutEngine  m_momentumEngine;
   // v2.13: Mean Reversion needs its own volatility-regime read scoped
   // to the CHART timeframe (m_srCtx), not the BOS-timeframe instance
   // (m_volRegime) Momentum/Regime already use above — VA/SR live on
   // the chart TF, so "controlled volatility" has to describe the same
   // market they're measuring, not a possibly-different BOS timeframe.
   CVolatilityRegime        m_volRegimeSR;
   CMeanReversionEngine     m_meanReversionEngine;
   // v2.14: no new detectors needed — reuses m_srCtx's own sr/valueArea/
   // orderBlock plus m_liqCtx.liquidity, same reuse pattern as the two
   // engines above. v2.17: now also wired to m_extendedKeyLevels below
   // and m_sessionFilter (already a member, above) for the three
   // previously-unwired sources.
   CKeyLevelEngine          m_keyLevelEngine;
   CExtendedKeyLevels       m_extendedKeyLevels; // v2.17 — prev week / session / psychological levels
   // v2.15: no Init() needed — see Strategies/StrategySelector.mqh, this
   // class only reads values the three engines above already computed.
   CStrategySelector        m_strategySelector;

   double            OBScore(bool forBuy);

   double            TrendScore(bool forBuy);
   bool              ContextMTFStructureAligned(CTFContext* ctx, bool forBuy);
   bool              MTFStructureAligned(bool forBuy);
   double            FVGScore(bool forBuy);
   double            SRScore(bool forBuy);
   double            VolumeScore(bool forBuy);
   double            FibonacciScore(bool forBuy);
   double            ValueAreaScore(bool forBuy);
   double            PipSize();
   double            CurrentPrice();
   // v2.10 diagnostics - read the already-computed reasons instead of
   // re-deriving anything, so a diagnostic can never disagree with the
   // CSV row it is logged next to.
   double            ContradictionPenalty(const SetupReasons &r);
   double            EnvironmentScore(const SetupReasons &r);
   double            ExecutionScore(const SetupReasons &r);

public:
                     CScoringEngine();
   void              Init(CTFContext* trendCtx, CTFContext* bosCtx, CTFContext* liqCtx,
                          CTFContext* fvgCtx, CTFContext* srCtx, CCandleData* priceRef);
   // MTF structure gate is opt-in until matched MT5 ablation tests prove its effect.
   // maxBosAgeBars is interpreted separately in every context's own timeframe.
   void              ConfigureMTFStructureAlignment(bool required, int maxBosAgeBars = 20)
     {
      m_requireMtfStructureAlignment = required;
      m_mtfMaxBosAgeBars = maxBosAgeBars;
      if(m_mtfMaxBosAgeBars < 1) m_mtfMaxBosAgeBars = 1;
      if(m_mtfMaxBosAgeBars > 500) m_mtfMaxBosAgeBars = 500;
     }
   void              ConfigureInducement(int lookbackBars, double impulseATRMult, double impulseBodyRatio,
                                         double equalTolATR, int maxLegExtend,
                                         bool requirePremiumDiscount, bool requireDistribution,
                                         int phaseRangeLookback, double phaseCompressionATRMult);
   // v2.6 addition. Volume and Fibonacci are FILTERS on top of the existing
   // Inducement-based confidence model, not additional signal generators:
   // when a gate is enabled and fails, CalculateConfidence returns 0 (same
   // as the premium/discount and phase gates above), exactly like the
   // spec's "trade is valid only if every mandatory filter passes." When a
   // gate passes (or is disabled), a small capped bonus (5 pts each) is
   // added for ranking, so a stronger volume/fib read can break a tie
   // between two otherwise-equal setups without being able to manufacture
   // a passing score on its own.
   //
   // Both gates default OFF. The spec's own "Backtesting Requirements"
   // section says a module should only be combined in after it's shown,
   // independently and out-of-sample, to improve results — and this
   // codebase currently has no MQL5 compile/backtest environment (Android/
   // Termux can't run MetaEditor's Strategy Tester; see project notes).
   // Shipping these gates pre-enabled would be exactly the un-validated
   // assumption that discipline exists to prevent. Flip both to true once
   // you've run the comparison on a Windows VPS/terminal.
   void              ConfigureVolumeFibonacci(bool requireVolumeConfirmation, double rvolThreshold,
                                              bool requireFibonacciZone, double fibZoneMinPct, double fibZoneMaxPct);
   // v2.20: separate the legacy location gate from the production
   // contradiction gate. The latter only blocks when a sufficiently good
   // profile actively conflicts with the trade thesis. Missing/low-quality
   // profile data fails open, and accepted breakouts remain eligible.
   void              ConfigureValueArea(bool requireValueAreaLocation, bool blockValueAreaContradictions = true);
   // v2.8 addition. htfObCtx MUST be a genuinely higher timeframe than
   // fvgCtx/bosCtx (e.g. entry on M15/H1, this on H4/D1) — passing the
   // same context defeats the point of "higher timeframe" confluence.
   // Defaults OFF for the same "unvalidated until proven" reason as
   // ConfigureVolumeFibonacci(): it's a brand-new engine, never backtested.
   void              ConfigureHtfOrderBlock(CTFContext* htfObCtx, bool requireHtfOB, double distATRMax = 2.0);
   // v2.8 addition. Blocks entries when the ATR-percentile regime reads
   // LOW (thin, choppy — see VolatilityRegime.mqh). Defaults OFF, same
   // discipline as above; the regime read itself is always populated in
   // EvaluateReasons() for diagnostics regardless of this flag.
   void              ConfigureVolatilityRegime(bool blockLowVolRegime, int lookback = 100,
                                                double lowPct = 0.25, double highPct = 0.75);
   // v2.8 addition. ON by default — this is the direct fix for "EA trades
   // every session uniformly": by default allows London, New York, and
   // the London/NY overlap; blocks Tokyo-only and dead hours. Pass
   // enabled=false to restore pre-v2.8 all-sessions behavior.
   void              ConfigureSessionFilter(bool enabled, bool allowTokyo = false, bool allowLondon = true,
                                            bool allowNewYork = true, bool allowOverlap = true);
   // v2.9 addition. FVGScore() now ranks every qualifying FVG and keeps
   // the best-scoring one instead of returning the first match found —
   // "first" had no relationship to "best" (freshness/proximity), so two
   // setups with identical top-line confidence could be resting on very
   // different FVG quality. Default distance cap tightened from the old
   // hardcoded 3.0 ATR to 1.25 ATR (item #8 in the review — a zone 2.8
   // ATR away isn't an immediate entry zone); this is a default-value
   // change, not a new OFF-by-default gate, since it only tightens an
   // existing filter rather than adding a new one. Still needs the same
   // ablation-test validation as everything else before being trusted.
   void              ConfigureFVGProximity(double maxDistATR = 1.25);
   // v2.9 addition (review item #4/#10 — "chase filter"). Rejects a
   // setup when price has already run too far past the BOS confirmation
   // close before the EA gets to evaluate it. Distinct from the existing
   // entry-deviation guard in OrderManager (which protects execution
   // AFTER a decision is made) — this catches a setup that was
   // strategically late before any order is even built. OFF by default,
   // same discipline as every other v2.8/v2.9 gate.
   void              ConfigureChaseFilter(bool requireChaseFilter, double maxChaseDistATR = 0.75);
   // v2.9 addition — passthrough to CInducement::ConfigureQualityGates().
   // See that method's comment for the OFF-by-default rationale.
   void              ConfigureSweepQuality(bool requireMinSweepGrade, ENUM_SWEEP_GRADE minSweepGrade,
                                           bool requireFreshSetup, int maxBarsSinceBOS = 5);
   // v2.9. warnMinutesBefore/After must be >= the EA's hard-block window
   // (InpNewsMinutesBefore/After) or they're clamped up to it inside
   // CNewsFilter::ConfigureWarningWindow() — WARNING is defined as a
   // superset of BLOCKED. newsWarningMultiplier default 0.85 is a
   // starting point, not a tuned constant.
   void              ConfigureNewsAwareness(CNewsFilter* newsFilter, int warnMinutesBefore = 60,
                                            int warnMinutesAfter = 30, double newsWarningMultiplier = 0.85);
   // v2.10 addition. Weights for the DIAGNOSTIC-ONLY contradiction /
   // environment / execution model. Defaults are the neutral starting
   // point from the upgrade spec, NOT tuned constants - replace them with
   // whatever tools/medistouch_retrain.py fits on your own resolved
   // outcomes. Changing these cannot change any trading decision; see the
   // SetupReasons v2.10 block in Core/Config.mqh.
   void              ConfigureLearnedDiagnostics(double contradictionWeight = 0.25,
                                                 double envWeight = 1.0,
                                                 double execWeight = 1.0);
   // v2.12 addition. Passthrough to CMomentumBreakoutEngine::Configure();
   // see that class for what each parameter means and why the defaults
   // are starting points, not tuned constants. The regime detector takes
   // no separate configuration — it has no tunable thresholds of its own
   // beyond what CVolatilityRegime/CMarketPhase already expose via their
   // own Configure calls above.
   void              ConfigureStrategyDiagnostics(int momentumBreakoutRecencyBars = 10,
                                                  int liqOverlapBars = 2,
                                                  int extensionLookbackBars = 15,
                                                  double exhaustionATRMult = 3.0,
                                                  int momentumLookbackBars = 10);
   // v2.13 addition. Passthrough to CMeanReversionEngine::Configure();
   // see that class for what each parameter means.
   void              ConfigureMeanReversionDiagnostics(double minStretchATR = 1.0,
                                                        double srZoneATRTolerance = 0.25,
                                                        double wickRejectionRatio = 0.55,
                                                        int liqRecencyBars = 10,
                                                        int trendConflictRecencyBars = 10,
                                                        double trendConflictMinStrength = 0.5);
   // v2.14 addition. Passthrough to CKeyLevelEngine::Configure(); see
   // that class for what each parameter means. v2.17: roundStep added —
   // passthrough to CExtendedKeyLevels::Configure(), default kept
   // separate from the other four params (own line) since it belongs to
   // a different underlying object, same separation the Init() wiring
   // above keeps.
   void              ConfigureKeyLevelDiagnostics(int lookbackBars = 5,
                                                   double levelSearchATRMax = 3.0,
                                                   double touchToleranceATRMult = 0.15,
                                                   int absorptionMinTouches = 3,
                                                   double wickRejectionRatio = 0.55,
                                                   double roundStep = 10.0);
   // v2.15 addition. Passthrough to CStrategySelector::Configure().
   void              ConfigureStrategySelection(double minSelectionScore = 60.0);
   double            CalculateConfidence(bool forBuy);
   void              EvaluateReasons(bool forBuy, SetupReasons &out);
   // v2.10. Call right after EvaluateReasons() with the confidence the
   // additive model actually returned; fills the four v2.10 diagnostic
   // fields on `out`. Separate from EvaluateReasons() because
   // env_exec_confidence needs a confidence value, and EvaluateReasons()
   // is deliberately allowed to run without one (the dashboard calls it).
   void              PopulateConfidenceDiagnostics(SetupReasons &out, double confidence);
   // v2.12. Same "call right after the fields it depends on exist"
   // convention as PopulateConfidenceDiagnostics(): call this after
   // EvaluateReasons() so out.regime/momentum_score/breakout_score/
   // breakout_class land on the same SetupReasons the rest of the row
   // describes. forBuy must match whatever direction EvaluateReasons()
   // was just called with, or the momentum/breakout read describes the
   // wrong side of the setup. confidence is the same value passed to
   // PopulateConfidenceDiagnostics() — v2.15 needs it to compare against
   // the three strategy scores computed in this same call.
   void              PopulateStrategyDiagnostics(bool forBuy, double confidence, SetupReasons &out);
   void              PopulateStructuralValidation(bool forBuy, SetupReasons &out);
   InducementResult  GetInducement(bool forBuy) { return m_inducement.Validate(forBuy); }
   ENUM_MARKET_PHASE GetPhase() { return m_phase.Detect(); }
  };
//+------------------------------------------------------------------+
CScoringEngine::CScoringEngine() : m_trendCtx(NULL), m_bosCtx(NULL), m_liqCtx(NULL),
                                    m_fvgCtx(NULL), m_srCtx(NULL), m_priceRef(NULL),
                                    m_requireMtfStructureAlignment(false), m_mtfMaxBosAgeBars(20),
                                    m_requirePremiumDiscount(true), m_requireDistribution(false),
                                    m_requireVolumeConfirmation(false), m_rvolThreshold(1.5),
                                    m_requireFibonacciZone(false), m_fibZoneMinPct(50.0), m_fibZoneMaxPct(61.8),
                                    m_requireValueAreaLocation(false), m_blockValueAreaContradictions(true),
                                    m_htfObCtx(NULL), m_requireHtfOB(false), m_obDistATRMax(2.0),
                                    m_blockLowVolRegime(false),
                                    m_fvgMaxDistATR(1.25), m_requireChaseFilter(false), m_maxChaseDistATR(0.75),
                                    m_newsFilter(NULL), m_newsWarningMultiplier(0.85),
                                    m_contradictionWeight(0.25), m_envWeight(1.0), m_execWeight(1.0)
  {
   // Session filter defaults to ON — see ConfigureSessionFilter()'s
   // comment. Unlike the other v2.8 gates this isn't a new, unbacktested
   // signal; it's a liquidity-hours restriction, and trading 24h flat
   // (including the Tokyo-only dead zone) is itself the unvalidated
   // assumption per the audit that flagged it.
   m_sessionFilter.Configure(true, false, true, true, true);
  }
void CScoringEngine::Init(CTFContext* trendCtx, CTFContext* bosCtx, CTFContext* liqCtx,
                          CTFContext* fvgCtx, CTFContext* srCtx, CCandleData* priceRef)
  {
   m_trendCtx = trendCtx;
   m_bosCtx = bosCtx;
   m_liqCtx = liqCtx;
   m_fvgCtx = fvgCtx;
   m_srCtx = srCtx;
   m_priceRef = priceRef;
   if(m_fvgCtx != NULL)
     {
      m_inducement.Init(&m_fvgCtx.candles);
      if(m_liqCtx != NULL)
         m_phase.Init(&m_fvgCtx.candles, &m_liqCtx.liquidity);
     }
   if(m_bosCtx != NULL)
      m_volRegime.Init(&m_bosCtx.candles); // defaults: 100-bar lookback, 25th/75th pct bands
   // v2.12: regime detector needs all three reads; momentum/breakout
   // engine needs the BOS-timeframe's own candles/BOS/liquidity so its
   // bar_index comparisons stay on one timeframe's series (mixing BOS
   // events from one TF with liquidity events from another would make
   // HasNearbyLiquidityEvent's bar_index gap meaningless).
   if(m_trendCtx != NULL && m_bosCtx != NULL)
      m_regimeDetector.Init(&m_trendCtx.trend, &m_volRegime, &m_phase);
   m_smcValidator.Init(m_trendCtx, m_fvgCtx, m_htfObCtx);
   if(m_bosCtx != NULL && m_liqCtx != NULL)
      m_momentumEngine.Init(&m_bosCtx.candles, &m_bosCtx.bos, &m_liqCtx.liquidity, &m_volRegime);
   // v2.13: chart-TF vol regime, deliberately separate instance from
   // m_volRegime above (see the member declaration comment for why).
   // Mean Reversion's candles/SR/valueArea all come from m_srCtx (chart
   // TF); liquidity/BOS reuse m_liqCtx/m_bosCtx same as Momentum does,
   // carrying the same cross-timeframe caveat documented there.
   if(m_srCtx != NULL)
     {
      m_volRegimeSR.Init(&m_srCtx.candles);
      if(m_liqCtx != NULL && m_bosCtx != NULL)
         m_meanReversionEngine.Init(&m_srCtx.candles, &m_srCtx.sr, &m_srCtx.valueArea,
                                    &m_liqCtx.liquidity, &m_volRegimeSR, &m_bosCtx.bos);
      // v2.14: same chart-TF sr/valueArea/orderBlock, same m_liqCtx
      // liquidity reuse (same cross-timeframe caveat as above).
      // v2.17: m_extendedKeyLevels.Init() needs a symbol — pulled from
      // this same chart-TF candle series rather than adding a new
      // parameter to CScoringEngine::Init(), since it's already the
      // exact symbol every other source in this engine is scoped to.
      // m_sessionFilter is already a member (see class declaration) —
      // passed by address, no separate Init() call needed for it here.
      if(m_liqCtx != NULL)
        {
         m_extendedKeyLevels.Init(m_srCtx.candles.Symbol());
         m_keyLevelEngine.Init(&m_srCtx.candles, &m_srCtx.sr, &m_srCtx.valueArea,
                               &m_liqCtx.liquidity, &m_srCtx.orderBlock,
                               &m_extendedKeyLevels, &m_sessionFilter);
        }
     }
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureInducement(int lookbackBars, double impulseATRMult, double impulseBodyRatio,
                                         double equalTolATR, int maxLegExtend,
                                         bool requirePremiumDiscount, bool requireDistribution,
                                         int phaseRangeLookback, double phaseCompressionATRMult)
  {
   if(m_fvgCtx != NULL)
     {
      m_inducement.Init(&m_fvgCtx.candles, lookbackBars, impulseATRMult, impulseBodyRatio, equalTolATR, maxLegExtend);
      if(m_liqCtx != NULL)
         m_phase.Init(&m_fvgCtx.candles, &m_liqCtx.liquidity, phaseRangeLookback, phaseCompressionATRMult);
     }
   m_requirePremiumDiscount = requirePremiumDiscount;
   m_requireDistribution = requireDistribution;
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureVolumeFibonacci(bool requireVolumeConfirmation, double rvolThreshold,
                                              bool requireFibonacciZone, double fibZoneMinPct, double fibZoneMaxPct)
  {
   m_requireVolumeConfirmation = requireVolumeConfirmation;
   m_rvolThreshold = (rvolThreshold > 0) ? rvolThreshold : 1.5;
   m_requireFibonacciZone = requireFibonacciZone;
   m_fibZoneMinPct = fibZoneMinPct;
   m_fibZoneMaxPct = fibZoneMaxPct;
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureValueArea(bool requireValueAreaLocation, bool blockValueAreaContradictions)
  {
   m_requireValueAreaLocation = requireValueAreaLocation;
   m_blockValueAreaContradictions = blockValueAreaContradictions;
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureHtfOrderBlock(CTFContext* htfObCtx, bool requireHtfOB, double distATRMax)
  {
   m_htfObCtx = htfObCtx;
   m_smcValidator.Init(m_trendCtx, m_fvgCtx, m_htfObCtx);
   m_requireHtfOB = requireHtfOB;
   m_obDistATRMax = (distATRMax > 0) ? distATRMax : 2.0;
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureVolatilityRegime(bool blockLowVolRegime, int lookback, double lowPct, double highPct)
  {
   m_blockLowVolRegime = blockLowVolRegime;
   if(m_bosCtx != NULL)
      m_volRegime.Init(&m_bosCtx.candles, lookback, lowPct, highPct);
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureSessionFilter(bool enabled, bool allowTokyo, bool allowLondon,
                                            bool allowNewYork, bool allowOverlap)
  {
   m_sessionFilter.Configure(enabled, allowTokyo, allowLondon, allowNewYork, allowOverlap);
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureFVGProximity(double maxDistATR)
  {
   m_fvgMaxDistATR = (maxDistATR > 0) ? maxDistATR : 1.25;
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureChaseFilter(bool requireChaseFilter, double maxChaseDistATR)
  {
   m_requireChaseFilter = requireChaseFilter;
   m_maxChaseDistATR = (maxChaseDistATR > 0) ? maxChaseDistATR : 0.75;
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureSweepQuality(bool requireMinSweepGrade, ENUM_SWEEP_GRADE minSweepGrade,
                                           bool requireFreshSetup, int maxBarsSinceBOS)
  {
   m_inducement.ConfigureQualityGates(requireMinSweepGrade, minSweepGrade, requireFreshSetup, maxBarsSinceBOS);
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureNewsAwareness(CNewsFilter* newsFilter, int warnMinutesBefore,
                                            int warnMinutesAfter, double newsWarningMultiplier)
  {
   m_newsFilter = newsFilter;
   if(m_newsFilter != NULL)
      m_newsFilter.ConfigureWarningWindow(warnMinutesBefore, warnMinutesAfter);
   m_newsWarningMultiplier = (newsWarningMultiplier > 0 && newsWarningMultiplier <= 1.0) ? newsWarningMultiplier : 0.85;
  }
//+------------------------------------------------------------------+
double CScoringEngine::CurrentPrice()
  {
   if(m_priceRef == NULL || m_priceRef.Total() == 0) return 0.0;
   return m_priceRef.GetCandle(0).close;
  }
//+------------------------------------------------------------------+
bool CScoringEngine::ContextMTFStructureAligned(CTFContext* ctx, bool forBuy)
  {
   // Fail closed only when this opt-in gate is enabled: the context, trend,
   // confirmed BOS and candle-to-event lineage must all be available.
   if(ctx == NULL || !ctx.candles.IsReady() || ctx.candles.Total() < 2)
      return false;

   ENUM_TREND_STATE trend = ctx.trend.GetCurrentTrend();
   bool trendAligned = forBuy
                       ? (trend == TREND_BULL || trend == TREND_BULL_STRONG)
                       : (trend == TREND_BEAR || trend == TREND_BEAR_STRONG);
   if(!trendAligned || ctx.bos.Count() <= 0)
      return false;

   // CBOS::Detect() emits only completed-bar events; GetBOS(0) is the
   // newest event. Require that it supports this direction and is fresh
   // relative to this context's own candle series, not the chart timeframe.
   BOSEvent latestBOS = ctx.bos.GetBOS(0);
   if(latestBOS.time <= 0 || latestBOS.is_bullish != forBuy)
      return false;
   if(latestBOS.bar_index < 1 || latestBOS.bar_index >= ctx.candles.Total())
      return false;

   CandleData latestClosed = ctx.candles.GetCandle(1);
   CandleData bosCandle = ctx.candles.GetCandle(latestBOS.bar_index);
   if(latestClosed.time <= 0 || bosCandle.time != latestBOS.time)
      return false; // reject stale/misaligned event provenance
   if(latestBOS.time > latestClosed.time)
      return false; // no forming/future-bar evidence

   int barsSinceBOS = latestBOS.bar_index - 1;
   if(barsSinceBOS < 0 || barsSinceBOS > m_mtfMaxBosAgeBars)
      return false;

   // A more recent opposing CHoCH means the BOS direction has been
   // challenged. Older CHoCH events are historical and must not override
   // a subsequently confirmed BOS. CHoCH timestamps are completed-bar times.
   if(ctx.choch.Count() > 0)
     {
      CHOCHPoint latestCHOCH = ctx.choch.Get(0);
      if(latestCHOCH.time > latestClosed.time)
         return false;
      if(latestCHOCH.time > latestBOS.time && latestCHOCH.bullish != forBuy)
         return false;
     }

   return true;
  }
//+------------------------------------------------------------------+
bool CScoringEngine::MTFStructureAligned(bool forBuy)
  {
   if(m_trendCtx == NULL || m_bosCtx == NULL)
      return false;

   // A shared timeframe is one evidence source, not two independent votes.
   if(m_trendCtx.tf == m_bosCtx.tf)
      return ContextMTFStructureAligned(m_trendCtx, forBuy);

   // Both the higher-timeframe trend context and the BOS/structure context
   // must independently pass direction, freshness and CHoCH-conflict checks.
   return ContextMTFStructureAligned(m_trendCtx, forBuy)
          && ContextMTFStructureAligned(m_bosCtx, forBuy);
  }
//+------------------------------------------------------------------+
double CScoringEngine::TrendScore(bool forBuy)
  {
   if(m_trendCtx == NULL) return 0.0;
   ENUM_TREND_STATE t = m_trendCtx.trend.GetCurrentTrend();
   if(forBuy)
     {
      if(t == TREND_BULL_STRONG) return 1.0;
      if(t == TREND_BULL) return 0.6;
      return 0.0;
     }
   else
     {
      if(t == TREND_BEAR_STRONG) return 1.0;
      if(t == TREND_BEAR) return 0.6;
      return 0.0;
     }
  }

double CScoringEngine::FVGScore(bool forBuy)
  {
   if(m_fvgCtx == NULL || m_fvgCtx.candles.Total() == 0) return 0.0;
   double price = CurrentPrice();
   double atr = m_fvgCtx.candles.GetATR(0);
   if(price <= 0 || atr <= 0) return 0.0;
   ENUM_FVG_DIR wantDir = forBuy ? FVG_BULL : FVG_BEAR;

   // v2.9 (review item #7/#8): rank every qualifying zone instead of
   // returning the first match — "first" is an artifact of detection
   // order, not quality. Distance cap now m_fvgMaxDistATR (default 1.25,
   // was hardcoded 3.0) — see ConfigureFVGProximity().
   double best = 0.0;
   for(int i = 0; i < m_fvgCtx.fvg.Count(); i++)
     {
      FVGZone z = m_fvgCtx.fvg.GetZone(i);
      if(z.dir != wantDir) continue;
      if(z.state != FVG_FRESH && z.state != FVG_TESTED) continue;
      double mid = (z.top + z.bottom) / 2.0;
      double distATR = MathAbs(price - mid) / atr;
      if(distATR > m_fvgMaxDistATR) continue;
      double base = (z.state == FVG_FRESH) ? 1.0 : 0.6;
      double proximity = MathMax(0.0, 1.0 - distATR / m_fvgMaxDistATR);
      double score = base * (0.5 + 0.5 * proximity);
      if(score > best) best = score;
     }
   return best;
  }
//+------------------------------------------------------------------+
double CScoringEngine::SRScore(bool forBuy)
  {
   if(m_srCtx == NULL || m_srCtx.candles.Total() == 0) return 0.0;
   double price = CurrentPrice();
   double atr = m_srCtx.candles.GetATR(0);
   if(price <= 0 || atr <= 0) return 0.0;

   for(int i = 0; i < m_srCtx.sr.Count(); i++)
     {
      SRZone z = m_srCtx.sr.GetZone(i);
      bool isSupport = (z.type == SR_MAJOR_SUPPORT || z.type == SR_MINOR_SUPPORT);
      bool isResistance = (z.type == SR_MAJOR_RESISTANCE || z.type == SR_MINOR_RESISTANCE);
      if(forBuy && !isSupport) continue;
      if(!forBuy && !isResistance) continue;
      double mid = (z.top + z.bottom) / 2.0;
      double distATR = MathAbs(price - mid) / atr;
      if(distATR > 1.5) continue;
      return MathMin((double)z.touches / 3.0, 1.0);
     }
   return 0.0;
  }
//+------------------------------------------------------------------+
// RVOL of the BOS/structure timeframe's most recently CLOSED bar.
// FIX (audit #16): the EA evaluates once per NEW bar (OnTick fires the
// instant iTime() for shift 0 changes -- i.e. the instant a bar OPENS),
// so shift 0 at that exact moment is a brand-new candle with almost no
// tick volume accumulated yet. Gating InpRVOLThreshold against that
// number checked volume at the single most uninformative instant
// possible. Shift 1 is the bar that just fully closed -- final volume,
// actually means something -- and matches what the audit itself
// recommended ("the volume gate should probably use a closed BOS/
// structure candle rather than the currently forming bar").
double CScoringEngine::VolumeScore(bool forBuy)
  {
   if(m_bosCtx == NULL) return 0.0;
   return m_bosCtx.volume.Score(1, m_rvolThreshold);
  }
//+------------------------------------------------------------------+
double CScoringEngine::FibonacciScore(bool forBuy)
  {
   if(m_bosCtx == NULL) return 0.0;
   double price = CurrentPrice();
   if(price <= 0) return 0.0;
   return m_bosCtx.fibonacci.Score(forBuy, price, m_fibZoneMinPct, m_fibZoneMaxPct);
  }
//+------------------------------------------------------------------+
// Value Area is chart-TF, same as SRScore() — it's "where is price
// relative to fair value on the resolution you're actually looking at."
double CScoringEngine::ValueAreaScore(bool forBuy)
  {
   if(m_srCtx == NULL) return 0.0;
   double price = CurrentPrice();
   if(price <= 0) return 0.0;
   return m_srCtx.valueArea.Score(forBuy, price);
  }
//+------------------------------------------------------------------+
// v2.8. Distance-scored the same way SRScore() rewards proximity: full
// credit at the OB midpoint, decaying to 0 at m_obDistATRMax. Uses the
// HTF context's OWN atr (m_htfObCtx.candles), not the entry-TF ATR — a
// "2 ATR" distance means something different on H4 than on M15, and
// mixing them would silently change what "near confluence" means.
double CScoringEngine::OBScore(bool forBuy)
  {
   if(m_htfObCtx == NULL) return 0.0;
   double price = CurrentPrice();
   if(price <= 0) return 0.0;
   double atr = m_htfObCtx.candles.GetATR(0);
   if(atr <= 0) return 0.0;

   OrderBlockZone z;
   ENUM_FVG_DIR dir = forBuy ? FVG_BULL : FVG_BEAR;
   if(!m_htfObCtx.orderBlock.NearestZone(dir, price, atr, m_obDistATRMax, z)) return 0.0;

   double mid = (z.top + z.bottom) / 2.0;
   double distATR = MathAbs(price - mid) / atr;
   double proximity = MathMax(0.0, 1.0 - distATR / m_obDistATRMax);
   double stateMult = (z.state == OB_FRESH) ? 1.0 : 0.7; // tested zones still count, just less
   return MathMin(proximity * stateMult, 1.0);
  }
//+------------------------------------------------------------------+
double CScoringEngine::CalculateConfidence(bool forBuy)
  {
   // v2.8: session gate runs first and cheapest — no point evaluating the
   // rest of the pipeline for a bar that's going to be rejected anyway.
   if(!m_sessionFilter.IsAllowed())
      return 0.0;

   InducementResult ind = m_inducement.Validate(forBuy);
   if(!ind.valid) return 0.0;

   // Optional hard gate: HTF trend bias and structure-timeframe trend must
   // agree with the proposed direction. Disabled by default pending ablation.
   if(m_requireMtfStructureAlignment && !MTFStructureAligned(forBuy))
      return 0.0;

   // v2.9 (review item #4/#10 — chase filter). Rejects a setup that's
   // already run too far past the BOS confirmation close by the time the
   // EA evaluates it — the single worst entry location per the review
   // ("BOS -> price explodes 1.2 ATR -> EA enters after"). Distinct from
   // OrderManager's entry-deviation guard, which protects execution
   // slippage AFTER a decision, not the decision itself. OFF by default.
   if(m_requireChaseFilter && ind.bosBarIndex >= 0 && m_bosCtx != NULL)
     {
      double price = CurrentPrice();
      double atr = m_bosCtx.candles.GetATR(0);
      if(price > 0 && atr > 0)
        {
         double chaseDist = forBuy ? (price - ind.bosClosePrice) : (ind.bosClosePrice - price);
         if(chaseDist / atr > m_maxChaseDistATR)
            return 0.0;
        }
     }

   double score = ind.totalScore;

   // v2.9: news-aware soft discount. The EA-level IsLocked() hard-blocks
   // the narrow window already (this code path never even runs then,
   // since the EA skips setup generation entirely) — this only fires in
   // the wider WARNING band around the block window.
   if(m_newsFilter != NULL)
     {
      string newsLabel; int newsMinutes;
      ENUM_NEWS_RISK tier = m_newsFilter.GetRiskTier(newsLabel, newsMinutes);
      if(tier == NEWS_WARNING)
         score *= m_newsWarningMultiplier;
     }
   score += 15.0 * FVGScore(forBuy);
   score += 15.0 * TrendScore(forBuy);

   if(m_requirePremiumDiscount)
     {
      double price = CurrentPrice();
      if(price > 0 && !CPremiumDiscount::OK(forBuy, price, ind.leg))
         return 0.0;
     }

   if(m_requireDistribution)
     {
      if(m_phase.Detect() != PHASE_DISTRIBUTION)
         return 0.0;
     }

   // v2.6 gates — see ConfigureVolumeFibonacci()'s comment for why both
   // default OFF. When ON, a fail here zeroes confidence exactly like the
   // premium/discount and phase gates above; nothing downstream can undo
   // that with a high inducement score. When passed (or disabled), a
   // small capped bonus nudges ranking only.
   if(m_requireVolumeConfirmation)
     {
      if(m_bosCtx == NULL || m_bosCtx.volume.RVOL(1) < m_rvolThreshold) // FIX #16: shift 1, see VolumeScore() above
         return 0.0;
     }
   if(m_requireFibonacciZone)
     {
      double price = CurrentPrice();
      if(price <= 0 || m_bosCtx == NULL ||
         !m_bosCtx.fibonacci.InPullbackZone(forBuy, price, m_fibZoneMinPct, m_fibZoneMaxPct))
         return 0.0;
     }
   // v2.20: hard-block only a validated profile contradiction. Being
   // outside VAH/VAL is not itself a rejection because accepted breakouts
   // are legitimate on trend-following setups.
   if(m_blockValueAreaContradictions && m_srCtx != NULL)
     {
      double price = CurrentPrice();
      if(price > 0 && m_srCtx.valueArea.IsValid() &&
         m_srCtx.valueArea.HardConflict(forBuy, price))
         return 0.0;
     }
   if(m_requireValueAreaLocation)
     {
      double price = CurrentPrice();
      if(price <= 0 || m_srCtx == NULL || !m_srCtx.valueArea.IsValid() ||
         !m_srCtx.valueArea.LocationOK(forBuy, price))
         return 0.0;
     }
   // v2.8 gates — same "fail-closed on unverifiable, hard-zero on
   // confirmed-wrong" discipline as the v2.6 block above. Both OFF by
   // default (see ConfigureHtfOrderBlock()/ConfigureVolatilityRegime()).
   if(m_requireHtfOB)
     {
      if(OBScore(forBuy) <= 0.0)
         return 0.0;
     }
   if(m_blockLowVolRegime)
     {
      ENUM_VOL_REGIME regime = m_volRegime.Classify(0);
      if(regime == VOL_REGIME_LOW)
         return 0.0;
      // VOL_REGIME_UNDEFINED (not enough ATR history) fails OPEN here,
      // deliberately inconsistent with the fail-closed CONFIRMATION rule
      // elsewhere: this is a data-availability gap, not a claim the setup
      // failed to confirm, and early-history warm-up shouldn't zero every
      // setup for the first `lookback` bars of a backtest.
     }

   score += 5.0 * VolumeScore(forBuy);
   score += 5.0 * FibonacciScore(forBuy);
   score += 5.0 * ValueAreaScore(forBuy);
   score += 5.0 * OBScore(forBuy);

   // FIX (audit #21 -- scoring model drift): real max raw score is 120
   // (70 inducement + 15 FVG + 15 Trend + 5+5+5+5 Vol/Fib/VA/OB), not the
   // 100 the old MathMin(score,100) clip implied. A hard clip means a
   // setup scoring 105 and one scoring 120 both reported as confidence
   // 100 -- indistinguishable to InpMinConfidenceExecute,
   // InpFullRiskConfidence, the dashboard, and the published signal, even
   // though one was meaningfully stronger. Rescaling against the TRUE
   // achievable maximum instead preserves relative ranking; confidence
   // 100 now only occurs when every component is actually maxed.
   const double MAX_RAW_SCORE = 120.0;
   double normalized = (score / MAX_RAW_SCORE) * 100.0;
   return MathMin(MathMax(normalized, 0.0), 100.0);
  }
//+------------------------------------------------------------------+
double CScoringEngine::PipSize()
  {
   if(m_priceRef == NULL) return 0.0001;
   // v2.9: delegates to CPipCalculator so this is the same definition
   // everywhere (Telegram payload, dashboard) instead of a locally
   // re-derived one. Behavior is unchanged — same formula as before.
   return CPipCalculator::PipSize(m_priceRef.Symbol());
  }
//+------------------------------------------------------------------+
void CScoringEngine::EvaluateReasons(bool forBuy, SetupReasons &out)
  {
   ZeroMemory(out);

   // Evidence authority: these fields must describe the same inducement
   // result that CalculateConfidence() uses. Do not reconstruct sweep/BOS
   // evidence through the legacy detectors here; doing so creates a second
   // representation of the same event and makes downstream consumers
   // vulnerable to accidental double-counting.
   InducementResult ind = m_inducement.Validate(forBuy);
   out.smc_inducement = ind;
   out.inducement_valid = ind.valid;
   out.bos_confirmed = ind.bosConfirmed;
   out.liquidity_swept = ind.sweepFound;
   out.trend_aligned   = (TrendScore(forBuy) >= 0.6);
   out.fresh_fvg       = (FVGScore(forBuy) > 0.0);
   out.sr_confluence   = (SRScore(forBuy) > 0.0);
   out.phase = m_phase.Detect();

   double price = CurrentPrice();
   out.premium_discount_ok = (price > 0) ? CPremiumDiscount::OK(forBuy, price, ind.leg) : true;

   // v2.6 diagnostics — always populated (dashboard/CSV visibility) even
   // when the corresponding gate in CalculateConfidence is disabled.
   if(m_bosCtx != NULL)
     {
      out.rvol = m_bosCtx.volume.RVOL(1); // FIX #16: shift 1, see VolumeScore() above -- diagnostics must match the live gate
      out.volume_confirmed = (out.rvol >= m_rvolThreshold);
      if(price > 0)
        {
         out.fib_zone = m_bosCtx.fibonacci.Zone(forBuy, price);
         out.fib_in_zone = m_bosCtx.fibonacci.InPullbackZone(forBuy, price, m_fibZoneMinPct, m_fibZoneMaxPct);
         double pctOut;
         out.fib_nearest_level = m_bosCtx.fibonacci.NearestLevel(forBuy, price, pctOut);
        }
     }

   if(m_srCtx != NULL && m_srCtx.valueArea.IsValid())
     {
      out.value_area_ok = m_srCtx.valueArea.LocationOK(forBuy, price);
      out.va_zone = m_srCtx.valueArea.Zone(price);
      out.va_poc = m_srCtx.valueArea.POC();
      out.va_high = m_srCtx.valueArea.VAH();
      out.va_low = m_srCtx.valueArea.VAL();
      out.value_profile_source = m_srCtx.valueArea.Source();
      out.value_profile_state = m_srCtx.valueArea.State();
      out.va_poc_migration_atr = m_srCtx.valueArea.POCMigrationATR();
      out.va_source_quality = m_srCtx.valueArea.SourceQuality();
      out.va_score = m_srCtx.valueArea.Score(forBuy, price);
      out.value_area_contradiction = m_srCtx.valueArea.HardConflict(forBuy, price);
     }

   // v2.8 diagnostics — always populated regardless of gate state, same
   // convention as the v2.6 block above.
   out.htf_ob_confluence = (OBScore(forBuy) > 0.0);
   if(m_htfObCtx != NULL && price > 0)
     {
      double atr = m_htfObCtx.candles.GetATR(0);
      OrderBlockZone z;
      if(atr > 0 && m_htfObCtx.orderBlock.NearestZone(forBuy ? FVG_BULL : FVG_BEAR, price, atr, m_obDistATRMax, z))
         out.htf_ob_state = z.state;
     }
   out.vol_regime = m_volRegime.Classify(0);
   out.session = m_sessionFilter.CurrentSession();
   out.session_ok = m_sessionFilter.IsAllowed();

   // v2.9 diagnostics — always populated regardless of gate state, same
   // convention as the v2.6/v2.8 blocks above.
   out.sweep_grade = ind.sweepGrade;
   out.bos_strength = ind.bosStrength;
   out.time_decay = ind.timeDecay;
   out.chase_dist_atr = 0.0;
   out.chase_ok = true;
   if(ind.bosBarIndex >= 0 && m_bosCtx != NULL && price > 0)
     {
      double atrB = m_bosCtx.candles.GetATR(0);
      if(atrB > 0)
        {
         out.chase_dist_atr = (forBuy ? (price - ind.bosClosePrice) : (ind.bosClosePrice - price)) / atrB;
         out.chase_ok = (out.chase_dist_atr <= m_maxChaseDistATR);
        }
     }

   out.news_risk = NEWS_NONE;
   out.news_label = "";
   out.news_minutes_to_event = 0;
   if(m_newsFilter != NULL)
      out.news_risk = m_newsFilter.GetRiskTier(out.news_label, out.news_minutes_to_event);

   out.risk_warning = "";
   if(m_srCtx == NULL || m_priceRef == NULL || m_priceRef.Total() == 0) return;

   double pip = PipSize();
   if(pip <= 0) pip = 0.0001;
   double bestDist = -1.0;
   ENUM_SR_TYPE bestType = SR_MINOR_RESISTANCE;
   int bestTouches = 0;

   for(int i = 0; i < m_srCtx.sr.Count(); i++)
     {
      SRZone z = m_srCtx.sr.GetZone(i);
      bool isResistance = (z.type == SR_MAJOR_RESISTANCE || z.type == SR_MINOR_RESISTANCE);
      bool isSupport = (z.type == SR_MAJOR_SUPPORT || z.type == SR_MINOR_SUPPORT);
      double mid = (z.top + z.bottom) / 2.0;

      if(forBuy && isResistance && mid > price)
        {
         double dist = (mid - price) / pip;
         if(bestDist < 0 || dist < bestDist) { bestDist = dist; bestType = z.type; bestTouches = z.touches; }
        }
      else if(!forBuy && isSupport && mid < price)
        {
         double dist = (price - mid) / pip;
         if(bestDist < 0 || dist < bestDist) { bestDist = dist; bestType = z.type; bestTouches = z.touches; }
        }
     }

   if(bestDist >= 0 && bestDist <= 60.0)
     {
      string strength = (bestType == SR_MAJOR_RESISTANCE || bestType == SR_MAJOR_SUPPORT) ? "High-impact" : "Minor";
      string kind = forBuy ? "resistance" : "support";
      out.risk_warning = StringFormat("%s %s %.0f pips away (%d touches)", strength, kind, bestDist, bestTouches);
     }
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureLearnedDiagnostics(double contradictionWeight, double envWeight, double execWeight)
  {
   m_contradictionWeight = MathMax(0.0, contradictionWeight);
   m_envWeight  = MathMin(MathMax(envWeight, 0.0), 1.0);
   m_execWeight = MathMin(MathMax(execWeight, 0.0), 1.0);
  }
//+------------------------------------------------------------------+
// v2.10 - CONTRADICTION, not absence. The additive model's failure mode is
// that a missing component costs the same as a component actively pointing
// the other way: a setup with no HTF read and a setup fighting the HTF
// trend score identically. This counts only actively-opposing conditions,
// so "unknown" and "wrong" stop being the same number. Returns 0-1.
double CScoringEngine::ContradictionPenalty(const SetupReasons &r)
  {
   int hits = 0;
   if(!r.trend_aligned)               hits++; // trend does not support the direction
   if(!r.premium_discount_ok)         hits++; // buying premium / selling discount
   if(!r.chase_ok)                    hits++; // price already ran past the BOS close
   if(r.vol_regime == VOL_REGIME_LOW) hits++; // thin, chop-prone regime
   if(!r.session_ok)                  hits++; // outside the allowed liquidity hours
   if(r.news_risk != NEWS_NONE)       hits++; // inside a news risk tier
   if(r.htf_ob_state == OB_MITIGATED) hits++; // the HTF OB this leans on is already spent
   if(r.value_area_contradiction)      hits++; // profile actively rejects the thesis
   if(hits == 0) return 0.0;
   double penalty = m_contradictionWeight * (double)hits;
   return MathMin(MathMax(penalty, 0.0), 1.0);
  }
//+------------------------------------------------------------------+
// v2.10 - "is the market itself suitable right now", independent of this
// particular entry. Multiplicative by design: a perfect entry in an
// unsuitable environment should not score like a perfect entry in a
// suitable one, which is exactly what adding points cannot express.
double CScoringEngine::EnvironmentScore(const SetupReasons &r)
  {
   double s = 1.0;
   if(r.vol_regime == VOL_REGIME_LOW)            s *= 0.60;
   else if(r.vol_regime == VOL_REGIME_HIGH)      s *= 0.90; // tradeable, but stops get run
   else if(r.vol_regime == VOL_REGIME_UNDEFINED) s *= 0.85; // warm-up: unknown rather than bad
   if(!r.session_ok)                             s *= 0.70;
   if(r.news_risk == NEWS_WARNING)               s *= 0.80;
   else if(r.news_risk == NEWS_BLOCKED)          s *= 0.50; // the hard block already stops entries; this only shapes the diagnostic
   // m_envWeight blends toward neutral 1.0, so 0 disables the component's
   // influence without needing a separate on/off flag.
   return MathMin(MathMax(1.0 - m_envWeight * (1.0 - s), 0.0), 1.0);
  }
//+------------------------------------------------------------------+
// v2.10 - "how good is THIS entry", given the environment is acceptable.
// Built from the v2.9 continuous reads (sweep grade, BOS strength, time
// decay) that the additive model currently collapses into pass/fail.
double CScoringEngine::ExecutionScore(const SetupReasons &r)
  {
   double grade = 0.40; // no graded sweep
   switch(r.sweep_grade)
     {
      case SWEEP_GRADE_A: grade = 1.00; break;
      case SWEEP_GRADE_B: grade = 0.80; break;
      case SWEEP_GRADE_C: grade = 0.55; break;
      default:            grade = 0.40; break;
     }
   double strength = MathMin(MathMax(r.bos_strength, 0.0), 1.0);
   double freshness = MathMin(MathMax(r.time_decay, 0.0), 1.0);
   if(freshness <= 0.0) freshness = 1.0; // 0 means "not computed", not "infinitely stale"
   double s = grade * (0.5 + 0.5 * strength) * freshness;
   if(!r.fresh_fvg) s *= 0.85;
   if(!r.chase_ok)  s *= 0.75;
   return MathMin(MathMax(1.0 - m_execWeight * (1.0 - s), 0.0), 1.0);
  }
//+------------------------------------------------------------------+
void CScoringEngine::PopulateConfidenceDiagnostics(SetupReasons &out, double confidence)
  {
   out.contradiction_penalty = ContradictionPenalty(out);
   out.env_score = EnvironmentScore(out);
   out.exec_score = ExecutionScore(out);
   double c = MathMin(MathMax(confidence, 0.0), 100.0);
   out.env_exec_confidence = c * out.env_score * out.exec_score * (1.0 - out.contradiction_penalty);
  }
//+------------------------------------------------------------------+
void CScoringEngine::ConfigureStrategyDiagnostics(int momentumBreakoutRecencyBars, int liqOverlapBars,
                                                  int extensionLookbackBars, double exhaustionATRMult,
                                                  int momentumLookbackBars)
  {
   m_momentumEngine.Configure(momentumBreakoutRecencyBars, liqOverlapBars, extensionLookbackBars,
                              exhaustionATRMult, momentumLookbackBars);
  }
//+------------------------------------------------------------------+
// v2.13. Passthrough, same shape as ConfigureStrategyDiagnostics above.
void CScoringEngine::ConfigureMeanReversionDiagnostics(double minStretchATR, double srZoneATRTolerance,
                                                       double wickRejectionRatio, int liqRecencyBars,
                                                       int trendConflictRecencyBars, double trendConflictMinStrength)
  {
   m_meanReversionEngine.Configure(minStretchATR, srZoneATRTolerance, wickRejectionRatio,
                                   liqRecencyBars, trendConflictRecencyBars, trendConflictMinStrength);
  }
//+------------------------------------------------------------------+
// v2.14. Passthrough, same shape as the two Configure methods above.
// v2.17: roundStep passthrough to CExtendedKeyLevels added.
void CScoringEngine::ConfigureKeyLevelDiagnostics(int lookbackBars, double levelSearchATRMax,
                                                  double touchToleranceATRMult, int absorptionMinTouches,
                                                  double wickRejectionRatio, double roundStep)
  {
   m_keyLevelEngine.Configure(lookbackBars, levelSearchATRMax, touchToleranceATRMult,
                              absorptionMinTouches, wickRejectionRatio);
   m_extendedKeyLevels.Configure(roundStep);
  }
//+------------------------------------------------------------------+
// v2.15. Passthrough, same shape as the three Configure methods above.
void CScoringEngine::ConfigureStrategySelection(double minSelectionScore)
  {
   m_strategySelector.Configure(minSelectionScore);
  }
//+------------------------------------------------------------------+
// v2.12. Deliberately separate from PopulateConfidenceDiagnostics() even
// though both are called from the same two call sites in
// Trading/TradeZone.mqh — that one reads fields EvaluateReasons() just
// set, this one runs two independent engines. Keeping them as two
// methods (rather than folding this into PopulateConfidenceDiagnostics)
// means a future change to one can't silently change what the other
// logs, and matches this class's existing pattern of one method per
// diagnostic generation added (v2.10 got its own method; this does too).
//+------------------------------------------------------------------+
// Diagnostic-only SMC structural validation. This method never changes
// confidence or strategy selection; it populates a separate evidence
// record so outcomes can be conditioned on structural truth.
void CScoringEngine::PopulateStructuralValidation(bool forBuy, SetupReasons &out)
  {
   m_smcValidator.Configure(m_fvgMaxDistATR, m_obDistATRMax);
   InducementResult ind = out.smc_inducement;
   SMCStructuralValidation v = m_smcValidator.Validate(forBuy, ind, CurrentPrice(),
                                                        out.regime, out.premium_discount_ok);

   out.smc_state = v.state;
   out.smc_structural_valid = v.structural_valid;
   out.smc_htf_structure_valid = v.htf_structure_valid;
   out.smc_regime_applicable = v.regime_applicable;
   out.smc_liquidity_target_valid = v.liquidity_target_valid;
   out.smc_sweep_valid = v.sweep_valid;
   out.smc_displacement_valid = v.displacement_valid;
   out.smc_bos_valid = v.bos_valid;
   out.smc_fvg_causal = v.fvg_causal;
   out.smc_order_block_causal = v.order_block_causal;
   out.smc_htf_ob_present = v.htf_ob_present;
   out.smc_premium_discount_valid = v.premium_discount_valid;
   out.smc_freshness_valid = v.freshness_valid;
   out.smc_invalidation_clear = v.invalidation_clear;
   out.smc_protected_level = v.protected_level;
   out.smc_invalidation_level = v.invalidation_level;
   out.smc_sweep_bar_index = v.sweep_bar_index;
   out.smc_bos_bar_index = v.bos_bar_index;
   out.smc_displacement_bar_index = v.displacement_bar_index;
   out.smc_entry_fvg_bar_index = v.entry_fvg_bar_index;
   out.smc_causal_ob_bar_index = v.causal_ob_bar_index;
   out.smc_failure_reason = v.failure_reason;
  }
//+------------------------------------------------------------------+
void CScoringEngine::PopulateStrategyDiagnostics(bool forBuy, double confidence, SetupReasons &out)
  {
   out.regime = m_regimeDetector.Classify();
   m_momentumEngine.Evaluate(forBuy, out.momentum_score, out.breakout_score, out.breakout_class);
   // v2.13: independent second strategy score, same call site, same
   // "never feeds back" discipline as the momentum/breakout call above.
   m_meanReversionEngine.Evaluate(forBuy, out.reversion_score, out.reversion_class);
   // v2.14: third independent strategy score, same call site, same
   // "never feeds back" discipline as the two calls above.
   m_keyLevelEngine.Evaluate(forBuy, out.keylevel_source, out.keylevel_reaction, out.keylevel_score);
   // v2.15: runs LAST, after every score above is populated on `out` —
   // compares them, never sums them. See Strategies/StrategySelector.mqh
   // for why that distinction is the entire point of this class. Still
   // never feeds back into `confidence` itself — it only writes to
   // out.selected_strategy / out.selected_strategy_score.
   m_strategySelector.Select(out, confidence, out.selected_strategy, out.selected_strategy_score);
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Analysis/Scoring.mqh
// BEGIN INLINED MODULE: includes/Trading/StrategyTradeZone.mqh
//+------------------------------------------------------------------+
//| Trading/StrategyTradeZone.mqh                                    |
//| Regime-first peer strategy routing and setup construction.        |
//+------------------------------------------------------------------+
#ifndef STRATEGYTRADEZONE_MQH
#define STRATEGYTRADEZONE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/CandleData.mqh
// already inlined once under include guard: includes/Analysis/TFContext.mqh
// already inlined once under include guard: includes/Analysis/Scoring.mqh
// BEGIN INLINED MODULE: includes/Trading/StrategySetupBuilders.mqh
//+------------------------------------------------------------------+
//| Trading/StrategySetupBuilders.mqh                                |
//| Strategy-owned TradeSetup construction boundary.                 |
//+------------------------------------------------------------------+
#ifndef STRATEGYSETUPBUILDERS_MQH
#define STRATEGYSETUPBUILDERS_MQH
// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Analysis/TFContext.mqh
// BEGIN INLINED MODULE: includes/Trading/Targets.mqh
//+------------------------------------------------------------------+
//|                                                Trading/Targets.mqh |
//+------------------------------------------------------------------+
#ifndef TARGETS_MQH
#define TARGETS_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Analysis/TFContext.mqh

// Ranks resting liquidity by "how big a stop hunt would this be" and lays
// TP1/TP2/TP3 out along that ladder instead of fixed ATR multiples:
//   TP1 = nearest internal pool (equal highs/lows)      priority 75
//   TP2 = nearest external D1 high/low                  priority 90
//   TP3 = weekly high/low                                priority 100
// Any tier with no valid candidate (must be beyond price in the trade's
// direction, and — where a tier already exists before it — beyond the
// previous tier) falls back to an ATR step so a thin liquidity map never
// blocks target assignment outright.
class CTargetSelector
  {
private:
   static bool       NearestBeyond(CTFContext* liqCtx, bool wantInternal, bool forBuy,
                                   double entryPrice, double excludeBeyond, bool haveExclude,
                                   double &outPrice);
   static bool       WeeklyLevel(string symbol, bool forBuy, double &outPrice);

public:
   static void       AssignTargets(TradeSetup &setup, CTFContext* liqCtx, string symbol,
                                   double atr, double entryPrice);
  };
//+------------------------------------------------------------------+
// Scans liquidity pools for the nearest one on the correct side of price
// (LIQ_BUY_SIDE pools sit above price and are the natural target for a
// buy; LIQ_SELL_SIDE pools sit below and target a sell), optionally
// requiring it to sit beyond an already-chosen level (so TP2 can't land
// behind TP1).
bool CTargetSelector::NearestBeyond(CTFContext* liqCtx, bool wantInternal, bool forBuy,
                                    double entryPrice, double excludeBeyond, bool haveExclude,
                                    double &outPrice)
  {
   outPrice = 0.0;
   if(liqCtx == NULL) return false;
   double best = 0.0;
   bool have = false;

   for(int i = 0; i < liqCtx.liquidity.PoolCount(); i++)
     {
      LiquidityPool p = liqCtx.liquidity.GetPool(i);
      if(p.external == wantInternal) continue; // wantInternal=true means we want external==false
      double price = forBuy ? p.price_top : p.price_bottom;
      bool onRightSide = forBuy ? (price > entryPrice) : (price < entryPrice);
      if(!onRightSide) continue;
      if(haveExclude)
        {
         bool beyondPrior = forBuy ? (price > excludeBeyond) : (price < excludeBeyond);
         if(!beyondPrior) continue;
        }
      bool better = !have || (forBuy ? (price < best) : (price > best)); // nearest = smallest distance
      if(better) { best = price; have = true; }
     }
   if(have) outPrice = best;
   return have;
  }
//+------------------------------------------------------------------+
bool CTargetSelector::WeeklyLevel(string symbol, bool forBuy, double &outPrice)
  {
   double v = forBuy ? iHigh(symbol, PERIOD_W1, 1) : iLow(symbol, PERIOD_W1, 1);
   if(v <= 0) return false;
   outPrice = v;
   return true;
  }
//+------------------------------------------------------------------+
void CTargetSelector::AssignTargets(TradeSetup &setup, CTFContext* liqCtx, string symbol,
                                    double atr, double entryPrice)
  {
   bool forBuy = (setup.type == ORDER_TYPE_BUY);
   double tp1, tp2, tp3;

   // TP1: nearest internal (equal highs/lows) pool.
   if(!NearestBeyond(liqCtx, true, forBuy, entryPrice, 0.0, false, tp1))
      tp1 = forBuy ? entryPrice + 2.0 * atr : entryPrice - 2.0 * atr;

   // TP2: nearest external (D1) pool beyond TP1.
   if(!NearestBeyond(liqCtx, false, forBuy, entryPrice, tp1, true, tp2))
      tp2 = forBuy ? tp1 + atr : tp1 - atr;

   // TP3: weekly high/low beyond TP2.
   double weekly;
   if(WeeklyLevel(symbol, forBuy, weekly) && (forBuy ? (weekly > tp2) : (weekly < tp2)))
      tp3 = weekly;
   else
      tp3 = forBuy ? tp2 + atr : tp2 - atr;

   setup.tp1 = tp1;
   setup.tp2 = tp2;
   setup.final_tp = tp3;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/Targets.mqh
class CStrategySetupBuilders
  {
private:
   static bool FindRecentBOS(CTFContext* bosCtx,bool forBuy,BOSEvent &out,int maxBars=20){if(bosCtx==NULL)return false;for(int i=0;i<bosCtx.bos.Count();i++){BOSEvent ev=bosCtx.bos.GetBOS(i);if(ev.bar_index>maxBars)break;if(ev.is_bullish==forBuy){out=ev;return true;}}return false;}
   static bool FindNearestSR(CTFContext* srCtx,bool forBuy,double price,double atr,double &level,int &touches){if(srCtx==NULL||atr<=0)return false;double best=DBL_MAX;bool found=false;touches=0;for(int i=0;i<srCtx.sr.Count();i++){SRZone z=srCtx.sr.GetZone(i);bool support=(z.type==SR_MAJOR_SUPPORT||z.type==SR_MINOR_SUPPORT);bool resistance=(z.type==SR_MAJOR_RESISTANCE||z.type==SR_MINOR_RESISTANCE);if(forBuy&&!support)continue;if(!forBuy&&!resistance)continue;double candidate=forBuy?z.top:z.bottom;double dist=MathAbs(price-candidate);if(dist<=3.0*atr&&dist<best){best=dist;level=candidate;touches=z.touches;found=true;}}return found;}
   static bool FindValueEdge(CTFContext* srCtx,bool forBuy,double price,double atr,double &edge,double &stretchATR){if(srCtx==NULL||!srCtx.valueArea.IsValid()||atr<=0)return false;edge=forBuy?srCtx.valueArea.VAL():srCtx.valueArea.VAH();stretchATR=forBuy?(edge-price)/atr:(price-edge)/atr;return stretchATR>=1.0;}
   static bool ValidateCandidate(TradeSetup &setup,bool forBuy){if(!setup.active)return false;if(!MathIsValidNumber(setup.entry_top)||!MathIsValidNumber(setup.entry_bottom)||!MathIsValidNumber(setup.invalidation)||!MathIsValidNumber(setup.stop_loss)||!MathIsValidNumber(setup.tp1)||!MathIsValidNumber(setup.tp2)||!MathIsValidNumber(setup.final_tp)||!MathIsValidNumber(setup.confidence))return false;if(setup.entry_top<setup.entry_bottom)return false;if(forBuy)return setup.invalidation<setup.entry_bottom&&setup.stop_loss<setup.invalidation&&setup.tp1>setup.entry_top&&setup.tp2>setup.tp1&&setup.final_tp>setup.tp2;return setup.invalidation>setup.entry_top&&setup.stop_loss>setup.invalidation&&setup.tp1<setup.entry_bottom&&setup.tp2<setup.tp1&&setup.final_tp<setup.tp2;}
public:
   static bool BuildMomentum(bool forBuy,double confidence,const SetupReasons &r,CTFContext* priceCtx,CTFContext* bosCtx,CTFContext* liqCtx,TradeSetup &out){ZeroMemory(out);if(r.regime!=REGIME_TRENDING||(r.breakout_class!=BREAKOUT_EXPANSION&&r.breakout_class!=BREAKOUT_LIQUIDITY)||priceCtx==NULL||bosCtx==NULL)return false;double price=priceCtx.candles.GetCandle(0).close,atr=bosCtx.candles.GetATR(0);if(price<=0||atr<=0)return false;BOSEvent bos;if(!FindRecentBOS(bosCtx,forBuy,bos))return false;double chase=forBuy?(price-bos.price)/atr:(bos.price-price)/atr;if(chase>0.75)return false;out.type=forBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;out.entry_top=price;out.entry_bottom=price;out.invalidation=bos.price;out.stop_loss=forBuy?bos.price-0.35*atr:bos.price+0.35*atr;CTargetSelector::AssignTargets(out,liqCtx,priceCtx.candles.Symbol(),atr,price);out.confidence=MathMax(0.0,MathMin(confidence,100.0));out.creation_time=TimeCurrent();out.active=true;out.reasons=r;out.reasons.risk_warning=StringFormat("Momentum owner: BOS %.5f, chase %.2f ATR",bos.price,chase);return ValidateCandidate(out,forBuy);}
   static bool BuildMeanReversion(bool forBuy,double confidence,const SetupReasons &r,CTFContext* priceCtx,CTFContext* srCtx,CTFContext* liqCtx,TradeSetup &out){ZeroMemory(out);if(r.regime!=REGIME_RANGING||(r.reversion_class!=REVERSION_VALUE_FADE&&r.reversion_class!=REVERSION_LEVEL_REJECTION)||priceCtx==NULL||srCtx==NULL)return false;double price=priceCtx.candles.GetCandle(0).close,atr=srCtx.candles.GetATR(0);if(price<=0||atr<=0)return false;double level=0,stretch=0;bool haveValue=FindValueEdge(srCtx,forBuy,price,atr,level,stretch);int touches=0;if(!haveValue&&!FindNearestSR(srCtx,forBuy,price,atr,level,touches))return false;if(r.reversion_class==REVERSION_VALUE_FADE&&!haveValue)return false;out.type=forBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;out.entry_top=level;out.entry_bottom=level;out.invalidation=forBuy?level-0.20*atr:level+0.20*atr;out.stop_loss=forBuy?level-0.40*atr:level+0.40*atr;CTargetSelector::AssignTargets(out,liqCtx,priceCtx.candles.Symbol(),atr,level);out.confidence=MathMax(0.0,MathMin(confidence,100.0));out.creation_time=TimeCurrent();out.active=true;out.reasons=r;out.reasons.risk_warning=StringFormat("Mean-reversion owner: reference %.5f%s",level,haveValue?StringFormat(", observed stretch %.2f ATR",stretch):"");return ValidateCandidate(out,forBuy);}
   static bool BuildKeyLevel(bool forBuy,double confidence,const SetupReasons &r,CTFContext* priceCtx,CTFContext* srCtx,CTFContext* liqCtx,TradeSetup &out){ZeroMemory(out);if(r.regime!=REGIME_TRANSITION||(r.keylevel_reaction!=REACTION_REJECTION&&r.keylevel_reaction!=REACTION_RETEST&&r.keylevel_reaction!=REACTION_FAILED_BREAK&&r.keylevel_reaction!=REACTION_ABSORPTION)||priceCtx==NULL||srCtx==NULL)return false;double price=priceCtx.candles.GetCandle(0).close,atr=srCtx.candles.GetATR(0);if(price<=0||atr<=0)return false;double level=0;int touches=0;if(!FindNearestSR(srCtx,forBuy,price,atr,level,touches))return false;out.type=forBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;out.entry_top=level;out.entry_bottom=level;out.invalidation=forBuy?level-0.20*atr:level+0.20*atr;out.stop_loss=forBuy?level-0.40*atr:level+0.40*atr;CTargetSelector::AssignTargets(out,liqCtx,priceCtx.candles.Symbol(),atr,level);out.confidence=MathMax(0.0,MathMin(confidence,100.0));out.creation_time=TimeCurrent();out.active=true;out.reasons=r;out.reasons.risk_warning=StringFormat("Key-level owner: level %.5f, %d touches, reaction %s",level,touches,EnumToString(r.keylevel_reaction));return ValidateCandidate(out,forBuy);}
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/StrategySetupBuilders.mqh
// already inlined once under include guard: includes/Trading/Targets.mqh
// BEGIN INLINED MODULE: includes/Trading/EnvironmentStrategyMemory.mqh
//+------------------------------------------------------------------+
//| Trading/EnvironmentStrategyMemory.mqh                            |
//+------------------------------------------------------------------+
#ifndef ENVIRONMENTSTRATEGYMEMORY_MQH
#define ENVIRONMENTSTRATEGYMEMORY_MQH
// already inlined once under include guard: includes/Core/Config.mqh

struct EnvironmentMemoryEvidence
  { int trades; int wins; int losses; int scratches; double win_rate; double avg_r; double profit_factor; double max_drawdown_r; double avg_mae_r; double avg_mfe_r; double avg_duration; double wilson_low; double wilson_high; int sample_size; string status; double adjustment; };
struct EnvironmentMemoryRecord
  { datetime timestamp; string environment_key; int strategy; double realized_r; double mae_r; double mfe_r; int duration; bool counted; };

class CEnvironmentStrategyMemory
  {
private:
   EnvironmentMemoryRecord m_records[]; string m_filename; int m_minSample; int m_degradedMinSample; double m_bonus; double m_penalty; bool m_persistent;
   string Bucket(double value,double a,double b,double c) const {if(value<a)return "0";if(value<b)return "1";if(value<c)return "2";return "3";}
   string EnvironmentKey(const SetupReasons &r) const {double spreadAtr=0.0;if(r.atr_value>0.0&&r.point_size>0.0)spreadAtr=r.spread_points*r.point_size/r.atr_value;string structure=EnumToString(r.sweep_grade)+"/"+IntegerToString((int)r.breakout_class)+"/"+IntegerToString((int)r.reversion_class)+"/"+IntegerToString((int)r.keylevel_reaction);string trendBucket=Bucket(MathAbs(r.trend_strength),0.25,0.60,0.85);return EnumToString(r.regime)+"|"+EnumToString(r.vol_regime)+"|T"+trendBucket+"|L"+IntegerToString(r.liquidity_bucket)+"|N"+EnumToString(r.news_risk)+"|S"+EnumToString(r.session)+"|SP"+Bucket(spreadAtr,0.02,0.05,0.10)+"|A"+EnumToString(r.vol_regime)+"|H"+(r.htf_ob_confluence?"1":"0")+"/"+IntegerToString((int)r.htf_ob_state)+"|V"+EnumToString(r.va_zone)+"|P"+EnumToString(r.phase)+"|M"+structure;}
   static double WilsonZ(){return 1.959963984540054;}
   double WilsonLower(int wins,int n) const {if(n<=0)return 0.0;double z=WilsonZ(),p=(double)wins/n,den=1.0+z*z/n,center=p+z*z/(2.0*n),spread=z*MathSqrt((p*(1.0-p)/n)+(z*z/(4.0*n*n)));return (center-spread)/den;}
   double WilsonUpper(int wins,int n) const {if(n<=0)return 0.0;double z=WilsonZ(),p=(double)wins/n,den=1.0+z*z/n,center=p+z*z/(2.0*n),spread=z*MathSqrt((p*(1.0-p)/n)+(z*z/(4.0*n*n)));return (center+spread)/den;}
   void Save() const {if(!m_persistent||StringLen(m_filename)==0)return;int h=FileOpen(m_filename,FILE_CSV|FILE_WRITE|FILE_ANSI,',');if(h==INVALID_HANDLE)return;FileWrite(h,"timestamp","environment_key","strategy","realized_r","mae_r","mfe_r","duration","counted");for(int i=0;i<ArraySize(m_records);i++)FileWrite(h,(long)m_records[i].timestamp,m_records[i].environment_key,m_records[i].strategy,m_records[i].realized_r,m_records[i].mae_r,m_records[i].mfe_r,m_records[i].duration,m_records[i].counted?1:0);FileClose(h);}
   void Load(){ArrayFree(m_records);if(!m_persistent||StringLen(m_filename)==0||!FileIsExist(m_filename))return;int h=FileOpen(m_filename,FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_ANSI,',');if(h==INVALID_HANDLE)return;for(int c=0;c<8&&!FileIsEnding(h);c++)FileReadString(h);while(!FileIsEnding(h)){string ts=FileReadString(h);if(StringLen(ts)==0)break;EnvironmentMemoryRecord r;ZeroMemory(r);r.timestamp=(datetime)StringToInteger(ts);r.environment_key=FileReadString(h);r.strategy=(int)StringToInteger(FileReadString(h));r.realized_r=StringToDouble(FileReadString(h));r.mae_r=StringToDouble(FileReadString(h));r.mfe_r=StringToDouble(FileReadString(h));r.duration=(int)StringToInteger(FileReadString(h));r.counted=(StringToInteger(FileReadString(h))!=0);int n=ArraySize(m_records);ArrayResize(m_records,n+1);m_records[n]=r;}FileClose(h);}
public:
   CEnvironmentStrategyMemory():m_filename(""),m_minSample(30),m_degradedMinSample(60),m_bonus(2.0),m_penalty(2.0),m_persistent(true){}
   void Init(string symbol,int minSample=30,double bonus=2.0,double penalty=2.0){m_filename="MedisTouch_EnvironmentMemory_"+symbol+".csv";m_minSample=MathMax(1,minSample);m_degradedMinSample=m_minSample*2;m_bonus=MathMax(0.0,bonus);m_penalty=MathMax(0.0,penalty);m_persistent=(MQLInfoInteger(MQL_TESTER)==0);Load();}
   string Key(const SetupReasons &r) const{return EnvironmentKey(r);}
   void RecordOutcome(const SetupReasons &r,ENUM_SELECTED_STRATEGY strategy,double realizedR,double maeR,double mfeR,int duration,datetime timestamp){if(strategy==STRATEGY_NONE)return;EnvironmentMemoryRecord rec;ZeroMemory(rec);rec.timestamp=timestamp;rec.environment_key=EnvironmentKey(r);rec.strategy=(int)strategy;rec.realized_r=realizedR;rec.mae_r=maeR;rec.mfe_r=mfeR;rec.duration=MathMax(0,duration);rec.counted=true;int n=ArraySize(m_records);ArrayResize(m_records,n+1);m_records[n]=rec;Save();}
   bool GetEvidence(const SetupReasons &r,ENUM_SELECTED_STRATEGY strategy,EnvironmentMemoryEvidence &out) const {ZeroMemory(out);if(strategy==STRATEGY_NONE)return false;string key=EnvironmentKey(r);double cumulative=0.0,peak=0.0;double sumR=0.0,sumMAE=0.0,sumMFE=0.0,sumDuration=0.0,grossProfit=0.0,grossLoss=0.0;int n=0,wins=0,losses=0,scratches=0;for(int i=0;i<ArraySize(m_records);i++){EnvironmentMemoryRecord rec=m_records[i];if(!rec.counted||rec.strategy!=(int)strategy||rec.environment_key!=key)continue;n++;sumR+=rec.realized_r;sumMAE+=rec.mae_r;sumMFE+=rec.mfe_r;sumDuration+=rec.duration;cumulative+=rec.realized_r;if(cumulative>peak)peak=cumulative;double dd=peak-cumulative;if(dd>out.max_drawdown_r)out.max_drawdown_r=dd;if(rec.realized_r>0.0){wins++;grossProfit+=rec.realized_r;}else if(rec.realized_r<0.0){losses++;grossLoss+=-rec.realized_r;}else scratches++;}out.trades=n;out.wins=wins;out.losses=losses;out.scratches=scratches;out.sample_size=wins+losses;out.win_rate=out.sample_size>0?(double)wins/out.sample_size:0.0;out.avg_r=n>0?sumR/n:0.0;out.profit_factor=grossLoss>0.0?grossProfit/grossLoss:(grossProfit>0.0?999999.0:0.0);out.avg_mae_r=n>0?sumMAE/n:0.0;out.avg_mfe_r=n>0?sumMFE/n:0.0;out.avg_duration=n>0?sumDuration/n:0.0;out.wilson_low=WilsonLower(wins,out.sample_size);out.wilson_high=WilsonUpper(wins,out.sample_size);if(out.sample_size<m_minSample){out.status="UNKNOWN";out.adjustment=0.0;return n>0;}bool qualified=(out.avg_r>0.0&&out.profit_factor>1.0&&out.wilson_low>=0.50);bool degraded=(out.sample_size>=m_degradedMinSample&&out.avg_r<0.0&&out.profit_factor>=0.0&&out.profit_factor<1.0&&out.wilson_high<0.50);if(qualified){out.status="QUALIFIED";out.adjustment=m_bonus;}else if(degraded){out.status="DEGRADED";out.adjustment=-m_penalty;}else{out.status="NEUTRAL";out.adjustment=0.0;}return true;}
   int Count() const{return ArraySize(m_records);} int MinimumSample() const{return m_minSample;} int DegradedMinimumSample() const{return m_degradedMinSample;}
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/EnvironmentStrategyMemory.mqh

extern CTFContext* g_chartCtx;
extern CTFContext* g_trendCtx;
extern CTFContext* g_bosCtx;

class CTradeDecision
  {
private:
   CCandleData*                    m_priceRef;
   CTFContext*                     m_fvgCtx;
   CTFContext*                     m_liqCtx;
   CTFContext*                     m_srCtx;
   CTFContext*                     m_bosCtx;
   CScoringEngine*                 m_scoring;
   CEnvironmentStrategyMemory*     m_environmentMemory;
   TradeSetup                      m_lastSetup;
   double                          m_slBufferATR;
   double                          m_minStopSpreadMult;
   double                          m_fvgMaxDistATR;
   double                          m_minSelectionScore;
   bool                            m_requireSmcStructuralValidity;

   bool FindEntryFVG(ENUM_FVG_DIR dir,FVGZone &out,int requiredBarIndex=-1);
   double EnforceSpreadFloor(string symbol,double entry,double stopLoss,bool isBuy);
   void PopulateStrategyReads(bool forBuy,SetupReasons &out);
   void SelectPeerStrategy(bool forBuy,SetupReasons &reasons,ENUM_SELECTED_STRATEGY &selected,double &selectedScore);
   TradeSetup BuildSMC(bool forBuy,double confidence,const SetupReasons &reasons);
   bool BuildNonSMC(bool forBuy,ENUM_SELECTED_STRATEGY selected,double confidence,const SetupReasons &reasons,TradeSetup &out);
   TradeSetup BuildAuthoritativeStrategy(bool forBuy);

public:
   CTradeDecision();
   void Init(CCandleData* priceRef,CTFContext* fvgCtx,CTFContext* liqCtx,CScoringEngine* scoring,double slBufferATR=0.25,double minStopSpreadMult=3.0,double fvgMaxDistATR=1.25,double minSelectionScore=60.0,CTFContext* srCtx=NULL,CTFContext* bosCtx=NULL,CEnvironmentStrategyMemory* environmentMemory=NULL);
   TradeSetup GenerateBuySetup();
   TradeSetup GenerateSellSetup();
   void ConfigureSMCStructuralGate(bool requireStructuralValidity);
   TradeSetup GetLastSetup()const{return m_lastSetup;}
  };

CTradeDecision::CTradeDecision(){ZeroMemory(m_lastSetup);m_priceRef=NULL;m_fvgCtx=NULL;m_liqCtx=NULL;m_srCtx=NULL;m_bosCtx=NULL;m_scoring=NULL;m_environmentMemory=NULL;m_slBufferATR=0.25;m_minStopSpreadMult=3.0;m_fvgMaxDistATR=1.25;m_minSelectionScore=60.0;m_requireSmcStructuralValidity=false;}

void CTradeDecision::Init(CCandleData* priceRef,CTFContext* fvgCtx,CTFContext* liqCtx,CScoringEngine* scoring,double slBufferATR,double minStopSpreadMult,double fvgMaxDistATR,double minSelectionScore,CTFContext* srCtx,CTFContext* bosCtx, CEnvironmentStrategyMemory* environmentMemory)
  {
   m_priceRef=priceRef;m_fvgCtx=fvgCtx;m_liqCtx=liqCtx;m_srCtx=(srCtx!=NULL?srCtx:g_chartCtx);m_bosCtx=(bosCtx!=NULL?bosCtx:g_bosCtx);m_scoring=scoring;m_environmentMemory=environmentMemory;
   m_slBufferATR=(slBufferATR>0?slBufferATR:0.25);m_minStopSpreadMult=(minStopSpreadMult>=0?minStopSpreadMult:3.0);m_fvgMaxDistATR=(fvgMaxDistATR>0?fvgMaxDistATR:1.25);m_minSelectionScore=(minSelectionScore>=0.0&&minSelectionScore<=100.0)?minSelectionScore:60.0;
  }

double CTradeDecision::EnforceSpreadFloor(string symbol,double entry,double stopLoss,bool isBuy)
  {if(m_minStopSpreadMult<=0)return stopLoss;long sp=SymbolInfoInteger(symbol,SYMBOL_SPREAD);double pt=SymbolInfoDouble(symbol,SYMBOL_POINT);if(sp<=0||pt<=0)return stopLoss;double minDist=(double)sp*pt*m_minStopSpreadMult;double cur=MathAbs(entry-stopLoss);if(cur>=minDist)return stopLoss;return isBuy?(entry-minDist):(entry+minDist);}

bool CTradeDecision::FindEntryFVG(ENUM_FVG_DIR dir,FVGZone &out,int requiredBarIndex)
  {if(m_fvgCtx==NULL||m_priceRef==NULL||m_priceRef.Total()==0)return false;double price=m_priceRef.GetCandle(0).close;double atr=m_fvgCtx.candles.GetATR(0);if(price<=0||atr<=0)return false;bool found=false;double bestScore=-1.0;for(int i=0;i<m_fvgCtx.fvg.Count();i++){FVGZone z=m_fvgCtx.fvg.GetZone(i);if(z.dir!=dir)continue;if(requiredBarIndex>0&&z.bar_index!=requiredBarIndex)continue;if(z.state!=FVG_FRESH&&z.state!=FVG_TESTED)continue;double mid=(z.top+z.bottom)/2.0;double distATR=MathAbs(price-mid)/atr;if(distATR>m_fvgMaxDistATR)continue;double base=(z.state==FVG_FRESH)?1.0:0.6;double proximity=MathMax(0.0,1.0-distATR/m_fvgMaxDistATR);double score=base*(0.5+0.5*proximity);if(!found||score>bestScore){found=true;bestScore=score;out=z;}}return found;}

void CTradeDecision::PopulateStrategyReads(bool forBuy,SetupReasons &out)
  {
   ZeroMemory(out);if(m_scoring==NULL)return;
   m_scoring.EvaluateReasons(forBuy,out);m_scoring.PopulateStrategyDiagnostics(forBuy,0.0,out);out.selected_strategy=STRATEGY_NONE;out.selected_strategy_score=0.0;
   if(m_priceRef!=NULL&&m_priceRef.Total()>0){out.spread_points=(double)SymbolInfoInteger(m_priceRef.Symbol(),SYMBOL_SPREAD);out.point_size=SymbolInfoDouble(m_priceRef.Symbol(),SYMBOL_POINT);out.atr_value=m_priceRef.GetATR(0);}
   if(g_trendCtx!=NULL){ENUM_TREND_STATE trend=g_trendCtx.trend.GetCurrentTrend();if(trend==TREND_BULL_STRONG||trend==TREND_BEAR_STRONG)out.trend_strength=1.0;else if(trend==TREND_BULL||trend==TREND_BEAR)out.trend_strength=0.6;else out.trend_strength=0.0;}
   if(m_liqCtx!=NULL&&m_liqCtx.liquidity.EventCount()>0){LiquidityEvent ev=m_liqCtx.liquidity.GetEvent(0);bool supports=forBuy?(ev.type==LIQ_SELL_SIDE):(ev.type==LIQ_BUY_SIDE);if(supports&&ev.bar_index<=10){out.liquidity_score=MathMin(MathMax(ev.strength,0.0),1.0);out.liquidity_bucket=out.liquidity_score>=0.75?3:(out.liquidity_score>=0.50?2:(out.liquidity_score>0.0?1:0));}}
  }

void CTradeDecision::SelectPeerStrategy(bool forBuy,SetupReasons &reasons,ENUM_SELECTED_STRATEGY &selected,double &selectedScore)
  {
   selected=STRATEGY_NONE;selectedScore=0.0;if(m_scoring==NULL||reasons.regime==REGIME_UNDEFINED)return;
   ENUM_SELECTED_STRATEGY challenger=STRATEGY_NONE;double challengerScore=-1.0;
   if(reasons.regime==REGIME_TRENDING){if(reasons.breakout_class!=BREAKOUT_FAILED&&reasons.breakout_class!=BREAKOUT_EXHAUSTION&&(reasons.breakout_class==BREAKOUT_EXPANSION||reasons.breakout_class==BREAKOUT_LIQUIDITY||reasons.momentum_score>=m_minSelectionScore)){challengerScore=MathMax(reasons.momentum_score,reasons.breakout_score);challenger=STRATEGY_MOMENTUM_BREAKOUT;}}
   else if(reasons.regime==REGIME_RANGING){if(reasons.reversion_class==REVERSION_VALUE_FADE||reasons.reversion_class==REVERSION_LEVEL_REJECTION){challengerScore=reasons.reversion_score;challenger=STRATEGY_MEAN_REVERSION;}}
   else if(reasons.regime==REGIME_TRANSITION){if(reasons.keylevel_reaction==REACTION_REJECTION||reasons.keylevel_reaction==REACTION_RETEST||reasons.keylevel_reaction==REACTION_FAILED_BREAK||reasons.keylevel_reaction==REACTION_ABSORPTION){challengerScore=reasons.keylevel_score;challenger=STRATEGY_KEY_LEVEL;}}
   bool challengerEligible=(challenger!=STRATEGY_NONE&&challengerScore>=m_minSelectionScore);double challengerAdjusted=challengerScore;EnvironmentMemoryEvidence challengerEvidence;ZeroMemory(challengerEvidence);bool challengerMemory=false;if(challengerEligible&&m_environmentMemory!=NULL)challengerMemory=m_environmentMemory.GetEvidence(reasons,challenger,challengerEvidence);if(challengerEligible&&challengerMemory)challengerAdjusted=challengerScore+challengerEvidence.adjustment;
   double smcScore=m_scoring.CalculateConfidence(forBuy);bool smcEligible=(smcScore>=m_minSelectionScore);double smcAdjusted=smcScore;EnvironmentMemoryEvidence smcEvidence;ZeroMemory(smcEvidence);bool smcMemory=false;if(smcEligible&&m_environmentMemory!=NULL)smcMemory=m_environmentMemory.GetEvidence(reasons,STRATEGY_SMC,smcEvidence);if(smcEligible&&smcMemory)smcAdjusted=smcScore+smcEvidence.adjustment;
   if(challengerEligible&&(!smcEligible||challengerAdjusted>smcAdjusted)){selected=challenger;selectedScore=challengerScore;if(challengerMemory){reasons.environment_memory_status=challengerEvidence.status;reasons.environment_memory_sample=challengerEvidence.sample_size;reasons.environment_memory_win_rate=challengerEvidence.win_rate*100.0;reasons.environment_memory_avg_r=challengerEvidence.avg_r;reasons.environment_memory_profit_factor=challengerEvidence.profit_factor;reasons.environment_memory_adjustment=challengerEvidence.adjustment;}else reasons.environment_memory_status="UNKNOWN";}
   else if(smcEligible){selected=STRATEGY_SMC;selectedScore=smcScore;if(smcMemory){reasons.environment_memory_status=smcEvidence.status;reasons.environment_memory_sample=smcEvidence.sample_size;reasons.environment_memory_win_rate=smcEvidence.win_rate*100.0;reasons.environment_memory_avg_r=smcEvidence.avg_r;reasons.environment_memory_profit_factor=smcEvidence.profit_factor;reasons.environment_memory_adjustment=smcEvidence.adjustment;}else reasons.environment_memory_status="UNKNOWN";}
   reasons.selected_strategy=selected;reasons.selected_strategy_score=selectedScore;
  }

void CTradeDecision::ConfigureSMCStructuralGate(bool requireStructuralValidity)
  {
   m_requireSmcStructuralValidity=requireStructuralValidity;
  }

TradeSetup CTradeDecision::BuildSMC(bool forBuy,double confidence,const SetupReasons &reasons)
  {TradeSetup setup;ZeroMemory(setup);if(m_priceRef==NULL||m_fvgCtx==NULL)return setup;int requiredFvgBarIndex=-1;if(m_requireSmcStructuralValidity){if(!reasons.smc_structural_valid||!reasons.smc_fvg_causal||reasons.smc_entry_fvg_bar_index<=0)return setup;requiredFvgBarIndex=reasons.smc_entry_fvg_bar_index;}FVGZone entryFVG;if(!FindEntryFVG(forBuy?FVG_BULL:FVG_BEAR,entryFVG,requiredFvgBarIndex))return setup;double atr=m_fvgCtx.candles.GetATR(0);if(atr<=0)return setup;setup.type=forBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;setup.entry_top=entryFVG.top;setup.entry_bottom=entryFVG.bottom;setup.invalidation=forBuy?(entryFVG.bottom-0.05*atr):(entryFVG.top+0.05*atr);setup.stop_loss=forBuy?(entryFVG.bottom-m_slBufferATR*atr):(entryFVG.top+m_slBufferATR*atr);setup.stop_loss=EnforceSpreadFloor(m_priceRef.Symbol(),forBuy?setup.entry_top:setup.entry_bottom,setup.stop_loss,forBuy);if((forBuy&&setup.stop_loss>=setup.invalidation)||(!forBuy&&setup.stop_loss<=setup.invalidation))return setup;CTargetSelector::AssignTargets(setup,m_liqCtx,m_priceRef.Symbol(),atr,forBuy?setup.entry_bottom:setup.entry_top);setup.confidence=MathMax(0.0,MathMin(confidence,100.0));setup.creation_time=TimeCurrent();setup.active=true;setup.reasons=reasons;return setup;}

bool CTradeDecision::BuildNonSMC(bool forBuy,ENUM_SELECTED_STRATEGY selected,double confidence,const SetupReasons &reasons,TradeSetup &out)
  {
   ZeroMemory(out);
   if(m_priceRef==NULL || g_chartCtx==NULL) return false;
   bool built=false;
   // Strategy builders require the full timeframe context (candles + structure),
   // not the raw CCandleData pointer used by CTradeDecision's price helpers.
   if(selected==STRATEGY_MOMENTUM_BREAKOUT)
      built=CStrategySetupBuilders::BuildMomentum(forBuy,confidence,reasons,g_chartCtx,m_bosCtx,m_liqCtx,out);
   else if(selected==STRATEGY_MEAN_REVERSION)
      built=CStrategySetupBuilders::BuildMeanReversion(forBuy,confidence,reasons,g_chartCtx,m_srCtx,m_liqCtx,out);
   else if(selected==STRATEGY_KEY_LEVEL)
      built=CStrategySetupBuilders::BuildKeyLevel(forBuy,confidence,reasons,g_chartCtx,m_srCtx,m_liqCtx,out);
   if(!built) return false;
   out.stop_loss=EnforceSpreadFloor(m_priceRef.Symbol(),ResolveExecutionEntry(out),out.stop_loss,forBuy);
   if((forBuy&&out.stop_loss>=out.invalidation)||(!forBuy&&out.stop_loss<=out.invalidation))
     { ZeroMemory(out); return false; }
   out.reasons.selected_strategy=selected;
   out.reasons.selected_strategy_score=confidence;
   return true;
  }

TradeSetup CTradeDecision::BuildAuthoritativeStrategy(bool forBuy)
  {TradeSetup owned;ZeroMemory(owned);if(m_scoring==NULL||m_priceRef==NULL)return owned;SetupReasons reasons;PopulateStrategyReads(forBuy,reasons);ENUM_SELECTED_STRATEGY selected=STRATEGY_NONE;double selectedScore=0.0;SelectPeerStrategy(forBuy,reasons,selected,selectedScore);if(selected==STRATEGY_NONE||selectedScore<m_minSelectionScore){m_lastSetup=owned;return owned;}reasons.selected_strategy=selected;reasons.selected_strategy_score=selectedScore;if(selected==STRATEGY_SMC){m_scoring.PopulateStructuralValidation(forBuy,reasons);if(m_requireSmcStructuralValidity&&!reasons.smc_structural_valid){owned.type=forBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;owned.creation_time=TimeCurrent();owned.reasons=reasons;owned.reasons.smc_failure_reason="Execution gate rejected: "+reasons.smc_failure_reason;m_lastSetup=owned;return owned;}owned=BuildSMC(forBuy,selectedScore,reasons);}else if(!BuildNonSMC(forBuy,selected,selectedScore,reasons,owned)){ZeroMemory(owned);m_lastSetup=owned;return owned;}if(!owned.active){ZeroMemory(owned);m_lastSetup=owned;return owned;}owned.reasons.selected_strategy=selected;owned.reasons.selected_strategy_score=selectedScore;m_lastSetup=owned;return owned;}

TradeSetup CTradeDecision::GenerateBuySetup(){return BuildAuthoritativeStrategy(true);}TradeSetup CTradeDecision::GenerateSellSetup(){return BuildAuthoritativeStrategy(false);}

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/StrategyTradeZone.mqh
// already inlined once under include guard: includes/Trading/EnvironmentStrategyMemory.mqh
// BEGIN INLINED MODULE: includes/Trading/RiskEngine.mqh
//+------------------------------------------------------------------+
//| Trading/RiskEngine.mqh                                           |
//| Stop-distance validation and account-currency position sizing.    |
//+------------------------------------------------------------------+
#ifndef RISKENGINE_MQH
#define RISKENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// BEGIN INLINED MODULE: includes/Portfolio/AccountRiskProfilePolicy.mqh
//+------------------------------------------------------------------+
//| Portfolio/AccountRiskProfilePolicy.mqh                            |
//| Explicit risk-profile selection with fail-closed validation.      |
//+------------------------------------------------------------------+
#ifndef ACCOUNTRISKPROFILEPOLICY_MQH
#define ACCOUNTRISKPROFILEPOLICY_MQH

// Absolute hard ceiling shared by profile validation and lot sizing.
// The user-requested small-account profile targets 20% of equity per trade;
// larger percentages remain rejected regardless of daily/portfolio limits.
#define MIDAS_MAX_RISK_PERCENT_PER_TRADE 20.0
#define MIDAS_SMALL_ACCOUNT_MIN_RISK_PERCENT_PER_TRADE 15.0

enum ENUM_ACCOUNT_RISK_PROFILE
  {
   ACCOUNT_RISK_PROFILE_LEGACY_INPUTS = 0, // existing EA inputs; default preserves prior behavior
   ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT = 1,
   ACCOUNT_RISK_PROFILE_PROP_FIRM     = 2
  };

struct AccountRiskLimits
  {
   ENUM_ACCOUNT_RISK_PROFILE profile;
   string profileName;
   double riskPercentPerTrade;
   int    maxOpenTrades;
   double maxDailyLossPercent;
   double maxDrawdownPercent;
   double deriskStartPercent;
   double deriskFloor;
   double maxPortfolioRiskPercent;
   int    maxPositionsPerSymbol;
   int    maxPositionsPerGroup;
  };

bool ValidateAccountRiskLimits(const AccountRiskLimits &limits,string &reason)
  {
   reason="";
   if(!MathIsValidNumber(limits.riskPercentPerTrade) || limits.riskPercentPerTrade<=0.0)
      { reason="riskPercentPerTrade must be finite and positive"; return false; }
   if(limits.riskPercentPerTrade>MIDAS_MAX_RISK_PERCENT_PER_TRADE)
      {
       reason=StringFormat("riskPercentPerTrade %.2f%% exceeds the hard safety ceiling of %.2f%%; risk above the configured ceiling is unsupported",
                           limits.riskPercentPerTrade,MIDAS_MAX_RISK_PERCENT_PER_TRADE);
       return false;
      }
   if(limits.maxOpenTrades<1)
      { reason="maxOpenTrades must be at least one"; return false; }
   if(!MathIsValidNumber(limits.maxDailyLossPercent) || limits.maxDailyLossPercent<=0.0)
      { reason="maxDailyLossPercent must be finite and positive"; return false; }
   if(!MathIsValidNumber(limits.maxDrawdownPercent) || limits.maxDrawdownPercent<=limits.maxDailyLossPercent)
      { reason="maxDrawdownPercent must exceed maxDailyLossPercent"; return false; }
   if(limits.riskPercentPerTrade>=limits.maxDailyLossPercent)
      { reason="per-trade risk must be below the daily-loss cap"; return false; }
   if(!MathIsValidNumber(limits.deriskStartPercent) || limits.deriskStartPercent<0.0 ||
      limits.deriskStartPercent>=limits.maxDrawdownPercent)
      { reason="deriskStartPercent must be non-negative and below the hard drawdown cap"; return false; }
   if(!MathIsValidNumber(limits.deriskFloor) || limits.deriskFloor<=0.0 || limits.deriskFloor>1.0)
      { reason="deriskFloor must be in (0, 1]"; return false; }
   if(!MathIsValidNumber(limits.maxPortfolioRiskPercent) ||
      limits.maxPortfolioRiskPercent<limits.riskPercentPerTrade)
      { reason="portfolio open-risk cap must be at least one base trade risk"; return false; }
   if(limits.maxPortfolioRiskPercent>limits.maxDailyLossPercent)
      { reason="portfolio open-risk cap must not exceed the daily-loss cap"; return false; }
   if(limits.maxPositionsPerSymbol<1 || limits.maxPositionsPerGroup<1)
      { reason="per-symbol and per-group position limits must be at least one"; return false; }
   if(limits.maxPositionsPerSymbol>limits.maxOpenTrades ||
      limits.maxPositionsPerGroup>limits.maxOpenTrades)
      { reason="per-symbol and per-group limits must not exceed the account-wide open-trade cap"; return false; }
   return true;
  }

// Select exactly one complete profile. The caller constructs all three from
// the EA inputs and validates the selected profile before any order routing.
// Global account-wide RiskGuard persistence remains account-scoped across restarts.
bool ResolveAccountRiskLimits(ENUM_ACCOUNT_RISK_PROFILE selected,
                              const AccountRiskLimits &legacy,
                              const AccountRiskLimits &smallAccount,
                              const AccountRiskLimits &propFirm,
                              AccountRiskLimits &out,
                              string &reason)
  {
   if(selected==ACCOUNT_RISK_PROFILE_LEGACY_INPUTS)
      out=legacy;
   else if(selected==ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT)
      out=smallAccount;
   else if(selected==ACCOUNT_RISK_PROFILE_PROP_FIRM)
      out=propFirm;
   else
     { reason="unknown account risk profile"; return false; }

   out.profile=selected;
   if(selected==ACCOUNT_RISK_PROFILE_LEGACY_INPUTS) out.profileName="legacy_inputs";
   else if(selected==ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT) out.profileName="small_account";
   else out.profileName="prop_firm";

   if(!ValidateAccountRiskLimits(out,reason))
      return false;
   return true;
  }


// Non-legacy profiles have separately editable inputs whose shipped values are
// placeholders copied from legacy settings. Fail closed until the operator has
// explicitly marked each profile configured against the intended account rules.
bool ResolveConfiguredAccountRiskLimits(ENUM_ACCOUNT_RISK_PROFILE selected,
                                        const AccountRiskLimits &legacy,
                                        const AccountRiskLimits &smallAccount,
                                        const AccountRiskLimits &propFirm,
                                        bool smallProfileConfigured,
                                        bool propProfileConfigured,
                                        AccountRiskLimits &out,
                                        string &reason)
  {
   reason="";
   if(selected==ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT && !smallProfileConfigured)
     {
      reason="small-account risk inputs must be configured before selecting this profile";
      return false;
     }
   if(selected==ACCOUNT_RISK_PROFILE_PROP_FIRM && !propProfileConfigured)
     {
      reason="exact prop-firm limits must be configured before selecting this profile";
      return false;
     }
   return ResolveAccountRiskLimits(selected,legacy,smallAccount,propFirm,out,reason);
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Portfolio/AccountRiskProfilePolicy.mqh

class CRiskEngine
  {
private:
   // Uses MT5's symbol-specific profit model rather than assuming
   // SYMBOL_TRADE_TICK_VALUE / TICK_SIZE is a complete loss model.
   bool              EstimateStopLossPerLot(string symbol,double entry,double stopLoss,double &lossPerLot);

public:
   bool              ValidateSetup(TradeSetup &setup,double minRR,double maxSLDistanceATR,double currentATR);
   bool              ValidateSetupAtEntry(const TradeSetup &setup,double entry,double minRR,double maxSLDistanceATR,double currentATR);
   double            CalculateLotSize(string symbol,double riskPercent,double entry,double stopLoss,
                                      bool halveForReducedRisk,bool allowMinLotOverride,bool &exceededRiskBudget,
                                      double sizeMultiplier=1.0);
   double            RiskAmountForLots(string symbol,double lots,double entry,double stopLoss);
  };

//+------------------------------------------------------------------+
// Estimate the account-currency loss for one lot if the proposed stop
// is reached. The stop side determines the intended direction here:
// below entry = buy stop; above entry = sell stop. ValidateSetup checks
// this geometry against the actual setup direction before execution.
// OrderCalcProfit includes the symbol's MT5 calculation mode and
// account-currency conversion; it does NOT include gap/slippage,
// commission, or swap, so portfolio risk remains a stop-based estimate.
//+------------------------------------------------------------------+
bool CRiskEngine::EstimateStopLossPerLot(string symbol,double entry,double stopLoss,double &lossPerLot)
  {
   lossPerLot=0.0;
   if(symbol=="" || !MathIsValidNumber(entry) || !MathIsValidNumber(stopLoss) ||
      entry<=0.0 || stopLoss<=0.0 || entry==stopLoss)
      return false;

   ENUM_ORDER_TYPE orderType=(stopLoss<entry ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double estimatedProfit=0.0;
   ResetLastError();
   if(!OrderCalcProfit(orderType,symbol,1.0,entry,stopLoss,estimatedProfit))
      return false;
   if(!MathIsValidNumber(estimatedProfit) || estimatedProfit>=0.0)
      return false;

   lossPerLot=-estimatedProfit;
   return MathIsValidNumber(lossPerLot) && lossPerLot>0.0;
  }

//+------------------------------------------------------------------+
// Convert the requested equity-risk budget into lots. Volume is always
// rounded DOWN to the broker's step. If the risk budget cannot purchase
// the minimum lot, the default is to reject; the explicit override is
// surfaced through exceededRiskBudget. A zero/invalid budget can never
// be raised to minimum lot, even when that override is enabled.
//+------------------------------------------------------------------+
double CRiskEngine::CalculateLotSize(string symbol,double riskPercent,double entry,double stopLoss,
                                     bool halveForReducedRisk,bool allowMinLotOverride,bool &exceededRiskBudget,
                                     double sizeMultiplier)
  {
   exceededRiskBudget=false;
   if(!MathIsValidNumber(riskPercent) || !MathIsValidNumber(sizeMultiplier) ||
      riskPercent<=0.0 || riskPercent>MIDAS_MAX_RISK_PERCENT_PER_TRADE ||
      entry<=0.0 || stopLoss<=0.0 || entry==stopLoss)
      return 0.0;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!MathIsValidNumber(equity) || equity<=0.0)
      return 0.0;

   double lossPerLot=0.0;
   if(!EstimateStopLossPerLot(symbol,entry,stopLoss,lossPerLot))
      return 0.0;

   double riskAmount=equity*(riskPercent/100.0);
   if(halveForReducedRisk) riskAmount*=0.5;
   double multiplier=MathMax(0.0,MathMin(1.0,sizeMultiplier));
   riskAmount*=multiplier;
   if(!MathIsValidNumber(riskAmount) || riskAmount<=0.0)
      return 0.0;

   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double lotStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(!MathIsValidNumber(minLot) || !MathIsValidNumber(maxLot) ||
      !MathIsValidNumber(lotStep) || minLot<=0.0 || maxLot<minLot || lotStep<=0.0)
      return 0.0;

   double lots=riskAmount/lossPerLot;
   if(!MathIsValidNumber(lots) || lots<=0.0)
      return 0.0;

   // Reject a raw size below the broker minimum before rounding. Valid
   // broker sizes are anchored at minLot + N*lotStep, not necessarily N*lotStep.
   // Rounding down relative to zero can reject valid minimum-sized positions
   // when minLot is not itself an exact multiple of lotStep.
   lots=MathMin(maxLot,lots);
   if(lots<minLot)
      return 0.0;
   lots=minLot+MathFloor((lots-minLot)/lotStep)*lotStep;
   lots=MathMin(maxLot,lots);
   lots=NormalizeDouble(lots,8);

   if(lots<minLot)
     {
      // Never increase volume to the broker minimum: the minimum lot can
      // breach the configured risk budget at wide stops or small risk values.
      // Keep the legacy argument for call-site compatibility, but enforce
      // hard risk compliance even when InpAllowMinLotOverride is enabled.
      return 0.0;
     }

   return lots;
  }

//+------------------------------------------------------------------+
// Stop-based risk for a proposed position. A stop already at or beyond
// entry protects against ordinary price loss at the stop, so it reports
// zero planned stop risk; gap risk and execution costs still exist.
// Invalid price/tick calculations return zero, and the caller must fail
// closed rather than treating that value as proof of safe exposure.
//+------------------------------------------------------------------+
double CRiskEngine::RiskAmountForLots(string symbol,double lots,double entry,double stopLoss)
  {
   if(!MathIsValidNumber(lots) || lots<=0.0 || !MathIsValidNumber(entry) ||
      !MathIsValidNumber(stopLoss) || entry<=0.0 || stopLoss<=0.0)
      return 0.0;

   if(entry==stopLoss)
      return 0.0;

   double lossPerLot=0.0;
   if(!EstimateStopLossPerLot(symbol,entry,stopLoss,lossPerLot))
      return 0.0;

   double risk=lossPerLot*lots;
   return (MathIsValidNumber(risk) && risk>0.0 ? risk : 0.0);
  }

//+------------------------------------------------------------------+
// Validate at the strategy's resolved entry for the normal setup gate.
//+------------------------------------------------------------------+
bool CRiskEngine::ValidateSetup(TradeSetup &setup,double minRR,double maxSLDistanceATR,double currentATR)
  {
   return ValidateSetupAtEntry(setup,ResolveExecutionEntry(setup),minRR,maxSLDistanceATR,currentATR);
  }

//+------------------------------------------------------------------+
// Validate geometry at a specified executable or conservative entry.
// This is used a second time before sizing a market order, where the
// worst allowed fill inside the configured deviation band must still
// satisfy the same RR and ATR risk limits.
//+------------------------------------------------------------------+
bool CRiskEngine::ValidateSetupAtEntry(const TradeSetup &setup,double entry,double minRR,double maxSLDistanceATR,double currentATR)
  {
   if(!setup.active || (setup.type!=ORDER_TYPE_BUY && setup.type!=ORDER_TYPE_SELL))
      return false;
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(minRR) ||
      !MathIsValidNumber(maxSLDistanceATR) || !MathIsValidNumber(currentATR) ||
      entry<=0.0 || minRR<=0.0)
      return false;

   double sl=setup.stop_loss;
   double tp1=setup.tp1;
   if(!MathIsValidNumber(sl) || !MathIsValidNumber(tp1) ||
      !MathIsValidNumber(setup.tp2) || !MathIsValidNumber(setup.final_tp) ||
      sl<=0.0 || tp1<=0.0 || setup.final_tp<=0.0 || setup.tp2<0.0)
      return false;

   if(setup.type==ORDER_TYPE_BUY)
     {
      if(!(sl<entry && tp1>entry)) return false;
      if(setup.tp2>0.0 && setup.tp2<=entry) return false;
      if(setup.final_tp>0.0 && setup.final_tp<=entry) return false;
     }
   else
     {
      if(!(sl>entry && tp1<entry)) return false;
      if(setup.tp2>0.0 && setup.tp2>=entry) return false;
      if(setup.final_tp>0.0 && setup.final_tp>=entry) return false;
     }

   double slDist=MathAbs(entry-sl);
   double tpDist=MathAbs(tp1-entry);
   if(slDist<=0.0 || tpDist/slDist<minRR)
      return false;

   // Zero explicitly disables the ATR-distance cap. Negative configuration is
   // malformed and must not silently disable validation. When enabled, missing
   // or non-positive ATR makes the cap unprovable, so reject the setup.
   if(!MathIsValidNumber(maxSLDistanceATR) || maxSLDistanceATR<0.0)
      return false;
   if(maxSLDistanceATR>0.0)
     {
      if(!MathIsValidNumber(currentATR) || currentATR<=0.0)
         return false;
      double slDistATR=slDist/currentATR;
      if(!MathIsValidNumber(slDistATR) || slDistATR>maxSLDistanceATR)
         return false;
     }
   return true;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/RiskEngine.mqh
// BEGIN INLINED MODULE: includes/Trading/OutcomeTrackerLive.mqh
//+------------------------------------------------------------------+
//| Trading/OutcomeTrackerLive.mqh                                  |
//+------------------------------------------------------------------+
#ifndef OUTCOMETRACKERLIVE_MQH
#define OUTCOMETRACKERLIVE_MQH
// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Core/SignalLogger.mqh
// BEGIN INLINED MODULE: includes/Trading/CalibrationEngine.mqh
//+------------------------------------------------------------------+
//|                                    Trading/CalibrationEngine.mqh  |
//+------------------------------------------------------------------+
#ifndef CALIBRATIONENGINE_MQH
#define CALIBRATIONENGINE_MQH

#define MEDIS_CALIBRATION_NUM_BUCKETS 20

// v2.9 addition — review item #1 / #9: "a confidence score isn't a
// probability until it's been checked against real outcomes." This
// bucket-tracks CScoringEngine::CalculateConfidence()'s output against
// COutcomeTracker's resolved win/loss verdicts and reports the ACTUAL
// historical win rate for each confidence range, persisted to a file so
// the sample survives restarts.
//
// HONEST LIMITATIONS — read before trusting the numbers this produces:
//  1. This does NOT change trading behavior on its own. Nothing in the
//     EA gates on calibrated probability yet — it is purely an
//     observability layer that answers "is an 80 actually an 80?" You
//     have to look at the numbers and decide what to do with them (e.g.
//     discover 90+ underperforms 80-89 and investigate why, per review
//     item #9). Wiring a live gate off this is a deliberate next step,
//     not something this file does implicitly.
//  2. Sample sizes below MIN_SAMPLE (default 30) per bucket are reported
//     but flagged low-confidence — with a live strategy this realistically
//     means MONTHS of forward/backtest data before any bucket's number
//     means anything. Don't trust a 5-trade bucket's win rate.
//  3. Buckets are fixed 5-point-wide bins from 0-100 (20 buckets). This
//     is a starting resolution, not a tuned one — too fine and you never
//     accumulate samples per bucket, too coarse and you can't see
//     structure like "90+ underperforms 80-89". Revisit once you have
//     real volume.
//  4. This tracks the RAW CalculateConfidence() output at the moment
//     AddSetup() logged the trade — if you change the scoring formula
//     (as the v2.9 sweep-grade/BOS-strength/decay changes in this same
//     release do), OLD calibration data no longer describes the NEW
//     score's meaning. Clear/reset the calibration file after any
//     scoring-formula change, or you'll be calibrating against a
//     confidence definition that no longer exists. See Reset().
//  5. Calibration is symbol-agnostic by construction (one file per
//     EA instance/symbol, same as OutcomeTracker's CSV) — a XAUUSD
//     bucket's win rate says nothing about EURUSD's. Don't share the
//     file across symbols.
class CCalibrationEngine
  {
private:
   int               m_wins[MEDIS_CALIBRATION_NUM_BUCKETS];
   int               m_losses[MEDIS_CALIBRATION_NUM_BUCKETS];
   int               m_scratches[MEDIS_CALIBRATION_NUM_BUCKETS];
   string            m_filename;
   int               m_minSample;

   int               BucketIndex(double confidence) const
     {
      int idx = (int)MathFloor(confidence / 5.0);
      return (int)MathMax(0, MathMin(idx, MEDIS_CALIBRATION_NUM_BUCKETS - 1));
     }

public:
                     CCalibrationEngine() : m_filename(""), m_minSample(30)
     {
      ArrayInitialize(m_wins, 0);
      ArrayInitialize(m_losses, 0);
      ArrayInitialize(m_scratches, 0);
     }

   void              Init(string symbol, int minSample = 30, bool useCommonFolder = false)
     {
      m_filename = "MedisTouch_Calibration_" + symbol + ".csv";
      m_minSample = MathMax(1, minSample);
      Load(useCommonFolder);
     }

   // Call once per resolved, sized (lots>0), non-ambiguous trade — see
   // COutcomeTracker::FinalizeExit() for the call site. netPnL > 0 counts
   // as a win, < 0 a loss, == 0 a scratch (matches OutcomeStats'
   // win/loss/scratch convention exactly, so this stays consistent with
   // the dashboard's headline win rate).
   void              Record(double confidence, double netPnL, bool useCommonFolder = false)
     {
      int b = BucketIndex(confidence);
      if(netPnL > 0.0000001)      m_wins[b]++;
      else if(netPnL < -0.0000001) m_losses[b]++;
      else                          m_scratches[b]++;
      Save(useCommonFolder); // flush every trade — this is low-frequency (one call per resolved trade), not per-tick
     }

   // Returns the empirical win rate for the bucket confidence falls
   // into, the sample size behind it, and whether that sample clears
   // m_minSample. hasEnoughData=false is not "no edge" — it's "don't
   // trust this number yet."
   double            GetCalibratedProbability(double confidence, int &sampleSizeOut, bool &hasEnoughDataOut) const
     {
      int b = BucketIndex(confidence);
      int w = m_wins[b], l = m_losses[b];
      int total = w + l; // scratches excluded from the win-rate denominator, same convention as OutcomeStats.WinRateExcludingAmbiguous()
      sampleSizeOut = total;
      hasEnoughDataOut = (total >= m_minSample);
      if(total == 0) return 0.0;
      return 100.0 * w / total;
     }

   // Whole-curve dump for the dashboard/CSV export — one row per bucket,
   // "" for the string return means "print this yourself", kept simple
   // rather than building a UI dependency into this file.
   string            BucketSummary(int bucketIdx) const
     {
      if(bucketIdx < 0 || bucketIdx >= MEDIS_CALIBRATION_NUM_BUCKETS) return "";
      int lo = bucketIdx * 5, hi = lo + 5;
      int w = m_wins[bucketIdx], l = m_losses[bucketIdx], s = m_scratches[bucketIdx];
      int total = w + l;
      double wr = (total > 0) ? (100.0 * w / total) : 0.0;
      return StringFormat("%d-%d: %d trades, %.1f%% win rate%s", lo, hi, total, wr,
                           (total < m_minSample) ? " (low sample)" : "");
     }
   int               NumBuckets() const { return MEDIS_CALIBRATION_NUM_BUCKETS; }

   // v2.9 note #4 above — call this after any scoring-formula change so
   // stale-definition data doesn't masquerade as current calibration.
   void              Reset(bool useCommonFolder = false)
     {
      ArrayInitialize(m_wins, 0);
      ArrayInitialize(m_losses, 0);
      ArrayInitialize(m_scratches, 0);
      Save(useCommonFolder);
     }

   void              Save(bool useCommonFolder = false)
     {
      if(StringLen(m_filename) == 0) return;
      int flags = FILE_CSV | FILE_WRITE | FILE_ANSI;
      if(useCommonFolder) flags |= FILE_COMMON;
      int h = FileOpen(m_filename, flags, ',');
      if(h == INVALID_HANDLE) return;
      FileWrite(h, "BucketLow", "BucketHigh", "Wins", "Losses", "Scratches");
      for(int i = 0; i < MEDIS_CALIBRATION_NUM_BUCKETS; i++)
         FileWrite(h, i * 5, i * 5 + 5, m_wins[i], m_losses[i], m_scratches[i]);
      FileClose(h);
     }

   bool              Load(bool useCommonFolder = false)
     {
      if(StringLen(m_filename) == 0) return false;
      int flags = FILE_CSV | FILE_READ | FILE_SHARE_READ | FILE_ANSI;
      if(useCommonFolder) flags |= FILE_COMMON;
      int h = FileOpen(m_filename, flags, ',');
      if(h == INVALID_HANDLE) return false; // no prior file — fresh start, not an error

      // header row
      for(int c = 0; c < 5 && !FileIsEnding(h); c++) FileReadString(h);

      int i = 0;
      while(!FileIsEnding(h) && i < MEDIS_CALIBRATION_NUM_BUCKETS)
        {
         string loS = FileReadString(h);
         if(FileIsEnding(h)) break;
         FileReadString(h); // hi, unused (derivable from index)
         string wS = FileReadString(h);
         string lS = FileReadString(h);
         string sS = FileReadString(h);
         m_wins[i] = (int)StringToInteger(wS);
         m_losses[i] = (int)StringToInteger(lS);
         m_scratches[i] = (int)StringToInteger(sS);
         i++;
        }
      FileClose(h);
      return true;
     }
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/CalibrationEngine.mqh
// BEGIN INLINED MODULE: includes/Signals/SignalPublisher.mqh
//+------------------------------------------------------------------+
//| Signals/SignalPublisher.mqh                                      |
//+------------------------------------------------------------------+
#ifndef SIGNALPUBLISHER_MQH
#define SIGNALPUBLISHER_MQH
// BEGIN INLINED MODULE: includes/Decision/TradeDecision.mqh
//+------------------------------------------------------------------+
//|                                       Decision/TradeDecision.mqh |
//|  Shared record types for the analysis -> decision -> action seam. |
//+------------------------------------------------------------------+
#ifndef TRADEDECISION_MQH
#define TRADEDECISION_MQH

// already inlined once under include guard: includes/Core/Config.mqh

enum ENUM_TRADE_POLICY
  {
   POLICY_IGNORE = 0,
   POLICY_SIGNAL_ONLY,
   POLICY_EXECUTE_ONLY,
   POLICY_EXECUTE_AND_SIGNAL
  };

string TradePolicyToString(ENUM_TRADE_POLICY p)
  {
   switch(p)
     {
      case POLICY_SIGNAL_ONLY:        return "SIGNAL_ONLY";
      case POLICY_EXECUTE_ONLY:       return "EXECUTE_ONLY";
      case POLICY_EXECUTE_AND_SIGNAL: return "EXECUTE_AND_SIGNAL";
      default:                        return "IGNORE";
     }
  }

struct TradeDecisionRecord
  {
   long              decision_id;
   string            symbol;
   TradeSetup        setup;
   ENUM_TRADE_POLICY action;
   bool              reduce_risk;
   bool              valid;
   double            confidence;
   double            spread_points;
   datetime          decided_time;
   string            reason;
   ENUM_TIMEFRAMES   timeframe;
   string            decision_schema_version;
   string            strategy_version;
   string            model_version;
   string            calibration_version;
   string            feature_schema_version;
   string            environment_schema_version;
   string            weight_version;
   string            environment_key;
   string            decision_fingerprint;
  };

struct ExecutionRecord
  {
   long              decision_id;
   double            volume;
   ulong             ticket;
   datetime          submitted_time;
   int               leg_index;
   double            target;
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Decision/TradeDecision.mqh
// BEGIN INLINED MODULE: includes/Signals/SubscriberPlatform.mqh
//+------------------------------------------------------------------+
//|                                   Signals/SubscriberPlatform.mqh |
//+------------------------------------------------------------------+
#ifndef SUBSCRIBERPLATFORM_MQH
#define SUBSCRIBERPLATFORM_MQH

// Subscriber registry + delivery bookkeeping for the Signal Distribution
// Engine. Deliberately file-based and hand-editable rather than a UI:
// MQL5 has no admin panel to build one without a much bigger investment
// (a web dashboard talking to this over HTTP), and a flat CSV a human —
// or a future admin tool — edits directly is enough to unblock "actually
// send signals to real subscribers" today.
//
// File format, "MedisTouch_Subscribers.csv" (ACCOUNT-WIDE, not
// per-symbol — one subscriber list serves every symbol this EA runs on):
//   SubscriberID, Name, Tier, Endpoint, Active
// Tier is a free-text label (e.g. "FREE", "PRO") — CSignalPublisher
// decides what tier sees what; this class only stores and serves the
// registry, it doesn't gate content by tier itself.
struct Subscriber
  {
   string            id;
   string            name;
   string            tier;
   string            endpoint;
   bool              active;
  };

class CSubscriberPlatform
  {
private:
   string            m_subsFilename;
   string            m_deliveryFilename;
   int               m_deliveryFileHandle;
   Subscriber        m_subscribers[];

   void              LoadSubscribers();

public:
   void              Init();
   void              Deinit();
   void              Reload(); // re-read the subscriber file on demand — it's hand-edited, not written by this class
   int               GetActiveSubscribers(Subscriber &out[]);
   int               GetActiveSubscribers(string tierFilter, Subscriber &out[]); // "" = all tiers
   void              RecordDelivery(string subscriberId, long decisionId, bool success);
   int               Count() { return ArraySize(m_subscribers); }
  };
//+------------------------------------------------------------------+
void CSubscriberPlatform::Init()
  {
   m_subsFilename = "MedisTouch_Subscribers.csv";
   m_deliveryFilename = "MedisTouch_Deliveries.csv";
   LoadSubscribers();

   bool exists = FileIsExist(m_deliveryFilename);
   m_deliveryFileHandle = FileOpen(m_deliveryFilename, FILE_READ | FILE_WRITE | FILE_CSV, ',');
   if(m_deliveryFileHandle == INVALID_HANDLE)
      Print("MedisTouch SubscriberPlatform: could not open ", m_deliveryFilename);
   else if(!exists)
     {
      FileWrite(m_deliveryFileHandle, "SubscriberID", "DecisionID", "Success", "Time");
      FileFlush(m_deliveryFileHandle);
     }
  }
//+------------------------------------------------------------------+
void CSubscriberPlatform::LoadSubscribers()
  {
   ArrayResize(m_subscribers, 0);
   if(!FileIsExist(m_subsFilename))
     {
      // Ship an empty-but-present file with a header so the format is
      // discoverable without documentation. First run, zero subscribers,
      // Publish() below just has nothing to iterate — that's correct.
      int h = FileOpen(m_subsFilename, FILE_WRITE | FILE_CSV, ',');
      if(h != INVALID_HANDLE)
        {
         FileWrite(h, "SubscriberID", "Name", "Tier", "Endpoint", "Active");
         FileClose(h);
        }
      return;
     }

   int handle = FileOpen(m_subsFilename, FILE_READ | FILE_CSV, ',');
   if(handle == INVALID_HANDLE)
     {
      Print("MedisTouch SubscriberPlatform: could not open ", m_subsFilename);
      return;
     }

   if(!FileIsEnding(handle))
      for(int c = 0; c < 5 && !FileIsEnding(handle); c++)
         FileReadString(handle); // skip header row

   int n = 0;
   while(!FileIsEnding(handle))
     {
      string id = FileReadString(handle);
      if(StringLen(id) == 0 && FileIsEnding(handle)) break; // trailing blank line guard

      Subscriber s;
      s.id       = id;
      s.name     = FileReadString(handle);
      s.tier     = FileReadString(handle);
      s.endpoint = FileReadString(handle);
      string activeStr = FileReadString(handle);
      s.active = (activeStr == "1" || activeStr == "true" || activeStr == "TRUE");

      ArrayResize(m_subscribers, n + 1);
      m_subscribers[n++] = s;
     }
   FileClose(handle);
   PrintFormat("MedisTouch SubscriberPlatform: loaded %d subscriber(s) from %s.", n, m_subsFilename);
  }
//+------------------------------------------------------------------+
void CSubscriberPlatform::Reload() { LoadSubscribers(); }
//+------------------------------------------------------------------+
void CSubscriberPlatform::Deinit()
  {
   if(m_deliveryFileHandle != INVALID_HANDLE) FileClose(m_deliveryFileHandle);
  }
//+------------------------------------------------------------------+
int CSubscriberPlatform::GetActiveSubscribers(Subscriber &out[])
  {
   return GetActiveSubscribers("", out);
  }
//+------------------------------------------------------------------+
int CSubscriberPlatform::GetActiveSubscribers(string tierFilter, Subscriber &out[])
  {
   ArrayResize(out, 0);
   int n = 0;
   for(int i = 0; i < ArraySize(m_subscribers); i++)
     {
      if(!m_subscribers[i].active) continue;
      if(tierFilter != "" && m_subscribers[i].tier != tierFilter) continue;
      ArrayResize(out, n + 1);
      out[n++] = m_subscribers[i];
     }
   return n;
  }
//+------------------------------------------------------------------+
void CSubscriberPlatform::RecordDelivery(string subscriberId, long decisionId, bool success)
  {
   if(m_deliveryFileHandle == INVALID_HANDLE) return;
   FileSeek(m_deliveryFileHandle, 0, SEEK_END);
   FileWrite(m_deliveryFileHandle, subscriberId, decisionId, success ? 1 : 0,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   FileFlush(m_deliveryFileHandle);
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Signals/SubscriberPlatform.mqh
// BEGIN INLINED MODULE: includes/Decision/DecisionFingerprint.mqh
//+------------------------------------------------------------------+
//| Decision/DecisionFingerprint.mqh                                 |
//| Portable canonical decision serialization and SHA-256 hashing.   |
//+------------------------------------------------------------------+
#ifndef DECISIONFINGERPRINT_MQH
#define DECISIONFINGERPRINT_MQH
// already inlined once under include guard: includes/Decision/TradeDecision.mqh

string DecisionFpNormalizeString(const string value)
  {
   string out=value;
   StringTrimLeft(out);
   StringTrimRight(out);
   return out;
  }

string DecisionFpCanonical(const TradeDecisionRecord &rec)
  {
   string direction=(rec.setup.type==ORDER_TYPE_BUY)?"BUY":"SELL";
   double entry=(rec.setup.type==ORDER_TYPE_BUY)?rec.setup.entry_top:rec.setup.entry_bottom;
   string canonical=
      "schema_version="+DecisionFpNormalizeString(rec.decision_schema_version)+
      "|decision_id="+IntegerToString(rec.decision_id)+
      "|symbol="+DecisionFpNormalizeString(rec.symbol)+
      "|direction="+direction+
      "|entry="+DoubleToString(entry,8)+
      "|invalidation="+DoubleToString(rec.setup.invalidation,8)+
      "|sl="+DoubleToString(rec.setup.stop_loss,8)+
      "|tp1="+DoubleToString(rec.setup.tp1,8)+
      "|tp2="+DoubleToString(rec.setup.tp2,8)+
      "|final_tp="+DoubleToString(rec.setup.final_tp,8)+
      "|confidence="+DoubleToString(rec.setup.confidence,4)+
      "|action="+TradePolicyToString(rec.action)+
      "|reduce_risk="+(rec.reduce_risk?"true":"false")+
      "|spread_points="+DoubleToString(rec.spread_points,8)+
      "|regime="+EnumToString(rec.setup.reasons.regime)+
      "|strategy="+EnumToString(rec.setup.reasons.selected_strategy)+
      "|session="+EnumToString(rec.setup.reasons.session)+
      "|weight_version="+DecisionFpNormalizeString(rec.weight_version)+
      "|strategy_version="+DecisionFpNormalizeString(rec.strategy_version)+
      "|model_version="+DecisionFpNormalizeString(rec.model_version)+
      "|calibration_version="+DecisionFpNormalizeString(rec.calibration_version)+
      "|feature_schema_version="+DecisionFpNormalizeString(rec.feature_schema_version)+
      "|environment_schema_version="+DecisionFpNormalizeString(rec.environment_schema_version)+
      "|environment_key="+DecisionFpNormalizeString(rec.environment_key);
   return canonical;
  }

string DecisionFpSha256(const string canonical)
  {
   uchar data[];
   const uchar key[] = {};
   uchar result[];
   int copied=StringToCharArray(canonical,data,0,-1,CP_UTF8);
   if(copied<=0)return "";
   ArrayResize(data,copied-1);
   ResetLastError();
   int n=CryptEncode(CRYPT_HASH_SHA256,data,key,result);
   if(n!=32)return "";
   string hex="";
   for(int i=0;i<n;i++)hex+=StringFormat("%02X",(int)result[i]);
   return hex;
  }

string DecisionFingerprintFor(const TradeDecisionRecord &rec)
  {
   return DecisionFpSha256(DecisionFpCanonical(rec));
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Decision/DecisionFingerprint.mqh
// already inlined once under include guard: includes/Core/PipCalculator.mqh
class CSignalPublisher
  {
private:
   string m_filename; int m_fileHandle; long m_lastPublishedId; CSubscriberPlatform* m_platform; int m_timeoutMs; string m_apiKey; string m_weightVersion;
   bool TransmitOne(string endpoint,const string &payload); bool TransmitOnePatch(string endpoint,const string &payload); string BuildJsonPayload(const TradeDecisionRecord &dec); string BuildReasonsJsonArray(const SetupReasons &r); string BuildExtraJson(const TradeDecisionRecord &dec); string SignalIdFor(long decisionId);
   string BuildOutcomeJsonPayload(string signalId,string symbol,string direction,string outcome,double realizedR,double mfeR,double maeR,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string strategy,string exitReason,string environmentKey,string environmentJson,bool outcomeHistoryComplete);
   string BuildOutcomeJsonPayloadProvenance(string signalId,string symbol,string direction,string outcome,string resolution,string strategy,double realizedR,double mfeR,double maeR,double commissionCost,double spreadCost,double slippageCost,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string decisionFingerprint,datetime signalTime,datetime executionTime,datetime outcomeTime,bool excursionHistoryComplete=true,double commissionCashflow=0.0,double swapCashflow=0.0,double brokerFeeCashflow=0.0,bool cashflowsKnown=false,bool spreadCostKnown=false,bool slippageCostKnown=false,string environmentKey="",string environmentJson="{}",bool outcomeHistoryComplete=true);
public:
   void Init(string symbol,CSubscriberPlatform* platform,int timeoutMs=5000,string apiKey=""); void Deinit(); bool Publish(const TradeDecisionRecord &dec); bool PublishStatusUpdate(long decisionId,string status,string reason); bool PublishOutcome(string signalId,string symbol,string direction,string outcome,double realizedR,double mfeR,double maeR,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string strategy="",string exitReason="",string environmentKey="",string environmentJson="",bool outcomeHistoryComplete=false); bool PublishOutcome(string signalId,string symbol,string direction,string outcome,string resolution,string strategy,double realizedR,double mfeR,double maeR,double commissionCost,double spreadCost,double slippageCost,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string decisionFingerprint="",datetime signalTime=0,datetime executionTime=0,datetime outcomeTime=0,bool excursionHistoryComplete=true,double commissionCashflow=0.0,double swapCashflow=0.0,double brokerFeeCashflow=0.0,bool cashflowsKnown=false,bool spreadCostKnown=false,bool slippageCostKnown=false,string environmentKey="",string environmentJson="{}",bool outcomeHistoryComplete=true); void SetWeightVersion(string v){m_weightVersion=v;} string SignalIdForDecision(long decisionId){return SignalIdFor(decisionId);}
  };
void CSignalPublisher::Init(string symbol,CSubscriberPlatform* platform,int timeoutMs,string apiKey){m_lastPublishedId=0;m_platform=platform;m_timeoutMs=timeoutMs;m_apiKey=apiKey;m_weightVersion="";m_filename="MedisTouch_SignalFeed_"+symbol+".csv";bool exists=FileIsExist(m_filename);m_fileHandle=FileOpen(m_filename,FILE_READ|FILE_WRITE|FILE_CSV,',');if(m_fileHandle==INVALID_HANDLE)return;FileSeek(m_fileHandle,0,SEEK_END);if(!exists)FileWrite(m_fileHandle,"DecisionID","Time","Symbol","Direction","Entry","SL","TP1","TP2","FinalTP","Confidence","Action","SubscribersTargeted","SubscribersDelivered");}
void CSignalPublisher::Deinit(){if(m_fileHandle!=INVALID_HANDLE)FileClose(m_fileHandle);}
string CSignalPublisher::SignalIdFor(long decisionId){return "MT#"+IntegerToString(decisionId);}
string CSignalPublisher::BuildReasonsJsonArray(const SetupReasons &r){string items[];int n=0;if(r.trend_aligned){ArrayResize(items,n+1);items[n++]="HTF trend aligned";}if(r.inducement_valid){ArrayResize(items,n+1);items[n++]="Inducement sequence confirmed";}if(r.liquidity_swept){ArrayResize(items,n+1);items[n++]="Liquidity swept";}if(r.bos_confirmed){ArrayResize(items,n+1);items[n++]="BOS confirmed";}if(r.fresh_fvg){ArrayResize(items,n+1);items[n++]="Fresh FVG in zone";}if(r.sr_confluence){ArrayResize(items,n+1);items[n++]="S/R confluence";}if(r.premium_discount_ok){ArrayResize(items,n+1);items[n++]="Premium/discount location OK";}if(r.volume_confirmed){ArrayResize(items,n+1);items[n++]="Volume confirmed";}if(r.fib_in_zone){ArrayResize(items,n+1);items[n++]="Fibonacci zone confluence";}if(r.value_area_ok){ArrayResize(items,n+1);items[n++]="Value area location OK";}if(r.htf_ob_confluence){ArrayResize(items,n+1);items[n++]="HTF order block confluence";}if(n==0){ArrayResize(items,1);items[0]="Confluence-based setup";n=1;}string json="[";for(int i=0;i<n;i++){string esc=items[i];StringReplace(esc,"\"", "'");json+="\""+esc+"\"";if(i<n-1)json+=",";}json+="]";return json;}
string CSignalPublisher::BuildExtraJson(const TradeDecisionRecord &dec){SetupReasons r=dec.setup.reasons;double pip=CPipCalculator::PipSize(dec.symbol);bool isBuy=(dec.setup.type==ORDER_TYPE_BUY);double entry=isBuy?dec.setup.entry_top:dec.setup.entry_bottom;double pipsSl=(pip>0)?MathAbs(entry-dec.setup.stop_loss)/pip:0.0;double pipsTp1=(pip>0)?MathAbs(dec.setup.tp1-entry)/pip:0.0;double pipsTp2=(pip>0)?MathAbs(dec.setup.tp2-entry)/pip:0.0;double rrTp1=(pipsSl>0)?pipsTp1/pipsSl:0.0;double rrTp2=(pipsSl>0)?pipsTp2/pipsSl:0.0;return StringFormat("{\"pips_sl\":%.1f,\"pips_tp1\":%.1f,\"pips_tp2\":%.1f,\"rr_tp1\":%.2f,\"rr_tp2\":%.2f,\"sweep_grade\":\"%s\",\"bos_strength\":%.1f,\"time_decay\":%.1f,\"chase_dist_atr\":%.2f,\"chase_ok\":%s,\"news_risk\":\"%s\",\"news_label\":\"%s\",\"news_minutes_to_event\":%d,\"calibrated_probability\":%.1f,\"calibration_sample\":%d,\"calibration_has_enough_data\":%s,\"environment_memory_status\":\"%s\",\"environment_memory_sample\":%d,\"environment_memory_adjustment\":%.2f}",pipsSl,pipsTp1,pipsTp2,rrTp1,rrTp2,EnumToString(r.sweep_grade),r.bos_strength*100.0,r.time_decay*100.0,r.chase_dist_atr,r.chase_ok?"true":"false",EnumToString(r.news_risk),r.news_label,r.news_minutes_to_event,dec.setup.calibrated_probability,dec.setup.calibration_sample,dec.setup.calibration_has_enough_data?"true":"false",r.environment_memory_status,r.environment_memory_sample,r.environment_memory_adjustment);}
string DecisionFpIsoPayloadTime(datetime t){return IntegerToString((long)t);}

string CSignalPublisher::BuildJsonPayload(const TradeDecisionRecord &dec)
  {
   bool isBuy=(dec.setup.type==ORDER_TYPE_BUY);
   double entry=isBuy?dec.setup.entry_top:dec.setup.entry_bottom;
   string dir=isBuy?"BUY":"SELL";
   string tf=EnumToString((ENUM_TIMEFRAMES)dec.timeframe);
   StringReplace(tf,"PERIOD_","");
   SetupReasons r=dec.setup.reasons;
   return StringFormat("{\"signal_id\":\"%s\",\"decision_id\":%d,\"symbol\":\"%s\",\"direction\":\"%s\",\"entry\":%.8f,\"invalidation\":%.8f,\"sl\":%.8f,\"tp1\":%.8f,\"tp2\":%.8f,\"final_tp\":%.8f,\"confidence\":%.4f,\"reasons\":%s,\"timeframe\":\"%s\",\"time\":\"%s\",\"signal_time\":%I64d,\"decision_time\":%I64d,\"regime\":\"%s\",\"strategy\":\"%s\",\"session\":\"%s\",\"sweep_grade\":\"%s\",\"htf_ob_aligned\":%s,\"weight_version\":\"%s\",\"strategy_version\":\"%s\",\"model_version\":\"%s\",\"calibration_version\":\"%s\",\"feature_schema_version\":\"%s\",\"environment_schema_version\":\"%s\",\"environment_key\":\"%s\",\"decision_schema_version\":\"%s\",\"decision_fingerprint\":\"%s\",\"policy_action\":\"%s\",\"reduce_risk\":%s,\"spread_points\":%.8f,\"extra\":%s}",
      SignalIdFor(dec.decision_id),dec.decision_id,dec.symbol,dir,entry,dec.setup.invalidation,dec.setup.stop_loss,dec.setup.tp1,dec.setup.tp2,dec.setup.final_tp,dec.setup.confidence,BuildReasonsJsonArray(dec.setup.reasons),tf,TimeToString(dec.decided_time,TIME_DATE|TIME_SECONDS),dec.setup.creation_time,dec.decided_time,EnumToString(r.regime),EnumToString(r.selected_strategy),EnumToString(r.session),EnumToString(r.sweep_grade),r.htf_ob_confluence?"true":"false",dec.weight_version,dec.strategy_version,dec.model_version,dec.calibration_version,dec.feature_schema_version,dec.environment_schema_version,dec.environment_key,dec.decision_schema_version,dec.decision_fingerprint,TradePolicyToString(dec.action),dec.reduce_risk?"true":"false",dec.spread_points,BuildExtraJson(dec));
  }

bool CSignalPublisher::TransmitOne(string endpoint,const string &payload){uchar rawData[];int len=StringToCharArray(payload,rawData)-1;if(len<0)len=0;ArrayResize(rawData,len);char data[];ArrayResize(data,len);ArrayCopy(data,rawData);char result[];string resultHeaders;string headers="Content-Type: application/json\r\n";if(StringLen(m_apiKey)>0)headers+="X-API-Key: "+m_apiKey+"\r\n";ResetLastError();int status=WebRequest("POST",endpoint,headers,m_timeoutMs,data,result,resultHeaders);if(status==-1)return false;if(status<200||status>=300)return false;return true;}
bool CSignalPublisher::TransmitOnePatch(string endpoint,const string &payload){uchar rawData[];int len=StringToCharArray(payload,rawData)-1;if(len<0)len=0;ArrayResize(rawData,len);char data[];ArrayResize(data,len);ArrayCopy(data,rawData);char result[];string resultHeaders;string headers="Content-Type: application/json\r\n";if(StringLen(m_apiKey)>0)headers+="X-API-Key: "+m_apiKey+"\r\n";ResetLastError();int status=WebRequest("PATCH",endpoint,headers,m_timeoutMs,data,result,resultHeaders);if(status==-1)return false;if(status<200||status>=300)return false;return true;}
bool CSignalPublisher::Publish(const TradeDecisionRecord &dec){if(dec.action!=POLICY_SIGNAL_ONLY&&dec.action!=POLICY_EXECUTE_AND_SIGNAL)return false;if(dec.decision_id==m_lastPublishedId)return false;if(m_fileHandle==INVALID_HANDLE)return false;bool isBuy=(dec.setup.type==ORDER_TYPE_BUY);double entry=isBuy?dec.setup.entry_top:dec.setup.entry_bottom;string dir=isBuy?"BUY":"SELL";string payload=BuildJsonPayload(dec);int targeted=0;int delivered=0;if(m_platform!=NULL){Subscriber subs[];targeted=m_platform.GetActiveSubscribers(subs);for(int i=0;i<targeted;i++){bool ok=TransmitOne(subs[i].endpoint,payload);if(ok)delivered++;m_platform.RecordDelivery(subs[i].id,dec.decision_id,ok);}}FileWrite(m_fileHandle,dec.decision_id,TimeToString(dec.decided_time,TIME_DATE|TIME_MINUTES),dec.symbol,dir,entry,dec.setup.stop_loss,dec.setup.tp1,dec.setup.tp2,dec.setup.final_tp,dec.setup.confidence,EnumToString(dec.action),targeted,delivered);FileFlush(m_fileHandle);m_lastPublishedId=dec.decision_id;return true;}
bool CSignalPublisher::PublishStatusUpdate(long decisionId,string status,string reason){if(m_platform==NULL)return false;string signalId=SignalIdFor(decisionId);string escReason=reason;StringReplace(escReason,"\"", "'");string payload=StringFormat("{\"status\":\"%s\",\"reason\":\"%s\"}",status,escReason);Subscriber subs[];int targeted=m_platform.GetActiveSubscribers(subs);bool anyOk=false;for(int i=0;i<targeted;i++){string endpoint=subs[i].endpoint;int pos=StringFind(endpoint,"/signal");if(pos<0)continue;string patchUrl=StringSubstr(endpoint,0,pos)+"/signal/"+signalId+"/status";if(TransmitOnePatch(patchUrl,payload))anyOk=true;}return anyOk;}
string CSignalPublisher::BuildOutcomeJsonPayload(string signalId,string symbol,string direction,string outcome,double realizedR,double mfeR,double maeR,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string strategy,string exitReason,string environmentKey,string environmentJson,bool outcomeHistoryComplete){bool hasR=(outcome!="no_fill"&&outcome!="ambiguous");string realizedRStr=hasR?StringFormat("%.4f",realizedR):"null";string mfeRStr=hasR?StringFormat("%.4f",mfeR):"null";string maeRStr=hasR?StringFormat("%.4f",maeR):"null";string env=(StringLen(environmentJson)>0)?environmentJson:"{}";return StringFormat("{\"signal_id\":\"%s\",\"symbol\":\"%s\",\"direction\":\"%s\",\"outcome\":\"%s\",\"realized_r\":%s,\"mfe_r\":%s,\"mae_r\":%s,\"bars_held\":%d,\"bars_to_fill\":%d,\"filled\":%s,\"regime\":\"%s\",\"session\":\"%s\",\"sweep_grade\":\"%s\",\"htf_ob_aligned\":%s,\"weight_version\":\"%s\",\"confidence_at_signal\":%.2f,\"confidence_decayed\":%.2f,\"decay_bars\":%d,\"strategy\":\"%s\",\"exit_reason\":\"%s\",\"environment_key\":\"%s\",\"environment\":%s,\"outcome_history_complete\":%s}",signalId,symbol,direction,outcome,realizedRStr,mfeRStr,maeRStr,barsHeld,barsToFill,filled?"true":"false",regime,session,sweepGrade,htfObAligned?"true":"false",m_weightVersion,confidenceAtSignal,confidenceDecayed,decayBars,strategy,exitReason,environmentKey,env);}
bool CSignalPublisher::PublishOutcome(string signalId,string symbol,string direction,string outcome,double realizedR,double mfeR,double maeR,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string strategy,string exitReason,string environmentKey,string environmentJson,bool outcomeHistoryComplete){if(m_platform==NULL)return false;string payload=BuildOutcomeJsonPayload(signalId,symbol,direction,outcome,realizedR,mfeR,maeR,barsHeld,barsToFill,filled,regime,session,sweepGrade,htfObAligned,confidenceAtSignal,confidenceDecayed,decayBars,strategy,exitReason,environmentKey,environmentJson,outcomeHistoryComplete);Subscriber subs[];int targeted=m_platform.GetActiveSubscribers(subs);bool anyOk=false;for(int i=0;i<targeted;i++){string endpoint=subs[i].endpoint;int pos=StringFind(endpoint,"/signal");if(pos<0)continue;string outcomeUrl=StringSubstr(endpoint,0,pos)+"/outcome";if(TransmitOne(outcomeUrl,payload))anyOk=true;}return anyOk;}
string CSignalPublisher::BuildOutcomeJsonPayloadProvenance(string signalId,string symbol,string direction,string outcome,string resolution,string strategy,double realizedR,double mfeR,double maeR,double commissionCost,double spreadCost,double slippageCost,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string decisionFingerprint,datetime signalTime,datetime executionTime,datetime outcomeTime,bool excursionHistoryComplete,double commissionCashflow,double swapCashflow,double brokerFeeCashflow,bool cashflowsKnown,bool spreadCostKnown,bool slippageCostKnown,string environmentKey,string environmentJson,bool outcomeHistoryComplete)
  {
   bool hasR=(outcome!="no_fill"&&outcome!="ambiguous");
   string realizedRStr=hasR?StringFormat("%.4f",realizedR):"null";
   string mfeRStr=hasR?StringFormat("%.4f",mfeR):"null";
   string maeRStr=hasR?StringFormat("%.4f",maeR):"null";
   string commissionStr=(filled&&cashflowsKnown)?StringFormat("%.4f",commissionCost):"null";
   string spreadStr=(filled&&spreadCostKnown)?StringFormat("%.4f",spreadCost):"null";
   string slippageStr=(filled&&slippageCostKnown)?StringFormat("%.4f",slippageCost):"null";
   string commissionCashflowStr=(filled&&cashflowsKnown)?StringFormat("%.4f",commissionCashflow):"null";
   string swapCashflowStr=(filled&&cashflowsKnown)?StringFormat("%.4f",swapCashflow):"null";
   string brokerFeeCashflowStr=(filled&&cashflowsKnown)?StringFormat("%.4f",brokerFeeCashflow):"null";
   string env=(StringLen(environmentJson)>0)?environmentJson:"{}";
   return StringFormat("{\"signal_id\":\"%s\",\"symbol\":\"%s\",\"direction\":\"%s\",\"outcome\":\"%s\",\"resolution\":\"%s\",\"strategy\":\"%s\",\"realized_r\":%s,\"mfe_r\":%s,\"mae_r\":%s,\"commission_cost\":%s,\"spread_cost\":%s,\"slippage_cost\":%s,\"commission_cashflow\":%s,\"swap_cashflow\":%s,\"broker_fee_cashflow\":%s,\"bars_held\":%d,\"bars_to_fill\":%d,\"filled\":%s,\"regime\":\"%s\",\"session\":\"%s\",\"sweep_grade\":\"%s\",\"htf_ob_aligned\":%s,\"weight_version\":\"%s\",\"confidence_at_signal\":%.2f,\"confidence_decayed\":%.2f,\"decay_bars\":%d,\"decision_fingerprint\":\"%s\",\"signal_time\":%I64d,\"execution_time\":%I64d,\"outcome_time\":%I64d,\"outcome_history_complete\":%s,\"cashflows_known\":%s,\"spread_cost_known\":%s,\"slippage_cost_known\":%s,\"excursion_history_complete\":%s,\"environment_key\":\"%s\",\"environment\":%s}",
      signalId,symbol,direction,outcome,resolution,strategy,realizedRStr,mfeRStr,maeRStr,commissionStr,spreadStr,slippageStr,commissionCashflowStr,swapCashflowStr,brokerFeeCashflowStr,barsHeld,barsToFill,filled?"true":"false",regime,session,sweepGrade,htfObAligned?"true":"false",m_weightVersion,confidenceAtSignal,confidenceDecayed,decayBars,decisionFingerprint,signalTime,executionTime,outcomeTime,outcomeHistoryComplete?"true":"false",cashflowsKnown?"true":"false",spreadCostKnown?"true":"false",slippageCostKnown?"true":"false",excursionHistoryComplete?"true":"false",environmentKey,env);
  }
bool CSignalPublisher::PublishOutcome(string signalId,string symbol,string direction,string outcome,string resolution,string strategy,double realizedR,double mfeR,double maeR,double commissionCost,double spreadCost,double slippageCost,int barsHeld,int barsToFill,bool filled,string regime,string session,string sweepGrade,bool htfObAligned,double confidenceAtSignal,double confidenceDecayed,int decayBars,string decisionFingerprint,datetime signalTime,datetime executionTime,datetime outcomeTime,bool excursionHistoryComplete,double commissionCashflow,double swapCashflow,double brokerFeeCashflow,bool cashflowsKnown,bool spreadCostKnown,bool slippageCostKnown,string environmentKey,string environmentJson,bool outcomeHistoryComplete)
  {
   if(m_platform==NULL)return false;
   string payload=BuildOutcomeJsonPayloadProvenance(signalId,symbol,direction,outcome,resolution,strategy,realizedR,mfeR,maeR,commissionCost,spreadCost,slippageCost,barsHeld,barsToFill,filled,regime,session,sweepGrade,htfObAligned,confidenceAtSignal,confidenceDecayed,decayBars,decisionFingerprint,signalTime,executionTime,outcomeTime,excursionHistoryComplete,commissionCashflow,swapCashflow,brokerFeeCashflow,cashflowsKnown,spreadCostKnown,slippageCostKnown,environmentKey,environmentJson,outcomeHistoryComplete);
   Subscriber subs[];int targeted=m_platform.GetActiveSubscribers(subs);bool anyOk=false;
   for(int i=0;i<targeted;i++)
     {
      string endpoint=subs[i].endpoint;int pos=StringFind(endpoint,"/signal");if(pos<0)continue;
      string outcomeUrl=StringSubstr(endpoint,0,pos)+"/outcome";
      if(TransmitOne(outcomeUrl,payload))anyOk=true;
     }
   return anyOk;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Signals/SignalPublisher.mqh
// already inlined once under include guard: includes/Trading/EnvironmentStrategyMemory.mqh
class COutcomeTrackerLive;
COutcomeTrackerLive* g_activeOutcomeTracker=NULL;

struct OutcomeReplayDeal
  {
   ulong ticket;
   ulong positionId;
   long timeMsc;
   ENUM_DEAL_ENTRY entry;
   datetime time;
   double volume;
   double price;
   double profit;
   double commission;
   double swap;
   double fee;
  };

class COutcomeTrackerLive
  {
private:
   PendingSetup m_pending[]; int m_count; int m_maxBars; CSignalLogger* m_logger; CSignalPublisher* m_publisher; CCalibrationEngine m_calibration; CEnvironmentStrategyMemory* m_environmentMemory;
   bool m_calibrationEnabled; string m_symbol; ENUM_TIMEFRAMES m_entryTF; ENUM_FILL_POLICY m_fillPolicy; ENUM_TIMEFRAMES m_replayTF; OutcomeStats m_stats;
   double m_breakEvenAtR,m_partialAtR,m_partialFraction,m_trailATRMult,m_riskPercent; bool m_allowMinLotOverride,m_liveExecution;
   double m_commissionPerLot,m_spreadPoints,m_slippagePoints,m_decayHalfLifeBars; string m_weightVersion;
   double m_lastFinalizedR; bool m_lastFinalizedQualified;
   ulong m_seenDealTickets[];
   long m_rebuiltDecisionIds[];
   bool WasDecisionRebuilt(long decisionId)
     {
      for(int i=0;i<ArraySize(m_rebuiltDecisionIds);i++)
         if(m_rebuiltDecisionIds[i]==decisionId) return true;
      return false;
     }
   bool MarkDecisionRebuilt(long decisionId)
     {
      if(WasDecisionRebuilt(decisionId)) return true;
      int n=ArraySize(m_rebuiltDecisionIds);
      if(ArrayResize(m_rebuiltDecisionIds,n+1)!=n+1) return false;
      m_rebuiltDecisionIds[n]=decisionId;
      return true;
     }
   bool HistoryIdentityDigits(const string value)
     {
      int length=StringLen(value);
      if(length<=0) return false;
      for(int i=0;i<length;i++)
        {
         ushort ch=StringGetCharacter(value,i);
         if(ch<'0' || ch>'9') return false;
        }
      return true;
     }
   bool ParseHistoryDecisionComment(string comment,long &decisionId)
     {
      decisionId=0;
      int marker=StringFind(comment,"MT#");
      if(marker<0) return false;

      string payload=StringSubstr(comment,marker+3);
      int separator=StringFind(payload,":L");
      if(separator>=0)
        {
         string legPart=StringSubstr(payload,separator+2);
         payload=StringSubstr(payload,0,separator);
         if(!HistoryIdentityDigits(legPart)) return false;
         long leg=StringToInteger(legPart);
         // A valid broker comment must match the EA's canonical identity format.
         if(leg<0 || leg>2147483647 || IntegerToString(leg)!=legPart) return false;
        }
      else if(StringFind(payload,":")>=0)
        {
         // Reject malformed suffixes such as :Lx or :legacy instead of
         // truncating at the colon and attributing the deal to another setup.
         return false;
        }

      if(!HistoryIdentityDigits(payload)) return false;
      decisionId=(long)StringToInteger(payload);
      if(decisionId<=0 || IntegerToString(decisionId)!=payload) return false;
      return true;
     }
   bool HistoryDealDecisionId(ulong dealTicket,long &decisionId)
     {
      string dealComment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
      if(ParseHistoryDecisionComment(dealComment,decisionId)) return true;
      ulong orderTicket=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
      if(orderTicket>0)
        {
         string orderComment=HistoryOrderGetString(orderTicket,ORDER_COMMENT);
         if(ParseHistoryDecisionComment(orderComment,decisionId)) return true;
        }
      decisionId=0;
      return false;
     }
   int ReplayPositionIndex(const ulong &positionIds[],ulong positionId)
     {
      for(int i=0;i<ArraySize(positionIds);i++)
         if(positionIds[i]==positionId) return i;
      return -1;
     }
   bool DealAlreadyProcessed(ulong dealTicket)
     {
      if(dealTicket==0) return false;
      for(int i=0;i<ArraySize(m_seenDealTickets);i++)
         if(m_seenDealTickets[i]==dealTicket) return true;
      return false;
     }
   void RememberDeal(ulong dealTicket)
     {
      if(dealTicket==0 || DealAlreadyProcessed(dealTicket)) return;
      int n=ArraySize(m_seenDealTickets);
      if(ArrayResize(m_seenDealTickets,n+1)!=n+1) return;
      m_seenDealTickets[n]=dealTicket;
     }
   int Find(long id){for(int i=0;i<m_count;i++)if(m_pending[i].decisionId==id)return i;return -1;}
   double RValue(const PendingSetup &p) const{double ts=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE),tv=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);if(ts<=0.0||tv<=0.0)return 0.0;double riskLotsDistance=p.weightedRiskDistLots>0.0?p.weightedRiskDistLots:(p.mgmtRiskDist*p.lots);if(riskLotsDistance<=0.0)return 0.0;double oneR=riskLotsDistance*(tv/ts);return oneR>0.0?p.realizedPnL/oneR:0.0;}
   string EnvironmentJson(const PendingSetup &p) const{SetupReasons r=p.setup.reasons;string structure=EnumToString(r.sweep_grade)+"/"+IntegerToString((int)r.breakout_class)+"/"+IntegerToString((int)r.reversion_class)+"/"+IntegerToString((int)r.keylevel_reaction);return StringFormat("{\"regime\":\"%s\",\"volatility_state\":\"%s\",\"trend_strength\":%.3f,\"liquidity_score\":%.3f,\"liquidity_bucket\":%d,\"news_state\":\"%s\",\"session\":\"%s\",\"spread_points\":%.2f,\"point_size\":%.10f,\"atr_value\":%.10f,\"atr_regime\":\"%s\",\"htf_ob_aligned\":%s,\"htf_ob_state\":\"%s\",\"value_area_zone\":\"%s\",\"market_phase\":\"%s\",\"market_structure\":\"%s\",\"bos_strength\":%.3f,\"sweep_grade\":\"%s\"}",EnumToString(r.regime),EnumToString(r.vol_regime),r.trend_strength,r.liquidity_score,r.liquidity_bucket,EnumToString(r.news_risk),EnumToString(r.session),r.spread_points,r.point_size,r.atr_value,EnumToString(r.vol_regime),r.htf_ob_confluence?"true":"false",EnumToString(r.htf_ob_state),EnumToString(r.va_zone),EnumToString(r.phase),structure,r.bos_strength,EnumToString(r.sweep_grade));}
   void Finalize(int idx,string exitReason,double exitPrice,datetime outcomeTime){m_lastFinalizedR=0.0;m_lastFinalizedQualified=false;if(idx<0||idx>=m_count)return;PendingSetup p=m_pending[idx];datetime resolvedAt=outcomeTime;if(resolvedAt<=0)resolvedAt=TimeCurrent();double rr=RValue(p);bool sized=p.filled&&p.lots>0.0;string coarseOutcome="scratch";if(!p.filled)coarseOutcome="no_fill";else if(p.realizedPnL>0.0000001)coarseOutcome="win";else if(p.realizedPnL<-0.0000001)coarseOutcome="loss";if((!p.outcomeHistoryComplete||!p.cashflowsKnown)&&p.filled)coarseOutcome="ambiguous";if(exitReason=="Ambiguous_SLandBE"||exitReason=="Ambiguous_SLandPartial"||exitReason=="Ambiguous_SLandTP"||exitReason=="Ambiguous_NettingReversal")coarseOutcome="ambiguous";m_lastFinalizedR=rr;m_lastFinalizedQualified=(sized&&p.outcomeHistoryComplete&&p.cashflowsKnown&&coarseOutcome=="win"&&p.realizedPnL>0.0000001);if(sized&&coarseOutcome!="ambiguous"&&coarseOutcome!="no_fill"){if(coarseOutcome=="win")m_stats.wins++;else if(coarseOutcome=="loss")m_stats.losses++;else m_stats.scratches++;m_stats.resolvedCount++;m_stats.netPnL+=p.realizedPnL;if(p.realizedPnL>0)m_stats.grossProfit+=p.realizedPnL;if(p.realizedPnL<0)m_stats.grossLoss+=-p.realizedPnL;m_stats.totalCommission+=p.totalCommission;m_stats.totalSpreadCost+=p.totalSpreadCost;m_stats.totalSlippageCost+=p.totalSlippageCost;m_stats.sumRMultiple+=rr;if(m_calibrationEnabled)m_calibration.Record(p.confidenceAtSignal,p.realizedPnL);if(m_environmentMemory!=NULL&&p.excursionHistoryComplete){bool buy=p.setup.type==ORDER_TYPE_BUY;double mfeR=0.0,maeR=0.0;if(p.mgmtRiskDist>0.0){mfeR=buy?(p.mfePrice-p.entryRef)/p.mgmtRiskDist:(p.entryRef-p.maePrice)/p.mgmtRiskDist;maeR=buy?(p.entryRef-p.maePrice)/p.mgmtRiskDist:(p.maePrice-p.entryRef)/p.mgmtRiskDist;}m_environmentMemory.RecordOutcome(p.setup.reasons,p.setup.reasons.selected_strategy,rr,maeR,mfeR,p.barsElapsed,resolvedAt);}}else if(coarseOutcome=="ambiguous")m_stats.ambiguous++;if(m_logger!=NULL)m_logger.LogOutcome(p,m_symbol,m_entryTF,exitReason,exitPrice,m_fillPolicy,resolvedAt);if(m_publisher!=NULL&&p.decisionId>0){bool buy=p.setup.type==ORDER_TYPE_BUY;double mfeR=0.0,maeR=0.0;if(p.filled&&p.mgmtRiskDist>0){double mfe=buy?(p.mfePrice-p.entryRef):(p.entryRef-p.mfePrice);double mae=buy?(p.entryRef-p.maePrice):(p.maePrice-p.entryRef);mfeR=mfe/p.mgmtRiskDist;maeR=mae/p.mgmtRiskDist;}if(!p.excursionHistoryComplete){mfeR=0.0;maeR=0.0;}string signalId=m_publisher.SignalIdForDecision(p.decisionId);string strategy=EnumToString(p.setup.reasons.selected_strategy);string envKey="";if(m_environmentMemory!=NULL)envKey=m_environmentMemory.Key(p.setup.reasons);m_publisher.PublishOutcome(signalId,m_symbol,buy?"BUY":"SELL",coarseOutcome,exitReason,strategy,rr,mfeR,maeR,p.totalCommission,p.totalSpreadCost,p.totalSlippageCost,p.barsElapsed,p.barsToFill,p.filled,EnumToString(p.setup.reasons.regime),EnumToString(p.setup.reasons.session),EnumToString(p.setup.reasons.sweep_grade),p.setup.reasons.htf_ob_confluence,p.confidenceAtSignal,p.confidenceDecayed,p.decayBars,p.decision_fingerprint,p.setup.creation_time,p.fillTime,resolvedAt,p.excursionHistoryComplete,p.totalCommissionCashflow,p.totalSwapCashflow,p.totalBrokerFeeCashflow,p.cashflowsKnown,p.spreadCostKnown,p.slippageCostKnown,envKey,EnvironmentJson(p),p.outcomeHistoryComplete);}for(int j=idx;j<m_count-1;j++)m_pending[j]=m_pending[j+1];m_count--;ArrayResize(m_pending,m_count);}
   void SimFill(int i,double price,datetime t){if(i<0||i>=m_count||m_pending[i].filled)return;PendingSetup p=m_pending[i];p.filled=true;p.fillTime=t;p.barsToFill=0;p.entryRef=price;p.entryFillPrice=price;p.mfePrice=price;p.maePrice=price;p.riskDist=MathAbs(price-p.setup.stop_loss);p.mgmtRiskDist=p.riskDist;m_pending[i]=p;}
public:
   COutcomeTrackerLive():m_count(0),m_maxBars(100),m_logger(NULL),m_publisher(NULL),m_environmentMemory(NULL),m_calibrationEnabled(false),m_symbol(""),m_entryTF(PERIOD_CURRENT),m_fillPolicy(FILL_CONSERVATIVE),m_replayTF(PERIOD_M1),m_breakEvenAtR(1.0),m_partialAtR(2.0),m_partialFraction(0.5),m_trailATRMult(1.5),m_riskPercent(0.5),m_allowMinLotOverride(true),m_liveExecution(true),m_commissionPerLot(7.0),m_spreadPoints(10.0),m_slippagePoints(2.0),m_decayHalfLifeBars(12.0),m_weightVersion(""),m_lastFinalizedR(0.0),m_lastFinalizedQualified(false){ZeroMemory(m_stats);g_activeOutcomeTracker=GetPointer(this);}
   void Init(CSignalLogger* logger,string symbol,ENUM_TIMEFRAMES tf,int maxBars,ENUM_FILL_POLICY fp=FILL_CONSERVATIVE,ENUM_TIMEFRAMES replayTF=PERIOD_M1){m_logger=logger;m_symbol=symbol;m_entryTF=tf;m_maxBars=MathMax(5,maxBars);m_fillPolicy=fp;m_replayTF=replayTF;m_count=0;m_lastFinalizedR=0.0;m_lastFinalizedQualified=false;ArrayResize(m_pending,0);ArrayResize(m_seenDealTickets,0);ArrayResize(m_rebuiltDecisionIds,0);ZeroMemory(m_stats);}
   void ConfigureExecutionMode(bool live){m_liveExecution=live;}void ConfigureSimulation(double risk,bool allow,double be,double partial,double frac,double trail,double comm,double spread,double slip){m_riskPercent=risk;m_allowMinLotOverride=allow;m_breakEvenAtR=be;m_partialAtR=partial;m_partialFraction=MathMax(0.0,MathMin(1.0,frac));m_trailATRMult=trail;m_commissionPerLot=MathMax(0.0,comm);m_spreadPoints=MathMax(0.0,spread);m_slippagePoints=MathMax(0.0,slip);}void ConfigureCalibration(bool enabled,int minSample=30){m_calibrationEnabled=enabled;m_calibration.Init(m_symbol,minSample);}void ConfigureConfidenceDecay(double halfLife=12.0){m_decayHalfLifeBars=halfLife;}void ConfigurePublishing(CSignalPublisher* p,string version){m_publisher=p;m_weightVersion=version;}void ConfigureEnvironmentMemory(CEnvironmentStrategyMemory* memory){m_environmentMemory=memory;}
   int ActiveCount()const{return m_count;}double LastFinalizedR()const{return m_lastFinalizedR;}bool LastFinalizedQualified()const{return m_lastFinalizedQualified;}OutcomeStats GetStats()const{return m_stats;}double GetCalibratedProbability(double confidence,int &sample,bool &enough)const{return m_calibration.GetCalibratedProbability(confidence,sample,enough);}
   void AddSetup(TradeSetup &setup,long decisionId=-1,string decisionFingerprint=""){if(!setup.active||decisionId<=0||Find(decisionId)>=0)return;PendingSetup p;ZeroMemory(p);p.setup=setup;p.decisionId=decisionId;p.decision_fingerprint=decisionFingerprint;p.entryRef=ResolveExecutionEntry(setup);p.riskDist=MathAbs(p.entryRef-setup.stop_loss);p.sizingEntryPrice=p.entryRef;p.mgmtRiskDist=p.riskDist;p.weightedRiskDistLots=0.0;p.mfePrice=p.entryRef;p.maePrice=p.entryRef;p.currentSL=setup.stop_loss;p.confidenceAtSignal=setup.confidence;p.confidenceDecayed=setup.confidence;p.cashflowsKnown=true;p.outcomeHistoryComplete=true;p.excursionHistoryComplete=true;int n=m_count++;ArrayResize(m_pending,m_count);m_pending[n]=p;}
   // Rebuild only a currently-live decision from broker deal history. Completed
   // decisions are intentionally not replayed here: replaying them on every restart
   // would duplicate calibration samples and published outcomes. The method first
   // validates the entire candidate ledger against current broker exposure, then
   // mutates tracker state; if validation fails the caller uses an ambiguous snapshot.
   bool RebuildOpenDecisionFromHistory(TradeSetup &setup,long decisionId,ulong livePositionId,ulong magic)
     {
      if(decisionId<=0 || livePositionId==0 || magic==0) return false;
      if(WasDecisionRebuilt(decisionId)) return true;
      if(Find(decisionId)>=0) return false;

      datetime fromTime=setup.creation_time>0 ? setup.creation_time-1 : 0;
      datetime toTime=TimeCurrent();
      if(toTime<fromTime || !HistorySelect(fromTime,toTime)) return false;

      ulong positionIds[];
      if(ArrayResize(positionIds,1)!=1) return false;
      positionIds[0]=livePositionId;
      bool liveEntryConfirmed=false;
      int totalDeals=HistoryDealsTotal();

      // Pass 1: enumerate every position identifier tied to this decision using
      // entry deal identity or its originating order comment. We require the
      // live position's original entry to be provable before trusting its history.
      for(int i=0;i<totalDeals;i++)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0) continue;
         if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=m_symbol) continue;
         if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=magic) continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
         long foundDecision=0;
         if(!HistoryDealDecisionId(dealTicket,foundDecision) || foundDecision!=decisionId) continue;
         ulong positionId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
         if(positionId==0) return false;
         if(positionId==livePositionId) liveEntryConfirmed=true;
         if(ReplayPositionIndex(positionIds,positionId)<0)
           {
            int n=ArraySize(positionIds);
            if(ArrayResize(positionIds,n+1)!=n+1) return false;
            positionIds[n]=positionId;
           }
        }
      if(!liveEntryConfirmed || ArraySize(positionIds)==0) return false;

      // Pass 2: materialize a deterministic per-deal ledger across every child
      // position in this decision. A netting reversal cannot be safely reduced to
      // ordinary close/open rows here, so it deliberately fails closed.
      OutcomeReplayDeal deals[];
      double expectedRemaining[];
      if(ArrayResize(expectedRemaining,ArraySize(positionIds))!=ArraySize(positionIds)) return false;
      ArrayInitialize(expectedRemaining,0.0);
      for(int i=0;i<totalDeals;i++)
        {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket==0) continue;
         if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=m_symbol) continue;
         if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=magic) continue;
         ulong positionId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
         int pidx=ReplayPositionIndex(positionIds,positionId);
         if(pidx<0) continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_INOUT) return false;
         if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;

         OutcomeReplayDeal row;
         row.ticket=dealTicket;
         row.positionId=positionId;
         row.timeMsc=(long)HistoryDealGetInteger(dealTicket,DEAL_TIME_MSC);
         row.time=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
         row.entry=entry;
         row.volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
         row.price=HistoryDealGetDouble(dealTicket,DEAL_PRICE);
         row.profit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
         row.commission=HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
         row.swap=HistoryDealGetDouble(dealTicket,DEAL_SWAP);
         row.fee=HistoryDealGetDouble(dealTicket,DEAL_FEE);
         if(row.volume<=0.0 || row.price<=0.0 || row.time<=0) return false;

         int n=ArraySize(deals);
         if(ArrayResize(deals,n+1)!=n+1) return false;
         deals[n]=row;
         if(entry==DEAL_ENTRY_IN)
            expectedRemaining[pidx]+=row.volume;
         else
           {
            expectedRemaining[pidx]-=row.volume;
            double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
            double tolerance=MathMax(1e-7,step*0.51);
            if(expectedRemaining[pidx]<-tolerance) return false;
            if(expectedRemaining[pidx]<0.0) expectedRemaining[pidx]=0.0;
           }
        }
      if(ArraySize(deals)==0) return false;

      // Broker open positions must match the volume reconstructed from all entries
      // and partial exits. This catches missing history rows, reversals and bad IDs.
      double actualRemaining[];
      if(ArrayResize(actualRemaining,ArraySize(positionIds))!=ArraySize(positionIds)) return false;
      ArrayInitialize(actualRemaining,0.0);
      for(int i=0;i<PositionsTotal();i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         int pidx=ReplayPositionIndex(positionIds,positionId);
         if(pidx>=0) actualRemaining[pidx]+=PositionGetDouble(POSITION_VOLUME);
        }
      double volumeStep=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      double volumeTolerance=MathMax(1e-7,volumeStep*0.51);
      for(int i=0;i<ArraySize(positionIds);i++)
         if(MathAbs(expectedRemaining[i]-actualRemaining[i])>volumeTolerance) return false;
      if(actualRemaining[ReplayPositionIndex(positionIds,livePositionId)]<=0.0) return false;

      // Sort deterministically by broker millisecond timestamp then unique deal ticket.
      for(int i=1;i<ArraySize(deals);i++)
        {
         OutcomeReplayDeal key=deals[i];
         int j=i-1;
         while(j>=0 && (deals[j].timeMsc>key.timeMsc ||
               (deals[j].timeMsc==key.timeMsc && deals[j].ticket>key.ticket)))
           {
            deals[j+1]=deals[j];
            j--;
           }
         deals[j+1]=key;
        }

      AddSetup(setup,decisionId);
      int trackerIndex=Find(decisionId);
      if(trackerIndex<0) return false;
      PendingSetup state=m_pending[trackerIndex];
      state.outcomeHistoryComplete=true;
      state.cashflowsKnown=true;
      state.excursionHistoryComplete=false;
      m_pending[trackerIndex]=state;

      // Replay historical partial closes but keep the parent decision active while
      // any part of it is currently open. Every deal ticket is remembered so the
      // terminal's subsequent transaction callback cannot double-count it.
      for(int i=0;i<ArraySize(deals);i++)
        {
         OutcomeReplayDeal row=deals[i];
         if(row.entry==DEAL_ENTRY_IN)
           {
            if(!MarkExecuted(decisionId,row.price,row.time,row.volume,row.ticket,row.commission,row.swap,row.fee,true))
              {
               MarkHistoryIncomplete(decisionId);
               return false;
              }
           }
         else
           {
            double net=row.profit+row.commission+row.swap+row.fee;
            if(!MarkClosed(decisionId,row.price,row.time,net,row.commission,row.swap,row.fee,
                           true,"Recovered_Partial",row.ticket,row.volume,true))
              {
               MarkHistoryIncomplete(decisionId);
               return false;
              }
           }
        }
      return MarkDecisionRebuilt(decisionId);
     }

   bool MarkExecuted(long id,double fill,datetime t,double volume,ulong dealTicket=0,double commission=0.0,double swap=0.0,double fee=0.0,bool cashflowsKnown=true)
     {
      m_lastFinalizedR=0.0;
      m_lastFinalizedQualified=false;
      if(DealAlreadyProcessed(dealTicket)) return true;
      int i=Find(id);
      if(i<0) return false;
      if(!MathIsValidNumber(fill) || !MathIsValidNumber(volume) || fill<=0.0 || volume<=0.0)
        {
         // Do not let NaN/Inf values poison the parent's P&L or volume state.
         // The real broker fill still requires reconciliation before learning.
         MarkHistoryIncomplete(id);
         return false;
        }

      bool costValuesValid=MathIsValidNumber(commission) &&
                           MathIsValidNumber(swap) &&
                           MathIsValidNumber(fee);
      bool timeValid=(t>0);
      if(!costValuesValid)
        {
         if(!MathIsValidNumber(commission)) commission=0.0;
         if(!MathIsValidNumber(swap)) swap=0.0;
         if(!MathIsValidNumber(fee)) fee=0.0;
        }
      if(!timeValid) t=TimeCurrent();

      PendingSetup p=m_pending[i];
      if(!timeValid || !costValuesValid)
        {
         p.outcomeHistoryComplete=false;
         p.excursionHistoryComplete=false;
        }
      double nextPnL=p.realizedPnL+commission+swap+fee;
      double nextCommissionCashflow=p.totalCommissionCashflow+commission;
      double nextSwapCashflow=p.totalSwapCashflow+swap;
      double nextFeeCashflow=p.totalBrokerFeeCashflow+fee;
      double nextCommission=p.totalCommission+MathMax(0.0,-commission);
      bool totalsValid=MathIsValidNumber(nextPnL) &&
                       MathIsValidNumber(nextCommissionCashflow) &&
                       MathIsValidNumber(nextSwapCashflow) &&
                       MathIsValidNumber(nextFeeCashflow) &&
                       MathIsValidNumber(nextCommission);
      if(totalsValid)
        {
         p.realizedPnL=nextPnL;
         p.totalCommissionCashflow=nextCommissionCashflow;
         p.totalSwapCashflow=nextSwapCashflow;
         p.totalBrokerFeeCashflow=nextFeeCashflow;
         p.totalCommission=nextCommission;
        }
      else
        {
         p.outcomeHistoryComplete=false;
         p.cashflowsKnown=false;
        }
      p.cashflowsKnown=p.cashflowsKnown && cashflowsKnown && costValuesValid && totalsValid;

      double stopLoss=p.setup.stop_loss;
      double riskIncrement=(MathIsValidNumber(stopLoss) && stopLoss>0.0)
                           ? MathAbs(fill-stopLoss)*volume : 0.0;
      if(!MathIsValidNumber(riskIncrement))
        {
         riskIncrement=0.0;
         p.outcomeHistoryComplete=false;
         p.excursionHistoryComplete=false;
        }

      if(p.filled)
        {
         // Multiple partial fills/target legs share a parent decision. Keep a
         // true volume-weighted fill price, but do not train MFE/MAE on a single
         // path when that parent contains fills at different prices/times.
         if(!MathIsValidNumber(p.lots) || p.lots<=0.0 ||
            !MathIsValidNumber(p.entryFillPrice) || p.entryFillPrice<=0.0)
           {
            p.outcomeHistoryComplete=false;
            p.excursionHistoryComplete=false;
            p.cashflowsKnown=false;
            m_pending[i]=p;
            return false;
           }
         double totalLots=p.lots+volume;
         double totalNotional=p.entryFillPrice*p.lots+fill*volume;
         double nextRemaining=p.remainingLots+volume;
         if(!MathIsValidNumber(totalLots) || totalLots<=p.lots ||
            !MathIsValidNumber(nextRemaining) || nextRemaining<=p.remainingLots)
           {
            p.outcomeHistoryComplete=false;
            p.excursionHistoryComplete=false;
            m_pending[i]=p;
            return false;
           }
         p.lots=totalLots;
         p.remainingLots=nextRemaining;
         if(MathIsValidNumber(totalNotional) && totalNotional>0.0)
           {
            double averageFill=totalNotional/totalLots;
            if(MathIsValidNumber(averageFill) && averageFill>0.0)
              {
               p.entryFillPrice=averageFill;
               p.entryRef=averageFill;
              }
            else
               p.outcomeHistoryComplete=false;
           }
         else
            p.outcomeHistoryComplete=false;

         double weightedRisk=p.weightedRiskDistLots+riskIncrement;
         if(MathIsValidNumber(weightedRisk) && weightedRisk>=0.0)
            p.weightedRiskDistLots=weightedRisk;
         else
            p.outcomeHistoryComplete=false;
         p.excursionHistoryComplete=false;
         p.mfePrice=0.0;
         p.maePrice=0.0;
         m_pending[i]=p;
         RememberDeal(dealTicket);
         return true;
        }

      p.filled=true;
      p.entryFillPrice=fill;
      p.entryRef=fill;
      p.fillTime=t;
      p.barsToFill=0;
      p.lots=volume;
      p.remainingLots=volume;
      p.riskDist=riskIncrement/volume;
      p.mgmtRiskDist=p.riskDist;
      p.weightedRiskDistLots=riskIncrement;
      p.mfePrice=fill;
      p.maePrice=fill;
      p.currentSL=(MathIsValidNumber(stopLoss) && stopLoss>0.0) ? stopLoss : 0.0;
      if(riskIncrement<=0.0)
        {
         p.outcomeHistoryComplete=false;
         p.excursionHistoryComplete=false;
        }
      m_pending[i]=p;
      RememberDeal(dealTicket);
      return true;
     }
   bool RestoreExecuted(TradeSetup &setup,long id,double fill,datetime t,double volume)
     {
      AddSetup(setup,id);
      if(!MarkExecuted(id,fill,t,volume,0,0.0,0.0,0.0,false)) return false;
      int i=Find(id);if(i<0)return false;
      PendingSetup p=m_pending[i];
      // A current-position snapshot contains remaining volume, not complete
      // entry/partial-exit deal history. Keep it out of calibration and learning
      // until broker history has been reconciled.
      p.cashflowsKnown=false;p.outcomeHistoryComplete=false;p.excursionHistoryComplete=false;
      m_pending[i]=p;
      return true;
     }
   void MarkHistoryIncomplete(long id)
     {
      int i=Find(id);if(i<0)return;
      PendingSetup p=m_pending[i];p.outcomeHistoryComplete=false;p.cashflowsKnown=false;p.excursionHistoryComplete=false;m_pending[i]=p;
     }
   bool MarkClosed(long id,double exitPrice,datetime t,double netPnl,double commission,double swap,double fee,bool stillOpen,string outcome,ulong dealTicket=0,double closedVolume=0.0,bool cashflowsKnown=true)
     {
      m_lastFinalizedR=0.0;
      m_lastFinalizedQualified=false;
      if(DealAlreadyProcessed(dealTicket)) return true;
      int i=Find(id);
      if(i<0) return false;
      PendingSetup p=m_pending[i];
      if(!p.filled) return false;

      bool timeValid=(t>0);
      bool exitPriceValid=MathIsValidNumber(exitPrice) && exitPrice>0.0;
      bool pnlValid=MathIsValidNumber(netPnl);
      bool volumeValid=MathIsValidNumber(closedVolume) && closedVolume>=0.0;
      bool costValuesValid=MathIsValidNumber(commission) &&
                           MathIsValidNumber(swap) &&
                           MathIsValidNumber(fee);
      if(!timeValid) t=TimeCurrent();
      if(!exitPriceValid) exitPrice=0.0;
      if(!pnlValid) netPnl=0.0;
      if(!costValuesValid)
        {
         if(!MathIsValidNumber(commission)) commission=0.0;
         if(!MathIsValidNumber(swap)) swap=0.0;
         if(!MathIsValidNumber(fee)) fee=0.0;
        }
      if(!volumeValid) closedVolume=0.0;

      // Incomplete broker values must never fall through into a scratch label
      // (NaN comparisons are false in MQL5). Continue tracking the close using
      // only finite values, but mark the outcome ineligible for calibration.
      if(!timeValid || !exitPriceValid || !pnlValid || !volumeValid)
        {
         p.outcomeHistoryComplete=false;
         p.excursionHistoryComplete=false;
        }
      if(!costValuesValid)
        {
         p.cashflowsKnown=false;
         p.outcomeHistoryComplete=false;
        }

      double nextPnL=p.realizedPnL+netPnl;
      double nextCommissionCashflow=p.totalCommissionCashflow+commission;
      double nextSwapCashflow=p.totalSwapCashflow+swap;
      double nextFeeCashflow=p.totalBrokerFeeCashflow+fee;
      double nextCommission=p.totalCommission+MathMax(0.0,-commission);
      bool totalsValid=MathIsValidNumber(nextPnL) &&
                       MathIsValidNumber(nextCommissionCashflow) &&
                       MathIsValidNumber(nextSwapCashflow) &&
                       MathIsValidNumber(nextFeeCashflow) &&
                       MathIsValidNumber(nextCommission);
      if(totalsValid)
        {
         p.realizedPnL=nextPnL;
         p.totalCommissionCashflow=nextCommissionCashflow;
         p.totalSwapCashflow=nextSwapCashflow;
         p.totalBrokerFeeCashflow=nextFeeCashflow;
         p.totalCommission=nextCommission;
        }
      else
        {
         p.cashflowsKnown=false;
         p.outcomeHistoryComplete=false;
        }
      p.cashflowsKnown=p.cashflowsKnown && cashflowsKnown &&
                       costValuesValid && pnlValid && totalsValid;

      if(closedVolume>0.0)
        {
         if(!MathIsValidNumber(p.remainingLots) || p.remainingLots<0.0 ||
            closedVolume>p.remainingLots+1e-8)
            p.outcomeHistoryComplete=false;
         double left=p.remainingLots-closedVolume;
         p.remainingLots=(MathIsValidNumber(left) ? MathMax(0.0,left) : 0.0);
        }
      if(!stillOpen && p.remainingLots>1e-8)
         p.outcomeHistoryComplete=false;

      // Swap and broker fees are not spread/slippage. Keep their signed values
      // separate, even for partial exits and manually resolved broker outcomes.
      RememberDeal(dealTicket);
      m_pending[i]=p;
      if(stillOpen) return true;
      Finalize(i,outcome,exitPrice,t);
      return true;
     }
   void Update(CTFContext* ctx){if(ctx==NULL||ctx.candles.Total()<3||ctx.candles.Timeframe()!=m_entryTF)return;CandleData bar=ctx.candles.GetCandle(1);if(bar.time<=0)return;for(int i=m_count-1;i>=0;i--){PendingSetup p=m_pending[i];bool buy=p.setup.type==ORDER_TYPE_BUY;int fshift=iBarShift(m_symbol,m_entryTF,p.fillTime,false);datetime creationBar=0;if(!p.filled){int shift=iBarShift(m_symbol,m_entryTF,p.setup.creation_time,false);creationBar=shift>=0?iTime(m_symbol,m_entryTF,shift):p.setup.creation_time;}if(!p.filled&&!m_liveExecution&&bar.time>creationBar){bool touched=buy?(bar.low<=p.entryRef):(bar.high>=p.entryRef);if(touched)SimFill(i,p.entryRef,bar.time);}if(!p.filled){p.barsElapsed++;p.lastBarTime=bar.time;m_pending[i]=p;if(p.barsElapsed>=m_maxBars)Finalize(i,"no_fill",bar.close,bar.time);continue;}if(fshift>=0){datetime fillBar=iTime(m_symbol,m_entryTF,fshift);if(bar.time<=fillBar)continue;}if(p.lastBarTime==bar.time)continue;p.barsElapsed++;p.lastBarTime=bar.time;if(buy){if(bar.high>p.mfePrice)p.mfePrice=bar.high;if(bar.low<p.maePrice)p.maePrice=bar.low;}else{if(bar.low<p.mfePrice)p.mfePrice=bar.low;if(bar.high>p.maePrice)p.maePrice=bar.high;}if(m_decayHalfLifeBars>0){p.decayBars=p.barsElapsed;p.confidenceDecayed=p.confidenceAtSignal*MathPow(0.5,(double)p.decayBars/m_decayHalfLifeBars);}m_pending[i]=p;if(p.barsElapsed>=m_maxBars)Finalize(i,"timeout",bar.close,bar.time);}}
   bool GetFillState(datetime creationTime,long id,bool &filled,double &fillPrice,datetime &fillTime,int &barsToFill){for(int i=0;i<m_count;i++)if(m_pending[i].setup.creation_time==creationTime&&(id<0||m_pending[i].decisionId==id)){filled=m_pending[i].filled;fillPrice=m_pending[i].entryFillPrice;fillTime=m_pending[i].fillTime;barsToFill=m_pending[i].barsToFill;return true;}return false;}
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/OutcomeTrackerLive.mqh
// BEGIN INLINED MODULE: includes/Trading/AccuracyPolicyShadow.mqh
//+------------------------------------------------------------------+
//| Trading/AccuracyPolicyShadow.mqh                                 |
//| Versioned evidence capture for accuracy-policy research.          |
//| This module is deliberately non-authoritative: it never blocks,   |
//| sizes, modifies, or submits an order.                              |
//+------------------------------------------------------------------+
#ifndef ACCURACYPOLICYSHADOW_MQH
#define ACCURACYPOLICYSHADOW_MQH

// already inlined once under include guard: includes/Core/Config.mqh

string AccuracyPolicyV3ShadowSummary(const TradeSetup &setup)
  {
   bool calibrationReady =
      setup.calibration_has_enough_data &&
      setup.calibration_sample >= 30 &&
      MathIsValidNumber(setup.calibrated_probability) &&
      setup.calibrated_probability >= 0.0 &&
      setup.calibrated_probability <= 100.0;

   string calibrationState = calibrationReady ? "READY" : "INSUFFICIENT_OR_INVALID";
   string environmentState = EnumToString(setup.reasons.regime) + "/" +
                             EnumToString(setup.reasons.vol_regime) + "/" +
                             EnumToString(setup.reasons.news_risk);
   string strategyState = EnumToString(setup.reasons.selected_strategy);

   return StringFormat(
      "policy=ACCURACY_V3_SHADOW;verdict=OBSERVE_ONLY;raw_confidence=%.2f;calibrated_probability=%.2f;calibration_samples=%d;calibration_state=%s;environment=%s;env_score=%.4f;exec_score=%.4f;env_exec_confidence=%.2f;contradiction_penalty=%.4f;selected_strategy=%s;selected_strategy_score=%.2f;momentum_score=%.2f;breakout_score=%.2f;reversion_score=%.2f;keylevel_score=%.2f;smc_structural_valid=%s;smc_failure=%s;execution_effect=NONE",
      setup.confidence,
      setup.calibrated_probability,
      setup.calibration_sample,
      calibrationState,
      environmentState,
      setup.reasons.env_score,
      setup.reasons.exec_score,
      setup.reasons.env_exec_confidence,
      setup.reasons.contradiction_penalty,
      strategyState,
      setup.reasons.selected_strategy_score,
      setup.reasons.momentum_score,
      setup.reasons.breakout_score,
      setup.reasons.reversion_score,
      setup.reasons.keylevel_score,
      setup.reasons.smc_structural_valid ? "true" : "false",
      setup.reasons.smc_failure_reason
   );
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/AccuracyPolicyShadow.mqh
// BEGIN INLINED MODULE: includes/Trading/DailyTradeTarget.mqh
//+------------------------------------------------------------------+
//| Trading/DailyTradeTarget.mqh                                     |
//| Counts qualified CLOSED trades; never bypasses strategy gates.  |
//+------------------------------------------------------------------+
#ifndef DAILYTRADETARGET_MQH
#define DAILYTRADETARGET_MQH

class CDailyTradeTarget
  {
private:
   int      m_target;
   int      m_count;          // qualified, fully closed winners at/above the R threshold
   int      m_entryCount;     // distinct broker entry orders that actually received a fill
   int      m_dateKey;
   datetime m_lastSearchLogAt;
   bool     m_weekday;
   bool     m_reported;
   double   m_minQualifiedR;
   string   m_storageKey;
   string   m_lockKey;
   double   m_lockValue;
   double   m_legacyLockSeenAt;
   bool     m_reconcilePending;

   int DateKey(datetime at)
     {
      MqlDateTime t;
      if(at<=0 || !TimeToStruct(at,t))return 0;
      return t.year*1000+t.day_of_year;
     }

   bool IsWeekday(datetime at)
     {
      MqlDateTime t;
      if(at<=0 || !TimeToStruct(at,t))return false;
      return t.day_of_week>=1 && t.day_of_week<=5;
     }

   string PositionMarker(ulong positionId)
     {
      // Full ID is encoded in the name; it is never rounded through a double.
      return m_storageKey+".X."+StringFormat("%I64u",positionId);
     }

   string CountKey(int dateKey)
     {
      return m_storageKey+".C."+IntegerToString(dateKey);
     }

   string EntryCountKey(int dateKey)
     {
      return m_storageKey+".N."+IntegerToString(dateKey);
     }

   string EntryMarker(ulong orderId)
     {
      // One marker per broker order: partial fills of the same order remain one entry.
      return m_storageKey+".I."+StringFormat("%I64u",orderId);
     }

   string BaselineKey(int dateKey)
     {
      return m_storageKey+".B."+IntegerToString(dateKey);
     }

   bool AcquireLock()
     {
      if(StringLen(m_lockKey)<=0)return false;
      bool created=GlobalVariableTemp(m_lockKey);
      // GlobalVariableTemp returns false when another EA already created the lock.
      if(!created && !GlobalVariableCheck(m_lockKey))return false;
      for(int attempt=0;attempt<250;attempt++)
        {
         double token=(double)GetTickCount64()+1.0;
         if(GlobalVariableSetOnCondition(m_lockKey,token,0.0))
           {
            m_lockValue=token;
            m_legacyLockSeenAt=0.0;
            return true;
           }
         double held=GlobalVariableGet(m_lockKey);
         double now=(double)GetTickCount64();
         // Recover a lease left behind by an interrupted EA event. CAS ensures
         // an old owner cannot release a lock already acquired by another owner.
         bool stale=false;
         if(held==1.0)
           {
            // Older builds used the constant 1.0 lock token, which has no age.
            // Observe it for 30 seconds before recovery to avoid stealing an active old lock.
            if(m_legacyLockSeenAt<=0.0)m_legacyLockSeenAt=now;
            else if(now-m_legacyLockSeenAt>30000.0)stale=true;
           }
         else if(held>0.0 && now-held>30000.0)
            stale=true;
         if(stale && GlobalVariableSetOnCondition(m_lockKey,0.0,held))
           {
            m_legacyLockSeenAt=0.0;
            continue;
           }
         Sleep(1);
        }
      Print("Midas Touch daily target: timed out acquiring shared counter lock.");
      return false;
     }

   void ReleaseLock()
     {
      if(StringLen(m_lockKey)>0 && m_lockValue>0.0)
         GlobalVariableSetOnCondition(m_lockKey,0.0,m_lockValue);
      m_lockValue=0.0;
     }

   // Migrate the previous single-day counter once, then keep a stable baseline.
   bool EnsureBaselineLocked(int dateKey)
     {
      string baselineKey=BaselineKey(dateKey);
      if(GlobalVariableCheck(baselineKey))return true;

      double baseline=0.0;
      string legacyDateKey=m_storageKey+".D";
      string legacyCountKey=m_storageKey+".C";
      if(GlobalVariableCheck(legacyDateKey) &&
         (int)GlobalVariableGet(legacyDateKey)==dateKey &&
         GlobalVariableCheck(legacyCountKey))
         baseline=MathMax(0.0,GlobalVariableGet(legacyCountKey));

      return GlobalVariableSet(baselineKey,baseline)>0;
     }

   void MigrateLegacyLastPositionLocked()
     {
      // The previous version persisted only the last position ID as a double.
      // Preserve that one deduplication record during upgrade when it is exact.
      string legacyKey=m_storageKey+".P";
      if(!GlobalVariableCheck(legacyKey))return;
      double raw=GlobalVariableGet(legacyKey);
      if(raw<=0.0 || raw>=9007199254740992.0)return; // Beyond exact IEEE-754 integer range.
      ulong positionId=(ulong)raw;
      string marker=PositionMarker(positionId);
      if(!GlobalVariableCheck(marker))GlobalVariableSet(marker,1.0);
      GlobalVariableDel(legacyKey); // prevent recreating the migrated marker on later restarts
     }

   int CountMarkersForDateLocked(int dateKey)
     {
      int count=0;
      string prefix=m_storageKey+".X.";
      int total=GlobalVariablesTotal();
      for(int i=0;i<total;i++)
        {
         string name=GlobalVariableName(i);
         if(StringFind(name,prefix)!=0)continue;
         double storedAt=GlobalVariableGet(name);
         // The previous implementation stored 1.0 as a claim flag. New entries
         // store their broker close timestamp, allowing crash recovery by date.
         if(storedAt<1000000000.0)continue;
         if(DateKey((datetime)storedAt)==dateKey)count++;
        }
      return count;
     }

   int CountEntryMarkersForDateLocked(int dateKey)
     {
      int count=0;
      string prefix=m_storageKey+".I.";
      int total=GlobalVariablesTotal();
      for(int i=0;i<total;i++)
        {
         string name=GlobalVariableName(i);
         if(StringFind(name,prefix)!=0)continue;
         double storedAt=GlobalVariableGet(name);
         if(storedAt<1000000000.0)continue;
         if(DateKey((datetime)storedAt)==dateKey)count++;
        }
      return count;
     }

   void PruneOldMarkersLocked(datetime now)
     {
      // Keep a 90-day deduplication window without growing terminal globals forever.
      double cutoff=(double)(now-90*86400);
      string prefix=m_storageKey+".X.";
      for(int i=GlobalVariablesTotal()-1;i>=0;i--)
        {
         string name=GlobalVariableName(i);
         bool qualifiedMarker=(StringFind(name,prefix)==0);
         string entryPrefix=m_storageKey+".I.";
         bool entryMarker=(StringFind(name,entryPrefix)==0);
         if(!qualifiedMarker && !entryMarker)continue;
         double storedAt=GlobalVariableGet(name);
         // Previous versions stored 1.0 as a marker flag without a timestamp.
         // Retire those legacy flags after rollover, as well as expired timestamp markers.
         if(storedAt<1000000000.0 || storedAt<cutoff)
            GlobalVariableDel(name);
        }
     }

   bool ReconcileDate(int dateKey,bool pruneOldMarkers)
     {
      if(dateKey<=0 || !AcquireLock())return false;
      bool baselineReady=EnsureBaselineLocked(dateKey);
      if(baselineReady)MigrateLegacyLastPositionLocked();
      if(!baselineReady)
        {
         ReleaseLock();
         Print("Midas Touch daily target: could not initialize persistent baseline.");
         return false;
        }

      double baseline=GlobalVariableGet(BaselineKey(dateKey));
      int markerCount=CountMarkersForDateLocked(dateKey);
      int currentCount=(int)MathMax(0.0,baseline)+(int)MathMax(0,markerCount);
      bool winnersSaved=(GlobalVariableSet(CountKey(dateKey),(double)currentCount)>0);
      int entryCount=CountEntryMarkersForDateLocked(dateKey);
      bool entriesSaved=(GlobalVariableSet(EntryCountKey(dateKey),(double)entryCount)>0);
      if(pruneOldMarkers)PruneOldMarkersLocked(TimeCurrent());
      if(winnersSaved && entriesSaved)GlobalVariablesFlush();
      ReleaseLock();

      if(!winnersSaved || !entriesSaved)
         Print("Midas Touch daily target: could not reconcile both entry and qualified-winner counts.");
      return (winnersSaved && entriesSaved);
     }

   void SyncStoredState()
     {
      string key=CountKey(m_dateKey);
      if(m_reconcilePending || !GlobalVariableCheck(key))
        {
         if(ReconcileDate(m_dateKey,false))m_reconcilePending=false;
         else m_reconcilePending=true;
        }
      if(GlobalVariableCheck(key))
         m_count=MathMax(0,(int)GlobalVariableGet(key));
      string entryKey=EntryCountKey(m_dateKey);
      if(GlobalVariableCheck(entryKey))
         m_entryCount=MathMax(0,(int)GlobalVariableGet(entryKey));
      if(m_target>0 && m_weekday && m_count>=m_target)m_reported=true;
     }

   void Rollover()
     {
      datetime now=TimeCurrent();
      MqlDateTime t;
      if(now<=0 || !TimeToStruct(now,t))return;
      int nextKey=t.year*1000+t.day_of_year;
      if(nextKey==m_dateKey)
        {
         SyncStoredState();
         return;
        }

      if(m_target>0 && m_weekday && m_count<m_target && m_dateKey>0)
         PrintFormat("Midas Touch daily qualified-trade target not met: prior weekday %d/%d. No trades were forced.",m_count,m_target);

      m_dateKey=nextKey;
      m_weekday=(t.day_of_week>=1 && t.day_of_week<=5);
      m_count=0;
      m_entryCount=0;
      m_lastSearchLogAt=0;
      m_reported=false;
      ReconcileDate(m_dateKey,true);
      SyncStoredState();
     }

public:
   CDailyTradeTarget():m_target(3),m_count(0),m_entryCount(0),m_dateKey(0),
      m_lastSearchLogAt(0),m_weekday(false),m_reported(false),m_minQualifiedR(0.25),
      m_storageKey(""),m_lockKey(""),m_lockValue(0.0),m_legacyLockSeenAt(0.0),
      m_reconcilePending(false){}

   void Init(int target,double minQualifiedR,ulong magic)
     {
      m_target=MathMax(0,target);
      m_minQualifiedR=MathMax(0.0,minQualifiedR);
      // Keep the prior namespace for transparent migration of its current-day count.
      m_storageKey=StringFormat("MT2DT.%I64d.%I64u",AccountInfoInteger(ACCOUNT_LOGIN),magic);
      m_lockKey=m_storageKey+".L";
      m_count=0;
      m_entryCount=0;
      m_dateKey=0;
      m_lastSearchLogAt=0;
      m_weekday=false;
      m_reported=false;
      m_lockValue=0.0;
      m_legacyLockSeenAt=0.0;
      m_reconcilePending=false;

      datetime now=TimeCurrent();
      MqlDateTime t;
      if(now<=0 || !TimeToStruct(now,t))return;
      m_dateKey=t.year*1000+t.day_of_year;
      m_weekday=(t.day_of_week>=1 && t.day_of_week<=5);

      if(!ReconcileDate(m_dateKey,false))
        {
         // Best effort read preserves visibility if another terminal-global operation
         // temporarily prevents reconciliation; next tick retries if the key is absent.
         string countKey=CountKey(m_dateKey);
         if(GlobalVariableCheck(countKey))m_count=MathMax(0,(int)GlobalVariableGet(countKey));
         return;
        }
      SyncStoredState();
      if(m_target>0 && m_weekday && m_count>=m_target)
         PrintFormat("Midas Touch daily qualified-trade target restored: %d/%d.",m_count,m_target);
     }

   // Count a distinct broker order only after it has at least one actual entry fill.
   // A unique order marker makes repeated/partial-fill deal callbacks idempotent.
   void OnEntry(datetime at,ulong orderId)
     {
      if(at<=0 || orderId==0 || !IsWeekday(at))return;
      int entryDateKey=DateKey(at);
      if(entryDateKey<=0 || !AcquireLock())return;

      string marker=EntryMarker(orderId);
      if(GlobalVariableCheck(marker))
        {
         ReleaseLock();
         return;
        }

      if(GlobalVariableSet(marker,(double)at)<=0)
        {
         ReleaseLock();
         Print("Midas Touch daily target: failed to persist executed-entry marker.");
         return;
        }
      GlobalVariablesFlush();

      int entries=CountEntryMarkersForDateLocked(entryDateKey);
      bool saved=(GlobalVariableSet(EntryCountKey(entryDateKey),(double)entries)>0);
      if(saved)GlobalVariablesFlush();
      ReleaseLock();

      if(!saved)
        {
         m_reconcilePending=true;
         Print("Midas Touch daily target: entry marker saved but entry count needs reconciliation.");
         return;
        }

      if(entryDateKey==m_dateKey)
         m_entryCount=entries;
     }

   // A count is added only after a complete tracked decision closes profitably
   // and meets the configured realized-R threshold. Deal time defines the day.
   void OnQualifiedClose(datetime at,double realizedR,ulong positionId)
     {
      if(m_target<=0 || at<=0 || positionId==0 || realizedR<=0.0 ||
         realizedR+1e-9<m_minQualifiedR || !IsWeekday(at))return;

      int closeDateKey=DateKey(at);
      if(closeDateKey<=0 || !AcquireLock())return;

      string marker=PositionMarker(positionId);
      if(GlobalVariableCheck(marker))
        {
         ReleaseLock();
         return; // Already accounted for, including a repeated event after restart.
        }

      // The marker is the durable idempotency record. Reconciliation can rebuild
      // the counter if the terminal stops between this write and the count update.
      if(GlobalVariableSet(marker,(double)at)<=0)
        {
         ReleaseLock();
         Print("Midas Touch daily target: failed to persist qualified-position marker.");
         return;
        }
      // Persist idempotency before the count write so startup reconciliation can recover
      // if the terminal stops immediately afterwards.
      GlobalVariablesFlush();

      if(!EnsureBaselineLocked(closeDateKey))
        {
         GlobalVariableDel(marker);
         ReleaseLock();
         Print("Midas Touch daily target: failed to initialize close-date baseline.");
         return;
        }

      double baseline=GlobalVariableGet(BaselineKey(closeDateKey));
      int markerCount=CountMarkersForDateLocked(closeDateKey);
      int reconciled=(int)MathMax(0.0,baseline)+(int)MathMax(0,markerCount);
      bool saved=(GlobalVariableSet(CountKey(closeDateKey),(double)reconciled)>0);
      if(saved)GlobalVariablesFlush();
      ReleaseLock();

      if(!saved)
        {
         m_reconcilePending=true;
         Print("Midas Touch daily target: marker was saved but daily count needs reconciliation.");
        }
      else
         m_reconcilePending=false;

      if(closeDateKey==m_dateKey)
        {
         m_count=reconciled;
         if(!m_reported && m_target>0 && m_weekday && m_count>=m_target)
           {
            m_reported=true;
            PrintFormat("Midas Touch daily qualified-trade target reached: %d/%d (minimum %.2fR per closed trade).",m_count,m_target,m_minQualifiedR);
           }
        }
     }

   // This is telemetry, not an entry gate: setup evaluation continues under the EA's
   // ordinary session, news, spread, stop, risk, and execution safeguards.
   void LogSearchProgress()
     {
      Rollover();
      if(!m_weekday || m_target<=0 || m_count>=m_target)return;
      datetime now=TimeCurrent();
      if(now<=0 || (m_lastSearchLogAt>0 && now-m_lastSearchLogAt<900))return;
      m_lastSearchLogAt=now;
      PrintFormat("Midas Touch daily objective outstanding: executed entries=%d, qualified closed winners=%d/%d (minimum %.2fR); continuing normal setup search, no entries forced.",
                  m_entryCount,m_count,m_target,m_minQualifiedR);
     }

   void OnTick(){Rollover();}
   int EntryCountToday(){Rollover();return m_entryCount;}
   int CountToday(){Rollover();return m_count;}
   int Target(){return m_target;}
   int Deficit(){Rollover();return MathMax(0,m_target-m_count);}
   bool ObjectiveOutstanding(){Rollover();return m_weekday && m_target>0 && m_count<m_target;}
   bool Met(){Rollover();return !m_weekday || m_target<=0 || m_count>=m_target;}
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Trading/DailyTradeTarget.mqh
// already inlined once under include guard: includes/Decision/DecisionFingerprint.mqh
// BEGIN INLINED MODULE: includes/Decision/DecisionEngine.mqh
//+------------------------------------------------------------------+
//|                                      Decision/DecisionEngine.mqh |
//|  The analysis -> action router: turns a validated TradeSetup into  |
//|  an explicit, ID'd, auditable TradeDecisionRecord.                |
//+------------------------------------------------------------------+
#ifndef DECISIONENGINE_MQH
#define DECISIONENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh
// BEGIN INLINED MODULE: includes/Portfolio/EnvironmentPolicy.mqh
//+------------------------------------------------------------------+
//| Portfolio/EnvironmentPolicy.mqh                                 |
//| Regime-adaptive protection for transition and shock conditions    |
//+------------------------------------------------------------------+
#ifndef ENVIRONMENTPOLICY_MQH
#define ENVIRONMENTPOLICY_MQH

// already inlined once under include guard: includes/Core/Config.mqh

enum ENUM_ENVIRONMENT_STATE
  {
   ENV_NORMAL,
   ENV_TRANSITION,
   ENV_SHOCK
  };

// The policy acts on setup diagnostics without changing raw setup
// confidence. This preserves the calibration population: raw confidence
// remains the model output; environment thresholds control live exposure.
class CEnvironmentPolicy
  {
private:
   double m_transitionExecute;
   double m_transitionSignal;
   double m_shockMinConfidence;

   bool IsHighVolNewsShock(const TradeSetup &setup) const
     {
      return setup.reasons.vol_regime == VOL_REGIME_HIGH &&
             setup.reasons.news_risk == NEWS_BLOCKED;
     }

public:
   CEnvironmentPolicy()
      : m_transitionExecute(80.0), m_transitionSignal(72.0),
        m_shockMinConfidence(92.0) {}

   void Configure(double transitionExecute, double transitionSignal,
                  double shockMinConfidence)
     {
      m_transitionExecute = MathMax(0.0, MathMin(100.0, transitionExecute));
      m_transitionSignal = MathMax(0.0, MathMin(100.0, transitionSignal));
      m_shockMinConfidence = MathMax(m_transitionExecute,
                                     MathMin(100.0, shockMinConfidence));
     }

   ENUM_ENVIRONMENT_STATE Classify(const TradeSetup &setup) const
     {
      if(IsHighVolNewsShock(setup)) return ENV_SHOCK;
      if(setup.reasons.regime == REGIME_TRANSITION ||
         setup.reasons.vol_regime == VOL_REGIME_HIGH ||
         setup.reasons.news_risk == NEWS_WARNING)
         return ENV_TRANSITION;
      return ENV_NORMAL;
     }

   double ExecuteThreshold(const TradeSetup &setup, double base) const
     {
      ENUM_ENVIRONMENT_STATE state = Classify(setup);
      if(state == ENV_SHOCK) return MathMax(base, m_shockMinConfidence);
      if(state == ENV_TRANSITION) return MathMax(base, m_transitionExecute);
      return base;
     }

   double SignalThreshold(const TradeSetup &setup, double base) const
     {
      ENUM_ENVIRONMENT_STATE state = Classify(setup);
      if(state == ENV_SHOCK) return MathMax(base, m_shockMinConfidence);
      if(state == ENV_TRANSITION) return MathMax(base, m_transitionSignal);
      return base;
     }

   // High volatility alone does not stop trading. A shock requires both
   // high ATR percentile and a blocked high-impact-news window. This keeps
   // genuinely strong expansion regimes tradeable while protecting the
   // known transition/news failure mode.
   bool BlockExecution(const TradeSetup &setup, string &reason) const
     {
      reason = "";
      if(Classify(setup) != ENV_SHOCK) return false;
      reason = "new exposure blocked: high-volatility transition coincides with a blocked high-impact news window";
      return true;
     }

   bool ReduceRisk(const TradeSetup &setup) const
     {
      return Classify(setup) == ENV_TRANSITION;
     }

   string StateName(const TradeSetup &setup) const
     {
      switch(Classify(setup))
        {
         case ENV_TRANSITION: return "TRANSITION";
         case ENV_SHOCK:      return "SHOCK";
         default:             return "NORMAL";
        }
     }
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Portfolio/EnvironmentPolicy.mqh
// already inlined once under include guard: includes/Decision/TradeDecision.mqh

class CDecisionEngine
  {
private:
   string            m_symbol;
   bool              m_enableExecution;
   bool              m_enableSignals;
   double            m_minConfidenceExecute;
   double            m_minConfidenceSignal;
   double            m_fullRiskConfidence;
   int               m_maxSpreadPoints;
   long              m_nextId;
   CEnvironmentPolicy m_environment;

   double            CurrentSpreadPoints() const;
   bool              ValidateSetupGeometry(const TradeSetup &setup) const;

public:
                     CDecisionEngine();
   void              Init(const string symbol, bool enableExecution, bool enableSignals,
                          double minConfidenceExecute, double minConfidenceSignal,
                          double fullRiskConfidence, int maxSpreadPoints);
   void              SeedNextId(long nextId);
   long              AllocateId() { return m_nextId++; } // unique monotonic ID for operator-initiated entries
   long              PeekNextId() const { return m_nextId; }
   TradeDecisionRecord Decide(const TradeSetup &setup);
  };
//+------------------------------------------------------------------+
CDecisionEngine::CDecisionEngine() : m_symbol(""), m_enableExecution(false), m_enableSignals(false),
                                     m_minConfidenceExecute(0.0), m_minConfidenceSignal(0.0),
                                     m_fullRiskConfidence(0.0), m_maxSpreadPoints(0), m_nextId(1) {}
//+------------------------------------------------------------------+
void CDecisionEngine::Init(const string symbol, bool enableExecution, bool enableSignals,
                           double minConfidenceExecute, double minConfidenceSignal,
                           double fullRiskConfidence, int maxSpreadPoints)
  {
   m_symbol = (symbol == "") ? _Symbol : symbol;
   m_enableExecution = enableExecution;
   m_enableSignals = enableSignals;
   m_minConfidenceExecute = minConfidenceExecute;
   m_minConfidenceSignal = minConfidenceSignal;
   m_fullRiskConfidence = fullRiskConfidence;
   m_maxSpreadPoints = MathMax(0, maxSpreadPoints);
  }
//+------------------------------------------------------------------+
void CDecisionEngine::SeedNextId(long nextId)
  {
   m_nextId=MathMax(1,nextId);
  }
//+------------------------------------------------------------------+
double CDecisionEngine::CurrentSpreadPoints() const
  {
   long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   if(spread > 0) return (double)spread;

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0) return 0.0;
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return 0.0;
   return (ask - bid) / point;
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::ValidateSetupGeometry(const TradeSetup &setup) const
  {
   if(!MathIsValidNumber(setup.entry_top) || !MathIsValidNumber(setup.entry_bottom) ||
      !MathIsValidNumber(setup.invalidation) || !MathIsValidNumber(setup.stop_loss) ||
      !MathIsValidNumber(setup.tp1) || !MathIsValidNumber(setup.tp2) ||
      !MathIsValidNumber(setup.final_tp) || !MathIsValidNumber(setup.confidence))
      return false;

   if(setup.entry_top <= 0.0 || setup.entry_bottom <= 0.0 || setup.invalidation <= 0.0 ||
      setup.stop_loss <= 0.0 || setup.tp1 <= 0.0 || setup.tp2 <= 0.0 || setup.final_tp <= 0.0)
      return false;

   if(setup.entry_top < setup.entry_bottom || setup.confidence < 0.0 || setup.confidence > 100.0)
      return false;

   // The thesis boundary is intentionally checked independently from the
   // broker stop. The protective stop must remain on the invalid side of
   // the thesis boundary, while targets must remain beyond the entry zone.
   if(setup.type == ORDER_TYPE_BUY)
      return setup.invalidation < setup.entry_bottom &&
             setup.stop_loss < setup.invalidation &&
             setup.tp1 > setup.entry_top && setup.tp2 > setup.tp1 && setup.final_tp > setup.tp2;

   if(setup.type == ORDER_TYPE_SELL)
      return setup.invalidation > setup.entry_top &&
             setup.stop_loss > setup.invalidation &&
             setup.tp1 < setup.entry_bottom && setup.tp2 < setup.tp1 && setup.final_tp < setup.tp2;

   return false;
  }
//+------------------------------------------------------------------+
TradeDecisionRecord CDecisionEngine::Decide(const TradeSetup &setup)
  {
   TradeDecisionRecord rec;
   ZeroMemory(rec);
   rec.symbol = m_symbol;
   rec.setup = setup;
   rec.confidence = setup.confidence;
   rec.decided_time = TimeCurrent();
   rec.action = POLICY_IGNORE;
   rec.valid = false;
   rec.spread_points = CurrentSpreadPoints();

   if(!setup.active)
     {
      rec.reason = "setup inactive";
      return rec;
     }

   if(!ValidateSetupGeometry(setup))
     {
      rec.reason = "setup rejected: invalid entry/invalidation/stop/target geometry";
      return rec;
     }

   if(!m_enableExecution && !m_enableSignals)
     {
      rec.reason = "execution and signals both disabled";
      return rec;
     }

   const double executeThreshold = m_environment.ExecuteThreshold(setup, m_minConfidenceExecute);
   const double signalThreshold  = m_environment.SignalThreshold(setup, m_minConfidenceSignal);
   bool canExecute = m_enableExecution && setup.confidence >= executeThreshold;
   bool canSignal  = m_enableSignals  && setup.confidence >= signalThreshold;

   string environmentReason;
   if(m_environment.BlockExecution(setup, environmentReason))
     {
      canExecute = false;
      rec.reason = environmentReason + "; ";
     }

   // Spread gate applies to EXECUTION only. A wide spread makes the fill
   // bad; it does not make the analysis wrong, so subscribers can still
   // receive the signal when the signal threshold is met.
   if(canExecute && m_maxSpreadPoints > 0 && rec.spread_points > (double)m_maxSpreadPoints)
     {
      canExecute = false;
      rec.reason += StringFormat("execution skipped: spread %.0f pts > max %d pts; ",
                                rec.spread_points, m_maxSpreadPoints);
     }

   if(canExecute && canSignal)      rec.action = POLICY_EXECUTE_AND_SIGNAL;
   else if(canExecute)              rec.action = POLICY_EXECUTE_ONLY;
   else if(canSignal)               rec.action = POLICY_SIGNAL_ONLY;

   if(rec.action == POLICY_IGNORE)
     {
      rec.reason += StringFormat("confidence %.1f below thresholds (execute %.1f / signal %.1f; environment %s)",
                                 setup.confidence, executeThreshold, signalThreshold,
                                 m_environment.StateName(setup));
      return rec;
     }

   // EnvironmentPolicy::ReduceRisk intentionally reuses the existing
   // CalculateLotSize(halveForReducedRisk) contract. That gives transition
   // and recovery decisions a deterministic 50% sizing reduction without
   // introducing a second, potentially divergent sizing path.
   rec.reduce_risk = (setup.confidence < m_fullRiskConfidence) || m_environment.ReduceRisk(setup);
   rec.valid = true;
   rec.decision_id = m_nextId++;
   rec.reason += StringFormat("%s at confidence %.1f (environment %s)%s", TradePolicyToString(rec.action),
                              setup.confidence, m_environment.StateName(setup),
                              rec.reduce_risk ? " (reduced risk)" : "");
   return rec;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Decision/DecisionEngine.mqh
// BEGIN INLINED MODULE: includes/Decision/DecisionStore.mqh
//+------------------------------------------------------------------+
//|                                       Decision/DecisionStore.mqh |
//+------------------------------------------------------------------+
#ifndef DECISIONSTORE_MQH
#define DECISIONSTORE_MQH
// already inlined once under include guard: includes/Core/Config.mqh
// already inlined once under include guard: includes/Decision/TradeDecision.mqh
#define DECISION_CSV_SEP ";"
class CDecisionStore
  {
private:
   string m_symbol,m_decisionsFile,m_executionsFile; TradeDecisionRecord m_decisions[]; ExecutionRecord m_executions[];
   string SanitizeSymbol(const string s); bool AppendLine(const string filename,const string line); int ReadLines(const string filename,string &lines[]);
   string SerializeDecision(const TradeDecisionRecord &rec); bool ParseDecision(const string line,TradeDecisionRecord &rec);
   string SerializeExecution(const ExecutionRecord &rec); bool ParseExecution(const string line,ExecutionRecord &rec); void LoadFromDisk();
public:
   CDecisionStore(); void Init(const string symbol); void Deinit(); bool Save(const TradeDecisionRecord &rec); bool SaveExecution(long decisionId,double volume,ulong ticket,int legIndex=0,double target=0.0);
   int LoadAll(TradeDecisionRecord &out[]); int LoadAllExecutions(ExecutionRecord &out[]); bool FindById(long decisionId,TradeDecisionRecord &out); int Count() const{return ArraySize(m_decisions);}
  };
CDecisionStore::CDecisionStore():m_symbol(""),m_decisionsFile(""),m_executionsFile(""){}
string CDecisionStore::SanitizeSymbol(const string s)
  {
   string out=""; for(int i=0;i<StringLen(s);i++){ushort c=StringGetCharacter(s,i);bool ok=(c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z')||c=='_';out+=ok?ShortToString(c):"_";}
   return out==""?"SYMBOL":out;
  }
void CDecisionStore::Init(const string symbol)
  {
   m_symbol=(symbol=="")?_Symbol:symbol; string tag=SanitizeSymbol(m_symbol);
   m_decisionsFile="MedisTouch_Decisions_"+tag+".csv"; m_executionsFile="MedisTouch_Executions_"+tag+".csv";
   ArrayFree(m_decisions); ArrayFree(m_executions); LoadFromDisk();
  }
void CDecisionStore::Deinit(){ArrayFree(m_decisions);ArrayFree(m_executions);}
bool CDecisionStore::AppendLine(const string filename,const string line)
  {
   ResetLastError(); int handle=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle==INVALID_HANDLE){PrintFormat("MedisTouch DecisionStore: cannot open %s for append (error %d).",filename,GetLastError());return false;}
   FileSeek(handle,0,SEEK_END); uint written=FileWriteString(handle,line+"\r\n"); FileFlush(handle); FileClose(handle);
   return written>0;
  }
int CDecisionStore::ReadLines(const string filename,string &lines[])
  {
   ArrayFree(lines); if(!FileIsExist(filename)) return 0; int handle=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle==INVALID_HANDLE)return 0; int count=0; while(!FileIsEnding(handle)){string line=FileReadString(handle);if(StringLen(line)==0)continue;ArrayResize(lines,count+1);lines[count++]=line;} FileClose(handle); return count;
  }
string CDecisionStore::SerializeDecision(const TradeDecisionRecord &rec)
  {
   // v2.19+ append-only contract: keep the historical fields readable while
   // making thesis invalidation and selected strategy durable across restart.
   string p[25]; p[0]=IntegerToString(rec.decision_id);p[1]=rec.symbol;p[2]=IntegerToString((int)rec.setup.type);p[3]=DoubleToString(rec.setup.entry_top,_Digits);
   p[4]=DoubleToString(rec.setup.entry_bottom,_Digits);p[5]=DoubleToString(rec.setup.invalidation,_Digits);p[6]=DoubleToString(rec.setup.stop_loss,_Digits);
   p[7]=DoubleToString(rec.setup.tp1,_Digits);p[8]=DoubleToString(rec.setup.tp2,_Digits);p[9]=DoubleToString(rec.setup.final_tp,_Digits);
   p[10]=DoubleToString(rec.setup.confidence,2);p[11]=IntegerToString((long)rec.decided_time);p[12]=IntegerToString((int)rec.action);
   p[13]=rec.reduce_risk?"1":"0";p[14]=IntegerToString((int)rec.setup.reasons.selected_strategy);p[15]=rec.decision_fingerprint;p[16]=rec.decision_schema_version;p[17]=rec.strategy_version;p[18]=rec.model_version;p[19]=rec.calibration_version;p[20]=rec.feature_schema_version;p[21]=rec.environment_schema_version;p[22]=rec.weight_version;p[23]=rec.environment_key;p[24]=IntegerToString((int)rec.timeframe);
   string line=p[0];for(int i=1;i<25;i++)line+=DECISION_CSV_SEP+p[i];return line;
  }
bool CDecisionStore::ParseDecision(const string line,TradeDecisionRecord &rec)
  {
   string f[];int n=StringSplit(line,StringGetCharacter(DECISION_CSV_SEP,0),f);if(n<11)return false;ZeroMemory(rec);
   rec.decision_id=(long)StringToInteger(f[0]);rec.symbol=f[1];rec.setup.type=(ENUM_ORDER_TYPE)(int)StringToInteger(f[2]);rec.setup.entry_top=StringToDouble(f[3]);rec.setup.entry_bottom=StringToDouble(f[4]);
   // New format has invalidation at column 5. Old rows used column 5 for
   // stop_loss; restore those rows conservatively by mirroring the old
   // semantics so historical decisions remain loadable rather than being
   // silently assigned a fabricated thesis boundary.
   if(n>=15)
     {
      rec.setup.invalidation=StringToDouble(f[5]);rec.setup.stop_loss=StringToDouble(f[6]);rec.setup.tp1=StringToDouble(f[7]);rec.setup.tp2=StringToDouble(f[8]);rec.setup.final_tp=StringToDouble(f[9]);
      rec.setup.confidence=StringToDouble(f[10]);rec.setup.creation_time=(datetime)StringToInteger(f[11]);rec.action=(ENUM_TRADE_POLICY)(int)StringToInteger(f[12]);rec.reduce_risk=(f[13]=="1");
      rec.setup.reasons.selected_strategy=(ENUM_SELECTED_STRATEGY)(int)StringToInteger(f[14]);
      if(n>=25){rec.decision_fingerprint=f[15];rec.decision_schema_version=f[16];rec.strategy_version=f[17];rec.model_version=f[18];rec.calibration_version=f[19];rec.feature_schema_version=f[20];rec.environment_schema_version=f[21];rec.weight_version=f[22];rec.environment_key=f[23];rec.timeframe=(ENUM_TIMEFRAMES)(int)StringToInteger(f[24]);}
     }
   else
     {
      rec.setup.stop_loss=StringToDouble(f[5]);rec.setup.tp1=StringToDouble(f[6]);rec.setup.tp2=StringToDouble(f[7]);rec.setup.final_tp=StringToDouble(f[8]);rec.setup.confidence=StringToDouble(f[9]);
      rec.setup.creation_time=(datetime)StringToInteger(f[10]);rec.action=(n>11)?(ENUM_TRADE_POLICY)(int)StringToInteger(f[11]):POLICY_EXECUTE_ONLY;rec.reduce_risk=(n>12&&f[12]=="1");
      // Legacy decisions predate the first-class thesis boundary. Keep them
      // restorable, but do not pretend the historical SL was a known thesis
      // invalidation: zero means "unavailable" and downstream lifecycle
      // code must not infer a new structural boundary from it.
      rec.setup.invalidation=0.0;
      rec.setup.reasons.selected_strategy=STRATEGY_NONE;
     }
   rec.setup.active=true;rec.confidence=rec.setup.confidence;rec.decided_time=rec.setup.creation_time;rec.valid=rec.decision_id>0;rec.reason="restored from "+m_decisionsFile;return rec.valid;
  }
string CDecisionStore::SerializeExecution(const ExecutionRecord &rec)
  {
   return IntegerToString(rec.decision_id)+DECISION_CSV_SEP+DoubleToString(rec.volume,2)+DECISION_CSV_SEP+
          IntegerToString((long)rec.ticket)+DECISION_CSV_SEP+IntegerToString((long)rec.submitted_time)+DECISION_CSV_SEP+
          IntegerToString(rec.leg_index)+DECISION_CSV_SEP+DoubleToString(rec.target,_Digits);
  }
bool CDecisionStore::ParseExecution(const string line,ExecutionRecord &rec)
  {
   string f[];int n=StringSplit(line,StringGetCharacter(DECISION_CSV_SEP,0),f);if(n<3)return false;ZeroMemory(rec);
   rec.decision_id=(long)StringToInteger(f[0]);rec.volume=StringToDouble(f[1]);rec.ticket=(ulong)StringToInteger(f[2]);
   rec.submitted_time=(n>3)?(datetime)StringToInteger(f[3]):0;rec.leg_index=(n>4)?(int)StringToInteger(f[4]):0;rec.target=(n>5)?StringToDouble(f[5]):0.0;
   return rec.decision_id>0&&rec.volume>0&&rec.ticket>0;
  }
void CDecisionStore::LoadFromDisk()
  {
   string lines[];int n=ReadLines(m_decisionsFile,lines);for(int i=0;i<n;i++){TradeDecisionRecord rec;if(!ParseDecision(lines[i],rec))continue;int idx=ArraySize(m_decisions);ArrayResize(m_decisions,idx+1);m_decisions[idx]=rec;}
   string elines[];int m=ReadLines(m_executionsFile,elines);for(int i=0;i<m;i++){ExecutionRecord rec;if(!ParseExecution(elines[i],rec))continue;int idx=ArraySize(m_executions);ArrayResize(m_executions,idx+1);m_executions[idx]=rec;}
  }
bool CDecisionStore::Save(const TradeDecisionRecord &rec)
  {
   if(!rec.valid)return false; for(int i=0;i<ArraySize(m_decisions);i++)if(m_decisions[i].decision_id==rec.decision_id)return true;
   if(!AppendLine(m_decisionsFile,SerializeDecision(rec)))return false;
   int idx=ArraySize(m_decisions);ArrayResize(m_decisions,idx+1);m_decisions[idx]=rec;return true;
  }
bool CDecisionStore::SaveExecution(long decisionId,double volume,ulong ticket,int legIndex,double target)
  {
   if(decisionId<=0||volume<=0||ticket==0||legIndex<0)return false;
   for(int i=0;i<ArraySize(m_executions);i++)if(m_executions[i].decision_id==decisionId&&m_executions[i].leg_index==legIndex)return true;
   ExecutionRecord rec;ZeroMemory(rec);rec.decision_id=decisionId;rec.volume=volume;rec.ticket=ticket;rec.submitted_time=TimeCurrent();rec.leg_index=legIndex;rec.target=target;
   if(!AppendLine(m_executionsFile,SerializeExecution(rec)))return false;
   int idx=ArraySize(m_executions);ArrayResize(m_executions,idx+1);m_executions[idx]=rec;return true;
  }
int CDecisionStore::LoadAll(TradeDecisionRecord &out[]){int n=ArraySize(m_decisions);ArrayResize(out,n);for(int i=0;i<n;i++)out[i]=m_decisions[i];return n;}
int CDecisionStore::LoadAllExecutions(ExecutionRecord &out[]){int n=ArraySize(m_executions);ArrayResize(out,n);for(int i=0;i<n;i++)out[i]=m_executions[i];return n;}
bool CDecisionStore::FindById(long decisionId,TradeDecisionRecord &out){for(int i=ArraySize(m_decisions)-1;i>=0;i--)if(m_decisions[i].decision_id==decisionId){out=m_decisions[i];return true;}return false;}

// EA-wide durable decision store instance. The EA references this object from
// OnInit/OnTick; keeping the instance here guarantees it is available wherever
// DecisionStore.mqh is included without altering trading logic.
CDecisionStore g_store;

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Decision/DecisionStore.mqh
// BEGIN INLINED MODULE: includes/Execution/BrokerAdapter.mqh
//+------------------------------------------------------------------+
//|                                       Execution/BrokerAdapter.mqh |
//+------------------------------------------------------------------+
#ifndef BROKERADAPTER_MQH
#define BROKERADAPTER_MQH

#include <Trade\Trade.mqh>
// BEGIN INLINED MODULE: includes/Execution/PriceGridNormalizer.mqh
//+------------------------------------------------------------------+
//| Execution/PriceGridNormalizer.mqh                                |
//| Tick-grid normalization for protective SL/TP prices.              |
//+------------------------------------------------------------------+
#ifndef PRICEGRIDNORMALIZER_MQH
#define PRICEGRIDNORMALIZER_MQH

// Normalize a price to the symbol's tradable tick grid.
// roundUp=true is used for SELL protective stops and BUY take-profits.
// roundUp=false is used for BUY protective stops and SELL take-profits.
// Directional rounding never moves a stop/target closer to the market
// solely because a broker requires a coarser tick size.
bool NormalizePriceToTickGrid(const double rawPrice,
                              const double tickSize,
                              const int digits,
                              const bool roundUp,
                              double &normalizedPrice)
  {
   normalizedPrice=0.0;
   if(!MathIsValidNumber(rawPrice) || rawPrice<=0.0 ||
      !MathIsValidNumber(tickSize) || tickSize<=0.0 ||
      digits<0 || digits>8)
      return false;

   double units=rawPrice/tickSize;
   if(!MathIsValidNumber(units)) return false;

   // Scale epsilon to floating-point precision without using a material
   // fraction of a tick. This avoids moving an already-grid-aligned price
   // by a tick because of binary floating-point representation.
   double tolerance=MathMax(1e-9,MathAbs(units)*1.7763568394002505e-15);
   double gridUnits=roundUp ? MathCeil(units-tolerance) : MathFloor(units+tolerance);
   double gridPrice=gridUnits*tickSize;
   if(!MathIsValidNumber(gridPrice) || gridPrice<=0.0) return false;

   normalizedPrice=NormalizeDouble(gridPrice,digits);
   if(!MathIsValidNumber(normalizedPrice) || normalizedPrice<=0.0)
     {
      normalizedPrice=0.0;
      return false;
     }

   // Digits rounding must not undo directional tick rounding.
   double directionalTolerance=tickSize*1e-8;
   if(roundUp && normalizedPrice<rawPrice-directionalTolerance)
     {
      gridUnits+=1.0;
      normalizedPrice=NormalizeDouble(gridUnits*tickSize,digits);
     }
   else if(!roundUp && normalizedPrice>rawPrice+directionalTolerance)
     {
      gridUnits-=1.0;
      normalizedPrice=NormalizeDouble(gridUnits*tickSize,digits);
     }

   if(!MathIsValidNumber(normalizedPrice) || normalizedPrice<=0.0)
     {
      normalizedPrice=0.0;
      return false;
     }
   if(roundUp && normalizedPrice<rawPrice-directionalTolerance) return false;
   if(!roundUp && normalizedPrice>rawPrice+directionalTolerance) return false;
   return true;
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/PriceGridNormalizer.mqh

class CBrokerAdapter
  {
private:
   CTrade            m_trade;
   ulong             m_magic;
   int               m_maxRetries;
   int               m_retryDelayMs;
   ulong             m_lastLatencyUs;
   ulong             m_lastBrokerOrderId;
   ulong             m_lastBrokerDealId;
   ulong             m_lastBrokerPositionId;
   bool              m_lastRequestAttempted;
   uint              m_lastRetcode;

   void              CaptureBrokerIdentifiers(string symbol);
   bool              LastRequestOk(string action);
   bool              LastExecutionCompleted(string action,bool allowPartial=false,bool allowNoChanges=false);
   ulong             ResolvePositionTicket(string symbol);
   bool              IsRetryable(uint retcode);
   int               DelayForRetcode(uint retcode);
   bool              IsConnected();
   bool              ConfigureFillingForSymbol(string symbol);
   bool              IsMarketOpenForTrading(string symbol, bool requireFullOpen, bool isBuy=true);
   bool              ValidateStopDistance(string symbol, double refPrice, double sl, double tp, bool isBuy, string action);

public:
   void              Init(ulong magic, int maxRetries = 3, int retryDelayMs = 300);
   double            LastLatencyMs() { return (double)m_lastLatencyUs / 1000.0; }
   ulong             LastBrokerOrderId() const { return m_lastBrokerOrderId; }
   ulong             LastBrokerDealId() const { return m_lastBrokerDealId; }
   ulong             LastBrokerPositionId() const { return m_lastBrokerPositionId; }
   bool              LastRequestAttempted() const { return m_lastRequestAttempted; }
   uint              LastRetcode() const { return m_lastRetcode; }
   bool              LastRequestAmbiguous() const
     {
      return m_lastRequestAttempted &&
             (m_lastRetcode==TRADE_RETCODE_TIMEOUT ||
              m_lastRetcode==TRADE_RETCODE_CONNECTION ||
              m_lastRetcode==TRADE_RETCODE_ERROR);
     }
   void              ResetLastRequestStatus()
     {
      m_lastRequestAttempted=false;
      m_lastRetcode=0;
      m_lastBrokerOrderId=0;
      m_lastBrokerDealId=0;
      m_lastBrokerPositionId=0;
     }
   bool              MarketBuy(string symbol, double volume, double sl, double tp, ulong &ticketOut, double &fillPriceOut, string comment = "");
   bool              MarketSell(string symbol, double volume, double sl, double tp, ulong &ticketOut, double &fillPriceOut, string comment = "");
   bool              PlaceLimit(string symbol, ENUM_ORDER_TYPE type, double volume, double price,
                                double sl, double tp, ulong &ticketOut, string comment = "");
   bool              CancelOrder(ulong ticket);
   bool              ModifySLTP(ulong ticket, double sl, double tp);
   bool              ClosePartial(ulong ticket, double volume);
   bool              CloseFull(ulong ticket);
   ulong             PositionTicketForIdentifier(string symbol, ulong positionIdentifier);
  };
//+------------------------------------------------------------------+
void CBrokerAdapter::Init(ulong magic, int maxRetries, int retryDelayMs)
  {
   m_magic = magic;
   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetDeviationInPoints(20);
   m_maxRetries = MathMax(1,maxRetries);
   m_retryDelayMs = MathMax(0,retryDelayMs);
   m_lastLatencyUs = 0;
   m_lastBrokerOrderId = 0;
   m_lastBrokerDealId = 0;
   m_lastBrokerPositionId = 0;
   m_lastRequestAttempted = false;
   m_lastRetcode = 0;
  }
//+------------------------------------------------------------------+
void CBrokerAdapter::CaptureBrokerIdentifiers(string symbol)
  {
   m_lastBrokerOrderId=(ulong)m_trade.ResultOrder();
   m_lastBrokerDealId=(ulong)m_trade.ResultDeal();
   m_lastBrokerPositionId=0;
   if(m_lastBrokerDealId>0 && HistoryDealSelect(m_lastBrokerDealId))
      m_lastBrokerPositionId=(ulong)HistoryDealGetInteger(m_lastBrokerDealId,DEAL_POSITION_ID);
   // For accepted pending orders the order ID is the durable broker reference;
   // for market fills the position ID comes from the actual deal history.
   if(m_lastBrokerPositionId==0 && m_lastBrokerDealId>0)
      PrintFormat("MidasTouch BrokerAdapter: deal #%I64u accepted but stable position identity is not yet observable for %s; reconciliation remains required.",
                  m_lastBrokerDealId,symbol);
  }
//+------------------------------------------------------------------+
// Retry only broker outcomes that are explicitly transient. Unknown,
// ambiguous, or permanent outcomes fail closed to prevent duplicate exposure.
bool CBrokerAdapter::IsRetryable(uint retcode)
  {
   // Retry only explicit price responses that guarantee the trade was not
   // executed. TIMEOUT, CONNECTION and generic ERROR remain ambiguous.
   switch(retcode)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
         return true;
      default:
         return false;
     }
  }
//+------------------------------------------------------------------+
int CBrokerAdapter::DelayForRetcode(uint retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
         return MathMin(m_retryDelayMs,50);
      default:
         return m_retryDelayMs;
     }
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::IsConnected()
  {
   if(TerminalInfoInteger(TERMINAL_CONNECTED)) return true;
   Print("MedisTouch BrokerAdapter: terminal not connected to the trade server — refusing to submit.");
   return false;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::ConfigureFillingForSymbol(string symbol)
  {
   if(StringLen(symbol)==0)
     {
      Print("MedisTouch BrokerAdapter: empty symbol — refusing order submission.");
      return false;
     }
   ResetLastError();
   if(!m_trade.SetTypeFillingBySymbol(symbol))
     {
      PrintFormat("MedisTouch BrokerAdapter: %s refused — could not select a supported order-filling mode (error=%d).",
                  symbol,GetLastError());
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// requireFullOpen=true is used for new exposure. In addition to disabled
// and close-only, enforce the broker's directional-only modes. This avoids
// sending a known-doomed BUY to a SHORTONLY symbol (or vice versa).
bool CBrokerAdapter::IsMarketOpenForTrading(string symbol, bool requireFullOpen, bool isBuy)
  {
   long mode=(long)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED)
     {
      PrintFormat("MedisTouch BrokerAdapter: %s trading is disabled — refusing.",symbol);
      return false;
     }
   if(requireFullOpen && mode==SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      PrintFormat("MedisTouch BrokerAdapter: %s is close-only — refusing new exposure.",symbol);
      return false;
     }
   if(requireFullOpen && mode==SYMBOL_TRADE_MODE_LONGONLY && !isBuy)
     {
      PrintFormat("MedisTouch BrokerAdapter: %s is LONGONLY — refusing SELL.",symbol);
      return false;
     }
   if(requireFullOpen && mode==SYMBOL_TRADE_MODE_SHORTONLY && isBuy)
     {
      PrintFormat("MedisTouch BrokerAdapter: %s is SHORTONLY — refusing BUY.",symbol);
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::ValidateStopDistance(string symbol, double refPrice, double sl, double tp, bool isBuy, string action)
  {
   if(refPrice<=0.0)
     {
      PrintFormat("MedisTouch BrokerAdapter: %s refused — invalid reference price %.5f.",action,refPrice);
      return false;
     }
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0.0) return false;

   long stopsLevelPts=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevelPts=SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax(stopsLevelPts,freezeLevelPts)*point;

   if(sl>0.0)
     {
      bool wrongSide=isBuy ? (sl>=refPrice) : (sl<=refPrice);
      if(wrongSide)
        {
         PrintFormat("MedisTouch BrokerAdapter: %s refused — SL %.5f is on the wrong side of reference %.5f.",action,sl,refPrice);
         return false;
        }
      if(minDist>0.0 && MathAbs(refPrice-sl)<minDist)
        {
         PrintFormat("MedisTouch BrokerAdapter: %s refused — SL %.5f is too close to %.5f (requires >= %.1f points).",action,sl,refPrice,minDist/point);
         return false;
        }
     }
   if(tp>0.0)
     {
      bool wrongSide=isBuy ? (tp<=refPrice) : (tp>=refPrice);
      if(wrongSide)
        {
         PrintFormat("MedisTouch BrokerAdapter: %s refused — TP %.5f is on the wrong side of reference %.5f.",action,tp,refPrice);
         return false;
        }
      if(minDist>0.0 && MathAbs(refPrice-tp)<minDist)
        {
         PrintFormat("MedisTouch BrokerAdapter: %s refused — TP %.5f is too close to %.5f (requires >= %.1f points).",action,tp,refPrice,minDist/point);
         return false;
        }
     }
   return true;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::LastRequestOk(string action)
  {
   uint code=m_trade.ResultRetcode();
   if(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_DONE_PARTIAL) return true;
   PrintFormat("MedisTouch BrokerAdapter: %s failed, retcode=%d (%s)",action,code,m_trade.ResultRetcodeDescription());
   return false;
  }
//+------------------------------------------------------------------+
// Order/position helpers return true only when the trade server confirms
// the requested terminal state. CTrade's bool alone only checks request structure.
bool CBrokerAdapter::LastExecutionCompleted(string action,bool allowPartial,bool allowNoChanges)
  {
   uint code=m_trade.ResultRetcode();
   bool completed=(code==TRADE_RETCODE_DONE ||
                   (allowPartial && code==TRADE_RETCODE_DONE_PARTIAL) ||
                   (allowNoChanges && code==TRADE_RETCODE_NO_CHANGES));
   if(!completed)
      PrintFormat("MedisTouch BrokerAdapter: %s not confirmed, retcode=%d (%s)",
                  action,code,m_trade.ResultRetcodeDescription());
   return completed;
  }
//+------------------------------------------------------------------+
// Resolve the terminal's current position ticket from the stable history identifier.
// POSITION_IDENTIFIER is a ledger identity, not the argument to PositionSelectByTicket.
ulong CBrokerAdapter::PositionTicketForIdentifier(string symbol,ulong positionIdentifier)
  {
   if(positionIdentifier==0) return 0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==positionIdentifier)
         return ticket;
     }
   return 0;
  }
//+------------------------------------------------------------------+
ulong CBrokerAdapter::ResolvePositionTicket(string symbol)
  {
   ulong dealTicket=m_trade.ResultDeal();
   ulong positionIdentifier=0;
   if(dealTicket>0 && HistoryDealSelect(dealTicket))
      positionIdentifier=(ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);

   if(positionIdentifier>0)
     {
      ulong ticket=PositionTicketForIdentifier(symbol,positionIdentifier);
      if(ticket>0) return ticket;

      // A synchronous trade call can return before the terminal exposes the
      // resulting position snapshot. Keep the stable identifier temporarily:
      // the transaction handler and manager reconcile it to POSITION_TICKET.
      PrintFormat("MedisTouch BrokerAdapter: position identifier #%I64u has no current ticket snapshot yet; deferred reconciliation will retry.",positionIdentifier);
      return positionIdentifier;
     }

   ulong orderTicket=m_trade.ResultOrder();
   if(orderTicket>0)
     {
      if(PositionSelectByTicket(orderTicket) &&
         PositionGetString(POSITION_SYMBOL)==symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==m_magic)
         return orderTicket;
      PrintFormat("MedisTouch BrokerAdapter: accepted order #%I64u has no resolved deal/position identity yet; transaction recovery must reconcile it.",orderTicket);
      return orderTicket;
     }

   Print("MedisTouch BrokerAdapter: broker accepted a request without a resolvable deal, order, or position identifier.");
   return 0;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::MarketBuy(string symbol,double volume,double sl,double tp,ulong &ticketOut,double &fillPriceOut,string comment)
  {
   ticketOut=0; fillPriceOut=0.0;
   ResetLastRequestStatus();
   if(!IsConnected() || !IsMarketOpenForTrading(symbol,true,true)) { m_lastLatencyUs=0; return false; }
   if(!ConfigureFillingForSymbol(symbol)) { m_lastLatencyUs=0; return false; }
   double refPrice=SymbolInfoDouble(symbol,SYMBOL_ASK);
   if(!ValidateStopDistance(symbol,refPrice,sl,tp,true,"MarketBuy")) { m_lastLatencyUs=0; return false; }
   ulong t0=GetMicrosecondCount();
   for(int i=0;i<m_maxRetries;i++)
     {
      bool requestOk=m_trade.Buy(volume,symbol,0.0,sl,tp,comment);
      m_lastRequestAttempted=true;
      m_lastRetcode=m_trade.ResultRetcode();
      CaptureBrokerIdentifiers(symbol);
      if(requestOk && LastRequestOk("MarketBuy"))
        {
         ticketOut=ResolvePositionTicket(symbol);
         fillPriceOut=m_trade.ResultPrice();
         m_lastLatencyUs=GetMicrosecondCount()-t0;
         return ticketOut>0;
        }
      uint code=m_lastRetcode;
      if(!IsRetryable(code)) break;
      Sleep(DelayForRetcode(code));
     }
   m_lastLatencyUs=GetMicrosecondCount()-t0;
   return false;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::MarketSell(string symbol,double volume,double sl,double tp,ulong &ticketOut,double &fillPriceOut,string comment)
  {
   ticketOut=0; fillPriceOut=0.0;
   ResetLastRequestStatus();
   if(!IsConnected() || !IsMarketOpenForTrading(symbol,true,false)) { m_lastLatencyUs=0; return false; }
   if(!ConfigureFillingForSymbol(symbol)) { m_lastLatencyUs=0; return false; }
   double refPrice=SymbolInfoDouble(symbol,SYMBOL_BID);
   if(!ValidateStopDistance(symbol,refPrice,sl,tp,false,"MarketSell")) { m_lastLatencyUs=0; return false; }
   ulong t0=GetMicrosecondCount();
   for(int i=0;i<m_maxRetries;i++)
     {
      bool requestOk=m_trade.Sell(volume,symbol,0.0,sl,tp,comment);
      m_lastRequestAttempted=true;
      m_lastRetcode=m_trade.ResultRetcode();
      CaptureBrokerIdentifiers(symbol);
      if(requestOk && LastRequestOk("MarketSell"))
        {
         ticketOut=ResolvePositionTicket(symbol);
         fillPriceOut=m_trade.ResultPrice();
         m_lastLatencyUs=GetMicrosecondCount()-t0;
         return ticketOut>0;
        }
      uint code=m_lastRetcode;
      if(!IsRetryable(code)) break;
      Sleep(DelayForRetcode(code));
     }
   m_lastLatencyUs=GetMicrosecondCount()-t0;
   return false;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::PlaceLimit(string symbol,ENUM_ORDER_TYPE type,double volume,double price,double sl,double tp,ulong &ticketOut,string comment)
  {
   ticketOut=0;
   ResetLastRequestStatus();
   if(type!=ORDER_TYPE_BUY_LIMIT && type!=ORDER_TYPE_SELL_LIMIT) return false;
   bool isBuy=(type==ORDER_TYPE_BUY_LIMIT);
   if(!IsConnected() || !IsMarketOpenForTrading(symbol,true,isBuy)) { m_lastLatencyUs=0; return false; }
   if(!ConfigureFillingForSymbol(symbol)) { m_lastLatencyUs=0; return false; }
   if(!ValidateStopDistance(symbol,price,sl,tp,isBuy,"PlaceLimit")) { m_lastLatencyUs=0; return false; }
   ulong t0=GetMicrosecondCount();
   for(int i=0;i<m_maxRetries;i++)
     {
      bool ok=isBuy
               ? m_trade.BuyLimit(volume,price,symbol,sl,tp,ORDER_TIME_GTC,0,comment)
               : m_trade.SellLimit(volume,price,symbol,sl,tp,ORDER_TIME_GTC,0,comment);
      m_lastRequestAttempted=true;
      m_lastRetcode=m_trade.ResultRetcode();
      CaptureBrokerIdentifiers(symbol);
      if(ok && LastRequestOk("PlaceLimit"))
        {
         ticketOut=m_trade.ResultOrder();
         m_lastLatencyUs=GetMicrosecondCount()-t0;
         return ticketOut>0;
        }
      uint code=m_lastRetcode;
      if(!IsRetryable(code)) break;
      Sleep(DelayForRetcode(code));
     }
   m_lastLatencyUs=GetMicrosecondCount()-t0;
   return false;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::CancelOrder(ulong ticket)
  {
   if(!IsConnected() || ticket==0 || !OrderSelect(ticket)) return false;
   if((ulong)OrderGetInteger(ORDER_MAGIC)!=m_magic)
     {
      PrintFormat("MedisTouch BrokerAdapter: CancelOrder refused for foreign magic order #%I64u.",ticket);
      return false;
     }
   bool submitted=m_trade.OrderDelete(ticket);
   if(!submitted)
     {
      LastExecutionCompleted("CancelOrder",false,false);
      return false;
     }
   return LastExecutionCompleted("CancelOrder",false,false);
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::ModifySLTP(ulong ticket,double sl,double tp)
  {
   if(!IsConnected() || !PositionSelectByTicket(ticket)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic)
     {
      PrintFormat("MedisTouch BrokerAdapter: ModifySLTP refused for foreign magic position #%I64u.",ticket);
      return false;
     }

   string symbol=PositionGetString(POSITION_SYMBOL);
   bool isBuy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double refPrice=isBuy ? SymbolInfoDouble(symbol,SYMBOL_BID) : SymbolInfoDouble(symbol,SYMBOL_ASK);
   double currentSL=PositionGetDouble(POSITION_SL);
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(tickSize<=0.0) tickSize=point;
   if(tickSize<=0.0 || digits<0 || digits>8)
     {
      PrintFormat("MedisTouch BrokerAdapter: ModifySLTP refused — missing/invalid tick geometry for %s.",symbol);
      return false;
     }

   double adjustedSL=sl;
   double adjustedTP=tp;
   // Round protective prices away from the market, never toward it:
   // BUY SL down / BUY TP up; SELL SL up / SELL TP down.
   if(sl>0.0 && !NormalizePriceToTickGrid(sl,tickSize,digits,!isBuy,adjustedSL))
     {
      PrintFormat("MedisTouch BrokerAdapter: ModifySLTP refused — invalid SL tick normalization for %s.",symbol);
      return false;
     }
   if(tp>0.0 && !NormalizePriceToTickGrid(tp,tickSize,digits,isBuy,adjustedTP))
     {
      PrintFormat("MedisTouch BrokerAdapter: ModifySLTP refused — invalid TP tick normalization for %s.",symbol);
      return false;
     }

   if(sl>0.0 && currentSL>0.0 &&
      (isBuy ? adjustedSL<=currentSL : adjustedSL>=currentSL))
     {
      PrintFormat("MedisTouch BrokerAdapter: ModifySLTP refused — tick-normalized SL would not tighten existing stop for %s.",symbol);
      return false;
     }
   if(sl<=0.0 && currentSL>0.0)
     {
      PrintFormat("MedisTouch BrokerAdapter: ModifySLTP refused — will not remove a live protective stop for %s.",symbol);
      return false;
     }

   if(!ValidateStopDistance(symbol,refPrice,adjustedSL,adjustedTP,isBuy,"ModifySLTP")) return false;
   bool submitted=m_trade.PositionModify(ticket,adjustedSL,adjustedTP);
   if(!submitted)
     {
      LastExecutionCompleted("ModifySLTP",false,true);
      return false;
     }
   return LastExecutionCompleted("ModifySLTP",false,true);
  }

//+------------------------------------------------------------------+
bool CBrokerAdapter::ClosePartial(ulong ticket,double volume)
  {
   if(!IsConnected() || !PositionSelectByTicket(ticket)) return false;
   string symbol=PositionGetString(POSITION_SYMBOL);
   if(!ConfigureFillingForSymbol(symbol)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic)
     {
      PrintFormat("MedisTouch BrokerAdapter: ClosePartial refused for foreign magic position #%I64u.",ticket);
      return false;
     }
   if(!IsMarketOpenForTrading(symbol,false,true)) return false;

   double initialVolume=PositionGetDouble(POSITION_VOLUME);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(initialVolume<=0.0 || step<=0.0 || minVolume<=0.0 || volume<=0.0)
     {
      PrintFormat("MedisTouch BrokerAdapter: ClosePartial refused invalid volume (ticket=%I64u requested=%.8f current=%.8f).",ticket,volume,initialVolume);
      return false;
     }

   int volumeDigits=0;
   for(int d=0;d<=8;d++)
      if(MathAbs(step-NormalizeDouble(step,d))<1e-9) { volumeDigits=d; break; }
   double closeVolume=NormalizeDouble(MathFloor((volume+1e-10)/step)*step,volumeDigits);
   if(closeVolume<minVolume || closeVolume>=initialVolume-step*0.25)
     {
      PrintFormat("MedisTouch BrokerAdapter: ClosePartial refused non-partial volume (ticket=%I64u requested=%.8f normalized=%.8f current=%.8f).",ticket,volume,closeVolume,initialVolume);
      return false;
     }

   ENUM_ACCOUNT_MARGIN_MODE mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   bool submitted=false;
   if(mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      submitted=m_trade.PositionClosePartial(ticket,closeVolume);
   else
     {
      // CTrade::PositionClosePartial is documented for hedging accounts only.
      // On netting/exchange accounts, an opposite deal reduces the single net
      // position. The strict volume checks above prevent accidental reversal.
      bool isBuy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      submitted=isBuy
                ? m_trade.Sell(closeVolume,symbol,0.0,0.0,0.0,"MidasTouch partial reduction")
                : m_trade.Buy(closeVolume,symbol,0.0,0.0,0.0,"MidasTouch partial reduction");
     }
   if(!submitted)
     {
      LastExecutionCompleted("ClosePartial",true,false);
      return false;
     }
   if(!LastExecutionCompleted("ClosePartial",true,false)) return false;

   bool remains=PositionSelectByTicket(ticket);
   if(!remains && mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      remains=PositionSelect(symbol); // a netting position's ticket may be reissued after a deal
   if(!remains)
     {
      PrintFormat("MedisTouch BrokerAdapter: ClosePartial was accepted but position #%I64u no longer exists; verify state before treating it as a runner.",ticket);
      return false;
     }
   double remainingVolume=PositionGetDouble(POSITION_VOLUME);
   if(remainingVolume>=initialVolume-step*0.25 || remainingVolume<minVolume-step*0.25)
     {
      PrintFormat("MedisTouch BrokerAdapter: ClosePartial did not leave a valid reduced position (ticket=%I64u before=%.8f after=%.8f).",ticket,initialVolume,remainingVolume);
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
bool CBrokerAdapter::CloseFull(ulong ticket)
  {
   if(!IsConnected() || !PositionSelectByTicket(ticket)) return false;
   string symbol=PositionGetString(POSITION_SYMBOL);
   if(!ConfigureFillingForSymbol(symbol)) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic)
     {
      PrintFormat("MedisTouch BrokerAdapter: CloseFull refused for foreign magic position #%I64u.",ticket);
      return false;
     }
   if(!IsMarketOpenForTrading(symbol,false,true)) return false;
   bool submitted=m_trade.PositionClose(ticket);
   if(!submitted)
     {
      LastExecutionCompleted("CloseFull",true,false);
      return false;
     }
   if(!LastExecutionCompleted("CloseFull",true,false)) return false;
   if(PositionSelectByTicket(ticket))
     {
      double remainingVolume=PositionGetDouble(POSITION_VOLUME);
      if(remainingVolume>0.0)
        {
         PrintFormat("MedisTouch BrokerAdapter: CloseFull was accepted but position #%I64u still has %.8f lot(s); emergency stop must remain unverified.",ticket,remainingVolume);
         return false;
        }
     }
   return true;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/BrokerAdapter.mqh
// BEGIN INLINED MODULE: includes/Execution/OrderManager.mqh
//+------------------------------------------------------------------+
//|                                        Execution/OrderManager.mqh |
//+------------------------------------------------------------------+
#ifndef ORDERMANAGER_MQH
#define ORDERMANAGER_MQH

// already inlined once under include guard: includes/Decision/TradeDecision.mqh
// BEGIN INLINED MODULE: includes/Monitoring/ProductionMonitor.mqh
//+------------------------------------------------------------------+
//|                                 Monitoring/ProductionMonitor.mqh |
//+------------------------------------------------------------------+
#ifndef PRODUCTIONMONITOR_MQH
#define PRODUCTIONMONITOR_MQH

// Lightweight health surface for running unattended. This is NOT a
// dashboard — it has no UI of its own. It writes a heartbeat file an
// external watchdog (cron job, VPS monitor, whatever you already use)
// can tail to detect the EA going silent, and logs terminal warnings
// when the account itself starts showing signs of trouble. Deliberately
// simple: no alerting integrations (email/Telegram/etc.), since those
// each need their own credentials and are a natural layer ON TOP of
// this, not inside it — same anti-complexity rule as the rest of this
// codebase.
class CProductionMonitor
  {
private:
   string            m_heartbeatFile;
   string            m_symbol;
   datetime          m_startTime;
   datetime          m_lastHeartbeat;
   int               m_heartbeatIntervalSec;

   int               m_brokerRejectCount;
   int               m_illegalTransitionCount;
   double            m_peakEquity;
   double            m_maxDrawdownAlertPercent;
   bool              m_drawdownAlertFired;

   // LATENCY: running stats over every TS_DETECTED->TS_FILLED trade this
   // session. Running sum/count instead of storing every sample — this
   // runs unattended for weeks, an unbounded array of latency samples is
   // exactly the kind of thing that quietly bloats memory on a VPS.
   // "last" is what you want when something feels slow right now;
   // "avg"/"max" are what you want for a trend.
   int               m_latencySamples;
   double            m_latencyTotalSumMs;
   double            m_latencyTotalMaxMs;
   double            m_latencyLastTotalMs;
   double            m_latencyBrokerSumMs;
   double            m_latencyBrokerMaxMs;
   double            m_latencyLastBrokerMs;

public:
   void              Init(string symbol, int heartbeatIntervalSec, double maxDrawdownAlertPercent);
   void              OnTickCheck();             // call once per OnTick — cheap, cadence-gated internally
   void              NotifyBrokerReject();       // call when Submit()/BrokerAdapter reports a failed order
   void              NotifyIllegalTransition();  // hook for CTradeStateMachine's illegal-transition log — see note below
   // LATENCY: call once per fill from COrderManager::Submit(), right
   // after TS_FILLED. totalMs is TS_DETECTED->TS_FILLED (the number that
   // matters to you); brokerMs is CBrokerAdapter::LastLatencyMs() (the
   // slice of totalMs that was actually the broker round-trip, as
   // opposed to our own code between DETECTED and the order being sent).
   void              NotifyTradeLatency(double totalMs, double brokerMs);
   string            StatusSummary();
  };
//+------------------------------------------------------------------+
void CProductionMonitor::Init(string symbol, int heartbeatIntervalSec, double maxDrawdownAlertPercent)
  {
   m_symbol = symbol;
   m_heartbeatFile = "MedisTouch_Heartbeat_" + symbol + ".txt";
   m_startTime = TimeCurrent();
   m_lastHeartbeat = 0;
   m_heartbeatIntervalSec = heartbeatIntervalSec;
   m_brokerRejectCount = 0;
   m_illegalTransitionCount = 0;
   m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_maxDrawdownAlertPercent = maxDrawdownAlertPercent;
   m_drawdownAlertFired = false;
   m_latencySamples = 0;
   m_latencyTotalSumMs = 0.0;
   m_latencyTotalMaxMs = 0.0;
   m_latencyLastTotalMs = -1.0;
   m_latencyBrokerSumMs = 0.0;
   m_latencyBrokerMaxMs = 0.0;
   m_latencyLastBrokerMs = -1.0;
  }
//+------------------------------------------------------------------+
void CProductionMonitor::NotifyBrokerReject() { m_brokerRejectCount++; }
//+------------------------------------------------------------------+
void CProductionMonitor::NotifyTradeLatency(double totalMs, double brokerMs)
  {
   m_latencySamples++;
   m_latencyLastTotalMs = totalMs;
   m_latencyTotalSumMs += totalMs;
   if(totalMs > m_latencyTotalMaxMs) m_latencyTotalMaxMs = totalMs;

   m_latencyLastBrokerMs = brokerMs;
   m_latencyBrokerSumMs += brokerMs;
   if(brokerMs > m_latencyBrokerMaxMs) m_latencyBrokerMaxMs = brokerMs;

   // Flag it immediately rather than waiting for the next heartbeat tick
   // — a single outlier fill is worth knowing about the moment it
   // happens, not up to m_heartbeatIntervalSec later.
   if(m_latencySamples > 0)
     {
      double avgMs = m_latencyTotalSumMs / m_latencySamples;
      if(totalMs > avgMs * 3.0 && m_latencySamples > 5)
         PrintFormat("MedisTouch Monitor: latency outlier — this fill took %.0fms (broker: %.0fms) vs a %.0fms running average.",
                     totalMs, brokerMs, avgMs);
     }
  }
//+------------------------------------------------------------------+
// C004 FIX: previously dead — nothing called this. CTradeStateMachine now
// holds a CProductionMonitor* (bound via BindMonitor(), see
// Execution/TradeStateMachine.mqh) and calls this from Transition() itself
// whenever IsLegal() rejects a move, instead of only Print()-ing it where
// no external watchdog can see. COrderManager binds every ManagedTrade's
// fsm to this monitor right after construction, in both Submit() and
// RestoreTrade().
void CProductionMonitor::NotifyIllegalTransition() { m_illegalTransitionCount++; }
//+------------------------------------------------------------------+
void CProductionMonitor::OnTickCheck()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > m_peakEquity) m_peakEquity = equity;

   double drawdownPercent = (m_peakEquity > 0) ? (m_peakEquity - equity) / m_peakEquity * 100.0 : 0.0;
   if(drawdownPercent >= m_maxDrawdownAlertPercent && !m_drawdownAlertFired)
     {
      PrintFormat("MedisTouch Monitor: ALERT — drawdown from peak equity is %.2f%%, at or past the %.2f%% alert threshold.",
                  drawdownPercent, m_maxDrawdownAlertPercent);
      m_drawdownAlertFired = true;
     }
   else if(drawdownPercent < m_maxDrawdownAlertPercent * 0.5 && m_drawdownAlertFired)
      m_drawdownAlertFired = false; // recovered well clear of the threshold — allow the alert to fire again if it recurs

   datetime now = TimeCurrent();
   if(now - m_lastHeartbeat < m_heartbeatIntervalSec) return;
   m_lastHeartbeat = now;

   double avgTotalMs = (m_latencySamples > 0) ? m_latencyTotalSumMs / m_latencySamples : 0.0;
   double avgBrokerMs = (m_latencySamples > 0) ? m_latencyBrokerSumMs / m_latencySamples : 0.0;

   int handle = FileOpen(m_heartbeatFile, FILE_WRITE | FILE_TXT);
   if(handle == INVALID_HANDLE) return;
   FileWriteString(handle, StringFormat(
      "symbol=%s\nlast_heartbeat=%s\nuptime_sec=%d\nequity=%.2f\npeak_equity=%.2f\ndrawdown_pct=%.2f\n"
      "broker_rejects=%d\nillegal_transitions=%d\n"
      "latency_samples=%d\nlatency_last_total_ms=%.0f\nlatency_avg_total_ms=%.0f\nlatency_max_total_ms=%.0f\n"
      "latency_last_broker_ms=%.0f\nlatency_avg_broker_ms=%.0f\nlatency_max_broker_ms=%.0f\n",
      m_symbol, TimeToString(now, TIME_DATE | TIME_SECONDS), (int)(now - m_startTime),
      equity, m_peakEquity, drawdownPercent, m_brokerRejectCount, m_illegalTransitionCount,
      m_latencySamples, m_latencyLastTotalMs, avgTotalMs, m_latencyTotalMaxMs,
      m_latencyLastBrokerMs, avgBrokerMs, m_latencyBrokerMaxMs));
   FileClose(handle);
  }
//+------------------------------------------------------------------+
string CProductionMonitor::StatusSummary()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdownPercent = (m_peakEquity > 0) ? (m_peakEquity - equity) / m_peakEquity * 100.0 : 0.0;
   double avgTotalMs = (m_latencySamples > 0) ? m_latencyTotalSumMs / m_latencySamples : 0.0;
   return StringFormat("MedisTouch [%s] uptime=%ds equity=%.2f drawdown=%.2f%% rejects=%d illegalTransitions=%d avgFillLatencyMs=%.0f (n=%d)",
                       m_symbol, (int)(TimeCurrent() - m_startTime), equity, drawdownPercent,
                       m_brokerRejectCount, m_illegalTransitionCount, avgTotalMs, m_latencySamples);
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Monitoring/ProductionMonitor.mqh
// BEGIN INLINED MODULE: includes/Execution/TradeStateMachine.mqh
//+------------------------------------------------------------------+
//|                                  Execution/TradeStateMachine.mqh |
//+------------------------------------------------------------------+
#ifndef TRADESTATEMACHINE_MQH
#define TRADESTATEMACHINE_MQH

// already inlined once under include guard: includes/Monitoring/ProductionMonitor.mqh

enum ENUM_TRADE_STATE
  {
   TS_DETECTED,   // setup produced by analysis, not yet routed through the Decision Engine
   TS_VALIDATED,  // Policy Engine approved execution
   TS_WAITING,    // approved, waiting for price to reach the entry zone (pending-order path)
   TS_PENDING,    // order sent to the broker, not yet filled
   TS_FILLED,     // position open, still at original SL/TP
   TS_PROTECTED,  // stop moved to break-even
   TS_PARTIAL,    // partial close taken at TP1
   TS_RUNNER,     // remainder trailing toward final_tp
   TS_CLOSED,     // position fully closed (SL, TP, trail, or manual)
   TS_ARCHIVED,   // closed trade written to the journal, no longer polled
   TS_CANCELLED,  // pending order cancelled or setup invalidated before fill
   TS_REJECTED    // broker rejected the order
  };
//+------------------------------------------------------------------+
string TradeStateToString(ENUM_TRADE_STATE s)
  {
   switch(s)
     {
      case TS_DETECTED:  return "Detected";
      case TS_VALIDATED: return "Validated";
      case TS_WAITING:   return "Waiting";
      case TS_PENDING:   return "Pending";
      case TS_FILLED:    return "Filled";
      case TS_PROTECTED: return "Protected";
      case TS_PARTIAL:   return "Partial";
      case TS_RUNNER:    return "Runner";
      case TS_CLOSED:    return "Closed";
      case TS_ARCHIVED:  return "Archived";
      case TS_CANCELLED: return "Cancelled";
      case TS_REJECTED:  return "Rejected";
     }
   return "Unknown";
  }
//+------------------------------------------------------------------+
// One instance per live trade, from decision through archive. Every state
// change goes through Transition(), which enforces the legal-move table
// below instead of six different call sites setting a flag directly and
// silently drifting out of sync with each other.
class CTradeStateMachine
  {
private:
   ENUM_TRADE_STATE  m_state;
   long              m_decisionId;
   ulong             m_ticket;      // order/position ticket, once one exists
   datetime          m_lastChange;
   CProductionMonitor* m_monitor;   // C004 FIX: was permanently NULL — nothing ever bound one. See BindMonitor().

   // LATENCY: datetime (m_lastChange) is second-resolution — useless for
   // measuring anything inside a single tick. GetMicrosecondCount() gives
   // a monotonic microsecond counter (wraps at ~71 minutes on a 32-bit
   // wrap of the underlying uint, which MQL5 handles by returning a
   // ulong that keeps counting — safe to subtract across a live trade's
   // lifetime, which is always far shorter than that). Only the four
   // stage transitions on the confirmation->execution path are stamped;
   // everything past TS_FILLED (break-even, partials, trailing) isn't
   // part of "trade confirmation and execution" latency and stays on
   // m_lastChange only, same as before.
   ulong             m_usDetected;
   ulong             m_usValidated;
   ulong             m_usPending;
   ulong             m_usFilled;

   bool              IsLegal(ENUM_TRADE_STATE from, ENUM_TRADE_STATE to);
   void              StampStage(ENUM_TRADE_STATE to);

public:
                     CTradeStateMachine();
   void              Start(long decisionId);
   // C004 FIX: this used to be a dead hook — CProductionMonitor::NotifyIllegalTransition()
   // existed and worked, but no CTradeStateMachine instance ever held a reference to call
   // it with, since each one is default-constructed inside the ManagedTrade array (Submit()/
   // RestoreTrade() in OrderManager.mqh) with no monitor available at construction time.
   // BindMonitor() is the mechanical fix the audit called out: call it once right after
   // Start(), from every place a ManagedTrade is created, and illegal transitions start
   // actually incrementing the monitor's counter and showing up in the heartbeat file
   // instead of only ever reaching a Print() no external watchdog can see.
   void              BindMonitor(CProductionMonitor *monitor) { m_monitor = monitor; }
   bool              Transition(ENUM_TRADE_STATE to);
   void              ForceState(ENUM_TRADE_STATE to); // RECOVERY ONLY — bypasses IsLegal(). Recovery reconstructs
                                                        // state from broker-side evidence (position SL vs entry,
                                                        // current volume vs submitted volume), not from a live
                                                        // decision walking through its normal sequence — so there is
                                                        // no "from" state to validate a transition against. Anything
                                                        // other than Recovery calling this defeats the entire point
                                                        // of the legal-transition table above.
   ENUM_TRADE_STATE  State() const { return m_state; }
   long              DecisionId() const { return m_decisionId; }
   void              SetTicket(ulong ticket) { m_ticket = ticket; }
   ulong             Ticket() const { return m_ticket; }
   datetime          LastChange() const { return m_lastChange; }

   // LATENCY: millisecond breakdowns of the confirmation->execution path.
   // Returns -1.0 when the relevant stage(s) haven't happened yet (e.g.
   // querying ConfirmationLatencyMs() before TS_VALIDATED is reached, or
   // any of these on a signal-only decision that never reaches
   // TS_PENDING/TS_FILLED) instead of a misleading 0.0 or a huge
   // underflowed ulong from subtracting an unset (zero) timestamp.
   //   ConfirmationLatencyMs: TS_DETECTED -> TS_VALIDATED (policy engine's own decision time)
   //   SubmitLatencyMs:       TS_VALIDATED -> TS_PENDING  (our code, between approval and sending the order)
   //   ExecutionLatencyMs:    TS_PENDING -> TS_FILLED     (broker round-trip, includes any retries)
   //   TotalLatencyMs:        TS_DETECTED -> TS_FILLED    (the end-to-end number that actually matters)
   double            ConfirmationLatencyMs() const
     { return (m_usDetected > 0 && m_usValidated > 0) ? (double)(m_usValidated - m_usDetected) / 1000.0 : -1.0; }
   double            SubmitLatencyMs() const
     { return (m_usValidated > 0 && m_usPending > 0) ? (double)(m_usPending - m_usValidated) / 1000.0 : -1.0; }
   double            ExecutionLatencyMs() const
     { return (m_usPending > 0 && m_usFilled > 0) ? (double)(m_usFilled - m_usPending) / 1000.0 : -1.0; }
   double            TotalLatencyMs() const
     { return (m_usDetected > 0 && m_usFilled > 0) ? (double)(m_usFilled - m_usDetected) / 1000.0 : -1.0; }
  };
//+------------------------------------------------------------------+
CTradeStateMachine::CTradeStateMachine()
  {
   m_state = TS_DETECTED;
   m_decisionId = 0;
   m_ticket = 0;
   m_lastChange = 0;
   m_monitor = NULL;
   m_usDetected = 0;
   m_usValidated = 0;
   m_usPending = 0;
   m_usFilled = 0;
  }
//+------------------------------------------------------------------+
void CTradeStateMachine::Start(long decisionId)
  {
   m_decisionId = decisionId;
   m_state = TS_DETECTED;
   m_ticket = 0;
   m_lastChange = TimeCurrent();
   m_usDetected = GetMicrosecondCount();
   m_usValidated = 0;
   m_usPending = 0;
   m_usFilled = 0;
  }
//+------------------------------------------------------------------+
// Stamps only the four states latency actually tracks. Deliberately a
// separate step from the legality check in Transition() — ForceState()
// (recovery) calls this too, but recovery timestamps are meaningless
// (the trade didn't just pass through that state, it's being
// reconstructed from broker-side evidence possibly days later), so
// ForceState() does NOT call this — see its body below.
void CTradeStateMachine::StampStage(ENUM_TRADE_STATE to)
  {
   ulong now = GetMicrosecondCount();
   switch(to)
     {
      case TS_VALIDATED: m_usValidated = now; break;
      case TS_PENDING:    m_usPending = now;  break;
      case TS_FILLED:     m_usFilled = now;   break;
      default: break; // every other state is outside the latency path
     }
  }
//+------------------------------------------------------------------+
bool CTradeStateMachine::IsLegal(ENUM_TRADE_STATE from, ENUM_TRADE_STATE to)
  {
   switch(from)
     {
      case TS_DETECTED:  return (to == TS_VALIDATED || to == TS_CANCELLED);
      case TS_VALIDATED: return (to == TS_WAITING || to == TS_PENDING || to == TS_CANCELLED);
      case TS_WAITING:   return (to == TS_PENDING || to == TS_CANCELLED);
      case TS_PENDING:   return (to == TS_FILLED || to == TS_CANCELLED || to == TS_REJECTED);
      case TS_FILLED:    return (to == TS_PROTECTED || to == TS_PARTIAL || to == TS_CLOSED);
      case TS_PROTECTED: return (to == TS_PARTIAL || to == TS_CLOSED);
      case TS_PARTIAL:   return (to == TS_RUNNER || to == TS_CLOSED);
      case TS_RUNNER:    return (to == TS_CLOSED);
      case TS_CLOSED:    return (to == TS_ARCHIVED);
      default:           return false; // ARCHIVED / CANCELLED / REJECTED are terminal
     }
  }
//+------------------------------------------------------------------+
bool CTradeStateMachine::Transition(ENUM_TRADE_STATE to)
  {
   if(!IsLegal(m_state, to))
     {
      PrintFormat("MedisTouch StateMachine: illegal transition %s -> %s (decision #%d)",
                  TradeStateToString(m_state), TradeStateToString(to), m_decisionId);
      if(m_monitor != NULL) m_monitor.NotifyIllegalTransition();
      return false;
     }
   m_state = to;
   m_lastChange = TimeCurrent();
   StampStage(to);
   return true;
  }
//+------------------------------------------------------------------+
void CTradeStateMachine::ForceState(ENUM_TRADE_STATE to)
  {
   PrintFormat("MedisTouch StateMachine: recovery force-state %s -> %s (decision #%d) — bypassing legality check",
               TradeStateToString(m_state), TradeStateToString(to), m_decisionId);
   m_state = to;
   m_lastChange = TimeCurrent();
   // No StampStage() here on purpose — see the comment on StampStage().
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/TradeStateMachine.mqh
// already inlined once under include guard: includes/Execution/BrokerAdapter.mqh

struct ManagedTrade
  {
   TradeDecisionRecord  decision;
   CTradeStateMachine   fsm;
   double               volume;
   double               fillPrice;
   int                  legIndex;
   ulong                positionIdentifier;
  };

class COrderManager
  {
private:
   CBrokerAdapter*     m_broker;
   ManagedTrade        m_trades[];
   int                 m_maxOpen;
   CProductionMonitor* m_monitor;
   int                 FindByDecisionAndLeg(long id,int legIndex);
   int                 FindByTicket(ulong ticket);
   bool                IsBrokerVolumeValid(string symbol,double volume);

public:
   void              Init(CBrokerAdapter* broker,int maxOpenTrades,CProductionMonitor* monitor);
   bool              Submit(const TradeDecisionRecord &decision,double volume,bool useMarket,double maxEntryDeviation,ulong &ticketOut,int legIndex=0);
   bool              RestoreTrade(const TradeDecisionRecord &decision,double volume,ulong ticket,ENUM_TRADE_STATE state,double fillPrice=0.0,int legIndex=0);
   int               OpenCount();
   int               Total() { return ArraySize(m_trades); }
   void              Prune();
   bool              CancelPendingAt(int idx);
   bool              MarkFilledFromPending(ulong orderTicket,ulong positionTicket,double fillPrice=0.0);
   bool              BindPositionIdentity(ulong knownTicket,ulong positionIdentifier,ulong positionTicket);
   ulong             PositionTicketAt(int idx);
   long              DecisionIdForPositionIdentifier(ulong positionIdentifier);
   bool              MarkPositionExitByIdentifier(ulong positionIdentifier,bool positionStillOpen);
   long              DecisionIdForTicket(ulong ticket);
   double            FillPriceForDecision(long decisionId);
   ENUM_TRADE_STATE  StateAt(int idx) { return m_trades[idx].fsm.State(); }
   ulong             TicketAt(int idx) { return m_trades[idx].fsm.Ticket(); }
   TradeDecisionRecord DecisionAt(int idx) { return m_trades[idx].decision; }
   double            VolumeAt(int idx) { return m_trades[idx].volume; }
   bool              TransitionAt(int idx,ENUM_TRADE_STATE to) { return m_trades[idx].fsm.Transition(to); }
   bool              HasLiveTradeForDecision(long decisionId,ulong excludeTicket=0);
   int               LegIndexForTicket(ulong ticket);
   double            FillPriceAt(int idx)
     {
      if(m_trades[idx].fillPrice>0.0) return m_trades[idx].fillPrice;
      bool isBuy=(m_trades[idx].decision.setup.type==ORDER_TYPE_BUY);
      return isBuy ? m_trades[idx].decision.setup.entry_top : m_trades[idx].decision.setup.entry_bottom;
     }
  };
//+------------------------------------------------------------------+
void COrderManager::Init(CBrokerAdapter* broker,int maxOpenTrades,CProductionMonitor* monitor)
  {
   m_broker=broker;
   m_maxOpen=MathMax(1,maxOpenTrades);
   m_monitor=monitor;
   ArrayResize(m_trades,0);
  }
//+------------------------------------------------------------------+
int COrderManager::FindByDecisionAndLeg(long id,int legIndex)
  {
   for(int i=0;i<ArraySize(m_trades);i++)
      if(m_trades[i].decision.decision_id==id && m_trades[i].legIndex==legIndex) return i;
   return -1;
  }
int COrderManager::FindByTicket(ulong ticket)
  {
   if(ticket==0) return -1;
   for(int i=0;i<ArraySize(m_trades);i++)
      if(m_trades[i].fsm.Ticket()==ticket) return i;
   return -1;
  }
//+------------------------------------------------------------------+
int COrderManager::OpenCount()
  {
   int c=0;
   for(int i=0;i<ArraySize(m_trades);i++)
     {
      ENUM_TRADE_STATE s=m_trades[i].fsm.State();
      if(s==TS_PENDING || s==TS_FILLED || s==TS_PROTECTED || s==TS_PARTIAL || s==TS_RUNNER) c++;
     }
   return c;
  }
//+------------------------------------------------------------------+
bool COrderManager::CancelPendingAt(int idx)
  {
   if(idx<0 || idx>=ArraySize(m_trades)) return false;
   ENUM_TRADE_STATE state=m_trades[idx].fsm.State();
   if(state!=TS_PENDING && state!=TS_WAITING) return false;
   ulong ticket=m_trades[idx].fsm.Ticket();
   if(ticket==0 || !m_broker.CancelOrder(ticket)) return false;
   bool transitioned=m_trades[idx].fsm.Transition(TS_CANCELLED);
   if(transitioned) PrintFormat("MedisTouch OrderManager: pending order %I64u cancelled by chart control.",ticket);
   return transitioned;
  }
//+------------------------------------------------------------------+
void COrderManager::Prune()
  {
   ManagedTrade kept[];
   int n=0;
   ArrayResize(kept,ArraySize(m_trades));
   for(int i=0;i<ArraySize(m_trades);i++)
     {
      ENUM_TRADE_STATE s=m_trades[i].fsm.State();
      if(s==TS_ARCHIVED || s==TS_CANCELLED || s==TS_REJECTED) continue;
      kept[n++]=m_trades[i];
     }
   ArrayResize(kept,n);
   ArrayResize(m_trades,n);
   for(int i=0;i<n;i++) m_trades[i]=kept[i];
  }
//+------------------------------------------------------------------+
bool COrderManager::MarkFilledFromPending(ulong orderTicket,ulong positionTicket,double fillPrice)
  {
   for(int i=0;i<ArraySize(m_trades);i++)
     {
      if(m_trades[i].fsm.State()!=TS_PENDING || m_trades[i].fsm.Ticket()!=orderTicket) continue;
      m_trades[i].fsm.SetTicket(positionTicket);
      if(fillPrice>0.0) m_trades[i].fillPrice=fillPrice;
      bool filled=m_trades[i].fsm.Transition(TS_FILLED);
      if(filled && m_monitor!=NULL)
        {
         double totalMs=m_trades[i].fsm.TotalLatencyMs();
         if(totalMs>=0.0) m_monitor.NotifyTradeLatency(totalMs,0.0);
        }
      return filled;
     }
   return false;
  }
// Bind the stable broker history identity to the current selectable position ticket.
bool COrderManager::BindPositionIdentity(ulong knownTicket,ulong positionIdentifier,ulong positionTicket)
  {
   if(positionIdentifier==0 || positionTicket==0) return false;
   int idx=FindByTicket(knownTicket);
   if(idx<0) idx=FindByTicket(positionIdentifier);
   if(idx<0) idx=FindByTicket(positionTicket);
   if(idx<0) return false;
   if(m_trades[idx].positionIdentifier!=0 &&
      m_trades[idx].positionIdentifier!=positionIdentifier)
     {
      PrintFormat("MedisTouch OrderManager: refused conflicting position identity for decision #%I64d.",m_trades[idx].decision.decision_id);
      return false;
     }
   m_trades[idx].positionIdentifier=positionIdentifier;
   m_trades[idx].fsm.SetTicket(positionTicket);
   return true;
  }
//+------------------------------------------------------------------+
ulong COrderManager::PositionTicketAt(int idx)
  {
   if(idx<0 || idx>=ArraySize(m_trades)) return 0;
   // Until a stable deal/position identity is bound, do not guess that a
   // broker order ticket or history identifier is a selectable position.
   ulong identifier=m_trades[idx].positionIdentifier;
   if(identifier==0) return 0;

   ulong ticket=m_trades[idx].fsm.Ticket();
   if(ticket>0 && PositionSelectByTicket(ticket))
     {
      if(PositionGetString(POSITION_SYMBOL)==m_trades[idx].decision.symbol &&
         (ulong)PositionGetInteger(POSITION_IDENTIFIER)==identifier)
         return ticket;
     }

   // POSITION_TICKET may change over the lifetime of a live position. Resolve
   // the current ticket via the stable POSITION_IDENTIFIER and repair the FSM.
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong actualTicket=PositionGetTicket(i);
      if(actualTicket==0 || !PositionSelectByTicket(actualTicket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=m_trades[idx].decision.symbol) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=identifier) continue;
      m_trades[idx].fsm.SetTicket(actualTicket);
      return actualTicket;
     }
   return 0;
  }
//+------------------------------------------------------------------+
long COrderManager::DecisionIdForPositionIdentifier(ulong positionIdentifier)
  {
   if(positionIdentifier==0) return -1;
   for(int i=0;i<ArraySize(m_trades);i++)
      if(m_trades[i].positionIdentifier==positionIdentifier)
         return m_trades[i].decision.decision_id;
   return -1;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool COrderManager::MarkPositionExitByIdentifier(ulong positionIdentifier,bool positionStillOpen)
  {
   if(positionIdentifier==0) return false;
   for(int i=0;i<ArraySize(m_trades);i++)
     {
      if(m_trades[i].positionIdentifier!=positionIdentifier) continue;
      if(positionStillOpen) return true;

      ENUM_TRADE_STATE state=m_trades[i].fsm.State();
      if(state==TS_ARCHIVED) return true;
      if(state!=TS_CLOSED && !m_trades[i].fsm.Transition(TS_CLOSED))
        {
         PrintFormat("MedisTouch OrderManager: could not close decision #%I64d after broker position #%I64u disappeared.",
                     m_trades[i].decision.decision_id,positionIdentifier);
         return false;
        }
      if(m_trades[i].fsm.State()==TS_CLOSED)
         return m_trades[i].fsm.Transition(TS_ARCHIVED);
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
long COrderManager::DecisionIdForTicket(ulong ticket)
  {
   for(int i=0;i<ArraySize(m_trades);i++)
      if(m_trades[i].fsm.Ticket()==ticket) return m_trades[i].decision.decision_id;
   return -1;
  }
//+------------------------------------------------------------------+
double COrderManager::FillPriceForDecision(long decisionId)
  {
   for(int i=0;i<ArraySize(m_trades);i++)
      if(m_trades[i].decision.decision_id==decisionId)
         return FillPriceAt(i);
   return 0.0;
  }
bool COrderManager::HasLiveTradeForDecision(long decisionId,ulong excludeTicket)
  {
   for(int i=0;i<ArraySize(m_trades);i++)
     {
      if(m_trades[i].decision.decision_id!=decisionId) continue;
      if(excludeTicket!=0 && (m_trades[i].fsm.Ticket()==excludeTicket || m_trades[i].positionIdentifier==excludeTicket)) continue;
      ENUM_TRADE_STATE s=m_trades[i].fsm.State();
      if(s==TS_PENDING || s==TS_WAITING) return true;
      if(s==TS_FILLED || s==TS_PROTECTED || s==TS_PARTIAL || s==TS_RUNNER)
        {
         ulong ticket=PositionTicketAt(i);
         if(ticket!=0 && PositionSelectByTicket(ticket)) return true;
        }
     }
   return false;
  }
int COrderManager::LegIndexForTicket(ulong ticket)
  {
   int idx=FindByTicket(ticket);
   return idx<0 ? 0 : m_trades[idx].legIndex;
  }
//+------------------------------------------------------------------+
bool COrderManager::IsBrokerVolumeValid(string symbol,double volume)
  {
   if(symbol=="" || !MathIsValidNumber(volume) || volume<=0.0) return false;

   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double lotStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(!MathIsValidNumber(minLot) || !MathIsValidNumber(maxLot) ||
      !MathIsValidNumber(lotStep) || minLot<=0.0 || maxLot<minLot || lotStep<=0.0)
      return false;
   if(volume<minLot || volume>maxLot) return false;

   // Validate against the broker's minimum-anchored step grid. Reject rather
   // than silently round a caller's requested volume and change its risk.
   double steps=(volume-minLot)/lotStep;
   if(!MathIsValidNumber(steps) || steps<0.0) return false;
   double alignedVolume=minLot+MathRound(steps)*lotStep;
   double tolerance=MathMax(1e-8,lotStep*1e-6);
   if(MathAbs(volume-alignedVolume)>tolerance) return false;
   return true;
  }
//+------------------------------------------------------------------+
bool COrderManager::Submit(const TradeDecisionRecord &decision,double volume,bool useMarket,double maxEntryDeviation,ulong &ticketOut,int legIndex)
  {
   ticketOut=0;
   if(m_broker==NULL) return false;
   m_broker.ResetLastRequestStatus();
   if(decision.action!=POLICY_EXECUTE_ONLY && decision.action!=POLICY_EXECUTE_AND_SIGNAL) return false;
   if(decision.decision_id<=0 ||
      (decision.setup.type!=ORDER_TYPE_BUY && decision.setup.type!=ORDER_TYPE_SELL)) return false;
   if(!IsBrokerVolumeValid(decision.symbol,volume))
     {
      PrintFormat("MedisTouch OrderManager: reject decision #%I64d — volume %.8f violates broker min/max/step for %s.",
                  decision.decision_id,volume,decision.symbol);
      return false;
     }
   if(OpenCount()>=m_maxOpen) return false;
   if(legIndex<0) return false;
   if(FindByDecisionAndLeg(decision.decision_id,legIndex)>=0) return false;

   double entry=ResolveExecutionEntry(decision.setup);
   if(useMarket && maxEntryDeviation>0.0)
     {
      MqlTick tick;
      if(!SymbolInfoTick(decision.symbol,tick)) return false;
      double marketPrice=(decision.setup.type==ORDER_TYPE_BUY)?tick.ask:tick.bid;
      if(MathAbs(marketPrice-entry)>maxEntryDeviation) return false;
     }

   int idx=ArraySize(m_trades);
   ArrayResize(m_trades,idx+1);
   m_trades[idx].decision=decision;
   m_trades[idx].volume=volume;
   m_trades[idx].fillPrice=0.0;
   m_trades[idx].legIndex=legIndex;
   m_trades[idx].positionIdentifier=0;
   m_trades[idx].fsm.Start(decision.decision_id);
   m_trades[idx].fsm.BindMonitor(m_monitor);
   m_trades[idx].fsm.Transition(TS_VALIDATED);

   double sl=decision.setup.stop_loss;
   double tp=decision.setup.final_tp;
   ulong ticket=0;
   double fillPrice=0.0;
   bool ok=false;
   if(useMarket)
     {
      m_trades[idx].fsm.Transition(TS_PENDING);
      string comment="MT#"+IntegerToString(decision.decision_id)+(legIndex>0?":L"+IntegerToString(legIndex):"");
      if(decision.setup.type==ORDER_TYPE_BUY)
        {
         ok=m_broker.MarketBuy(decision.symbol,volume,sl,tp,ticket,fillPrice,comment);
        }
      else
        {
         ok=m_broker.MarketSell(decision.symbol,volume,sl,tp,ticket,fillPrice,comment);
        }
      if(ok)
        {
         m_trades[idx].fsm.SetTicket(ticket);
         m_trades[idx].fsm.Transition(TS_FILLED);
         m_trades[idx].fillPrice=fillPrice;
         double totalMs=m_trades[idx].fsm.TotalLatencyMs();
         if(m_monitor!=NULL && totalMs>=0.0) m_monitor.NotifyTradeLatency(totalMs,m_broker.LastLatencyMs());
        }
      else m_trades[idx].fsm.Transition(TS_REJECTED);
     }
   else
     {
      m_trades[idx].fsm.Transition(TS_WAITING);
      m_trades[idx].fsm.Transition(TS_PENDING);
      ENUM_ORDER_TYPE limitType=(decision.setup.type==ORDER_TYPE_BUY)?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT;
      string comment="MT#"+IntegerToString(decision.decision_id)+(legIndex>0?":L"+IntegerToString(legIndex):"");
      ok=m_broker.PlaceLimit(decision.symbol,limitType,volume,entry,sl,tp,ticket,comment);
      if(ok) m_trades[idx].fsm.SetTicket(ticket);
      else m_trades[idx].fsm.Transition(TS_REJECTED);
     }
   if(ok) ticketOut=ticket;
   return ok;
  }
//+------------------------------------------------------------------+
bool COrderManager::RestoreTrade(const TradeDecisionRecord &decision,double volume,ulong ticket,ENUM_TRADE_STATE state,double fillPrice,int legIndex)
  {
   if(volume<=0 || ticket==0) return false;
   if(FindByTicket(ticket)>=0) return false;
   if(legIndex<0) return false;
   int idx=ArraySize(m_trades);
   ArrayResize(m_trades,idx+1);
   m_trades[idx].decision=decision;
   m_trades[idx].volume=volume;
   m_trades[idx].fillPrice=fillPrice;
   m_trades[idx].legIndex=legIndex;
   m_trades[idx].positionIdentifier=0;
   m_trades[idx].fsm.Start(decision.decision_id);
   m_trades[idx].fsm.BindMonitor(m_monitor);
   m_trades[idx].fsm.SetTicket(ticket);
   m_trades[idx].fsm.ForceState(state);
   return true;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/OrderManager.mqh
// BEGIN INLINED MODULE: includes/Portfolio/MultiTradeEngine.mqh
//+------------------------------------------------------------------+
//| Portfolio/MultiTradeEngine.mqh                                    |
//| High-probability multi-leg portfolio allocation policy.           |
//+------------------------------------------------------------------+
#ifndef MULTITRADEENGINE_MQH
#define MULTITRADEENGINE_MQH

// already inlined once under include guard: includes/Core/Config.mqh

#define MULTITRADE_MAX_LEGS 3

struct MultiTradePlan
  {
   bool eligible;
   int legCount;
   double riskFraction[MULTITRADE_MAX_LEGS];
   double target[MULTITRADE_MAX_LEGS];
   string label[MULTITRADE_MAX_LEGS];
   string reason;
  };

class CMultiTradeEngine
  {
private:
   bool   m_enabled;
   double m_dualProbability;
   double m_tripleProbability;
   double m_minRawConfidence;
   int    m_minCalibrationSample;
   double m_dualRiskFraction0;
   double m_dualRiskFraction1;
   double m_tripleRiskFraction0;
   double m_tripleRiskFraction1;
   double m_tripleRiskFraction2;
   bool   m_requireHedging;

public:
   void Init(bool enabled,double dualProbability,double tripleProbability,
             double minRawConfidence,int minCalibrationSample,
             double dualRiskFraction0,double dualRiskFraction1,
             double tripleRiskFraction0,double tripleRiskFraction1,double tripleRiskFraction2,
             bool requireHedging=true);
   bool Build(const TradeSetup &setup,int availableSlots,MultiTradePlan &out);
   bool IsHedgingAccount() const;
  };

void CMultiTradeEngine::Init(bool enabled,double dualProbability,double tripleProbability,
                             double minRawConfidence,int minCalibrationSample,
                             double dualRiskFraction0,double dualRiskFraction1,
                             double tripleRiskFraction0,double tripleRiskFraction1,double tripleRiskFraction2,
                             bool requireHedging)
  {
   m_enabled=enabled;
   m_dualProbability=MathMax(0.0,MathMin(100.0,dualProbability));
   m_tripleProbability=MathMax(m_dualProbability,MathMin(100.0,tripleProbability));
   m_minRawConfidence=MathMax(0.0,MathMin(100.0,minRawConfidence));
   m_minCalibrationSample=MathMax(1,minCalibrationSample);
   m_dualRiskFraction0=MathMax(0.0,dualRiskFraction0);
   m_dualRiskFraction1=MathMax(0.0,dualRiskFraction1);
   m_tripleRiskFraction0=MathMax(0.0,tripleRiskFraction0);
   m_tripleRiskFraction1=MathMax(0.0,tripleRiskFraction1);
   m_tripleRiskFraction2=MathMax(0.0,tripleRiskFraction2);
   m_requireHedging=requireHedging;
  }

bool CMultiTradeEngine::IsHedgingAccount() const
  {
   return (AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

bool CMultiTradeEngine::Build(const TradeSetup &setup,int availableSlots,MultiTradePlan &out)
  {
   ZeroMemory(out);
   out.eligible=false;
   out.legCount=1;
   out.riskFraction[0]=1.0;
   out.target[0]=setup.final_tp;
   out.label[0]="PRIMARY";
   out.reason="single-trade path";

   if(!m_enabled) { out.reason="multi-trade disabled"; return true; }
   if(!setup.active) { out.reason="setup inactive"; return true; }
   if(availableSlots<2) { out.reason="fewer than two execution slots available"; return true; }
   if(!MathIsValidNumber(setup.confidence) || setup.confidence<0.0 || setup.confidence>100.0)
     { out.reason="raw confidence is non-finite or outside [0,100]"; return true; }
   if(!MathIsValidNumber(setup.calibrated_probability) || setup.calibrated_probability<0.0 || setup.calibrated_probability>100.0)
     { out.reason="calibrated probability is non-finite or outside [0,100]"; return true; }
   if(!setup.calibration_has_enough_data || setup.calibration_sample<m_minCalibrationSample)
     { out.reason="calibration sample is insufficient for multi-trade scaling"; return true; }
   if(setup.confidence<m_minRawConfidence)
     { out.reason="raw confidence below multi-trade floor"; return true; }
   if(setup.calibrated_probability<m_dualProbability)
     { out.reason="calibrated probability below dual-trade threshold"; return true; }
   if(m_requireHedging && !IsHedgingAccount())
     { out.reason="multi-trade requires MT5 hedging account semantics"; return true; }

   int legs=2;
   if(availableSlots>=3 && setup.calibrated_probability>=m_tripleProbability)
      legs=3;

   out.eligible=true;
   out.legCount=legs;
   if(legs==2)
     {
      out.riskFraction[0]=m_dualRiskFraction0;
      out.riskFraction[1]=m_dualRiskFraction1;
      out.target[0]=setup.tp1;
      out.target[1]=setup.final_tp;
      out.label[0]="TP1";
      out.label[1]="FINAL";
      out.reason=StringFormat("dual execution: calibrated probability %.1f%%",setup.calibrated_probability);
     }
   else
     {
      out.riskFraction[0]=m_tripleRiskFraction0;
      out.riskFraction[1]=m_tripleRiskFraction1;
      out.riskFraction[2]=m_tripleRiskFraction2;
      out.target[0]=setup.tp1;
      out.target[1]=setup.tp2;
      out.target[2]=setup.final_tp;
      out.label[0]="TP1";
      out.label[1]="TP2";
      out.label[2]="FINAL";
      out.reason=StringFormat("triple execution: calibrated probability %.1f%%",setup.calibrated_probability);
     }

   double fractionTotal=0.0;
   for(int i=0;i<out.legCount;i++)
      fractionTotal+=out.riskFraction[i];
   if(MathAbs(fractionTotal-1.0)>0.000001)
     {
      ZeroMemory(out);
      out.eligible=false;
      out.legCount=1;
      out.riskFraction[0]=1.0;
      out.target[0]=setup.final_tp;
      out.label[0]="PRIMARY";
      out.reason="invalid multi-trade risk allocation";
      return false;
     }
   return true;
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Portfolio/MultiTradeEngine.mqh
// BEGIN INLINED MODULE: includes/Execution/PositionManager.mqh
//+------------------------------------------------------------------+
//| Execution/PositionManager.mqh                                    |
//+------------------------------------------------------------------+
#ifndef POSITIONMANAGER_MQH
#define POSITIONMANAGER_MQH

// already inlined once under include guard: includes/Execution/OrderManager.mqh
// already inlined once under include guard: includes/Execution/BrokerAdapter.mqh
// BEGIN INLINED MODULE: includes/Execution/ExecutionLedgerClient.mqh
//+------------------------------------------------------------------+
//| Execution/ExecutionLedgerClient.mqh                              |
//| Fail-closed HTTP client for bridge-side durable execution state. |
//+------------------------------------------------------------------+
#ifndef MIDAS_EXECUTIONLEDGERCLIENT_MQH
#define MIDAS_EXECUTIONLEDGERCLIENT_MQH

class CExecutionLedgerClient
  {
private:
   string m_baseUrl;
   string m_apiKey;
   string m_portfolioKey;
   int    m_timeoutMs;
   bool   m_ready;
   bool   m_admissionHealthy;

   string JsonSafe(string value)
     {
      // Keep identifiers JSON-safe. Server names/symbols should not contain
      // these characters, but sanitizing them prevents malformed request JSON.
      StringReplace(value,"\\","/");
      StringReplace(value,"\"","'");
      StringReplace(value,"\r"," ");
      StringReplace(value,"\n"," ");
      return value;
     }

   bool PostJson(const string path,const string &payload)
     {
      if(!m_ready) return false;

      char data[];
      int len=StringToCharArray(payload,data,0,WHOLE_ARRAY,CP_UTF8);
      if(len>0)
         ArrayResize(data,len-1); // remove the terminal NUL; HTTP body is UTF-8 JSON
      else
         ArrayResize(data,0);

      char result[];
      string resultHeaders;
      string headers="Content-Type: application/json\r\nX-API-Key: "+m_apiKey+"\r\n";
      ResetLastError();
      int status=WebRequest("POST",m_baseUrl+path,headers,m_timeoutMs,data,result,resultHeaders);
      if(status==-1)
        {
         m_admissionHealthy=false;
         PrintFormat("Midas execution ledger: POST %s failed at transport layer (error=%d); do not assume broker outcome.",path,GetLastError());
         return false;
        }
      if(status<200 || status>=300)
        {
         m_admissionHealthy=false;
         PrintFormat("Midas execution ledger: POST %s returned HTTP %d; response=%s",path,status,CharArrayToString(result));
         return false;
        }
      return true;
     }

public:
    void Init(const string baseUrl,const string apiKey,const ulong magicNumber,int timeoutMs=5000)
      {
      m_baseUrl=baseUrl;
      while(StringLen(m_baseUrl)>0 && StringSubstr(m_baseUrl,StringLen(m_baseUrl)-1,1)=="/")
         m_baseUrl=StringSubstr(m_baseUrl,0,StringLen(m_baseUrl)-1);
      m_apiKey=apiKey;
      m_timeoutMs=MathMax(1000,timeoutMs);
      m_portfolioKey="";
      m_ready=false;
       m_admissionHealthy=false;

       if(StringLen(m_baseUrl)<8 || StringLen(m_apiKey)==0)
         {
          Print("Midas execution ledger: base URL or bridge API key missing; remote execution ledger is not ready.");
          return;
         }

      string server=JsonSafe(AccountInfoString(ACCOUNT_SERVER));
      string login=IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
      string magicText=IntegerToString((long)magicNumber);
      // Account + broker server + strategy magic defines an isolated risk book.
      m_portfolioKey=server+":"+login+":"+magicText;
      if(StringLen(m_portfolioKey)>80)
        {
         Print("Midas execution ledger: portfolio key exceeds safe request-ID budget.");
         m_portfolioKey="";
         return;
        }
      m_ready=true;
      // Configuration is not proof of bridge/database readiness. Admission
      // remains closed until the authenticated health probe succeeds.
      m_admissionHealthy=false;
     }

   bool CheckHealth()
     {
      // MetaTrader explicitly disallows WebRequest inside Strategy Tester agents.
      // Research backtests must run with the bridge disconnected and ledger admission
      // explicitly disabled; demo/live operation remains fail-closed by default.
      if((bool)MQLInfoInteger(MQL_TESTER))
        {
         m_admissionHealthy=false;
         Print("Midas execution ledger: WebRequest is unavailable in Strategy Tester; disable ledger enforcement only for isolated backtests.");
         return false;
        }
      if(!m_ready)
        {
         m_admissionHealthy=false;
         return false;
        }
      char data[];
      ArrayResize(data,0);
      char result[];
      string resultHeaders;
      string headers="X-API-Key: "+m_apiKey+"\r\n";
      ResetLastError();
      int status=WebRequest("GET",m_baseUrl+"/execution-ledger/health",headers,
                            m_timeoutMs,data,result,resultHeaders);
      if(status!=200)
        {
         m_admissionHealthy=false;
         PrintFormat("Midas execution ledger: authenticated health probe failed (HTTP=%d, error=%d); new entries remain blocked.",
                     status,GetLastError());
         return false;
        }
      string body=CharArrayToString(result,0,-1,CP_UTF8);
      string quote=CharToString(34);
      string readinessToken=quote+"execution_ledger"+quote+":"+quote+"ready"+quote;
      string schemaToken=quote+"ledger_schema"+quote+":"+quote+"ready"+quote;
      if(StringFind(body,readinessToken)<0 || StringFind(body,schemaToken)<0)
        {
         m_admissionHealthy=false;
         PrintFormat("Midas execution ledger: health response did not confirm execution_ledger=ready and ledger_schema=ready; body=%s",body);
         return false;
        }
      m_admissionHealthy=true;
      return true;
     }

   bool Ready() const { return m_ready; }
   bool AdmissionReady() const { return (m_ready && m_admissionHealthy); }
   void RequireReconciliation() { m_admissionHealthy=false; }
   void MarkReconciled() { if(m_ready) m_admissionHealthy=true; }
   string PortfolioKey() const { return m_portfolioKey; }

   string RequestIdForDecision(const long decisionId,const int legIndex)
     {
      return m_portfolioKey+":decision:"+IntegerToString(decisionId)+":leg:"+IntegerToString(legIndex);
     }

   string RequestIdForPosition(const ulong positionIdentifier)
     {
      return "position:"+m_portfolioKey+":"+IntegerToString((long)positionIdentifier);
     }

   string RequestIdForPendingOrder(const ulong orderTicket)
     {
      return "pending:"+m_portfolioKey+":"+IntegerToString((long)orderTicket);
     }

   bool Reserve(const long decisionId,const int legIndex,const string signalId,
                const string symbol,const string direction,const double riskR,
                const double volatility,string &requestId)
     {
      requestId=RequestIdForDecision(decisionId,legIndex);
      if(!AdmissionReady() || StringLen(requestId)>128 || riskR<=0.0 ||
         !MathIsValidNumber(riskR) || volatility<0.0 || !MathIsValidNumber(volatility))
         return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"request_id\":\"%s\",\"signal_id\":\"%s\",\"symbol\":\"%s\",\"direction\":\"%s\",\"risk_r\":%.8f,\"volatility\":%.8f,\"factors\":{},\"max_heat_r\":3.0,\"requested_by\":\"MT5_EA\"}",
         JsonSafe(m_portfolioKey),JsonSafe(requestId),JsonSafe(signalId),
         JsonSafe(symbol),JsonSafe(direction),riskR,volatility);
      return PostJson("/execution-ledger/reserve",payload);
     }

   bool Transition(const string requestId,const string state,const string resultJson="{}")
     {
      if(!m_ready || StringLen(requestId)==0 || StringLen(resultJson)==0) return false;
      string payload=StringFormat("{\"request_id\":\"%s\",\"state\":\"%s\",\"result\":%s}",
                                  JsonSafe(requestId),JsonSafe(state),resultJson);
      return PostJson("/execution-ledger/transition",payload);
     }

   bool SyncPosition(const ulong positionIdentifier,const ulong orderId,const ulong dealId,
                     const string symbol,const string direction,const double riskR,
                     const double volatility,const string evidenceRef,
                     const string requestIdOverride="",const double stopLoss=0.0,const double takeProfit=0.0)
     {
      if(!m_ready || positionIdentifier==0 || riskR<0.0 || !MathIsValidNumber(riskR)) return false;
      string requestId=requestIdOverride;
      if(StringLen(requestId)==0) requestId=RequestIdForPosition(positionIdentifier);
      string orderIdJson=(orderId>0)?StringFormat("\"%I64u\"",orderId):"null";
      string dealIdJson=(dealId>0)?StringFormat("\"%I64u\"",dealId):"null";
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"request_id\":\"%s\",\"broker_position_id\":\"%I64u\",\"broker_order_id\":%s,\"broker_deal_id\":%s,\"symbol\":\"%s\",\"direction\":\"%s\",\"risk_r\":%.8f,\"volatility\":%.8f,\"factors\":{},\"evidence_ref\":\"%s\",\"stop_loss\":%.10f,\"take_profit\":%.10f}",
         JsonSafe(m_portfolioKey),JsonSafe(requestId),positionIdentifier,orderIdJson,dealIdJson,
         JsonSafe(symbol),JsonSafe(direction),riskR,MathMax(0.0,volatility),JsonSafe(evidenceRef),stopLoss,takeProfit);
      return PostJson("/execution-ledger/sync-position",payload);
     }

   bool SyncPendingOrder(const ulong orderTicket,const string symbol,const string direction,
                         const double riskR,const double volatility,const string evidenceRef,
                         const string requestIdOverride="")
     {
      if(!m_ready || orderTicket==0 || riskR<=0.0 || !MathIsValidNumber(riskR)) return false;
      string requestId=requestIdOverride;
      if(StringLen(requestId)==0) requestId=RequestIdForPendingOrder(orderTicket);
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"request_id\":\"%s\",\"broker_order_id\":\"%I64u\",\"symbol\":\"%s\",\"direction\":\"%s\",\"risk_r\":%.8f,\"volatility\":%.8f,\"factors\":{},\"evidence_ref\":\"%s\"}",
         JsonSafe(m_portfolioKey),JsonSafe(requestId),orderTicket,
         JsonSafe(symbol),JsonSafe(direction),riskR,MathMax(0.0,volatility),JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/sync-pending-order",payload);
     }


   bool PreparePositionModification(const string eventId,const ulong positionIdentifier,
                                     const string symbol,const string direction,
                                     const double oldSL,const double oldTP,
                                     const double proposedSL,const double proposedTP,
                                     const string evidenceRef)
     {
      if(!AdmissionReady() || StringLen(eventId)==0 || positionIdentifier==0 ||
         oldSL<0.0 || oldTP<0.0 || proposedSL<=0.0 || proposedTP<0.0 ||
         !MathIsValidNumber(oldSL) || !MathIsValidNumber(oldTP) ||
         !MathIsValidNumber(proposedSL) || !MathIsValidNumber(proposedTP))
         return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"event_id\":\"%s\",\"broker_position_id\":\"%I64u\",\"symbol\":\"%s\",\"direction\":\"%s\",\"old_stop_loss\":%.10f,\"old_take_profit\":%.10f,\"proposed_stop_loss\":%.10f,\"proposed_take_profit\":%.10f,\"evidence_ref\":\"%s\",\"requested_by\":\"MT5_EA\"}",
         JsonSafe(m_portfolioKey),JsonSafe(eventId),positionIdentifier,JsonSafe(symbol),JsonSafe(direction),
         oldSL,oldTP,proposedSL,proposedTP,JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/position-modification/prepare",payload);
     }

   bool ConfirmPositionModification(const string eventId,const double actualSL,const double actualTP,
                                    const double riskR,const double volatility,const string evidenceRef)
     {
      if(!m_ready || StringLen(eventId)==0 || actualSL<=0.0 || actualTP<0.0 ||
         riskR<0.0 || volatility<0.0 || !MathIsValidNumber(actualSL) ||
         !MathIsValidNumber(actualTP) || !MathIsValidNumber(riskR) || !MathIsValidNumber(volatility))
         return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"event_id\":\"%s\",\"actual_stop_loss\":%.10f,\"actual_take_profit\":%.10f,\"risk_r\":%.8f,\"volatility\":%.8f,\"evidence_ref\":\"%s\",\"requested_by\":\"MT5_EA\"}",
         JsonSafe(m_portfolioKey),JsonSafe(eventId),actualSL,actualTP,riskR,volatility,JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/position-modification/confirm",payload);
     }

   bool UpdatePositionRisk(const ulong positionIdentifier,const string direction,
                           const double riskR,const double volatility,const string evidenceRef)
     {
      if(!m_ready || positionIdentifier==0 || riskR<0.0 || !MathIsValidNumber(riskR)) return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"broker_position_id\":\"%I64u\",\"direction\":\"%s\",\"risk_r\":%.8f,\"volatility\":%.8f,\"factors\":{},\"evidence_ref\":\"%s\"}",
         JsonSafe(m_portfolioKey),positionIdentifier,JsonSafe(direction),riskR,
         MathMax(0.0,volatility),JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/position-risk",payload);
     }

   bool ClosePosition(const ulong positionIdentifier,const ulong closingDealId,const string evidenceRef,
                      const string requestIdOverride="")
     {
      if(!m_ready || positionIdentifier==0 || closingDealId==0) return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"request_id\":\"%s\",\"broker_position_id\":\"%I64u\",\"broker_deal_id\":\"%I64u\",\"evidence_ref\":\"%s\"}",
         JsonSafe(m_portfolioKey),JsonSafe(requestIdOverride),positionIdentifier,closingDealId,JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/position-closed",payload);
     }


   bool SyncClosedPosition(const ulong positionIdentifier,const ulong closingDealId,const string evidenceRef,
                           const string requestIdOverride="")
     {
      if(!m_ready || positionIdentifier==0 || closingDealId==0) return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"request_id\":\"%s\",\"broker_position_id\":\"%I64u\",\"broker_deal_id\":\"%I64u\",\"evidence_ref\":\"%s\"}",
         JsonSafe(m_portfolioKey),JsonSafe(requestIdOverride),positionIdentifier,closingDealId,JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/sync-closed-position",payload);
     }

   bool RecoverExpired()
     {
      return PostJson("/execution-ledger/recover-expired","{}");
     }


   bool DealEvent(const string requestId,const ulong dealId,const ulong orderId,
                  const ulong positionIdentifier,const string symbol,const string entryType,
                  const string dealType,const string positionDirection,const double volume,
                  const double price,const double profitCashflow,const double commissionCashflow,
                  const double swapCashflow,const double feeCashflow,const bool cashflowsKnown,
                  const bool positionOpen,const double remainingVolume,const double riskR,
                  const double volatility,const string evidenceRef)
     {
      if(!m_ready || StringLen(requestId)==0 || StringLen(requestId)>128 ||
         dealId==0 || positionIdentifier==0 || volume<=0.0 || price<=0.0 ||
         !MathIsValidNumber(volume) || !MathIsValidNumber(price) ||
         !MathIsValidNumber(profitCashflow) || !MathIsValidNumber(commissionCashflow) ||
         !MathIsValidNumber(swapCashflow) || !MathIsValidNumber(feeCashflow) ||
         !MathIsValidNumber(remainingVolume) || !MathIsValidNumber(riskR) ||
         !MathIsValidNumber(volatility) || remainingVolume<0.0 || riskR<0.0 || volatility<0.0)
         return false;
      if(positionOpen && (remainingVolume<=0.0 || riskR<0.0)) return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"request_id\":\"%s\",\"broker_deal_id\":\"%I64u\",\"broker_order_id\":\"%I64u\",\"broker_position_id\":\"%I64u\",\"symbol\":\"%s\",\"entry_type\":\"%s\",\"deal_type\":\"%s\",\"direction\":\"%s\",\"volume\":%.8f,\"price\":%.8f,\"profit_cashflow\":%.8f,\"commission_cashflow\":%.8f,\"swap_cashflow\":%.8f,\"fee_cashflow\":%.8f,\"cashflows_known\":%s,\"position_open\":%s,\"remaining_volume\":%.8f,\"risk_r\":%.8f,\"volatility\":%.8f,\"factors\":{},\"evidence_ref\":\"%s\"}",
         JsonSafe(m_portfolioKey),JsonSafe(requestId),dealId,orderId,positionIdentifier,
         JsonSafe(symbol),JsonSafe(entryType),JsonSafe(dealType),JsonSafe(positionDirection),
         volume,price,profitCashflow,commissionCashflow,swapCashflow,feeCashflow,
         cashflowsKnown?"true":"false",positionOpen?"true":"false",remainingVolume,
         riskR,volatility,JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/deal-event",payload);
     }

   bool TerminalOrder(const ulong orderTicket,const string state,const string evidenceRef)
     {
      if(!m_ready || orderTicket==0 || (state!="CANCELLED" && state!="REJECTED")) return false;
      string payload=StringFormat(
         "{\"portfolio_key\":\"%s\",\"broker_order_id\":\"%I64u\",\"terminal_state\":\"%s\",\"evidence_ref\":\"%s\"}",
         JsonSafe(m_portfolioKey),orderTicket,JsonSafe(state),JsonSafe(evidenceRef));
      return PostJson("/execution-ledger/order-terminal",payload);
     }
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/ExecutionLedgerClient.mqh
// already inlined once under include guard: includes/Trading/RiskEngine.mqh
// BEGIN INLINED MODULE: includes/Execution/DynamicStopEngine.mqh
//+------------------------------------------------------------------+
//| Execution/DynamicStopEngine.mqh                                  |
//| Dynamic Stop Engine v1 — deterministic stop-policy layer.        |
//+------------------------------------------------------------------+
#ifndef DYNAMICSTOPENGINE_MQH
#define DYNAMICSTOPENGINE_MQH

// BEGIN INLINED MODULE: includes/Execution/DynamicStopInputs.mqh
//+------------------------------------------------------------------+
//| Execution/DynamicStopInputs.mqh                                  |
//| Canonical EA-facing controls for Dynamic Stop Engine v1.          |
//+------------------------------------------------------------------+
#ifndef DYNAMICSTOPINPUTS_MQH
#define DYNAMICSTOPINPUTS_MQH

input group "Dynamic Stop Engine v1"
input bool   InpEnableDynamicStop = true;       // protect open positions after the initial structural SL
input double InpDynamicStopActivateAtR = 0.75;  // protection activates at +0.75R
input double InpDynamicStopBreakevenAtR = 1.00; // breakeven protection begins at +1R
input double InpDynamicStopATRMult = 1.50;      // ATR fallback trailing distance
input double InpDynamicStopMinImprovementPoints = 2.0; // ignore insignificant SL changes
input int    InpDynamicStopMaxSpreadPoints = 0; // 0 = no additional modification spread gate
input double InpDynamicStopMinATR = 0.0;        // 0 = no volatility floor
input double InpDynamicStopMaxATR = 0.0;        // 0 = no volatility ceiling
input int    InpDynamicStopModifyIntervalSec = 5; // minimum seconds between successful SL changes per ticket
input bool   InpDynamicStopUseStructuralAnchor = true; // prefer an explicit structure-derived anchor when supplied
input double InpDynamicStopStructuralBufferATR = 0.10; // buffer beyond the structural anchor, in ATR

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/DynamicStopInputs.mqh

enum ENUM_DYNAMIC_STOP_STAGE
  {
   DSE_STRUCTURAL = 0,
   DSE_PROTECTION = 1,
   DSE_BREAKEVEN  = 2,
   DSE_TRAILING   = 3
  };

struct DynamicStopConfig
  {
   double activateAtR;
   double breakevenAtR;
   double atrMultiplier;
   double minImprovementPts;
   int    maxSpreadPoints;
   double minATR;
   double maxATR;
   bool   useStructuralAnchor;
   double structuralBufferATR;

   void SetDefaults()
     {
      activateAtR          = 0.75;
      breakevenAtR         = 1.00;
      atrMultiplier        = 1.50;
      minImprovementPts    = 2.0;
      maxSpreadPoints      = 0;
      minATR               = 0.0;
      maxATR               = 0.0;
      useStructuralAnchor  = true;
      structuralBufferATR  = 0.10;
     }
  };

struct DynamicStopDecision
  {
   ENUM_DYNAMIC_STOP_STAGE stage;
   double proposedSL;
   bool modify;
   string reason;
  };

class CDynamicStopEngine
  {
private:
   DynamicStopConfig m_cfg;

   bool IsTighter(bool isBuy,double candidate,double current) const
     {
      if(candidate<=0.0) return false;
      if(current<=0.0) return true;
      return isBuy ? candidate>current : candidate<current;
     }

   bool ImprovementLargeEnough(string symbol,double candidate,double current,
                               double pointOverride=0.0) const
     {
      double point=(MathIsValidNumber(pointOverride) && pointOverride>0.0)
                   ? pointOverride : SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0) return true;
      return MathAbs(candidate-current)>=m_cfg.minImprovementPts*point;
     }

   // Preflight the same broker geometry that BrokerAdapter validates before
   // sending PositionModify().  For an open BUY the protective stop is
   // measured from Bid; for an open SELL it is measured from Ask.  Stops
   // and freeze levels are broker constraints, not strategy preferences.
   // Rejecting here avoids repeatedly generating modifications that the
   // broker is guaranteed to reject while the price is inside the freeze
   // band. BrokerAdapter still performs the authoritative final check.
   bool BrokerDistanceSafe(string symbol,bool isBuy,double candidate,double currentPrice,
                           double pointOverride=0.0) const
     {
      if(candidate<=0.0 || currentPrice<=0.0) return false;
      // A positive explicit point is a deterministic unit-test seam; production
      // calls leave it at zero and must obtain symbol metadata from the terminal.
      double point=(MathIsValidNumber(pointOverride) && pointOverride>0.0)
                   ? pointOverride : SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0) return false;

      // A protective stop must be strictly on the loss side of the live
      // executable quote even when this broker reports zero stop/freeze
      // distance. With a zero/missing ATR, the fallback candidate can equal
      // the market price; reject it here rather than sending a predictably
      // invalid modification to the broker adapter.
      bool wrongSide=isBuy ? (candidate>=currentPrice) : (candidate<=currentPrice);
      if(wrongSide) return false;

      long stops=(long)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
      long freeze=(long)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      long required=MathMax(stops,freeze);
      if(required<=0) return true;
      double minDistance=(double)required*point;
      return MathAbs(currentPrice-candidate)>=minDistance;
     }

public:
   void Configure(const DynamicStopConfig &cfg) { m_cfg=cfg; }
   DynamicStopConfig Config() const { return m_cfg; }

private:
   // structuralAnchor is supplied by the caller from a confirmed market
   // structure point. Zero means "no anchor available" and causes a
   // deterministic ATR fallback rather than inventing structure.
   DynamicStopDecision EvaluateInternal(string symbol,bool isBuy,double entry,
                                double structuralSL,double currentSL,
                                double currentPrice,double atr,
                                double spreadPoints,
                                double structuralAnchor,
                                double pointOverride) const
     {
      DynamicStopDecision d;
      d.stage=DSE_STRUCTURAL;
      d.proposedSL=structuralSL;
      d.modify=false;
      d.reason="structural stop retained";

      if(entry<=0.0 || structuralSL<=0.0 || currentPrice<=0.0)
        { d.reason="invalid entry/structural stop/price"; return d; }
      if(m_cfg.maxSpreadPoints>0 && spreadPoints>m_cfg.maxSpreadPoints)
        { d.reason="spread protection"; return d; }
      if(m_cfg.minATR>0.0 && atr<m_cfg.minATR)
        { d.reason="volatility below floor"; return d; }
      if(m_cfg.maxATR>0.0 && atr>m_cfg.maxATR)
        { d.reason="volatility above ceiling"; return d; }

      double risk=MathAbs(entry-structuralSL);
      if(risk<=0.0) { d.reason="zero structural risk"; return d; }
      double favorableMove=isBuy ? currentPrice-entry : entry-currentPrice;
      double r=favorableMove/risk;
      if(r<m_cfg.activateAtR) return d;

      d.stage=DSE_PROTECTION;
      double candidate=isBuy
                        ? currentPrice-MathMax(atr,0.0)*m_cfg.atrMultiplier
                        : currentPrice+MathMax(atr,0.0)*m_cfg.atrMultiplier;

      if(m_cfg.useStructuralAnchor && structuralAnchor>0.0 && atr>0.0)
        {
         double anchorCandidate=isBuy
                               ? structuralAnchor-MathMax(0.0,m_cfg.structuralBufferATR)*atr
                               : structuralAnchor+MathMax(0.0,m_cfg.structuralBufferATR)*atr;
         // Never manufacture a stop on the wrong side of the market.
         bool validAnchor=isBuy ? (anchorCandidate<currentPrice && anchorCandidate>0.0)
                                : (anchorCandidate>currentPrice && anchorCandidate>0.0);
         if(validAnchor)
           {
            candidate=anchorCandidate;
            d.stage=DSE_TRAILING;
            d.reason="confirmed structural-anchor trailing";
           }
        }

      if(r>=m_cfg.breakevenAtR)
        {
         if(isBuy) candidate=MathMax(candidate,entry);
         else      candidate=MathMin(candidate,entry);
         if(d.stage!=DSE_TRAILING)
            d.stage=(atr>0.0 ? DSE_TRAILING : DSE_BREAKEVEN);
        }

      if(!BrokerDistanceSafe(symbol,isBuy,candidate,currentPrice,pointOverride))
        {
         d.reason="broker stops/freeze distance protection";
         return d;
        }

      if(IsTighter(isBuy,candidate,currentSL) && ImprovementLargeEnough(symbol,candidate,currentSL,pointOverride))
        {
         d.proposedSL=candidate;
         d.modify=true;
         if(d.reason=="structural stop retained")
            d.reason=(d.stage==DSE_BREAKEVEN ? "+1R breakeven protection" : "+0.75R protection");
        }
      else if(!IsTighter(isBuy,candidate,currentSL))
         d.reason="candidate would widen or equal current stop";
      else
         d.reason="improvement below modification threshold";
      return d;
     }
public:
   // Production entry point: always uses real terminal symbol metadata.
   DynamicStopDecision Evaluate(string symbol,bool isBuy,double entry,
                                double structuralSL,double currentSL,
                                double currentPrice,double atr,
                                double spreadPoints=0.0,
                                double structuralAnchor=0.0) const
     {
      return EvaluateInternal(symbol,isBuy,entry,structuralSL,currentSL,
                              currentPrice,atr,spreadPoints,structuralAnchor,0.0);
     }

#ifdef MIDAS_DYNAMIC_STOP_TESTING
   // Test-only geometry injection is not compiled into the production EA.
   DynamicStopDecision EvaluateForTest(string symbol,bool isBuy,double entry,
                                       double structuralSL,double currentSL,
                                       double currentPrice,double atr,
                                       double spreadPoints,double structuralAnchor,
                                       double pointOverride) const
     {
      return EvaluateInternal(symbol,isBuy,entry,structuralSL,currentSL,
                              currentPrice,atr,spreadPoints,structuralAnchor,pointOverride);
     }
#endif
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/DynamicStopEngine.mqh
// already inlined once under include guard: includes/Execution/DynamicStopInputs.mqh
// BEGIN INLINED MODULE: includes/Execution/PositionManagementPolicy.mqh
//+------------------------------------------------------------------+
//| Execution/PositionManagementPolicy.mqh                            |
//| Pure policy helpers for independently testable position handling. |
//+------------------------------------------------------------------+
#ifndef POSITIONMANAGEMENTPOLICY_MQH
#define POSITIONMANAGEMENTPOLICY_MQH

// already inlined once under include guard: includes/Execution/TradeStateMachine.mqh

// Partial profit-taking is an exit policy, not a side effect of trailing
// stop modification. A filled position can reach its partial target even
// when dynamic trailing is disabled or a broker rejects a stop edit.
// Recovery must restore trade state and remaining volume before this policy
// is evaluated; this helper intentionally does not infer broker fills.
bool ShouldTakePartialAtR(ENUM_TRADE_STATE state,double r,double partialAtR)
  {
   if(!MathIsValidNumber(r) || !MathIsValidNumber(partialAtR)) return false;
   if(partialAtR<=0.0 || r<partialAtR) return false;
   return (state==TS_FILLED || state==TS_PROTECTED);
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/PositionManagementPolicy.mqh
// BEGIN INLINED MODULE: includes/Monitoring/SLModificationAudit.mqh
//+------------------------------------------------------------------+
//| Monitoring/SLModificationAudit.mqh                               |
//| Append-only local audit trail for successful SL changes.          |
//+------------------------------------------------------------------+
#ifndef SLMODIFICATIONAUDIT_MQH
#define SLMODIFICATIONAUDIT_MQH

class CSLModificationAudit
  {
private:
   string m_file;
   bool   m_common;
public:
   void Init(string fileName="MedisTouch_SL_Audit.csv", bool useCommonFolder=false)
     {
      m_file=fileName;
      m_common=useCommonFolder;
      int flags=FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI;
      if(m_common) flags|=FILE_COMMON;
      int h=FileOpen(m_file,flags,',');
      if(h==INVALID_HANDLE)
        {
         PrintFormat("MedisTouch SL audit: cannot open %s",m_file);
         return;
        }
      if(FileSize(h)==0)
         FileWrite(h,"timestamp","ticket","symbol","side","stage","old_sl","new_sl","price","r_multiple","reason");
      FileClose(h);
     }

   void Record(ulong ticket,string symbol,bool isBuy,string stage,double oldSL,double newSL,
               double price,double rMultiple,string reason)
     {
      int flags=FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI;
      if(m_common) flags|=FILE_COMMON;
      int h=FileOpen(m_file,flags,',');
      if(h==INVALID_HANDLE)
        {
         PrintFormat("MedisTouch SL audit: failed to append ticket #%d",ticket);
         return;
        }
      FileSeek(h,0,SEEK_END);
      FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),IntegerToString((long)ticket),symbol,
                isBuy?"BUY":"SELL",stage,DoubleToString(oldSL,8),DoubleToString(newSL,8),
                DoubleToString(price,8),DoubleToString(rMultiple,4),reason);
      FileFlush(h);
      FileClose(h);
     }
  };
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Monitoring/SLModificationAudit.mqh
// already inlined once under include guard: includes/Structure/SwingDetector.mqh

class CPositionManager
  {
private:
   COrderManager*        m_orders;
   CBrokerAdapter*       m_broker;
   CExecutionLedgerClient* m_ledger;
   CRiskEngine*           m_risk;
   double                 m_riskPercent;
   CSwingDetector*       m_structureSwings;
   CSLModificationAudit  m_audit;
   CDynamicStopEngine    m_dynamicStop;
   double                m_partialAtR;
   double                m_partialFraction;
   int                   m_minModifyIntervalSec;
   ulong                 m_lastModifyTickets[];
   datetime              m_lastModifyTimes[];

   double CurrentExitPrice(string symbol,bool isBuy);
   bool   PartialVolumeForPosition(string symbol,double currentVolume,double &closeVolume);
   double RMultiple(const TradeDecisionRecord &dec,double entry,double price);
   bool   CanModifyNow(ulong ticket);
   void   RecordModification(ulong ticket);
   double ConfirmedStructuralAnchor(bool isBuy);

public:
   void Init(COrderManager* orders,CBrokerAdapter* broker,
             double breakEvenAtR,double partialAtR,double partialFraction,double trailAtrMult,
             int maxSpreadPoints=0,double minATR=0.0,double maxATR=0.0,
             int minModifyIntervalSec=5,CSwingDetector* structureSwings=NULL,
             CExecutionLedgerClient* ledger=NULL,CRiskEngine* risk=NULL,double riskPercent=0.0);
   void OnTick(double currentAtr);
  };

void CPositionManager::Init(COrderManager* orders,CBrokerAdapter* broker,
                            double breakEvenAtR,double partialAtR,double partialFraction,double trailAtrMult,
                            int maxSpreadPoints,double minATR,double maxATR,int minModifyIntervalSec,
                            CSwingDetector* structureSwings,CExecutionLedgerClient* ledger,
                            CRiskEngine* risk,double riskPercent)
  {
   m_orders=orders;
   m_broker=broker;
   m_ledger=ledger;
   m_risk=risk;
   m_riskPercent=riskPercent;
   m_structureSwings=structureSwings;
   m_partialAtR=partialAtR;
   m_partialFraction=partialFraction;
   m_minModifyIntervalSec=MathMax(0,minModifyIntervalSec);
   ArrayResize(m_lastModifyTickets,0);
   ArrayResize(m_lastModifyTimes,0);
   m_audit.Init();

   DynamicStopConfig cfg;
   cfg.SetDefaults();
   cfg.activateAtR=InpDynamicStopActivateAtR;
   cfg.breakevenAtR=InpDynamicStopBreakevenAtR;
   cfg.atrMultiplier=InpDynamicStopATRMult;
   cfg.minImprovementPts=InpDynamicStopMinImprovementPoints;
   cfg.maxSpreadPoints=InpDynamicStopMaxSpreadPoints;
   cfg.minATR=InpDynamicStopMinATR;
   cfg.maxATR=InpDynamicStopMaxATR;
   cfg.useStructuralAnchor=InpDynamicStopUseStructuralAnchor;
   cfg.structuralBufferATR=InpDynamicStopStructuralBufferATR;
   m_minModifyIntervalSec=MathMax(0,InpDynamicStopModifyIntervalSec);
   m_dynamicStop.Configure(cfg);
  }

double CPositionManager::CurrentExitPrice(string symbol,bool isBuy)
  {
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return 0.0;
   return isBuy ? tick.bid : tick.ask;
  }

bool CPositionManager::PartialVolumeForPosition(string symbol,double currentVolume,double &closeVolume)
  {
   closeVolume=0.0;
   if(symbol=="" || !MathIsValidNumber(currentVolume) || currentVolume<=0.0 ||
      !MathIsValidNumber(m_partialFraction) || m_partialFraction<=0.0 || m_partialFraction>=1.0)
      return false;

   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(!MathIsValidNumber(step) || !MathIsValidNumber(minVolume) || step<=0.0 || minVolume<=0.0)
      return false;

   int volumeDigits=0;
   for(int d=0;d<=8;d++)
      if(MathAbs(step-NormalizeDouble(step,d))<1e-9) { volumeDigits=d; break; }

   // Round down to the broker's volume step and validate both sides of the
   // partial close. A legal close amount that leaves an illegal remainder
   // is not a legal partial close. Never silently turn it into a full close.
   closeVolume=NormalizeDouble(MathFloor((currentVolume*m_partialFraction+1e-10)/step)*step,volumeDigits);
   double remainingVolume=NormalizeDouble(currentVolume-closeVolume,volumeDigits);
   double tolerance=step*0.25;
   if(closeVolume<minVolume-tolerance || remainingVolume<minVolume-tolerance ||
      closeVolume>=currentVolume-tolerance)
     {
      closeVolume=0.0;
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
double CPositionManager::RMultiple(const TradeDecisionRecord &dec,double entry,double price)
  {
   bool isBuy=(dec.setup.type==ORDER_TYPE_BUY);
   double riskDist=MathAbs(entry-dec.setup.stop_loss);
   if(riskDist<=0.0) return 0.0;
   double moveInFavor=isBuy ? price-entry : entry-price;
   return moveInFavor/riskDist;
  }

bool CPositionManager::CanModifyNow(ulong ticket)
  {
   if(m_minModifyIntervalSec<=0) return true;
   for(int i=0;i<ArraySize(m_lastModifyTickets);i++)
      if(m_lastModifyTickets[i]==ticket)
         return (TimeCurrent()-m_lastModifyTimes[i])>=m_minModifyIntervalSec;
   return true;
  }

void CPositionManager::RecordModification(ulong ticket)
  {
   for(int i=0;i<ArraySize(m_lastModifyTickets);i++)
      if(m_lastModifyTickets[i]==ticket)
        { m_lastModifyTimes[i]=TimeCurrent(); return; }
   int n=ArraySize(m_lastModifyTickets);
   ArrayResize(m_lastModifyTickets,n+1);
   ArrayResize(m_lastModifyTimes,n+1);
   m_lastModifyTickets[n]=ticket;
   m_lastModifyTimes[n]=TimeCurrent();
  }

// Return the newest CONFIRMED swing on the opposite side of the position.
// CSwingDetector only exposes swings after its left/right strength window
// has completed, so this is market structure derived from the actual
// terminal candle feed rather than a synthetic price level.
// BUY  -> most recent confirmed swing low.
// SELL -> most recent confirmed swing high.
// The DynamicStopEngine remains the final geometry/safety gate.
double CPositionManager::ConfirmedStructuralAnchor(bool isBuy)
  {
   if(m_structureSwings==NULL) return 0.0;
   if(isBuy)
     {
      if(m_structureSwings.LowCount()<=0) return 0.0;
      SwingPoint low=m_structureSwings.GetLow(0);
      if(low.time<=0 || low.price<=0.0 || low.is_high) return 0.0;
      return low.price;
     }
   if(m_structureSwings.HighCount()<=0) return 0.0;
   SwingPoint high=m_structureSwings.GetHigh(0);
   if(high.time<=0 || high.price<=0.0 || !high.is_high) return 0.0;
   return high.price;
  }

void CPositionManager::OnTick(double currentAtr)
  {
   for(int i=0;i<m_orders.Total();i++)
     {
      ENUM_TRADE_STATE state=m_orders.StateAt(i);
      if(state!=TS_FILLED && state!=TS_PROTECTED && state!=TS_PARTIAL && state!=TS_RUNNER)
         continue;

      ulong ticket=m_orders.PositionTicketAt(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket))
        {
         m_orders.TransitionAt(i,TS_CLOSED);
         m_orders.TransitionAt(i,TS_ARCHIVED);
         continue;
        }

      TradeDecisionRecord dec=m_orders.DecisionAt(i);
      bool isBuy=(dec.setup.type==ORDER_TYPE_BUY);
      double entry=m_orders.FillPriceAt(i);
      double price=CurrentExitPrice(dec.symbol,isBuy);
      if(price<=0.0 || entry<=0.0) continue;
      double r=RMultiple(dec,entry,price);
      double curSL=PositionGetDouble(POSITION_SL);

      MqlTick tick;
      if(!SymbolInfoTick(dec.symbol,tick)) continue;
      double point=SymbolInfoDouble(dec.symbol,SYMBOL_POINT);
      double spreadPoints=(point>0.0 ? (tick.ask-tick.bid)/point : 0.0);

      if(InpEnableDynamicStop && CanModifyNow(ticket))
        {
         // Source the anchor from the already-running, confirmed swing
         // detector for the entry timeframe. If no confirmed swing exists,
         // the DynamicStopEngine receives zero and deterministically falls
         // back to its ATR policy; it never fabricates structure.
         double structuralAnchor=ConfirmedStructuralAnchor(isBuy);
         DynamicStopDecision ds=m_dynamicStop.Evaluate(dec.symbol,isBuy,entry,dec.setup.stop_loss,
                                                        curSL,price,currentAtr,spreadPoints,structuralAnchor);
         if(ds.modify)
           {
            ulong positionIdentifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
            double oldTP=PositionGetDouble(POSITION_TP);
            string direction=isBuy?"BUY":"SELL";
            string eventId=StringFormat("modify:%I64u:%.10f:%.10f:%.10f:%.10f",
                                        positionIdentifier,curSL,ds.proposedSL,oldTP,dec.setup.final_tp);
            string intentEvidence="mt5-stop-intent:"+eventId;
            bool ledgerIntentReady=(m_ledger!=NULL && m_ledger.Ready() && positionIdentifier>0 &&
               m_ledger.PreparePositionModification(eventId,positionIdentifier,dec.symbol,direction,
                                                      curSL,oldTP,ds.proposedSL,dec.setup.final_tp,
                                                      intentEvidence));
            if(!ledgerIntentReady && m_ledger!=NULL)
               m_ledger.RequireReconciliation();

            // Protective broker changes are still attempted when the ledger
            // is unavailable. The admission latch remains closed until a
            // broker snapshot resolves any durable PENDING intent.
            bool brokerModified=m_broker.ModifySLTP(ticket,ds.proposedSL,dec.setup.final_tp);
            if(brokerModified)
              {
               double appliedSL=0.0;
               double appliedTP=0.0;
               if(PositionSelectByTicket(ticket))
                 {
                  double observedSL=PositionGetDouble(POSITION_SL);
                  double observedTP=PositionGetDouble(POSITION_TP);
                  appliedSL=observedSL;
                  appliedTP=observedTP;
                 }
               if(appliedSL<=0.0)
                 {
                  if(m_ledger!=NULL) m_ledger.RequireReconciliation();
                  PrintFormat("Midas position modification accepted but broker snapshot unavailable; ticket=%I64u",ticket);
                  continue;
                 }

               bool ledgerConfirmed=false;
               if(ledgerIntentReady && m_risk!=NULL && m_riskPercent>0.0)
                 {
                  double remainingRisk=0.0;
                  bool stopLocked=(isBuy && appliedSL>=entry) || (!isBuy && appliedSL<=entry);
                  if(stopLocked)
                     remainingRisk=0.0;
                  else
                     remainingRisk=m_risk.RiskAmountForLots(dec.symbol,PositionGetDouble(POSITION_VOLUME),
                                                            entry,appliedSL);
                  double baseRiskUnit=AccountInfoDouble(ACCOUNT_EQUITY)*m_riskPercent/100.0;
                  double riskR=(stopLocked ? 0.0 :
                                (baseRiskUnit>0.0 && remainingRisk>0.0 ? remainingRisk/baseRiskUnit : -1.0));
                  string confirmEvidence="mt5-stop-observed:"+eventId;
                  if(riskR>=0.0 && MathIsValidNumber(riskR))
                     ledgerConfirmed=m_ledger.ConfirmPositionModification(eventId,appliedSL,appliedTP,
                                                                            riskR,MathMax(0.0,currentAtr),
                                                                            confirmEvidence);
                 }
               if(!ledgerConfirmed && m_ledger!=NULL)
                 {
                  m_ledger.RequireReconciliation();
                  PrintFormat("Midas position modification awaits ledger reconciliation; ticket=%I64u",ticket);
                 }

               m_audit.Record(ticket,dec.symbol,isBuy,EnumToString(ds.stage),curSL,appliedSL,price,r,ds.reason);
               RecordModification(ticket);
               if(state==TS_FILLED) m_orders.TransitionAt(i,TS_PROTECTED);
              }
            else
              {
               // The broker result may be ambiguous after a transport failure.
               // Keep the intent unresolved and block further new entries.
               if(ledgerIntentReady && m_ledger!=NULL)
                  m_ledger.RequireReconciliation();
               RecordModification(ticket);
              }
           }
        }

      ENUM_TRADE_STATE stateAfterStop=m_orders.StateAt(i);
      if(ShouldTakePartialAtR(stateAfterStop,r,m_partialAtR))
        {
         double currentVolume=PositionGetDouble(POSITION_VOLUME);
         double closeVolume=0.0;
         // Skip locally when broker volume constraints make a partial close
         // impossible. This avoids repeating a predictably invalid request
         // on every tick while trailing-stop management continues normally.
         if(PartialVolumeForPosition(dec.symbol,currentVolume,closeVolume) &&
            m_broker.ClosePartial(ticket,closeVolume))
            m_orders.TransitionAt(i,TS_PARTIAL);
        }
      if(m_orders.StateAt(i)==TS_PARTIAL)
         m_orders.TransitionAt(i,TS_RUNNER);
     }
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/PositionManager.mqh
// BEGIN INLINED MODULE: includes/Execution/TesterDealExport.mqh
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
  };

class CTesterDealExport
  {
private:
   bool   m_enabled;
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
   double m_tickValue;
   double m_initialBalance;
   string m_currency;
   string m_server;
   long   m_leverage;
   long   m_terminalBuild;
   long   m_fillMode;
   TesterDealExportRow m_rows[];
   ulong  m_seenDeals[];
   ulong  m_riskPositions[];
   double m_positionRiskCash[];

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

   string TimeIsoUtc(datetime value) const
     {
      // MT5 Strategy Tester time is simulated independently of any connected
      // broker server; Tester time is represented as GMT for reproducibility.
      // This exporter is test-only and remains inert outside MQL_TESTER.
      string stamp=TimeToString(value,TIME_DATE|TIME_SECONDS);
      StringReplace(stamp,".","-");
      StringReplace(stamp," ","T");
      return stamp+"Z";
     }

   void WriteMetadata()
     {
      string filename="MidasTesterMeta_"+m_runId+".json";
      int handle=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=metadata file=%s error=%d",
                     filename,GetLastError());
         return;
        }
      double cashPerPoint=0.0;
      if(m_point>0.0 && m_tickSize>0.0 && m_tickValue>0.0)
         cashPerPoint=m_tickValue*m_point/m_tickSize;
      double averageSpread=(m_spreadSamples>0 ? m_spreadSum/(double)m_spreadSamples : 0.0);
      string json=StringFormat(
         "{\"run_id\":\"%s\",\"symbol\":\"%s\",\"server\":\"%s\","
         "\"account_currency\":\"%s\",\"leverage\":%I64d,"
         "\"initial_balance\":%.8f,\"terminal_build\":%I64d,"
         "\"point\":%.10f,\"tick_size\":%.10f,\"tick_value\":%.8f,"
         "\"cash_per_point_per_lot\":%.8f,\"spread_points_mean\":%.8f,"
         "\"spread_points_max\":%.8f,\"spread_samples\":%I64u,"
         "\"fill_mode\":%I64d}",
         m_runId,m_symbol,m_server,m_currency,m_leverage,m_initialBalance,
         m_terminalBuild,m_point,m_tickSize,m_tickValue,cashPerPoint,
         averageSpread,m_spreadMax,m_spreadSamples,m_fillMode);
      FileWriteString(handle,json);
      FileFlush(handle);
      FileClose(handle);
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
      if(positionId==0 || !MathIsValidNumber(riskCash) || riskCash<=0.0) return;
      int index=RiskIndex(positionId);
      if(index<0)
        {
         index=ArraySize(m_riskPositions);
         ArrayResize(m_riskPositions,index+1);
         ArrayResize(m_positionRiskCash,index+1);
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
   void Init(const string runId,const string symbol,const ulong magic,const bool enabled)
     {
      m_enabled=(enabled && (bool)MQLInfoInteger(MQL_TESTER));
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
      m_tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      m_initialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_currency=AccountInfoString(ACCOUNT_CURRENCY);
      m_server=AccountInfoString(ACCOUNT_SERVER);
      m_leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);
      m_terminalBuild=TerminalInfoInteger(TERMINAL_BUILD);
      m_fillMode=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      ArrayResize(m_rows,0);
      ArrayResize(m_seenDeals,0);
      ArrayResize(m_riskPositions,0);
      ArrayResize(m_positionRiskCash,0);
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
               const double fee,const double entryRiskCash)
     {
      if(!m_enabled) return true;
      if(dealId==0 || orderId==0 || positionId==0 || symbol=="") return false;
      if(DealWasSeen(dealId)) return true;
      double values[]={volume,price,profit,commission,swap,fee,entryRiskCash};
      for(int i=0;i<ArraySize(values);i++)
         if(!MathIsValidNumber(values[i])) return false;
      if(volume<=0.0 || price<=0.0) return false;

      int seen=ArraySize(m_seenDeals);
      ArrayResize(m_seenDeals,seen+1);
      m_seenDeals[seen]=dealId;
      if(entry==DEAL_ENTRY_IN) AddEntryRisk(positionId,entryRiskCash);

      int count=ArraySize(m_rows);
      ArrayResize(m_rows,count+1);
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
      return true;
     }

   void Finalize()
     {
      if(!m_enabled) return;
      int handle=FileOpen(m_dealsName,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(handle==INVALID_HANDLE)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=deals file=%s error=%d",
                     m_dealsName,GetLastError());
         return;
        }
      FileWrite(handle,"position_id","time","entry","volume","profit","commission",
                "swap","fee","risk_cash","lane","deal_id","order_id","symbol");
      for(int i=0;i<ArraySize(m_rows);i++)
        {
         TesterDealExportRow row=m_rows[i];
         FileWrite(handle,
                   IntegerToString((long)row.position_id),
                   TimeIsoUtc(row.deal_time),
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
                   row.symbol);
        }
      FileFlush(handle);
      FileClose(handle);

      int openHandle=FileOpen(m_openName,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(openHandle==INVALID_HANDLE)
        {
         PrintFormat("MIDAS_TEST_EXPORT_ERROR kind=open_positions file=%s error=%d",
                     m_openName,GetLastError());
         return;
        }
      FileWrite(openHandle,"position_id");
      for(int p=PositionsTotal()-1;p>=0;p--)
        {
         ulong ticket=PositionGetTicket(p);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(positionId>0) FileWrite(openHandle,IntegerToString((long)positionId));
        }
      FileFlush(openHandle);
      FileClose(openHandle);
      WriteMetadata();
      PrintFormat("MIDAS_TEST_EXPORT_COMPLETE run=%s deals=%d risk_positions=%d deals_file=%s open_file=%s",
                  m_runId,ArraySize(m_rows),ArraySize(m_riskPositions),m_dealsName,m_openName);
     }
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/TesterDealExport.mqh
// BEGIN INLINED MODULE: includes/Recovery/RecoveryEngine.mqh
//+------------------------------------------------------------------+
//| Recovery/RecoveryEngine.mqh                                    |
//+------------------------------------------------------------------+
#ifndef RECOVERYENGINE_MQH
#define RECOVERYENGINE_MQH
// already inlined once under include guard: includes/Decision/DecisionStore.mqh
// already inlined once under include guard: includes/Execution/OrderManager.mqh
// already inlined once under include guard: includes/Execution/TradeStateMachine.mqh
// already inlined once under include guard: includes/Trading/OutcomeTrackerLive.mqh
class CRecoveryEngine
  {
private:
   CDecisionStore* m_store; COrderManager* m_orders; COutcomeTrackerLive* m_tracker; ulong m_magic; string m_symbol;
   bool ParseDecisionId(string comment,long &idOut);
   bool IsDecimalDigits(const string value);
   bool ParseTradeIdentity(string comment,long &idOut,int &legOut);
   ENUM_TRADE_STATE InferPositionState(double submittedVolume,double currentVolume,double entryPrice,double currentSL,bool isBuy);
public:
   void Init(CDecisionStore* store,COrderManager* orders,ulong magic,string symbol,COutcomeTrackerLive* tracker=NULL); int Recover();
  };
void CRecoveryEngine::Init(CDecisionStore* store,COrderManager* orders,ulong magic,string symbol,COutcomeTrackerLive* tracker){m_store=store;m_orders=orders;m_magic=magic;m_symbol=symbol;m_tracker=(tracker!=NULL?tracker:g_activeOutcomeTracker);}
bool CRecoveryEngine::IsDecimalDigits(const string value)
  {
   int length=StringLen(value);
   if(length<=0) return false;
   for(int i=0;i<length;i++)
     {
      ushort ch=StringGetCharacter(value,i);
      if(ch<'0' || ch>'9') return false;
     }
   return true;
  }
bool CRecoveryEngine::ParseTradeIdentity(string comment,long &idOut,int &legOut)
  {
   idOut=0;legOut=0;
   if(StringSubstr(comment,0,3)!="MT#") return false;

   string payload=StringSubstr(comment,3);
   int sep=StringFind(payload,":L");
   if(sep>=0)
     {
      string legPart=StringSubstr(payload,sep+2);
      payload=StringSubstr(payload,0,sep);
      if(!IsDecimalDigits(legPart)) return false;

      long parsedLeg=StringToInteger(legPart);
      // This comment format is generated by IntegerToString. Requiring a
      // canonical round-trip rejects overflow and non-canonical numeric text.
      if(parsedLeg<0 || parsedLeg>2147483647) return false;
      if(IntegerToString(parsedLeg)!=legPart) return false;
      legOut=(int)parsedLeg;
     }

   if(!IsDecimalDigits(payload)) return false;
   idOut=(long)StringToInteger(payload);
   if(idOut<=0 || IntegerToString(idOut)!=payload) return false;
   return true;
  }
bool CRecoveryEngine::ParseDecisionId(string comment,long &idOut)
  {
   int leg=0;
   return ParseTradeIdentity(comment,idOut,leg);
  }
ENUM_TRADE_STATE CRecoveryEngine::InferPositionState(double submittedVolume,double currentVolume,double entryPrice,double currentSL,bool isBuy){bool partialTaken=(submittedVolume>0&&currentVolume<submittedVolume-0.0000001);bool atOrPastBreakEven=isBuy?(currentSL>=entryPrice-0.0000001):(currentSL<=entryPrice+0.0000001);if(currentSL==0)atOrPastBreakEven=false;if(partialTaken)return TS_RUNNER;if(atOrPastBreakEven)return TS_PROTECTED;return TS_FILLED;}
int CRecoveryEngine::Recover()
  {
   int restored=0;
   ExecutionRecord execs[];
   int execCount=m_store.LoadAllExecutions(execs);

   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;

      long decisionId;
      int legIndex=0;
      if(!ParseTradeIdentity(PositionGetString(POSITION_COMMENT),decisionId,legIndex)) continue;

      TradeDecisionRecord dec;
      if(!m_store.FindById(decisionId,dec))
        {
         PrintFormat("MedisTouch Recovery: position #%I64u references decision #%I64d not found in store — skipping.",ticket,decisionId);
         continue;
        }

      double currentVolume=PositionGetDouble(POSITION_VOLUME);
      double submittedVolume=currentVolume;
      double restoredTarget=0.0;
      for(int e=0;e<execCount;e++)
        {
         if(execs[e].decision_id==decisionId && execs[e].leg_index==legIndex)
           {
            submittedVolume=execs[e].volume;
            restoredTarget=execs[e].target;
            break;
           }
        }

      TradeDecisionRecord restoredDecision=dec;
      if(restoredTarget>0.0)
         restoredDecision.setup.final_tp=restoredTarget;

      bool isBuy=restoredDecision.setup.type==ORDER_TYPE_BUY;
      double actualEntry=PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL=PositionGetDouble(POSITION_SL);
      ENUM_TRADE_STATE state=InferPositionState(submittedVolume,currentVolume,actualEntry,currentSL,isBuy);

      if(m_orders.RestoreTrade(restoredDecision,currentVolume,ticket,state,actualEntry,legIndex))
        {
         restored++;
         ulong positionIdentifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         m_orders.BindPositionIdentity(ticket,positionIdentifier,ticket);
         if(m_tracker!=NULL)
           {
            bool historyRebuilt=m_tracker.RebuildOpenDecisionFromHistory(restoredDecision.setup,decisionId,positionIdentifier,m_magic);
            if(!historyRebuilt)
              {
               // Do not synthesize missing partial closes or charges. Keep the
               // broker snapshot usable for protection, but mark its outcome
               // accounting incomplete so it cannot teach the calibration engine.
               m_tracker.RestoreExecuted(restoredDecision.setup,decisionId,actualEntry,(datetime)PositionGetInteger(POSITION_TIME),currentVolume);
               m_tracker.MarkHistoryIncomplete(decisionId);
               PrintFormat("MedisTouch Recovery: history ledger for decision #%I64d did not reconcile; outcome learning disabled until clean closure.",decisionId);
              }
           }
         PrintFormat("MedisTouch Recovery: restored decision #%I64d leg %d as ticket #%I64u in state %s at broker entry %.5f.",decisionId,legIndex,ticket,TradeStateToString(state),actualEntry);
        }
     }

   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0||!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=m_symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=m_magic) continue;

      long decisionId;
      int legIndex=0;
      if(!ParseTradeIdentity(OrderGetString(ORDER_COMMENT),decisionId,legIndex)) continue;

      TradeDecisionRecord dec;
      if(!m_store.FindById(decisionId,dec)) continue;

      double vol=OrderGetDouble(ORDER_VOLUME_CURRENT);
      double restoredTarget=0.0;
      for(int e=0;e<execCount;e++)
        {
         if(execs[e].decision_id==decisionId && execs[e].leg_index==legIndex)
           {
            restoredTarget=execs[e].target;
            break;
           }
        }

      TradeDecisionRecord restoredDecision=dec;
      if(restoredTarget>0.0)
         restoredDecision.setup.final_tp=restoredTarget;

      if(m_orders.RestoreTrade(restoredDecision,vol,ticket,TS_PENDING,0.0,legIndex))
        {
         restored++;
         PrintFormat("MedisTouch Recovery: restored decision #%I64d leg %d as pending order #%I64u.",decisionId,legIndex,ticket);
        }
     }

   return restored;
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Recovery/RecoveryEngine.mqh
// BEGIN INLINED MODULE: includes/Portfolio/PortfolioManager.mqh
//+------------------------------------------------------------------+
//|                                     Portfolio/PortfolioManager.mqh |
//+------------------------------------------------------------------+
#ifndef PORTFOLIOMANAGER_MQH
#define PORTFOLIOMANAGER_MQH
// already inlined once under include guard: includes/Trading/RiskEngine.mqh
class CPortfolioManager
  {
private:
   double m_maxPortfolioRiskPercent; int m_maxPositionsPerSymbol; int m_maxPositionsPerGroup; ulong m_magic; CRiskEngine* m_risk;
   string CorrelationGroup(string symbol); double OpenRiskAmount(ulong ticket); double PendingOrderRiskAmount(ulong ticket);
public:
   void Init(double maxPortfolioRiskPercent,int maxPositionsPerSymbol,int maxPositionsPerGroup,ulong magic,CRiskEngine* risk);
   bool AllowNewTrade(string symbol,double proposedRiskAmount,string &reasonOut);
   bool AllowNewTradeBatch(string symbol,double proposedRiskAmount,int proposedPositions,string &reasonOut);
  };
void CPortfolioManager::Init(double maxPortfolioRiskPercent,int maxPositionsPerSymbol,int maxPositionsPerGroup,ulong magic,CRiskEngine* risk)
  {
   m_maxPortfolioRiskPercent=MathMax(0.0,maxPortfolioRiskPercent); m_maxPositionsPerSymbol=MathMax(1,maxPositionsPerSymbol);
   m_maxPositionsPerGroup=MathMax(1,maxPositionsPerGroup); m_magic=magic; m_risk=risk;
  }
string CPortfolioManager::CorrelationGroup(string symbol)
  {
   if(StringFind(symbol,"BTC")>=0 || StringFind(symbol,"ETH")>=0 || StringFind(symbol,"XRP")>=0) return "CRYPTO";
   if(StringFind(symbol,"XAU")>=0 || StringFind(symbol,"XAG")>=0) return "METALS";
   if(StringFind(symbol,"US30")>=0 || StringFind(symbol,"NAS100")>=0 || StringFind(symbol,"SPX")>=0 || StringFind(symbol,"GER40")>=0 || StringFind(symbol,"UK100")>=0 || StringFind(symbol,"JPN225")>=0) return "INDICES";
   return "FX";
  }
double CPortfolioManager::OpenRiskAmount(ulong ticket)
  {
   if(m_risk==NULL || !PositionSelectByTicket(ticket)) return -1.0;

   string symbol=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double volume=PositionGetDouble(POSITION_VOLUME);

   // Missing protection is unknown risk, so the portfolio gate must fail closed.
   if(sl<=0.0 || entry<=0.0 || volume<=0.0) return -1.0;

   // Use the remaining adverse distance to the actual stop. A stop at or
   // beyond entry locks out price-based loss at the stop, so its planned
   // stop risk is zero rather than "unknown". Gaps, slippage and broker
   // execution can still make a realized loss exceed this stop-based estimate.
   if(type==POSITION_TYPE_BUY && sl>=entry) return 0.0;
   if(type==POSITION_TYPE_SELL && sl<=entry) return 0.0;

   // Any nonstandard/invalid position geometry is not safe to estimate.
   if(type!=POSITION_TYPE_BUY && type!=POSITION_TYPE_SELL) return -1.0;

   double risk=m_risk.RiskAmountForLots(symbol,volume,entry,sl);
   return risk>0.0 ? risk : -1.0; // Invalid tick metadata remains unknown, not zero risk.
  }
double CPortfolioManager::PendingOrderRiskAmount(ulong ticket)
  {
   if(m_risk==NULL || ticket==0 || !OrderSelect(ticket)) return -1.0;

   string symbol=OrderGetString(ORDER_SYMBOL);
   ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   double entry=OrderGetDouble(ORDER_PRICE_OPEN);
   double sl=OrderGetDouble(ORDER_SL);
   double volume=OrderGetDouble(ORDER_VOLUME_CURRENT);

   // An active order without a protective stop is unknown exposure. Unlike
   // an already-open position, a pending order with a stop on the wrong side
   // must not be interpreted as zero risk: the pending order has not yet
   // earned any locked-in protection.
   if(symbol=="" || entry<=0.0 || sl<=0.0 || volume<=0.0) return -1.0;

   bool isBuy=(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT ||
               type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
   bool isSell=(type==ORDER_TYPE_SELL || type==ORDER_TYPE_SELL_LIMIT ||
                type==ORDER_TYPE_SELL_STOP || type==ORDER_TYPE_SELL_STOP_LIMIT);
   if(!isBuy && !isSell) return -1.0;
   if(isBuy && sl>=entry) return -1.0;
   if(isSell && sl<=entry) return -1.0;

   double risk=m_risk.RiskAmountForLots(symbol,volume,entry,sl);
   return risk>0.0 ? risk : -1.0;
  }

bool CPortfolioManager::AllowNewTradeBatch(string symbol,double proposedRiskAmount,int proposedPositions,string &reasonOut)
  {
   reasonOut="";
   if(m_risk==NULL){reasonOut="portfolio risk engine unavailable";return false;}
   if(proposedRiskAmount<=0.0){reasonOut="proposed trade risk is non-positive or cannot be calculated";return false;}
   if(proposedPositions<=0){reasonOut="proposed position count is invalid";return false;}
   if(m_maxPortfolioRiskPercent<=0.0){reasonOut="portfolio risk cap is zero; refusing new exposure";return false;}

   string group=CorrelationGroup(symbol);
   double totalRisk=proposedRiskAmount;
   int symbolCount=0;
   int groupCount=0;
   bool unknown=false;

   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
      string posSymbol=PositionGetString(POSITION_SYMBOL);
      if(posSymbol==symbol) symbolCount++;
      if(CorrelationGroup(posSymbol)==group) groupCount++;
      double risk=OpenRiskAmount(ticket);
      if(risk<0.0) unknown=true;
      else totalRisk+=risk;
     }

   // Include live pending orders as contingent exposure. Otherwise an
   // EA instance could reserve a portfolio budget with a pending limit
   // order and another instance could spend the same budget before fill.
   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i); // Selects this active order.
      if(ticket==0) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=m_magic) continue;
      string orderSymbol=OrderGetString(ORDER_SYMBOL);
      if(orderSymbol==symbol) symbolCount++;
      if(CorrelationGroup(orderSymbol)==group) groupCount++;
      double risk=PendingOrderRiskAmount(ticket);
      if(risk<0.0) unknown=true;
      else totalRisk+=risk;
     }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0){reasonOut="account equity unavailable/non-positive";return false;}

   double maxRiskAmount=equity*(m_maxPortfolioRiskPercent/100.0);
   if(symbolCount+proposedPositions>m_maxPositionsPerSymbol)
     {
      reasonOut=StringFormat("%s would have %d position(s), above the per-symbol limit %d",
                             symbol,symbolCount+proposedPositions,m_maxPositionsPerSymbol);
      return false;
     }
   if(groupCount+proposedPositions>m_maxPositionsPerGroup)
     {
      reasonOut=StringFormat("correlation group %s would have %d position(s), above the group limit %d",
                             group,groupCount+proposedPositions,m_maxPositionsPerGroup);
      return false;
     }
   if(unknown)
     {
      reasonOut="an existing position or pending order under this magic number has uncomputable risk — refusing new exposure until its stop/risk can be verified";
      return false;
     }
   if(totalRisk>maxRiskAmount)
     {
      reasonOut=StringFormat("adding this trade batch would bring total open risk to %.2f, above the %.2f%% portfolio cap (%.2f)",
                             totalRisk,m_maxPortfolioRiskPercent,maxRiskAmount);
      return false;
     }
   return true;
  }

bool CPortfolioManager::AllowNewTrade(string symbol,double proposedRiskAmount,string &reasonOut)
  {
   return AllowNewTradeBatch(symbol,proposedRiskAmount,1,reasonOut);
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Portfolio/PortfolioManager.mqh
// BEGIN INLINED MODULE: includes/Portfolio/RiskGuard.mqh
//+------------------------------------------------------------------+
//|                                        Portfolio/RiskGuard.mqh    |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_MQH
#define RISKGUARD_MQH

// Account-level circuit breaker. The daily baseline, peak-equity halt state
// are account-wide (not chart/symbol-wide) and persisted in terminal
// GlobalVariables so restarting one EA instance cannot silently reset the
// account's risk limits or create a second independent risk budget.
class CRiskGuard
  {
private:
   double   m_maxDailyLossPercent;
   double   m_maxDrawdownPercent;
   double   m_deriskStartPercent;
   double   m_deriskFloor;
   bool     m_useProgressiveDailyDerisk;

   double   m_dayStartEquity;
   int      m_dayStartDayOfYear;
   int      m_dayStartYear;

   double   m_peakEquity;
   bool     m_hardHalted;
   string   m_lastReportedRiskState;

   string   m_symbol; // retained for diagnostics only; state keys are account-wide
   string   m_gvPeakKey;
   string   m_gvHaltedKey;
   string   m_gvDayStartEquityKey;
   string   m_gvDayKey;

   void     RolloverIfNewDay();
   void     PersistDayBaseline();

public:
   void     Init(string symbol, double maxDailyLossPercent, double maxDrawdownPercent,
                  double deriskStartPercent, double deriskFloor,
                  bool useProgressiveDailyDerisk = false);
   void     OnTick();

   bool     IsDailyLossLimitHit(string &reasonOut);
   bool     IsHardHalted(string &reasonOut);
   double   SizeMultiplier();
   double   CurrentDrawdownPercent();
   double   CurrentDailyLossPercent();
   string   RiskStateName();

   void     ManualReset();
  };
//+------------------------------------------------------------------+
void CRiskGuard::PersistDayBaseline()
  {
   GlobalVariableSet(m_gvDayStartEquityKey, m_dayStartEquity);
   GlobalVariableSet(m_gvDayKey, (double)m_dayStartYear * 1000.0 + m_dayStartDayOfYear);
  }
//+------------------------------------------------------------------+
void CRiskGuard::Init(string symbol, double maxDailyLossPercent, double maxDrawdownPercent,
                       double deriskStartPercent, double deriskFloor,
                       bool useProgressiveDailyDerisk)
  {
   m_symbol = symbol;
   m_lastReportedRiskState = "";
   m_useProgressiveDailyDerisk = useProgressiveDailyDerisk;
   m_maxDailyLossPercent = MathMax(0.0, maxDailyLossPercent);
   m_maxDrawdownPercent = MathMax(0.0, maxDrawdownPercent);
   m_deriskStartPercent = MathMax(0.0, deriskStartPercent);
   m_deriskFloor = MathMax(0.05, MathMin(1.0, deriskFloor));

   string prefix = "MedisTouch_RiskGuard_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
   m_gvPeakKey = prefix + "_PeakEquity";
   m_gvHaltedKey = prefix + "_HardHalted";
   m_gvDayStartEquityKey = prefix + "_DayStartEquity";
   m_gvDayKey = prefix + "_DayKey";

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(m_gvPeakKey))
      m_peakEquity = MathMax(GlobalVariableGet(m_gvPeakKey), equity);
   else
      m_peakEquity = equity;
   GlobalVariableSet(m_gvPeakKey, m_peakEquity);

   m_hardHalted = GlobalVariableCheck(m_gvHaltedKey) && (GlobalVariableGet(m_gvHaltedKey) > 0.5);

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   m_dayStartYear = t.year;
   m_dayStartDayOfYear = t.day_of_year;

   double persistedDay = 0.0;
   if(GlobalVariableCheck(m_gvDayKey))
      persistedDay = GlobalVariableGet(m_gvDayKey);
   double currentDayKey = (double)t.year * 1000.0 + t.day_of_year;

   if(GlobalVariableCheck(m_gvDayStartEquityKey) && MathAbs(persistedDay - currentDayKey) < 0.1)
      m_dayStartEquity = GlobalVariableGet(m_gvDayStartEquityKey);
   else
     {
      m_dayStartEquity = equity;
      PersistDayBaseline();
     }
  }
//+------------------------------------------------------------------+
void CRiskGuard::RolloverIfNewDay()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.year != m_dayStartYear || t.day_of_year != m_dayStartDayOfYear)
     {
      m_dayStartYear = t.year;
      m_dayStartDayOfYear = t.day_of_year;
      m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      PersistDayBaseline();
      PrintFormat("MedisTouch RiskGuard: new trading day, account-wide daily loss cap reset (start equity %.2f)", m_dayStartEquity);
     }
  }
//+------------------------------------------------------------------+
void CRiskGuard::OnTick()
  {
   RolloverIfNewDay();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > m_peakEquity)
     {
      m_peakEquity = equity;
      GlobalVariableSet(m_gvPeakKey, m_peakEquity);
     }

   if(!m_hardHalted && m_maxDrawdownPercent > 0 && CurrentDrawdownPercent() >= m_maxDrawdownPercent)
     {
      m_hardHalted = true;
      GlobalVariableSet(m_gvHaltedKey, 1.0);
      PrintFormat("MedisTouch RiskGuard: HARD HALT — account drawdown %.2f%% reached %.2f%% cap. No new trades until ManualReset().",
                  CurrentDrawdownPercent(), m_maxDrawdownPercent);
     }
   string state=RiskStateName();
   if(state!=m_lastReportedRiskState)
     {
      PrintFormat("Midas drawdown-risk state=%s peak-DD=%.2f%% daily-loss=%.2f%% size-multiplier=%.3f",
                  state,CurrentDrawdownPercent(),CurrentDailyLossPercent(),SizeMultiplier());
      m_lastReportedRiskState=state;
     }
  }
//+------------------------------------------------------------------+
double CRiskGuard::CurrentDrawdownPercent()
  {
   if(m_peakEquity <= 0) return 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMax(0.0, (m_peakEquity - equity) / m_peakEquity * 100.0);
  }
//+------------------------------------------------------------------+
double CRiskGuard::CurrentDailyLossPercent()
  {
   if(m_dayStartEquity<=0.0) return 0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMax(0.0,(m_dayStartEquity-equity)/m_dayStartEquity*100.0);
  }
//+------------------------------------------------------------------+
bool CRiskGuard::IsDailyLossLimitHit(string &reasonOut)
  {
   reasonOut = "";
   if(m_maxDailyLossPercent <= 0 || m_dayStartEquity <= 0) return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercent = MathMax(0.0, (m_dayStartEquity - equity) / m_dayStartEquity * 100.0);
   if(lossPercent >= m_maxDailyLossPercent)
     {
      reasonOut = StringFormat("daily loss cap hit: account down %.2f%% from today's persisted start equity %.2f (cap %.2f%%)",
                                lossPercent, m_dayStartEquity, m_maxDailyLossPercent);
      return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
bool CRiskGuard::IsHardHalted(string &reasonOut)
  {
   reasonOut = "";
   if(!m_hardHalted) return false;
   reasonOut = StringFormat("account-wide hard drawdown halt active — %.2f%% below peak equity %.2f (cap %.2f%%). Call ManualReset() after review.",
                             CurrentDrawdownPercent(), m_peakEquity, m_maxDrawdownPercent);
   return true;
  }
//+------------------------------------------------------------------+
double CRiskGuard::SizeMultiplier()
  {
   double multiplier=1.0;
   double dd=CurrentDrawdownPercent();
   if(m_maxDrawdownPercent>m_deriskStartPercent && m_maxDrawdownPercent>0.0 && dd>m_deriskStartPercent)
     {
      if(dd>=m_maxDrawdownPercent)
         multiplier=m_deriskFloor;
      else
        {
         double span=m_maxDrawdownPercent-m_deriskStartPercent;
         double progress=(dd-m_deriskStartPercent)/span;
         multiplier=1.0-progress*(1.0-m_deriskFloor);
        }
     }

   // Daily loss de-risking is separate from the peak-to-equity drawdown ramp.
   // It only reduces exposure; it can never increase risk or trigger recovery sizing.
   if(m_useProgressiveDailyDerisk && m_maxDailyLossPercent>0.0)
     {
      double dailyLoss=CurrentDailyLossPercent();
      if(dailyLoss>=m_maxDailyLossPercent) return 0.0;
      double dailyRatio=dailyLoss/m_maxDailyLossPercent;
      if(dailyRatio>=0.75) multiplier=MathMin(multiplier,0.25);
      else if(dailyRatio>=0.50) multiplier=MathMin(multiplier,0.50);
      else if(dailyRatio>=0.25) multiplier=MathMin(multiplier,0.75);
     }
   return MathMax(0.0,MathMin(1.0,multiplier));
  }
//+------------------------------------------------------------------+
string CRiskGuard::RiskStateName()
  {
   double dd=CurrentDrawdownPercent();
   double daily=CurrentDailyLossPercent();
   if(m_hardHalted || (m_maxDrawdownPercent>0.0 && dd>=m_maxDrawdownPercent) ||
      (m_maxDailyLossPercent>0.0 && daily>=m_maxDailyLossPercent)) return "HALTED";
   double ddSpan=MathMax(0.0,m_maxDrawdownPercent-m_deriskStartPercent);
   if(((m_useProgressiveDailyDerisk && m_maxDailyLossPercent>0.0 && daily>=0.75*m_maxDailyLossPercent)) ||
      (ddSpan>0.0 && dd>=m_deriskStartPercent+0.75*ddSpan)) return "CRITICAL";
   if(((m_useProgressiveDailyDerisk && m_maxDailyLossPercent>0.0 && daily>=0.50*m_maxDailyLossPercent)) ||
      (ddSpan>0.0 && dd>=m_deriskStartPercent+0.50*ddSpan)) return "DEFENSIVE";
   if(((m_useProgressiveDailyDerisk && m_maxDailyLossPercent>0.0 && daily>=0.25*m_maxDailyLossPercent)) ||
      (m_deriskStartPercent>0.0 && dd>=m_deriskStartPercent)) return "CAUTION";
   return "NORMAL";
  }
//+------------------------------------------------------------------+
void CRiskGuard::ManualReset()
  {
   m_hardHalted = false;
   GlobalVariableSet(m_gvHaltedKey, 0.0);
   Print("MedisTouch RiskGuard: account-wide hard halt manually cleared by operator.");
  }
//+------------------------------------------------------------------+
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Portfolio/RiskGuard.mqh
// already inlined once under include guard: includes/Portfolio/AccountRiskProfilePolicy.mqh
// BEGIN INLINED MODULE: includes/Portfolio/OpposingPositionPolicy.mqh
//+------------------------------------------------------------------+
//| Portfolio/OpposingPositionPolicy.mqh                              |
//| Pure, fail-closed policy for independent long/short exposure.     |
//+------------------------------------------------------------------+
#ifndef OPPOSINGPOSITIONPOLICY_MQH
#define OPPOSINGPOSITIONPOLICY_MQH

// Returns true only when the position/order direction is opposite to the
// requested market direction. Unknown order types are not inferred as a side;
// the caller's account-mode guard remains responsible for unsupported exposure.
bool MidasIsOpposingPositionDirection(ENUM_ORDER_TYPE desiredType,
                                     ENUM_POSITION_TYPE existingType)
  {
   if(desiredType!=ORDER_TYPE_BUY && desiredType!=ORDER_TYPE_SELL)
      return false;

   if(existingType==POSITION_TYPE_BUY)
      return desiredType==ORDER_TYPE_SELL;
   if(existingType==POSITION_TYPE_SELL)
      return desiredType==ORDER_TYPE_BUY;
   return false;
  }

bool MidasIsOpposingOrderDirection(ENUM_ORDER_TYPE desiredType,
                                   ENUM_ORDER_TYPE existingType)
  {
   if(desiredType!=ORDER_TYPE_BUY && desiredType!=ORDER_TYPE_SELL)
      return false;

   bool existingBuy=(existingType==ORDER_TYPE_BUY ||
                     existingType==ORDER_TYPE_BUY_LIMIT ||
                     existingType==ORDER_TYPE_BUY_STOP ||
                     existingType==ORDER_TYPE_BUY_STOP_LIMIT);
   bool existingSell=(existingType==ORDER_TYPE_SELL ||
                      existingType==ORDER_TYPE_SELL_LIMIT ||
                      existingType==ORDER_TYPE_SELL_STOP ||
                      existingType==ORDER_TYPE_SELL_STOP_LIMIT);

   if(!existingBuy && !existingSell)
      return false;
   return (desiredType==ORDER_TYPE_BUY ? existingSell : existingBuy);
  }

// This tests permission policy only. The production caller must still apply
// account-wide, per-symbol, correlation-group, daily-loss and execution guards.
// A netting/exchange account cannot retain independent opposing same-symbol
// positions, even when an operator attempts to enable the input.
bool MidasConcurrentOpposingPolicyAllows(ENUM_ACCOUNT_MARGIN_MODE accountMode,
                                         bool hasOpposingExposure,
                                         bool explicitlyEnabled,
                                         string &reasonOut)
  {
   reasonOut="";
   if(!hasOpposingExposure)
      return true;

   if(accountMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      reasonOut="MT5 netting/exchange accounts cannot retain independent opposing positions on the same symbol";
      return false;
     }

   if(!explicitlyEnabled)
     {
      reasonOut="opposing same-symbol exposure exists; InpAllowConcurrentOpposingPositions must be explicitly enabled";
      return false;
     }

   return true;
  }

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Portfolio/OpposingPositionPolicy.mqh
// already inlined once under include guard: includes/Core/NewsFilter.mqh
// already inlined once under include guard: includes/Signals/SubscriberPlatform.mqh
// already inlined once under include guard: includes/Signals/SignalPublisher.mqh
// BEGIN INLINED MODULE: includes/Signals/ConfigSync.mqh
//+------------------------------------------------------------------+
//| ConfigSync.mqh                                                   |
//| Fail-closed EA transport for immutable configuration envelopes.   |
//+------------------------------------------------------------------+
#ifndef CONFIGSYNC_MQH
#define CONFIGSYNC_MQH

// BEGIN INLINED MODULE: includes/Signals/ConfigSyncContract.mqh
//+------------------------------------------------------------------+
//| ConfigSyncContract.mqh                                           |
//| EA-side protocol boundary for immutable configuration delivery.   |
//| This class validates metadata and ACK state only. It deliberately  |
//| does not mutate any trading inputs or strategy objects.           |
//+------------------------------------------------------------------+
#ifndef CONFIGSYNC_CONTRACT_MQH
#define CONFIGSYNC_CONTRACT_MQH

#define CONFIG_SYNC_PROTOCOL_VERSION 1

class CConfigSyncContract
  {
private:
   string m_configHash;
   string m_strategy;
   string m_instrument;
   string m_timeframe;
   string m_dataVersion;
   string m_optimizerVersion;
   string m_lifecycle;
   int    m_version;

public:
   CConfigSyncContract(void)
     {
      Reset();
     }

   void Reset(void)
     {
      m_configHash = "";
      m_strategy = "";
      m_instrument = "";
      m_timeframe = "";
      m_dataVersion = "";
      m_optimizerVersion = "";
      m_lifecycle = "";
      m_version = 0;
     }

   void SetEnvelope(const string configHash,
                    const string strategy,
                    const string instrument,
                    const string timeframe,
                    const string dataVersion,
                    const string optimizerVersion,
                    const string lifecycle,
                    const int version)
     {
      m_configHash = configHash;
      m_strategy = strategy;
      m_instrument = instrument;
      m_timeframe = timeframe;
      m_dataVersion = dataVersion;
      m_optimizerVersion = optimizerVersion;
      m_lifecycle = lifecycle;
      m_version = version;
     }

   bool ValidateMetadata(const string expectedInstrument,
                         const string expectedTimeframe,
                         const string expectedStrategy,
                         string &reason) const
     {
      reason = "";
      if(m_version != CONFIG_SYNC_PROTOCOL_VERSION)
        {
         reason = "unsupported configuration protocol version";
         return false;
        }
      if(m_configHash == "")
        {
         reason = "configuration hash is missing";
         return false;
        }
      if(m_strategy != expectedStrategy)
        {
         reason = "strategy mismatch";
         return false;
        }
      if(m_instrument != expectedInstrument)
        {
         reason = "instrument mismatch";
         return false;
        }
      if(m_timeframe != expectedTimeframe)
        {
         reason = "timeframe mismatch";
         return false;
        }
      if(m_dataVersion == "")
        {
         reason = "data version is missing";
         return false;
        }
      if(m_optimizerVersion == "")
        {
         reason = "optimizer version is missing";
         return false;
        }
      // Evaluation states are not activation states. Only the bridge's
      // CHAMPION envelope may cross the exact-ACK activation boundary.
      if(m_lifecycle != "CHAMPION")
        {
         reason = "configuration lifecycle is not CHAMPION";
         return false;
        }
      return true;
     }

   bool CanActivate(const string acknowledgedHash,
                    const string expectedHash,
                    const bool metadataValid,
                    string &reason) const
     {
      reason = "";
      if(!metadataValid)
        {
         reason = "configuration metadata validation failed";
         return false;
        }
      if(m_configHash == "" || expectedHash == "")
        {
         reason = "configuration hash is missing";
         return false;
        }
      if(m_configHash != expectedHash)
        {
         reason = "configuration hash does not match expected identity";
         return false;
        }
      if(acknowledgedHash == "")
        {
         reason = "EA acknowledgement is missing";
         return false;
        }
      if(acknowledgedHash != expectedHash)
        {
         reason = "EA acknowledgement hash mismatch";
         return false;
        }
      return true;
     }

   string ConfigHash(void) const { return m_configHash; }
   string Lifecycle(void) const { return m_lifecycle; }
   int    Version(void) const { return m_version; }
  };

#endif // CONFIGSYNC_CONTRACT_MQH
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Signals/ConfigSyncContract.mqh

class CConfigSync
  {
private:
   string m_symbol;
   string m_endpoint;
   string m_apiKey;
   string m_compiledWeightVersion;
   int    m_timeoutMs;
   string m_lastSeenHash;
   string m_lastAckedHash;
   bool   m_everWarned;
   CConfigSyncContract m_contract;

   bool ExtractJsonStringField(const string &json,const string field,string &out);
   bool ExtractJsonIntField(const string &json,const string field,int &out);
   bool PostAcknowledgement(const string configHash,const string strategy,
                            const string timeframe,const int version);

public:
   CConfigSync(void) : m_timeoutMs(5000),m_lastSeenHash(""),m_lastAckedHash(""),m_everWarned(false) {}

   void Init(const string symbol,const string signalEndpoint,const string apiKey,
             const string compiledWeightVersion,const int timeoutMs=5000)
     {
      m_symbol=symbol;
      m_apiKey=apiKey;
      m_compiledWeightVersion=compiledWeightVersion;
      m_timeoutMs=MathMax(1000,timeoutMs);

      string suffix="/signal";
      if(StringLen(signalEndpoint)<StringLen(suffix) ||
         StringSubstr(signalEndpoint,StringLen(signalEndpoint)-StringLen(suffix))!=suffix)
        {
         PrintFormat("MedisTouch ConfigSync: endpoint %s must end in /signal — disabled.",signalEndpoint);
         m_endpoint="";
         return;
        }
      m_endpoint=StringSubstr(signalEndpoint,0,StringLen(signalEndpoint)-StringLen(suffix)) + "/config/" + symbol;
     }

   void Poll(void);
  };
//+------------------------------------------------------------------+
void CConfigSync::Poll(void)
  {
   if(StringLen(m_endpoint)==0) return;

   char data[]; char result[]; string resultHeaders;
   string headers="Content-Type: application/json\r\n";
   if(StringLen(m_apiKey)>0) headers+="X-API-Key: "+m_apiKey+"\r\n";

   ResetLastError();
   int status=WebRequest("GET",m_endpoint,headers,m_timeoutMs,data,result,resultHeaders);
   if(status==-1)
     {
      int err=GetLastError();
      if(err==4060) PrintFormat("MedisTouch ConfigSync: WebRequest blocked for %s — add the URL to MT5 allowed WebRequest URLs.",m_endpoint);
      return;
     }
   if(status<200 || status>=300) return;

   string body=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8);
   string configHash,strategy,instrument,timeframe,dataVersion,optimizerVersion,lifecycle;
   int version=0;
   if(!ExtractJsonStringField(body,"config_hash",configHash) ||
      !ExtractJsonStringField(body,"strategy",strategy) ||
      !ExtractJsonStringField(body,"instrument",instrument) ||
      !ExtractJsonStringField(body,"timeframe",timeframe) ||
      !ExtractJsonStringField(body,"data_version",dataVersion) ||
      !ExtractJsonStringField(body,"optimizer_version",optimizerVersion) ||
      !ExtractJsonStringField(body,"lifecycle_status",lifecycle) ||
      !ExtractJsonIntField(body,"version",version)) return;

   m_contract.SetEnvelope(configHash,strategy,instrument,timeframe,dataVersion,optimizerVersion,lifecycle,version);
   string reason;
   if(!m_contract.ValidateMetadata(m_symbol,EnumToString(_Period),"SMC",reason))
     {
      if(!m_everWarned || m_lastSeenHash!=configHash)
        {
         PrintFormat("MedisTouch ConfigSync: configuration %s rejected — %s",configHash,reason);
         m_everWarned=true;
        }
      m_lastSeenHash=configHash;
      return;
     }

   // A valid envelope is not considered synchronized until its ACK has
   // actually succeeded. The old implementation updated m_lastSeenHash
   // even when POST /ack failed, which caused the next poll to return early
   // forever and left the server waiting for an ACK that would never arrive.
   if(m_lastAckedHash==configHash) { m_lastSeenHash=configHash; m_everWarned=false; return; }

   if(PostAcknowledgement(configHash,strategy,timeframe,version))
     {
      m_lastAckedHash=configHash;
      m_lastSeenHash=configHash;
      m_everWarned=false;
      PrintFormat("MedisTouch ConfigSync: validated and acknowledged config %s; live numeric inputs remain unchanged.",configHash);
     }
   else
     {
      m_lastSeenHash=configHash;
      m_everWarned=true;
      PrintFormat("MedisTouch ConfigSync: ACK failed for config %s; will retry on the next poll.",configHash);
     }
  }
//+------------------------------------------------------------------+
bool CConfigSync::PostAcknowledgement(const string configHash,const string strategy,
                                       const string timeframe,const int version)
  {
   string body=StringFormat("{\"config_hash\":\"%s\",\"strategy\":\"%s\",\"timeframe\":\"%s\",\"version\":%d}",
                            configHash,strategy,timeframe,version);
   char postData[];
   int copied=StringToCharArray(body,postData,0,WHOLE_ARRAY,CP_UTF8);
   if(copied>0) ArrayResize(postData,copied-1);
   char result[]; string resultHeaders;
   string headers="Content-Type: application/json\r\n";
   if(StringLen(m_apiKey)>0) headers+="X-API-Key: "+m_apiKey+"\r\n";
   ResetLastError();
   int status=WebRequest("POST",m_endpoint+"/ack",headers,m_timeoutMs,postData,result,resultHeaders);
   if(status==-1) return false;
   return status>=200 && status<300;
  }
//+------------------------------------------------------------------+
bool CConfigSync::ExtractJsonStringField(const string &json,const string field,string &out)
  {
   string needle="\""+field+"\":";
   int pos=StringFind(json,needle);
   if(pos<0) return false;
   int valueStart=pos+StringLen(needle);
   if(StringSubstr(json,valueStart,4)=="null") { out=""; return true; }
   if(StringGetCharacter(json,valueStart)!='"') return false;
   valueStart++;
   int valueEnd=StringFind(json,"\"",valueStart);
   if(valueEnd<0) return false;
   out=StringSubstr(json,valueStart,valueEnd-valueStart);
   return true;
  }
//+------------------------------------------------------------------+
bool CConfigSync::ExtractJsonIntField(const string &json,const string field,int &out)
  {
   string needle="\""+field+"\":";
   int pos=StringFind(json,needle);
   if(pos<0) return false;
   int start=pos+StringLen(needle);
   string digits="";
   for(int i=start;i<StringLen(json);i++)
     {
      ushort ch=StringGetCharacter(json,i);
      if(ch<'0' || ch>'9') break;
      digits+=StringSubstr(json,i,1);
     }
   if(StringLen(digits)==0) return false;
   out=(int)StringToInteger(digits);
   return true;
  }
#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Signals/ConfigSync.mqh
// already inlined once under include guard: includes/Monitoring/ProductionMonitor.mqh
// BEGIN INLINED MODULE: includes/Execution/ExecutionAudit.mqh
//+------------------------------------------------------------------+
//| Execution/ExecutionAudit.mqh                                    |
//| Append-only terminal execution audit trail.                     |
//+------------------------------------------------------------------+
#ifndef MIDAS_EXECUTIONAUDIT_MQH
#define MIDAS_EXECUTIONAUDIT_MQH

class CExecutionAudit
  {
private:
   string m_symbol;
   string m_filename;
   ulong  m_magic;

public:
   void Init(const string symbol,ulong magic)
     {
      m_symbol=symbol;
      m_magic=magic;
      string safe=symbol;
      StringReplace(safe,"/","_");
      StringReplace(safe,"\\","_");
      m_filename="MidasTouch_ExecutionAudit_"+safe+".csv";
     }

   void Log(const string eventName,const string detail,long decisionId=0,ulong ticket=0,
            double volume=0.0,double price=0.0,double sl=0.0,double tp=0.0)
     {
      ResetLastError();
      int handle=FileOpen(m_filename,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(handle!=INVALID_HANDLE)
        {
         if(FileSize(handle)==0)
            FileWrite(handle,"time","symbol","magic","event","decision_id","ticket","volume","price","sl","tp","detail");
         FileSeek(handle,0,SEEK_END);
         FileWrite(handle,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),m_symbol,
                   (long)m_magic,eventName,decisionId,(long)ticket,
                   DoubleToString(volume,2),DoubleToString(price,_Digits),
                   DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),detail);
         FileFlush(handle);
         FileClose(handle);
        }
      PrintFormat("MidasTouch AUDIT | %s | %s | %s | magic=%I64u | id=%I64d | ticket=%I64u | %s",
                  TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),m_symbol,eventName,
                  m_magic,decisionId,ticket,detail);
     }
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/Execution/ExecutionAudit.mqh
// already inlined once under include guard: includes/Execution/ExecutionLedgerClient.mqh
// BEGIN INLINED MODULE: includes/UI/TradeControlPanel.mqh
//+------------------------------------------------------------------+
//| UI/TradeControlPanel.mqh                                         |
//| On-chart operator controls and append-only execution audit trail. |
//+------------------------------------------------------------------+
#ifndef MIDAS_TRADECONTROLPANEL_MQH
#define MIDAS_TRADECONTROLPANEL_MQH

enum ENUM_PANEL_ACTION
  {
   PANEL_ACTION_NONE=0,
   PANEL_ACTION_BUY,
   PANEL_ACTION_SELL,
   PANEL_ACTION_CLOSE_ALL,
   PANEL_ACTION_EMERGENCY_STOP,
   PANEL_ACTION_RESUME
  };

class CTradeControlPanel
  {
private:
   long   m_chart;
   string m_prefix;
   string m_symbol;
   ulong  m_magic;
   int    m_x;
   int    m_y;

   bool CreateLabel(const string suffix,const string caption,int x,int y,int fontSize,color textColor)
     {
      string name=m_prefix+suffix;
      if(ObjectFind(m_chart,name)<0 && !ObjectCreate(m_chart,name,OBJ_LABEL,0,0,0))
         return false;
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,fontSize);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,textColor);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(m_chart,name,OBJPROP_FONT,"Consolas");
      ObjectSetString(m_chart,name,OBJPROP_TEXT,caption);
      return true;
     }

   bool CreateButton(const string suffix,const string caption,int x,int y,int width,color background,color foreground)
     {
      string name=m_prefix+suffix;
      if(ObjectFind(m_chart,name)<0 && !ObjectCreate(m_chart,name,OBJ_BUTTON,0,0,0))
         return false;
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,width);
      ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,25);
      ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,foreground);
      ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,background);
      ObjectSetInteger(m_chart,name,OBJPROP_BORDER_COLOR,clrDimGray);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(m_chart,name,OBJPROP_STATE,false);
      ObjectSetString(m_chart,name,OBJPROP_FONT,"Arial");
      ObjectSetString(m_chart,name,OBJPROP_TEXT,caption);
      return true;
     }

public:
   bool Init(long chartId,string symbol,ulong magic)
     {
      m_chart=chartId;
      m_prefix="MidasCtl_";
      m_symbol=symbol;
      m_magic=magic;
      m_x=10;
      m_y=18;
      ObjectsDeleteAll(m_chart,m_prefix);
      bool ok=true;
      ok=CreateLabel("TITLE","MIDAS TOUCH  |  EXECUTION CONTROL",m_x,m_y,10,clrWhite) && ok;
      ok=CreateLabel("STATUS1","Loading account and trade state...",m_x,m_y+20,9,clrSilver) && ok;
      ok=CreateLabel("STATUS2","Trail: --  |  Session: --",m_x,m_y+37,9,clrSilver) && ok;
      int by=m_y+57;
      int bw=86;
      int gap=5;
      ok=CreateButton("BUY","BUY",m_x,by,bw,clrForestGreen,clrWhite) && ok;
      ok=CreateButton("SELL","SELL",m_x+(bw+gap),by,bw,clrFireBrick,clrWhite) && ok;
      ok=CreateButton("CLOSE","CLOSE ALL",m_x+2*(bw+gap),by,bw,clrDarkSlateGray,clrWhite) && ok;
      ok=CreateButton("STOP","EMERGENCY STOP",m_x+3*(bw+gap),by,105,clrMaroon,clrWhite) && ok;
      ok=CreateButton("RESUME","RESUME",m_x+3*(bw+gap)+110,by,72,clrDarkGreen,clrWhite) && ok;
      ChartRedraw(m_chart);
      return ok;
     }

   void Refresh(int managedPositions,double floatingPnl,bool trailingEnabled,bool emergencyStopped,string sessionName)
     {
      string state=emergencyStopped ? "EMERGENCY HALT" : "RUNNING";
      color stateColor=emergencyStopped ? clrTomato : clrLimeGreen;
      ObjectSetString(m_chart,m_prefix+"STATUS1",OBJPROP_TEXT,
                      StringFormat("%s | Magic: %I64u | Positions: %d | Float: %.2f",
                                   m_symbol,m_magic,managedPositions,floatingPnl));
      ObjectSetInteger(m_chart,m_prefix+"STATUS1",OBJPROP_COLOR,clrSilver);
      ObjectSetString(m_chart,m_prefix+"STATUS2",OBJPROP_TEXT,
                      StringFormat("State: %s  |  Trailing profit: %s  |  Session: %s",
                                   state,(trailingEnabled ? "ON" : "OFF"),sessionName));
      ObjectSetInteger(m_chart,m_prefix+"STATUS2",OBJPROP_COLOR,stateColor);
      ChartRedraw(m_chart);
     }

   int CommandForClick(const string objectName)
     {
      if(StringFind(objectName,m_prefix)!=0)
         return PANEL_ACTION_NONE;
      ObjectSetInteger(m_chart,objectName,OBJPROP_STATE,false);
      string key=StringSubstr(objectName,StringLen(m_prefix));
      if(key=="BUY") return PANEL_ACTION_BUY;
      if(key=="SELL") return PANEL_ACTION_SELL;
      if(key=="CLOSE") return PANEL_ACTION_CLOSE_ALL;
      if(key=="STOP") return PANEL_ACTION_EMERGENCY_STOP;
      if(key=="RESUME") return PANEL_ACTION_RESUME;
      return PANEL_ACTION_NONE;
     }

   void Destroy()
     {
      ObjectsDeleteAll(m_chart,m_prefix);
      ChartRedraw(m_chart);
     }
  };

#endif
//+------------------------------------------------------------------+
// END INLINED MODULE: includes/UI/TradeControlPanel.mqh

input group "General"
input int InpMaxHistoryBars=500;
input string InpTesterExportRunId="matched-experiment"; // logical label; exporter adds a runtime suffix and remains tester-only
input group "Structure"
input int InpSwingStrength=3;
input group "Per-Concept Timeframes"
input ENUM_TIMEFRAMES InpTrendTF=PERIOD_D1;
input ENUM_TIMEFRAMES InpBOSTF=PERIOD_H4;
input ENUM_TIMEFRAMES InpLiquidityTF=PERIOD_M15;
input ENUM_TIMEFRAMES InpFVGTF=PERIOD_M15;
input group "Multi-timeframe Structure Alignment (research gate)"
input bool InpRequireMtfStructureAlignment=false; // enable only after matched MT5 ablation validates the gate
input int InpMtfMaxBosAgeBars=20; // measured independently in each configured timeframe
input group "Top-Down MTF (research candidate; off until matched validation)"
input bool InpEnableTopDownMTF=false; // Enable only after matched MT5 Strategy Tester validation
input double InpMTFMaxConfidenceAdjustment=8.0; // Bounded +/- confidence adjustment; never a standalone entry trigger
input int InpMTFChochLookbackBars=8;
input group "Fair Value Gaps"
input double InpFVGMinSizeATR=0.1;
input group "Liquidity"
input double InpInternalLiqThresholdATR=0.2;
input group "Risk (setup validation)"
input double InpMinRiskReward=1.5;
input double InpMaxSLDistanceATR=1.5;
input double InpSLBufferATR=0.25;
input double InpMinStopSpreadMult=3.0;
input double InpMaxEntryDeviationATR=0.15;
input group "Inducement Engine"
input int InpImpulseLookbackBars=40;
input double InpImpulseATRMult=1.2;
input double InpImpulseBodyRatio=0.6;
input double InpEqualTolATR=0.2;
input int InpMaxLegExtend=10;
input bool InpRequirePremiumDiscount=true;
input bool InpRequireDistributionPhase=false;
input int InpPhaseRangeLookback=20;
input double InpPhaseCompressionATRMult=2.5;
input group "Volume Engine (v2.6)"
input bool InpRequireVolumeConfirmation=true;
input double InpRVOLThreshold=1.5;
input int InpRVOLLookback=20;
input group "Fibonacci Engine (v2.6)"
input bool InpRequireFibonacciZone=true;
input double InpFibZoneMinPct=50.0;
input double InpFibZoneMaxPct=61.8;
input group "Value Area Engine (v2.6)"
input bool InpRequireValueAreaLocation=false;
input bool InpBlockValueAreaContradictions=true;
input int InpVALookbackBars=100;
input int InpVANumBins=24;
input double InpVAPercent=70.0;
input group "HTF Order Block Engine (v2.8)"
input ENUM_TIMEFRAMES InpHtfObTF=PERIOD_H4;
input bool InpRequireHtfOB=false;
input double InpOBDisplacementATRMult=1.5;
input double InpOBMinBodyRatio=0.5;
input double InpOBDistATRMax=2.0;
input group "Volatility Regime (v2.8)"
input bool InpBlockLowVolRegime=false;
input int InpVolRegimeLookback=100;
input double InpVolRegimeLowPct=0.25;
input double InpVolRegimeHighPct=0.75;
input group "Session Filter (v2.8)"
input bool InpUseSessionFilter=false; // OFF by default: London/NY is a liquidity policy, not a universal exchange calendar
input bool InpAllowTokyoSession=false;
input bool InpAllowLondonSession=true;
input bool InpAllowNewYorkSession=true;
input bool InpAllowLondonNYOverlap=true;
input group "Sweep Quality / Chase Filter / FVG Proximity (v2.9)"
input bool InpRequireMinSweepGrade=false;
input int InpMinSweepGrade=2;
input bool InpRequireFreshSetup=false;
input int InpMaxBarsSinceBOS=5;
input bool InpRequireChaseFilter=false;
input double InpMaxChaseDistATR=0.75;
input double InpFVGMaxDistATR=1.25;
input double InpMinDirectionalAdvantage=0.0;
input group "Signal Lifecycle (v2.9)"
input bool InpPublishLifecycleUpdates=false;
input int InpSignalExpiryBars=12;
input double InpSignalStaleChaseATR=1.0;
input double InpInvalidateOpposingConfidence=70.0;
input group "Confidence Diagnostics (v2.10) - measured, NOT acted on"
input double InpDiagContradictionWeight=0.25;
input double InpDiagEnvWeight=1.0;
input double InpDiagExecWeight=1.0;
input double InpDiagDecayHalfLifeBars=12.0;
input group "Strategy Diagnostics (v2.12) - measured, NOT acted on"
input int InpMomentumBreakoutRecencyBars=10;
input int InpBreakoutLiqOverlapBars=2;
input int InpBreakoutExtensionLookbackBars=15;
input double InpBreakoutExhaustionATRMult=3.0;
input int InpMomentumLookbackBars=10;
input group "Mean Reversion Diagnostics (v2.13) - measured, NOT acted on"
input double InpReversionMinStretchATR=1.0;
input double InpReversionSRZoneATRTolerance=0.25;
input double InpReversionWickRejectionRatio=0.55;
input int InpReversionLiqRecencyBars=10;
input int InpReversionTrendConflictRecencyBars=10;
input double InpReversionTrendConflictMinStrength=0.5;
input group "Key-Level Reaction Diagnostics (v2.14) - measured, NOT acted on"
input int InpKeyLevelLookbackBars=5;
input double InpKeyLevelSearchATRMax=3.0;
input double InpKeyLevelTouchToleranceATRMult=0.15;
input int InpKeyLevelAbsorptionMinTouches=3;
input double InpKeyLevelWickRejectionRatio=0.55;
input double InpKeyLevelRoundStep=0.0; // 0 = disabled; set explicitly per instrument when a psychological price grid is appropriate
input group "SMC Structural Gate (research)"
input bool InpRequireSMCStructuralValidity=false; // OFF until matched ablation and OOS evidence support promotion
input group "Strategy Selection (v2.15) - measured, NOT acted on"
input double InpMinSelectionScore=60.0;
input group "Adaptive Environment Memory"
input int InpEnvironmentMemoryMinSample=30;
input double InpEnvironmentMemoryBonus=2.0;
input double InpEnvironmentMemoryPenalty=2.0;
input group "Logging"
input bool InpLogSignals=true;
input bool InpTrackOutcomes=true;
input int InpMaxTrackingBars=100;
input int InpCalibrationMinSample=30;
input int InpSessionGMTOffsetOverride=999;
input ENUM_FILL_POLICY InpFillPolicy=FILL_CONSERVATIVE;
input ENUM_TIMEFRAMES InpReplayTF=PERIOD_M1;
input group "Policy — what this account does with a validated setup"
input bool InpEnableExecution=true;
input bool InpEnableSignals=true;
input double InpMinConfidenceExecute=68.0;
input double InpMinConfidenceSignal=58.0;
input double InpFullRiskConfidence=85.0;
input int InpMaxSpreadPoints=0;
input group "Account Risk Profile"
input ENUM_ACCOUNT_RISK_PROFILE InpAccountRiskProfile=ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT; // conservative small-account preset is the default

input group "Execution — Legacy Risk Inputs"
input bool InpUseMarketOrders=true;
input double InpRiskPercentPerTrade=0.5;
input int InpMaxOpenTrades=3;
input ulong InpMagicNumber=987654321;
input bool InpAllowMinLotOverride=false;
input double InpMaxDailyLossPercent=3.0;
input double InpMaxDrawdownPercent=10.0;
input double InpDeriskStartPercent=5.0;
input double InpDeriskFloor=0.25;
input bool InpUseNewsFilter=false;
input string InpNewsFilterFile="MedisTouch_News.csv";
input int InpNewsMinutesBefore=15;
input int InpNewsMinutesAfter=5;
input int InpNewsWarnMinutesBefore=60;
input int InpNewsWarnMinutesAfter=30;
input double InpNewsWarnMultiplier=0.85;
input group "Position Management"
input double InpBreakEvenAtR=1.0;
input double InpPartialAtR=2.0;
input double InpPartialFraction=0.5;
input double InpTrailATRMult=1.5;
input group "Trade Simulator costs (v2.7)"
input double InpSimCommissionPerLot=7.0;
input double InpSimSpreadPoints=10.0;
input double InpSimSlippagePoints=2.0;
input group "Portfolio (account-wide, across every symbol this magic number trades)"
input double InpMaxPortfolioRiskPercent=3.0;
input int InpMaxPositionsPerSymbol=3;
input int InpMaxPositionsPerGroup=3;

// User-requested aggressive profile for the KSh 1,500 starting account.
// A 20% planned stop-risk budget is KSh 300; 15% is KSh 225, both before
// gaps, slippage, commission and swaps. These are not profit guarantees.
// The EA rejects a trade if broker minimum volume would exceed its budget.
input group "Risk Profile — Small Account (high-risk; validate on demo first)"
input double InpSmallMinimumRiskPercentPerTrade=15.0;
input double InpSmallRiskPercentPerTrade=20.0; // Target; hard cap is shared with lot sizing
input int    InpSmallMaxOpenTrades=3;           // Ceiling; runtime admits one initially and expands conditionally
input double InpSmallMaxDailyLossPercent=25.0;
input double InpSmallMaxDrawdownPercent=35.0;
input double InpSmallDeriskStartPercent=10.0;
input double InpSmallDeriskFloor=0.75;          // 20% * 0.75 = 15% at the configured drawdown-de-risk floor
input double InpSmallMaxPortfolioRiskPercent=20.0;
input int    InpSmallMaxPositionsPerSymbol=3;
input int    InpSmallMaxPositionsPerGroup=3;
input bool   InpSmallAccountProfileConfigured=true; // Requested profile values; production profitability remains unverified

input group "Risk Profile — Prop Firm (configure exact firm rules)"
input double InpPropRiskPercentPerTrade=0.5;
input int    InpPropMaxOpenTrades=3;
input double InpPropMaxDailyLossPercent=3.0;
input double InpPropMaxDrawdownPercent=10.0;
input double InpPropDeriskStartPercent=5.0;
input double InpPropDeriskFloor=0.25;
input double InpPropMaxPortfolioRiskPercent=3.0;
input int    InpPropMaxPositionsPerSymbol=3;
input int    InpPropMaxPositionsPerGroup=3;
input bool   InpPropFirmProfileConfigured=false; // Set true only after entering and checking the exact firm's rules above

input group "Portfolio — High-Probability Multi-Trade"
input bool InpEnableMultiTrade=true;
input double InpMultiTradeDualProbability=90.0;
input double InpMultiTradeTripleProbability=95.0;
input double InpMultiTradeMinRawConfidence=85.0;
input int InpMultiTradeMinCalibrationSample=30;
input bool InpRequireHedgingForMultiTrade=true;
input group "Opposing positions — explicit hedge mode"
input bool InpAllowConcurrentOpposingPositions=true; // Requested default: simultaneous long/short only on MT5 retail-hedging accounts; netting remains fail-closed.
input double InpMultiTradeDualLeg0RiskFraction=0.60;
input double InpMultiTradeDualLeg1RiskFraction=0.40;
input double InpMultiTradeTripleLeg0RiskFraction=0.50;
input double InpMultiTradeTripleLeg1RiskFraction=0.30;
input double InpMultiTradeTripleLeg2RiskFraction=0.20;
input group "Signal Transport"
input int InpWebRequestTimeoutMs=5000;
input string InpBridgeApiKey="";
input string InpExecutionLedgerBaseUrl=""; // HTTPS root for the durable broker execution ledger
input bool InpRequireExecutionLedger=true; // Fail closed until broker/database reconciliation succeeds
input int InpExecutionLedgerRetrySeconds=30;
input string InpWeightSetVersion="v2.10-baseline";
input group "Decision Lineage"
input string InpDecisionSchemaVersion="decision-v1";
input string InpStrategyVersion="strategy-v1-integrated";
input string InpModelVersion="model-v1";
input string InpCalibrationVersion="calibration-v1";
input string InpFeatureSchemaVersion="feature-v1";
input string InpEnvironmentSchemaVersion="environment-v1";
input int InpMinimumQualifiedTradesPerDay=3;
input double InpMinimumQualifiedTradeR=0.25; // Count only fully closed net winners of at least this realized R.
input string InpConfigSyncEndpoint="";
input int InpConfigSyncPollMinutes=15;
input group "Production Monitoring"
input int InpHeartbeatIntervalSec=60;
input double InpMaxDrawdownAlertPercent=10.0;
input group "Progressive Drawdown De-Risk (research candidate; off by default)"
input bool InpEnableProgressiveDailyLossDeRisk=false; // Enable only after matched risk-policy validation

input group "On-chart Trade Control"
input bool InpShowTradeControlPanel=true;
input double InpManualStopATR=1.25;          // ATR distance used by BUY/SELL buttons
input double InpManualRiskReward=2.0;       // Final TP R multiple; keep at least 0.3R above InpMinRiskReward
input bool InpUseCustomTradingSessions=false; // optional extra gate based on broker-server time
input bool InpSession1Enabled=true;
input string InpSession1Start="07:00";
input string InpSession1End="12:00";
input bool InpSession2Enabled=true;
input string InpSession2Start="13:00";
input string InpSession2End="17:00";
input bool InpSession3Enabled=false;
input string InpSession3Start="19:00";
input string InpSession3End="22:00";

CTFContextPool g_pool;CTopDownMTFEngine g_topDownMTF;CScoringEngine g_scoring;CSessionFilter g_operatorSessionFilter;CTradeDecision g_decision;CRiskEngine g_risk;CSignalLogger g_logger;COutcomeTrackerLive g_tracker;CEnvironmentStrategyMemory g_environmentMemory;CDecisionEngine g_router;CBrokerAdapter g_broker;COrderManager g_orders;CPositionManager g_positions;CRecoveryEngine g_recovery;CPortfolioManager g_portfolio;CMultiTradeEngine g_multiTrade;CRiskGuard g_riskGuard;CNewsFilter g_newsFilter;CSubscriberPlatform g_subscribers;CSignalPublisher g_publisher;CDailyTradeTarget g_dailyTradeTarget;CConfigSync g_configSync;CProductionMonitor g_monitor;CTradeControlPanel g_controlPanel;CExecutionAudit g_execAudit;bool g_emergencyStop=false;datetime g_lastSessionBlockLog=0;datetime g_lastEmergencyLatchRefresh=0;CTFContext* g_chartCtx=NULL;CTFContext* g_trendCtx=NULL;CTFContext* g_bosCtx=NULL;CTFContext* g_liqCtx=NULL;CTFContext* g_fvgCtx=NULL;CTFContext* g_htfObCtx=NULL;
AccountRiskLimits g_activeRiskLimits;
CExecutionLedgerClient g_executionLedger; CTesterDealExport g_testerDealExport; bool g_executionLedgerHealthy=false; datetime g_lastLedgerReconcileAttempt=0; datetime g_lastConfigSyncPoll=0;
datetime g_lastLoggedTime=0,g_lastBarTime=0;long g_lifecycleDecisionId=0;datetime g_lifecycleCreationTime=0;TradeSetup g_lifecycleSetup;string g_lifecycleStatus="valid";bool g_panelInitialized=false;

string EmergencyStopGlobalKey();
bool IsConfiguredSessionAllowed();
bool IsNettingOrExchangeAccount();
bool IsRetailHedgingAccount();
bool HasAnyChartSymbolExposure();
bool HasForeignChartSymbolExposure();
bool HasOpposingChartSymbolExposure(ENUM_ORDER_TYPE desiredType);
bool CanOpenDirectionWithExposure(ENUM_ORDER_TYPE desiredType,string &reasonOut);
void RefreshTradeControlPanel();
bool RiskRFromMoney(double riskMoney,double &riskR,bool allowZero);
bool ReconcileBrokerStateSnapshot();
bool SyncHistoricalClosedPositions();
bool SyncHistoricalDealEvents();
bool SendLedgerDealEvent(const ulong dealTicket,const ulong positionIdentifier);
bool IsPositionIdentifierOpen(const ulong positionIdentifier);
bool ParseManagedOrderComment(const string comment,long &decisionId,int &legIndex);
bool PrepareLedgerForSubmit(const TradeDecisionRecord &decision,const int legIndex,const double riskMoney,const double volatility,string &requestId);
void MarkLedgerSubmissionAccepted(const string requestId);
void MarkLedgerSubmissionAmbiguous(const string requestId);
bool UpdateLedgerRiskForPosition(const ulong positionIdentifier,const string direction,const double volatility,const string evidenceRef);
bool IsOrderBuyDirection(const ENUM_ORDER_TYPE orderType);
int EffectiveMaxOpenTrades();
bool SmallAccountRiskAdmission(bool reduceRisk,string &reasonOut);

void ConfigureAccountRiskLimits(AccountRiskLimits &limits,
                                 ENUM_ACCOUNT_RISK_PROFILE profile,
                                 string profileName,double riskPercent,int maxOpenTrades,
                                 double maxDailyLoss,double maxDrawdown,double deriskStart,
                                 double deriskFloor,double portfolioRisk,
                                 int maxPerSymbol,int maxPerGroup)
  {
   limits.profile=profile;
   limits.profileName=profileName;
   limits.riskPercentPerTrade=riskPercent;
   limits.maxOpenTrades=maxOpenTrades;
   limits.maxDailyLossPercent=maxDailyLoss;
   limits.maxDrawdownPercent=maxDrawdown;
   limits.deriskStartPercent=deriskStart;
   limits.deriskFloor=deriskFloor;
   limits.maxPortfolioRiskPercent=portfolioRisk;
   limits.maxPositionsPerSymbol=maxPerSymbol;
   limits.maxPositionsPerGroup=maxPerGroup;
  }

bool RiskRFromMoney(double riskMoney,double &riskR,bool allowZero)
  {
   riskR=0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double baseRiskUnit=equity*g_activeRiskLimits.riskPercentPerTrade/100.0;
   // Zero risk is valid only when the caller proves the broker stop is at or
   // beyond breakeven. New reservations and unprotected stops remain strict.
   if(equity<=0.0 || baseRiskUnit<=0.0 || !MathIsValidNumber(riskMoney) ||
      !MathIsValidNumber(baseRiskUnit) || riskMoney<0.0 || (riskMoney==0.0 && !allowZero))
      return false;
   riskR=riskMoney/baseRiskUnit;
   return (MathIsValidNumber(riskR) && (allowZero ? riskR>=0.0 : riskR>0.0));
  }

bool ParseManagedOrderComment(const string comment,long &decisionId,int &legIndex)
  {
   decisionId=0;
   legIndex=0;
   int marker=StringFind(comment,"MT#");
   if(marker<0) return false;
   string tail=StringSubstr(comment,marker+3);
   int legMarker=StringFind(tail,":L");
   string idText=(legMarker>=0)?StringSubstr(tail,0,legMarker):tail;
   decisionId=StringToInteger(idText);
   if(legMarker>=0)
      legIndex=(int)StringToInteger(StringSubstr(tail,legMarker+2));
   return (decisionId>0 && legIndex>=0);
  }

bool IsOrderBuyDirection(const ENUM_ORDER_TYPE orderType)
  {
   return (orderType==ORDER_TYPE_BUY || orderType==ORDER_TYPE_BUY_LIMIT ||
           orderType==ORDER_TYPE_BUY_STOP || orderType==ORDER_TYPE_BUY_STOP_LIMIT);
  }

bool IsPositionIdentifierOpen(const ulong positionIdentifier)
  {
   if(positionIdentifier==0) return false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==positionIdentifier)
         return true;
     }
   return false;
  }

bool PrepareLedgerForSubmit(const TradeDecisionRecord &decision,const int legIndex,
                            const double riskMoney,const double volatility,string &requestId)
  {
   requestId="";
   if(!g_executionLedger.AdmissionReady())
      return !InpRequireExecutionLedger;

   double riskR=0.0;
   if(!RiskRFromMoney(riskMoney,riskR,false))
     {
      g_execAudit.Log("EXECUTION_LEDGER_RISK_INVALID",
                      "risk could not be normalized to the configured base risk unit",
                      decision.decision_id);
      return false;
     }
   string direction=(decision.setup.type==ORDER_TYPE_BUY)?"BUY":"SELL";
   string signalId="MT#"+IntegerToString(decision.decision_id);
   if(!g_executionLedger.Reserve(decision.decision_id,legIndex,signalId,_Symbol,direction,
                                 riskR,MathMax(0.0,volatility),requestId))
     {
      g_execAudit.Log("EXECUTION_LEDGER_RESERVATION_BLOCKED",
                      "bridge did not confirm an idempotent portfolio-risk reservation",
                      decision.decision_id,0,0.0,0.0,0.0,0.0);
      return false;
     }
   // Write-ahead intent: persist SENT before the broker call. If MT5 crashes
   // after this point, recovery treats the outcome as ambiguous rather than
   // releasing the reservation and risking a duplicate order.
   if(!g_executionLedger.Transition(requestId,"CHECKED","{}"))
     {
      g_executionLedgerHealthy=false;
      g_execAudit.Log("EXECUTION_LEDGER_CHECKED_FAILED",
                      "risk reserved but CHECKED transition was not acknowledged; broker call suppressed",
                      decision.decision_id);
      return false;
     }
   if(!g_executionLedger.Transition(requestId,"SENT","{\"ea_send_intent\":true}"))
     {
      g_executionLedgerHealthy=false;
      g_execAudit.Log("EXECUTION_LEDGER_SENT_FAILED",
                      "risk reserved but SENT transition was not acknowledged; broker call suppressed",
                      decision.decision_id);
      return false;
     }
   return true;
  }

void MarkLedgerSubmissionAccepted(const string requestId)
  {
   if(StringLen(requestId)==0 || !g_executionLedger.Ready()) return;
   ulong orderId=g_broker.LastBrokerOrderId();
   ulong dealId=g_broker.LastBrokerDealId();
   ulong positionId=g_broker.LastBrokerPositionId();

   if(orderId>0)
     {
      string ack=StringFormat("{\"broker_acknowledged\":true,\"broker_order_id\":\"%I64u\"",orderId);
      if(dealId>0) ack+=StringFormat(",\"broker_deal_id\":\"%I64u\"",dealId);
      if(positionId>0) ack+=StringFormat(",\"broker_position_id\":\"%I64u\"",positionId);
      ack+="}";
      if(!g_executionLedger.Transition(requestId,"ACKED",ack))
        {
         g_executionLedgerHealthy=false;
         PrintFormat("Midas: broker accepted order #%I64u but ACKED persistence failed; startup reconciliation required.",orderId);
         return;
        }
     }

   if(dealId>0 && positionId>0)
     {
      string fill=StringFormat(
         "{\"broker_confirmed_fill\":true,\"broker_order_id\":\"%I64u\",\"broker_deal_id\":\"%I64u\",\"broker_position_id\":\"%I64u\",\"evidence_ref\":\"mt5-deal:%I64u\"}",
         orderId,dealId,positionId,dealId);
      if(!g_executionLedger.Transition(requestId,"FILLED",fill))
        {
         g_executionLedgerHealthy=false;
         PrintFormat("Midas: broker fill #%I64u could not be durably marked; risk reservation must remain in recovery.",dealId);
        }
     }
   else if(orderId==0)
     {
      MarkLedgerSubmissionAmbiguous(requestId);
     }
  }

void MarkLedgerSubmissionAmbiguous(const string requestId)
  {
   if(StringLen(requestId)==0 || !g_executionLedger.Ready()) return;
   if(!g_executionLedger.Transition(requestId,"RECOVERING",
                                    "{\"submission_result\":\"ambiguous\",\"evidence_ref\":\"ea-submit-result\"}"))
     {
      g_executionLedgerHealthy=false;
      Print("Midas: submission result could not be reconciled with the bridge; new entries are blocked until recovery.");
     }
  }

bool UpdateLedgerRiskForPosition(const ulong positionIdentifier,const string direction,
                                 const double volatility,const string evidenceRef)
  {
   if(!g_executionLedger.Ready()) return !InpRequireExecutionLedger;
   ulong ticket=g_broker.PositionTicketForIdentifier(_Symbol,positionIdentifier);
   if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
   double sl=PositionGetDouble(POSITION_SL);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double volume=PositionGetDouble(POSITION_VOLUME);
   if(sl<=0.0 || entry<=0.0 || volume<=0.0) return false;
   double riskMoney=g_risk.RiskAmountForLots(_Symbol,volume,entry,sl);
   double riskR=0.0;
   bool stopLocked=(direction=="BUY" && sl>=entry) || (direction=="SELL" && sl<=entry);
   if(!RiskRFromMoney(riskMoney,riskR,stopLocked)) return false;
   return g_executionLedger.UpdatePositionRisk(positionIdentifier,direction,riskR,
                                                MathMax(0.0,volatility),evidenceRef);
  }

bool ReconcileBrokerStateSnapshot()
  {
   g_lastLedgerReconcileAttempt=TimeCurrent();
   if(!g_executionLedger.Ready()) return false;
   bool allOk=true;
   if(!g_executionLedger.RecoverExpired())
     {
      g_execAudit.Log("LEDGER_RECOVERY_API_FAILED","could not request expired execution lease recovery");
      allOk=false;
     }

   double baseRiskUnit=AccountInfoDouble(ACCOUNT_EQUITY)*g_activeRiskLimits.riskPercentPerTrade/100.0;
   if(baseRiskUnit<=0.0)
     {
      g_execAudit.Log("LEDGER_STARTUP_BLOCKED","base risk unit is non-positive; existing exposure cannot be normalized");
      return false;
     }

   // Import every live position for this strategy magic, across symbols.
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      if(positionId==0 || sl<=0.0 || entry<=0.0 || volume<=0.0)
        {
         g_execAudit.Log("LEDGER_POSITION_RISK_UNKNOWN",
                         "startup reconciliation found an EA position without computable stop risk",
                         0,ticket,volume,entry,sl,0.0);
         allOk=false;
         continue;
        }
      double riskMoney=g_risk.RiskAmountForLots(symbol,volume,entry,sl);
      double riskR=0.0;
      long positionType=PositionGetInteger(POSITION_TYPE);
      bool stopLocked=(positionType==POSITION_TYPE_BUY && sl>=entry) ||
                      (positionType==POSITION_TYPE_SELL && sl<=entry);
      if(!RiskRFromMoney(riskMoney,riskR,stopLocked))
        {
         allOk=false;
         continue;
        }

      ulong openingOrder=0;
      ulong openingDeal=0;
      long commentDecisionId=0;
      int commentLegIndex=0;
      string requestIdOverride="";
      if(HistorySelectByPosition(positionId))
        {
         for(int d=0;d<HistoryDealsTotal();d++)
           {
            ulong deal=HistoryDealGetTicket(d);
            if(deal==0) continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
            if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber) continue;
            openingOrder=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
            openingDeal=deal;
            break;
           }
        }
      if(openingOrder>0 && HistoryOrderSelect(openingOrder))
        {
         string comment=HistoryOrderGetString(openingOrder,ORDER_COMMENT);
         if(ParseManagedOrderComment(comment,commentDecisionId,commentLegIndex))
            requestIdOverride=g_executionLedger.RequestIdForDecision(commentDecisionId,commentLegIndex);
        }

      string direction=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?"BUY":"SELL";
      string evidence=StringFormat("mt5-oninit-position:%I64u:%I64u",positionId,TimeCurrent());
      double observedTP=PositionGetDouble(POSITION_TP);
      if(!g_executionLedger.SyncPosition(positionId,openingOrder,openingDeal,symbol,direction,
                                         riskR,0.0,evidence,requestIdOverride,sl,observedTP))
        {
         g_execAudit.Log("LEDGER_POSITION_SYNC_FAILED",
                         "live broker position could not be imported into the persistent portfolio risk book",
                         commentDecisionId,ticket,volume,entry,sl,0.0);
         allOk=false;
        }
     }

   // Import live pending orders too: their risk remains reserved even if no
   // position has filled yet. Unknown SL risk fails closed rather than guessed.
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong orderTicket=OrderGetTicket(i);
      if(orderTicket==0 || !OrderSelect(orderTicket)) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      ENUM_ORDER_TYPE orderType=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType!=ORDER_TYPE_BUY_LIMIT && orderType!=ORDER_TYPE_SELL_LIMIT &&
         orderType!=ORDER_TYPE_BUY_STOP && orderType!=ORDER_TYPE_SELL_STOP &&
         orderType!=ORDER_TYPE_BUY_STOP_LIMIT && orderType!=ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      string symbol=OrderGetString(ORDER_SYMBOL);
      double volume=OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(volume<=0.0) volume=OrderGetDouble(ORDER_VOLUME_INITIAL);
      double entry=OrderGetDouble(ORDER_PRICE_OPEN);
      double sl=OrderGetDouble(ORDER_SL);
      if(sl<=0.0 || entry<=0.0 || volume<=0.0)
        {
         g_execAudit.Log("LEDGER_PENDING_RISK_UNKNOWN",
                         "startup found a pending EA order without computable stop risk",
                         0,orderTicket,volume,entry,sl,0.0);
         allOk=false;
         continue;
        }
      double riskMoney=g_risk.RiskAmountForLots(symbol,volume,entry,sl);
      double riskR=0.0;
      if(!RiskRFromMoney(riskMoney,riskR,false))
        {
         allOk=false;
         continue;
        }
      long decisionId=0;
      int legIndex=0;
      string requestIdOverride="";
      if(ParseManagedOrderComment(OrderGetString(ORDER_COMMENT),decisionId,legIndex))
         requestIdOverride=g_executionLedger.RequestIdForDecision(decisionId,legIndex);
      string direction=IsOrderBuyDirection(orderType)?"BUY":"SELL";
      string evidence=StringFormat("mt5-oninit-order:%I64u:%I64u",orderTicket,TimeCurrent());
      if(!g_executionLedger.SyncPendingOrder(orderTicket,symbol,direction,riskR,0.0,evidence,requestIdOverride))
        {
         g_execAudit.Log("LEDGER_ORDER_SYNC_FAILED",
                         "live broker pending order could not be imported into portfolio risk book",
                         decisionId,orderTicket,volume,entry,sl,0.0);
         allOk=false;
        }
     }

   // Replay broker deal history before declaring the ledger healthy. This repairs
   // missed callbacks after terminal restarts and is idempotent by broker deal ID.
   if(!SyncHistoricalDealEvents())
      allOk=false;
   if(!SyncHistoricalClosedPositions())
      allOk=false;
   return allOk;
  }

bool SyncHistoricalDealEvents()
  {
   if(!g_executionLedger.Ready()) return !InpRequireExecutionLedger;
   if(!HistorySelect(0,TimeCurrent())) return false;
   ulong deals[];
   int total=HistoryDealsTotal();
   ArrayResize(deals,total);
   for(int i=0;i<total;i++) deals[i]=HistoryDealGetTicket(i);

   bool allOk=true;
   for(int i=0;i<ArraySize(deals);i++)
     {
      ulong deal=deals[i];
      if(deal==0 || !HistoryDealSelect(deal)) { allOk=false; continue; }
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_OUT &&
         entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) continue;
      ulong positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(positionId==0) { allOk=false; continue; }
      if(!SendLedgerDealEvent(deal,positionId))
        {
         g_execAudit.Log("LEDGER_HISTORY_DEAL_REPLAY_FAILED",
                         "historical broker deal could not be durably replayed",
                         0,positionId,HistoryDealGetDouble(deal,DEAL_VOLUME),
                         HistoryDealGetDouble(deal,DEAL_PRICE));
         allOk=false;
        }
     }
   return allOk;
  }

bool SyncHistoricalClosedPositions()
  {
   if(!g_executionLedger.Ready()) return !InpRequireExecutionLedger;
   // A netting reversal can reuse the same position identity for a new side;
   // never infer terminal closure from volume arithmetic in that mode.
   if(IsNettingOrExchangeAccount()) return true;
   if(!HistorySelect(0,TimeCurrent())) return false;

   ulong candidateIds[];
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      ulong positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(positionId==0 || IsPositionIdentifierOpen(positionId)) continue;
      bool known=false;
      for(int j=0;j<ArraySize(candidateIds);j++)
         if(candidateIds[j]==positionId) { known=true; break; }
      if(!known)
        {
         int size=ArraySize(candidateIds);
         ArrayResize(candidateIds,size+1);
         candidateIds[size]=positionId;
        }
     }

   bool allOk=true;
   for(int p=0;p<ArraySize(candidateIds);p++)
     {
      ulong positionId=candidateIds[p];
      if(IsPositionIdentifierOpen(positionId) || !HistorySelectByPosition(positionId)) continue;
      double openedVolume=0.0;
      double closedVolume=0.0;
      bool hasManagedEntry=false;
      bool foreignEntry=false;
      bool ambiguous=false;
      ulong lastCloseDeal=0;
      ulong openingOrder=0;
      long decisionId=0;
      int legIndex=0;

      for(int d=0;d<HistoryDealsTotal();d++)
        {
         ulong deal=HistoryDealGetTicket(d);
         if(deal==0) continue;
         if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=positionId) continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
         double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
         ulong dealMagic=(ulong)HistoryDealGetInteger(deal,DEAL_MAGIC);
         if(entry==DEAL_ENTRY_IN)
           {
            if(dealMagic==InpMagicNumber)
              {
               hasManagedEntry=true;
               openedVolume+=volume;
               if(openingOrder==0)
                  openingOrder=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
              }
            else foreignEntry=true;
           }
         else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
           {
            closedVolume+=volume;
            lastCloseDeal=deal;
           }
         else if(entry==DEAL_ENTRY_INOUT) ambiguous=true;
        }

      double tolerance=MathMax(1e-6,openedVolume*1e-5);
      if(!hasManagedEntry || foreignEntry || ambiguous || lastCloseDeal==0 ||
         openedVolume<=0.0 || closedVolume+tolerance<openedVolume)
         continue;

      string requestIdOverride="";
      if(openingOrder>0 && HistoryOrderSelect(openingOrder))
        {
         string comment=HistoryOrderGetString(openingOrder,ORDER_COMMENT);
         if(ParseManagedOrderComment(comment,decisionId,legIndex))
            requestIdOverride=g_executionLedger.RequestIdForDecision(decisionId,legIndex);
        }
      string evidence=StringFormat("mt5-oninit-closed-history:%I64u:%I64u",positionId,lastCloseDeal);
      if(!g_executionLedger.SyncClosedPosition(positionId,lastCloseDeal,evidence,requestIdOverride))
        {
         g_execAudit.Log("LEDGER_CLOSED_HISTORY_SYNC_FAILED",
                         "closed position history could not be replayed into persistent execution state",
                         decisionId,positionId,0.0,0.0,0.0,0.0);
         allOk=false;
        }
     }
   return allOk;
  }


bool ResolveSelectedAccountRiskProfile()
  {
   if(InpAccountRiskProfile==ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT)
     {
      if(!MathIsValidNumber(InpSmallMinimumRiskPercentPerTrade) ||
         InpSmallMinimumRiskPercentPerTrade<MIDAS_SMALL_ACCOUNT_MIN_RISK_PERCENT_PER_TRADE ||
         InpSmallMinimumRiskPercentPerTrade>InpSmallRiskPercentPerTrade ||
         InpSmallRiskPercentPerTrade>MIDAS_MAX_RISK_PERCENT_PER_TRADE ||
         InpSmallRiskPercentPerTrade*InpSmallDeriskFloor+0.000001<InpSmallMinimumRiskPercentPerTrade)
        {
         PrintFormat("MedisTouch: invalid small-account risk range; minimum=%.2f%% target=%.2f%% derisk-floor=%.3f ceiling=%.2f%%",
                     InpSmallMinimumRiskPercentPerTrade,InpSmallRiskPercentPerTrade,
                     InpSmallDeriskFloor,MIDAS_MAX_RISK_PERCENT_PER_TRADE);
         return false;
        }
     }
   AccountRiskLimits legacy,smallAccount,propFirm;
   ConfigureAccountRiskLimits(legacy,ACCOUNT_RISK_PROFILE_LEGACY_INPUTS,"legacy_inputs",
      InpRiskPercentPerTrade,InpMaxOpenTrades,InpMaxDailyLossPercent,InpMaxDrawdownPercent,
      InpDeriskStartPercent,InpDeriskFloor,InpMaxPortfolioRiskPercent,
      InpMaxPositionsPerSymbol,InpMaxPositionsPerGroup);
   ConfigureAccountRiskLimits(smallAccount,ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT,"small_account",
      InpSmallRiskPercentPerTrade,InpSmallMaxOpenTrades,InpSmallMaxDailyLossPercent,
      InpSmallMaxDrawdownPercent,InpSmallDeriskStartPercent,InpSmallDeriskFloor,
      InpSmallMaxPortfolioRiskPercent,InpSmallMaxPositionsPerSymbol,InpSmallMaxPositionsPerGroup);
   ConfigureAccountRiskLimits(propFirm,ACCOUNT_RISK_PROFILE_PROP_FIRM,"prop_firm",
      InpPropRiskPercentPerTrade,InpPropMaxOpenTrades,InpPropMaxDailyLossPercent,
      InpPropMaxDrawdownPercent,InpPropDeriskStartPercent,InpPropDeriskFloor,
      InpPropMaxPortfolioRiskPercent,InpPropMaxPositionsPerSymbol,InpPropMaxPositionsPerGroup);

   string reason="";
   if(!ResolveConfiguredAccountRiskLimits(InpAccountRiskProfile,legacy,smallAccount,propFirm,
                                            InpSmallAccountProfileConfigured,InpPropFirmProfileConfigured,
                                            g_activeRiskLimits,reason))
     {
      PrintFormat("MedisTouch: invalid account risk profile (%s): %s",
                  EnumToString(InpAccountRiskProfile),reason);
      return false;
     }
   PrintFormat("MedisTouch: active risk profile=%s risk/trade=%.3f%% max-open=%d daily-cap=%.2f%% hard-DD=%.2f%% portfolio-open-risk=%.2f%% per-symbol=%d per-group=%d",
               g_activeRiskLimits.profileName,g_activeRiskLimits.riskPercentPerTrade,
               g_activeRiskLimits.maxOpenTrades,g_activeRiskLimits.maxDailyLossPercent,
               g_activeRiskLimits.maxDrawdownPercent,g_activeRiskLimits.maxPortfolioRiskPercent,
               g_activeRiskLimits.maxPositionsPerSymbol,g_activeRiskLimits.maxPositionsPerGroup);
   return true;
  }

int OnInit()
  {
   // Dynamic trailing is mandatory for every attached EA instance. The
   // Strategy Tester alone may disable it for a controlled matched ablation.
   if(!InpEnableDynamicStop && !MQLInfoInteger(MQL_TESTER))
     {
      Print("Midas Touch: CRITICAL — dynamic trailing stop is mandatory outside the Strategy Tester; refusing to initialize.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!ResolveSelectedAccountRiskProfile()) return INIT_PARAMETERS_INCORRECT;
   g_testerDealExport.Init(InpTesterExportRunId,_Symbol,InpMagicNumber,
                           (bool)MQLInfoInteger(MQL_TESTER));
   if(StringLen(InpExecutionLedgerBaseUrl)>0 && StringLen(InpBridgeApiKey)>0)
     {
      g_executionLedger.Init(InpExecutionLedgerBaseUrl,InpBridgeApiKey,InpMagicNumber,InpWebRequestTimeoutMs);
      if(!g_executionLedger.CheckHealth())
         g_execAudit.Log("EXECUTION_LEDGER_HEALTH_FAILED","authenticated bridge health probe did not confirm database-backed execution_ledger=ready; new entries remain blocked");
     }
   else
      Print("Midas execution ledger: configure InpExecutionLedgerBaseUrl and InpBridgeApiKey before enabling ledger-enforced entries.");
   g_executionLedgerHealthy=(!InpEnableExecution || !InpRequireExecutionLedger);
   // M1 is the execution timeframe for this research candidate. Refuse ambiguous chart-timeframe execution.
   if(InpEnableTopDownMTF && _Period!=PERIOD_M1)
     {
      Print("Midas: InpEnableTopDownMTF requires an M1 chart; refusing mismatched execution timeframe.");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_pool.Configure(_Symbol,InpMaxHistoryBars,InpSwingStrength,InpFVGMinSizeATR,InpInternalLiqThresholdATR,InpRVOLLookback,InpVALookbackBars,InpVANumBins,InpVAPercent/100.0,InpOBDisplacementATRMult,InpOBMinBodyRatio);g_chartCtx=g_pool.Get(_Period);g_trendCtx=g_pool.Get(InpTrendTF);g_bosCtx=g_pool.Get(InpBOSTF);g_liqCtx=g_pool.Get(InpLiquidityTF);g_fvgCtx=g_pool.Get(InpFVGTF);g_htfObCtx=g_pool.Get(InpHtfObTF);if(g_chartCtx==NULL||g_trendCtx==NULL||g_bosCtx==NULL||g_liqCtx==NULL||g_fvgCtx==NULL||g_htfObCtx==NULL)return INIT_FAILED;
   // Top-down contexts are additional to per-concept contexts. The pool deduplicates
   // identical timeframes and is sized to support both sets without aliasing TFs.
   if(InpEnableTopDownMTF)
     {
      CTFContext* tdD1=g_pool.Get(PERIOD_D1);
      CTFContext* tdH4=g_pool.Get(PERIOD_H4);
      CTFContext* tdH1=g_pool.Get(PERIOD_H1);
      CTFContext* tdM30=g_pool.Get(PERIOD_M30);
      CTFContext* tdM15=g_pool.Get(PERIOD_M15);
      CTFContext* tdM5=g_pool.Get(PERIOD_M5);
      CTFContext* tdM1=g_pool.Get(PERIOD_M1);
      if(tdD1==NULL || tdH4==NULL || tdH1==NULL || tdM30==NULL ||
         tdM15==NULL || tdM5==NULL || tdM1==NULL ||
         !g_topDownMTF.Init(tdD1,tdH4,tdH1,tdM30,tdM15,tdM5,tdM1))
        {
         Print("Midas: top-down MTF initialization failed; refusing to start with an incomplete timeframe stack.");
         return INIT_FAILED;
        }
      g_topDownMTF.Configure(InpMTFMaxConfidenceAdjustment,InpMTFChochLookbackBars);
      Print("Midas: direction-agnostic D1/H4/H1/M30/M15/M5/M1 scoring enabled; matched validation is required before production activation.");
     }
   g_scoring.Init(g_trendCtx,g_bosCtx,g_liqCtx,g_fvgCtx,g_chartCtx,&g_chartCtx.candles);g_scoring.ConfigureMTFStructureAlignment(InpRequireMtfStructureAlignment,InpMtfMaxBosAgeBars);g_scoring.ConfigureInducement(InpImpulseLookbackBars,InpImpulseATRMult,InpImpulseBodyRatio,InpEqualTolATR,InpMaxLegExtend,InpRequirePremiumDiscount,InpRequireDistributionPhase,InpPhaseRangeLookback,InpPhaseCompressionATRMult);g_scoring.ConfigureVolumeFibonacci(InpRequireVolumeConfirmation,InpRVOLThreshold,InpRequireFibonacciZone,InpFibZoneMinPct,InpFibZoneMaxPct);g_scoring.ConfigureValueArea(InpRequireValueAreaLocation,InpBlockValueAreaContradictions);g_scoring.ConfigureHtfOrderBlock(g_htfObCtx,InpRequireHtfOB,InpOBDistATRMax);g_scoring.ConfigureVolatilityRegime(InpBlockLowVolRegime,InpVolRegimeLookback,InpVolRegimeLowPct,InpVolRegimeHighPct);g_scoring.ConfigureSessionFilter(InpUseSessionFilter,InpAllowTokyoSession,InpAllowLondonSession,InpAllowNewYorkSession,InpAllowLondonNYOverlap);g_operatorSessionFilter.Configure(InpUseSessionFilter,InpAllowTokyoSession,InpAllowLondonSession,InpAllowNewYorkSession,InpAllowLondonNYOverlap);g_scoring.ConfigureSweepQuality(InpRequireMinSweepGrade,(ENUM_SWEEP_GRADE)InpMinSweepGrade,InpRequireFreshSetup,InpMaxBarsSinceBOS);g_scoring.ConfigureChaseFilter(InpRequireChaseFilter,InpMaxChaseDistATR);g_scoring.ConfigureFVGProximity(InpFVGMaxDistATR);g_scoring.ConfigureLearnedDiagnostics(InpDiagContradictionWeight,InpDiagEnvWeight,InpDiagExecWeight);g_scoring.ConfigureStrategyDiagnostics(InpMomentumBreakoutRecencyBars,InpBreakoutLiqOverlapBars,InpBreakoutExtensionLookbackBars,InpBreakoutExhaustionATRMult,InpMomentumLookbackBars);g_scoring.ConfigureMeanReversionDiagnostics(InpReversionMinStretchATR,InpReversionSRZoneATRTolerance,InpReversionWickRejectionRatio,InpReversionLiqRecencyBars,InpReversionTrendConflictRecencyBars,InpReversionTrendConflictMinStrength);g_scoring.ConfigureKeyLevelDiagnostics(InpKeyLevelLookbackBars,InpKeyLevelSearchATRMax,InpKeyLevelTouchToleranceATRMult,InpKeyLevelAbsorptionMinTouches,InpKeyLevelWickRejectionRatio,InpKeyLevelRoundStep);g_scoring.ConfigureStrategySelection(InpMinSelectionScore);
   g_environmentMemory.Init(_Symbol,InpEnvironmentMemoryMinSample,InpEnvironmentMemoryBonus,InpEnvironmentMemoryPenalty);g_decision.Init(&g_chartCtx.candles,g_fvgCtx,g_liqCtx,&g_scoring,InpSLBufferATR,InpMinStopSpreadMult,InpFVGMaxDistATR,InpMinSelectionScore,g_chartCtx,g_bosCtx,GetPointer(g_environmentMemory));g_decision.ConfigureSMCStructuralGate(InpRequireSMCStructuralValidity);g_logger.Init(_Symbol,InpSessionGMTOffsetOverride);g_tracker.Init(&g_logger,_Symbol,_Period,InpMaxTrackingBars,InpFillPolicy,InpReplayTF);g_tracker.ConfigureEnvironmentMemory(GetPointer(g_environmentMemory));g_tracker.ConfigureSimulation(g_activeRiskLimits.riskPercentPerTrade,InpAllowMinLotOverride,InpBreakEvenAtR,InpPartialAtR,InpPartialFraction,InpTrailATRMult,InpSimCommissionPerLot,InpSimSpreadPoints,InpSimSlippagePoints);g_tracker.ConfigureCalibration(InpTrackOutcomes,InpCalibrationMinSample);g_tracker.ConfigureConfidenceDecay(InpDiagDecayHalfLifeBars);g_router.Init(_Symbol,InpEnableExecution,InpEnableSignals,InpMinConfidenceExecute,InpMinConfidenceSignal,InpFullRiskConfidence,InpMaxSpreadPoints);g_multiTrade.Init(InpEnableMultiTrade,InpMultiTradeDualProbability,InpMultiTradeTripleProbability,InpMultiTradeMinRawConfidence,InpMultiTradeMinCalibrationSample,InpMultiTradeDualLeg0RiskFraction,InpMultiTradeDualLeg1RiskFraction,InpMultiTradeTripleLeg0RiskFraction,InpMultiTradeTripleLeg1RiskFraction,InpMultiTradeTripleLeg2RiskFraction,InpRequireHedgingForMultiTrade);g_broker.Init(InpMagicNumber);g_monitor.Init(_Symbol,InpHeartbeatIntervalSec,InpMaxDrawdownAlertPercent);g_orders.Init(&g_broker,g_activeRiskLimits.maxOpenTrades,&g_monitor);g_positions.Init(&g_orders,&g_broker,InpBreakEvenAtR,InpPartialAtR,InpPartialFraction,InpTrailATRMult,0,0.0,0.0,5,&g_chartCtx.swings,&g_executionLedger,&g_risk,g_activeRiskLimits.riskPercentPerTrade);g_store.Init(_Symbol);g_execAudit.Init(_Symbol,InpMagicNumber);g_emergencyStop=(GlobalVariableCheck(EmergencyStopGlobalKey()) && GlobalVariableGet(EmergencyStopGlobalKey())>0.5);if(InpShowTradeControlPanel || g_emergencyStop){g_panelInitialized=g_controlPanel.Init(ChartID(),_Symbol,InpMagicNumber);if(!g_panelInitialized)Print("MedisTouch: trade control panel could not create every chart object.");}g_execAudit.Log("INIT",StringFormat("version=2.81 magic=%I64u risk_profile=%s risk_per_trade=%.3f max_open=%d emergency_latched=%s account_margin_mode=%d",InpMagicNumber,g_activeRiskLimits.profileName,g_activeRiskLimits.riskPercentPerTrade,g_activeRiskLimits.maxOpenTrades,g_emergencyStop?"true":"false",(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE)));if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){g_execAudit.Log("ACCOUNT_MODE_WARNING","MT5 netting/exchange mode aggregates same-symbol exposure; isolate manual/other-EA activity before using close-all");Print("MedisTouch: WARNING — netting/exchange account may aggregate this symbol with other trade sources.");}bool qualifiedTradeTrackingSupported=InpTrackOutcomes && InpEnableExecution;g_dailyTradeTarget.Init(qualifiedTradeTrackingSupported?InpMinimumQualifiedTradesPerDay:0,InpMinimumQualifiedTradeR,InpMagicNumber);if(InpMinimumQualifiedTradesPerDay>0 && !qualifiedTradeTrackingSupported)Print("Midas Touch: weekday qualified-trade counter disabled; requires outcome tracking and automated execution.");if(InpAllowConcurrentOpposingPositions && !IsRetailHedgingAccount()){g_execAudit.Log("DUAL_MODE_UNSUPPORTED","InpAllowConcurrentOpposingPositions=true but the account is not MT5 retail hedging; simultaneous same-symbol long/short positions are not supported");Print("Midas Touch: opposing-position mode requested, but this account is not retail hedging; same-symbol opposing exposure remains blocked.");}else if(InpAllowConcurrentOpposingPositions){g_execAudit.Log("DUAL_MODE_ENABLED","same-symbol opposing positions permitted by explicit input; portfolio risk and position caps still apply");}g_subscribers.Init();g_publisher.Init(_Symbol,&g_subscribers,InpWebRequestTimeoutMs,InpBridgeApiKey);g_publisher.SetWeightVersion(InpWeightSetVersion);
   if(StringLen(InpConfigSyncEndpoint)>0){g_configSync.Init(_Symbol,InpConfigSyncEndpoint,InpBridgeApiKey,InpWeightSetVersion,InpWebRequestTimeoutMs);EventSetTimer(MathMax(60,InpConfigSyncPollMinutes*60));}g_tracker.ConfigurePublishing(&g_publisher,InpWeightSetVersion);g_portfolio.Init(g_activeRiskLimits.maxPortfolioRiskPercent,g_activeRiskLimits.maxPositionsPerSymbol,g_activeRiskLimits.maxPositionsPerGroup,InpMagicNumber,&g_risk);g_riskGuard.Init(_Symbol,g_activeRiskLimits.maxDailyLossPercent,g_activeRiskLimits.maxDrawdownPercent,g_activeRiskLimits.deriskStartPercent,g_activeRiskLimits.deriskFloor,InpEnableProgressiveDailyLossDeRisk);if(InpUseNewsFilter)g_newsFilter.Load(InpNewsFilterFile,InpNewsMinutesBefore,InpNewsMinutesAfter);g_scoring.ConfigureNewsAwareness(GetPointer(g_newsFilter),InpNewsWarnMinutesBefore,InpNewsWarnMinutesAfter,InpNewsWarnMultiplier);g_recovery.Init(&g_store,&g_orders,InpMagicNumber,_Symbol);int restored=g_recovery.Recover();if(restored>0)PrintFormat("MedisTouch EA: recovery restored %d live trade(s).",restored);TradeDecisionRecord prior[];int n=g_store.LoadAll(prior);long maxId=0;for(int i=0;i<n;i++)if(prior[i].decision_id>maxId)maxId=prior[i].decision_id;if(maxId>0)g_router.SeedNextId(maxId+1);
   if(InpEnableExecution && g_executionLedger.Ready() && g_executionLedger.AdmissionReady())
     {
      // Retry authenticated health before database reconciliation. A URL or
      // cached success is not sufficient to reopen trade admission.
      g_executionLedgerHealthy=g_executionLedger.CheckHealth() && ReconcileBrokerStateSnapshot();
      if(g_executionLedgerHealthy) g_executionLedger.MarkReconciled();
      if(!g_executionLedgerHealthy)
         g_execAudit.Log("EXECUTION_LEDGER_NOT_READY","broker/database startup reconciliation incomplete; existing positions remain managed, but new EA entries are blocked");
      else
         g_execAudit.Log("EXECUTION_LEDGER_READY","startup positions, pending orders and complete closed-history evidence reconciled");
     }
   else if(InpEnableExecution && InpRequireExecutionLedger)
     {
      g_executionLedgerHealthy=false;
      g_execAudit.Log("EXECUTION_LEDGER_NOT_READY","bridge health or credentials are unavailable; new automated and manual entries remain blocked while local position protection continues");
     }
   else g_executionLedgerHealthy=true;
   if(StringLen(InpConfigSyncEndpoint)>0 || (InpEnableExecution && InpRequireExecutionLedger) || g_emergencyStop)
      EventSetTimer(MathMax(10,InpExecutionLedgerRetrySeconds));
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason){g_testerDealExport.Finalize();EventKillTimer();if(StringLen(InpConfigSyncEndpoint)>0)EventKillTimer();g_execAudit.Log("DEINIT",StringFormat("reason=%d",reason));if(g_panelInitialized)g_controlPanel.Destroy();g_publisher.Deinit();g_subscribers.Deinit();g_store.Deinit();}
void OnTimer()
  {
   datetime now=TimeCurrent();
   // Use local terminal time for the refresh cadence: TimeCurrent can stop
   // advancing when the market is closed. A failed refresh must never clear
   // the in-memory halt.
   datetime localNow=TimeLocal();
   if(g_emergencyStop && localNow-g_lastEmergencyLatchRefresh>=60)
     {
      g_lastEmergencyLatchRefresh=localNow;
      ResetLastError();
      datetime latchWriteTime=GlobalVariableSet(EmergencyStopGlobalKey(),1.0);
      int latchWriteError=GetLastError();
      GlobalVariablesFlush();
      bool latchReadBack=(latchWriteTime>0 &&
                          GlobalVariableCheck(EmergencyStopGlobalKey()) &&
                          GlobalVariableGet(EmergencyStopGlobalKey())>0.5);
      if(!latchReadBack)
        {
         g_execAudit.Log("EMERGENCY_STOP_PERSIST_FAILED",
                         StringFormat("periodic persistent stop latch refresh failed; err=%d; in-memory halt remains active",latchWriteError));
         Print("CRITICAL: MidasTouch stop remains active in memory, but persistent restart latch refresh failed.");
        }
     }
   if(!(bool)MQLInfoInteger(MQL_TESTER) &&
      InpEnableExecution && InpRequireExecutionLedger &&
      (!g_executionLedgerHealthy || !g_executionLedger.AdmissionReady()) &&
      localNow-g_lastLedgerReconcileAttempt>=MathMax(10,InpExecutionLedgerRetrySeconds))
     {
      // Retry cadence uses local terminal time so recovery continues while the market is closed.
      g_lastLedgerReconcileAttempt=localNow;
      // Reopen admission only after fresh authenticated DB health and complete broker/history reconciliation.
      g_executionLedgerHealthy=g_executionLedger.CheckHealth() && ReconcileBrokerStateSnapshot();
      if(g_executionLedgerHealthy) g_executionLedger.MarkReconciled();
      if(g_executionLedgerHealthy)
         g_execAudit.Log("EXECUTION_LEDGER_RECOVERED","broker snapshot and restart history reconciliation succeeded; new entries re-enabled");
     }
   if(StringLen(InpConfigSyncEndpoint)>0 &&
      now-g_lastConfigSyncPoll>=MathMax(60,InpConfigSyncPollMinutes*60))
     {
      g_configSync.Poll();
      g_lastConfigSyncPoll=now;
     }
  }
void CheckSignalLifecycle(double atr){if(g_lifecycleDecisionId==0)return;bool filled;double fillPrice;datetime fillTime;int barsToFill;if(!g_tracker.GetFillState(g_lifecycleCreationTime,g_lifecycleDecisionId,filled,fillPrice,fillTime,barsToFill)){g_lifecycleDecisionId=0;return;}if(filled){g_lifecycleDecisionId=0;return;}bool buy=g_lifecycleSetup.type==ORDER_TYPE_BUY;int barsSince=iBarShift(_Symbol,_Period,g_lifecycleCreationTime,false);if(barsSince>=InpSignalExpiryBars){if(g_lifecycleStatus!="expired"){g_publisher.PublishStatusUpdate(g_lifecycleDecisionId,"expired",StringFormat("Unfilled for %d execution bars",barsSince));g_lifecycleStatus="expired";}g_lifecycleDecisionId=0;return;}double opposite=g_scoring.CalculateConfidence(!buy);if(opposite>=InpInvalidateOpposingConfidence){if(g_lifecycleStatus!="invalidated"){g_publisher.PublishStatusUpdate(g_lifecycleDecisionId,"invalidated",StringFormat("Opposing confidence %.0f",opposite));g_lifecycleStatus="invalidated";}g_lifecycleDecisionId=0;return;}if(atr>0){double entry=ResolveExecutionEntry(g_lifecycleSetup);double price=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);double drift=MathAbs(price-entry)/atr;bool wrong=buy?(price>entry):(price<entry);if(wrong&&drift>=InpSignalStaleChaseATR){if(g_lifecycleStatus!="stale"){g_publisher.PublishStatusUpdate(g_lifecycleDecisionId,"stale",StringFormat("Price drifted %.2f ATR past entry",drift));g_lifecycleStatus="stale";}}else if(g_lifecycleStatus=="stale"&&drift<InpSignalStaleChaseATR*0.5){g_publisher.PublishStatusUpdate(g_lifecycleDecisionId,"valid","Price returned toward entry");g_lifecycleStatus="valid";}}}
void OnTick(){g_testerDealExport.ObserveSpread(_Symbol);g_monitor.OnTickCheck();g_dailyTradeTarget.OnTick();g_pool.DetectAll();if(g_chartCtx==NULL||!g_chartCtx.candles.IsReady())return;double atr=g_chartCtx.candles.GetATR(0);g_positions.OnTick(atr);g_orders.Prune();g_riskGuard.OnTick();RefreshTradeControlPanel();if(g_emergencyStop)return;if(InpPublishLifecycleUpdates)CheckSignalLifecycle(atr);datetime barTime=iTime(_Symbol,_Period,0);bool isNewBar=(barTime!=g_lastBarTime);g_lastBarTime=barTime;if(!isNewBar)return;if(InpTrackOutcomes)g_tracker.Update(g_chartCtx);string haltReason;if(g_riskGuard.IsHardHalted(haltReason))return;if(g_riskGuard.IsDailyLossLimitHit(haltReason))return;string newsReason;if(InpUseNewsFilter&&g_newsFilter.IsLocked(newsReason))return;if(!IsConfiguredSessionAllowed()){if(TimeCurrent()-g_lastSessionBlockLog>=900){g_execAudit.Log("SESSION_BLOCK","new automated entries suppressed outside configured session windows");g_lastSessionBlockLog=TimeCurrent();}return;}g_dailyTradeTarget.LogSearchProgress();TradeSetup buySetup=g_decision.GenerateBuySetup();TradeSetup sellSetup=g_decision.GenerateSellSetup();if(InpLogSignals){if(buySetup.reasons.selected_strategy==STRATEGY_SMC)g_logger.LogSMCStructure(buySetup,_Symbol,InpFVGTF);if(sellSetup.reasons.selected_strategy==STRATEGY_SMC)g_logger.LogSMCStructure(sellSetup,_Symbol,InpFVGTF);}
   // Evaluate both sides independently. The MTF layer adjusts confidence only;
   // it does not hard-block every countertrend setup or manufacture a trade.
   if(InpEnableTopDownMTF)
     {
      if(!g_topDownMTF.Evaluate())
        {
         g_execAudit.Log("MTF_CONTEXT_UNAVAILABLE","top-down MTF enabled but one or more D1/H4/H1/M30/M15/M5/M1 contexts are not ready; automated candidate suppressed");
         return;
        }
      g_topDownMTF.AdjustSetup(buySetup);
      g_topDownMTF.AdjustSetup(sellSetup);
      if(InpLogSignals) g_execAudit.Log("MTF_CONTEXT",g_topDownMTF.Summary());
     }
   TradeSetup chosen;ZeroMemory(chosen);double delta=buySetup.confidence-sellSetup.confidence;if(buySetup.active&&sellSetup.active){if(delta>InpMinDirectionalAdvantage){if(g_risk.ValidateSetup(buySetup,InpMinRiskReward,InpMaxSLDistanceATR,atr))chosen=buySetup;}else if(-delta>InpMinDirectionalAdvantage){if(g_risk.ValidateSetup(sellSetup,InpMinRiskReward,InpMaxSLDistanceATR,atr))chosen=sellSetup;}else{g_execAudit.Log("DIRECTIONAL_CONFLICT",StringFormat("BUY/SELL confidence difference %.3f does not exceed required directional advantage %.3f; neither side selected",MathAbs(delta),InpMinDirectionalAdvantage));}}else if(buySetup.active){if(g_risk.ValidateSetup(buySetup,InpMinRiskReward,InpMaxSLDistanceATR,atr))chosen=buySetup;}else if(sellSetup.active){if(g_risk.ValidateSetup(sellSetup,InpMinRiskReward,InpMaxSLDistanceATR,atr))chosen=sellSetup;}if(!chosen.active||chosen.creation_time==g_lastLoggedTime)return;g_lastLoggedTime=chosen.creation_time;chosen.calibrated_probability=g_tracker.GetCalibratedProbability(chosen.confidence,chosen.calibration_sample,chosen.calibration_has_enough_data);if(InpLogSignals){ENUM_TREND_STATE t=g_trendCtx.trend.GetCurrentTrend();g_logger.LogSetup(chosen,_Symbol,InpFVGTF,EnumToString(t));}TradeDecisionRecord decision=g_router.Decide(chosen);g_execAudit.Log("ACCURACY_POLICY_V3_SHADOW",StringFormat("%s;router_action=%s;router_reason=%s",AccuracyPolicyV3ShadowSummary(chosen),TradePolicyToString(decision.action),decision.reason),decision.decision_id);g_execAudit.Log("DECISION",StringFormat("automated candidate action=%s confidence=%.1f reason=%s",TradePolicyToString(decision.action),decision.confidence,decision.reason),decision.decision_id,0,0.0,ResolveExecutionEntry(chosen),chosen.stop_loss,chosen.final_tp);decision.timeframe=_Period;decision.decision_schema_version=InpDecisionSchemaVersion;decision.strategy_version=InpStrategyVersion;decision.model_version=InpModelVersion;decision.calibration_version=InpCalibrationVersion;decision.feature_schema_version=InpFeatureSchemaVersion;decision.environment_schema_version=InpEnvironmentSchemaVersion;decision.weight_version=InpWeightSetVersion;decision.environment_key=g_environmentMemory.Key(chosen.reasons);decision.spread_points=chosen.reasons.spread_points;decision.decision_fingerprint=DecisionFingerprintFor(decision);if(InpTrackOutcomes)g_tracker.AddSetup(chosen,decision.decision_id,decision.decision_fingerprint);if(!decision.valid||decision.action==POLICY_IGNORE)return;if(!g_store.Save(decision)){PrintFormat("MedisTouch EA: decision #%I64d rejected — durable DecisionStore write failed.",decision.decision_id);return;}if(decision.action==POLICY_EXECUTE_ONLY||decision.action==POLICY_EXECUTE_AND_SIGNAL){string opposingDirectionReason;if((InpRequireExecutionLedger && !g_executionLedger.Ready()) || (g_executionLedger.Ready() && !g_executionLedgerHealthy)){g_execAudit.Log("EXECUTION_LEDGER_NOT_READY","automated trade blocked until bridge admission and broker reconciliation are healthy",decision.decision_id);}else if(IsNettingOrExchangeAccount() && HasAnyChartSymbolExposure()){g_execAudit.Log("AUTOMATED_BLOCKED_NETTING_EXPOSURE",StringFormat("decision #%I64d suppressed: same-symbol position or pending order already exists on netting/exchange account",decision.decision_id),decision.decision_id);}else if(HasForeignChartSymbolExposure()){g_execAudit.Log("AUTOMATED_BLOCKED_FOREIGN_EXPOSURE",StringFormat("decision #%I64d suppressed: a manual/other-EA position or pending order on this symbol is outside this instance's risk-attribution boundary",decision.decision_id),decision.decision_id);}else if(!CanOpenDirectionWithExposure(decision.setup.type,opposingDirectionReason)){g_execAudit.Log("AUTOMATED_BLOCKED_OPPOSING_EXPOSURE",StringFormat("decision #%I64d suppressed: %s",decision.decision_id,opposingDirectionReason),decision.decision_id);}else{string smallRiskReason;if(!SmallAccountRiskAdmission(decision.reduce_risk,smallRiskReason)){g_execAudit.Log("AUTOMATED_BLOCKED_SMALL_ACCOUNT_RISK_ADMISSION",smallRiskReason,decision.decision_id);return;}int availableSlots=EffectiveMaxOpenTrades()-g_orders.OpenCount();if(availableSlots<0)availableSlots=0;if(availableSlots==0){g_execAudit.Log("AUTOMATED_BLOCKED_ADAPTIVE_OPEN_TRADE_CAP",StringFormat("open=%d adaptive-cap=%d; expansion requires every existing position to be profitable with a break-even-or-better stop",g_orders.OpenCount(),EffectiveMaxOpenTrades()),decision.decision_id);return;}MultiTradePlan plan;bool planOk=g_multiTrade.Build(decision.setup,availableSlots,plan);if(!planOk){PrintFormat("MedisTouch EA: decision #%I64d rejected — multi-trade plan construction failed.",decision.decision_id);return;}double entry=ResolveExecutionEntry(chosen);double legLots[3];double legRisk[3];for(int leg=0;leg<3;leg++){legLots[leg]=0.0;legRisk[leg]=0.0;}bool sizingOk=true;for(int leg=0;leg<plan.legCount;leg++){double fraction=plan.riskFraction[leg];bool exceeded=false;legLots[leg]=g_risk.CalculateLotSize(_Symbol,g_activeRiskLimits.riskPercentPerTrade*fraction,entry,chosen.stop_loss,decision.reduce_risk,InpAllowMinLotOverride,exceeded,g_riskGuard.SizeMultiplier());if(legLots[leg]<=0.0){sizingOk=false;break;}legRisk[leg]=g_risk.RiskAmountForLots(_Symbol,legLots[leg],entry,chosen.stop_loss);}if(!sizingOk){PrintFormat("MedisTouch EA: decision #%I64d skipped — one or more execution legs cannot satisfy broker lot/risk constraints.",decision.decision_id);return;}double totalProposedRisk=0.0;for(int leg=0;leg<plan.legCount;leg++)totalProposedRisk+=legRisk[leg];if(g_activeRiskLimits.profile==ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT){double sizingEquity=AccountInfoDouble(ACCOUNT_EQUITY);double achievedRiskPercent=(sizingEquity>0.0?totalProposedRisk/sizingEquity*100.0:0.0);if(sizingEquity<=0.0||achievedRiskPercent+0.000001<InpSmallMinimumRiskPercentPerTrade){g_execAudit.Log("AUTOMATED_BLOCKED_BELOW_MINIMUM_RISK",StringFormat("combined execution plan yields %.2f%% planned risk, below configured minimum %.2f%%",achievedRiskPercent,InpSmallMinimumRiskPercentPerTrade),decision.decision_id,0,0.0,entry,chosen.stop_loss,chosen.final_tp);return;}}string block;if(!g_portfolio.AllowNewTradeBatch(_Symbol,totalProposedRisk,plan.legCount,block)){PrintFormat("MedisTouch EA: decision #%I64d blocked — %s",decision.decision_id,block);return;}ulong tickets[3];bool submittedAny=false;double maxDeviation=InpMaxEntryDeviationATR*atr;for(int leg=0;leg<plan.legCount;leg++){TradeDecisionRecord legDecision=decision;legDecision.setup.final_tp=plan.target[leg];legDecision.reason+=StringFormat("; multi-trade leg %d/%d (%s)",leg+1,plan.legCount,plan.label[leg]);string ledgerRequestId="";if(!PrepareLedgerForSubmit(legDecision,leg,legRisk[leg],atr,ledgerRequestId)){g_execAudit.Log("AUTOMATED_LEDGER_BLOCKED","bridge did not acknowledge pre-send reservation; this leg was not sent",decision.decision_id,0,legLots[leg],entry,chosen.stop_loss,plan.target[leg]);continue;}ulong ticket=0;if(g_orders.Submit(legDecision,legLots[leg],InpUseMarketOrders,maxDeviation,ticket,leg)){submittedAny=true;tickets[leg]=ticket;if(StringLen(ledgerRequestId)>0)MarkLedgerSubmissionAccepted(ledgerRequestId);if(!g_store.SaveExecution(decision.decision_id,legLots[leg],ticket,leg,plan.target[leg])){PrintFormat("CRITICAL: decision #%I64d leg %d executed but execution record was not durably persisted.",decision.decision_id,leg);g_execAudit.Log("CRITICAL_EXECUTION_RECORD_FAILURE","automated order submitted but execution persistence failed",decision.decision_id,ticket,legLots[leg],entry,chosen.stop_loss,plan.target[leg]);}else g_execAudit.Log("ORDER_SUBMITTED",StringFormat("automated leg %d/%d",leg+1,plan.legCount),decision.decision_id,ticket,legLots[leg],entry,chosen.stop_loss,plan.target[leg]);}else{if(StringLen(ledgerRequestId)>0)MarkLedgerSubmissionAmbiguous(ledgerRequestId);g_monitor.NotifyBrokerReject();g_execAudit.Log("ORDER_REJECTED","automated broker/order-manager submission failed; ledger reservation retained for broker reconciliation",decision.decision_id,0,legLots[leg],entry,chosen.stop_loss,plan.target[leg]);}}if(!submittedAny)PrintFormat("MedisTouch EA: decision #%I64d rejected by broker on every requested execution leg.",decision.decision_id);}}if(decision.action==POLICY_SIGNAL_ONLY||decision.action==POLICY_EXECUTE_AND_SIGNAL){g_publisher.Publish(decision);g_lifecycleDecisionId=decision.decision_id;g_lifecycleCreationTime=chosen.creation_time;g_lifecycleSetup=chosen;g_lifecycleStatus="valid";}}
// Persistent per-symbol/per-magic emergency latch. A normal terminal restart
// does not silently re-enable order entry after the operator presses STOP.
string EmergencyStopGlobalKey()
  {
   string key="MIDAS_STOP_"+_Symbol+"_"+IntegerToString((long)InpMagicNumber);
   StringReplace(key,".","_");
   StringReplace(key,"#","_");
   if(StringLen(key)>63) key=StringSubstr(key,0,63);
   return key;
  }

int ParseSessionMinute(const string value)
  {
   string fields[];
   ushort colon=StringGetCharacter(":",0);
   if(StringSplit(value,colon,fields)!=2) return -1;
   int hour=(int)StringToInteger(fields[0]);
   int minute=(int)StringToInteger(fields[1]);
   if(hour<0 || hour>23 || minute<0 || minute>59) return -1;
   return hour*60+minute;
  }

bool SessionWindowContains(int nowMinute,int startMinute,int endMinute)
  {
   if(startMinute<0 || endMinute<0 || startMinute==endMinute) return false;
   if(startMinute<endMinute) return (nowMinute>=startMinute && nowMinute<endMinute);
   // A window such as 22:00-02:00 crosses midnight.
   return (nowMinute>=startMinute || nowMinute<endMinute);
  }

bool IsConfiguredSessionAllowed()
  {
   if(!InpUseCustomTradingSessions) return true;
   datetime now=TimeTradeServer();
   if(now<=0) now=TimeCurrent();
   MqlDateTime parts;
   TimeToStruct(now,parts);
   int minuteOfDay=parts.hour*60+parts.min;
   if(InpSession1Enabled)
     {
      int start=ParseSessionMinute(InpSession1Start),finish=ParseSessionMinute(InpSession1End);
      if(SessionWindowContains(minuteOfDay,start,finish)) return true;
     }
   if(InpSession2Enabled)
     {
      int start=ParseSessionMinute(InpSession2Start),finish=ParseSessionMinute(InpSession2End);
      if(SessionWindowContains(minuteOfDay,start,finish)) return true;
     }
   if(InpSession3Enabled)
     {
      int start=ParseSessionMinute(InpSession3Start),finish=ParseSessionMinute(InpSession3End);
      if(SessionWindowContains(minuteOfDay,start,finish)) return true;
     }
   // Fail closed if enabled session definitions are invalid or no valid
   // windows exist. Existing DST-aware session policy is unchanged when off.
   return false;
  }

string ControlPanelSessionStatus()
  {
   bool customAllowed=IsConfiguredSessionAllowed();
   bool dstAllowed=g_operatorSessionFilter.IsAllowed();
   if(InpUseCustomTradingSessions && InpUseSessionFilter)
      return (customAllowed && dstAllowed) ? "CUSTOM + DST OPEN" : "SESSION BLOCKED";
   if(InpUseCustomTradingSessions)
      return customAllowed ? "CUSTOM OPEN" : "CUSTOM CLOSED";
   if(InpUseSessionFilter)
      return dstAllowed ? "DST SESSION OPEN" : "DST SESSION CLOSED";
   return "ALL HOURS";
  }

void RefreshTradeControlPanel()
  {
   if(!g_panelInitialized) return;
   int count=0;
   double floating=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      count++;
      floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
     }
   g_controlPanel.Refresh(count,floating,InpEnableDynamicStop,g_emergencyStop,ControlPanelSessionStatus());
  }

int EffectiveMaxOpenTrades()
  {
   int cap=g_activeRiskLimits.maxOpenTrades;
   if(cap<1) return 0;
   if(g_activeRiskLimits.profile!=ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT)
      return cap;

   // Small-account mode starts with one position. It earns one additional slot
   // only when every currently tracked chart-symbol position is net-positive
   // on floating P&L and its stop has locked at least breakeven. Unfilled,
   // untracked or ambiguous orders prevent expansion. Aggregate portfolio risk
   // and the configured cap remain independent admission gates.
   int tracked=g_orders.OpenCount();
   int activePositions=0;
   bool allSecuredAndProfitable=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;

      activePositions++;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double stop=PositionGetDouble(POSITION_SL);
      double floating=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      ENUM_POSITION_TYPE direction=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool stopProtected=(stop>0.0 && entry>0.0 &&
                          ((direction==POSITION_TYPE_BUY && stop>=entry) ||
                           (direction==POSITION_TYPE_SELL && stop<=entry)));
      if(!stopProtected || floating<=0.0)
         allSecuredAndProfitable=false;
     }

   if(tracked<=0)
      return (activePositions>0 ? 0 : 1);
   if(activePositions!=tracked)
      return (tracked<cap ? tracked : cap);
   if(!allSecuredAndProfitable)
      return (tracked<cap ? tracked : cap);
   if(tracked>=cap)
      return cap;
   return tracked+1;
  }

bool SmallAccountRiskAdmission(bool reduceRisk,string &reasonOut)
  {
   reasonOut="";
   if(g_activeRiskLimits.profile!=ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT)
      return true;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!MathIsValidNumber(equity) || equity<=0.0)
     { reasonOut="small-account risk admission blocked: account equity is invalid"; return false; }

   double requestedRisk=g_activeRiskLimits.riskPercentPerTrade;
   if(reduceRisk) requestedRisk*=0.5;
   requestedRisk*=g_riskGuard.SizeMultiplier();
   if(!MathIsValidNumber(requestedRisk) ||
      requestedRisk+0.000001<InpSmallMinimumRiskPercentPerTrade)
     {
      reasonOut=StringFormat("risk reduction would take planned risk %.2f%% below the configured %.2f%% minimum; trade skipped rather than silently violating the minimum",
                             requestedRisk,InpSmallMinimumRiskPercentPerTrade);
      return false;
     }

   // Keep sufficient headroom for a full stop-loss under the configured daily
   // and peak-equity limits. This is intentionally conservative: a new entry
   // is blocked when its planned risk can exceed the remaining loss allowance.
   double dailyHeadroom=g_activeRiskLimits.maxDailyLossPercent-g_riskGuard.CurrentDailyLossPercent();
   double drawdownHeadroom=g_activeRiskLimits.maxDrawdownPercent-g_riskGuard.CurrentDrawdownPercent();
   if(dailyHeadroom+0.000001<requestedRisk)
     {
      reasonOut=StringFormat("remaining daily-loss headroom %.2f%% is below planned risk %.2f%%",
                             dailyHeadroom,requestedRisk);
      return false;
     }
   if(drawdownHeadroom+0.000001<requestedRisk)
     {
      reasonOut=StringFormat("remaining peak-drawdown headroom %.2f%% is below planned risk %.2f%%",
                             drawdownHeadroom,requestedRisk);
      return false;
     }
   return true;
  }

void CloseAllManagedExposure(const string reason)
  {
   int cancelled=0,closed=0,failed=0;
   // Cancel orders represented in the state machine first.
   for(int i=g_orders.Total()-1;i>=0;i--)
     {
      ENUM_TRADE_STATE state=g_orders.StateAt(i);
      if(state!=TS_PENDING && state!=TS_WAITING) continue;
      ulong ticket=g_orders.TicketAt(i);
      if(ticket>0 && g_orders.CancelPendingAt(i))
        {
         cancelled++;
         g_execAudit.Log("PENDING_CANCEL",reason,g_orders.DecisionAt(i).decision_id,ticket);
        }
     }
   // Include matching broker pending orders not present in the local store.
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong order=OrderGetTicket(i);
      if(order==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      if(g_broker.CancelOrder(order))
        {
         cancelled++;
         g_execAudit.Log("PENDING_CANCEL",reason,0,order);
        }
      else failed++;
     }
   // Scope is deliberately this chart symbol + this EA's magic number.
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      double volume=PositionGetDouble(POSITION_VOLUME);
      double price=PositionGetDouble(POSITION_PRICE_CURRENT);
      if(g_broker.CloseFull(ticket))
        {
         closed++;
         g_execAudit.Log("POSITION_CLOSE",reason,g_orders.DecisionIdForTicket(ticket),ticket,volume,price);
        }
      else
        {
         failed++;
         g_execAudit.Log("POSITION_CLOSE_FAILED",reason,g_orders.DecisionIdForTicket(ticket),ticket,volume,price);
        }
     }
   g_execAudit.Log("CLOSE_ALL_SUMMARY",StringFormat("reason=%s closed=%d cancelled=%d failed=%d",reason,closed,cancelled,failed));
   RefreshTradeControlPanel();
  }

void EmergencyStop()
  {
   // Halt the current EA instance first. A persistence failure must never re-enable
   // entries in this process, and must be unmistakable to the operator.
   g_emergencyStop=true;
   // Start/restart the timer even if optional config-sync or ledger polling is off.
   ResetLastError();
   bool refreshTimerStarted=EventSetTimer(MathMax(10,InpExecutionLedgerRetrySeconds));
   int refreshTimerError=GetLastError();
   if(!refreshTimerStarted)
     {
      g_execAudit.Log("EMERGENCY_STOP_REFRESH_TIMER_FAILED",
                      StringFormat("periodic stop-latch refresh timer failed; err=%d; in-memory halt remains active",refreshTimerError));
      Print("CRITICAL: MidasTouch stop is active, but periodic latch refresh could not start.");
      Alert("CRITICAL: MIDAS EMERGENCY STOP REFRESH TIMER NOT RUNNING");
     }
   ResetLastError();
   datetime stopWriteTime=GlobalVariableSet(EmergencyStopGlobalKey(),1.0);
   int stopWriteError=GetLastError();
   GlobalVariablesFlush();
   g_lastEmergencyLatchRefresh=TimeLocal();

   bool stopLatchVerified=(stopWriteTime>0 &&
                           GlobalVariableCheck(EmergencyStopGlobalKey()) &&
                           GlobalVariableGet(EmergencyStopGlobalKey())>0.5);
   if(!stopLatchVerified)
     {
      g_execAudit.Log("EMERGENCY_STOP_PERSIST_FAILED",
                      StringFormat("persistent stop latch write/read-back failed; err=%d; in-memory halt remains active",stopWriteError));
      Print("CRITICAL: MidasTouch emergency stop is active in memory, but its persistent restart latch could not be verified. Do not restart or resume until storage is checked.");
      Alert("CRITICAL: MIDAS EMERGENCY STOP RESTART LATCH NOT VERIFIED");
     }
   else
     {
      g_execAudit.Log("EMERGENCY_STOP",
                      "latched; global-variable flush requested and read-back verified; new entries blocked and managed exposure is being flattened");
     }
   CloseAllManagedExposure("emergency-stop");
  }

bool HasManagedExposure()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) return true;
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)==_Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagicNumber) return true;
     }
   return false;
  }

void ResumeTrading()
  {
   if(HasManagedExposure())
     {
      g_execAudit.Log("EMERGENCY_RESUME_BLOCKED","managed positions or pending orders remain open; stop latch retained");
      Print("MedisTouch: RESUME refused — close/verify all positions and pending orders for this symbol/magic first.");
      return;
     }
   bool stopLatchClearOK=true;
   int stopLatchClearError=0;
   if(GlobalVariableCheck(EmergencyStopGlobalKey()))
     {
      ResetLastError();
      stopLatchClearOK=GlobalVariableDel(EmergencyStopGlobalKey());
      stopLatchClearError=GetLastError();
     }
   // Flush the cleared state before allowing entry logic to resume. If deletion or
   // read-back verification fails, retain the in-memory halt and fail closed.
   GlobalVariablesFlush();
   if(!stopLatchClearOK || GlobalVariableCheck(EmergencyStopGlobalKey()))
     {
      g_emergencyStop=true;
      g_execAudit.Log("EMERGENCY_RESUME_FAILED",
                      StringFormat("persistent stop latch clear failed; err=%d; in-memory halt retained",stopLatchClearError));
      Print("CRITICAL: RESUME refused — the persistent emergency-stop latch could not be cleared and verified.");
      Alert("CRITICAL: MIDAS EMERGENCY STOP STILL LATCHED");
      return;
     }
   g_emergencyStop=false;
   g_execAudit.Log("EMERGENCY_RESUME","operator cleared persistent emergency latch after exposure check; cleared state flushed and absent on read-back");
   if(!InpShowTradeControlPanel && g_panelInitialized)
     {
      g_controlPanel.Destroy();
      g_panelInitialized=false;
     }
   RefreshTradeControlPanel();
  }

bool IsRetailHedgingAccount()
  {
   return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
  }

bool IsNettingOrExchangeAccount()
  {
   return !IsRetailHedgingAccount();
  }

bool HasOpposingChartSymbolExposure(ENUM_ORDER_TYPE desiredType)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      ENUM_POSITION_TYPE current=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(MidasIsOpposingPositionDirection(desiredType,current))
         return true;
     }

   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0)continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)continue;
      ENUM_ORDER_TYPE current=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(MidasIsOpposingOrderDirection(desiredType,current))return true;
     }
   return false;
  }

bool CanOpenDirectionWithExposure(ENUM_ORDER_TYPE desiredType,string &reasonOut)
  {
   return MidasConcurrentOpposingPolicyAllows(
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE),
      HasOpposingChartSymbolExposure(desiredType),
      InpAllowConcurrentOpposingPositions,reasonOut);
  }

// Exposure from a manual terminal trade or a different EA magic is not covered
// by this instance's portfolio ledger. Fail closed on that symbol rather than
// allowing the explicit hedging switch to admit unaccounted risk.
bool HasForeignChartSymbolExposure()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)return true;
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0)continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)return true;
     }
   return false;
  }

// Netting/exchange accounts aggregate all activity for a symbol into one position.
// Manual BUY/SELL must not accidentally net, reverse, or inherit another trade's identity.
bool HasAnyChartSymbolExposure()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)==_Symbol) return true;
     }
   return false;
  }

void ManualMarketEntry(bool isBuy)
  {
   string side=isBuy ? "BUY" : "SELL";
   if(g_emergencyStop) { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: emergency stop is latched"); return; }
   if(!InpEnableExecution) { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: InpEnableExecution=false"); return; }
   if(IsNettingOrExchangeAccount() && HasAnyChartSymbolExposure())
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: netting/exchange account already has same-symbol position or pending order; resolve it before another manual entry"); return; }
   if(HasForeignChartSymbolExposure())
     { g_execAudit.Log("MANUAL_BLOCKED_FOREIGN_EXPOSURE",side+" rejected: manual/other-EA exposure on this symbol is outside this instance's portfolio-risk attribution boundary"); return; }
   string opposingDirectionReason;
   ENUM_ORDER_TYPE manualDirection=isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CanOpenDirectionWithExposure(manualDirection,opposingDirectionReason))
     { g_execAudit.Log("MANUAL_BLOCKED_OPPOSING_EXPOSURE",side+" rejected: "+opposingDirectionReason); return; }
   if(!g_operatorSessionFilter.IsAllowed()) { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: outside DST-aware trading sessions"); return; }
   if(!IsConfiguredSessionAllowed()) { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: outside configured server-time sessions"); return; }
   string haltReason;
   if(g_riskGuard.IsHardHalted(haltReason) || g_riskGuard.IsDailyLossLimitHit(haltReason))
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected by risk guard: "+haltReason); return; }
   string newsReason;
   if(InpUseNewsFilter && g_newsFilter.IsLocked(newsReason))
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected by news filter: "+newsReason); return; }
   if(g_orders.OpenCount()>=EffectiveMaxOpenTrades())
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: adaptive open-trade cap reached; existing positions must be profitable and stop-protected before expansion"); return; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: no current tick"); return; }
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double atr=(g_chartCtx!=NULL ? g_chartCtx.candles.GetATR(0) : 0.0);
   if(point<=0.0 || atr<=0.0 || InpManualStopATR<=0.0 || InpManualRiskReward<InpMinRiskReward+0.3)
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: invalid point/ATR/manual risk parameters"); return; }
   double entry=isBuy ? tick.ask : tick.bid;
   double spreadPoints=(tick.ask-tick.bid)/point;
   if(InpMaxSpreadPoints>0 && spreadPoints>InpMaxSpreadPoints)
     { g_execAudit.Log("MANUAL_BLOCKED",StringFormat("%s spread %.1f exceeds limit %d",side,spreadPoints,InpMaxSpreadPoints)); return; }

   double riskDistance=MathMax(atr*InpManualStopATR,spreadPoints*point*MathMax(1.0,InpMinStopSpreadMult));
   double stop=isBuy ? entry-riskDistance : entry+riskDistance;
   double buffer=MathMin(riskDistance*0.20,MathMax(point*2.0,riskDistance*0.05));
   TradeSetup setup;
   ZeroMemory(setup);
   setup.type=isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   setup.entry_top=entry;
   setup.entry_bottom=entry;
   setup.stop_loss=NormalizeDouble(stop,_Digits);
   setup.invalidation=NormalizeDouble(isBuy ? stop+buffer : stop-buffer,_Digits);
   double risk=MathAbs(entry-setup.stop_loss);
   double tp1R=InpMinRiskReward+0.1; // CRiskEngine validates R:R against TP1, not final_tp.
   double tp2R=(tp1R+InpManualRiskReward)*0.5;
   setup.tp1=NormalizeDouble(isBuy ? entry+risk*tp1R : entry-risk*tp1R,_Digits);
   setup.tp2=NormalizeDouble(isBuy ? entry+risk*tp2R : entry-risk*tp2R,_Digits);
   setup.final_tp=NormalizeDouble(isBuy ? entry+risk*InpManualRiskReward : entry-risk*InpManualRiskReward,_Digits);
   setup.confidence=100.0;
   setup.creation_time=TimeCurrent();
   setup.active=true;
   setup.reasons.selected_strategy=STRATEGY_NONE;
   setup.reasons.session_ok=true;
   if(!g_risk.ValidateSetup(setup,InpMinRiskReward,InpMaxSLDistanceATR,atr))
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected by stop/target validation",0,0,0.0,entry,setup.stop_loss,setup.final_tp); return; }

   TradeDecisionRecord decision;
   ZeroMemory(decision);
   decision.decision_id=g_router.AllocateId();
   decision.symbol=_Symbol;
   decision.setup=setup;
   decision.action=POLICY_EXECUTE_ONLY;
   decision.valid=true;
   decision.confidence=setup.confidence;
   decision.spread_points=spreadPoints;
   decision.decided_time=TimeCurrent();
   decision.reason="operator chart control";
   decision.timeframe=_Period;
   decision.decision_schema_version=InpDecisionSchemaVersion;
   decision.strategy_version=InpStrategyVersion;
   decision.model_version=InpModelVersion;
   decision.calibration_version=InpCalibrationVersion;
   decision.feature_schema_version=InpFeatureSchemaVersion;
   decision.environment_schema_version=InpEnvironmentSchemaVersion;
   decision.weight_version=InpWeightSetVersion;
   decision.environment_key="manual_operator";
   decision.decision_fingerprint=DecisionFingerprintFor(decision);

   bool exceededMinLot=false;
   string smallRiskReason;
   if(!SmallAccountRiskAdmission(decision.reduce_risk,smallRiskReason))
     {
      g_execAudit.Log("MANUAL_BLOCKED_SMALL_ACCOUNT_RISK_ADMISSION",smallRiskReason,decision.decision_id,0,0.0,entry,setup.stop_loss,setup.final_tp);
      return;
     }
   double lots=g_risk.CalculateLotSize(_Symbol,g_activeRiskLimits.riskPercentPerTrade,entry,setup.stop_loss,
                                      decision.reduce_risk,InpAllowMinLotOverride,exceededMinLot,
                                      g_riskGuard.SizeMultiplier());
   if(lots<=0.0)
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: broker lot/risk sizing returned zero",decision.decision_id,0,0.0,entry,setup.stop_loss,setup.final_tp); return; }
   double proposedRisk=g_risk.RiskAmountForLots(_Symbol,lots,entry,setup.stop_loss);
   if(g_activeRiskLimits.profile==ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT)
     {
      double sizingEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      double achievedRiskPercent=(sizingEquity>0.0?proposedRisk/sizingEquity*100.0:0.0);
      if(sizingEquity<=0.0 || achievedRiskPercent+0.000001<InpSmallMinimumRiskPercentPerTrade)
        {
         g_execAudit.Log("MANUAL_BLOCKED_BELOW_MINIMUM_RISK",
                         StringFormat("broker volume step yields %.2f%% planned risk, below configured minimum %.2f%%",
                                      achievedRiskPercent,InpSmallMinimumRiskPercentPerTrade),
                         decision.decision_id,0,lots,entry,setup.stop_loss,setup.final_tp);
         return;
        }
     }
   string portfolioReason;
   if(!g_portfolio.AllowNewTradeBatch(_Symbol,proposedRisk,1,portfolioReason))
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected by portfolio risk guard: "+portfolioReason,decision.decision_id,0,lots,entry,setup.stop_loss,setup.final_tp); return; }
   if(!g_store.Save(decision))
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: durable decision write failed",decision.decision_id,0,lots,entry,setup.stop_loss,setup.final_tp); return; }
   // Deliberate operator entries are execution-audited but excluded from strategy calibration
   // and EnvironmentStrategyMemory, preventing manual discretion from contaminating model evidence.

   string ledgerRequestId="";
   if(!PrepareLedgerForSubmit(decision,0,proposedRisk,atr,ledgerRequestId))
     { g_execAudit.Log("MANUAL_BLOCKED",side+" rejected: bridge reservation or SENT state was not acknowledged",decision.decision_id,0,lots,entry,setup.stop_loss,setup.final_tp); return; }
   ulong ticket=0;
   double maxDeviation=InpMaxEntryDeviationATR*atr;
   if(!g_orders.Submit(decision,lots,true,maxDeviation,ticket,0))
     {
      if(StringLen(ledgerRequestId)>0) MarkLedgerSubmissionAmbiguous(ledgerRequestId);
      g_monitor.NotifyBrokerReject();
      g_execAudit.Log("MANUAL_REJECTED",side+" market request rejected by execution layer",decision.decision_id,0,lots,entry,setup.stop_loss,setup.final_tp);
      return;
     }
   if(StringLen(ledgerRequestId)>0) MarkLedgerSubmissionAccepted(ledgerRequestId);
   if(!g_store.SaveExecution(decision.decision_id,lots,ticket,0,setup.final_tp))
      g_execAudit.Log("CRITICAL_EXECUTION_RECORD_FAILURE","manual order submitted but execution persistence failed",decision.decision_id,ticket,lots,entry,setup.stop_loss,setup.final_tp);
   else
      g_execAudit.Log("MANUAL_ORDER_SUBMITTED",side+" chart button",decision.decision_id,ticket,lots,entry,setup.stop_loss,setup.final_tp);
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(!g_panelInitialized || id!=CHARTEVENT_OBJECT_CLICK) return;
   int command=g_controlPanel.CommandForClick(sparam);
   if(command==PANEL_ACTION_BUY) ManualMarketEntry(true);
   else if(command==PANEL_ACTION_SELL) ManualMarketEntry(false);
   else if(command==PANEL_ACTION_CLOSE_ALL) CloseAllManagedExposure("operator-close-all");
   else if(command==PANEL_ACTION_EMERGENCY_STOP) EmergencyStop();
   else if(command==PANEL_ACTION_RESUME) ResumeTrading();
   RefreshTradeControlPanel();
  }

bool SendLedgerDealEvent(const ulong dealTicket,const ulong positionIdentifier)
  {
   if(!g_executionLedger.Ready()) return !InpRequireExecutionLedger;
   if(dealTicket==0 || positionIdentifier==0 || !HistoryDealSelect(dealTicket)) return false;

   string symbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
   if(symbol=="") return false;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
   ENUM_DEAL_TYPE dealType=(ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket,DEAL_TYPE);
   string entryType="IN";
   if(entry==DEAL_ENTRY_OUT) entryType="OUT";
   else if(entry==DEAL_ENTRY_OUT_BY) entryType="OUT_BY";
   else if(entry==DEAL_ENTRY_INOUT) entryType="INOUT";
   string dealSide=(dealType==DEAL_TYPE_BUY)?"BUY":"SELL";

   bool positionOpen=IsPositionIdentifierOpen(positionIdentifier);
   double remainingVolume=0.0;
   double riskR=0.0;
   string positionDirection=(entry==DEAL_ENTRY_IN)?dealSide:((dealSide=="BUY")?"SELL":"BUY");
   if(entry==DEAL_ENTRY_INOUT) positionDirection=dealSide;
   if(positionOpen)
     {
      ulong positionTicket=g_broker.PositionTicketForIdentifier(symbol,positionIdentifier);
      if(positionTicket==0 || !PositionSelectByTicket(positionTicket)) return false;
      long positionType=PositionGetInteger(POSITION_TYPE);
      positionDirection=(positionType==POSITION_TYPE_BUY)?"BUY":"SELL";
      remainingVolume=PositionGetDouble(POSITION_VOLUME);
      double stop=PositionGetDouble(POSITION_SL);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      if(stop<=0.0 || openPrice<=0.0 || remainingVolume<=0.0) return false;
      double riskMoney=g_risk.RiskAmountForLots(symbol,remainingVolume,openPrice,stop);
      bool stopLocked=(positionType==POSITION_TYPE_BUY && stop>=openPrice) ||
                      (positionType==POSITION_TYPE_SELL && stop<=openPrice);
      if(!RiskRFromMoney(riskMoney,riskR,stopLocked)) return false;
     }

   double volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
   double price=HistoryDealGetDouble(dealTicket,DEAL_PRICE);
   double profit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
   double commission=HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
   double swap=HistoryDealGetDouble(dealTicket,DEAL_SWAP);
   double fee=HistoryDealGetDouble(dealTicket,DEAL_FEE);
   ulong orderId=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
   string evidence=StringFormat("mt5-deal:%I64u",dealTicket);
   string requestId=g_executionLedger.RequestIdForPosition(positionIdentifier);
   return g_executionLedger.DealEvent(requestId,dealTicket,orderId,positionIdentifier,
                                      symbol,entryType,dealSide,positionDirection,
                                      volume,price,profit,commission,swap,fee,true,
                                      positionOpen,remainingVolume,riskR,0.0,evidence);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagicNumber) return;

   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   ulong positionIdentifier=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(positionIdentifier==0) return;
   // Native tester export is disabled in live/demo terminal operation.
   // Preserve raw cashflows and entry stop-risk basis for locked out-of-sample analysis.
   if(g_testerDealExport.Enabled())
     {
      ulong exportOrder=(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER);
      double entryRiskCash=0.0;
      if(entry==DEAL_ENTRY_IN && exportOrder>0 && HistoryOrderSelect(exportOrder))
        {
         double entryStop=HistoryOrderGetDouble(exportOrder,ORDER_SL);
         double entryVolume=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
         double entryPrice=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
         if(entryStop>0.0 && entryVolume>0.0 && entryPrice>0.0)
            entryRiskCash=g_risk.RiskAmountForLots(_Symbol,entryVolume,entryPrice,entryStop);
        }
      if(!g_testerDealExport.Record(
            trans.deal,exportOrder,positionIdentifier,
            (datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME),
            HistoryDealGetString(trans.deal,DEAL_SYMBOL),entry,
            HistoryDealGetDouble(trans.deal,DEAL_VOLUME),
            HistoryDealGetDouble(trans.deal,DEAL_PRICE),
            HistoryDealGetDouble(trans.deal,DEAL_PROFIT),
            HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),
            HistoryDealGetDouble(trans.deal,DEAL_SWAP),
            HistoryDealGetDouble(trans.deal,DEAL_FEE),entryRiskCash))
         PrintFormat("MIDAS_TEST_EXPORT_ERROR deal=%I64u position=%I64u; artifact will be incomplete",
                     trans.deal,positionIdentifier);
     }
   // Persist each immutable broker deal before local tracking can return.
   // Failed writes keep new entries blocked until restart/history reconciliation repairs the ledger.
   if(g_executionLedger.Ready() && !SendLedgerDealEvent(trans.deal,positionIdentifier))
     {
      g_executionLedgerHealthy=false;
      g_execAudit.Log("LEDGER_DEAL_EVENT_FAILED","broker deal evidence could not be persisted; execution admission remains blocked",
                      0,positionIdentifier,HistoryDealGetDouble(trans.deal,DEAL_VOLUME),
                      HistoryDealGetDouble(trans.deal,DEAL_PRICE));
     }

   datetime dealTime=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
     {
      ulong executedOrder=(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER);
      g_dailyTradeTarget.OnEntry(dealTime,executedOrder>0?executedOrder:trans.deal);
     }
   double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   double volume=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
   ulong positionTicket=g_broker.PositionTicketForIdentifier(_Symbol,positionIdentifier);
   // Preserve the stable identifier as a temporary token if a just-executed
   // position has not appeared in the terminal snapshot yet. The order manager
   // repairs the token to a selectable POSITION_TICKET on the next resolution.
   if(positionTicket==0) positionTicket=positionIdentifier;

   long decisionId=-1;
   if(entry==DEAL_ENTRY_IN)
     {
      ulong orderTicket=(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER);
      g_orders.MarkFilledFromPending(orderTicket,positionTicket,price);
      g_orders.BindPositionIdentity(orderTicket,positionIdentifier,positionTicket);
      decisionId=g_orders.DecisionIdForPositionIdentifier(positionIdentifier);
      if(decisionId<=0) decisionId=g_orders.DecisionIdForTicket(positionTicket);

      double entryCommission=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
      double entrySwap=HistoryDealGetDouble(trans.deal,DEAL_SWAP);
      double entryFee=HistoryDealGetDouble(trans.deal,DEAL_FEE);
      if(decisionId>0)
         g_tracker.MarkExecuted(decisionId,price,dealTime,volume,trans.deal,entryCommission,entrySwap,entryFee,true);

      double loggedSL=0.0,loggedTP=0.0;
      if(g_broker.PositionTicketForIdentifier(_Symbol,positionIdentifier)>0 &&
         PositionSelectByTicket(g_broker.PositionTicketForIdentifier(_Symbol,positionIdentifier)))
        {
         loggedSL=PositionGetDouble(POSITION_SL);
         loggedTP=PositionGetDouble(POSITION_TP);
        }
      g_execAudit.Log("FILL_IN",
                      StringFormat("deal=%I64u position_id=%I64u",trans.deal,positionIdentifier),
                      decisionId,positionTicket,volume,price,loggedSL,loggedTP);
      return;
     }

   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
     {
      decisionId=g_orders.DecisionIdForPositionIdentifier(positionIdentifier);
      // Compatibility fallback for positions recovered by older builds before
      // stable position identifiers were retained by the order manager.
      if(decisionId<=0) decisionId=g_orders.DecisionIdForTicket(positionIdentifier);
      if(decisionId<=0) return;

      double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
      double commission=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
      double swap=HistoryDealGetDouble(trans.deal,DEAL_SWAP);
      double fee=HistoryDealGetDouble(trans.deal,DEAL_FEE);
      double net=profit+commission+swap+fee;
      bool samePositionStillOpen=(g_broker.PositionTicketForIdentifier(_Symbol,positionIdentifier)>0);
      g_orders.MarkPositionExitByIdentifier(positionIdentifier,samePositionStillOpen);
      bool stillOpen=g_orders.HasLiveTradeForDecision(decisionId);
      ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON);
      string outcome="closed";
      if(reason==DEAL_REASON_SL) outcome="SL_Hit";
      else if(reason==DEAL_REASON_TP) outcome="FinalTP_Hit";
      if(entry==DEAL_ENTRY_INOUT)
        {
         outcome="Ambiguous_NettingReversal";
         g_tracker.MarkHistoryIncomplete(decisionId);
        }
      bool tracked=g_tracker.MarkClosed(decisionId,price,dealTime,net,commission,swap,fee,stillOpen,
                                        outcome,trans.deal,volume,true);
      if(tracked && !stillOpen && g_tracker.LastFinalizedQualified())
         g_dailyTradeTarget.OnQualifiedClose(dealTime,g_tracker.LastFinalizedR(),positionIdentifier);
      g_execAudit.Log("FILL_OUT",
                      StringFormat("outcome=%s net=%.2f commission=%.2f swap=%.2f fee=%.2f still_open=%s deal=%I64u position_id=%I64u",
                                   outcome,net,commission,swap,fee,stillOpen?"true":"false",trans.deal,positionIdentifier),
                      decisionId,positionTicket,volume,price);
     }
  }
//+------------------------------------------------------------------+
