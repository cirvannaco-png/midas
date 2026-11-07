//+------------------------------------------------------------------+
//| Trading/AccuracyPolicyShadow.mqh                                 |
//| Versioned evidence capture for accuracy-policy research.          |
//| This module is deliberately non-authoritative: it never blocks,   |
//| sizes, modifies, or submits an order.                              |
//+------------------------------------------------------------------+
#ifndef ACCURACYPOLICYSHADOW_MQH
#define ACCURACYPOLICYSHADOW_MQH

#include "../Core/Config.mqh"

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
      "policy=ACCURACY_V3_SHADOW;verdict=OBSERVE_ONLY;"
      "raw_confidence=%.2f;calibrated_probability=%.2f;"
      "calibration_samples=%d;calibration_state=%s;"
      "environment=%s;env_score=%.4f;exec_score=%.4f;"
      "env_exec_confidence=%.2f;contradiction_penalty=%.4f;"
      "selected_strategy=%s;selected_strategy_score=%.2f;"
      "momentum_score=%.2f;breakout_score=%.2f;"
      "reversion_score=%.2f;keylevel_score=%.2f;"
      "smc_structural_valid=%s;smc_failure=%s;"
      "execution_effect=NONE",
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
