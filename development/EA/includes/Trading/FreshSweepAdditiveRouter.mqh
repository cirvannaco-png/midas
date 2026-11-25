//+------------------------------------------------------------------+
//| Trading/FreshSweepAdditiveRouter.mqh                              |
//| Research port of StrategyTune Midas Fresh-Sweep Additive Router. |
//| Entry-selection only: sizing, risk, orders and exits stay native. |
//+------------------------------------------------------------------+
#ifndef FRESH_SWEEP_ADDITIVE_ROUTER_MQH
#define FRESH_SWEEP_ADDITIVE_ROUTER_MQH

#include "../Core/Config.mqh"
#include "../Core/CandleData.mqh"

enum ENUM_FRESH_SWEEP_LANE
  {
   FRESH_SWEEP_NONE = 0,
   FRESH_SWEEP_CONTINUATION,
   FRESH_SWEEP_SINGLE_SWING
  };

struct MidasFreshSweepCandidate
  {
   bool   valid;
   double quality;
   double rank_score;
   double direction_trend_atr;
   double invalidation;
   double atr;
   double rejection_ratio;
   double sweep_level;
   double bos_level;
   int    sweep_shift;
   int    sweep_grade;
   double sweep_grade_score;
   double bos_strength;
   bool   has_sweep;
  };

