import unittest
import pytest
from datetime import datetime, timezone

from tools.position_ledger_metrics import LedgerError, calculate_metrics, reconstruct_positions, reject_reserved_oos_entries


def deal(pid, stamp, entry, volume, profit=0.0, commission=0.0, risk_cash=0.0, lane="A", row=2, symbol="EURUSD", strategy="", regime="", slippage_cost_cash=None, slippage_points=None, slippage_known=False):
    return {
        "position_id": str(pid), "time": datetime.fromisoformat(stamp).replace(tzinfo=timezone.utc),
        "entry": entry, "volume": volume, "profit": profit, "commission": commission,
        "swap": 0.0, "fee": 0.0, "risk_cash": risk_cash, "lane": lane,
        "symbol": symbol, "strategy": strategy, "regime": regime, "source_row": row,
        "decision_id": "",
        "requested_price": 1.1 if slippage_known else None,
        "slippage_points": slippage_points if slippage_known else None,
        "slippage_cost_cash": slippage_cost_cash if slippage_known else None,
        "slippage_known": slippage_known,
    }


class PositionLedgerMetricsTests(unittest.TestCase):
    def test_partial_exits_are_one_position_and_costs_are_net(self):
        rows = [
            deal(100, "2026-01-01T10:00:00", "in", 1.0, commission=-1.0, risk_cash=100, row=2),
            deal(100, "2026-01-01T11:00:00", "out", 0.4, profit=30.0, commission=-0.3, risk_cash=100, row=3),
            deal(100, "2026-01-01T12:00:00", "out", 0.6, profit=20.0, commission=-0.3, risk_cash=100, row=4),
        ]
        positions, ignored = reconstruct_positions(rows)
        report = calculate_metrics(positions, 10000, ignored)
        self.assertEqual(len(positions), 1)
        self.assertEqual(report["partial_exit_rows_collapsed"], 1)
        self.assertAlmostEqual(report["net_pnl"], 48.4)
        self.assertAlmostEqual(report["account_return_pct"], 0.484)
        self.assertAlmostEqual(report["average_realized_R"], 0.484)

    def test_incomplete_trade_is_not_counted(self):
        positions, ignored = reconstruct_positions([deal(200, "2026-01-01T10:00:00", "in", 1.0, row=2)])
        self.assertEqual(positions, [])
        self.assertEqual(ignored["incomplete_volume"], 1)
        self.assertEqual(calculate_metrics(positions, 10000)["status"], "no_complete_positions")

    def test_metrics_and_closed_position_drawdown(self):
        rows = [
            deal(1, "2026-01-01T09:00:00", "in", 1, risk_cash=100, row=2),
            deal(1, "2026-01-01T10:00:00", "out", 1, profit=50, risk_cash=100, row=3),
            deal(2, "2026-01-02T09:00:00", "in", 1, risk_cash=100, row=4),
            deal(2, "2026-01-02T10:00:00", "out", 1, profit=-25, risk_cash=100, row=5),
        ]
        positions, ignored = reconstruct_positions(rows)
        report = calculate_metrics(positions, 1000, ignored)
        self.assertEqual(report["completed_positions"], 2)
        self.assertAlmostEqual(report["net_pnl"], 25)
        self.assertAlmostEqual(report["account_return_pct"], 2.5)
        self.assertEqual(report["profit_factor"], 2.0)
        self.assertEqual(report["average_win"], 50)
        self.assertEqual(report["average_loss"], -25)
        self.assertEqual(report["average_win_R"], 0.5)
        self.assertEqual(report["average_loss_R_abs"], 0.25)
        self.assertEqual(report["payoff_ratio_R"], 2.0)
        self.assertAlmostEqual(report["break_even_win_rate_pct_from_avg_R"], 33.33, places=2)
        self.assertEqual(report["max_closed_position_drawdown_cash"], 25)
        # Signal-accuracy goals must never be mislabeled as account-return targets.
        self.assertNotIn("target_reached", report)
        self.assertNotIn("target_account_return_pct", report)
        self.assertNotIn("target_profit_from_10000", report)

    def test_missing_risk_amount_does_not_fabricate_r_metrics(self):
        rows = [
            deal(9, "2026-01-01T09:00:00", "in", 1, row=2),
            deal(9, "2026-01-01T10:00:00", "out", 1, profit=10, row=3),
        ]
        positions, ignored = reconstruct_positions(rows)
        report = calculate_metrics(positions, 1000, ignored)
        self.assertIsNone(report["average_win_R"])
        self.assertIsNone(report["payoff_ratio_R"])
        self.assertEqual(report["positions_with_risk_cash"], 0)

    def test_currently_open_ids_are_excluded(self):
        rows = [
            deal(3, "2026-01-01T09:00:00", "in", 1, row=2),
            deal(3, "2026-01-01T10:00:00", "out", 1, profit=12, row=3),
        ]
        positions, ignored = reconstruct_positions(rows, {"3"})
        self.assertEqual(positions, [])
        self.assertEqual(ignored["open_position"], 1)

    def test_netting_reversal_is_explicitly_ambiguous(self):
        rows = [
            deal(4, "2026-01-01T09:00:00", "in", 1, row=2),
            deal(4, "2026-01-01T10:00:00", "inout", 1.5, profit=8, row=3),
        ]
        positions, ignored = reconstruct_positions(rows)
        self.assertEqual(positions, [])
        self.assertEqual(ignored["inout_ambiguous"], 1)


