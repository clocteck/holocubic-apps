#!/usr/bin/env python3
"""Generate the HoloCubic ClawdMoji animation pack.

The canonical 12 x 8 sprite and outline helper are imported from the sibling
ClawdMoji project. Outputs are native-size indexed GIFs: 160 x 160 for Codex
status and 128 x 128 for weather. No runtime scaling or antialiasing is used.
"""

from __future__ import annotations

import json
import math
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


WORKSPACE = Path(__file__).resolve().parents[3]
CLAWDMOJI = WORKSPACE / "ClawdMoji"
sys.path.insert(0, str(CLAWDMOJI))

from shared.clawd import ART, border_mask, pen_square  # noqa: E402


OUT = Path(__file__).resolve().parents[1] / "package" / "assets" / "clawdmoji"
STATUS_OUT = OUT / "status"
WEATHER_OUT = OUT / "weather"
PREVIEW_OUT = Path(__file__).resolve().parents[1] / "art"

STATUS_SIZE = 160
WEATHER_SIZE = 128
FRAMES = 12
DURATION_MS = 120

# Fixed palette. Index 0 is always transparent in status GIFs.
COLORS = [
    (1, 2, 3),       # 0 transparent sentinel
    (6, 5, 4),       # 1 bg
    (18, 13, 10),    # 2 panel
    (85, 52, 39),    # 3 line
    (218, 119, 88),  # 4 Clawd rust
    (244, 193, 167), # 5 peach
    (255, 243, 232), # 6 cream
    (0, 0, 0),       # 7 eye black
    (143, 224, 199), # 8 mint
    (255, 209, 102), # 9 warn
    (255, 107, 107), # 10 error
    (90, 151, 191),  # 11 sky
    (55, 111, 151),  # 12 blue
    (27, 57, 79),    # 13 dark blue
    (181, 190, 193), # 14 cloud
    (100, 112, 119), # 15 cloud dark
    (108, 173, 103), # 16 green
    (48, 100, 64),   # 17 dark green
    (255, 255, 255), # 18 white outline
    (91, 183, 217),  # 19 rain
    (222, 246, 255), # 20 snow
    (166, 179, 181), # 21 fog
    (166, 112, 194), # 22 purple
    (241, 139, 64),  # 23 orange
    (255, 229, 92),  # 24 sun
    (121, 76, 54),   # 25 brown
    (94, 216, 220),  # 26 cyan
    (59, 52, 49),    # 27 grey
    (235, 151, 76),  # 28 amber
    (196, 220, 255), # 29 ice
    (214, 92, 72),   # 30 deep rust
    (131, 207, 240), # 31 light blue
]
PALETTE = [channel for rgb in COLORS for channel in rgb] + [0] * (768 - len(COLORS) * 3)


def frame(size: int, fill: int = 0) -> Image.Image:
    image = Image.new("P", (size, size), fill)
    image.putpalette(PALETTE)
    return image