// This router reproduces the StrategyTune v3 entry-selection formulas and
// completed-bar indexing. It intentionally does NOT reproduce StrategyTune's
// custom order sizing or custom exits. Native Midas remains the execution owner.
class CFreshSweepAdditiveRouter
  {
private:
   CCandleData *m_candles;
   bool         m_enabled;
   bool         m_enable_single_swing;
   bool         m_use_dual_lane_rank_b;
   bool         m_trend_only_continuation;
   double       m_min_trend_slope_atr;
   int          m_max_signal_age_bars;
   int          m_lookback_bars;
   double       m_directional_advantage;

   double ATR(int back) const
     {
      if(m_candles == NULL) return 0.0;
      const int period = 14;
      const int total = m_candles.Total();
      if(back < 0 || total < back + period + 2) return 0.0;

      double sum = 0.0;
      for(int i = back; i < back + period; i++)
        {
         CandleData c = m_candles.GetCandle(i);
         CandleData previous = m_candles.GetCandle(i + 1);
         double tr = MathMax(c.high - c.low,
                             MathMax(MathAbs(c.high - previous.close),
                                     MathAbs(c.low - previous.close)));
         if(!MathIsValidNumber(tr) || tr < 0.0) return 0.0;
         sum += tr;
        }
      return sum / (double)period;
     }

   double BodyRatio(int shift) const
     {
      if(m_candles == NULL) return 0.0;
      CandleData c = m_candles.GetCandle(shift);
      double range = c.high - c.low;
      return (range > 0.0 ? MathAbs(c.close - c.open) / range : 0.0);
     }

   bool IsSwingHigh(int shift) const
     {
      if(m_candles == NULL || shift < 2 || shift + 1 >= m_candles.Total())
         return false;
      double value = m_candles.GetCandle(shift).high;
      return value >= m_candles.GetCandle(shift - 1).high &&
             value >= m_candles.GetCandle(shift + 1).high;
     }

   bool IsSwingLow(int shift) const
     {
      if(m_candles == NULL || shift < 2 || shift + 1 >= m_candles.Total())
         return false;
      double value = m_candles.GetCandle(shift).low;
      return value <= m_candles.GetCandle(shift - 1).low &&
             value <= m_candles.GetCandle(shift + 1).low;
     }

   double TrendSlopeProxyATR() const
     {
      const double atr = ATR(1);
      if(!(atr > 0.0) || m_candles == NULL || m_candles.Total() < 25)
         return -1.0;

      double fast = 0.0;
      double slow = 0.0;
      for(int i = 1; i <= 8; i++)
         fast += m_candles.GetCandle(i).close;
      for(int i = 1; i <= 21; i++)
         slow += m_candles.GetCandle(i).close;

      return MathAbs(fast / 8.0 - slow / 21.0) / atr;
     }

   double DirectionalTrendSlopeATR(bool forBuy) const
     {
      const double atr = ATR(1);
      if(!(atr > 0.0) || m_candles == NULL || m_candles.Total() < 22)
         return 0.0;
      double fast = 0.0;
      double slow = 0.0;
      for(int i = 1; i <= 8; i++)
         fast += m_candles.GetCandle(i).close;
      for(int i = 1; i <= 21; i++)
         slow += m_candles.GetCandle(i).close;
      const double signedTrendATR = (fast / 8.0 - slow / 21.0) / atr;
      return forBuy ? signedTrendATR : -signedTrendATR;
     }

   MidasFreshSweepCandidate EmptyCandidate() const
     {
      MidasFreshSweepCandidate out;
      ZeroMemory(out);
      return out;
     }

   MidasFreshSweepCandidate BuildContinuation(bool forBuy) const
     {
      MidasFreshSweepCandidate out = EmptyCandidate();
      if(m_candles == NULL || m_candles.Total() < 60) return out;

      const double atr = ATR(1);
      if(!(atr > 0.0)) return out;
      if(!IsContinuationSlopeAllowed(TrendSlopeProxyATR(),
                                     m_trend_only_continuation,
                                     m_min_trend_slope_atr))
         return out;

      double fast = 0.0;
      double slow = 0.0;
      for(int i = 1; i <= 20; i++)
         fast += m_candles.GetCandle(i).close;
      for(int i = 1; i <= 50; i++)
         slow += m_candles.GetCandle(i).close;
      fast /= 20.0;
      slow /= 50.0;

      const double close1 = m_candles.GetCandle(1).close;
      const double close2 = m_candles.GetCandle(2).close;
      if(forBuy ? !(close1 > fast && fast > slow)
                : !(close1 < fast && fast < slow))
         return out;

      const double body = BodyRatio(1);
      const double range = m_candles.GetCandle(1).high -
                           m_candles.GetCandle(1).low;
      if(body < 0.35 || range / atr < 0.45) return out;

      bool touched = false;
      for(int i = 1; i <= 8; i++)
        {
         CandleData c = m_candles.GetCandle(i);
         if(forBuy)
           {
            if(c.low <= fast + 0.20 * atr &&
               c.high >= fast - 0.20 * atr)
               touched = true;
           }
         else
           {
            if(c.high >= fast - 0.20 * atr &&
               c.low <= fast + 0.20 * atr)
               touched = true;
           }
        }
      if(!touched) return out;

      double level = forBuy ? -DBL_MAX : DBL_MAX;
      for(int i = 2; i <= 5; i++)
        {
         CandleData c = m_candles.GetCandle(i);
         if(forBuy) level = MathMax(level, c.high);
         else       level = MathMin(level, c.low);
        }

      const bool crossed = forBuy ? (close1 > level && close2 <= level)
                                  : (close1 < level && close2 >= level);
      if(!crossed) return out;

      const double strength = MathMax(0.0,
         MathMin(1.0, MathAbs(close1 - level) / (0.25 * atr)));
      const double quality = 100.0 *
         (0.45 * MathMin(body / 0.7, 1.0) +
          0.35 * strength +
          0.20 * MathMin(MathAbs(close1 - fast) / atr, 1.0));
      if(quality < 48.0) return out;

      double invalidation = forBuy ? m_candles.GetCandle(1).low
                                   : m_candles.GetCandle(1).high;
      for(int i = 2; i <= 5; i++)
        {
         CandleData c = m_candles.GetCandle(i);
         if(forBuy) invalidation = MathMin(invalidation, c.low);
         else       invalidation = MathMax(invalidation, c.high);
        }

      out.valid = true;
      out.quality = quality;
      out.rank_score = NormalizeCandidateScore(quality, 48.0);
      out.direction_trend_atr = DirectionalTrendSlopeATR(forBuy);
      out.invalidation = invalidation;
      out.atr = atr;
      out.rejection_ratio = body;
      out.bos_level = level;
      out.bos_strength = strength;
      out.sweep_grade = 0;
      out.sweep_grade_score = 0.0;
      out.sweep_shift = 0;
      out.has_sweep = false;
      return out;
     }

   MidasFreshSweepCandidate BuildSingleSwing(bool forBuy) const
     {
      MidasFreshSweepCandidate out = EmptyCandidate();
      if(m_candles == NULL || m_candles.Total() < 60) return out;

      const double atr = ATR(1);
      const double trendSlope = TrendSlopeProxyATR();
      if(!(atr > 0.0) || trendSlope < 0.0) return out;

      // StrategyTune defaults: adaptiveFallbackPD=true, range threshold=0.20,
      // transition band [0.20,0.45) is rejected, trend slope >=0.45 uses
      // a 1.5 ATR signal-range ceiling. Range-like bars (<0.20) use a
      // midpoint premium/discount check and a 10 ATR range ceiling.
      if(!IsSingleSwingSlopeAllowed(trendSlope)) return out;
      const bool rangeRegime = (trendSlope < 0.20);

      const int maxPivot = MathMin(MathMin(m_lookback_bars, 45),
                                   m_candles.Total() - 2);
      const int maxAge = 8; // min(fallbackMaxSweepBars=8, maxSweepAgeBars=8 + 2)
      MidasFreshSweepCandidate best = EmptyCandidate();

      for(int pivot = 3; pivot <= maxPivot; pivot++)
        {
         if(forBuy ? !IsSwingLow(pivot) : !IsSwingHigh(pivot))
            continue;

         const double level = forBuy ? m_candles.GetCandle(pivot).low
                                     : m_candles.GetCandle(pivot).high;
         const int oldestShift = MathMax(2, pivot - maxAge);

         for(int sw = pivot - 1; sw >= oldestShift; sw--)
           {
            if(!IsSignalAgeAllowed(sw, m_max_signal_age_bars))
               continue;

            CandleData sweep = m_candles.GetCandle(sw);
            const bool swept = forBuy ? (sweep.low < level && sweep.close > level)
                                      : (sweep.high > level && sweep.close < level);
            if(!swept) continue;

            const double wick = forBuy ? level - sweep.low : sweep.high - level;
            const double reclaim = forBuy ? sweep.close - level : level - sweep.close;
            if(!(wick > 0.0)) continue;

            const double rejection = MathMax(0.0,
               MathMin(1.0, reclaim / wick));
            if(rejection < 0.20 * 0.65) continue;

            double micro = forBuy ? -DBL_MAX : DBL_MAX;
            for(int k = 2; k < sw; k++)
              {
               CandleData c = m_candles.GetCandle(k);
               if(forBuy) micro = MathMax(micro, c.high);
               else       micro = MathMin(micro, c.low);
              }
            if(!MathIsValidNumber(micro) ||
               (forBuy && micro == -DBL_MAX) ||
               (!forBuy && micro == DBL_MAX))
               continue;

            CandleData signal = m_candles.GetCandle(1);
            CandleData previous = m_candles.GetCandle(2);
            const bool crossed = forBuy
               ? (signal.close > micro && previous.close <= micro &&
                  signal.close > signal.open)
               : (signal.close < micro && previous.close >= micro &&
                  signal.close < signal.open);
            if(!crossed) continue;

            const double body = BodyRatio(1);
            const double range = signal.high - signal.low;
            const double rangeATR = range / atr;
            const double effectiveRangeCap = rangeRegime ? 10.0 : 1.5;
            if(body < 0.40 * 0.75 || rangeATR < 0.55 ||
               rangeATR > effectiveRangeCap)
               continue;

            // Adaptive fallback PD is applied only in range-like conditions.
            if(rangeRegime)
              {
               double rangeHigh = -DBL_MAX;
               double rangeLow = DBL_MAX;
               const int rangeLimit = MathMin(40, m_candles.Total() - 2);
               for(int k = 2; k <= rangeLimit; k++)
                 {
                  CandleData c = m_candles.GetCandle(k);
                  rangeHigh = MathMax(rangeHigh, c.high);
                  rangeLow = MathMin(rangeLow, c.low);
                 }
               if(!(rangeHigh > rangeLow)) continue;
               const double midpoint = (rangeHigh + rangeLow) / 2.0;
               const double price = m_candles.GetCandle(1).close;
               if(forBuy ? (price > midpoint) : (price < midpoint))
                  continue;
              }

            const double breakQ = MathMax(0.0,
               MathMin(1.0, MathAbs(signal.close - micro) / (0.25 * atr)));
            const double rejectQ = MathMax(0.0,
               MathMin(1.0, rejection / 0.65));
            const double bodyQ = MathMax(0.0,
               MathMin(1.0, body / 0.65));
            const double quality = 100.0 *
               (0.35 * rejectQ + 0.40 * breakQ + 0.25 * bodyQ);
            if(quality < 55.0) continue;

            MidasFreshSweepCandidate candidate = EmptyCandidate();
            candidate.valid = true;
            candidate.quality = quality;
            candidate.rank_score = NormalizeCandidateScore(quality, 55.0);
            candidate.direction_trend_atr = DirectionalTrendSlopeATR(forBuy);
            candidate.invalidation = forBuy ? sweep.low : sweep.high;
            candidate.atr = atr;
            candidate.rejection_ratio = rejection;
            candidate.sweep_level = level;
            candidate.bos_level = signal.close;
            candidate.sweep_shift = sw;
            candidate.has_sweep = true;

            const double sweepATR = ATR(sw);
            if(!(sweepATR > 0.0)) continue;
            const double sweepPenATR = wick / sweepATR;
            const double shapeScore =
               (sweepPenATR >= 0.03 && sweepPenATR <= 0.60)
               ? 1.0
               : MathMax(0.0, 1.0 - MathAbs(sweepPenATR - 0.30) / 0.60);

            const int followIdx = sw - 1;
            bool followThrough = false;
            if(followIdx >= 1)
              {
               const double followATR = ATR(followIdx);
               CandleData follow = m_candles.GetCandle(followIdx);
               const double followRange = follow.high - follow.low;
               const bool followDirectional = forBuy
                  ? (follow.close > follow.open)
                  : (follow.close < follow.open);
               const double followBody = (followRange > 0.0
                  ? MathAbs(follow.close - follow.open) / followRange : 0.0);
               const double oppositeWick = forBuy
                  ? follow.open - follow.low
                  : follow.high - follow.open;
               followThrough = followDirectional && followATR > 0.0 &&
                  followRange / followATR >= 1.2 && followBody >= 0.6 &&
                  oppositeWick <= 0.3 * followRange;
              }

            candidate.sweep_grade_score = MathMax(0.0, MathMin(1.0,
               0.4 * rejection + 0.3 * shapeScore +
               0.3 * (followThrough ? 1.0 : 0.0)));
            candidate.sweep_grade = (candidate.sweep_grade_score >= 0.70
               ? 3 : (candidate.sweep_grade_score >= 0.40 ? 2 : 1));

            const double bosBreak = forBuy
               ? signal.close - micro : micro - signal.close;
            const double bosDistScore = MathMax(0.0,
               MathMin(bosBreak / (0.5 * atr), 1.0));
            candidate.bos_strength = MathMax(0.0,
               MathMin(0.6 * bosDistScore + 0.4 * body, 1.0));

            if(!best.valid || candidate.quality > best.quality)
               best = candidate;
           }
        }
      return best;
     }

public:
                     CFreshSweepAdditiveRouter()
      : m_candles(NULL), m_enabled(false), m_enable_single_swing(false),
        m_use_dual_lane_rank_b(false), m_trend_only_continuation(false),
        m_min_trend_slope_atr(0.45), m_max_signal_age_bars(4), m_lookback_bars(50),
        m_directional_advantage(5.0)
     {
     }

   void Configure(CCandleData *candles, bool enabled,
                  bool enableSingleSwingFallback, int maxSignalAgeBars = 4,
                  int lookbackBars = 50, double directionalAdvantage = 5.0,
                  bool useDualLaneRankB = false,
                  bool trendOnlyContinuation = false,
                  double minTrendSlopeATR = 0.45)
     {
      m_candles = candles;
      m_enabled = enabled;
      m_enable_single_swing = enableSingleSwingFallback;
      m_use_dual_lane_rank_b = useDualLaneRankB;
      m_trend_only_continuation = trendOnlyContinuation;
      m_min_trend_slope_atr = (MathIsValidNumber(minTrendSlopeATR) &&
                               minTrendSlopeATR >= 0.0 && minTrendSlopeATR <= 5.0)
                              ? minTrendSlopeATR : 0.45;
      m_max_signal_age_bars = MathMax(1, MathMin(20, maxSignalAgeBars));
      m_lookback_bars = MathMax(10, MathMin(100, lookbackBars));
      m_directional_advantage = (directionalAdvantage >= 0.0 &&
                                 directionalAdvantage <= 100.0)
                                ? directionalAdvantage : 5.0;
     }

   static double NormalizeCandidateScore(double quality, double floor)
     {
      const double span = MathMax(1.0, 100.0 - floor);
      return MathMax(0.0,
         MathMin(100.0, 100.0 * (quality - floor) / span));
     }

   static double DualLaneRankScore(double quality, double floor,
                                   double directionTrendATR)
     {
      const double baseRank = NormalizeCandidateScore(quality, floor);
      const double trendAdjustment =
         MathMax(-12.0, MathMin(4.0, directionTrendATR * 10.0));
      return MathMax(0.0, MathMin(100.0, baseRank + trendAdjustment));
     }

   static bool IsSignalAgeAllowed(int shift, int maxAgeBars)
     {
      return shift >= 2 && maxAgeBars >= 2 && shift <= maxAgeBars;
     }

   static bool IsSingleSwingSlopeAllowed(double trendSlopeATR)
     {
      // StrategyTune adaptiveFallbackPD: range <0.20, reject [0.20,0.45),
      // trend >=0.45. Negative/invalid slope values fail closed.
      return MathIsValidNumber(trendSlopeATR) && trendSlopeATR >= 0.0 &&
             (trendSlopeATR < 0.20 || trendSlopeATR >= 0.45);
     }

   static bool IsContinuationSlopeAllowed(double trendSlopeATR,
                                          bool requireTrendOnly,
                                          double minTrendSlopeATR = 0.45)
     {
      if(!requireTrendOnly) return true;
      if(!MathIsValidNumber(trendSlopeATR) ||
         !MathIsValidNumber(minTrendSlopeATR) || minTrendSlopeATR < 0.0)
         return false;
      return trendSlopeATR >= minTrendSlopeATR;
     }

   static bool SelectDirection(const MidasFreshSweepCandidate &buy,
                               const MidasFreshSweepCandidate &sell,
                               double directionalAdvantage,
                               MidasFreshSweepCandidate &chosen,
                               bool &forBuy)
     {
      ZeroMemory(chosen);
      forBuy = false;
      if(!buy.valid && !sell.valid) return false;
      if(buy.valid && !sell.valid)
        {
         chosen = buy;
         forBuy = true;
         return true;
        }
      if(sell.valid && !buy.valid)
        {
         chosen = sell;
         forBuy = false;
         return true;
        }

      const double delta = buy.rank_score - sell.rank_score;
      if(delta >= directionalAdvantage)
        {
         chosen = buy;
         forBuy = true;
         return true;
        }
      if(-delta >= directionalAdvantage)
        {
         chosen = sell;
         forBuy = false;
         return true;
        }
      return false;
     }

   // Mirrors the StrategyTune v3 source exactly: continuation has priority.
   // If it cannot select a direction (including a close opposing-candidate
   // conflict), enabled single-swing candidates may be considered.
   static bool SelectLanes(const MidasFreshSweepCandidate &continuationBuy,
                           const MidasFreshSweepCandidate &continuationSell,
                           const MidasFreshSweepCandidate &singleSwingBuy,
                           const MidasFreshSweepCandidate &singleSwingSell,
                           bool enableSingleSwingFallback,
                           double directionalAdvantage,
                           MidasFreshSweepCandidate &chosen,
                           bool &forBuy,
                           ENUM_FRESH_SWEEP_LANE &lane)
     {
      lane = FRESH_SWEEP_NONE;
      if(SelectDirection(continuationBuy, continuationSell,
                         directionalAdvantage, chosen, forBuy))
        {
         lane = FRESH_SWEEP_CONTINUATION;
         return true;
        }

      if(!enableSingleSwingFallback)
         return false;

      if(SelectDirection(singleSwingBuy, singleSwingSell,
                         directionalAdvantage, chosen, forBuy))
        {
         lane = FRESH_SWEEP_SINGLE_SWING;
         return true;
        }
      return false;
     }

   static bool SelectDualLaneRankB(
      const MidasFreshSweepCandidate &continuationBuy,
      const MidasFreshSweepCandidate &continuationSell,
      const MidasFreshSweepCandidate &singleSwingBuy,
      const MidasFreshSweepCandidate &singleSwingSell,
      double directionalAdvantage,
      MidasFreshSweepCandidate &chosen,
      bool &forBuy,
      ENUM_FRESH_SWEEP_LANE &lane)
     {
      lane = FRESH_SWEEP_NONE;
      ZeroMemory(chosen);
      forBuy = false;
      MidasFreshSweepCandidate bestBuy;
      MidasFreshSweepCandidate bestSell;
      ZeroMemory(bestBuy);
      ZeroMemory(bestSell);
      double bestBuyScore = -1.0;
      double bestSellScore = -1.0;
      ENUM_FRESH_SWEEP_LANE bestBuyLane = FRESH_SWEEP_NONE;
      ENUM_FRESH_SWEEP_LANE bestSellLane = FRESH_SWEEP_NONE;

      if(singleSwingBuy.valid)
        {
         bestBuy = singleSwingBuy;
         bestBuyScore = DualLaneRankScore(singleSwingBuy.quality, 55.0,
                                          singleSwingBuy.direction_trend_atr);
         bestBuy.rank_score = bestBuyScore;
         bestBuyLane = FRESH_SWEEP_SINGLE_SWING;
        }
      if(continuationBuy.valid)
        {
         const double score = DualLaneRankScore(continuationBuy.quality, 48.0,
                                                continuationBuy.direction_trend_atr);
         if(!bestBuy.valid || score > bestBuyScore)
           {
            bestBuy = continuationBuy;
            bestBuyScore = score;
            bestBuy.rank_score = score;
            bestBuyLane = FRESH_SWEEP_CONTINUATION;
           }
        }
      if(singleSwingSell.valid)
        {
         bestSell = singleSwingSell;
         bestSellScore = DualLaneRankScore(singleSwingSell.quality, 55.0,
                                           singleSwingSell.direction_trend_atr);
         bestSell.rank_score = bestSellScore;
         bestSellLane = FRESH_SWEEP_SINGLE_SWING;
        }
      if(continuationSell.valid)
        {
         const double score = DualLaneRankScore(continuationSell.quality, 48.0,
                                                continuationSell.direction_trend_atr);
         if(!bestSell.valid || score > bestSellScore)
           {
            bestSell = continuationSell;
            bestSellScore = score;
            bestSell.rank_score = score;
            bestSellLane = FRESH_SWEEP_CONTINUATION;
           }
        }

      if(!bestBuy.valid && !bestSell.valid) return false;
      if(bestBuy.valid && !bestSell.valid)
        {
         chosen = bestBuy; forBuy = true; lane = bestBuyLane; return true;
        }
      if(bestSell.valid && !bestBuy.valid)
        {
         chosen = bestSell; forBuy = false; lane = bestSellLane; return true;
        }
      const double delta = bestBuyScore - bestSellScore;
      if(delta >= directionalAdvantage)
        {
         chosen = bestBuy; forBuy = true; lane = bestBuyLane; return true;
        }
      if(-delta >= directionalAdvantage)
        {
         chosen = bestSell; forBuy = false; lane = bestSellLane; return true;
        }
      return false;
     }

   bool Select(MidasFreshSweepCandidate &chosen,
               bool &forBuy,
               ENUM_FRESH_SWEEP_LANE &lane) const
     {
      ZeroMemory(chosen);
      forBuy = false;
      lane = FRESH_SWEEP_NONE;
      if(!m_enabled || m_candles == NULL || m_candles.Total() < 60)
         return false;

      MidasFreshSweepCandidate continuationBuy = BuildContinuation(true);
      MidasFreshSweepCandidate continuationSell = BuildContinuation(false);
      MidasFreshSweepCandidate singleSwingBuy = EmptyCandidate();
      MidasFreshSweepCandidate singleSwingSell = EmptyCandidate();

      if(m_enable_single_swing)
        {
         singleSwingBuy = BuildSingleSwing(true);
         singleSwingSell = BuildSingleSwing(false);
        }

      if(m_use_dual_lane_rank_b && m_enable_single_swing)
         return SelectDualLaneRankB(continuationBuy, continuationSell,
                                    singleSwingBuy, singleSwingSell,
                                    m_directional_advantage, chosen, forBuy, lane);

      return SelectLanes(continuationBuy, continuationSell,
                         singleSwingBuy, singleSwingSell,
                         m_enable_single_swing, m_directional_advantage,
                         chosen, forBuy, lane);
     }
  };

#endif
//+------------------------------------------------------------------+
