#!/usr/bin/env python3
"""Fail-closed StrategyTune saved-session position and attribution reconciler."""
from __future__ import annotations
import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

EPS = 1e-7
PRICE_TOLERANCE = 1e-5
FAMILIES = {0: "strict", 1: "singleSwing", 2: "continuation", 3: "microMomentum", 4: "other"}
REGIMES = {0: "range", 1: "transition", 2: "trend"}


class LedgerError(ValueError):
    pass


def _num(value, field):
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise LedgerError(f"invalid {field}: {value!r}") from exc
    if not math.isfinite(result):
        raise LedgerError(f"non-finite {field}")
    return result


def _required(obj, key):
    value = obj.get(key)
    if value is None or str(value).strip() == "":
        raise LedgerError(f"missing {key}")
    return value


def _entry_map(custom):
    if custom.get("entryMapVersion") != 1 or custom.get("sessionRowsAuthoritative") is not True:
        raise LedgerError("unsupported entry map or session rows not declared authoritative")
    if custom.get("entryMapOverflow") is not False:
        raise LedgerError("entry map overflowed or overflow flag is missing")
    try:
        expected, count = int(custom["entryMapRecords"]), int(custom["entryMapChunks"])
    except (KeyError, TypeError, ValueError) as exc:
        raise LedgerError("entry map counts are missing") from exc
    if expected < 0 or not 0 <= count <= 48:
        raise LedgerError("entry map counts outside supported bounds")
    records, identities = [], set()
    for i in range(count):
        chunk = custom.get(f"entryMap{i}")
        if not isinstance(chunk, str) or not chunk or len(chunk) > 256:
            raise LedgerError(f"entryMap{i} missing or exceeds 256 characters")
        for raw in chunk.split(";"):
            fields = raw.split("|")
            if len(fields) != 9:
                raise LedgerError(f"malformed entry-map record in chunk {i}")
            ts, side, price, family, regime, quality, risk, spread, slope = fields
            try:
                ts, family, regime = int(ts), int(family), int(regime)
            except ValueError as exc:
                raise LedgerError(f"invalid integer in entryMap{i}") from exc
            side = {"L": "Long", "S": "Short"}.get(side)
            if side is None or ts <= 0 or family not in FAMILIES or regime not in REGIMES:
                raise LedgerError(f"invalid side/time/family/regime in entryMap{i}")
            rec = {
                "timestamp": ts, "side": side, "price": _num(price, "entry price"),
                "family": FAMILIES[family], "regime": REGIMES[regime],
                "quality": _num(quality, "entry quality"), "risk_cash": _num(risk, "risk cash"),
                "spread_atr": _num(spread, "spread/ATR"), "trend_slope_atr": _num(slope, "trend slope/ATR"),
            }
            if rec["price"] <= 0 or rec["risk_cash"] <= 0 or not 0 <= rec["quality"] <= 100:
                raise LedgerError("entry map contains invalid price, risk or quality")
            if rec["spread_atr"] < 0 or rec["trend_slope_atr"] < 0:
                raise LedgerError("entry map contains a negative ATR feature")
            identity = (ts, side, round(rec["price"], 5))
            if identity in identities:
                raise LedgerError(f"duplicate entry-map identity {identity}")
            identities.add(identity)
            records.append(rec)
    if len(records) != expected:
        raise LedgerError(f"entry-map count mismatch: expected {expected}, parsed {len(records)}")
    return records


