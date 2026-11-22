import csv, json
from pathlib import Path
import pytest
from tools.reconcile_mt5_cashflows import ReconciliationError, reconcile

FIELDS = ["profit", "commission", "swap", "fee"]

def write_csv(path, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS); w.writeheader(); w.writerows(rows)

def setup_bundle(tmp_path):
    rows = [dict(profit="12.5", commission="-1", swap="-0.2", fee="-0.1"),
            dict(profit="-2", commission="-0.5", swap="0", fee="0")]
    deals = tmp_path / "tester.csv"; write_csv(deals, rows)
    totals = {k: sum(float(r[k]) for r in rows) for k in FIELDS}
    meta = {"export_status":"complete", "history_expected_deals":2, "history_recorded_deals":2,
            "history_missing_deals":0, "deals_exported":2, "deals_file_written":True,
            "deal_profit_total":totals["profit"], "deal_commission_total":totals["commission"],
            "deal_swap_total":totals["swap"], "deal_fee_total":totals["fee"]}
    metadata = tmp_path / "metadata.json"; metadata.write_text(json.dumps(meta))
    return metadata, deals, rows, totals

def summary(path, totals):
    path.write_text(json.dumps({**totals, "net_cashflow":sum(totals.values())}))

def test_tester_metadata_and_report_reconcile(tmp_path):
    metadata, deals, rows, totals = setup_bundle(tmp_path)
    report = tmp_path / "tester-summary.json"; summary(report, totals)
    result = reconcile(metadata, deals, tester_summary=report)
    assert result["status"] == "reconciled"
    assert result["tester_deal_count"] == 2
    assert result["tester_csv_vs_report"]["net_cashflow"]["matches"]

def test_broker_statement_is_reconciled_separately_and_delta_is_not_forced_zero(tmp_path):
    metadata, deals, rows, totals = setup_bundle(tmp_path)
    broker = tmp_path / "broker.csv"
    broker_rows = [dict(profit="10", commission="-1.5", swap="-0.2", fee="-0.1")]
    write_csv(broker, broker_rows)
    broker_totals = {k: sum(float(r[k]) for r in broker_rows) for k in FIELDS}
    statement = tmp_path / "broker-summary.json"; summary(statement, broker_totals)
    result = reconcile(metadata, deals, broker_deals=broker, broker_summary=statement)
    assert result["broker_statement_vs_summary"]["net_cashflow"]["matches"]
    assert result["tester_vs_broker_net_delta"] != 0
    assert result["tester_vs_broker_interpretation"] == "diagnostic_only_execution_conditions_may_differ"

@pytest.mark.parametrize("change, message", [
    ({"export_status":"incomplete"}, "status is not complete"),
    ({"history_missing_deals":1}, "missing deals"),
    ({"history_recorded_deals":1}, "counts differ"),
    ({"deals_file_written":False}, "deals_file_written is false"),
    ({"deal_fee_total":None}, "must be numeric"),
])
def test_incomplete_or_invalid_native_export_fails_closed(tmp_path, change, message):
    metadata, deals, _, _ = setup_bundle(tmp_path)
    payload = json.loads(metadata.read_text()); payload.update(change); metadata.write_text(json.dumps(payload))
    with pytest.raises(ReconciliationError, match=message): reconcile(metadata, deals)

def test_csv_cashflow_mismatch_fails(tmp_path):
    metadata, deals, rows, totals = setup_bundle(tmp_path)
    payload = json.loads(metadata.read_text()); payload["deal_commission_total"] -= 1
    metadata.write_text(json.dumps(payload))
    with pytest.raises(ReconciliationError, match="cashflows do not reconcile"):
        reconcile(metadata, deals)

def test_blank_cost_is_not_treated_as_zero(tmp_path):
    metadata, deals, rows, totals = setup_bundle(tmp_path)
    rows[0]["fee"] = ""
    write_csv(deals, rows)
    with pytest.raises(ReconciliationError, match="blank fee"):
        reconcile(metadata, deals)

def test_broker_summary_without_broker_deals_fails(tmp_path):
    metadata, deals, _, totals = setup_bundle(tmp_path)
    statement = tmp_path / "broker-summary.json"; summary(statement, totals)
    with pytest.raises(ReconciliationError, match="requires broker_deals"):
        reconcile(metadata, deals, broker_summary=statement)