if __name__ == "__main__":
    unittest.main()



def test_expectancy_and_maximum_consecutive_losses_are_position_level() -> None:
    pnl_sequence = [10.0, -1.0, -2.0, -3.0, 0.0, -4.0, -5.0, 6.0]
    rows = []
    for index, pnl in enumerate(pnl_sequence, start=1):
        day = f"2026-01-{index:02d}"
        rows.append(
            deal(index, f"{day}T09:00:00", "in", 1.0, risk_cash=100.0, lane="STRICT", row=2 * index)
        )
        rows.append(
            deal(index, f"{day}T10:00:00", "out", 1.0, profit=pnl, risk_cash=100.0, lane="STRICT", row=2 * index + 1)
        )

    positions, ignored = reconstruct_positions(rows)
    report = calculate_metrics(positions, 10000.0, ignored)

    assert report["completed_positions"] == 8
    assert report["net_pnl"] == 1.0
    assert report["net_expectancy_per_completed_position"] == 0.125
    assert report["average_win"] == 8.0
    assert report["average_loss"] == -3.0
    assert report["profit_factor"] == 1.0667
    assert report["max_consecutive_losses"] == 3
    assert report["by_lane"]["STRICT"]["expectancy_per_position"] == 0.125
    assert report["by_lane"]["STRICT"]["max_consecutive_losses"] == 3


def test_losing_streak_is_scoped_to_lane_and_flats_break_a_streak() -> None:
    pnl_lanes = [
        (1, 10.0, "STRICT"),
        (2, -1.0, "STRICT"),
        (3, -2.0, "STRICT"),
        (4, 5.0, "SINGLE"),
        (5, -4.0, "SINGLE"),
        (6, 0.0, "SINGLE"),
        (7, -3.0, "SINGLE"),
        (8, -2.0, "SINGLE"),
    ]
    rows = []
    for index, pnl, lane in pnl_lanes:
        day = f"2026-02-{index:02d}"
        rows.append(deal(index, f"{day}T09:00:00", "in", 1.0, risk_cash=100.0, lane=lane, row=2 * index))
        rows.append(deal(index, f"{day}T10:00:00", "out", 1.0, profit=pnl, risk_cash=100.0, lane=lane, row=2 * index + 1))
    positions, ignored = reconstruct_positions(rows)
    report = calculate_metrics(positions, 10000.0, ignored)
    assert report["by_lane"]["STRICT"]["max_consecutive_losses"] == 2
    assert report["by_lane"]["SINGLE"]["max_consecutive_losses"] == 2