def _session_rows(session):
    rows = session.get("trades")
    if not isinstance(rows, list) or not rows:
        raise LedgerError("session trade rows are missing")
    if session.get("hasMore") is not False:
        raise LedgerError("session pagination is incomplete")
    for key in ("returned", "total", "totalUnfiltered"):
        if session.get(key) is not None and int(session[key]) != len(rows):
            raise LedgerError(f"session {key} differs from parsed row count")

    groups, close_ids = defaultdict(list), set()
    normalized = []
    for n, row in enumerate(rows, 1):
        status = str(row.get("status", "")).lower()
        if status not in {"open", "closed"}:
            raise LedgerError(f"row {n}: unknown status {status!r}")
        opening_id = str(_required(row, "openingFillId"))
        side = str(_required(row, "side"))
        if side not in {"Long", "Short"}:
            raise LedgerError(f"row {n}: invalid side")
        item = {
            "opening_id": opening_id, "status": status, "side": side,
            "quantity": _num(_required(row, "quantity"), "quantity"),
            "pnl": _num(_required(row, "pnl"), "pnl"),
            "open_time": int(_num(_required(row, "openTimestamp"), "openTimestamp")),
            "open_price": _num(_required(row, "openPrice"), "openPrice"),
            "close_time": None,
        }
        if item["quantity"] <= 0 or item["open_time"] <= 0 or item["open_price"] <= 0:
            raise LedgerError(f"row {n}: invalid quantity or opening identity")
        if status == "closed":
            close_id = str(_required(row, "closingFillId"))
            key = (opening_id, close_id)
            if key in close_ids:
                raise LedgerError(f"duplicate closing row {key}")
            close_ids.add(key)
            item["close_time"] = int(_num(_required(row, "closeTimestamp"), "closeTimestamp"))
            if item["close_time"] < item["open_time"]:
                raise LedgerError(f"row {n}: close precedes open")
        groups[opening_id].append(item)
        normalized.append(item)

    positions = []
    for opening_id, group in groups.items():
        first = group[0]
        for row in group[1:]:
            if row["side"] != first["side"] or row["open_time"] != first["open_time"]:
                raise LedgerError(f"openingFillId {opening_id}: inconsistent side or timestamp")
            if abs(row["open_price"] - first["open_price"]) > PRICE_TOLERANCE:
                raise LedgerError(f"openingFillId {opening_id}: inconsistent open price")
        closed = [r for r in group if r["status"] == "closed"]
        open_rows = [r for r in group if r["status"] == "open"]
        positions.append({
            "opening_id": opening_id, "side": first["side"], "open_time": first["open_time"],
            "open_price": first["open_price"], "closed_rows": closed, "open_rows": open_rows,
            "closed_pnl": sum(r["pnl"] for r in closed),
            "unrealized_pnl": sum(r["pnl"] for r in open_rows),
            "complete": not open_rows,
            "closed_at": max((r["close_time"] for r in closed), default=None),
            "partial_exit_rows": len(closed),
        })
    return normalized, positions


def _join(positions, records):
    lookup = defaultdict(list)
    for record in records:
        lookup[(record["timestamp"], record["side"])].append(record)
    used, matched, unmatched, ambiguous = set(), 0, 0, 0
    for position in positions:
        candidates = lookup[(position["open_time"], position["side"])]
        hits = [r for r in candidates if abs(r["price"] - position["open_price"]) <= PRICE_TOLERANCE]
        if len(hits) == 1:
            position["attribution"] = hits[0]
            used.add(id(hits[0]))
            matched += 1
        elif not hits:
            unmatched += 1
        else:
            ambiguous += 1
    unmatched += len(records) - len(used)
    return matched, unmatched, ambiguous


def _grouped(positions, dimension):
    groups = defaultdict(list)
    for p in positions:
        if p["complete"] and p.get("attribution"):
            groups[p["attribution"][dimension]].append(p)
    out = {}
    for label, group in sorted(groups.items()):
        wins = [p for p in group if p["closed_pnl"] > EPS]
        losses = [p for p in group if p["closed_pnl"] < -EPS]
        gw = sum(p["closed_pnl"] for p in wins)
        gl = abs(sum(p["closed_pnl"] for p in losses))
        mean_r = sum(p["closed_pnl"] / p["attribution"]["risk_cash"] for p in group) / len(group)
        out[label] = {
            "positions": len(group), "wins": len(wins), "losses": len(losses),
            "win_rate_pct": round(100 * len(wins) / (len(wins) + len(losses)), 2) if wins or losses else None,
            "net_pnl": round(sum(p["closed_pnl"] for p in group), 8),
            "expectancy_per_position": round(sum(p["closed_pnl"] for p in group) / len(group), 8),
            "profit_factor": round(gw / gl, 4) if gl else (None if not gw else "no_losses"),
            "mean_R": round(mean_r, 6),
        }
    return out


