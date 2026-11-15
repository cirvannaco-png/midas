from __future__ import annotations
import csv
import hashlib
import json
from datetime import datetime, timedelta, timezone
import pytest
from research.confidence_diagnostics.evaluate import EvaluationError, evaluate_dataset, run

def make_manifest():
    return {
        "schema_version": 1, "dataset_id": "gold-m15-oos-01",
        "source_kind": "mt5_strategy_tester", "ea_source_sha": "a" * 40,
        "ea_build": "ea-build-01", "terminal_build": "mt5-build-01",
        "symbol": "XAUUSD", "timeframe": "M15", "provider": "IC Markets",
        "period_start": "2025-01-01T00:00:00Z", "period_end": "2026-11-01T00:00:00Z",
        "market_data_sha256": "b" * 64, "spread_model": "real_ticks",
        "commission_model": "7 USD round trip per lot", "slippage_model": "2 points",
        "fill_policy": "real_ticks", "initial_balance": 1500, "account_currency": "USD",
        "strategy_version": "strategy-v1", "model_version": "model-v1",
        "weight_version": "weights-v1", "calibration_version": "calibration-v1",
        "feature_schema_version": "feature-v1", "environment_schema_version": "env-v1",
        "train_end": "2026-05-31T23:59:59Z", "holdout_start": "2026-06-01T00:00:00Z",
        "evaluation_cutoff": "2026-11-15T00:00:00Z",
    }

def make_row(i, winner):
    t = datetime(2026, 6, 1, tzinfo=timezone.utc) + timedelta(days=i)
    return {
        "decision_id": f"d-{i}", "position_id": f"p-{i}",
        "signal_time": t.isoformat().replace("+00:00", "Z"),
        "outcome_time": (t + timedelta(hours=2)).isoformat().replace("+00:00", "Z"),
        "outcome_status": "win" if winner else "loss", "filled": "true",
        "outcome_history_complete": "true", "cashflows_known": "true",
        "confidence_at_signal": str(30 + i % 30),
        "env_exec_confidence": str((75 + i % 10) if winner else (15 + i % 10)),
        "realized_r": "1.0" if winner else "-1.0",
    }

def balanced_rows(count=60):
    return [make_row(i, True) for i in range(count)] + [make_row(i + count, False) for i in range(count)]

def test_diagnostic_adds_oos_ranking_signal_but_cannot_promote_live_changes():
    report = evaluate_dataset(make_manifest(), balanced_rows(), bootstrap_repetitions=300, seed=3)
    assert report["verdict"] == "INCREMENTAL_PREDICTIVE_SIGNAL"
    assert report["promotion_authorized"] is False
    assert report["live_parameters_changed"] is False
    assert report["probability_calibration_claim"] is False
    assert report["env_exec_confidence"]["win_loss_auc"] > report["raw_confidence"]["win_loss_auc"]
    assert report["env_exec_confidence"]["spearman_rho"] > report["raw_confidence"]["spearman_rho"]
    assert report["incremental_comparison"]["paired_auc_delta_bootstrap_95pct_ci"]["low"] > 0

def test_insufficient_sample_is_not_promoted():
    report = evaluate_dataset(make_manifest(), balanced_rows(10), min_holdout_positions=100,
                              min_winners=30, min_losers=30, bootstrap_repetitions=100)
    assert report["verdict"] == "INSUFFICIENT_EVIDENCE"
    assert report["promotion_authorized"] is False
    assert report["reasons"]

