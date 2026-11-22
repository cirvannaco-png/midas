#!/usr/bin/env python3
"""Reconcile native MT5 deal cashflows without conflating tester and broker fills.

Inputs are exporter metadata JSON, native deal CSV, and optional normalized
Strategy Tester/broker summary JSON plus broker deal CSV. Summary JSON uses
profit, commission, swap, fee, and net_cashflow numeric fields. Tester and
broker are reconciled independently; tester-vs-broker deltas are diagnostic,
not forced equal because execution conditions can differ.
"""
from __future__ import annotations
import argparse, csv, json, math, sys
from pathlib import Path
from typing import Any

FIELDS = ("profit", "commission", "swap", "fee")
META_FIELDS = {"profit": "deal_profit_total", "commission": "deal_commission_total",
               "swap": "deal_swap_total", "fee": "deal_fee_total"}
ALIASES = {
    "profit": {"profit", "dealprofit", "grossprofit"},
    "commission": {"commission", "dealcommission"},
    "swap": {"swap", "dealswap"},
    "fee": {"fee", "dealfee"},
}
class ReconciliationError(ValueError): pass

def _finite(value: Any, label: str) -> float:
    if isinstance(value, bool): raise ReconciliationError(f"{label} must be numeric")
    try: result = float(value)
    except (TypeError, ValueError) as exc: raise ReconciliationError(f"{label} must be numeric") from exc
    if not math.isfinite(result): raise ReconciliationError(f"{label} must be finite")
    return result

def _read_json(path: Path, label: str) -> dict:
    try: value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReconciliationError(f"cannot read {label} JSON: {path}") from exc
    if not isinstance(value, dict): raise ReconciliationError(f"{label} must be a JSON object")
    return value

def _csv_totals(path: Path, label: str) -> tuple[dict[str, float], int]:
    try:
        stream = path.open(newline="", encoding="utf-8-sig")
    except OSError as exc: raise ReconciliationError(f"cannot read {label} CSV: {path}") from exc
    with stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames: raise ReconciliationError(f"{label} CSV has no header")
        normalized = {"".join(c.lower() for c in h if c.isalnum()): h for h in reader.fieldnames}
        columns = {}
        for field, aliases in ALIASES.items():
            found = next((normalized[a] for a in aliases if a in normalized), None)
            if found is None: raise ReconciliationError(f"{label} CSV missing {field} column")
            columns[field] = found
        totals = {field: 0.0 for field in FIELDS}; count = 0
        for line, row in enumerate(reader, 2):
            for field, column in columns.items():
                raw = row.get(column)
                if raw is None or not raw.strip(): raise ReconciliationError(f"{label} CSV row {line} has blank {field}")
                totals[field] += _finite(raw.replace(" ", ""), f"{label} CSV row {line} {field}")
            count += 1
    return totals, count

def _validate_export(metadata: dict, count: int) -> None:
    if metadata.get("export_status") != "complete": raise ReconciliationError("native exporter status is not complete")
    for key in ("history_expected_deals", "history_recorded_deals", "history_missing_deals", "deals_exported"):
        value = metadata.get(key)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ReconciliationError(f"metadata {key} must be a non-negative integer")
    if metadata["history_missing_deals"] != 0: raise ReconciliationError("native history reports missing deals")
    if metadata["history_expected_deals"] != metadata["history_recorded_deals"]:
        raise ReconciliationError("expected and recorded native deal counts differ")
    if metadata["deals_exported"] != metadata["history_recorded_deals"] or count != metadata["deals_exported"]:
        raise ReconciliationError("CSV deal count does not match complete native history")
    if metadata.get("deals_file_written") is not True: raise ReconciliationError("metadata says deals_file_written is false")
    for key in META_FIELDS.values():
        if key not in metadata: raise ReconciliationError(f"metadata missing cashflow total {key}")

