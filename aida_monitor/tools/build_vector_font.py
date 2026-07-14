#!/usr/bin/env python3
"""Build the single vector font shipped with AIDA Monitor.

The source is the OFL-licensed Noto Sans SC variable font from Google Fonts.
The output is a static 400-weight TrueType font containing GB2312, printable
ASCII, and the symbols commonly emitted by AIDA64.  Keeping one curated CJK
font makes on-device TrueType rasterization fit comfortably in PSRAM.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


EXTRA_SYMBOLS = (
    "°℃℉µΩ→←↑↓·—–…，。！？：；（）【】《》“”‘’￥％‰±×÷≤≥≈≠∞"
    "①②③④⑤⑥⑦⑧⑨⑩✓✕●○■□▲△▼▽◆◇"
)


def gb2312_characters() -> str:
    result: list[str] = []
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                result.append(bytes((high, low)).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return "".join(result)


def rename_font(font: TTFont) -> None:
    names = {
        1: "AIDA Noto Sans SC",
        2: "Regular",
        4: "AIDA Noto Sans SC Regular",
        6: "AIDANotoSansSC-Regular",
        16: "AIDA Noto Sans SC",
        17: "Regular",
    }
    table = font["name"]
    for name_id, value in names.items():
        table.setName(value, name_id, 3, 1, 0x0409)
        table.setName(value, name_id, 1, 0, 0)
    if "OS/2" in font:
        font["OS/2"].usWeightClass = 400
        font["OS/2"].fsSelection &= ~(1 << 5)
        font["OS/2"].fsSelection |= 1 << 6
    if "head" in font:
        font["head"].macStyle &= ~1


def build(source: Path, output: Path) -> None:
    font = TTFont(source)
    if "fvar" in font:
        font = instantiateVariableFont(font, {"wght": 400}, inplace=True, overlap=False)

    characters = "".join(chr(code) for code in range(0x20, 0x7F))
    characters += gb2312_characters() + EXTRA_SYMBOLS
    characters = "".join(dict.fromkeys(characters))

    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.layout_features = ["*"]
    options.hinting = False

    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=characters)
    subsetter.subset(font)
    rename_font(font)
    output.parent.mkdir(parents=True, exist_ok=True)
    font.save(output)
    print(f"wrote {output} ({output.stat().st_size} bytes, {len(characters)} characters)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="NotoSansSC[wght].ttf")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "package/font/aida_noto_sans_sc.ttf",
    )
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
