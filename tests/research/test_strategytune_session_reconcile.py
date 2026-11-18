from __future__ import annotations

import copy

import pytest

from scripts.strategytune_session_reconcile import ReconciliationError, reconcile_session


def row(status, opening, closing, pnl, quantity, *, open_ts=1000, close_ts=1100,
        side="Long", open_price=2000.0, close_price=2001.0):
    return {
        "status": status,
        "ticker": "Gold",
        "side": side,
        "quantity": quantity,
        "openingFillId": opening,
        "closingFillId": closing,
        "openTimestamp": open_ts,
        "closeTimestamp": close_ts if status == "Closed" else None,
        "openPrice": open_price,
        "closePrice": close_price if status == "Closed" else None,
        "pnl": pnl,
        "exitReason": "market" if status == "Closed" else None,
    }


def page(trades, *, offset=0, total=None, has_more=False, next_offset=None):
    return {
        "recordId": "record-1",
        "name": "synthetic partial-close session",
        "ticker": "Gold",
        "dataProvider": "icmarkets",
        "currency": "USD",
        "trades": trades,
        "total": len(trades) if total is None else total,
        "offset": offset,
        "returned": len(trades),
        "hasMore": has_more,
        "nextOffset": next_offset,
    }


def test_multiple_partial_closes_same_update_are_grouped_by_opening_fill():
    rows = [
        row("Closed", 101, 201, 2.90, 0.96, close_ts=1200),
        row("Closed", 101, 202, 1.92, 0.24, close_ts=1200),
        row("Closed", 102, 203, -4.00, 0.50, side="Short", open_price=2010, close_price=2013),
    ]
    report = reconcile_session(page(rows), engine_closed_pnl=0.82)

    assert report["reconciled"] is True
    assert report["closed_execution_rows"] == 3
    assert report["unique_opening_fills"] == 2
    assert report["completed_positions"] == 2
    assert report["partial_close_rows_collapsed"] == 1
    assert report["realized_closed_pnl"] == pytest.approx(0.82)
    assert report["completed_position_outcomes"]["wins"] == 1
    assert report["completed_position_outcomes"]["losses"] == 1
    first = next(p for p in report["positions"] if p["openingFillId"] == "101")
    assert first["closedRows"] == 2
    assert first["realizedPnl"] == pytest.approx(4.82)


def test_open_residual_pnl_is_not_mixed_into_realized_reconciliation():
    rows = [
        row("Closed", 101, 201, 1.25, 0.40),
        row("Open", 101, None, -8.50, 0.60),
        row("Closed", 102, 202, -0.50, 0.20, side="Short"),
    ]
    report = reconcile_session(page(rows), engine_closed_pnl=0.75)

    assert report["reconciled"] is True
    assert report["realized_closed_pnl"] == pytest.approx(0.75)
    assert report["completed_positions"] == 1
    assert report["open_positions"] == 1
    assert report["completed_position_outcomes"]["wins"] == 0
    assert report["completed_position_outcomes"]["losses"] == 1
    open_position = next(p for p in report["positions"] if p["openingFillId"] == "101")
    assert open_position["complete"] is False
    assert open_position["realizedPnl"] == pytest.approx(1.25)


def test_paginated_session_is_reconciled_only_after_every_page_is_present():
    first = page([row("Closed", 101, 201, 1.0, 0.2)], total=2,
                 has_more=True, next_offset=1)
    second = page([row("Closed", 102, 202, -0.25, 0.2, side="Short")],
                  offset=1, total=2)
    report = reconcile_session([first, second], engine_closed_pnl=0.75)
    assert report["reconciled"] is True
    assert report["session_row_count"] == 2

    with pytest.raises(ReconciliationError, match="pagination is incomplete"):
        reconcile_session(first, engine_closed_pnl=0.75)


def test_engine_mismatch_fails_reconciliation():
    report = reconcile_session(
        page([row("Closed", 101, 201, 1.0, 0.2)]),
        engine_closed_pnl=1.50,
        tolerance=0.01,
    )
    assert report["reconciled"] is False
    assert report["status"] == "MISMATCH"
    assert report["reconciliation_delta"] == pytest.approx(-0.50)


def test_duplicate_closing_row_is_rejected():
    item = row("Closed", 101, 201, 1.0, 0.2)
    with pytest.raises(ReconciliationError, match="duplicate closing row"):
        reconcile_session(page([item, copy.deepcopy(item)]), engine_closed_pnl=2.0)


def test_inconsistent_opening_fill_identity_is_rejected():
    rows = [
        row("Closed", 101, 201, 1.0, 0.2),
        row("Closed", 101, 202, -0.5, 0.2, open_price=2001.0),
    ]
    with pytest.raises(ReconciliationError, match="conflicting openPrice"):
        reconcile_session(page(rows), engine_closed_pnl=0.5)


def test_unknown_status_or_missing_closing_fill_is_rejected():
    bad_status = row("Closed", 101, 201, 1.0, 0.2)
    bad_status["status"] = "Partial"
    with pytest.raises(ReconciliationError, match="unsupported status"):
        reconcile_session(page([bad_status]), engine_closed_pnl=1.0)

    missing_close = row("Closed", 101, None, 1.0, 0.2)
    with pytest.raises(ReconciliationError, match="missing closingFillId"):
        reconcile_session(page([missing_close]), engine_closed_pnl=1.0)


def test_tool_envelope_and_run_result_summary_are_supported():
    from scripts.strategytune_session_reconcile import engine_pnl_from_summary

    payload = {"text": '{"stats":{"stats":{"totalPnl":-12.5},"account":{"closedPnl":-12.5}}}'}
    assert engine_pnl_from_summary(payload) == pytest.approx(-12.5)
