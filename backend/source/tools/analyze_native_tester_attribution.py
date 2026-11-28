#!/usr/bin/env python3
"""Position-level diagnostics for native Midas MT5 tester deal + outcome exports.

The deals CSV is authoritative for realized broker cashflows. The outcome CSV
adds decision-level excursions and exit context. Partial exits are collapsed
by position_id before calculating performance; decision-level outcomes are
reported separately and never duplicated across multi-leg positions.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

from position_ledger_metrics import (
    LedgerError,
    calculate_metrics,
    read_deals,
    read_open_ids,
    reconstruct_positions,
    reject_reserved_oos_entries,
)


class AttributionError(ValueError):
    pass


def finite_number(value: str, field: str, row: int, *, optional: bool = False):
    raw = (value or "").strip()
    if not raw and optional:
        return None
    if not raw:
        raise AttributionError(f"outcome row {row}: missing {field}")
    try:
        number = float(raw)
    except ValueError as exc:
        raise AttributionError(f"outcome row {row}: invalid {field}") from exc
    if not math.isfinite(number):
        raise AttributionError(f"outcome row {row}: non-finite {field}")
    return number


def read_export_metadata(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AttributionError(f"cannot read export metadata: {path}") from exc
    if not isinstance(data, dict):
        raise AttributionError("export metadata must be a JSON object")
    if data.get("export_status") != "complete":
        raise AttributionError("tester export is not marked complete")
    expected = data.get("history_expected_deals")
    recorded = data.get("history_recorded_deals")
    missing = data.get("history_missing_deals")
    if not all(isinstance(v, int) for v in (expected, recorded, missing)):
        raise AttributionError("metadata lacks integer history reconciliation counts")
    if expected != recorded or missing != 0:
        raise AttributionError("tester export history reconciliation does not balance")
    if data.get("deals_exported") != recorded:
        raise AttributionError("exported deal count does not match recorded history")
    if not str(data.get("run_id", "")).strip() or not str(data.get("symbol", "")).strip():
        raise AttributionError("tester metadata lacks run identity or symbol")
    if data.get("deals_file_written") is not True or data.get("open_positions_file_written") is not True:
        raise AttributionError("tester export artifacts are not both confirmed written")
    if data.get("timestamp_basis") != "broker_wall_clock_with_explicit_offset":
        raise AttributionError("unsupported or missing tester timestamp provenance")
    offset = data.get("server_utc_offset_minutes")
    if not isinstance(offset, int) or not -840 <= offset <= 840:
        raise AttributionError("tester metadata has no verified broker UTC offset")
    return data


def read_position_labels(path: Path) -> dict[str, dict]:
    required = {
        "position_id", "direction", "session", "initial_stop_price",
        "initial_stop_distance_points", "deal_reason", "spread_points_observed", "spread_observed",
    }
    grouped: dict[str, dict] = defaultdict(lambda: {
        "directions": set(), "sessions": set(), "stop_prices": set(),
        "stop_distances": set(), "deal_reasons": set(), "exit_reasons": set(),
        "spread_volume_points_sum": 0.0, "spread_observed_volume": 0.0,
        "spread_unknown_rows": 0, "deal_rows": 0,
    })
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise AttributionError("deals CSV lacks required attribution columns: " + ", ".join(sorted(missing)))
        for row_num, row in enumerate(reader, 2):
            pid = (row.get("position_id") or "").strip()
            if not pid:
                raise AttributionError(f"deals row {row_num}: blank position_id")
            target = grouped[pid]
            direction = (row.get("direction") or "").strip().upper()
            session = (row.get("session") or "").strip().upper()
            reason = (row.get("deal_reason") or "").strip().upper()
            if direction:
                target["directions"].add(direction)
            if session:
                target["sessions"].add(session)
            target["deal_rows"] += 1
            if reason:
                target["deal_reasons"].add(reason)
                entry_kind = (row.get("entry") or "").strip().upper()
                if entry_kind in {"OUT", "OUT_BY", "DEAL_ENTRY_OUT", "DEAL_ENTRY_OUT_BY", "1", "3"}:
                    target["exit_reasons"].add(reason)
            spread_flag = (row.get("spread_observed") or "").strip().lower() in {"1", "true", "yes"}
            if spread_flag:
                spread_points = finite_number(row.get("spread_points_observed", ""), "spread_points_observed", row_num)
                volume = finite_number(row.get("volume", ""), "volume", row_num)
                if spread_points < 0 or volume <= 0:
                    raise AttributionError(f"deals row {row_num}: invalid observed spread or volume")
                target["spread_volume_points_sum"] += spread_points * volume
                target["spread_observed_volume"] += volume
            else:
                target["spread_unknown_rows"] += 1
            stop_price = finite_number(row.get("initial_stop_price", ""), "initial_stop_price", row_num, optional=True)
            stop_distance = finite_number(row.get("initial_stop_distance_points", ""), "initial_stop_distance_points", row_num, optional=True)
            if stop_price is not None and stop_price > 0:
                target["stop_prices"].add(round(stop_price, 10))
            if stop_distance is not None and stop_distance > 0:
                target["stop_distances"].add(round(stop_distance, 6))
    output = {}
    for pid, item in grouped.items():
        direction_conflict = len(item["directions"]) > 1
        session_conflict = len(item["sessions"]) > 1
        stop_conflict = len(item["stop_prices"]) > 1 or len(item["stop_distances"]) > 1
        # Conflicts on an INOUT/netting-reversal group are retained as labels;
        # reconstruct_positions will censor that group. Completed positions
        # are checked fail-closed before they enter any cohort.
        output[pid] = {
            "direction": ("CONFLICT" if direction_conflict else next(iter(item["directions"]), "UNTAGGED")),
            "session": ("CONFLICT" if session_conflict else next(iter(item["sessions"]), "UNTAGGED")),
            "initial_stop_price": (None if stop_conflict else next(iter(item["stop_prices"]), None)),
            "initial_stop_distance_points": (None if stop_conflict else next(iter(item["stop_distances"]), None)),
            "attribution_conflict": direction_conflict or session_conflict or stop_conflict,
            "deal_reasons": sorted(item["deal_reasons"]),
            "exit_deal_reasons": sorted(item["exit_reasons"]),
            "spread_observation_complete": item["spread_unknown_rows"] == 0 and item["deal_rows"] > 0,
            "spread_volume_points_sum": item["spread_volume_points_sum"],
            "spread_observed_volume": item["spread_observed_volume"],
        }
    return output


def read_decision_outcomes(path: Path) -> list[dict]:
    required = {
        "DecisionID", "RunID", "Symbol", "Direction", "Session", "SelectedStrategy",
        "Regime", "Outcome", "MFE_R", "MAE_R", "BarsHeld", "RealizedR",
        "RealizedNetPnL", "OutcomeEpoch",
    }
    rows = []
    seen = set()
    run_ids = set()
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise AttributionError("outcome CSV lacks required columns: " + ", ".join(sorted(missing)))
        for row_num, row in enumerate(reader, 2):
            run_id = (row.get("RunID") or "").strip()
            if not run_id:
                raise AttributionError(f"outcome row {row_num}: blank RunID")
            run_ids.add(run_id)
            decision = (row.get("DecisionID") or "").strip()
            if not decision or decision == "0":
                continue
            if decision in seen:
                raise AttributionError(f"outcome CSV contains duplicate DecisionID {decision}")
            seen.add(decision)
            if (row.get("Filled") or "").strip().lower() not in {"yes", "true", "1"}:
                continue
            rows.append({
                "decision_id": decision,
                "run_id": run_id,
                "symbol": (row.get("Symbol") or "UNKNOWN").strip().upper(),
                "direction": (row.get("Direction") or "UNTAGGED").strip().upper(),
                "session": (row.get("Session") or "UNTAGGED").strip().upper(),
                "strategy": (row.get("SelectedStrategy") or "UNTAGGED").strip().upper(),
                "regime": (row.get("Regime") or "UNTAGGED").strip().upper(),
                "exit_outcome": (row.get("Outcome") or "UNKNOWN").strip().upper(),
                "mfe_r": finite_number(row.get("MFE_R", ""), "MFE_R", row_num),
                "mae_r": finite_number(row.get("MAE_R", ""), "MAE_R", row_num),
                "bars_held": finite_number(row.get("BarsHeld", ""), "BarsHeld", row_num),
                "realized_r": finite_number(row.get("RealizedR", ""), "RealizedR", row_num),
                "realized_net_pnl": finite_number(row.get("RealizedNetPnL", ""), "RealizedNetPnL", row_num),
                "tp1_hit": (row.get("TP1_Hit") or "").strip().lower() in {"yes", "true", "1"},
                "tp2_hit": (row.get("TP2_Hit") or "").strip().lower() in {"yes", "true", "1"},
                "break_even_done": (row.get("BreakEvenDone") or "").strip().lower() in {"yes", "true", "1"},
                "partial_done": (row.get("PartialDone") or "").strip().lower() in {"yes", "true", "1"},
            })
    if len(run_ids) != 1:
        raise AttributionError("outcome CSV must contain exactly one tester RunID")
    return rows


def summarize(rows: list[dict], initial_balance: float) -> dict:
    wins = [p for p in rows if p["net_pnl"] > 1e-7]
    losses = [p for p in rows if p["net_pnl"] < -1e-7]
    flats = [p for p in rows if abs(p["net_pnl"]) <= 1e-7]
    gp = sum(p["net_pnl"] for p in wins)
    gl = -sum(p["net_pnl"] for p in losses)
    r_values = [p["net_pnl"] / p["risk_cash"] for p in rows if p.get("risk_cash") and p["risk_cash"] > 0]
    return {
        "positions": len(rows), "wins": len(wins), "losses": len(losses), "breakeven": len(flats),
        "win_rate_pct_excluding_flats": round(100 * len(wins) / (len(wins) + len(losses)), 2) if wins or losses else None,
        "gross_profit": round(gp, 2), "gross_loss_abs": round(gl, 2),
        "profit_factor": round(gp / gl, 4) if gl else (None if not gp else "no_losses"),
        "net_pnl": round(sum(p["net_pnl"] for p in rows), 2),
        "return_pct_initial_balance": round(100 * sum(p["net_pnl"] for p in rows) / initial_balance, 4) if initial_balance > 0 else None,
        "expectancy_per_position": round(sum(p["net_pnl"] for p in rows) / len(rows), 4) if rows else None,
        "average_realized_R": round(sum(r_values) / len(r_values), 4) if r_values else None,
        "positions_with_risk_cash": len(r_values),
        "mean_initial_stop_distance_points": round(
            sum(p["initial_stop_distance_points"] for p in rows if p.get("initial_stop_distance_points") is not None)
            / sum(1 for p in rows if p.get("initial_stop_distance_points") is not None), 4
        ) if any(p.get("initial_stop_distance_points") is not None for p in rows) else None,
        "positions_with_initial_stop_data": sum(1 for p in rows if p.get("initial_stop_distance_points") is not None),
        "stop_loss_exit_positions": sum(1 for p in rows if "DEAL_REASON_SL" in p.get("exit_deal_reasons", [])),
        "mean_commission_cashflow_per_position": round(sum(p.get("commission_cashflow", 0.0) for p in rows) / len(rows), 4) if rows else None,
        "mean_swap_cashflow_per_position": round(sum(p.get("swap_cashflow", 0.0) for p in rows) / len(rows), 4) if rows else None,
        "mean_fee_cashflow_per_position": round(sum(p.get("fee_cashflow", 0.0) for p in rows) / len(rows), 4) if rows else None,
        "mean_known_slippage_cost_per_position": round(
            sum(p["slippage_cost_cash"] for p in rows if p.get("slippage_complete") and p.get("slippage_cost_cash") is not None)
            / sum(1 for p in rows if p.get("slippage_complete") and p.get("slippage_cost_cash") is not None), 4
        ) if any(p.get("slippage_complete") and p.get("slippage_cost_cash") is not None for p in rows) else None,
        "mean_estimated_embedded_spread_cost_per_position": round(
            sum(p["estimated_embedded_spread_cost_cash"] for p in rows if p.get("estimated_embedded_spread_cost_cash") is not None)
            / sum(1 for p in rows if p.get("estimated_embedded_spread_cost_cash") is not None), 4
        ) if any(p.get("estimated_embedded_spread_cost_cash") is not None for p in rows) else None,
        "sample_status": "insufficient" if len(rows) < 30 else ("exploratory" if len(rows) < 100 else "larger_sample"),
    }


MIN_PROMOTION_WIN_RATE_PCT = 70.0
PERFORMANCE_TARGET_WIN_RATE_PCT = 87.0
MIN_PROMOTION_POSITIONS = 100
MIN_PROMOTION_PROFIT_FACTOR = 1.05


def assess_research_eligibility(metrics: dict) -> dict:
    """Apply the user's hard win-rate floor plus independent profitability/sample gates.

    Passing this screen only permits independent replication; it never promotes
    a strategy into production or changes an EA default.
    """
    win_rate = metrics.get("win_rate_pct_excluding_flats")
    positions = metrics.get("positions", 0)
    profit_factor = metrics.get("profit_factor")
    expectancy = metrics.get("expectancy_per_position")
    checks = {
        "minimum_completed_positions": positions >= MIN_PROMOTION_POSITIONS,
        "minimum_position_win_rate": (
            isinstance(win_rate, (int, float)) and win_rate >= MIN_PROMOTION_WIN_RATE_PCT
        ),
        "minimum_profit_factor": (
            isinstance(profit_factor, (int, float)) and profit_factor >= MIN_PROMOTION_PROFIT_FACTOR
        ),
        "positive_net_expectancy": isinstance(expectancy, (int, float)) and expectancy > 0,
    }
    failed = [name for name, passed in checks.items() if not passed]
    return {
        "eligible_for_independent_replication": not failed,
        "status": "candidate_for_independent_replication" if not failed else "not_eligible",
        "checks": checks,
        "failed_checks": failed,
        "policy": {
            "minimum_completed_positions": MIN_PROMOTION_POSITIONS,
            "minimum_position_win_rate_pct": MIN_PROMOTION_WIN_RATE_PCT,
            "performance_target_win_rate_pct": PERFORMANCE_TARGET_WIN_RATE_PCT,
            "minimum_profit_factor": MIN_PROMOTION_PROFIT_FACTOR,
            "expectancy": "strictly positive after broker profit, commission, swap and fee cashflows",
            "scope": "research shortlist only; not production promotion",
        },
    }


def grouped_metrics(positions: list[dict], initial_balance: float, keys: tuple[str, ...]) -> dict:
    groups: dict[tuple, list] = defaultdict(list)
    for p in positions:
        groups[tuple(p.get(key, "UNKNOWN") for key in keys)].append(p)
    output = {}
    for key, rows in sorted(groups.items(), key=lambda x: tuple(str(v) for v in x[0])):
        label = "|".join(str(v) for v in key)
        output[label] = {**dict(zip(keys, key)), **summarize(rows, initial_balance)}
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deals", required=True, type=Path)
    parser.add_argument("--open-positions", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--outcomes", required=True, type=Path)
    parser.add_argument("--initial-balance", type=float, default=None)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        metadata = read_export_metadata(args.metadata)
        deals = read_deals(args.deals)
        reject_reserved_oos_entries(deals)
        if len(deals) != metadata["history_recorded_deals"]:
            raise AttributionError("deals CSV row count does not match export metadata")
        open_ids = read_open_ids(args.open_positions)
        positions, ignored = reconstruct_positions(deals, open_ids)
        labels = read_position_labels(args.deals)
        cash_per_point = metadata.get("cash_per_point_per_lot")
        cash_per_point = float(cash_per_point) if cash_per_point is not None else 0.0
        outcomes = read_decision_outcomes(args.outcomes)
        if not outcomes:
            raise AttributionError("outcome CSV contains no filled decision rows")
        outcome_run_id = outcomes[0]["run_id"]
        if not str(metadata.get("run_id", "")).startswith(outcome_run_id + "_"):
            raise AttributionError("outcome RunID does not match tester deal export metadata")
        decision_ids = {str(row["decision_id"]) for row in positions if row.get("decision_id")}
        outcome_by_id = {row["decision_id"]: row for row in outcomes}
        missing_outcomes = sorted(decision_ids - set(outcome_by_id))
        initial_balance = args.initial_balance or float(metadata.get("initial_balance", 0.0))
        if not math.isfinite(initial_balance) or initial_balance <= 0:
            raise AttributionError("initial balance must be supplied or present in metadata")

        deals_by_position: dict[str, list[dict]] = defaultdict(list)
        for deal in deals:
            deals_by_position[deal["position_id"]].append(deal)

        enriched = []
        for position in positions:
            pid = position["position_id"]
            position.update(labels.get(pid, {}))
            if position.get("attribution_conflict"):
                raise AttributionError(f"completed position {pid}: conflicting direction, session or initial-stop attribution")
            if position.get("spread_observation_complete") and cash_per_point > 0.0:
                position["estimated_embedded_spread_cost_cash"] = round(
                    0.5 * position["spread_volume_points_sum"] * cash_per_point, 8
                )
            else:
                position["estimated_embedded_spread_cost_cash"] = None
            rows = deals_by_position[pid]
            position["gross_deal_profit"] = round(sum(d["profit"] for d in rows), 8)
            position["commission_cashflow"] = round(sum(d["commission"] for d in rows), 8)
            position["swap_cashflow"] = round(sum(d["swap"] for d in rows), 8)
            position["fee_cashflow"] = round(sum(d["fee"] for d in rows), 8)
            position["slippage_complete"] = all(d.get("slippage_known", False) for d in rows)
            position["slippage_cost_cash"] = (
                round(sum(d["slippage_cost_cash"] for d in rows), 8)
                if position["slippage_complete"] else None
            )
            enriched.append(position)

        eligible_ids = {p["position_id"] for p in enriched}
        total_rows = [d for d in deals if d["position_id"] in eligible_ids]
        losses = [p for p in enriched if p["net_pnl"] < -1e-7]
        stop_loss_positions = [p for p in enriched if "DEAL_REASON_SL" in p.get("exit_deal_reasons", [])]
        exit_reason_counts = {}
        for p in enriched:
            for reason in p.get("exit_deal_reasons", []):
                exit_reason_counts[reason] = exit_reason_counts.get(reason, 0) + 1
        cost_breakdown = {
            "gross_deal_profit_cashflow": round(sum(d["profit"] for d in total_rows), 2),
            "commission_cashflow": round(sum(d["commission"] for d in total_rows), 2),
            "swap_cashflow": round(sum(d["swap"] for d in total_rows), 2),
            "fee_cashflow": round(sum(d["fee"] for d in total_rows), 2),
            "known_adverse_slippage_cost_cash": round(sum(d["slippage_cost_cash"] for d in total_rows if d.get("slippage_known")), 2),
            "deals_with_known_slippage": sum(1 for d in total_rows if d.get("slippage_known")),
            "deals_with_unknown_slippage": sum(1 for d in total_rows if not d.get("slippage_known")),
            "loss_positions": len(losses),
            "loss_position_commission_cashflow": round(sum(p["commission_cashflow"] for p in losses), 2),
            "loss_position_swap_cashflow": round(sum(p["swap_cashflow"] for p in losses), 2),
            "loss_position_fee_cashflow": round(sum(p["fee_cashflow"] for p in losses), 2),
            "loss_positions_with_complete_slippage": sum(1 for p in losses if p["slippage_complete"]),
            "loss_position_known_slippage_cost_cash": round(sum(p["slippage_cost_cash"] or 0.0 for p in losses), 2),
            "positions_exited_by_stop_loss": len(stop_loss_positions),
            "losing_positions_exited_by_stop_loss": sum(1 for p in stop_loss_positions if p["net_pnl"] < -1e-7),
            "exit_deal_reason_position_counts": exit_reason_counts,
            "baseline_spread_points_mean": metadata.get("spread_points_mean"),
            "baseline_spread_points_max": metadata.get("spread_points_max"),
            "positions_with_complete_observed_spread": sum(1 for p in enriched if p.get("spread_observation_complete")),
            "positions_with_unknown_observed_spread": sum(1 for p in enriched if not p.get("spread_observation_complete")),
            "estimated_embedded_spread_cost_cash": (
                round(sum(p["estimated_embedded_spread_cost_cash"] for p in enriched if p.get("estimated_embedded_spread_cost_cash") is not None), 2)
                if any(p.get("estimated_embedded_spread_cost_cash") is not None for p in enriched) else None
            ),
            "loss_position_estimated_embedded_spread_cost_cash": (
                round(sum(p["estimated_embedded_spread_cost_cash"] for p in losses if p.get("estimated_embedded_spread_cost_cash") is not None), 2)
                if any(p.get("estimated_embedded_spread_cost_cash") is not None for p in losses) else None
            ),
            "spread_cash_note": "Estimated from deal-callback observed spread and broker cash-per-point metadata. It is an explanatory estimate of spread already embedded in tester fills, not an additional deduction. Use cost_stress_monte_carlo.py for incremental spread-widening scenarios.",
        }

        joined_outcomes = [row for row in outcomes if row["decision_id"] in decision_ids]
        outcome_groups: dict[str, list[dict]] = defaultdict(list)
        for row in joined_outcomes:
            key = "|".join((row["symbol"], row["strategy"], row["direction"], row["session"]))
            outcome_groups[key].append(row)
        by_strategy_session_outcomes = {}
        for key, group in sorted(outcome_groups.items()):
            by_strategy_session_outcomes[key] = {
                "symbol": group[0]["symbol"], "strategy": group[0]["strategy"],
                "direction": group[0]["direction"], "session": group[0]["session"],
                "decisions": len(group),
                "mean_mfe_R": round(sum(r["mfe_r"] for r in group) / len(group), 4),
                "mean_mae_R": round(sum(r["mae_r"] for r in group) / len(group), 4),
                "mean_bars_held": round(sum(r["bars_held"] for r in group) / len(group), 2),
                "mean_realized_R": round(sum(r["realized_r"] for r in group) / len(group), 4),
                "sl_hit_decisions": sum(1 for r in group if r["exit_outcome"] == "SL_HIT"),
                "tp_hit_decisions": sum(1 for r in group if r["exit_outcome"] == "FINALTP_HIT"),
                "possible_premature_exit_candidates": sum(1 for r in group if r["exit_outcome"] not in {"SL_HIT", "FINALTP_HIT"} and r["mfe_r"] >= 1.0 and r["realized_r"] <= 0.25),
            }
        premature = [
            row for row in joined_outcomes
            if row["exit_outcome"] not in {"SL_HIT", "FINALTP_HIT"}
            and row["mfe_r"] >= 1.0 and row["realized_r"] <= 0.25
        ]
        family_metrics = grouped_metrics(enriched, initial_balance, ("symbol", "strategy"))
        family_priority = []
        for cohort in family_metrics.values():
            eligibility = assess_research_eligibility(cohort)
            family_priority.append({
                "symbol": cohort.get("symbol"), "strategy": cohort.get("strategy"),
                "positions": cohort.get("positions"),
                "win_rate_pct_excluding_flats": cohort.get("win_rate_pct_excluding_flats"),
                "profit_factor": cohort.get("profit_factor"),
                "expectancy_per_position": cohort.get("expectancy_per_position"),
                "priority": eligibility["status"],
                "eligibility": eligibility,
            })
        report = {
            "schema_version": 1,
            "source": {
                "deals_csv": str(args.deals), "open_positions_csv": str(args.open_positions),
                "metadata_json": str(args.metadata), "outcomes_csv": str(args.outcomes),
                "run_id": metadata.get("run_id"), "symbol": metadata.get("symbol"),
                "account_currency": metadata.get("account_currency"),
                "initial_balance": initial_balance, "export_status": metadata.get("export_status"),
                "history_expected_deals": metadata.get("history_expected_deals"),
                "history_recorded_deals": metadata.get("history_recorded_deals"),
                "history_missing_deals": metadata.get("history_missing_deals"),
                "timestamp_basis": metadata.get("timestamp_basis"),
                "server_utc_offset_minutes": metadata.get("server_utc_offset_minutes"),
            },
            "position_metrics": summarize(enriched, initial_balance),
            "by_symbol_direction": grouped_metrics(enriched, initial_balance, ("symbol", "direction")),
            "by_symbol_strategy_family": family_metrics,
            "family_research_priority": family_priority,
            "by_symbol_strategy_direction_session": grouped_metrics(
                enriched, initial_balance, ("symbol", "strategy", "direction", "session")
            ),
            "by_symbol_strategy_regime_direction_session": grouped_metrics(
                enriched, initial_balance, ("symbol", "strategy", "regime", "direction", "session")
            ),
            "decision_excursion_metrics": {
                "matched_decisions": len(joined_outcomes),
                "missing_decision_outcomes": missing_outcomes,
                "mean_mfe_R": round(sum(r["mfe_r"] for r in joined_outcomes) / len(joined_outcomes), 4) if joined_outcomes else None,
                "mean_mae_R": round(sum(r["mae_r"] for r in joined_outcomes) / len(joined_outcomes), 4) if joined_outcomes else None,
                "mean_bars_held": round(sum(r["bars_held"] for r in joined_outcomes) / len(joined_outcomes), 2) if joined_outcomes else None,
                "mean_realized_R": round(sum(r["realized_r"] for r in joined_outcomes) / len(joined_outcomes), 4) if joined_outcomes else None,
                "possible_premature_exit_candidates": len(premature),
                "premature_exit_rule": "decision-level non-SL/non-TP exit with MFE_R >= 1.0 and RealizedR <= 0.25; diagnostic candidate only, not proof of an avoidable exit",
                "by_strategy_session": by_strategy_session_outcomes,
            },
            "loss_cost_attribution": cost_breakdown,
            "ignored_or_censored_position_groups": ignored,
            "attribution_coverage": {
                "positions": len(enriched),
                "direction_tagged": sum(1 for p in enriched if p.get("direction") not in {"", "UNTAGGED", "CONFLICT"}),
                "session_tagged": sum(1 for p in enriched if p.get("session") not in {"", "UNTAGGED", "CONFLICT"}),
                "strategy_tagged": sum(1 for p in enriched if p.get("strategy") not in {"", "UNTAGGED", "CONFLICT"}),
                "slippage_complete_positions": sum(1 for p in enriched if p.get("slippage_complete")),
                "slippage_unknown_positions": sum(1 for p in enriched if not p.get("slippage_complete")),
                "positions_with_initial_stop_distance": sum(1 for p in enriched if p.get("initial_stop_distance_points") is not None),
                "positions_with_exit_reason": sum(1 for p in enriched if p.get("exit_deal_reasons")),
                "positions_with_complete_observed_spread": sum(1 for p in enriched if p.get("spread_observation_complete")),
            },
            "interpretation": {
                "position_unit": "stable MT5 position_id; partial close deals are collapsed",
                "decision_excursions": "one outcome row per decision; reported separately and not duplicated across multi-leg positions",
                "commission_swap_fee": "signed broker deal cashflows included once in net P&L",
                "slippage": "adverse cash cost reported only where every deal in the position has valid requested-price provenance",
                "spread": "baseline spread already embedded in tester fills; only incremental widening belongs in cost stress",
                "drawdown": "closed-position settlement sequence; not tick-level equity drawdown",
                "promotion": "no family below 70% completed-position win rate is eligible even for independent replication; eligible cohorts still require native multi-fold validation, realistic cost stress and explicit human review",
                "promotion_policy": {
                    "minimum_completed_position_win_rate_pct": MIN_PROMOTION_WIN_RATE_PCT,
                    "performance_target_win_rate_pct": PERFORMANCE_TARGET_WIN_RATE_PCT,
                    "minimum_completed_positions": MIN_PROMOTION_POSITIONS,
                    "minimum_profit_factor": MIN_PROMOTION_PROFIT_FACTOR,
                    "positive_expectancy_required": True,
                    "automatic_production_promotion": False,
                },
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "completed_positions": len(enriched), "matched_decisions": len(joined_outcomes)}, indent=2))
        return 0
    except (OSError, LedgerError, AttributionError, ValueError) as exc:
        print(f"native_tester_attribution: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
