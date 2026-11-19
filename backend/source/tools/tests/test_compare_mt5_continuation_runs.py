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
        "period_start": "2026-11-01T00:00:00Z",
        "period_end": "2027-02-27T17:18:40Z",
        "locked_oos_start": "2026-11-13T17:18:40Z",
        "locked_oos_end": "2027-02-13T17:18:40Z",
        "dataset_sha256": dataset_hash,
        "ea_source_sha": "a" * 40,
        "ea_build": "midas-v2.8-test",
        "terminal_build": "terminal-build-1",
        "data_vendor": "broker-real-tick-export",
        "spread_model": "real_ticks",
        "spread_points": None,
        "commission_per_lot": 7.0,
        "slippage_points": 1.0,
        "fill_policy": "real_ticks",
        "initial_balance": 10000.0,
        "risk_percent": 0.5,
        "account_currency": "USD",
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
    for role, enabled, strategy in (
        ("baseline", "false", "SMC"),
        ("continuation", "true", "FreshSweepContinuation"),
    ):
        preset = folder / f"{role}.set"
        preset.write_text(
            "\n".join([
                f"InpEnableFreshSweepAdditiveRouter={enabled}",
                "InpFreshSweepEnableSingleSwingFallback=false",
                "InpRiskPercent=0.5",
                "InpDynamicStopEnabled=true",
                "InpPartialAtR=0.5",
            ]) + "\n",
            encoding="utf-8",
        )
        report = folder / f"{role}.html"
        report.write_text(f"<html>{role} genuine tester export fixture</html>\n", encoding="utf-8")
        deals = folder / f"{role}-deals.csv"
        _write_deals(deals, strategy)
        open_ids = folder / f"{role}-open.csv"
        open_ids.write_text("position_id\n", encoding="utf-8")
        variants.append({
            "role": role,
            "run_id": f"mt5-{role}-run",
            "observed_context": dict(context),
            "parameters": {"InpRiskPercent": 0.5, "InpEnableFreshSweepAdditiveRouter": enabled},
            "input_preset": preset.name,
            "report_path": report.name,
            "deals_csv": deals.name,
            "open_positions_csv": open_ids.name,
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
        "InpRiskPercent=0.5", "InpRiskPercent=0.75"
    ), encoding="utf-8")
    with pytest.raises(ComparisonError, match="only MT5 input allowed to differ"):
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
