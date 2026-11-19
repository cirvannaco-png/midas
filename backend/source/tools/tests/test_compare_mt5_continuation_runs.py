import csv
import hashlib
import json
from pathlib import Path

import pytest

from tools.compare_mt5_continuation_runs import ComparisonError, compare_manifest


def _context(dataset_hash):
    return {
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "period_start": "2026-10-01T21:00:00Z",
        "period_end": "2027-02-27T17:18:40Z",
        "locked_oos_start": "2026-11-13T17:18:40Z",
        "locked_oos_end": "2027-02-13T17:18:40Z",
        "dataset_sha256": dataset_hash,
        "ea_source_sha": "a" * 40,
        "ea_build": "midas-v2.8-test",
        "terminal_build": "5000",
        "data_vendor": "broker-real-tick-export",
        "spread_model": "real_ticks",
        "spread_points": None,
        "commission_per_lot": 0.0,
        "slippage_points": 0.0,
        "fill_policy": "real_ticks",
        "initial_balance": 1500.0,
        "risk_percent": 20.0,
        "account_currency": "KES",
        "leverage": "1:500",
    }


def _write_deals(path, strategy):
    fields = [
        "position_id", "time", "entry", "volume", "profit",
        "commission", "swap", "fee", "risk_cash", "lane",
        "strategy", "regime",
    ]
    rows = [
        ["P1", "2026-11-02T10:00:00Z", "IN", 0.1, 0, -0.7, 0, 0, 50, "EA", strategy, "TRENDING"],
        ["P1", "2026-11-02T11:00:00Z", "OUT", 0.1, 4, -0.7, 0, 0, 50, "EA", strategy, "TRENDING"],
    ]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(fields)
        writer.writerows(rows)


def _make_manifest(folder: Path):
    folder.mkdir(parents=True, exist_ok=True)
    dataset = folder / "ticks.zip"
    dataset.write_bytes(b"immutable test tick data")
    context = _context(hashlib.sha256(dataset.read_bytes()).hexdigest())
    variants = []
    for role, enabled, strategy, suffix in (
        ("baseline", "false", "SMC", "1001"),
        ("continuation", "true", "FreshSweepContinuation", "2002"),
    ):
        export_label = "matched-continuation-pair"
        preset = folder / f"{role}.set"
        values = [
            f"InpEnableFreshSweepAdditiveRouter={enabled}",
            "InpFreshSweepEnableSingleSwingFallback=false",
            "InpEnableExecution=true",
            "InpRequireExecutionLedger=false",
            "InpEnableDynamicStop=true",
            "InpTrackOutcomes=true",
            "InpAllowMinLotOverride=false",
            "InpAccountRiskProfile=1",
            "InpSmallAccountProfileConfigured=true",
            "InpSmallMinimumRiskPercentPerTrade=15.0",
            "InpSmallRiskPercentPerTrade=20.0",
            "InpSmallMaxDailyLossPercent=25.0",
            "InpSmallMaxDrawdownPercent=35.0",
            "InpSmallMaxPortfolioRiskPercent=20.0",
            "InpSmallGoldMaxStopRiskKES=7.50",
            "InpSmallMaxOpenTrades=3",
            "InpSmallMaxPositionsPerSymbol=3",
            "InpSmallMaxPositionsPerGroup=3",
            "InpAccountCurrencyPerKES=0.0",
            "InpTesterServerUtcOffsetMinutes=180",
            f"InpTesterExportRunId={export_label}",
            "InpPartialAtR=2.0",
            "InpPartialFraction=0.5",
            "InpDynamicStopActivateAtR=0.75",
            "InpDynamicStopBreakevenAtR=1.0",
            "InpDynamicStopATRMult=1.5",
        ]
        preset.write_text("\n".join(values) + "\n", encoding="utf-8")

        report = folder / f"{role}.html"
        report.write_text(f"<html>{role} genuine tester export fixture</html>\n", encoding="utf-8")
        deals = folder / f"{role}-deals.csv"
        _write_deals(deals, strategy)
        open_ids = folder / f"{role}-open.csv"
        open_ids.write_text("position_id\n", encoding="utf-8")

        run_id = f"{export_label}_{suffix}"
        metadata_path = folder / f"{role}-metadata.json"
        metadata_path.write_text(json.dumps({
            "run_id": run_id,
            "symbol": "XAUUSD",
            "server": "Broker-Demo-KES",
            "account_currency": "KES",
            "leverage": 500,
            "initial_balance": 1500.0,
            "terminal_build": 5000,
            "point": 0.01,
            "tick_size": 0.01,
            "tick_value": 10.0,
            "cash_per_point_per_lot": 10.0,
            "spread_points_mean": 2.0,
            "spread_points_max": 5.0,
            "spread_samples": 1000,
            "fill_mode": 2,
            "server_utc_offset_minutes": 180,
            "timestamp_basis": "broker_wall_clock_with_explicit_offset",
        }, indent=2), encoding="utf-8")

        tester_config_path = folder / f"{role}-tester.ini"
        tester_config_path.write_text("\n".join([
            "[Tester]",
            "Expert=MedisTouch_v2.8.ex5",
            f"ExpertParameters={preset.name}",
            "Symbol=XAUUSD",
            "Period=M15",
            "Model=4",
            "ExecutionMode=100",
            "Optimization=0",
            "FromDate=2026.10.02",
            "ToDate=2026.11.12",
            "Deposit=1500",
            "Currency=KES",
            "Leverage=1:500",
            "ForwardMode=0",
            f"Report={role}-tester-report",
        ]) + "\n", encoding="utf-8")
        variants.append({
            "role": role,
            "run_id": run_id,
            "observed_context": dict(context),
            "parameters": {
                "InpSmallRiskPercentPerTrade": 20.0,
                "InpEnableFreshSweepAdditiveRouter": enabled,
                "InpRequireExecutionLedger": False,
            },
            "input_preset": preset.name,
            "report_path": report.name,
            "deals_csv": deals.name,
            "open_positions_csv": open_ids.name,
            "tester_metadata_path": metadata_path.name,
            "tester_config_path": tester_config_path.name,
        })
    manifest = folder / "manifest.json"
    manifest.write_text(json.dumps({
        "schema_version": 1,
        "experiment_id": "midas-matched-continuation-test",
        "test_context": context,
        "dataset_path": dataset.name,
        "variants": variants,
    }, indent=2), encoding="utf-8")
    return manifest


