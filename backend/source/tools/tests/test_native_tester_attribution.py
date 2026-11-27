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
)


def test_metadata_requires_complete_reconciled_export(tmp_path):
    path = tmp_path / "meta.json"
    path.write_text(
        '{"export_status":"complete","history_expected_deals":2,'
        '"history_recorded_deals":2,"history_missing_deals":0,'
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
    with pytest.raises(AttributionError, match="conflicting direction"):
        read_position_labels(path)


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
    assert result["expectancy_per_position"] == pytest.approx(5 / 3)
