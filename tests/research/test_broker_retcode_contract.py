from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_placed_retcode_is_only_accepted_for_new_order_requests():
    source = (ROOT / "development/EA/includes/Execution/BrokerAdapter.mqh").read_text()
    start = source.index("bool CBrokerAdapter::LastRequestOk(string action)")
    end = source.index("//+------------------------------------------------------------------+", start)
    body = source[start:end]
    assert "code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL" in body
    assert "code==TRADE_RETCODE_PLACED" in body
    assert '(action=="PlaceLimit" || action=="MarketBuy" || action=="MarketSell")' in body
    assert "if(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_DONE_PARTIAL) return true;" not in body


def test_management_operations_require_completion_retcodes():
    source = (ROOT / "development/EA/includes/Execution/BrokerAdapter.mqh").read_text()
    start = source.index("bool CBrokerAdapter::LastExecutionCompleted(")
    end = source.index("//+------------------------------------------------------------------+", start)
    body = source[start:end]
    assert "TRADE_RETCODE_DONE" in body
    assert "TRADE_RETCODE_PLACED" not in body
