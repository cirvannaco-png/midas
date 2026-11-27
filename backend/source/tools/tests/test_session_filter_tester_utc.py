from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[4]


def read_modular(path: str) -> str:
    return (REPO_ROOT / "development" / "EA" / path).read_text(encoding="utf-8")


def test_strategy_tester_session_uses_explicit_server_utc_offset():
    session = read_modular("includes/Core/SessionFilter.mqh")
    assert "datetime CSessionFilter::CurrentGMT()" in session
    assert "MQLInfoInteger(MQL_TESTER)" in session
    assert "ServerTimeToGMT(TimeCurrent(),m_testerServerUtcOffsetMinutes)" in session
    assert "return SESSION_UNKNOWN;" in session
    assert "return TimeGMT();" in session
    assert "ServerTimeToGMT(datetime serverTime,int offsetMinutes)" in session
    assert "SessionAtGMT(datetime nowGmt)" in session


def test_both_automatic_and_manual_session_filters_receive_tester_offset():
    scoring = read_modular("includes/Analysis/Scoring.mqh")
    ea = read_modular("MedisTouch_v2.8.source.mq5")
    config = read_modular("includes/Core/Config.mqh")
    assert "SetTesterServerUtcOffsetMinutes(testerServerUtcOffsetMinutes)" in scoring
    assert "InpTesterServerUtcOffsetMinutes);" in ea
    assert "g_operatorSessionFilter.SetTesterServerUtcOffsetMinutes(InpTesterServerUtcOffsetMinutes);" in ea
    assert "SESSION_UNKNOWN" in config



def test_native_policy_suite_covers_utc_conversion_and_dst_boundaries():
    test_source = (REPO_ROOT / "development" / "EA" / "tests" / "SessionFilterUtc.mq5").read_text(encoding="utf-8")
    runner = (REPO_ROOT / "scripts" / "run_mt5_policy_tests.ps1").read_text(encoding="utf-8")
    assert "ServerTimeToGMT(serverTime,180)" in test_source
    assert "2026.03.15 12:30" in test_source
    assert "2026.04.15 07:30" in test_source
    assert '"SessionFilterUtc"' in runner
