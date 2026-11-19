from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EA_ROOT = ROOT / "development" / "EA"
ROUTER = (EA_ROOT / "includes" / "Trading" / "FreshSweepAdditiveRouter.mqh").read_text()
TRADE_ZONE = (EA_ROOT / "includes" / "Trading" / "StrategyTradeZone.mqh").read_text()
SCORING = (EA_ROOT / "includes" / "Analysis" / "Scoring.mqh").read_text()
ENTRY = (EA_ROOT / "MedisTouch_v2.8.source.mq5").read_text()
CONFIG = (EA_ROOT / "includes" / "Core" / "Config.mqh").read_text()
LOGGER = (EA_ROOT / "includes" / "Core" / "SignalLogger.mqh").read_text()
CANDIDATE = (
    ROOT / "research" / "strategytune" / "gold-m15" / "candidates" /
    "fresh-sweep-additive-router-2026-11" / "strategy.ts"
).read_text()
CONTINUATION_LAB = (
    ROOT / "research" / "strategytune" / "gold-m15" / "candidates" /
    "continuation-frequency-lab-2026-11" / "strategy.ts"
).read_text()


def test_native_port_keeps_router_opt_in_and_single_swing_disabled_by_default():
    assert "InpEnableFreshSweepAdditiveRouter=false" in ENTRY
    assert "InpFreshSweepEnableSingleSwingFallback=false" in ENTRY
    assert "InpFreshSweepMaxSignalAgeBars=4" in ENTRY
    assert "m_enabled(false)" in ROUTER
    assert "m_enable_single_swing(false)" in ROUTER


def test_fresh_sweep_age_gate_matches_saved_strategytune_v3_candidate():
    assert "if(sw>ctx.inputs.maxFallbackSignalAgeBars)continue;" in CANDIDATE
    compact = "".join(ROUTER.split())
    assert "IsSignalAgeAllowed(sw,m_max_signal_age_bars)" in compact
    assert "returnshift>=2&&maxAgeBars>=2&&shift<=maxAgeBars;" in compact
    assert "IsSingleSwingSlopeAllowed(trendSlope)" in compact
    assert "trendSlopeATR<0.20||trendSlopeATR>=0.45" in compact
    assert "constdoubleeffectiveRangeCap=rangeRegime?10.0:1.5;" in compact
    assert "candidate.sweep_grade=(candidate.sweep_grade_score>=0.70?3:(candidate.sweep_grade_score>=0.40?2:1));" in compact


def test_candidate_lane_normalization_and_continuation_priority_are_preserved():
    assert "const span=Math.max(1,100-floor);" in CANDIDATE
    assert "NormalizeCandidateScore(quality, 48.0)" in ROUTER
    assert "NormalizeCandidateScore(quality, 55.0)" in ROUTER
    assert "lane = FRESH_SWEEP_CONTINUATION;" in ROUTER
    assert "lane = FRESH_SWEEP_SINGLE_SWING;" in ROUTER
    assert "if(!enableSingleSwingFallback)" in ROUTER
    assert "continuationSelected!==null" in CANDIDATE


def test_router_is_additive_after_native_strategy_generation_only():
    expected = (
        "TradeSetupbuySetup=g_decision.GenerateBuySetup();"
        "TradeSetupsellSetup=g_decision.GenerateSellSetup();"
        "if(InpEnableFreshSweepAdditiveRouter&&!buySetup.active&&!sellSetup.active)"
        "g_decision.GenerateFreshSweepAdditiveSetups(buySetup,sellSetup);"
    )
    compact = "".join(ENTRY.split())
    assert expected in compact


def test_native_stop_floor_and_target_builder_are_reused():
    assert "EnforceSpreadFloor(symbol,entry,stopLoss,forBuy)" in TRADE_ZONE
    assert "CTargetSelector::AssignTargets(out,m_liqCtx,symbol,candidate.atr,entry)" in TRADE_ZONE
    assert "g_risk.ValidateSetup(" in ENTRY
    assert "g_risk.CalculateLotSize(" in ENTRY
    assert "g_positions.OnTick(atr)" in ENTRY


def test_risk_sizing_and_exit_modules_are_not_reimplemented_in_router():
    forbidden = (
        "CalculateLotSize", "RiskAmountForLots", "OrderSend", "OrderManager",
        "PositionManager", "DynamicStop", "partialFraction", "riskPercent",
    )
    for symbol in forbidden:
        assert symbol not in ROUTER


