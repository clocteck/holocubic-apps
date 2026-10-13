#!/usr/bin/env python3
"""Generate reproducible UI charsets, including GB2312 level 1/2 place-name Hanzi."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUNCTUATION = "，。！？；：、（）《》〈〉【】〔〕［］｛｝“”‘’—…·￥「」『』～・〜％℃℉‰°±×÷≤≥≈←↑→↓"
LATIN = "ÄÖÜäöüßẞéèêëáàâãåæçíìîïñóòôõøúùûýÿŒœ–’‹›"
# Common administrative/place-name characters outside GB2312. Keep this local,
# rather than relying on another firmware checkout's frequency-ranked word list.
PLACE_NAMES = "湛江儋州亳州漯河濮阳衢州郴州蚌埠菏泽滁州泸州漳州鄂尔多斯鄯善盱眙黟县歙县婺源荥阳邛崃郫都阆中鄠邑埇桥潞州渌口沾益濂溪赣榆浉河郓城鄄城茌平滦州栾川珲春桦甸讷河绥芬河瑷珲珲春茫崖噶尔堆龙德庆米东堃塬垌墘滘涌寮畲碶岙岜垚甪禤"


def dedupe(text: str) -> str:
    return "".join(dict.fromkeys(text))


def project_chars() -> str:
    chars: list[str] = []
    for relative in (
        "launcher/package/main.lua",
        "BTC/package/i18n.lua",
        "BTC/package/ui.lua",
        "weather/package/main.lua",
        "ebook/package/reader.lua",
        "settings/package/i18n.lua",
        "NixieClock/package/main.lua",
        "../youxia173-holocubic-apps/gold-miner/package/main.lua",
    ):
        source = ROOT / relative
        if not source.exists():
            continue
        text = source.read_text(encoding="utf-8")
        chars.extend(re.findall(r"[\u3000-\u30ff\u3400-\u9fff\uf900-\ufaff]", text))
    return dedupe("".join(chars))


def gb2312_hanzi() -> str:
    """All 6,763 level-1/2 Hanzi, not just the 4,000 most frequent characters."""
    chars = []
    for lead in range(0xB0, 0xF8):
        for trail in range(0xA1, 0xFF):
            try:
                char = bytes((lead, trail)).decode("gb2312")
            except UnicodeDecodeError:
                continue
            if len(char) == 1 and "\u3400" <= char <= "\u9fff":
                chars.append(char)
    assert len(chars) == 6763
    return "".join(chars)


def big5_level1() -> str:
    chars: list[str] = []
    for lead in range(0xA4, 0xC7):
        for trail in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            if lead == 0xC6 and trail > 0x7E:
                break
            try:
                char = bytes((lead, trail)).decode("big5")
            except UnicodeDecodeError:
                continue
            if len(char) == 1:
                chars.append(char)
    return dedupe("".join(chars))


def jis_level1() -> str:
    chars: list[str] = []
    for ku in range(16, 48):
        for ten in range(1, 95):
            try:
                char = bytes((ku + 0xA0, ten + 0xA0)).decode("euc_jp")
            except UnicodeDecodeError:
                continue
            if len(char) == 1 and "\u3400" <= char <= "\u9fff":
                chars.append(char)
    kana = "".join(chr(code) for code in range(0x3041, 0x30FB)) + "ー々〆ヶ"
    return dedupe(kana + "".join(chars))


def main() -> None:
    sc_source = gb2312_hanzi()
    extras = project_chars()
    charsets = {
        "zh_cn": dedupe(LATIN + PUNCTUATION + extras + sc_source + PLACE_NAMES),
        "zh_tw": dedupe(LATIN + PUNCTUATION + extras + big5_level1()),
        "ja": dedupe(LATIN + PUNCTUATION + extras + jis_level1()),
        "de": dedupe(LATIN + "°℃℉€←↑→↓…·–—"),
    }
    for name, chars in charsets.items():
        output = ROOT / "tools" / f"charset_{name}.txt"
        output.write_text(chars, encoding="utf-8")
        print(f"[charset] {name}: {len(chars)} -> {output}")


if __name__ == "__main__":
    main()