def _compare_totals(actual: dict[str, float], expected: dict[str, float], label: str, tolerance: float) -> dict:
    result = {}; failed = []
    for field in FIELDS:
        delta = actual[field] - expected[field]
        result[field] = {"actual": actual[field], "expected": expected[field], "delta": delta,
                         "matches": math.isclose(actual[field], expected[field], rel_tol=0.0, abs_tol=tolerance)}
        if not result[field]["matches"]: failed.append(field)
    actual_net = sum(actual.values()); expected_net = sum(expected.values())
    result["net_cashflow"] = {"actual": actual_net, "expected": expected_net,
        "delta": actual_net - expected_net,
        "matches": math.isclose(actual_net, expected_net, rel_tol=0.0, abs_tol=tolerance)}
    if not result["net_cashflow"]["matches"]: failed.append("net_cashflow")
    if failed: raise ReconciliationError(f"{label} cashflows do not reconcile: {', '.join(failed)}")
    return result

def _summary_totals(payload: dict, label: str) -> dict[str, float]:
    totals = {field: _finite(payload.get(field), f"{label} {field}") for field in FIELDS}
    declared_net = _finite(payload.get("net_cashflow"), f"{label} net_cashflow")
    if not math.isclose(sum(totals.values()), declared_net, rel_tol=0.0, abs_tol=1e-6):
        raise ReconciliationError(f"{label} summary net_cashflow does not equal component totals")
    return totals

def reconcile(metadata_path: Path, deals_path: Path, *, tester_summary: Path | None = None,
              broker_deals: Path | None = None, broker_summary: Path | None = None,
              tolerance: float = 0.01) -> dict:
    if tolerance < 0 or not math.isfinite(tolerance): raise ReconciliationError("tolerance must be finite and non-negative")
    metadata = _read_json(metadata_path, "tester metadata")
    tester, count = _csv_totals(deals_path, "tester deals")
    _validate_export(metadata, count)
    declared = {field: _finite(metadata[META_FIELDS[field]], f"metadata {META_FIELDS[field]}") for field in FIELDS}
    report = {"status": "reconciled", "tester_deal_count": count,
              "tester_csv_vs_metadata": _compare_totals(tester, declared, "tester CSV vs metadata", tolerance)}
    if tester_summary:
        expected = _summary_totals(_read_json(tester_summary, "tester summary"), "tester summary")
        report["tester_csv_vs_report"] = _compare_totals(tester, expected, "tester CSV vs Strategy Tester report", tolerance)
    if broker_deals:
        broker, broker_count = _csv_totals(broker_deals, "broker statement deals")
        report["broker_deal_count"] = broker_count
        if broker_summary:
            expected = _summary_totals(_read_json(broker_summary, "broker summary"), "broker summary")
            report["broker_statement_vs_summary"] = _compare_totals(broker, expected, "broker statement vs broker summary", tolerance)
        report["tester_vs_broker_delta"] = {field: tester[field] - broker[field] for field in FIELDS}
        report["tester_vs_broker_net_delta"] = sum(tester.values()) - sum(broker.values())
        report["tester_vs_broker_interpretation"] = "diagnostic_only_execution_conditions_may_differ"
    elif broker_summary:
        raise ReconciliationError("broker_summary requires broker_deals for independent reconciliation")
    return report

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--deals", type=Path, required=True)
    parser.add_argument("--tester-summary", type=Path)
    parser.add_argument("--broker-deals", type=Path)
    parser.add_argument("--broker-summary", type=Path)
    parser.add_argument("--tolerance", type=float, default=0.01)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = reconcile(args.metadata, args.deals, tester_summary=args.tester_summary,
                           broker_deals=args.broker_deals, broker_summary=args.broker_summary,
                           tolerance=args.tolerance)
    except ReconciliationError as exc:
        print(f"RECONCILIATION_FAILED: {exc}", file=sys.stderr); return 2
    encoded = json.dumps(result, indent=2, sort_keys=True)
    if args.output: args.output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded); return 0
if __name__ == "__main__": raise SystemExit(main())
