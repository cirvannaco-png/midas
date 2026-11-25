from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_margin_admission_is_account_scoped_and_instance_idempotent():
    client = (ROOT / "development/EA/includes/Execution/ExecutionLedgerClient.mqh").read_text()
    assert 'm_portfolioKey=server+":"+login+":midas"' in client
    assert "m_instanceKey=magicText" in client
    assert "return m_instanceKey+\":decision:\"" in client
    assert "RequestIdForPosition" in client and "RequestIdForPendingOrder" in client


def test_ea_requires_broker_calculated_margin_and_fresh_account_snapshot():
    ea = (ROOT / "development/EA/MedisTouch_v2.8.source.mq5").read_text()
    assert "OrderCalcMargin(decision.setup.type,_Symbol,lots,entry,requiredMargin)" in ea
    assert "AccountInfoDouble(ACCOUNT_MARGIN_FREE)" in ea
    assert "AccountInfoString(ACCOUNT_CURRENCY)" in ea
    client = (ROOT / "development/EA/includes/Execution/ExecutionLedgerClient.mqh").read_text()
    assert "midas-account-margin-v1" in client
    assert "expectedResponseToken" in client
    assert "(long)TimeGMT()" in ea
    assert "requiredMargin<=0.0" in ea
    assert "SyncPendingOrder(orderTicket,symbol,direction,riskR,0.0," in ea
    assert "OrderCalcMargin(marginOrderType,symbol,volume,entry,requiredMargin)" in ea


def test_bridge_enforces_snapshot_freshness_atomic_margin_and_currency():
    bridge = (ROOT / "backend/source/telegram-bridge/app/execution_control.py").read_text()
    assert "pg_advisory_xact_lock" in bridge
    assert "MAX_MARGIN_SNAPSHOT_AGE_SECONDS = 10.0" in bridge
    assert "MAX_MARGIN_SNAPSHOT_FUTURE_SECONDS = 2.0" in bridge
    assert "MIN_FREE_MARGIN_BUFFER_RATIO = _margin_buffer_ratio()" in bridge
    assert "required_margin + unreflected > float(free_margin) * (1.0 - MIN_FREE_MARGIN_BUFFER_RATIO)" in bridge
    assert 'state in {"RESERVED", "CHECKED", "SENT", "RECOVERING"}' in bridge
    assert 'state in {"ACKED", "FILLED"}' in bridge
    assert '"last_transition_at": now.isoformat()' in bridge


def test_bridge_requires_margin_evidence_for_pending_order_reconciliation():
    api = (ROOT / "backend/source/telegram-bridge/app/api/execution_ledger.py").read_text()
    client = (ROOT / "development/EA/includes/Execution/ExecutionLedgerClient.mqh").read_text()
    assert "required_margin: float = Field(gt=0, strict=True)" in api
    assert "account_currency: str = Field" in api
    assert 'margin_admission_version: Literal["midas-account-margin-v1"]' in api
    assert '"margin_admission_version": "midas-account-margin-v1"' in api
    assert '"required_margin\\":%.8f' in client
    assert '"account_currency\\":\\"%s' in client
