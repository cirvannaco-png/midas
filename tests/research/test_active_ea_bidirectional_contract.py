from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
ACTIVE_SOURCE = ROOT / "development/EA/MedisTouch_v2.8.source.mq5"
GENERATED_EA = ROOT / "development/EA/MedisTouch_v2.8.mq5"


def _assert_bidirectional_default(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    assert re.search(
        r"GenerateBuySetup\(\)[\s\S]{0,240}GenerateSellSetup\(\)",
        source,
    ), f"{path} must generate both BUY and SELL setups"
    assert "InpGoldLongOnlyMode" not in source, (
        f"{path} must not introduce an upstream Gold-only direction suppression "
        "into the canonical Midas build"
    )


def test_active_modular_ea_keeps_buy_and_sell_generation_enabled():
    _assert_bidirectional_default(ACTIVE_SOURCE)


def test_generated_upload_ea_matches_bidirectional_direction_contract():
    _assert_bidirectional_default(GENERATED_EA)
