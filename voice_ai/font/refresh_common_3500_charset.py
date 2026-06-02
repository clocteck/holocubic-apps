#!/usr/bin/env python3
"""Build the charset file for the Voice AI Microsoft YaHei LVGL font."""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

WIKTIONARY_TITLE = "Appendix:通用规范汉字表"
WIKTIONARY_API = (
    "https://zh.wiktionary.org/w/api.php?action=parse"
    f"&page={urllib.parse.quote(WIKTIONARY_TITLE)}"
    "&prop=wikitext&formatversion=2&format=json"
)

ASCII_CHARS = "".join(chr(code) for code in range(0x20, 0x7F))
CHINESE_PUNCTUATION = "，。！？；：、（）《》〈〉【】〔〕［］｛｝“”‘’—…·￥「」『』～"
COMMON_SYMBOLS = "℃℉‰°±×÷≤≥≈←↑→↓★☆○●□■△▲▽▼"


def fetch_wikitext() -> str:
    request = urllib.request.Request(
        WIKTIONARY_API,
        headers={"User-Agent": "voice-ai-font-builder/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return payload["parse"]["wikitext"]


def extract_level1_hanzi(wikitext: str) -> list[str]:
    start_marker = "==一级字表（3500字）=="
    end_marker = "==二级字表（3000字）=="
    start = wikitext.index(start_marker)
    end = wikitext.index(end_marker, start)
    section = wikitext[start:end]

    chars: list[str] = []
    for line in section.splitlines():
        if not re.match(r"^\|\d{4}\|\|", line):
            continue
        match = re.search(r"\[\[([^\]|]+)", line)
        if not match:
            continue
        char = match.group(1)
        if len(char) != 1:
            raise ValueError(f"non-single-char entry: {char!r}")
        chars.append(char)

    if len(chars) != 3500:
        raise ValueError(f"expected 3500 level-1 chars, got {len(chars)}")
    if len(chars) != len(set(chars)):
        raise ValueError("duplicated level-1 chars")
    return chars


def dedupe(text: str) -> str:
    seen: set[str] = set()
    out: list[str] = []
    for char in text:
        if char in seen:
            continue
        seen.add(char)
        out.append(char)
    return "".join(out)


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    hanzi_path = script_dir / "common_hanzi_3500.txt"
    charset_path = script_dir / "msyh_cn_3500_charset.txt"

    hanzi = "".join(extract_level1_hanzi(fetch_wikitext()))
    charset = dedupe(ASCII_CHARS + CHINESE_PUNCTUATION + COMMON_SYMBOLS + hanzi)

    hanzi_path.write_text(hanzi, encoding="utf-8")
    charset_path.write_text(charset, encoding="utf-8")

    print(f"[charset] hanzi={len(hanzi)}")
    print(f"[charset] total={len(charset)}")
    print(f"[charset] wrote {hanzi_path}")
    print(f"[charset] wrote {charset_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[charset] failed: {exc}", file=sys.stderr)
        raise
