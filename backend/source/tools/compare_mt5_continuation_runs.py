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
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
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
ALLOWED_ROOT = {"schema_version", "experiment_id", "test_context", "dataset_path", "server_timezone_evidence_path", "variants"}
ALLOWED_VARIANT = {
    "role", "run_id", "observed_context", "parameters",
    "input_preset", "report_path", "deals_csv", "open_positions_csv",
    "tester_metadata_path", "tester_config_path",
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


def _numeric_value(values: dict[str, str], key: str, name: str) -> float:
    if key not in values:
        raise ComparisonError(f"{name} is missing required input {key}")
    token = values[key].split("||", 1)[0].strip()
    try:
        value = float(token)
    except ValueError as exc:
        raise ComparisonError(f"{name}.{key} must be numeric") from exc
    if not math.isfinite(value):
        raise ComparisonError(f"{name}.{key} must be finite")
    return value


def _integer_value(values: dict[str, str], key: str, name: str) -> int:
    value = _numeric_value(values, key, name)
    if not value.is_integer():
        raise ComparisonError(f"{name}.{key} must be an integer")
    return int(value)


def _parse_tester_ini(path: Path, name: str) -> dict[str, str]:
    """Read the [Tester] section from the exact MT5 terminal launch INI."""
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise ComparisonError(f"{name} cannot read tester configuration INI: {path}") from exc

    section = ""
    values: dict[str, str] = {}
    for line_number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith((";", "#")):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1].strip().casefold()
            continue
        if section != "tester":
            continue
        if "=" not in stripped:
            raise ComparisonError(f"{name} tester INI line {line_number} is not key=value")
        key, value = stripped.split("=", 1)
        key, value = key.strip(), value.strip()
        normalized = key.casefold()
        if not normalized or normalized in values:
            raise ComparisonError(f"{name} tester INI has an empty or duplicate [Tester] key")
        values[normalized] = value

    if not values:
        raise ComparisonError(f"{name} tester INI is missing a non-empty [Tester] section")
    return values


