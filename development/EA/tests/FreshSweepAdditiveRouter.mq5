#property strict
#include "../includes/Trading/FreshSweepAdditiveRouter.mqh"
#include "TestHarness.mqh"

int failures=0;

void AssertTrue(bool value,string label)
  {
   if(value) PrintFormat("PASS: %s",label);
   else { PrintFormat("FAIL: %s",label); failures++; }
  }

MidasFreshSweepCandidate Candidate(double rank)
  {
   MidasFreshSweepCandidate c;
   ZeroMemory(c);
   c.valid=true;
   c.quality=rank;
   c.rank_score=rank;
   return c;
  }

MidasFreshSweepCandidate CandidateWithTrend(double quality,double directionTrendATR)
  {
   MidasFreshSweepCandidate c=Candidate(quality);
   c.direction_trend_atr=directionTrendATR;
   return c;
  }

void OnStart()
  {
   AssertTrue(MathAbs(CFreshSweepAdditiveRouter::NormalizeCandidateScore(74.0,48.0)-50.0)<0.000001,
              "continuation ranking normalizes against its own 48-point floor");
   AssertTrue(MathAbs(CFreshSweepAdditiveRouter::NormalizeCandidateScore(77.5,55.0)-50.0)<0.000001,
              "single-swing ranking normalizes against its own 55-point floor");
   AssertTrue(MathAbs(CFreshSweepAdditiveRouter::DualLaneRankScore(74.0,48.0,0.0)-50.0)<0.000001,
              "Rank B normalizes continuation quality before a neutral trend prior");
   AssertTrue(MathAbs(CFreshSweepAdditiveRouter::DualLaneRankScore(74.0,48.0,0.5)-54.0)<0.000001,
              "Rank B caps aligned prior at plus four score points");
   AssertTrue(MathAbs(CFreshSweepAdditiveRouter::DualLaneRankScore(80.0,48.0,-2.0)-49.5384615385)<0.00001,
              "Rank B caps opposing prior at minus twelve score points");
   AssertTrue(CFreshSweepAdditiveRouter::IsSignalAgeAllowed(4,4),
              "four completed bars is inside the candidate freshness limit");
   AssertTrue(!CFreshSweepAdditiveRouter::IsSignalAgeAllowed(5,4),
              "five completed bars is outside the candidate freshness limit");
   AssertTrue(!CFreshSweepAdditiveRouter::IsSignalAgeAllowed(1,4),
              "the forming/most-recent bar is not accepted as a sweep shift");
   AssertTrue(CFreshSweepAdditiveRouter::IsSingleSwingSlopeAllowed(0.19),
              "range-like single-swing setups remain eligible for PD validation");
   AssertTrue(!CFreshSweepAdditiveRouter::IsSingleSwingSlopeAllowed(0.20),
              "the adaptive transition regime begins at 0.20 ATR and is rejected");
   AssertTrue(!CFreshSweepAdditiveRouter::IsSingleSwingSlopeAllowed(0.44),
              "the adaptive transition regime remains rejected below 0.45 ATR");
   AssertTrue(CFreshSweepAdditiveRouter::IsSingleSwingSlopeAllowed(0.45),
              "trend-like single-swing setups become eligible at 0.45 ATR");
   AssertTrue(!CFreshSweepAdditiveRouter::IsSingleSwingSlopeAllowed(-1.0),
              "invalid trend-slope measurements fail closed");

   MidasFreshSweepCandidate contBuy=Candidate(50.0);
   MidasFreshSweepCandidate contSell;
   ZeroMemory(contSell);
   MidasFreshSweepCandidate singleBuy=Candidate(98.0);
   MidasFreshSweepCandidate singleSell;
   ZeroMemory(singleSell);
   MidasFreshSweepCandidate chosen;
   bool forBuy=false;
   ENUM_FRESH_SWEEP_LANE lane=FRESH_SWEEP_NONE;

   AssertTrue(CFreshSweepAdditiveRouter::SelectLanes(contBuy,contSell,singleBuy,singleSell,
              true,5.0,chosen,forBuy,lane) &&
              lane==FRESH_SWEEP_CONTINUATION && forBuy,
              "a selected continuation lane retains priority over a higher-ranked single-swing candidate");

   MidasFreshSweepCandidate weakContBuy=Candidate(50.0);
   MidasFreshSweepCandidate weakContSell=Candidate(48.0);
   AssertTrue(CFreshSweepAdditiveRouter::SelectLanes(weakContBuy,weakContSell,singleBuy,singleSell,
              true,5.0,chosen,forBuy,lane) &&
              lane==FRESH_SWEEP_SINGLE_SWING && forBuy,
              "single-swing may be selected when opposing continuation candidates fail the direction threshold");

   AssertTrue(!CFreshSweepAdditiveRouter::SelectLanes(weakContBuy,weakContSell,singleBuy,singleSell,
              false,5.0,chosen,forBuy,lane),
              "disabled single-swing fallback is never selected");

   MidasFreshSweepCandidate contRank=CandidateWithTrend(80.0,0.0);
   MidasFreshSweepCandidate singleRank=CandidateWithTrend(85.0,0.0);
   MidasFreshSweepCandidate noOpposing;
   ZeroMemory(noOpposing);
   AssertTrue(CFreshSweepAdditiveRouter::SelectDualLaneRankB(
              contRank,noOpposing,singleRank,noOpposing,5.0,chosen,forBuy,lane) &&
              lane==FRESH_SWEEP_SINGLE_SWING && forBuy,
              "Rank B selects a higher normalized single-swing candidate");
   MidasFreshSweepCandidate opposingSingle=CandidateWithTrend(85.0,-2.0);
   AssertTrue(CFreshSweepAdditiveRouter::SelectDualLaneRankB(
              contRank,noOpposing,opposingSingle,noOpposing,5.0,chosen,forBuy,lane) &&
              lane==FRESH_SWEEP_CONTINUATION && forBuy,
              "directional prior can reorder families without rejecting either");
   MidasFreshSweepCandidate contSell=CandidateWithTrend(80.0,0.0);
   MidasFreshSweepCandidate contBuy=CandidateWithTrend(82.0,0.0);
   AssertTrue(!CFreshSweepAdditiveRouter::SelectDualLaneRankB(
              contBuy,contSell,noOpposing,noOpposing,5.0,chosen,forBuy,lane),
              "Rank B abstains when opposite-side scores are inside the advantage threshold");
   AssertTrue(!CFreshSweepAdditiveRouter::SelectDualLaneRankB(
              noOpposing,noOpposing,noOpposing,noOpposing,5.0,chosen,forBuy,lane),
              "Rank B abstains when neither family has a valid candidate");

   MidasFreshSweepCandidate noCandidate;
   ZeroMemory(noCandidate);
   AssertTrue(!CFreshSweepAdditiveRouter::SelectLanes(noCandidate,noCandidate,noCandidate,noCandidate,
              true,5.0,chosen,forBuy,lane),
              "router abstains when neither lane has an admissible candidate");

   PrintFormat("FreshSweepAdditiveRouter tests: %d failure(s)",failures);
   MidasTestFinish("FreshSweepAdditiveRouter-tests.txt",failures);
  }
