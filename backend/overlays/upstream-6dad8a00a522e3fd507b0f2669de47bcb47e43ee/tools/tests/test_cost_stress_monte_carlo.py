"""Regression tests for cost-stress, temporal folds, and Monte Carlo diagnostics."""
import csv
from pathlib import Path
from datetime import datetime, timezone

import pytest

try:
    from tools.cost_stress_monte_carlo import (
        CostStressError,
        build_report,
        incremental_cost_for_position,
        monte_carlo_drawdown,
        performance_metrics,
        require_explicit_cost_columns,
        reject_reserved_oos_overlap,
    )
except ImportError:
    from cost_stress_monte_carlo import (  # type: ignore[no-redef]
        CostStressError,
        build_report,
        incremental_cost_for_position,
        monte_carlo_drawdown,
        performance_metrics,
        require_explicit_cost_columns,
        reject_reserved_oos_overlap,
    )


def test_incremental_spread_and_slippage_are_charged_per_executed_side():
    # One lot entered + one lot exited => two lot-sides. Four points of
    # extra full spread cost 2 points per side; one slippage point per side.
    assert incremental_cost_for_position(2.0, 1.0, 4.0, 1.0) == 6.0


def test_additional_commission_is_charged_per_lot_per_executed_fill():
    # Two lot-sides, each charged an extra 0.75 account-currency commission.
    assert incremental_cost_for_position(2.0, 1.0, 4.0, 1.0, 0.75) == 7.5


def test_additional_commission_rejects_negative_and_non_finite_values():
    with pytest.raises(CostStressError, match="cannot be negative"):
        incremental_cost_for_position(2.0, 1.0, 0.0, 0.0, -0.01)
    with pytest.raises(CostStressError, match="must be finite"):
        incremental_cost_for_position(2.0, 1.0, 0.0, 0.0, float("inf"))


def test_invalid_point_value_fails_closed():
    with pytest.raises(CostStressError, match="point value"):
        incremental_cost_for_position(2.0, 0.0, 2.0, 1.0)


def test_cost_analysis_rejects_missing_commission_swap_or_fee_column(tmp_path: Path):
    path = tmp_path / "deals.csv"
    path.write_text("position_id,time,entry,volume,profit,commission,fee\n", encoding="utf-8")
    with pytest.raises(CostStressError, match="swap"):
        require_explicit_cost_columns(path)


def test_cost_analysis_accepts_explicit_zero_cost_fields(tmp_path: Path):
    path = tmp_path / "deals.csv"
    path.write_text("position_id,time,entry,volume,profit,commission,swap,fee\n", encoding="utf-8")
    require_explicit_cost_columns(path)


def test_performance_metrics_capture_drawdown_and_loss_streak():
    result = performance_metrics([10.0, -12.0, -8.0, 4.0], 100.0)
    assert result["net_pnl"] == -6.0
    assert result["max_consecutive_losses"] == 2
    assert result["max_closed_trade_drawdown_cash"] == 20.0
    assert result["max_closed_trade_drawdown_pct"] == pytest.approx(18.181818, abs=1e-5)


def test_monte_carlo_is_reproducible_and_reports_ranges():
    first = monte_carlo_drawdown([10.0, -12.0, -8.0, 4.0], 100.0, 500, 9876)
    second = monte_carlo_drawdown([10.0, -12.0, -8.0, 4.0], 100.0, 500, 9876)
    assert first == second
    assert first["trade_shuffle_without_replacement"]["max_drawdown_cash_p05_p50_p95"][0] <= \
           first["trade_shuffle_without_replacement"]["max_drawdown_cash_p05_p50_p95"][2]
    assert "ending_balance_p05_p50_p95" in first["bootstrap_with_replacement"]


def test_monte_carlo_requires_at_least_100_simulations():
    with pytest.raises(CostStressError, match="at least 100"):
        monte_carlo_drawdown([1.0, -1.0], 100.0, 99, 1)


def test_standard_cost_stress_cli_refuses_reserved_oos_overlap():
    start = datetime(2026, 9, 10, tzinfo=timezone.utc)
    end = datetime(2026, 9, 20, tzinfo=timezone.utc)
    with pytest.raises(CostStressError, match="overlaps the registered locked-OOS entry window"):
        reject_reserved_oos_overlap(start, end)


def test_development_cost_stress_ending_at_oos_start_is_allowed():
    start = datetime(2025, 1, 1, tzinfo=timezone.utc)
    end = datetime(2026, 9, 1, tzinfo=timezone.utc)
    reject_reserved_oos_overlap(start, end)


def test_cost_analysis_rejects_newer_locked_oos_reservation():
    start = datetime(2026, 11, 14, tzinfo=timezone.utc)
    end = datetime(2026, 12, 1, tzinfo=timezone.utc)
    with pytest.raises(CostStressError, match="midas-gold-m15-frozen-main"):
        reject_reserved_oos_overlap(start, end)


def test_build_report_crosses_additional_commission_into_spread_slippage_grid(tmp_path: Path):
    deals = tmp_path / "deals.csv"
    deals.write_text(
        "\n".join([
            "position_id,time,entry,volume,profit,commission,swap,fee,risk_cash,lane,strategy,regime",
            "P1,2025-01-05T10:00:00Z,IN,0.5,0,-0.5,0,0,20,EA,SMC,TRENDING",
            "P1,2025-01-05T11:00:00Z,OUT,0.5,10,-0.5,0,0,20,EA,SMC,TRENDING",
        ]) + "\n",
        encoding="utf-8",
    )
    open_ids = tmp_path / "open.csv"
    open_ids.write_text("position_id\n", encoding="utf-8")
    report = build_report(
        deals, open_ids,
        point_value_per_lot=1.0,
        initial_balance=10000.0,
        spread_stresses=[0.0, 2.0],
        slippage_stresses=[0.0],
        commission_stresses=[0.0, 1.0],
        start=datetime(2025, 1, 1, tzinfo=timezone.utc),
        end=datetime(2025, 4, 1, tzinfo=timezone.utc),
        train_months=1,
        test_months=1,
        folds=2,
        simulations=100,
        seed=7,
    )
    assert len(report["scenarios"]) == 4
    no_stress = next(
        item for item in report["scenarios"]
        if item["incremental_spread_widening_points"] == 0
        and item["additional_commission_per_lot_per_fill"] == 0
    )
    commission_only = next(
        item for item in report["scenarios"]
        if item["incremental_spread_widening_points"] == 0
        and item["additional_commission_per_lot_per_fill"] == 1
    )
    combined = next(
        item for item in report["scenarios"]
        if item["incremental_spread_widening_points"] == 2
        and item["additional_commission_per_lot_per_fill"] == 1
    )
    assert no_stress["metrics"]["net_pnl"] == 9.0
    assert commission_only["incremental_stress_cost"] == 1.0
    assert combined["incremental_stress_cost"] == 2.0
    assert combined["metrics"]["net_pnl"] == 7.0
