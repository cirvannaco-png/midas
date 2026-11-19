#!/usr/bin/env python3
"""Compare a baseline Midas MT5 EA run with the opt-in continuation-router run.

This consumes authentic, matched MT5 Strategy Tester artifacts. It does not run
MT5, simulate fills, score locked OOS entries, or approve production promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

try:
    from tools.compare_mt5_variant_runs import (
        CONTEXT_KEYS, _normalize_context, _require_same_context, _resolve_file,
        _sha256, _read_header, _lane_header_exists, _require_cost_headers,
        _metrics_for, _unresolved_entries_in_window, _metric_delta,
        ComparisonError,
    )
    from tools.cost_stress_monte_carlo import reject_reserved_oos_overlap
    from tools.position_ledger_metrics import (
        LedgerError, read_deals, read_open_ids, reconstruct_positions,
    )
except ImportError:
    from compare_mt5_variant_runs import (  # type: ignore
        CONTEXT_KEYS, _normalize_context, _require_same_context, _resolve_file,
        _sha256, _read_header, _lane_header_exists, _require_cost_headers,
        _metrics_for, _unresolved_entries_in_window, _metric_delta,
        ComparisonError,
    )
    from cost_stress_monte_carlo import reject_reserved_oos_overlap  # type: ignore
    from position_ledger_metrics import (  # type: ignore
        LedgerError, read_deals, read_open_ids, reconstruct_positions,
    )


ROLES = ("baseline", "continuation")
ALLOWED_ROOT = {"schema_version", "experiment_id", "test_context", "dataset_path", "variants"}
ALLOWED_VARIANT = {
    "role", "run_id", "observed_context", "parameters",
    "input_preset", "report_path", "deals_csv", "open_positions_csv",
}
BOOL_FALSE = {"false", "0", "no", "off"}
BOOL_TRUE = {"true", "1", "yes", "on"}


def _parse_set(path: Path, name: str) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise ComparisonError(f"cannot read {name}: {path}") from exc
    for line_number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith((";", "#")):
            continue
        if "=" not in stripped:
            raise ComparisonError(f"{name}:{line_number} is not a key=value MT5 input")
        key, value = stripped.split("=", 1)
        key, value = key.strip(), value.strip()
        if not key or key in values:
            raise ComparisonError(f"{name}:{line_number} has an empty or duplicate input name")
        values[key] = value
    if not values:
        raise ComparisonError(f"{name} is empty")
    return values


def _bool_value(values: dict[str, str], key: str, name: str) -> bool:
    if key not in values:
        raise ComparisonError(f"{name} is missing required input {key}")
    token = values[key].split("||", 1)[0].strip().lower()
    if token in BOOL_FALSE:
        return False
    if token in BOOL_TRUE:
        return True
    raise ComparisonError(f"{name}.{key} must be an explicit boolean value")


def _validate_presets(baseline_path: Path, candidate_path: Path) -> tuple[dict, dict]:
    baseline = _parse_set(baseline_path, "baseline preset")
    candidate = _parse_set(candidate_path, "continuation preset")
    if set(baseline) != set(candidate):
        missing_candidate = sorted(set(baseline) - set(candidate))
        missing_baseline = sorted(set(candidate) - set(baseline))
        raise ComparisonError(
            "baseline and continuation presets must contain identical input keys "
            f"(missing from candidate={missing_candidate}; missing from baseline={missing_baseline})"
        )

    toggle = "InpEnableFreshSweepAdditiveRouter"
    fallback = "InpFreshSweepEnableSingleSwingFallback"
    if _bool_value(baseline, toggle, "baseline") is not False:
        raise ComparisonError("baseline must set InpEnableFreshSweepAdditiveRouter=false")
    if _bool_value(candidate, toggle, "continuation") is not True:
        raise ComparisonError("continuation preset must set InpEnableFreshSweepAdditiveRouter=true")
    if _bool_value(baseline, fallback, "baseline") is not False:
        raise ComparisonError("baseline must keep InpFreshSweepEnableSingleSwingFallback=false")
    if _bool_value(candidate, fallback, "continuation") is not False:
        raise ComparisonError("continuation must keep InpFreshSweepEnableSingleSwingFallback=false")

    changed = [key for key in baseline if baseline[key] != candidate[key]]
    if changed != [toggle] and set(changed) != {toggle}:
        raise ComparisonError(
            "the only MT5 input allowed to differ is InpEnableFreshSweepAdditiveRouter; "
            f"changed inputs: {changed}"
        )
    return baseline, candidate


def compare_manifest(manifest_path: str | Path) -> tuple[dict[str, Any], dict[str, Any]]:
    source_path = Path(manifest_path).expanduser().resolve()
    try:
        manifest = json.loads(source_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ComparisonError(f"cannot read valid UTF-8 JSON manifest: {source_path}") from exc
    if not isinstance(manifest, dict):
        raise ComparisonError("manifest root must be a JSON object")
    unknown = sorted(set(manifest) - ALLOWED_ROOT)
    missing = sorted(ALLOWED_ROOT - set(manifest))
    if unknown or missing:
        raise ComparisonError(f"manifest root keys invalid; unknown={unknown}; missing={missing}")
    if manifest["schema_version"] != 1:
        raise ComparisonError("schema_version must be 1")
    experiment_id = manifest["experiment_id"]
    if not isinstance(experiment_id, str) or not experiment_id.strip():
        raise ComparisonError("experiment_id must be a non-empty string")

    context = _normalize_context(manifest["test_context"], "test_context")
    period_start, period_end = context["period_start"], context["period_end"]
    locked_oos_start, locked_oos_end = context["locked_oos_start"], context["locked_oos_end"]
    # Development analysis is required to stop precisely at the OOS entry boundary.
    reject_reserved_oos_overlap(period_start, locked_oos_start)

    dataset = _resolve_file(source_path, manifest["dataset_path"], "dataset_path")
    dataset_hash = _sha256(dataset)
    if dataset_hash != context["dataset_sha256"]:
        raise ComparisonError("dataset_sha256 does not match the actual dataset_path digest")

    variants = manifest["variants"]
    if not isinstance(variants, list) or len(variants) != 2:
        raise ComparisonError("variants must contain exactly baseline and continuation")
    by_role: dict[str, dict] = {}
    preset_paths: dict[str, Path] = {}
    run_ids: set[str] = set()
    preset_hashes: set[str] = set()
    artifact_paths: set[Path] = set()

    for index, raw in enumerate(variants):
        name = f"variants[{index}]"
        if not isinstance(raw, dict):
            raise ComparisonError(f"{name} must be a JSON object")
        unknown = sorted(set(raw) - ALLOWED_VARIANT)
        missing = sorted(ALLOWED_VARIANT - set(raw))
        if unknown or missing:
            raise ComparisonError(f"{name} keys invalid; unknown={unknown}; missing={missing}")
        role = raw["role"]
        if role not in ROLES or role in by_role:
            raise ComparisonError(f"{name}.role must be unique and one of {ROLES}")
        run_id = raw["run_id"]
        if not isinstance(run_id, str) or not run_id.strip() or run_id in run_ids:
            raise ComparisonError(f"{name}.run_id must be non-empty and unique")
        run_ids.add(run_id)

        observed = _normalize_context(raw["observed_context"], f"{name}.observed_context")
        _require_same_context(context, observed, f"{name}.observed_context")
        parameters = raw["parameters"]
        if not isinstance(parameters, dict) or not parameters:
            raise ComparisonError(f"{name}.parameters must be a non-empty JSON object")
        try:
            json.dumps(parameters, allow_nan=False)
        except (TypeError, ValueError) as exc:
            raise ComparisonError(f"{name}.parameters must contain finite JSON values") from exc

        preset = _resolve_file(source_path, raw["input_preset"], f"{name}.input_preset")
        report = _resolve_file(source_path, raw["report_path"], f"{name}.report_path")
        deals_path = _resolve_file(source_path, raw["deals_csv"], f"{name}.deals_csv")
        open_path = _resolve_file(
            source_path, raw["open_positions_csv"], f"{name}.open_positions_csv", allow_empty=False
        )
        if preset.suffix.lower() != ".set":
            raise ComparisonError(f"{name}.input_preset must be an MT5 .set file")
        for artifact in (preset, report, deals_path, open_path):
            if artifact in artifact_paths:
                raise ComparisonError(f"artifact path reused across variants: {artifact}")
            artifact_paths.add(artifact)
        preset_paths[role] = preset
        preset_hash = _sha256(preset)
        if preset_hash in preset_hashes:
            raise ComparisonError("baseline and continuation .set files must have different SHA-256 hashes")
        preset_hashes.add(preset_hash)

        if not _lane_header_exists(_read_header(deals_path)):
            raise ComparisonError(f"{name}.deals_csv requires a lane/risk_lane/entry_lane column")
        header = {re.sub(r"[^a-z0-9]", "", col.lower()) for col in _read_header(deals_path)}
        if "strategy" not in header:
            raise ComparisonError(f"{name}.deals_csv requires explicit strategy attribution")
        _require_cost_headers(deals_path)
        try:
            deals = read_deals(deals_path)
            open_ids = read_open_ids(open_path)
            positions, ignored = reconstruct_positions(deals, open_ids)
        except (OSError, LedgerError) as exc:
            raise ComparisonError(f"{name} deal-ledger validation failed: {exc}") from exc

        in_period = [p for p in positions if period_start <= p["opened_at"] < period_end]
        development = [p for p in in_period if p["opened_at"] < locked_oos_start and p["closed_at"] < locked_oos_start]
        censored = sum(
            1 for p in in_period
            if p["opened_at"] < locked_oos_start and p["closed_at"] >= locked_oos_start
        )
        unresolved = _unresolved_entries_in_window(deals, positions, period_start, locked_oos_start)
        missing_strategy = [
            p["position_id"] for p in development
            if p.get("strategy") in {"", "UNTAGGED", "UNKNOWN", "CONFLICT", None}
        ]
        if missing_strategy:
            raise ComparisonError(
                f"{name} has development positions without reliable strategy attribution: "
                + ", ".join(str(pid) for pid in missing_strategy[:10])
            )

        continuation_positions = [
            p for p in development
            if "FRESH SWEEP CONTINUATION" in p["strategy"].upper().replace("_", " ")
            or "FRESH SWEEP CONTINUATION" in p["strategy"].upper().replace("-", " ")
            or "FRESHSWEEPCONTINUATION" in p["strategy"].upper()
        ]
        by_role[role] = {
            "role": role,
            "run_id": run_id,
            "parameters": parameters,
            "input_preset_values": _parse_set(preset, f"{role} preset"),
            "artifacts": {
                "input_preset": {"path": str(preset), "sha256": preset_hash},
                "report": {"path": str(report), "sha256": _sha256(report)},
                "deals_csv": {"path": str(deals_path), "sha256": _sha256(deals_path)},
                "open_positions_csv": {"path": str(open_path), "sha256": _sha256(open_path)},
            },
            "metrics": {"development": _metrics_for(development, context["initial_balance"])},
            "ledger_diagnostics": {
                "positions_opened_in_declared_period": len(in_period) + unresolved,
                "development_completed_positions": len(development),
                "development_boundary_censored_positions": censored,
                "development_unresolved_or_open_entries": unresolved,
                "development_strategy_attribution_complete": True,
            },
            "continuation_router_positions": len(continuation_positions),
            "continuation_router_strategy_names": sorted({p["strategy"] for p in continuation_positions}),
        }

    missing_roles = [role for role in ROLES if role not in by_role]
    if missing_roles:
        raise ComparisonError(f"manifest missing roles: {missing_roles}")
    _validate_presets(preset_paths["baseline"], preset_paths["continuation"])
    baseline = by_role["baseline"]
    candidate = by_role["continuation"]
    if baseline["continuation_router_positions"] != 0:
        raise ComparisonError("baseline contains continuation-router strategy trades; the baseline is not isolated")
    if candidate["continuation_router_positions"] == 0:
        router_observed = False
    else:
        router_observed = True

    payload = {
        "status": "comparison_completed",
        "experiment_id": experiment_id.strip(),
        "comparison_only": True,
        "promotion_recommendation": None,
        "test_context": {
            key: (value.isoformat() if hasattr(value, "isoformat") else value)
            for key, value in context.items()
        },
        "dataset_artifact": {"path": str(dataset), "sha256": dataset_hash},
        "variants": by_role,
        "continuation_router_exercised": router_observed,
        "continuation_candidate_delta_vs_baseline": {
            "development": _metric_delta(
                candidate["metrics"]["development"], baseline["metrics"]["development"]
            )
        },
        "locked_oos_status": (
            "withheld; this tool scores development entries only and does not inspect OOS outcomes"
        ),
        "interpretation_limits": [
            "This tool compares exported MT5 runs; it does not launch or simulate MT5.",
            "Closed-position drawdown is not tick-level equity drawdown; retain native tester equity statistics.",
            "The matched pair proves only the incremental effect of the continuation input under this frozen test context.",
            "Zero continuation trades means the candidate router was not exercised; no efficacy claim is possible.",
            "No statistical significance or production approval is inferred.",
        ],
    }
    summary = {
        "status": payload["status"],
        "experiment_id": payload["experiment_id"],
        "matched_context_verified": True,
        "dataset_digest_verified": True,
        "only_router_enable_input_differs": True,
        "single_swing_fallback_disabled_in_both": True,
        "continuation_router_exercised": router_observed,
        "locked_oos_scored": False,
        "mt5_run_performed_by_this_tool": False,
        "promotion_recommendation": None,
    }
    return payload, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, help="JSON manifest with authentic matched MT5 runs")
    parser.add_argument("--output", required=True, help="Path for comparison JSON output")
    args = parser.parse_args()
    try:
        payload, summary = compare_manifest(args.manifest)
        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(json.dumps({
            **summary,
            "output": str(output),
            "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        }, indent=2))
        return 0
    except (ComparisonError, LedgerError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
