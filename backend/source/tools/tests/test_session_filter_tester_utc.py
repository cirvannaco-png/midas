from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[4]


def read_modular(path: str) -> str:
    return (REPO_ROOT / "development" / "EA" / path).read_text(encoding="utf-8")


def test_strategy_tester_session_uses_explicit_server_utc_offset():
    session = read_modular("includes/Core/SessionFilter.mqh")
    assert "datetime CSessionFilter::CurrentGMT()" in session
    assert "MQLInfoInteger(MQL_TESTER)" in session
    assert "TimeCurrent()-(datetime)(m_testerServerUtcOffsetMinutes*60)" in session
    assert "return SESSION_UNKNOWN;" in session
    assert "return TimeGMT();" in session


def test_both_automatic_and_manual_session_filters_receive_tester_offset():
    scoring = read_modular("includes/Analysis/Scoring.mqh")
    ea = read_modular("MedisTouch_v2.8.source.mq5")
    config = read_modular("includes/Core/Config.mqh")
    assert "SetTesterServerUtcOffsetMinutes(testerServerUtcOffsetMinutes)" in scoring
    assert "InpTesterServerUtcOffsetMinutes);" in ea
    assert "g_operatorSessionFilter.SetTesterServerUtcOffsetMinutes(InpTesterServerUtcOffsetMinutes);" in ea
    assert "SESSION_UNKNOWN" in config
