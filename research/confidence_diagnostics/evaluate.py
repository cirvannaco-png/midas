#!/usr/bin/env python3
"""Locked-OOS comparison of raw Midas confidence and the shadow diagnostic score.

Research only: this tool does not fit or alter live EA weights, thresholds,
admission, sizing or exits. env_exec_confidence is a ranking score, not a probability.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
import random
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean

MANIFEST_FIELDS = (
    "schema_version dataset_id source_kind ea_source_sha ea_build terminal_build "
    "symbol timeframe provider period_start period_end market_data_sha256 spread_model "
    "commission_model slippage_model fill_policy initial_balance account_currency "
    "strategy_version model_version weight_version calibration_version "
    "feature_schema_version environment_schema_version train_end holdout_start "
    "evaluation_cutoff"
).split()
ROW_FIELDS = (
    "decision_id signal_time outcome_time outcome_status filled "
    "outcome_history_complete cashflows_known confidence_at_signal "
    "env_exec_confidence realized_r"
).split()


class EvaluationError(ValueError):
    """Input provenance or evidence is unsafe to evaluate."""


def utc(value, field):
    if not isinstance(value, str) or not value.strip():
        raise EvaluationError(f"{field} must be an ISO-8601 timestamp")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise EvaluationError(f"{field} is not a valid ISO-8601 timestamp") from exc
    if result.tzinfo is None or result.utcoffset() is None:
        raise EvaluationError(f"{field} must include an explicit timezone")
    return result.astimezone(timezone.utc)


def flag(value, field):
    value = str(value).strip().lower()
    if value in ("true", "1", "yes"):
        return True
    if value in ("false", "0", "no"):
        return False
    raise EvaluationError(f"{field} must be true or false")


def number(value, field):
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise EvaluationError(f"{field} must be numeric") from exc
    if not math.isfinite(result):
        raise EvaluationError(f"{field} must be finite")
    return result


def validate_manifest(m):
    missing = [k for k in MANIFEST_FIELDS if k not in m or m[k] in (None, "")]
    if missing:
        raise EvaluationError("manifest missing required fields: " + ", ".join(missing))
    if m["schema_version"] != 1:
        raise EvaluationError("unsupported manifest schema_version; expected 1")
    if m["source_kind"] not in ("mt5_strategy_tester", "broker_demo"):
        raise EvaluationError("source_kind must be mt5_strategy_tester or broker_demo")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", str(m["ea_source_sha"])):
        raise EvaluationError("ea_source_sha must be a 40-character Git SHA-1")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", str(m["market_data_sha256"])):
        raise EvaluationError("market_data_sha256 must be a 64-character SHA-256")
    if number(m["initial_balance"], "initial_balance") <= 0:
        raise EvaluationError("initial_balance must be greater than zero")
    t = {k: utc(m[k], k) for k in
         ("period_start", "period_end", "train_end", "holdout_start", "evaluation_cutoff")}
    if not t["period_start"] <= t["train_end"] < t["holdout_start"] <= t["period_end"] <= t["evaluation_cutoff"]:
        raise EvaluationError("chronology must satisfy period_start <= train_end < holdout_start <= period_end <= evaluation_cutoff")
    return t


def ranks(values):
    order = sorted(range(len(values)), key=lambda i: values[i])
    out = [0.0] * len(values)
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and values[order[end]] == values[order[start]]:
            end += 1
        rank = (start + 1 + end) / 2.0
        for j in range(start, end):
            out[order[j]] = rank
        start = end
    return out


def pearson(x, y):
    if len(x) != len(y) or len(x) < 2:
        return None
    mx, my = mean(x), mean(y)
    dx, dy = [v - mx for v in x], [v - my for v in y]
    sx, sy = math.sqrt(sum(v*v for v in dx)), math.sqrt(sum(v*v for v in dy))
    return None if sx == 0 or sy == 0 else sum(a*b for a, b in zip(dx, dy)) / (sx*sy)


def spearman(scores, outcomes):
    return pearson(ranks(scores), ranks(outcomes)) if len(scores) == len(outcomes) else None


def auc(scores, outcomes):
    pairs = [(s, y) for s, y in zip(scores, outcomes) if y != 0]
    if not any(y > 0 for _, y in pairs) or not any(y < 0 for _, y in pairs):
        return None
    ranked = ranks([s for s, _ in pairs])
    p = sum(y > 0 for _, y in pairs)
    n = len(pairs) - p
    positive_rank_sum = sum(r for r, (_, y) in zip(ranked, pairs) if y > 0)
    return (positive_rank_sum - p * (p + 1) / 2.0) / (p * n)


def metrics(rows, key):
    scores = [r[key] for r in rows]
    outcomes = [r["realized_r"] for r in rows]
    ordered_hi = sorted(rows, key=lambda r: r[key], reverse=True)
    ordered_lo = list(reversed(ordered_hi))
    q = max(1, math.ceil(len(rows) * .25))
    top = mean(r["realized_r"] for r in ordered_hi[:q])
    bottom = mean(r["realized_r"] for r in ordered_lo[:q])
    winners = sum(y > 0 for y in outcomes)
    losers = sum(y < 0 for y in outcomes)
    return {
        "n_positions": len(rows), "n_winners": winners, "n_losers": losers,
        "n_scratch": sum(y == 0 for y in outcomes),
        "win_rate_pct": 100.0 * winners / len(rows),
        "expectancy_r": mean(outcomes),
        "spearman_rho": spearman(scores, outcomes),
        "win_loss_auc": auc(scores, outcomes),
        "top_quartile_mean_r": top, "bottom_quartile_mean_r": bottom,
        "top_bottom_spread_r": top - bottom,
    }


def percentile(xs, q):
    xs = sorted(xs)
    p = (len(xs) - 1) * q
    lo, hi = math.floor(p), math.ceil(p)
    return xs[lo] if lo == hi else xs[lo] * (hi-p) + xs[hi] * (p-lo)


def paired_auc_ci(rows, repetitions=1000, seed=17):
    if repetitions < 100:
        raise EvaluationError("bootstrap_repetitions must be at least 100")
    rng, deltas = random.Random(seed), []
    for _ in range(repetitions):
        sample = [rows[rng.randrange(len(rows))] for _ in rows]
        y = [r["realized_r"] for r in sample]
        raw = auc([r["raw"] for r in sample], y)
        diag = auc([r["diagnostic"] for r in sample], y)
        if raw is not None and diag is not None:
            deltas.append(diag - raw)
    if len(deltas) < max(100, math.ceil(repetitions * .5)):
        return {"valid_replicates": len(deltas), "repetitions": repetitions,
                "low": None, "high": None}
    return {"valid_replicates": len(deltas), "repetitions": repetitions,
            "low": percentile(deltas, .025), "high": percentile(deltas, .975)}


def evaluate_dataset(manifest, rows, *, min_holdout_positions=100,
                     min_winners=30, min_losers=30, bootstrap_repetitions=1000, seed=17):
    if min_holdout_positions < 2 or min_winners < 1 or min_losers < 1:
        raise EvaluationError("minimum sample settings are invalid")
    t = validate_manifest(manifest)
    eligible, excluded, seen = [], Counter(), set()
    count = 0
    for line, row in enumerate(rows, 2):
        count += 1
        missing = [k for k in ROW_FIELDS if k not in row or row[k] in (None, "")]
        if missing:
            raise EvaluationError(f"row {line} missing fields: " + ", ".join(missing))
        did = str(row["decision_id"]).strip()
        pid = str(row.get("position_id") or "").strip()
        if not did:
            raise EvaluationError(f"row {line} has an empty decision_id")
        if did in seen:
            raise EvaluationError(f"duplicate decision_id {did}; use one aggregated row per position decision")
        seen.add(did)
        signal, outcome = utc(row["signal_time"], f"row {line} signal_time"), utc(row["outcome_time"], f"row {line} outcome_time")
        if outcome < signal:
            raise EvaluationError(f"row {line} outcome_time precedes signal_time")
        if signal < t["period_start"]:
            raise EvaluationError(f"row {line} signal_time precedes the declared test period")
        if signal < t["holdout_start"]:
            excluded["development_before_holdout"] += 1
            continue
        if signal > t["period_end"]:
            raise EvaluationError(f"row {line} signal_time is outside the declared test period")
        if outcome > t["evaluation_cutoff"]:
            excluded["not_resolved_by_evaluation_cutoff"] += 1
            continue
        status = str(row["outcome_status"]).strip().lower()
        if status not in ("win", "loss", "scratch", "no_fill", "ambiguous", "pending"):
            raise EvaluationError(f"row {line} has unsupported outcome_status {status!r}")
        filled = flag(row["filled"], f"row {line} filled")
        if filled and not pid:
            raise EvaluationError(f"row {line} is filled but has no position_id")
        if status == "no_fill":
            if filled:
                raise EvaluationError(f"row {line} has status=no_fill but filled=true")
            excluded["no_fill"] += 1
            continue
        if status in ("ambiguous", "pending"):
            excluded[status] += 1
            continue
        if not filled:
            raise EvaluationError(f"row {line} has a resolved trade outcome but filled=false")
        if not flag(row["outcome_history_complete"], f"row {line} outcome_history_complete"):
            excluded["incomplete_outcome_history"] += 1
            continue
        if not flag(row["cashflows_known"], f"row {line} cashflows_known"):
            excluded["unknown_cashflows"] += 1
            continue
        r = number(row["realized_r"], f"row {line} realized_r")
        raw = number(row["confidence_at_signal"], f"row {line} confidence_at_signal")
        diag = number(row["env_exec_confidence"], f"row {line} env_exec_confidence")
        if not 0 <= raw <= 100 or not 0 <= diag <= 100:
            raise EvaluationError(f"row {line} confidence scores must be within [0, 100]")
        if (status == "win" and r <= 0) or (status == "loss" and r >= 0) or (status == "scratch" and r != 0):
            raise EvaluationError(f"row {line} outcome_status conflicts with realized_r")
        eligible.append({"decision_id": did, "position_id": pid, "signal_time": signal,
                         "outcome_time": outcome, "raw": raw, "diagnostic": diag, "realized_r": r})
    if not eligible:
        raise EvaluationError("no eligible completed positions in the locked holdout")
    raw_m, diag_m = metrics(eligible, "raw"), metrics(eligible, "diagnostic")
    ci = paired_auc_ci(eligible, bootstrap_repetitions, seed)
    reasons = []
    if len(eligible) < min_holdout_positions:
        reasons.append(f"holdout positions {len(eligible)} below minimum {min_holdout_positions}")
    if raw_m["n_winners"] < min_winners:
        reasons.append(f"winner count {raw_m['n_winners']} below minimum {min_winners}")
    if raw_m["n_losers"] < min_losers:
        reasons.append(f"loser count {raw_m['n_losers']} below minimum {min_losers}")
    if ci["low"] is None:
        reasons.append("paired bootstrap lacked valid winner/loser resamples")
    da = None if raw_m["win_loss_auc"] is None or diag_m["win_loss_auc"] is None else diag_m["win_loss_auc"] - raw_m["win_loss_auc"]
    ds = None if raw_m["spearman_rho"] is None or diag_m["spearman_rho"] is None else diag_m["spearman_rho"] - raw_m["spearman_rho"]
    if reasons:
        verdict = "INSUFFICIENT_EVIDENCE"
    elif ci["low"] > 0 and da is not None and da > 0 and ds is not None and ds > 0:
        verdict = "INCREMENTAL_PREDICTIVE_SIGNAL"
    else:
        verdict = "NO_DEMONSTRATED_INCREMENTAL_VALUE"
    return {
        "schema_version": 1, "evaluation_type": "shadow_score_predictive_value_only",
        "verdict": verdict, "promotion_authorized": False, "live_parameters_changed": False,
        "probability_calibration_claim": False,
        "manifest": {k: manifest[k] for k in MANIFEST_FIELDS},
        "outcomes_csv_sha256": None, "row_count": count,
        "eligible_holdout_positions": len(eligible), "excluded_rows": dict(sorted(excluded.items())),
        "raw_confidence": raw_m, "env_exec_confidence": diag_m,
        "incremental_comparison": {
            "auc_delta_diagnostic_minus_raw": da, "spearman_delta_diagnostic_minus_raw": ds,
            "top_bottom_spread_delta_r": diag_m["top_bottom_spread_r"] - raw_m["top_bottom_spread_r"],
            "paired_auc_delta_bootstrap_95pct_ci": ci,
        },
        "minimum_evidence": {"holdout_positions": min_holdout_positions, "winners": min_winners,
                             "losers": min_losers, "bootstrap_repetitions": bootstrap_repetitions},
        "reasons": reasons,
        "interpretation": "Ranking association on the declared holdout only. The diagnostic is not a probability; a positive result does not prove profitability, causality, execution quality, or authorize live gating or sizing changes.",
    }


def run(manifest_path: Path, outcomes_path: Path, **kwargs):
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvaluationError(f"cannot read manifest JSON: {exc}") from exc
    if not isinstance(manifest, dict):
        raise EvaluationError("manifest root must be a JSON object")
    digest = hashlib.sha256()
    try:
        with outcomes_path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        with outcomes_path.open("r", newline="", encoding="utf-8-sig") as stream:
            reader = csv.DictReader(stream)
            missing = [k for k in ROW_FIELDS if k not in (reader.fieldnames or [])]
            if missing:
                raise EvaluationError("outcomes CSV missing columns: " + ", ".join(missing))
            report = evaluate_dataset(manifest, reader, **kwargs)
    except OSError as exc:
        raise EvaluationError(f"cannot read outcomes CSV: {exc}") from exc
    report["outcomes_csv_sha256"] = digest.hexdigest()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--outcomes", required=True, type=Path)
    parser.add_argument("--min-holdout-positions", type=int, default=100)
    parser.add_argument("--min-winners", type=int, default=30)
    parser.add_argument("--min-losers", type=int, default=30)
    parser.add_argument("--bootstrap-repetitions", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=17)
    args = parser.parse_args(argv)
    try:
        report = run(args.manifest, args.outcomes, min_holdout_positions=args.min_holdout_positions,
                     min_winners=args.min_winners, min_losers=args.min_losers,
                     bootstrap_repetitions=args.bootstrap_repetitions, seed=args.seed)
    except EvaluationError as exc:
        print(json.dumps({"verdict": "REJECTED", "error": str(exc)}, indent=2), file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["verdict"] != "INSUFFICIENT_EVIDENCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