def test_strategy_enum_values_are_appended_and_logged():
    assert "STRATEGY_KEY_LEVEL, STRATEGY_FRESH_SWEEP_CONTINUATION, STRATEGY_FRESH_SWEEP_SINGLE_SWING" in CONFIG
    assert "STRATEGY_FRESH_SWEEP_CONTINUATION: return" in LOGGER
    assert "STRATEGY_FRESH_SWEEP_SINGLE_SWING:  return" in LOGGER


def test_native_trade_generator_uses_existing_entry_risk_geometry():
    assert "candidate.invalidation-stopBuffer" in TRADE_ZONE
    assert "candidate.invalidation+stopBuffer" in TRADE_ZONE
    assert "native CRiskEngine validation" in TRADE_ZONE
    assert "out.confidence=MathMax(0.0,MathMin(candidate.quality,100.0));" in TRADE_ZONE


def test_router_cannot_bypass_existing_system_risk_execution_or_recovery_gates():
    compact = "".join(ENTRY.split())
    # Emergency stop, daily/hard loss controls and session/news filters run
    # before signal routing. All continuation entries subsequently pass the
    # same native setup validation, sizing, portfolio, ledger and order path.
    assert "if(g_emergencyStop)return;" in compact
    assert "g_riskGuard.IsHardHalted(haltReason)" in compact
    assert "g_riskGuard.IsDailyLossLimitHit(haltReason)" in compact
    assert "g_risk.ValidateSetup(" in compact
    assert "g_risk.CalculateLotSize(" in compact
    assert "g_portfolio.AllowNewTradeBatch(" in compact
    assert "g_executionLedger.Ready()" in compact
    assert "g_orders.Submit(" in compact
    assert "g_positions.OnTick(atr)" in compact
    assert "g_recovery.Recover()" in compact
    assert "InpEnableFreshSweepAdditiveRouter=false" in compact
    assert "InpFreshSweepEnableSingleSwingFallback=false" in compact


def test_continuation_fallback_honours_existing_required_volume_and_fibonacci_filters():
    scoring_compact = "".join(SCORING.split())
    trade_zone_compact = "".join(TRADE_ZONE.split())
    assert "PassesConfiguredVolumeFibonacciFilters(boolforBuy)" in scoring_compact
    assert "m_bosCtx.volume.RVOL(1)<m_rvolThreshold" in scoring_compact
    assert "m_bosCtx.fibonacci.InPullbackZone(forBuy,price,m_fibZoneMinPct,m_fibZoneMaxPct)" in scoring_compact
    assert "m_scoring==NULL||!m_scoring.PassesConfiguredVolumeFibonacciFilters(forBuy)" in trade_zone_compact
    # The core fallback gate must run before the setup is constructed.
    assert trade_zone_compact.index("PassesConfiguredVolumeFibonacciFilters(forBuy)") < trade_zone_compact.index("out.type=forBuy")


def test_native_continuation_chain_matches_frequency_lab_signal_thresholds():
    native = "".join(ROUTER.split())
    research = "".join(CONTINUATION_LAB.split())
    # Closed-bar EMA trend alignment and confirmed break of bars 2..5.
    assert "for(inti=1;i<=20;i++)" in native
    assert "for(inti=1;i<=50;i++)" in native
    assert "for(leti=1;i<=20;i++)fast+=ctx.bars.close(i)" in research
    assert "for(leti=1;i<=50;i++)slow+=ctx.bars.close(i)" in research
    assert "for(inti=2;i<=5;i++)" in native
    assert "for(leti=2;i<=5;i++)" in research
    # Exact frequency-expansion floors and pullback window.
    assert "body<0.35||range/atr<0.45" in native
    assert "body<0.35||range/atr<0.45" in research
    assert "for(inti=1;i<=8;i++)" in native
    assert "for(leti=1;i<=8;i++)" in research
    assert "if(quality<48.0)returnout;" in native
    assert "if(quality<ctx.inputs.fallbackQualityFloor)returnnull;" in research
    assert "0.45*MathMin(body/0.7,1.0)+0.35*strength+0.20*MathMin(MathAbs(close1-fast)/atr,1.0)" in native
    assert "0.45*Math.min(body/0.7,1)+0.35*strength+0.20*Math.min(Math.abs(close1-fast)/atr,1)" in research
