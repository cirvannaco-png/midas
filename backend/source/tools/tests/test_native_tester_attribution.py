from pathlib import Path
import sys

import pytest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from analyze_native_tester_attribution import (  # noqa: E402
    AttributionError,
    read_export_metadata,
    read_position_labels,
    read_decision_outcomes,
    summarize,
    assess_research_eligibility,
    grouped_metrics,
)


def test_metadata_requires_complete_reconciled_export(tmp_path):
    path = tmp_path / "meta.json"
    path.write_text(
        '{"export_status":"complete","run_id":"diagnostic-run_123","symbol":"EURUSD",'
        '"history_expected_deals":2,"history_recorded_deals":2,"history_missing_deals":0,"deals_exported":2,'
        '"deals_file_written":true,"open_positions_file_written":true,'
        '"timestamp_basis":"broker_wall_clock_with_explicit_offset",'
        '"server_utc_offset_minutes":180}',
        encoding="utf-8",
    )
    assert read_export_metadata(path)["export_status"] == "complete"
    path.write_text('{"export_status":"incomplete"}', encoding="utf-8")
    with pytest.raises(AttributionError, match="not marked complete"):
        read_export_metadata(path)


def test_position_labels_keep_direction_session_and_stop_geometry(tmp_path):
    path = tmp_path / "deals.csv"
    path.write_text(
        "position_id,direction,session,initial_stop_price,"
        "initial_stop_distance_points,deal_reason,spread_points_observed,spread_observed,volume,entry\n"
        "10,BUY,SESSION_LONDON,1.0800,120,DEAL_REASON_EXPERT,1.2,true,0.5,IN\n"
        "10,BUY,SESSION_LONDON,1.0800,120,DEAL_REASON_SL,1.4,true,0.5,OUT\n",
        encoding="utf-8",
    )
    labels = read_position_labels(path)
    assert labels["10"]["direction"] == "BUY"
    assert labels["10"]["session"] == "SESSION_LONDON"
    assert labels["10"]["initial_stop_distance_points"] == 120
    assert labels["10"]["exit_deal_reasons"] == ["DEAL_REASON_SL"]
    assert labels["10"]["spread_observation_complete"] is True
    assert labels["10"]["spread_volume_points_sum"] == pytest.approx(1.3)


def test_position_label_conflicts_fail_closed(tmp_path):
    path = tmp_path / "deals.csv"
    path.write_text(
        "position_id,direction,session,initial_stop_price,"
        "initial_stop_distance_points,deal_reason,spread_points_observed,spread_observed,volume,entry\n"
        "10,BUY,SESSION_LONDON,1.0800,120,DEAL_REASON_EXPERT,1.2,true,0.5,IN\n"
        "10,SELL,SESSION_LONDON,1.0800,120,DEAL_REASON_SL,1.4,true,0.5,OUT\n",
        encoding="utf-8",
    )
    labels = read_position_labels(path)
    assert labels["10"]["direction"] == "CONFLICT"
    assert labels["10"]["attribution_conflict"] is True


def test_outcome_reader_joins_by_stable_decision_id(tmp_path):
    path = tmp_path / "outcomes.csv"
    path.write_text(
        "DecisionID,RunID,Symbol,Direction,Session,SelectedStrategy,Regime,Outcome,"
        "MFE_R,MAE_R,BarsHeld,RealizedR,RealizedNetPnL,OutcomeEpoch,Filled,"
        "TP1_Hit,TP2_Hit,BreakEvenDone,PartialDone\n"
        "77,diagnostic-run,EURUSD,BUY,SESSION_LONDON,STRATEGY_SMC,REGIME_TRENDING,closed,"
        "1.2,0.8,12,0.1,2.5,1790000000,Yes,Yes,No,Yes,Yes\n",
        encoding="utf-8",
    )
    rows = read_decision_outcomes(path)
    assert len(rows) == 1
    assert rows[0]["decision_id"] == "77"
    assert rows[0]["run_id"] == "diagnostic-run"
    assert rows[0]["session"] == "SESSION_LONDON"
    assert rows[0]["mfe_r"] == 1.2
    assert rows[0]["realized_r"] == 0.1


def test_position_summary_uses_completed_positions_not_partial_rows():
    rows = [
        {"net_pnl": 10.0, "risk_cash": 5.0},
        {"net_pnl": -5.0, "risk_cash": 5.0},
        {"net_pnl": 0.0, "risk_cash": None},
    ]
    result = summarize(rows, 1000.0)
    assert result["positions"] == 3
    assert result["wins"] == 1
    assert result["losses"] == 1
    assert result["breakeven"] == 1
    assert result["profit_factor"] == 2.0
    assert result["expectancy_per_position"] == pytest.approx(5 / 3, abs=1e-4)



def test_research_eligibility_rejects_every_cohort_below_70_percent():
    result = assess_research_eligibility({
        "positions": 500,
        "win_rate_pct_excluding_flats": 69.99,
        "profit_factor": 1.8,
        "expectancy_per_position": 2.0,
    })
    assert result["eligible_for_independent_replication"] is False
    assert result["status"] == "not_eligible"
    assert "minimum_position_win_rate" in result["failed_checks"]


def test_research_eligibility_accepts_exactly_70_only_when_other_gates_pass():
    result = assess_research_eligibility({
        "positions": 100,
        "win_rate_pct_excluding_flats": 70.0,
        "profit_factor": 1.05,
        "expectancy_per_position": 0.01,
    })
    assert result["eligible_for_independent_replication"] is True
    assert result["status"] == "candidate_for_independent_replication"


def test_70_percent_win_rate_alone_never_overrides_negative_expectancy():
    result = assess_research_eligibility({
        "positions": 250,
        "win_rate_pct_excluding_flats": 85.0,
        "profit_factor": 0.95,
        "expectancy_per_position": -0.2,
    })
    assert result["eligible_for_independent_replication"] is False
    assert "minimum_profit_factor" in result["failed_checks"]
    assert "positive_net_expectancy" in result["failed_checks"]


def test_research_eligibility_rejects_small_samples_even_with_high_win_rate():
    result = assess_research_eligibility({
        "positions": 99,
        "win_rate_pct_excluding_flats": 90.0,
        "profit_factor": 2.0,
        "expectancy_per_position": 1.0,
    })
    assert result["eligible_for_independent_replication"] is False
    assert "minimum_completed_positions" in result["failed_checks"]



def test_every_direction_session_or_family_cohort_gets_its_own_70_percent_gate():
    positions = [
        {"symbol": "EURUSD", "strategy": "STRATEGY_SMC", "direction": "BUY", "session": "SESSION_LONDON",
         "net_pnl": 2.0, "risk_cash": 1.0}
        for _ in range(69)
    ] + [
        {"symbol": "EURUSD", "strategy": "STRATEGY_SMC", "direction": "BUY", "session": "SESSION_LONDON",
         "net_pnl": -1.0, "risk_cash": 1.0}
        for _ in range(31)
    ]
    groups = grouped_metrics(positions, 10000.0, ("symbol", "strategy", "direction", "session"))
    cohort = groups["EURUSD|STRATEGY_SMC|BUY|SESSION_LONDON"]
    assert cohort["win_rate_pct_excluding_flats"] == 69.0
    assert cohort["research_eligibility"]["eligible_for_independent_replication"] is False
    assert "minimum_position_win_rate" in cohort["research_eligibility"]["failed_checks"]