def build_report(payload):
    session = payload.get("session", payload)
    run = payload.get("run", {})
    stats = run.get("stats", {}) if isinstance(run, dict) else {}
    engine = stats.get("stats", {}) if isinstance(stats, dict) else {}
    custom = stats.get("customStats", {}) if isinstance(stats, dict) else {}
    rows, positions = _session_rows(session)
    records = _entry_map(custom)
    matched, unmatched, ambiguous = _join(positions, records)
    closed_rows = [r for r in rows if r["status"] == "closed"]
    row_pnl = sum(r["pnl"] for r in closed_rows)
    engine_pnl = _num(_required(engine, "totalPnl"), "engine totalPnl")
    delta = row_pnl - engine_pnl
    pnl_ok = abs(delta) <= max(0.01, abs(engine_pnl) * 1e-8)
    engine_trades = engine.get("trades")
    count_ok = engine_trades is None or int(engine_trades) == len(closed_rows)
    map_ok = matched == len(positions) and unmatched == 0 and ambiguous == 0
    valid = pnl_ok and count_ok and map_ok and custom.get("entryMapOverflow") is False
    complete = [p for p in positions if p["complete"]]
    wins = [p for p in complete if p["closed_pnl"] > EPS]
    losses = [p for p in complete if p["closed_pnl"] < -EPS]
    gw, gl = sum(p["closed_pnl"] for p in wins), abs(sum(p["closed_pnl"] for p in losses))
    metrics = {
        "positions_total": len(positions), "completed_positions": len(complete),
        "open_positions": len(positions) - len(complete), "wins": len(wins), "losses": len(losses),
        "win_rate_pct": round(100 * len(wins) / (len(wins) + len(losses)), 2) if wins or losses else None,
        "completed_positions_pnl": round(sum(p["closed_pnl"] for p in complete), 8),
        "realized_pnl_all_positions": round(sum(p["closed_pnl"] for p in positions), 8),
        "unrealized_pnl_open_positions": round(sum(p["unrealized_pnl"] for p in positions), 8),
        "partial_exit_positions": sum(p["partial_exit_rows"] > 1 for p in positions),
        "profit_factor": round(gw / gl, 4) if gl else (None if not gw else "no_losses"),
    }
    record = run.get("record", {}) if isinstance(run.get("record"), dict) else {}
    starting = record.get("startingBalance", payload.get("startingBalance"))
    settlement_dd = None
    if starting is not None:
        balance = peak = _num(starting, "starting balance")
        settlement_dd = 0.0
        ordered = sorted((p for p in complete if p["closed_at"] is not None),
                         key=lambda p: (p["closed_at"], p["opening_id"]))
        for p in ordered:
            balance += p["closed_pnl"]
            peak = max(peak, balance)
            settlement_dd = max(settlement_dd, peak - balance)
    return {
        "ledger_valid": valid, "ticker": session.get("ticker"),
        "currency": session.get("currency") or run.get("accountCurrency"),
        "session_name": session.get("name"), "session_rows": len(rows),
        "closed_rows": len(closed_rows), "positions": metrics,
        "position_settlement_drawdown": settlement_dd,
        "closed_rows_pnl": round(row_pnl, 8), "engine_total_pnl": round(engine_pnl, 8),
        "pnl_reconciliation_delta": round(delta, 12), "pnl_reconciled": pnl_ok,
        "closed_row_count_reconciled": count_ok, "engine_closed_trade_rows": engine_trades,
        "entry_map_records": len(records), "entry_map_matched": matched,
        "entry_map_unmatched": unmatched, "entry_map_ambiguous": ambiguous,
        "entry_map_overflow": custom.get("entryMapOverflow"),
        "internal_shadow_ledger_valid": custom.get("positionAttributionValid"),
        "internal_shadow_missed_close_events": custom.get("missedCloseEvents"),
        "by_family": _grouped(positions, "family"), "by_regime": _grouped(positions, "regime"),
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("payload", type=Path, help="JSON bundle with session and run result objects")
    args = ap.parse_args(argv)
    try:
        report = build_report(json.loads(args.payload.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, LedgerError) as exc:
        print(json.dumps({"ledger_valid": False, "error": str(exc)}, indent=2), file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["ledger_valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