def _parse_utc_timestamp(value: Any, *, name: str, field: str) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise ComparisonError(f"{name} timezone evidence {field} must be a non-empty ISO-8601 UTC timestamp")
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError as exc:
        raise ComparisonError(f"{name} timezone evidence {field} must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timedelta(0):
        raise ComparisonError(f"{name} timezone evidence {field} must explicitly use UTC")
    return parsed.astimezone(timezone.utc)


def _load_server_timezone_evidence(
    evidence_path: Path, *, broker_server: str, name: str
) -> tuple[ZoneInfo, dict[str, Any]]:
    try:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ComparisonError(f"{name} cannot read valid broker timezone evidence JSON: {evidence_path}") from exc
    required = {"schema_version", "broker_server", "iana_timezone", "source_reference", "verified_at_utc"}
    if not isinstance(evidence, dict) or set(evidence) != required:
        raise ComparisonError(
            f"{name} broker timezone evidence keys invalid; required exactly: {sorted(required)}"
        )
    if evidence["schema_version"] != 1:
        raise ComparisonError(f"{name} broker timezone evidence schema_version must be 1")
    for field in ("broker_server", "iana_timezone", "source_reference"):
        if not isinstance(evidence[field], str) or not evidence[field].strip():
            raise ComparisonError(f"{name} broker timezone evidence {field} must be non-empty")
    if not evidence["source_reference"].strip().lower().startswith("https://"):
        raise ComparisonError(f"{name} broker timezone source_reference must be an HTTPS broker-document URL")
    if evidence["broker_server"].casefold() != broker_server.casefold():
        raise ComparisonError(f"{name} broker timezone evidence broker_server does not match tester metadata server")
    _parse_utc_timestamp(evidence["verified_at_utc"], name=name, field="verified_at_utc")
    try:
        broker_timezone = ZoneInfo(evidence["iana_timezone"])
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ComparisonError(
            f"{name} broker timezone evidence iana_timezone is not available in the IANA timezone database"
        ) from exc
    return broker_timezone, {
        "broker_server": evidence["broker_server"],
        "iana_timezone": evidence["iana_timezone"],
        "source_reference": evidence["source_reference"],
        "verified_at_utc": evidence["verified_at_utc"],
        "sha256": _sha256(evidence_path),
    }


def _local_midnight_utc(day, broker_timezone: ZoneInfo, *, name: str, field: str) -> datetime:
    local = datetime.combine(day, time.min).replace(tzinfo=broker_timezone)
    utc_value = local.astimezone(timezone.utc)
    round_trip = utc_value.astimezone(broker_timezone)
    if round_trip.replace(tzinfo=None) != local.replace(tzinfo=None):
        raise ComparisonError(f"{name} {field} is a nonexistent broker-local midnight in the IANA timezone")
    alternate = local.replace(fold=1)
    if alternate.utcoffset() != local.utcoffset():
        raise ComparisonError(f"{name} {field} is an ambiguous broker-local midnight; split the tester interval")
    return utc_value


def _require_constant_server_offset(
    start_utc: datetime,
    end_utc: datetime,
    broker_timezone: ZoneInfo,
    expected_offset_minutes: int,
    *,
    name: str,
) -> None:
    if end_utc <= start_utc:
        raise ComparisonError(f"{name} tester launch interval is empty or reversed")
    expected_offset = timedelta(minutes=expected_offset_minutes)
    # Check every minute; MT5 INI date bounds include the entire ToDate.
    cursor = start_utc
    while cursor < end_utc:
        observed = cursor.astimezone(broker_timezone).utcoffset()
        if observed != expected_offset:
            raise ComparisonError(
                f"{name} tester interval crosses a broker UTC-offset transition; split the run at the transition"
            )
        cursor += timedelta(minutes=1)
    final_offset = (end_utc - timedelta(microseconds=1)).astimezone(broker_timezone).utcoffset()
    if final_offset != expected_offset:
        raise ComparisonError(
            f"{name} tester interval crosses a broker UTC-offset transition; split the run at the transition"
        )


def _validate_tester_config(
    config_path: Path,
    *,
    context: dict[str, Any],
    preset_path: Path,
    server_utc_offset_minutes: int,
    timezone_evidence_path: Path,
    broker_server: str,
    name: str,
) -> dict[str, Any]:
    values = _parse_tester_ini(config_path, name)
    required = {
        "expert", "expertparameters", "symbol", "period", "model", "executionmode",
        "optimization", "fromdate", "todate", "deposit", "currency", "leverage",
        "forwardmode", "report",
    }
    missing = sorted(required - set(values))
    if missing:
        raise ComparisonError(f"{name} tester INI is missing required [Tester] keys: {missing}")

    expert_file = values["expert"].replace("/", chr(92)).rsplit(chr(92), 1)[-1].casefold()
    if expert_file != "medistouch_v2.8.ex5":
        raise ComparisonError(
            f"{name} tester INI must run the exact consolidated MedisTouch_v2.8.ex5 expert"
        )

    preset_name = values["expertparameters"].replace("/", chr(92)).rsplit(chr(92), 1)[-1].casefold()
    if preset_name != preset_path.name.casefold():
        raise ComparisonError(f"{name} tester INI ExpertParameters does not point to its hashed .set file")

    if values["symbol"].casefold() != context["symbol"].casefold():
        raise ComparisonError(f"{name} tester INI symbol does not match the matched test context")
    if values["period"].casefold() != context["timeframe"].casefold():
        raise ComparisonError(f"{name} tester INI period does not match the matched test context")

    try:
        model = int(values["model"])
        execution_mode = int(values["executionmode"])
        optimization = int(values["optimization"])
        forward_mode = int(values["forwardmode"])
    except ValueError as exc:
        raise ComparisonError(f"{name} tester INI model/execution/optimization modes must be integers") from exc

    # MetaTrader 5 Model=4 is "Every tick based on real ticks".
    if model != 4:
        raise ComparisonError(f"{name} tester INI must use Model=4 (Every tick based on real ticks)")
    # MT5 ExecutionMode=0 is normal/no emulated delay; -1 is random delay and
    # positive values are fixed milliseconds. Require a non-zero delay and
    # require the paired runs to use the same value.
    if execution_mode == 0 or execution_mode < -1 or execution_mode > 600000:
        raise ComparisonError(
            f"{name} tester INI ExecutionMode must be -1 (random) or 1..600000 ms"
        )
    if optimization != 0:
        raise ComparisonError(f"{name} tester INI must disable optimization (Optimization=0)")
    if forward_mode != 0:
        raise ComparisonError(f"{name} tester INI must disable embedded forward mode (ForwardMode=0)")

    def parse_ini_date(key: str) -> str:
        try:
            from datetime import datetime
            return datetime.strptime(values[key], "%Y.%m.%d").date().isoformat()
        except ValueError as exc:
            raise ComparisonError(f"{name} tester INI {key} must use YYYY.MM.DD") from exc

    broker_tz, timezone_evidence = _load_server_timezone_evidence(
        timezone_evidence_path, broker_server=broker_server, name=name
    )
    start_local = context["period_start"].astimezone(broker_tz)
    locked_start_local = context["locked_oos_start"].astimezone(broker_tz)
    # MT5's tester INI accepts calendar dates, not timestamps. Require the
    # development start at broker midnight and stop on the complete broker-local
    # day before the reserved OOS entry date. This prevents the terminal from
    # touching holdout ticks even though the manifest also declares its horizon.
    if start_local.time() != time.min:
        raise ComparisonError(
            f"{name} tester FromDate boundary must align to midnight in the verified broker-server timezone"
        )
    expected_from = start_local.date().isoformat()
    expected_to_date = locked_start_local.date() - timedelta(days=1)
    expected_to = expected_to_date.isoformat()
    if expected_to_date < start_local.date():
        raise ComparisonError(f"{name} tester development range is empty before locked OOS")
    if parse_ini_date("fromdate") != expected_from:
        raise ComparisonError(f"{name} tester INI FromDate does not match the verified broker-local start date")
    if parse_ini_date("todate") != expected_to:
        raise ComparisonError(
            f"{name} tester INI ToDate must be the day before the exclusive locked-OOS start"
        )

    from_date = datetime.strptime(values["fromdate"], "%Y.%m.%d").date()
    to_date = datetime.strptime(values["todate"], "%Y.%m.%d").date()
    run_start_utc = _local_midnight_utc(from_date, broker_tz, name=name, field="FromDate")
    run_end_utc = _local_midnight_utc(to_date + timedelta(days=1), broker_tz, name=name, field="ToDate end")
    _require_constant_server_offset(
        run_start_utc, run_end_utc, broker_tz, server_utc_offset_minutes, name=name
    )

    try:
        deposit = float(values["deposit"])
    except ValueError as exc:
        raise ComparisonError(f"{name} tester INI Deposit must be numeric") from exc
    if not math.isfinite(deposit) or not math.isclose(
        deposit, context["initial_balance"], rel_tol=1e-8, abs_tol=1e-6
    ):
        raise ComparisonError(f"{name} tester INI Deposit does not match the matched test context")

    if values["currency"].upper() != context["account_currency"].upper():
        raise ComparisonError(f"{name} tester INI Currency does not match the matched test context")
    if values["leverage"] != context["leverage"]:
        raise ComparisonError(f"{name} tester INI Leverage does not match the matched test context")
    report_name = values["report"].strip()
    if not report_name:
        raise ComparisonError(f"{name} tester INI Report must be non-empty")

    return {
        "expert": values["expert"],
        "expert_parameters": values["expertparameters"],
        "symbol": values["symbol"],
        "period": values["period"],
        "model": model,
        "model_name": "every_tick_based_on_real_ticks",
        "execution_mode": execution_mode,
        "optimization": optimization,
        "from_date": values["fromdate"],
        "to_date": values["todate"],
        "deposit": deposit,
        "currency": values["currency"],
        "leverage": values["leverage"],
        "forward_mode": forward_mode,
        "report": report_name,
        "iana_timezone": timezone_evidence["iana_timezone"],
        "timezone_evidence_sha256": timezone_evidence["sha256"],
        "timezone_evidence_source_reference": timezone_evidence["source_reference"],
        "server_utc_offset_minutes": server_utc_offset_minutes,
        "offset_constant_throughout_interval": True,
        "run_start_utc": run_start_utc.isoformat(),
        "run_end_utc_exclusive": run_end_utc.isoformat(),
    }


def _validate_tester_metadata(
    metadata_path: Path,
    *,
    run_id: str,
    context: dict[str, Any],
    preset: dict[str, str],
    name: str,
) -> dict[str, Any]:
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ComparisonError(f"{name} cannot read valid tester metadata JSON: {metadata_path}") from exc

    required = {
        "run_id", "symbol", "server", "account_currency", "leverage",
        "initial_balance", "terminal_build", "point", "tick_size", "tick_value",
        "cash_per_point_per_lot", "spread_points_mean", "spread_points_max",
        "spread_samples", "fill_mode", "server_utc_offset_minutes", "timestamp_basis",
        "export_status", "history_expected_deals", "history_recorded_deals",
        "history_missing_deals", "deals_exported", "open_positions_exported",
        "deals_file_written", "open_positions_file_written",
        "deal_profit_total", "deal_commission_total", "deal_swap_total", "deal_fee_total",
        "deal_net_cashflow_total",
    }
    if not isinstance(metadata, dict) or set(metadata) != required:
        raise ComparisonError(
            f"{name} tester metadata keys invalid; required exactly: {sorted(required)}"
        )

    for key in ("run_id", "symbol", "server", "account_currency", "timestamp_basis"):
        if not isinstance(metadata[key], str) or not metadata[key].strip():
            raise ComparisonError(f"{name} tester metadata {key} must be non-empty")
    if metadata["run_id"] != run_id:
        raise ComparisonError(f"{name} manifest run_id does not match exported tester metadata run_id")
    if metadata["symbol"].casefold() != context["symbol"].casefold():
        raise ComparisonError(f"{name} metadata symbol does not match the matched test context")
    if metadata["account_currency"].upper() != context["account_currency"].upper():
        raise ComparisonError(f"{name} metadata account currency does not match the matched test context")
    if str(metadata["terminal_build"]) != context["terminal_build"]:
        raise ComparisonError(f"{name} metadata terminal build does not match the matched test context")
    if metadata["timestamp_basis"] != "broker_wall_clock_with_explicit_offset":
        raise ComparisonError(f"{name} metadata timestamp basis is unsupported")

    if metadata["export_status"] != "complete":
        raise ComparisonError(f"{name} native tester exporter did not mark this run complete")
    for key in (
        "history_expected_deals", "history_recorded_deals", "history_missing_deals",
        "deals_exported", "open_positions_exported",
    ):
        value = metadata[key]
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ComparisonError(f"{name} tester metadata {key} must be a non-negative integer")
    if metadata["history_missing_deals"] != 0:
        raise ComparisonError(f"{name} tester export history reconciliation reports missing deals")
    if metadata["history_expected_deals"] != metadata["history_recorded_deals"]:
        raise ComparisonError(f"{name} tester export history counts do not reconcile")
    if metadata["deals_exported"] != metadata["history_recorded_deals"]:
        raise ComparisonError(f"{name} tester CSV deal count does not reconcile to native history")
    for key in ("deals_file_written", "open_positions_file_written"):
        if metadata[key] is not True:
            raise ComparisonError(f"{name} native tester exporter reports {key}=false")

    numeric = (
        "initial_balance", "point", "tick_size", "tick_value",
        "cash_per_point_per_lot", "spread_points_mean", "spread_points_max",
        "deal_profit_total", "deal_commission_total", "deal_swap_total", "deal_fee_total",
        "deal_net_cashflow_total",
    )
    for key in numeric:
        if isinstance(metadata[key], bool) or not isinstance(metadata[key], (int, float)):
            raise ComparisonError(f"{name} tester metadata {key} must be numeric")
        if not math.isfinite(float(metadata[key])):
            raise ComparisonError(f"{name} tester metadata {key} must be finite")
    if not math.isclose(
        float(metadata["initial_balance"]), context["initial_balance"],
        rel_tol=1e-8, abs_tol=1e-6,
    ):
        raise ComparisonError(f"{name} metadata initial balance does not match the matched test context")

    for key in ("point", "tick_size", "tick_value", "cash_per_point_per_lot"):
        if float(metadata[key]) <= 0.0:
            raise ComparisonError(f"{name} metadata {key} must be positive")
    calculated_cash_per_point = float(metadata["tick_value"]) * float(metadata["point"]) / float(metadata["tick_size"])
    if not math.isclose(
        calculated_cash_per_point, float(metadata["cash_per_point_per_lot"]),
        rel_tol=1e-7, abs_tol=1e-8,
    ):
        raise ComparisonError(f"{name} metadata cash_per_point_per_lot does not reconcile to tick value/size/point")

    mean_spread = float(metadata["spread_points_mean"])
    max_spread = float(metadata["spread_points_max"])
    samples = metadata["spread_samples"]
    fill_mode = metadata["fill_mode"]
    if isinstance(fill_mode, bool) or not isinstance(fill_mode, int) or fill_mode < 0:
        raise ComparisonError(f"{name} tester metadata fill_mode must be a non-negative integer")
    if isinstance(samples, bool) or not isinstance(samples, int) or samples <= 0:
        raise ComparisonError(f"{name} tester metadata spread_samples must be a positive integer")
    if mean_spread < 0.0 or max_spread < mean_spread:
        raise ComparisonError(f"{name} tester metadata spread observations are invalid")

    leverage = metadata["leverage"]
    if isinstance(leverage, bool) or not isinstance(leverage, int) or leverage <= 0:
        raise ComparisonError(f"{name} tester metadata leverage must be a positive integer")
    expected_leverage = f"1:{leverage}"
    if expected_leverage != context["leverage"]:
        raise ComparisonError(f"{name} metadata leverage does not match the matched test context")

    offset = metadata["server_utc_offset_minutes"]
    if isinstance(offset, bool) or not isinstance(offset, int) or not -840 <= offset <= 840:
        raise ComparisonError(f"{name} tester metadata server UTC offset is invalid")
    if offset != _integer_value(preset, "InpTesterServerUtcOffsetMinutes", name):
        raise ComparisonError(f"{name} exported server UTC offset does not match the preset input")

    label = preset.get("InpTesterExportRunId", "").split("||", 1)[0].strip()
    if not label or not metadata["run_id"].startswith(label + "_"):
        raise ComparisonError(f"{name} exported metadata run_id does not match InpTesterExportRunId")

    return {
        "run_id": metadata["run_id"],
        "symbol": metadata["symbol"],
        "server": metadata["server"],
        "account_currency": metadata["account_currency"],
        "leverage": metadata["leverage"],
        "initial_balance": float(metadata["initial_balance"]),
        "terminal_build": str(metadata["terminal_build"]),
        "point": float(metadata["point"]),
        "tick_size": float(metadata["tick_size"]),
        "tick_value": float(metadata["tick_value"]),
        "cash_per_point_per_lot": float(metadata["cash_per_point_per_lot"]),
        "spread_points_mean": mean_spread,
        "spread_points_max": max_spread,
        "spread_samples": samples,
        "fill_mode": fill_mode,
        "server_utc_offset_minutes": offset,
        "timestamp_basis": metadata["timestamp_basis"],
        "export_status": metadata["export_status"],
        "history_expected_deals": metadata["history_expected_deals"],
        "history_recorded_deals": metadata["history_recorded_deals"],
        "history_missing_deals": metadata["history_missing_deals"],
        "deals_exported": metadata["deals_exported"],
        "open_positions_exported": metadata["open_positions_exported"],
        "deals_file_written": metadata["deals_file_written"],
        "open_positions_file_written": metadata["open_positions_file_written"],
        "deal_profit_total": float(metadata["deal_profit_total"]),
        "deal_commission_total": float(metadata["deal_commission_total"]),
        "deal_swap_total": float(metadata["deal_swap_total"]),
        "deal_fee_total": float(metadata["deal_fee_total"]),
        "deal_net_cashflow_total": float(metadata["deal_net_cashflow_total"]),
    }


def _validate_presets(
    baseline_path: Path, candidate_path: Path, context: dict[str, Any]
) -> tuple[dict, dict]:
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

    # WebRequest is disabled by MT5 Strategy Tester agents. The external
    # execution ledger must therefore be bypassed explicitly in this isolated
    # simulation only; local native sizing, order management and deal export
    # remain active. Live/demo defaults are not changed by this preset.
    required_true = (
        "InpEnableExecution",
        "InpEnableDynamicStop",
        "InpTrackOutcomes",
        "InpSmallAccountProfileConfigured",
    )
    for key in required_true:
        if _bool_value(baseline, key, "baseline") is not True:
            raise ComparisonError(f"baseline must set {key}=true")
        if _bool_value(candidate, key, "continuation") is not True:
            raise ComparisonError(f"continuation must set {key}=true")

    required_false = ("InpRequireExecutionLedger", "InpAllowMinLotOverride")
    for key in required_false:
        if _bool_value(baseline, key, "baseline") is not False:
            raise ComparisonError(
                f"baseline must set {key}=false for isolated Strategy Tester execution"
            )
        if _bool_value(candidate, key, "continuation") is not False:
            raise ComparisonError(
                f"continuation must set {key}=false for isolated Strategy Tester execution"
            )

    if _integer_value(baseline, "InpAccountRiskProfile", "baseline") != 1:
        raise ComparisonError("baseline must use ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT")
    if _integer_value(candidate, "InpAccountRiskProfile", "continuation") != 1:
        raise ComparisonError("continuation must use ACCOUNT_RISK_PROFILE_SMALL_ACCOUNT")

    # This preregistered matched experiment fixes the planned target at 20%.
    # Both variants must use exactly that value; accepting 15% would validate a
    # different sizing policy from the frozen test protocol.
    if not math.isclose(context["risk_percent"], 20.0, abs_tol=1e-8):
        raise ComparisonError("matched continuation test_context.risk_percent must be exactly 20%")
    for role, values in (("baseline", baseline), ("continuation", candidate)):
        minimum_risk = _numeric_value(values, "InpSmallMinimumRiskPercentPerTrade", role)
        target_risk = _numeric_value(values, "InpSmallRiskPercentPerTrade", role)
        if not math.isclose(minimum_risk, 15.0, abs_tol=1e-8):
            raise ComparisonError(f"{role} must preserve the 15% small-account minimum-risk floor")
        if not math.isclose(target_risk, 20.0, abs_tol=1e-8):
            raise ComparisonError(f"{role} InpSmallRiskPercentPerTrade must be exactly 20% for this protocol")
        if not math.isclose(target_risk, context["risk_percent"], abs_tol=1e-8):
            raise ComparisonError(f"{role} InpSmallRiskPercentPerTrade does not match test_context.risk_percent")
        ceilings = {
            "InpSmallMaxDailyLossPercent": 25.0,
            "InpSmallMaxDrawdownPercent": 35.0,
            "InpSmallMaxPortfolioRiskPercent": 20.0,
            "InpSmallGoldMaxStopRiskKES": 7.50,
        }
        for key, maximum in ceilings.items():
            if _numeric_value(values, key, role) > maximum + 1e-8:
                raise ComparisonError(f"{role} {key} exceeds the existing small-account safety ceiling")
        if _integer_value(values, "InpSmallMaxOpenTrades", role) > 3:
            raise ComparisonError(f"{role} InpSmallMaxOpenTrades exceeds the existing cap of 3")
        if _integer_value(values, "InpSmallMaxPositionsPerSymbol", role) > 3:
            raise ComparisonError(f"{role} InpSmallMaxPositionsPerSymbol exceeds the existing cap of 3")
        if _integer_value(values, "InpSmallMaxPositionsPerGroup", role) > 3:
            raise ComparisonError(f"{role} InpSmallMaxPositionsPerGroup exceeds the existing cap of 3")
        conversion = _numeric_value(values, "InpAccountCurrencyPerKES", role)
        if context["account_currency"].upper() == "KES":
            if not math.isclose(conversion, 0.0, abs_tol=1e-12):
                raise ComparisonError(f"{role} KES account must not inject a non-KES conversion override")
        elif conversion <= 0.0:
            raise ComparisonError(
                f"{role} non-KES Strategy Tester account requires an explicit InpAccountCurrencyPerKES rate"
            )
        offset = _integer_value(values, "InpTesterServerUtcOffsetMinutes", role)
        if not -840 <= offset <= 840:
            raise ComparisonError(f"{role} InpTesterServerUtcOffsetMinutes must be verified within [-840, 840]")
        export_label = values.get("InpTesterExportRunId", "").split("||", 1)[0].strip()
        if not export_label:
            raise ComparisonError(f"{role} must set a non-empty InpTesterExportRunId")

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
    if context["spread_model"].casefold() != "real_ticks":
        raise ComparisonError("matched MT5 comparison requires test_context.spread_model=real_ticks")
    # Matched development backtests must not touch any registered reserved
    # holdout, even when their outcomes would later be filtered from the report.
    reject_reserved_oos_overlap(period_start, locked_oos_start)

    dataset = _resolve_file(source_path, manifest["dataset_path"], "dataset_path")
    timezone_evidence_path = _resolve_file(
        source_path, manifest["server_timezone_evidence_path"], "server_timezone_evidence_path", allow_empty=False
    )
    if timezone_evidence_path == dataset:
        raise ComparisonError("server timezone evidence must be a separate artifact from tick data")
    timezone_evidence_hash = _sha256(timezone_evidence_path)
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
    artifact_paths: set[Path] = {timezone_evidence_path}

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
        metadata_path = _resolve_file(
            source_path, raw["tester_metadata_path"], f"{name}.tester_metadata_path", allow_empty=False
        )
        tester_config_path = _resolve_file(
            source_path, raw["tester_config_path"], f"{name}.tester_config_path", allow_empty=False
        )
        if tester_config_path.suffix.lower() != ".ini":
            raise ComparisonError(f"{name}.tester_config_path must be an MT5 .ini launch configuration")
        if preset.suffix.lower() != ".set":
            raise ComparisonError(f"{name}.input_preset must be an MT5 .set file")
        for artifact in (preset, report, deals_path, open_path, metadata_path, tester_config_path):
            if artifact in artifact_paths:
                raise ComparisonError(f"artifact path reused across variants: {artifact}")
            artifact_paths.add(artifact)
        preset_paths[role] = preset
        preset_values = _parse_set(preset, f"{role} preset")
        metadata = _validate_tester_metadata(
            metadata_path,
            run_id=run_id,
            context=context,
            preset=preset_values,
            name=name,
        )
        tester_config = _validate_tester_config(
            tester_config_path,
            context=context,
            preset_path=preset,
            server_utc_offset_minutes=metadata["server_utc_offset_minutes"],
            timezone_evidence_path=timezone_evidence_path,
            broker_server=metadata["server"],
            name=name,
        )
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
            if len(deals) != metadata["deals_exported"]:
                raise ComparisonError(f"{name} deals CSV row count does not match native exporter metadata")
            cashflow_components = {
                "profit": sum(row["profit"] for row in deals),
                "commission": sum(row["commission"] for row in deals),
                "swap": sum(row["swap"] for row in deals),
                "fee": sum(row["fee"] for row in deals),
            }
            for component, total_key in (
                ("profit", "deal_profit_total"), ("commission", "deal_commission_total"),
                ("swap", "deal_swap_total"), ("fee", "deal_fee_total"),
            ):
                if not math.isclose(cashflow_components[component], metadata[total_key], rel_tol=0.0, abs_tol=0.01):
                    raise ComparisonError(f"{name} deal CSV {component} total does not reconcile to native metadata")
            csv_net_cashflow = sum(cashflow_components.values())
            if not math.isclose(csv_net_cashflow, metadata["deal_net_cashflow_total"], rel_tol=0.0, abs_tol=0.01):
                raise ComparisonError(f"{name} deal CSV net cashflow does not reconcile to native metadata")
            if len(open_ids) != metadata["open_positions_exported"]:
                raise ComparisonError(f"{name} open-position CSV row count does not match native exporter metadata")
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
            "input_preset_values": preset_values,
            "tester_metadata": metadata,
            "tester_config": tester_config,
            "artifacts": {
                "input_preset": {"path": str(preset), "sha256": preset_hash},
                "report": {"path": str(report), "sha256": _sha256(report)},
                "deals_csv": {"path": str(deals_path), "sha256": _sha256(deals_path)},
                "open_positions_csv": {"path": str(open_path), "sha256": _sha256(open_path)},
                "tester_metadata": {"path": str(metadata_path), "sha256": _sha256(metadata_path)},
                "tester_config": {"path": str(tester_config_path), "sha256": _sha256(tester_config_path)},
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
    _validate_presets(preset_paths["baseline"], preset_paths["continuation"], context)
    baseline = by_role["baseline"]
    candidate = by_role["continuation"]
    baseline_metadata = baseline["tester_metadata"]
    candidate_metadata = candidate["tester_metadata"]
    metadata_match_keys = (
        "symbol", "server", "account_currency", "leverage", "initial_balance",
        "terminal_build", "point", "tick_size", "tick_value",
        "cash_per_point_per_lot", "spread_points_mean", "spread_points_max",
        "spread_samples", "fill_mode", "server_utc_offset_minutes", "timestamp_basis",
    )
    mismatched_metadata = [
        key for key in metadata_match_keys
        if baseline_metadata[key] != candidate_metadata[key]
    ]
    if mismatched_metadata:
        raise ComparisonError(
            "baseline and continuation tester metadata differ for matched broker/tick conditions: "
            + ", ".join(mismatched_metadata)
        )
    baseline_config = baseline["tester_config"]
    candidate_config = candidate["tester_config"]
    config_match_keys = (
        "expert", "symbol", "period", "model", "execution_mode", "optimization",
        "from_date", "to_date", "deposit", "currency", "leverage", "forward_mode",
    )
    mismatched_config = [
        key for key in config_match_keys
        if baseline_config[key] != candidate_config[key]
    ]
    if mismatched_config:
        raise ComparisonError(
            "baseline and continuation MT5 tester launch configurations differ: "
            + ", ".join(mismatched_config)
        )
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
        "server_timezone_evidence": {
            "path": str(timezone_evidence_path),
            "sha256": timezone_evidence_hash,
            "source_reference": baseline_config["timezone_evidence_source_reference"],
            "iana_timezone": baseline_config["iana_timezone"],
            "broker_server": baseline_metadata["server"],
            "offset_constant_under_supplied_iana_rules": True,
        },
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
        "tester_execution_enabled_in_both": True,
        "external_execution_ledger_disabled_for_strategy_tester_only": True,
        "dynamic_stops_enabled_in_both": True,
        "small_account_safety_ceilings_verified": True,
        "broker_metadata_validated_for_cost_stress": True,
        "mt5_every_tick_real_ticks_model_verified": True,
        "nonzero_matched_execution_delay_verified": True,
        "tester_optimization_disabled": True,
        "broker_timezone_mapping_artifact_present": True,
        "server_utc_offset_constant_under_supplied_iana_rules": True,
        "native_tester_export_completeness_verified": True,
        "small_account_target_risk_exactly_20_percent": True,
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