def save_gif(frames: list[Image.Image], path: Path, transparent: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    options = dict(
        save_all=True,
        append_images=frames[1:],
        duration=DURATION_MS,
        loop=0,
        optimize=True,
        disposal=2,
    )
    if transparent:
        options["transparency"] = 0
    frames[0].save(path, **options)


def draw_clawd(
    image: Image.Image,
    x: int,
    y: int,
    cell: int,
    *,
    eye: str = "open",
    body_color: int = 4,
    outline: int = 2,
) -> None:
    """Draw canonical ClawdMoji ART with an integer-pixel outline."""
    h, w = image.height, image.width
    body = np.zeros((h, w), dtype=bool)
    eye_cells: list[tuple[int, int]] = []
    for gy, row in enumerate(ART):
        for gx, token in enumerate(row):
            if token in ("#", "O"):
                x0, y0 = x + gx * cell, y + gy * cell
                x1, y1 = min(w, x0 + cell), min(h, y0 + cell)
                if x1 > 0 and y1 > 0 and x0 < w and y0 < h:
                    body[max(0, y0):y1, max(0, x0):x1] = True
                if token == "O":
                    eye_cells.append((x0, y0))

    if outline > 0:
        border = border_mask(body, pen_square(outline))
        image.paste(18, mask=Image.fromarray((border * 255).astype("uint8"), "L"))
    image.paste(body_color, mask=Image.fromarray((body * 255).astype("uint8"), "L"))

    d = ImageDraw.Draw(image)
    for ex, ey in eye_cells:
        if eye == "closed":
            d.rectangle((ex + 1, ey + cell // 2, ex + cell - 2, ey + cell // 2 + 1), fill=7)
        elif eye == "wide":
            d.rectangle((ex + 1, ey + 1, ex + cell - 2, ey + cell - 2), fill=18)
            d.rectangle((ex + cell // 2 - 1, ey + cell // 2 - 1, ex + cell // 2 + 1, ey + cell // 2 + 1), fill=7)
        elif eye == "focus":
            d.rectangle((ex + 1, ey + 2, ex + cell - 2, ey + cell - 2), fill=7)
            d.rectangle((ex + 1, ey + 2, ex + cell // 2, ey + 3), fill=18)
        elif eye == "happy":
            d.line((ex + 1, ey + cell // 2, ex + cell // 2, ey + 2, ex + cell - 2, ey + cell // 2), fill=7, width=2)
        else:
            inset = max(1, cell // 5)
            d.rectangle((ex + inset, ey + inset, ex + cell - inset - 1, ey + cell - inset - 1), fill=7)


def cloud(d: ImageDraw.ImageDraw, x: int, y: int, color: int = 14) -> None:
    d.rectangle((x + 5, y, x + 20, y + 8), fill=color)
    d.rectangle((x, y + 5, x + 28, y + 13), fill=color)
    d.rectangle((x + 9, y - 4, x + 17, y + 10), fill=color)


def sparkle(d: ImageDraw.ImageDraw, x: int, y: int, color: int = 9, size: int = 4) -> None:
    d.rectangle((x - size, y, x + size, y + 1), fill=color)
    d.rectangle((x, y - size, x + 1, y + size), fill=color)


def draw_prop(d: ImageDraw.ImageDraw, name: str, f: int, variant: int) -> None:
    pulse = 1 if math.sin(2 * math.pi * f / FRAMES) > 0 else 0
    shift = (f + variant) % FRAMES
    if name in {"coffee", "tea"}:
        d.rectangle((117, 101, 143, 122), fill=6)
        d.rectangle((121, 105, 139, 118), fill=25)
        d.rectangle((143, 106, 149, 116), outline=6, width=2)
        for i in range(2):
            x = 124 + i * 9 + pulse
            d.line((x, 98, x - 2, 91, x + 1, 84), fill=21, width=2)
    elif name in {"book", "stack"}:
        d.rectangle((112, 99, 148, 124), fill=22)
        d.line((130, 99, 130, 124), fill=6, width=2)
        d.line((116, 105, 126, 105), fill=5, width=2)
        d.line((134, 105, 144, 105), fill=5, width=2)
    elif name == "plant":
        d.rectangle((120, 107, 143, 127), fill=25)
        d.line((131, 107, 131, 86), fill=17, width=3)
        d.ellipse((116 + pulse, 86, 132, 99), fill=16)
        d.ellipse((130, 80 + pulse, 145, 96), fill=16)
    elif name in {"music", "dance"}:
        for i, (x, y) in enumerate(((21, 42), (128, 28), (139, 58))):
            yy = y + int(3 * math.sin(2 * math.pi * (f + i * 3) / FRAMES))
            d.line((x + 5, yy, x + 5, yy + 15), fill=9, width=3)
            d.ellipse((x, yy + 12, x + 7, yy + 19), fill=9)
    elif name in {"star", "spark", "pop"}:
        for i in range(4):
            a = 2 * math.pi * (i / 4 + f / FRAMES)
            sparkle(d, int(80 + math.cos(a) * (55 + pulse * 3)), int(78 + math.sin(a) * 55), 9 if i % 2 else 8, 3)
    elif name == "bug":
        x = 130 + int(math.sin(2 * math.pi * f / FRAMES) * 12)
        y = 62 + int(math.sin(4 * math.pi * f / FRAMES) * 7)
        d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=7)
        d.rectangle((x - 7, y - 5, x - 3, y), fill=9)
        d.rectangle((x + 3, y - 5, x + 7, y), fill=9)
    elif name == "clock":
        d.rectangle((119, 30, 146, 57), fill=6)
        d.rectangle((122, 33, 143, 54), fill=13)
        d.line((132, 43, 132, 36), fill=8, width=2)
        d.line((132, 43, 139, 46), fill=8, width=2)
    elif name in {"paint", "tidy", "broom"}:
        d.line((119, 117, 148, 79), fill=25, width=4)
        d.rectangle((112, 111, 127, 126), fill=9 if name == "paint" else 8)
        if name == "paint":
            d.rectangle((140, 123, 150, 129), fill=22)
    elif name == "snack":
        d.rectangle((118, 103, 147, 128), fill=28)
        d.polygon(((118, 103), (147, 103), (142, 94), (123, 94)), fill=9)
        d.rectangle((125, 108, 140, 112), fill=30)
    elif name in {"radio", "signal"}:
        d.rectangle((114, 96, 148, 126), fill=13)
        d.rectangle((120, 102, 141, 112), fill=26)
        d.line((139, 96, 148, 80), fill=6, width=2)
        for radius in (8, 14):
            d.arc((129 - radius, 71 - radius, 129 + radius, 71 + radius), 210, 330, fill=8, width=2)
    elif name in {"orbit", "focus"}:
        for i in range(3):
            a = 2 * math.pi * (f / FRAMES + i / 3)
            x, y = int(80 + math.cos(a) * 61), int(80 + math.sin(a) * 46)
            d.rectangle((x - 3, y - 3, x + 3, y + 3), fill=(8, 9, 22)[i])
    elif name in {"rainwatch", "umbrella"}:
        d.arc((109, 34, 151, 77), 180, 360, fill=19, width=5)
        d.line((130, 55, 130, 104, 138, 111), fill=19, width=3)
        for i in range(5):
            x = 15 + ((i * 31 + f * 5) % 140)
            y = 24 + ((i * 23 + f * 9) % 80)
            d.line((x, y, x - 3, y + 9), fill=19, width=2)
    elif name in {"sun", "wave"}:
        d.ellipse((120, 22, 149, 51), fill=24)
        for i in range(8):
            a = 2 * math.pi * i / 8
            d.line((int(134 + math.cos(a) * 19), int(36 + math.sin(a) * 19), int(134 + math.cos(a) * 25), int(36 + math.sin(a) * 25)), fill=24, width=2)
    elif name in {"moon", "zzz", "lamp"}:
        d.ellipse((116, 22, 148, 54), fill=24)
        d.ellipse((108, 16, 138, 46), fill=0)
        if name != "lamp":
            d.line((126, 66, 142, 66, 128, 80, 145, 80), fill=22, width=3)
    elif name in {"terminal", "code"}:
        d.rectangle((108, 92, 151, 126), fill=13)
        d.rectangle((112, 96, 147, 122), fill=2)
        d.line((116, 102, 123, 107, 116, 112), fill=8, width=2)
        d.line((127, 114, 141 - pulse * 3, 114), fill=26, width=2)
    elif name in {"question", "bubble", "ear"}:
        d.rectangle((111, 24, 149, 59), fill=6)
        d.polygon(((120, 59), (126, 69), (132, 59)), fill=6)
        if name == "question":
            d.line((126, 33, 136, 29, 142, 35, 135, 43, 135, 49), fill=22, width=3)
            d.rectangle((134, 53, 137, 56), fill=22)
        else:
            for i in range(3):
                d.rectangle((120 + i * 9, 39, 124 + i * 9, 43), fill=4)
    elif name in {"hammer", "gear", "search", "inspect"}:
        if name in {"search", "inspect"}:
            d.ellipse((114, 35, 140, 61), outline=8, width=4)
            d.line((137, 58, 150, 73), fill=8, width=4)
        else:
            d.rectangle((119, 36, 145, 51), fill=15)
            d.line((131, 50, 113, 77), fill=25, width=5)
            if name == "gear":
                d.ellipse((116, 87, 147, 118), outline=8, width=5)
                d.ellipse((127, 98, 136, 107), fill=8)
    elif name in {"lock", "key", "shield", "alert"}:
        if name == "key":
            d.ellipse((117, 39, 136, 58), outline=9, width=4)
            d.line((133, 55, 150, 72), fill=9, width=4)
            d.line((143, 65, 148, 60), fill=9, width=3)
        elif name == "alert":
            d.polygon(((132, 27), (151, 64), (112, 64)), fill=9)
            d.rectangle((130, 38, 134, 51), fill=2)
            d.rectangle((130, 56, 134, 59), fill=2)
        else:
            d.rectangle((114, 48, 148, 76), fill=9 if name == "lock" else 8)
            d.arc((120, 30, 142, 58), 180, 360, fill=9, width=5)
            if name == "shield":
                d.polygon(((131, 83), (147, 75), (145, 99), (131, 111), (116, 99), (114, 75)), fill=8)
    elif name in {"check", "mintcheck", "package", "box", "zip", "funnel", "squeeze"}:
        if name in {"check", "mintcheck"}:
            d.line((113, 55, 125, 68, 150, 35), fill=8, width=6)
        elif name == "funnel":
            d.polygon(((109, 31), (151, 31), (137, 52), (137, 72), (124, 72), (124, 52)), fill=22)
        else:
            d.rectangle((112, 91, 149, 124), fill=25)
            d.line((112, 100, 149, 100), fill=9, width=3)
            d.line((130, 91, 130, 124), fill=9, width=3)
            if name == "zip":
                d.line((137, 30, 137, 80), fill=6, width=3)
                for y in range(34, 80, 8):
                    d.line((128, y, 146, y), fill=6, width=2)
    elif name in {"clone", "split", "merge", "highfive", "home"}:
        draw_clawd(d._image, 111, 30 + pulse * 2, 3, outline=1, eye="happy")
        draw_clawd(d._image, 128, 58 - pulse * 2, 3, outline=1, eye="open")
        if name in {"merge", "home"}:
            d.line((119, 81, 128, 91, 138, 81), fill=8, width=3)
        elif name == "highfive":
            d.line((118, 91, 130, 78, 142, 91), fill=9, width=4)
    elif name in {"rocket", "flag"}:
        d.polygon(((130, 27), (146, 57), (134, 73), (118, 57)), fill=6)
        d.ellipse((127, 45, 137, 55), fill=12)
        d.polygon(((124, 70), (133, 93), (141, 70)), fill=23 if pulse else 9)
    elif name in {"crown", "confetti", "heart"}:
        if name == "crown":
            d.polygon(((113, 55), (113, 34), (124, 45), (132, 28), (140, 45), (151, 34), (151, 55)), fill=9)
        elif name == "heart":
            d.polygon(((132, 70), (112, 49), (117, 37), (131, 44), (145, 37), (151, 49)), fill=10)
        else:
            for i in range(16):
                x = 10 + ((i * 37 + f * (3 + i % 3)) % 140)
                y = 18 + ((i * 23 + f * 7) % 115)
                d.rectangle((x, y, x + 3, y + 5), fill=(8, 9, 22, 10)[i % 4])
    elif name in {"cross", "bugerror", "smoke", "bandage"}:
        if name == "cross":
            d.line((116, 34, 149, 67), fill=10, width=6)
            d.line((149, 34, 116, 67), fill=10, width=6)
        elif name == "smoke":
            for i in range(4):
                x = 119 + i * 7 + int(math.sin((f + i) * 0.8) * 3)
                y = 70 - i * 12
                d.rectangle((x, y, x + 9, y + 9), fill=15)
        elif name == "bandage":
            d.rectangle((113, 44, 150, 58), fill=5)
            d.rectangle((128, 42, 136, 60), fill=6)
        else:
            d.ellipse((122, 42, 142, 62), fill=7)
            d.line((115, 34, 149, 70), fill=10, width=3)
    elif name == "blanket":
        d.rectangle((31, 91, 129, 135), fill=22)
        for x in range(35, 126, 14):
            d.rectangle((x, 97, x + 6, 103), fill=5)


IDLE_PROPS = [
    "coffee", "book", "plant", "music", "star", "bug", "clock", "paint",
    "snack", "radio", "orbit", "stretch", "toe", "sway", "wave", "breathe",
    "yawn", "nap", "code", "rainwatch", "sun", "moon", "dance", "tidy",
]

EVENT_PROPS = {
    "SessionStart": ["sun", "wave", "coffee", "spark"],
    "UserPromptSubmit": ["bubble", "question", "ear", "focus"],
    "PreToolUse": ["terminal", "hammer", "search", "gear"],
    "PermissionRequest": ["lock", "key", "shield", "alert"],
    "PostToolUse": ["check", "stack", "inspect", "spark"],
    "PreCompact": ["funnel", "box", "zip", "squeeze"],
    "PostCompact": ["package", "broom", "mintcheck", "pop"],
    "SubagentStart": ["clone", "rocket", "split", "signal"],
    "SubagentStop": ["highfive", "merge", "wave", "home"],
    "Stop": ["crown", "confetti", "tea", "heart", "flag"],
    "Error": ["cross", "smoke", "bugerror", "bandage"],
    "Sleeping": ["moon", "zzz", "blanket", "lamp"],
}


def status_frames(event: str, prop: str, variant: int) -> list[Image.Image]:
    images: list[Image.Image] = []
    for f in range(FRAMES):
        image = frame(STATUS_SIZE)
        d = ImageDraw.Draw(image)
        phase = 2 * math.pi * (f / FRAMES)
        bob = int(round(math.sin(phase) * (1 + variant % 2)))
        sway = int(round(math.sin(phase) * 2)) if prop in {"sway", "dance", "wave"} else 0
        eye = "open"
        if event == "Sleeping" or prop in {"nap", "zzz", "blanket"}:
            eye = "closed"
        elif event in {"Stop", "PostToolUse", "PostCompact", "SubagentStop"}:
            eye = "happy"
        elif event in {"PermissionRequest", "PreToolUse", "PreCompact"}:
            eye = "focus"
        elif event == "Error":
            eye = "wide"
        elif (f + variant * 2) % FRAMES in (0, 1):
            eye = "closed"

        body_y = 56 + bob
        if prop in {"stretch", "yawn"}:
            body_y -= abs(int(math.sin(phase) * 5))
        draw_clawd(image, 20 + sway, body_y, 10, eye=eye)
        if prop not in {"stretch", "toe", "sway", "breathe", "yawn", "nap"}:
            draw_prop(d, prop, f, variant)
        elif prop == "toe":
            d.rectangle((38 + ((f // 2) % 2) * 5, 136, 51 + ((f // 2) % 2) * 5, 141), fill=9)
        elif prop == "breathe":
            for i in range(3):
                x = 124 + i * 9 + int(math.sin(phase + i) * 2)
                d.rectangle((x, 45 + i * 8, x + 3, 48 + i * 8), fill=8)
        elif prop == "yawn":
            d.ellipse((72, 88, 88, 98), fill=7)
        elif prop == "nap":
            draw_prop(d, "zzz", f, variant)
        images.append(image)
    return images


WEATHER_KINDS = ["clear", "partly", "cloudy", "overcast", "drizzle", "rain", "storm", "snow", "fog", "wind"]
WEATHER_MOODS = ["cold_dry", "cold_humid", "mild_dry", "mild_humid", "hot_dry", "hot_humid"]


def weather_frames(kind: str, mood: str) -> list[Image.Image]:
    images: list[Image.Image] = []
    temp_band, humidity_band = mood.split("_")
    for f in range(FRAMES):
        phase = 2 * math.pi * f / FRAMES
        dark = kind in {"overcast", "rain", "storm", "fog"}
        image = frame(WEATHER_SIZE, 13 if dark else 11)
        d = ImageDraw.Draw(image)

        # Sky and terrain establish a complete opaque scene.
        d.rectangle((0, 94, 127, 127), fill=17 if dark else 16)
        for x in range(0, 128, 13):
            h = 3 + ((x * 7 + f) % 8)
            d.line((x, 100, x + int(math.sin(phase + x) * 2), 100 - h), fill=8 if not dark else 17, width=1)

        if kind in {"clear", "partly"}:
            sx, sy = 102, 21
            d.ellipse((sx - 12, sy - 12, sx + 12, sy + 12), fill=24)
            for i in range(8):
                a = 2 * math.pi * (i / 8 + f / FRAMES / 8)
                d.line((int(sx + math.cos(a) * 16), int(sy + math.sin(a) * 16), int(sx + math.cos(a) * 22), int(sy + math.sin(a) * 22)), fill=24, width=2)
        if kind in {"partly", "cloudy", "overcast", "drizzle", "rain", "storm"}:
            count = 1 if kind == "partly" else 3
            for i in range(count):
                x = -15 + ((i * 51 + f * (1 + i % 2)) % 150)
                y = 16 + i * 14
                cloud(d, x, y, 15 if dark else 14)
        if kind in {"drizzle", "rain", "storm"}:
            drops = 7 if kind == "drizzle" else 15
            for i in range(drops):
                x = (i * 19 + f * (4 if kind == "drizzle" else 7)) % 134 - 4
                y = 38 + ((i * 17 + f * 11) % 65)
                length = 4 if kind == "drizzle" else 8
                d.line((x, y, x - 2, y + length), fill=19, width=1 if kind == "drizzle" else 2)
        if kind == "storm" and f in {2, 3, 8}:
            d.line((85, 39, 73, 59, 82, 59, 69, 82), fill=9, width=4)
        if kind == "snow":
            for i in range(18):
                x = (i * 23 + f * (1 + i % 3)) % 132 - 2
                y = (i * 17 + f * 5) % 100
                d.rectangle((x, y, x + 2, y + 2), fill=20)
        if kind == "fog":
            for i in range(5):
                y = 25 + i * 15
                offset = int(math.sin(phase + i) * 7)
                d.rectangle((-8 + offset, y, 102 + offset, y + 4), fill=21)
        if kind == "wind":
            for i in range(6):
                y = 18 + i * 14
                x = -35 + ((f * 9 + i * 27) % 180)
                d.line((x, y, x + 31, y, x + 38, y - 5), fill=29, width=2)

        bob = int(round(math.sin(phase) * 1))
        if temp_band == "cold":
            bob += 1 if f % 3 == 0 else -1 if f % 3 == 1 else 0
        draw_clawd(image, 28, 58 + bob, 6, eye="closed" if f == 0 else "open", outline=1)

        if temp_band == "cold":
            d.rectangle((38, 75 + bob, 91, 82 + bob), fill=22)
            d.rectangle((83, 80 + bob, 91, 96 + bob), fill=22)
            d.rectangle((24, 52, 29, 58), fill=29)
        elif temp_band == "hot":
            for i in range(3):
                x = 24 + i * 39
                y = 57 + ((f * 5 + i * 13) % 27)
                d.polygon(((x, y), (x - 3, y + 7), (x + 3, y + 7)), fill=31)
            d.rectangle((91, 83, 115, 86), fill=25)
            d.arc((96, 68, 116, 88), 150, 390, fill=6, width=2)
        else:
            sparkle(d, 18, 83 + int(math.sin(phase) * 3), 8, 2)

        if humidity_band == "humid":
            for i in range(4):
                x = 15 + i * 30
                y = 106 + ((f * 2 + i * 5) % 13)
                d.rectangle((x, y, x + 5, y + 2), fill=26)
        else:
            d.line((104, 112, 111, 106, 116, 112, 123, 106), fill=28, width=2)

        images.append(image)
    return images


def contact_sheet(paths: list[Path], output: Path, columns: int, tile: int) -> None:
    if not paths:
        return
    rows = math.ceil(len(paths) / columns)
    sheet = Image.new("RGB", (columns * tile, rows * tile), (18, 13, 10))
    for i, path in enumerate(paths):
        with Image.open(path) as gif:
            still = gif.convert("RGBA")
            bg = Image.new("RGBA", still.size, (6, 5, 4, 255))
            bg.alpha_composite(still)
            still_rgb = bg.convert("RGB")
            if still_rgb.size != (tile, tile):
                still_rgb = still_rgb.resize((tile, tile), Image.Resampling.NEAREST)
            sheet.paste(still_rgb, ((i % columns) * tile, (i // columns) * tile))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def lua_quote(value: str) -> str:
    return json.dumps(value).replace("\\/", "/")


def main() -> None:
    if not (CLAWDMOJI / "shared" / "clawd.py").exists():
        raise SystemExit(f"ClawdMoji source not found: {CLAWDMOJI}")
    if OUT.exists():
        shutil.rmtree(OUT)
    STATUS_OUT.mkdir(parents=True)
    WEATHER_OUT.mkdir(parents=True)

    status_manifest: dict[str, list[str]] = {}
    status_paths: list[Path] = []

    idle_files: list[str] = []
    for i, prop in enumerate(IDLE_PROPS, 1):
        filename = f"idle_{i:02d}.gif"
        path = STATUS_OUT / filename
        save_gif(status_frames("Idle", prop, i), path, True)
        idle_files.append(f"/sd/apps/holo_pet/assets/clawdmoji/status/{filename}")
        status_paths.append(path)
    status_manifest["Idle"] = idle_files

    for event, props in EVENT_PROPS.items():
        files: list[str] = []
        slug = event.lower()
        for i, prop in enumerate(props, 1):
            filename = f"{slug}_{i:02d}.gif"
            path = STATUS_OUT / filename
            save_gif(status_frames(event, prop, i), path, True)
            files.append(f"/sd/apps/holo_pet/assets/clawdmoji/status/{filename}")
            status_paths.append(path)
        status_manifest[event] = files

    weather_manifest: dict[str, dict[str, str]] = {}
    weather_paths: list[Path] = []
    for kind in WEATHER_KINDS:
        moods: dict[str, str] = {}
        for mood in WEATHER_MOODS:
            filename = f"{kind}_{mood}.gif"
            path = WEATHER_OUT / filename
            save_gif(weather_frames(kind, mood), path, False)
            moods[mood] = f"/sd/apps/holo_pet/assets/clawdmoji/weather/{filename}"
            weather_paths.append(path)
        weather_manifest[kind] = moods

    lines = ["-- Generated by tools/generate_clawdmoji_pack.py", "return {", "  events = {"]
    for event, paths in status_manifest.items():
        values = ", ".join(lua_quote(p) for p in paths)
        lines.append(f"    [{lua_quote(event)}] = {{ {values} }},")
    lines.extend(["  },", "  weather = {"])
    for kind, moods in weather_manifest.items():
        lines.append(f"    [{lua_quote(kind)}] = {{")
        for mood, path in moods.items():
            lines.append(f"      [{lua_quote(mood)}] = {lua_quote(path)},")
        lines.append("    },")
    lines.extend(["  },", "}", ""])
    (OUT / "manifest.lua").write_text("\n".join(lines), encoding="utf-8", newline="\n")

    icon = frame(75)
    draw_clawd(icon, 7, 17, 5, eye="open", outline=1)
    icon.save(OUT.parents[1] / "main.png", transparency=0, optimize=True)

    contact_sheet(status_paths, PREVIEW_OUT / "clawdmoji-status-contact-sheet.png", 8, 80)
    contact_sheet(weather_paths, PREVIEW_OUT / "clawdmoji-weather-contact-sheet.png", 10, 64)

    total_bytes = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
    report = {
        "source": "https://github.com/afspies/ClawdMoji/blob/main/shared/clawd.py",
        "idle_animations": len(status_manifest["Idle"]),
        "event_groups": {key: len(value) for key, value in status_manifest.items() if key != "Idle"},
        "weather_combinations": len(weather_paths),
        "total_files": len(status_paths) + len(weather_paths),
        "total_bytes": total_bytes,
        "launcher_icon": "package/main.png",
    }
    (OUT / "build-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