def test_standard_ledger_refuses_reserved_oos_entries():
    rows = [deal(900, "2026-09-15T10:00:00", "in", 1.0, commission=-1.0)]
    import pytest
    with pytest.raises(LedgerError, match="registered locked-OOS window"):
        reject_reserved_oos_entries(rows)


def test_standard_ledger_allows_development_only_deals():
    rows = [deal(901, "2026-08-31T10:00:00", "in", 1.0, commission=-1.0)]
    reject_reserved_oos_entries(rows)


def test_strategy_regime_attribution_uses_completed_positions_not_exit_rows():
    rows = [
        deal(501, "2026-03-01T09:00:00", "in", 1.0, risk_cash=100.0,
             symbol="EURUSD", strategy="MOMENTUM_BREAKOUT", regime="TRENDING", row=2),
        deal(501, "2026-03-01T10:00:00", "out", 0.4, profit=30.0, commission=-0.2,
             risk_cash=100.0, symbol="EURUSD", strategy="MOMENTUM_BREAKOUT", regime="TRENDING", row=3),
        deal(501, "2026-03-01T11:00:00", "out", 0.6, profit=20.0, commission=-0.2,
             risk_cash=100.0, symbol="EURUSD", strategy="MOMENTUM_BREAKOUT", regime="TRENDING", row=4),
        deal(502, "2026-03-02T09:00:00", "in", 1.0, risk_cash=100.0,
             symbol="XAUUSD", strategy="MEAN_REVERSION", regime="RANGING", row=5),
        deal(502, "2026-03-02T10:00:00", "out", 1.0, profit=-20.0,
             risk_cash=100.0, symbol="XAUUSD", strategy="MEAN_REVERSION", regime="RANGING", row=6),
    ]
    positions, ignored = reconstruct_positions(rows)
    report = calculate_metrics(positions, 10000.0, ignored)

    assert report["completed_positions"] == 2
    assert report["partial_exit_rows_collapsed"] == 1
    trend = report["by_symbol_strategy_regime"]["EURUSD|MOMENTUM_BREAKOUT|TRENDING"]
    assert trend["positions"] == 1
    assert trend["wins"] == 1
    assert trend["net_pnl"] == 49.6
    assert trend["average_realized_R"] == 0.496
    reversal = report["by_symbol_strategy_regime"]["XAUUSD|MEAN_REVERSION|RANGING"]
    assert reversal["positions"] == 1
    assert reversal["losses"] == 1
    assert reversal["net_pnl"] == -20.0


def test_position_rejects_conflicting_strategy_or_regime_lineage():
    rows = [
        deal(503, "2026-03-03T09:00:00", "in", 1.0, risk_cash=100.0,
             strategy="SMC", regime="TRENDING", row=2),
        deal(503, "2026-03-03T10:00:00", "out", 1.0, profit=10.0, risk_cash=100.0,
             strategy="MEAN_REVERSION", regime="RANGING", row=3),
    ]
    with pytest.raises(LedgerError, match="conflicting strategy labels"):
        reconstruct_positions(rows)