def test_matched_continuation_comparison_validates_risk_controls_and_detects_router_trade(tmp_path):
    report, summary = compare_manifest(_make_manifest(tmp_path))
    assert summary["matched_context_verified"] is True
    assert summary["dataset_digest_verified"] is True
    assert summary["only_router_enable_input_differs"] is True
    assert summary["single_swing_fallback_disabled_in_both"] is True
    assert summary["tester_execution_enabled_in_both"] is True
    assert summary["external_execution_ledger_disabled_for_strategy_tester_only"] is True
    assert summary["dynamic_stops_enabled_in_both"] is True
    assert summary["small_account_safety_ceilings_verified"] is True
    assert summary["broker_metadata_validated_for_cost_stress"] is True
    assert summary["mt5_every_tick_real_ticks_model_verified"] is True
    assert summary["nonzero_matched_execution_delay_verified"] is True
    assert summary["tester_optimization_disabled"] is True
    assert report["variants"]["baseline"]["tester_config"]["model"] == 4
    assert report["variants"]["baseline"]["tester_config"]["execution_mode"] == 100
    assert report["variants"]["baseline"]["tester_metadata"]["cash_per_point_per_lot"] == 10.0
    assert report["variants"]["continuation"]["tester_metadata"]["server"] == "Broker-Demo-KES"
    assert summary["locked_oos_scored"] is False
    assert report["continuation_router_exercised"] is True
    assert report["variants"]["baseline"]["continuation_router_positions"] == 0
    assert report["variants"]["continuation"]["continuation_router_positions"] == 1
    assert report["variants"]["baseline"]["metrics"]["development"]["completed_positions"] == 1


