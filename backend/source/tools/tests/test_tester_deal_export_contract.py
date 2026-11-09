"""Contract checks for native Strategy Tester deal evidence export."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_deal_export_is_hard_disabled_outside_strategy_tester():
    ea = read("EA/MedisTouch_v2.8.mq5")
    exporter = read("EA/includes/Execution/TesterDealExport.mqh")

    assert "input string InpTesterExportRunId=" in ea
    assert "input int InpTesterServerUtcOffsetMinutes=99999" in ea
    assert "g_testerDealExport.Init(InpTesterExportRunId,_Symbol,InpMagicNumber," in ea
    assert "InpTesterServerUtcOffsetMinutes" in ea
    assert "m_enabled=(enabled && (bool)MQLInfoInteger(MQL_TESTER) && validOffset);" in exporter
    assert "serverUtcOffsetMinutes>=-840 && serverUtcOffsetMinutes<=840" in exporter
    assert "g_testerDealExport.Finalize();" in ea


def test_export_retains_costs_and_position_level_risk_basis():
    ea = read("EA/MedisTouch_v2.8.mq5")
    exporter = read("EA/includes/Execution/TesterDealExport.mqh")

    assert "HistoryDealGetDouble(trans.deal,DEAL_PROFIT)" in ea
    assert "HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)" in ea
    assert "HistoryDealGetDouble(trans.deal,DEAL_SWAP)" in ea
    assert "HistoryDealGetDouble(trans.deal,DEAL_FEE)" in ea
    assert "entryRiskCash=g_risk.RiskAmountForLots" in ea
    assert 'FileWrite(handle,"position_id","time","entry","volume","profit","commission"' in exporter
    assert 'DoubleToString(RiskCash(row.position_id),8)' in exporter
    assert re_search_lane_ea(exporter)


def re_search_lane_ea(exporter: str) -> bool:
    return '                    "EA",' in exporter


def test_export_observes_spread_and_preserves_unique_run_identity():
    ea = read("EA/MedisTouch_v2.8.mq5")
    exporter = read("EA/includes/Execution/TesterDealExport.mqh")

    assert "g_testerDealExport.ObserveSpread(_Symbol);" in ea
    assert 'm_runId=SafeName(runId+"_"+IntegerToString((long)GetTickCount()));' in exporter
    assert "spread_points_mean" in exporter
    assert "spread_points_max" in exporter
    assert "TimeIsoWithOffset" in exporter
    assert "broker_wall_clock_with_explicit_offset" in exporter
    assert "return stamp+zone;" in exporter
    assert 'return stamp+"Z";' not in exporter


def read_modular(path: str) -> str:
    repo_root = ROOT.parents[1]
    return (repo_root / "development" / "EA" / path).read_text(encoding="utf-8")


def test_native_export_carries_decision_strategy_regime_and_slippage_provenance():
    ea = read_modular("MedisTouch_v2.8.mq5")
    exporter = read_modular("includes/Execution/TesterDealExport.mqh")
    tracker = read_modular("includes/Trading/OutcomeTrackerLive.mqh")

    assert "bool GetAttribution(long decisionId,string &strategy,string &regime)" in tracker
    assert "ParseManagedOrderComment(orderComment,exportDecisionId,exportLegIndex)" in ea
    assert "g_tracker.GetAttribution(exportDecisionId,exportStrategy,exportRegime)" in ea
    assert "HistoryOrderGetDouble(exportOrder,ORDER_PRICE_OPEN)" in ea
    assert "OrderCalcProfit(slippageCalcType,_Symbol,dealVolume" in ea
    assert "entry!=DEAL_ENTRY_INOUT && (buyMatch || sellMatch)" in ea
    assert "historicalOrderType==ORDER_TYPE_BUY" in ea
    assert "historicalOrderType==ORDER_TYPE_SELL" in ea
    assert "Pending stop/limit triggers are deliberately left unknown" in ea
    assert "slippage_known" in exporter
    assert '"decision_id","strategy","regime","requested_price","slippage_points"' in exporter
    assert "RememberAttribution(positionId,decisionId,strategy,regime)" in exporter


def test_unknown_slippage_is_blank_not_zero_and_labels_follow_position_id():
    exporter = read_modular("includes/Execution/TesterDealExport.mqh")
    assert '(row.slippage_known?DoubleToString(row.slippage_cost_cash,8):"")' in exporter
    assert 'm_attributions[attribution].strategy' in exporter
    assert 'm_attributions[attribution].regime' in exporter
    assert 'm_attributions[index].strategy="CONFLICT"' in exporter


def test_only_opening_orders_resolve_strategy_decision_identity():
    ea = read_modular("MedisTouch_v2.8.mq5")
    assert "if(entry==DEAL_ENTRY_IN &&" in ea



def test_exit_slippage_cash_uses_position_direction_not_deal_direction():
    ea = read_modular("MedisTouch_v2.8.mq5")
    assert "ENUM_ORDER_TYPE slippageCalcType=historicalOrderType;" in ea
    assert "if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)" in ea
    assert "slippageCalcType=(historicalOrderType==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);" in ea
    assert "OrderCalcProfit(slippageCalcType,_Symbol,dealVolume" in ea



def test_netting_reversal_invalidates_position_lineage():
    exporter = read_modular("includes/Execution/TesterDealExport.mqh")
    assert "else if(entry==DEAL_ENTRY_INOUT)" in exporter
    assert 'm_attributions[attribution].decision_id=0;' in exporter
    assert 'm_attributions[attribution].strategy="CONFLICT";' in exporter
    assert 'm_attributions[attribution].regime="CONFLICT";' in exporter
    assert 'resolvedStrategy="CONFLICT";' in exporter
    assert 'resolvedRegime="CONFLICT";' in exporter