def test_excludes_development_ambiguous_no_fill_incomplete_and_unresolved_rows():
    rows = balanced_rows()
    dev = make_row(200, True); dev["signal_time"] = "2026-05-20T00:00:00Z"
    no_fill = make_row(201, True)
    no_fill.update(signal_time="2026-10-01T00:00:00Z", outcome_time="2026-10-01T01:00:00Z",
                   outcome_status="no_fill", filled="false", position_id="", realized_r="0")
    ambiguous = make_row(202, False)
    ambiguous.update(signal_time="2026-10-02T00:00:00Z", outcome_time="2026-10-02T01:00:00Z",
                     outcome_status="ambiguous", cashflows_known="false")
    incomplete = make_row(203, True)
    incomplete.update(signal_time="2026-10-03T00:00:00Z", outcome_time="2026-10-03T01:00:00Z",
                      outcome_history_complete="false")
    unresolved = make_row(204, False)
    unresolved.update(signal_time="2026-10-04T00:00:00Z", outcome_time="2026-11-16T00:00:00Z")
    report = evaluate_dataset(make_manifest(), rows + [dev, no_fill, ambiguous, incomplete, unresolved],
                              bootstrap_repetitions=100)
    assert report["eligible_holdout_positions"] == 120
    assert report["excluded_rows"] == {
        "ambiguous": 1, "development_before_holdout": 1, "incomplete_outcome_history": 1,
        "no_fill": 1, "not_resolved_by_evaluation_cutoff": 1,
    }

def test_duplicate_decision_is_rejected():
    rows = balanced_rows(); rows.append(dict(rows[0]))
    with pytest.raises(EvaluationError, match="duplicate decision_id"):
        evaluate_dataset(make_manifest(), rows, bootstrap_repetitions=100)

def test_manifest_provenance_and_chronology_are_mandatory():
    bad = make_manifest(); bad.pop("ea_source_sha")
    with pytest.raises(EvaluationError, match="ea_source_sha"):
        evaluate_dataset(bad, balanced_rows(), bootstrap_repetitions=100)
    bad = make_manifest(); bad["holdout_start"] = "2026-05-01T00:00:00Z"
    with pytest.raises(EvaluationError, match="train_end < holdout_start"):
        evaluate_dataset(bad, balanced_rows(), bootstrap_repetitions=100)

def test_timestamps_must_be_timezone_aware():
    rows = balanced_rows(); rows[0]["signal_time"] = "2026-06-01T00:00:00"
    with pytest.raises(EvaluationError, match="explicit timezone"):
        evaluate_dataset(make_manifest(), rows, bootstrap_repetitions=100)

def test_score_range_and_status_must_match_realized_r():
    rows = balanced_rows(); rows[0]["env_exec_confidence"] = "101"
    with pytest.raises(EvaluationError, match=r"within \[0, 100\]"):
        evaluate_dataset(make_manifest(), rows, bootstrap_repetitions=100)
    rows = balanced_rows(); rows[0]["realized_r"] = "-0.5"
    with pytest.raises(EvaluationError, match="conflicts with realized_r"):
        evaluate_dataset(make_manifest(), rows, bootstrap_repetitions=100)

def test_scratch_remains_in_expectancy_but_is_not_a_binary_auc_class():
    rows = balanced_rows(); scratch = make_row(121, True)
    scratch.update(outcome_status="scratch", realized_r="0"); rows.append(scratch)
    report = evaluate_dataset(make_manifest(), rows, bootstrap_repetitions=100)
    assert report["eligible_holdout_positions"] == 121
    assert report["raw_confidence"]["n_scratch"] == 1
    assert report["raw_confidence"]["win_loss_auc"] is not None

def test_csv_runner_hashes_exact_export(tmp_path):
    manifest_path, outcomes_path = tmp_path / "manifest.json", tmp_path / "outcomes.csv"
    manifest_path.write_text(json.dumps(make_manifest()), encoding="utf-8")
    rows = balanced_rows()
    with outcomes_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    expected = hashlib.sha256(outcomes_path.read_bytes()).hexdigest()
    report = run(manifest_path, outcomes_path, bootstrap_repetitions=100)
    assert report["outcomes_csv_sha256"] == expected
    assert report["row_count"] == 120

def test_bad_market_data_hash_is_rejected():
    bad = make_manifest(); bad["market_data_sha256"] = "not-a-sha256"
    with pytest.raises(EvaluationError, match="market_data_sha256"):
        evaluate_dataset(bad, balanced_rows(), bootstrap_repetitions=100)


def test_signal_before_declared_period_is_rejected():
    rows = balanced_rows()
    rows[0]["signal_time"] = "2024-12-31T23:59:59Z"
    with pytest.raises(EvaluationError, match="precedes the declared test period"):
        evaluate_dataset(make_manifest(), rows, bootstrap_repetitions=100)