def test_matched_continuation_comparison_rejects_any_risk_or_exit_preset_change(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate = tmp_path / manifest["variants"][1]["input_preset"]
    candidate.write_text(candidate.read_text(encoding="utf-8").replace(
        "InpSmallRiskPercentPerTrade=20.0", "InpSmallRiskPercentPerTrade=20.1"
    ), encoding="utf-8")
    with pytest.raises(ComparisonError, match="small-account target risk must be within"):
        compare_manifest(manifest_path)


def test_matched_continuation_comparison_rejects_enabled_single_swing_fallback(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate = tmp_path / manifest["variants"][1]["input_preset"]
    candidate.write_text(candidate.read_text(encoding="utf-8").replace(
        "InpFreshSweepEnableSingleSwingFallback=false",
        "InpFreshSweepEnableSingleSwingFallback=true"
    ), encoding="utf-8")
    with pytest.raises(ComparisonError, match="continuation must keep InpFreshSweepEnableSingleSwingFallback=false"):
        compare_manifest(manifest_path)


def test_matched_continuation_comparison_rejects_strategy_attribution_missing(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    deals = tmp_path / manifest["variants"][1]["deals_csv"]
    text = deals.read_text(encoding="utf-8").replace("strategy,", "strategy,")
    rows = list(csv.DictReader(text.splitlines()))
    fields = list(rows[0])
    fields.remove("strategy")
    with deals.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            row.pop("strategy", None)
            writer.writerow(row)
    with pytest.raises(ComparisonError, match="requires explicit strategy attribution"):
        compare_manifest(manifest_path)


@pytest.mark.parametrize(
    ("key", "replacement", "message"),
    [
        ("InpRequireExecutionLedger=false", "InpRequireExecutionLedger=true", "InpRequireExecutionLedger=false"),
        ("InpEnableExecution=true", "InpEnableExecution=false", "InpEnableExecution=true"),
        ("InpEnableDynamicStop=true", "InpEnableDynamicStop=false", "InpEnableDynamicStop=true"),
        ("InpTesterServerUtcOffsetMinutes=180", "InpTesterServerUtcOffsetMinutes=99999", "does not match the preset input"),
        ("InpSmallGoldMaxStopRiskKES=7.50", "InpSmallGoldMaxStopRiskKES=8.00", "GoldMaxStopRiskKES"),
        ("InpSmallMaxDrawdownPercent=35.0", "InpSmallMaxDrawdownPercent=40.0", "MaxDrawdownPercent"),
    ],
)
def test_matched_pair_rejects_tester_bypass_or_weakened_risk_settings(
    tmp_path, key, replacement, message
):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate = tmp_path / manifest["variants"][1]["input_preset"]
    original = candidate.read_text(encoding="utf-8")
    assert key in original
    candidate.write_text(original.replace(key, replacement), encoding="utf-8")
    with pytest.raises(ComparisonError, match=message):
        compare_manifest(manifest_path)


def test_matched_pair_rejects_tester_metadata_contract_value_mismatch(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    metadata_path = tmp_path / manifest["variants"][1]["tester_metadata_path"]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["cash_per_point_per_lot"] = 999.0
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    with pytest.raises(ComparisonError, match="cash_per_point_per_lot does not reconcile"):
        compare_manifest(manifest_path)


def test_matched_pair_rejects_missing_tester_metadata_file(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    (tmp_path / manifest["variants"][0]["tester_metadata_path"]).unlink()
    with pytest.raises(ComparisonError, match="tester_metadata_path does not exist"):
        compare_manifest(manifest_path)


def test_matched_pair_rejects_non_unique_run_ids(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["variants"][1]["run_id"] = manifest["variants"][0]["run_id"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ComparisonError, match="run_id must be non-empty and unique"):
        compare_manifest(manifest_path)



def test_matched_pair_rejects_broker_server_or_contract_metadata_mismatch(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    metadata_path = tmp_path / manifest["variants"][1]["tester_metadata_path"]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["server"] = "Different-Broker-Server"
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    with pytest.raises(ComparisonError, match="tester metadata differ.*server"):
        compare_manifest(manifest_path)


def test_matched_pair_rejects_different_real_tick_spread_observations(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    metadata_path = tmp_path / manifest["variants"][1]["tester_metadata_path"]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["spread_points_max"] = 6.0
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
    with pytest.raises(ComparisonError, match="tester metadata differ.*spread_points_max"):
        compare_manifest(manifest_path)



@pytest.mark.parametrize(
    ("old", "new", "message"),
    [
        ("Model=4", "Model=0", "Model=4"),
        ("ExecutionMode=100", "ExecutionMode=0", "ExecutionMode must be"),
        ("Optimization=0", "Optimization=1", "Optimization=0"),
        ("Leverage=1:500", "Leverage=1:100", "Leverage does not match"),
    ],
)
def test_matched_pair_rejects_nonreal_tick_or_unmatched_tester_launch_settings(
    tmp_path, old, new, message
):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate_config = tmp_path / manifest["variants"][1]["tester_config_path"]
    original = candidate_config.read_text(encoding="utf-8")
    assert old in original
    candidate_config.write_text(original.replace(old, new), encoding="utf-8")
    with pytest.raises(ComparisonError, match=message):
        compare_manifest(manifest_path)


def test_matched_pair_rejects_different_tester_execution_delays(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate_config = tmp_path / manifest["variants"][1]["tester_config_path"]
    original = candidate_config.read_text(encoding="utf-8")
    candidate_config.write_text(original.replace("ExecutionMode=100", "ExecutionMode=250"), encoding="utf-8")
    with pytest.raises(ComparisonError, match="tester launch configurations differ.*execution_mode"):
        compare_manifest(manifest_path)



def test_matched_pair_rejects_tester_to_date_that_reaches_locked_oos_start_day(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate_config = tmp_path / manifest["variants"][1]["tester_config_path"]
    original = candidate_config.read_text(encoding="utf-8")
    candidate_config.write_text(
        original.replace("ToDate=2026.11.12", "ToDate=2026.11.13"),
        encoding="utf-8",
    )
    with pytest.raises(ComparisonError, match="ToDate must be the day before the exclusive locked-OOS start"):
        compare_manifest(manifest_path)


def test_matched_pair_rejects_tester_from_date_not_aligned_to_broker_midnight(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate_config = tmp_path / manifest["variants"][1]["tester_config_path"]
    original = candidate_config.read_text(encoding="utf-8")
    candidate_config.write_text(
        original.replace("FromDate=2026.10.02", "FromDate=2026.10.01"),
        encoding="utf-8",
    )
    with pytest.raises(ComparisonError, match="FromDate does not match the verified broker-local start date"):
        compare_manifest(manifest_path)



def test_matched_pair_rejects_context_that_claims_a_non_real_tick_spread_model(tmp_path):
    manifest_path = _make_manifest(tmp_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["test_context"]["spread_model"] = "fixed_points"
    manifest["test_context"]["spread_points"] = 2.0
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ComparisonError, match="spread_model=real_ticks"):
        compare_manifest(manifest_path)