def test_position_slippage_requires_complete_known_costs_for_every_deal():
    rows = [
        deal(700, "2026-04-01T09:00:00", "in", 1.0, risk_cash=100.0,
             strategy="MOMENTUM_BREAKOUT", regime="TRENDING",
             slippage_cost_cash=0.40, slippage_points=1.0, slippage_known=True, row=2),
        deal(700, "2026-04-01T10:00:00", "out", 0.4, profit=10.0,
             strategy="MOMENTUM_BREAKOUT", regime="TRENDING",
             slippage_cost_cash=0.10, slippage_points=0.5, slippage_known=True, row=3),
        deal(700, "2026-04-01T11:00:00", "out", 0.6, profit=10.0,
             strategy="MOMENTUM_BREAKOUT", regime="TRENDING",
             slippage_cost_cash=0.20, slippage_points=-0.25, slippage_known=True, row=4),
        deal(701, "2026-04-02T09:00:00", "in", 1.0, risk_cash=100.0,
             strategy="MEAN_REVERSION", regime="RANGING",
             slippage_known=False, row=5),
        deal(701, "2026-04-02T10:00:00", "out", 1.0, profit=-5.0,
             strategy="MEAN_REVERSION", regime="RANGING",
             slippage_known=True, slippage_cost_cash=0.2, slippage_points=0.5, row=6),
    ]
    positions, ignored = reconstruct_positions(rows)
    report = calculate_metrics(positions, 10000.0, ignored)

    first = next(position for position in positions if position["position_id"] == "700")
    second = next(position for position in positions if position["position_id"] == "701")
    assert first["slippage_complete"] is True
    assert first["slippage_cost_cash"] == pytest.approx(0.70)
    assert first["volume_weighted_slippage_points"] == pytest.approx(0.525)
    assert second["slippage_complete"] is False
    assert second["slippage_cost_cash"] is None
    assert report["slippage_complete_positions"] == 1
    assert report["slippage_unknown_positions"] == 1
    assert report["slippage_coverage_pct"] == 50.0
    assert report["slippage_cost_cash_known_positions"] == pytest.approx(0.70)


def test_strategy_regime_and_decision_attribution_coverage_is_explicit():
    rows = [
        deal(710, "2026-04-03T09:00:00", "in", 1.0, risk_cash=100.0,
             strategy="MOMENTUM_BREAKOUT", regime="TRENDING", row=2),
        deal(710, "2026-04-03T10:00:00", "out", 1.0, profit=2.0,
             strategy="MOMENTUM_BREAKOUT", regime="TRENDING", row=3),
        deal(711, "2026-04-04T09:00:00", "in", 1.0, risk_cash=100.0,
             strategy="UNTAGGED", regime="CONFLICT", row=4),
        deal(711, "2026-04-04T10:00:00", "out", 1.0, profit=1.0,
             strategy="UNTAGGED", regime="CONFLICT", row=5),
    ]
    rows[0]["decision_id"] = rows[1]["decision_id"] = "123"
    positions, ignored = reconstruct_positions(rows)
    report = calculate_metrics(positions, 10000.0, ignored)
    assert report["positions_with_strategy_attribution"] == 1
    assert report["strategy_attribution_coverage_pct"] == 50.0
    assert report["positions_with_regime_attribution"] == 1
    assert report["regime_attribution_coverage_pct"] == 50.0
    assert report["positions_with_decision_attribution"] == 1
    assert report["decision_attribution_coverage_pct"] == 50.0


def test_decision_id_must_be_consistent_across_position_deals():
    rows = [
        deal(720, "2026-04-05T09:00:00", "in", 1.0, row=2),
        deal(720, "2026-04-05T10:00:00", "out", 1.0, profit=3.0, row=3),
    ]
    rows[0]["decision_id"] = "123"
    rows[1]["decision_id"] = "124"
    with pytest.raises(LedgerError, match="conflicting decision IDs"):
        reconstruct_positions(rows)



def test_inout_reversal_excludes_entire_stable_position_identifier():
    rows = [
        deal(730, "2026-04-05T09:00:00", "in", 1.0, risk_cash=100.0,
             strategy="MOMENTUM_BREAKOUT", regime="TRENDING", row=2),
        deal(730, "2026-04-05T10:00:00", "inout", 2.0, risk_cash=100.0,
             strategy="CONFLICT", regime="CONFLICT", row=3),
        deal(730, "2026-04-05T11:00:00", "out", 1.0, profit=15.0,
             strategy="CONFLICT", regime="CONFLICT", row=4),
    ]
    positions, ignored = reconstruct_positions(rows)
    assert positions == []
    assert ignored["inout_ambiguous"] == 1
