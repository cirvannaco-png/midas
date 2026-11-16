#!/usr/bin/env python3
"""Reconcile StrategyTune position outcomes from every saved-session close row.

StrategyTune's in-run Context exposes only the latest closed trade. This utility
therefore treats get_session_trades rows, grouped by openingFillId, as the
authoritative source for position-level realized P&L and reconciles their sum
against the engine's closed P&L.

Input JSON is either one complete get_session_trades response, a list of
paginated responses, or {"pages": [...]} containing every page. The engine summary is a get_run_result JSON response.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


class ReconciliationError(ValueError):
    """Raised when session rows are incomplete, inconsistent, or malformed."""


def _decode_tool_envelope(value: Any) -> Any:
    if isinstance(value, dict) and isinstance(value.get("text"), str):
        try:
            return json.loads(value["text"])
        except json.JSONDecodeError as exc:
            raise ReconciliationError("tool response text is not valid JSON") from exc
    return value


def _number(value: Any, field: str, *, allow_zero: bool = True) -> float:
    if isinstance(value, bool):
        raise ReconciliationError(f"{field} must be numeric, not boolean")
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise ReconciliationError(f"{field} is missing or not numeric") from exc
    if not math.isfinite(result):
        raise ReconciliationError(f"{field} must be finite")
    if not allow_zero and result <= 0:
        raise ReconciliationError(f"{field} must be positive")
    return result


def _pages(payload: Any) -> list[dict[str, Any]]:
    payload = _decode_tool_envelope(payload)
    if isinstance(payload, dict) and isinstance(payload.get("pages"), list):
        raw_pages = payload["pages"]
    elif isinstance(payload, list):
        raw_pages = payload
    elif isinstance(payload, dict):
        raw_pages = [payload]
    else:
        raise ReconciliationError("session JSON must contain a page object or page list")

    pages = [_decode_tool_envelope(page) for page in raw_pages]
    if not pages or any(not isinstance(page, dict) for page in pages):
        raise ReconciliationError("session page list is empty or contains a non-object")

    for page in pages:
        if not isinstance(page.get("recordId"), str) or not page["recordId"]:
            raise ReconciliationError("session page is missing recordId")
        if not isinstance(page.get("trades"), list):
            raise ReconciliationError("session page is missing its trades array")
        if "total" not in page or "offset" not in page:
            raise ReconciliationError("session page must include total and offset pagination fields")
        if int(page.get("returned", len(page["trades"]))) != len(page["trades"]):
            raise ReconciliationError("returned row count does not match the trades array")

    record_ids = {page["recordId"] for page in pages}
    totals = {int(page["total"]) for page in pages}
    if len(record_ids) != 1:
        raise ReconciliationError("pages contain more than one recordId")
    if len(totals) != 1:
        raise ReconciliationError("pages disagree on total row count")

    pages.sort(key=lambda page: int(page["offset"]))
    expected_offset = 0
    all_rows: list[dict[str, Any]] = []
    for index, page in enumerate(pages):
        offset = int(page["offset"])
        if offset != expected_offset:
            raise ReconciliationError(
                f"pagination gap or overlap: expected offset {expected_offset}, received {offset}"
            )
        rows = page["trades"]
        all_rows.extend(rows)
        expected_offset += len(rows)
        has_more = bool(page.get("hasMore", False))
        if has_more:
            if int(page.get("nextOffset", -1)) != expected_offset:
                raise ReconciliationError("nextOffset does not follow the current page")
            if index == len(pages) - 1:
                raise ReconciliationError("session pagination is incomplete: more pages remain")
        elif index != len(pages) - 1:
            raise ReconciliationError("a non-final page is marked hasMore=false")

    expected_total = next(iter(totals))
    if expected_offset != expected_total:
        raise ReconciliationError(
            f"incomplete session: collected {expected_offset} of {expected_total} rows"
        )
    return pages


def _consistent(previous: float, current: float, field: str, opening_fill_id: str) -> None:
    if not math.isclose(previous, current, rel_tol=1e-9, abs_tol=1e-7):
        raise ReconciliationError(
            f"openingFillId {opening_fill_id} has conflicting {field} values"
        )


def reconcile_session(payload: Any, engine_closed_pnl: float, tolerance: float = 0.01) -> dict[str, Any]:
    """Aggregate partial close rows by openingFillId and reconcile cash P&L."""
    engine_pnl = _number(engine_closed_pnl, "engine_closed_pnl")
    allowed_delta = _number(tolerance, "tolerance")
    if allowed_delta < 0:
        raise ReconciliationError("tolerance cannot be negative")

    pages = _pages(payload)
    first = pages[0]
    rows = [row for page in pages for row in page["trades"]]
    if any(not isinstance(row, dict) for row in rows):
        raise ReconciliationError("trade rows must be JSON objects")

    grouped: dict[str, dict[str, Any]] = {}
    seen_closes: set[tuple[str, str]] = set()
    closed_row_count = 0
    open_row_count = 0
    closed_row_pnl = 0.0

    for row_index, row in enumerate(rows, start=1):
        status = str(row.get("status", "")).strip().lower()
        if status not in {"closed", "open"}:
            raise ReconciliationError(f"row {row_index}: unsupported status {row.get('status')!r}")

        raw_open_id = row.get("openingFillId")
        if raw_open_id is None or str(raw_open_id).strip() == "":
            raise ReconciliationError(f"row {row_index}: missing openingFillId")
        opening_id = str(raw_open_id)

        side = str(row.get("side", "")).strip()
        if side not in {"Long", "Short"}:
            raise ReconciliationError(f"row {row_index}: side must be Long or Short")
        open_timestamp = int(_number(row.get("openTimestamp"), "openTimestamp", allow_zero=False))
        open_price = _number(row.get("openPrice"), "openPrice", allow_zero=False)
        quantity = _number(row.get("quantity"), "quantity", allow_zero=False)

        group = grouped.get(opening_id)
        if group is None:
            group = {
                "openingFillId": opening_id,
                "side": side,
                "openTimestamp": open_timestamp,
                "openPrice": open_price,
                "closedRows": 0,
                "openRows": 0,
                "closedQuantity": 0.0,
                "openQuantity": 0.0,
                "realizedPnl": 0.0,
                "closeTimestamps": [],
                "exitReasons": set(),
            }
            grouped[opening_id] = group
        else:
            if group["side"] != side:
                raise ReconciliationError(f"openingFillId {opening_id} has conflicting side values")
            if group["openTimestamp"] != open_timestamp:
                raise ReconciliationError(f"openingFillId {opening_id} has conflicting openTimestamp values")
            _consistent(group["openPrice"], open_price, "openPrice", opening_id)

        if status == "closed":
            closing_id = row.get("closingFillId")
            if closing_id is None or str(closing_id).strip() == "":
                raise ReconciliationError(f"row {row_index}: closed row is missing closingFillId")
            close_key = (opening_id, str(closing_id))
            if close_key in seen_closes:
                raise ReconciliationError(
                    f"duplicate closing row for openingFillId {opening_id}, closingFillId {closing_id}"
                )
            seen_closes.add(close_key)
            if row.get("closeTimestamp") is None:
                raise ReconciliationError(f"row {row_index}: closed row is missing closeTimestamp")
            close_timestamp = int(_number(row["closeTimestamp"], "closeTimestamp", allow_zero=False))
            if close_timestamp < open_timestamp:
                raise ReconciliationError(f"row {row_index}: closeTimestamp precedes openTimestamp")
            _number(row.get("closePrice"), "closePrice", allow_zero=False)
            pnl = _number(row.get("pnl"), "closed pnl")
            group["closedRows"] += 1
            group["closedQuantity"] += quantity
            group["realizedPnl"] += pnl
            group["closeTimestamps"].append(close_timestamp)
            if row.get("exitReason"):
                group["exitReasons"].add(str(row["exitReason"]))
            closed_row_count += 1
            closed_row_pnl += pnl
        else:
            if row.get("closingFillId") not in (None, ""):
                raise ReconciliationError(f"row {row_index}: open row must not have closingFillId")
            if group["openRows"] > 0:
                raise ReconciliationError(f"openingFillId {opening_id} has multiple open residual rows")
            group["openRows"] += 1
            group["openQuantity"] += quantity
            open_row_count += 1
            # Open-row pnl is unrealized and MUST NOT enter realized reconciliation.

    position_rows = []
    completed = []
    open_positions = []
    for group in grouped.values():
        position = {
            "openingFillId": group["openingFillId"],
            "side": group["side"],
            "openTimestamp": group["openTimestamp"],
            "openPrice": round(group["openPrice"], 10),
            "closedRows": group["closedRows"],
            "openRows": group["openRows"],
            "closedQuantity": round(group["closedQuantity"], 10),
            "openQuantity": round(group["openQuantity"], 10),
            "realizedPnl": round(group["realizedPnl"], 8),
            "complete": group["openRows"] == 0 and group["closedRows"] > 0,
            "exitReasons": sorted(group["exitReasons"]),
        }
        position_rows.append(position)
        if position["complete"]:
            completed.append(position)
        elif position["openRows"] > 0:
            open_positions.append(position)

    completed.sort(key=lambda position: (position["openTimestamp"], position["openingFillId"]))
    position_rows.sort(key=lambda position: (position["openTimestamp"], position["openingFillId"]))
    wins = [position for position in completed if position["realizedPnl"] > allowed_delta]
    losses = [position for position in completed if position["realizedPnl"] < -allowed_delta]
    flats = [position for position in completed if abs(position["realizedPnl"]) <= allowed_delta]
    gross_profit = sum(position["realizedPnl"] for position in wins)
    gross_loss = abs(sum(position["realizedPnl"] for position in losses))
    delta = closed_row_pnl - engine_pnl
    reconciled = abs(delta) <= allowed_delta

    return {
        "status": "RECONCILED" if reconciled else "MISMATCH",
        "reconciled": reconciled,
        "record_id": first["recordId"],
        "session_name": first.get("name"),
        "ticker": first.get("ticker"),
        "data_provider": first.get("dataProvider"),
        "currency": first.get("currency"),
        "session_row_count": len(rows),
        "closed_execution_rows": closed_row_count,
        "open_residual_rows": open_row_count,
        "unique_opening_fills": len(grouped),
        "completed_positions": len(completed),
        "open_positions": len(open_positions),
        "partial_close_rows_collapsed": sum(max(0, p["closedRows"] - 1) for p in completed),
        "realized_closed_pnl": round(closed_row_pnl, 8),
        "engine_closed_pnl": round(engine_pnl, 8),
        "reconciliation_delta": round(delta, 8),
        "tolerance": allowed_delta,
        "completed_position_outcomes": {
            "wins": len(wins),
            "losses": len(losses),
            "flats": len(flats),
            "win_rate_pct_excluding_flats": round(100 * len(wins) / (len(wins) + len(losses)), 4)
                if wins or losses else None,
            "gross_profit": round(gross_profit, 8),
            "gross_loss_abs": round(gross_loss, 8),
            "profit_factor": round(gross_profit / gross_loss, 6)
                if gross_loss > 0 else (None if gross_profit == 0 else "no_losses"),
            "net_pnl": round(sum(position["realizedPnl"] for position in completed), 8),
            "expectancy_per_position": round(
                sum(position["realizedPnl"] for position in completed) / len(completed), 8
            ) if completed else None,
        },
        "positions": position_rows,
        "authority": "saved get_session_trades rows grouped by openingFillId",
        "open_row_pnl_excluded_as_unrealized": True,
    }


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReconciliationError(f"cannot read JSON file {path}: {exc}") from exc


def engine_pnl_from_summary(payload: Any) -> float:
    payload = _decode_tool_envelope(payload)
    if not isinstance(payload, dict):
        raise ReconciliationError("summary JSON must be an object")
    candidates = [
        payload.get("netPnl"),
        payload.get("engineClosedPnl"),
        (payload.get("stats") or {}).get("stats", {}).get("totalPnl")
            if isinstance(payload.get("stats"), dict) else None,
        (payload.get("stats") or {}).get("account", {}).get("closedPnl")
            if isinstance(payload.get("stats"), dict) else None,
    ]
    for value in candidates:
        if value is not None:
            return _number(value, "summary engine closed P&L")
    raise ReconciliationError(
        "summary must contain stats.stats.totalPnl, stats.account.closedPnl, netPnl, or engineClosedPnl"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-json", required=True, type=Path,
                        help="complete get_session_trades response or JSON array of all pages")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--engine-closed-pnl", type=float,
                        help="engine stats.totalPnl / account.closedPnl in session currency")
    source.add_argument("--summary-json", type=Path,
                        help="get_run_result response JSON")
    parser.add_argument("--tolerance", type=float, default=0.01)
    parser.add_argument("--output", type=Path, help="optional report JSON output path")
    args = parser.parse_args(argv)

    try:
        session_payload = load_json(args.session_json)
        engine_pnl = args.engine_closed_pnl
        if args.summary_json is not None:
            engine_pnl = engine_pnl_from_summary(load_json(args.summary_json))
        report = reconcile_session(session_payload, engine_pnl, args.tolerance)
    except ReconciliationError as exc:
        print(f"strategytune_session_reconcile: {exc}", file=sys.stderr)
        return 2

    output = json.dumps(report, indent=2, sort_keys=True, allow_nan=False)
    if args.output:
        args.output.write_text(output + "\n", encoding="utf-8")
    print(output)
    return 0 if report["reconciled"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
