#!/usr/bin/env python3
"""Generate compact 128px Clawd meme loops for the HoloCubic session page."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

WORKSPACE = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(WORKSPACE / "ClawdMoji"))
from shared.clawd import ART, CLAWD_RGB, border_mask, pen_square  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "package" / "assets" / "clawdmoji" / "meme"
N = 128
F = 20
DUR = 95

COLORS = [
    (0, 0, 0),             # 0 transparent
    (255, 243, 232),       # 1 warm outline
    CLAWD_RGB,             # 2 body
    (6, 5, 4),             # 3 eyes / ink
    (25, 18, 14),          # 4 panel black
    (244, 193, 167),       # 5 peach
    (255, 209, 102),       # 6 yellow
    (255, 107, 107),       # 7 red
    (91, 183, 217),        # 8 blue
    (143, 224, 199),       # 9 mint
    (154, 117, 100),       # 10 dim
    (104, 57, 38),         # 11 brown
    (218, 234, 240),       # 12 pale blue
    (217, 119, 87),        # 13 rust
    (88, 192, 120),        # 14 chart green
    (74, 44, 34),          # 15 shadow
]
T, OUTLINE, BODY, INK, BLACK, PEACH, YELLOW, RED, BLUE, MINT, DIM, BROWN, PALE, RUST, GREEN, SHADOW = range(16)
PAL = bytes([channel for rgb in COLORS for channel in rgb] + [0] * (768 - len(COLORS) * 3))


def canvas() -> Image.Image:
    image = Image.new("P", (N, N), T)
    image.putpalette(PAL)
    return image


def draw_clawd(image: Image.Image, x: int, y: int, scale: int = 7, squash: int = 0) -> None:
    """Draw the canonical 12x8 Clawd grid with its two-pixel warm outline."""
    cell_h = max(3, scale - squash)
    sprite = np.zeros((N, N), dtype=np.uint8)
    for row, line in enumerate(ART):
        for col, char in enumerate(line):
            if char == ".":
                continue
            y0, y1 = y + row * cell_h, y + (row + 1) * cell_h
            x0, x1 = x + col * scale, x + (col + 1) * scale
            if y1 <= 0 or x1 <= 0 or y0 >= N or x0 >= N:
                continue
            sprite[max(0, y0):min(N, y1), max(0, x0):min(N, x1)] = INK if char == "O" else BODY
    mask = sprite != T
    outline = border_mask(mask, pen_square(2))
    target = np.array(image)
    target[outline] = OUTLINE
    target[mask] = sprite[mask]
    image.paste(Image.fromarray(target, "P"))
    image.putpalette(PAL)


def pixel_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fill: int, scale: int = 2) -> None:
    font = {
        "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
        "E": ["111", "100", "110", "100", "111"], "K": ["101", "110", "100", "110", "101"],
        "N": ["101", "111", "111", "111", "101"], "O": ["010", "101", "101", "101", "010"],
        "P": ["110", "101", "110", "100", "100"], "S": ["011", "100", "010", "001", "110"],
        "T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
        "!": ["1", "1", "1", "0", "1"], " ": ["0", "0", "0", "0", "0"],
    }
    x, y = xy
    cursor = x
    for char in text:
        glyph = font.get(char, font[" "])
        width = len(glyph[0])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    draw.rectangle((cursor + gx * scale, y + gy * scale,
                                    cursor + (gx + 1) * scale - 1, y + (gy + 1) * scale - 1), fill=fill)
        cursor += (width + 1) * scale


def save(name: str, frames: list[Image.Image], representative: int = 0) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.gif"
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=DUR, loop=0,
                   transparency=T, disposal=2, optimize=False)
    frames[representative % len(frames)].convert("RGBA").save(OUT / f"{name}_still.png")
    return path


def keyboard() -> Path:
    frames = []
    for f in range(F):
        im, d = canvas(), None
        d = ImageDraw.Draw(im)
        for row in range(4):
            width = 28 + ((row * 11 + f * 5) % 34)
            d.rectangle((8, 6 + row * 6, 8 + width, 8 + row * 6), fill=DIM if row < 3 else MINT)
        bob = 1 if f % 4 in (1, 2) else 0
        draw_clawd(im, 22, 29 + bob, 7)
        d = ImageDraw.Draw(im)
        d.rectangle((13, 91, 115, 113), fill=OUTLINE)
        d.rectangle((16, 94, 112, 110), fill=BLACK)
        for ky in range(2):
            for kx in range(10):
                hot = (kx + ky * 3 + f) % 7 == 0
                x, y = 20 + kx * 9, 97 + ky * 7
                d.rectangle((x, y, x + 5, y + 3), fill=PEACH if hot else DIM)
        hand_x = 40 if f % 2 == 0 else 78
        d.rectangle((hand_x, 84, hand_x + 10, 98), fill=BODY)
        for k in range(3):
            px = 26 + ((f * 13 + k * 31) % 76)
            py = 82 - ((f * 7 + k * 11) % 18)
            d.rectangle((px, py, px + 3, py + 2), fill=YELLOW)
        frames.append(im)
    return save("keyboard", frames, 7)


def popcorn() -> Path:
    frames = []
    for f in range(F):
        im = canvas()
        draw_clawd(im, 22, 25, 7)
        d = ImageDraw.Draw(im)
        d.polygon([(44, 82), (84, 82), (78, 119), (50, 119)], fill=OUTLINE)
        for x in range(50, 80, 8):
            d.rectangle((x, 87, x + 4, 116), fill=RED if (x // 8) % 2 else PEACH)
        for k in range(8):
            x = 47 + ((k * 17 + f * 2) % 36)
            y = 78 + ((k * 7) % 8)
            d.rectangle((x, y, x + 5, y + 4), fill=YELLOW)
            d.point((x + 2, y + 1), fill=OUTLINE)
        eat = f % 10
        if eat < 6:
            hx = 86 - eat * 4
            hy = 88 - eat * 6
            d.line((83, 91, hx, hy), fill=BODY, width=6)
            d.rectangle((hx - 2, hy - 2, hx + 3, hy + 3), fill=YELLOW)
        for k in range(3):
            phase = (f + k * 6) % F
            x = 52 + k * 13 + int(5 * math.sin(phase * math.pi / 10))
            y = 72 - int(10 * abs(math.sin(phase * math.pi / 10)))
            d.rectangle((x, y, x + 4, y + 3), fill=YELLOW)
        frames.append(im)
    return save("popcorn", frames, 4)


def bonk() -> Path:
    frames = []
    for f in range(F):
        phase = f / F * 2 * math.pi
        impact = f in (9, 10)
        im = canvas()
        draw_clawd(im, 22, 40 + (4 if impact else 0), 7, squash=1 if impact else 0)
        d = ImageDraw.Draw(im)
        angle = -1.15 + 1.55 * (0.5 - 0.5 * math.cos(phase))
        pivot = (112, 10)
        tip = (int(pivot[0] - 74 * math.cos(angle)), int(pivot[1] + 74 * math.sin(angle)))
        d.line((pivot[0], pivot[1], tip[0], tip[1]), fill=BROWN, width=6)
        d.rectangle((tip[0] - 15, tip[1] - 7, tip[0] + 9, tip[1] + 7), fill=OUTLINE)
        d.rectangle((tip[0] - 12, tip[1] - 5, tip[0] + 6, tip[1] + 5), fill=RED)
        if impact:
            pixel_text(d, (7, 9), "BONK!", YELLOW, 2)
            for sx, sy in ((26, 34), (43, 23), (68, 29), (88, 37)):
                d.line((sx - 3, sy, sx + 3, sy), fill=YELLOW, width=2)
                d.line((sx, sy - 3, sx, sy + 3), fill=YELLOW, width=2)
        frames.append(im)
    return save("bonk", frames, 9)


def stonks() -> Path:
    frames = []
    for f in range(F):
        im = canvas()
        d = ImageDraw.Draw(im)
        for x in range(8, 125, 16): d.line((x, 10, x, 112), fill=SHADOW)
        for y in range(16, 113, 16): d.line((8, y, 122, y), fill=SHADOW)
        points = [(10, 103), (28, 91), (43, 96), (60, 72), (78, 76), (96, 44), (119, 20)]
        reveal = max(2, min(len(points), 2 + f // 3))
        d.line(points[:reveal], fill=GREEN, width=5)
        if reveal == len(points):
            d.polygon([(119, 20), (108, 23), (116, 31)], fill=GREEN)
        draw_clawd(im, 22, 47 + int(2 * math.sin(f * math.pi / 5)), 7)
        d = ImageDraw.Draw(im)
        d.rectangle((38, 57, 90, 62), fill=BLACK)
        d.rectangle((39, 62, 58, 73), fill=BLACK)
        d.rectangle((70, 62, 89, 73), fill=BLACK)
        if f in (14, 15):
            d.rectangle((40, 63, 43, 66), fill=PALE)
            d.rectangle((71, 63, 74, 66), fill=PALE)
        pixel_text(d, (7, 5), "STONKS", MINT, 1)
        frames.append(im)
    return save("stonks", frames, 15)


def panic_button() -> Path:
    frames = []
    for f in range(F):
        press = f % 8 in (4, 5)
        im = canvas()
        draw_clawd(im, 22, 25 + (2 if press else 0), 7)
        d = ImageDraw.Draw(im)
        d.rectangle((33, 102, 95, 119), fill=OUTLINE)
        d.rectangle((38, 106, 90, 116), fill=BLACK)
        button_y = 92 if press else 86
        d.ellipse((51, button_y, 77, button_y + 14), fill=OUTLINE)
        d.ellipse((54, button_y + 2, 74, button_y + 12), fill=RED)
        hand_y = button_y - 11
        d.line((87, 75, 65, hand_y), fill=BODY, width=7)
        if press:
            pixel_text(d, (12, 6), "PANIC!", RED, 2)
            for x in (27, 99): d.line((x, 84, x + (-8 if x < 60 else 8), 76), fill=YELLOW, width=3)
        else:
            pixel_text(d, (18, 8), "PUSH", DIM, 2)
        frames.append(im)
    return save("panic", frames, 5)


def contact_sheet(paths: list[Path]) -> None:
    sheet = Image.new("RGBA", (N * len(paths), N), (16, 4, 8, 255))
    for index, path in enumerate(paths):
        still = Image.open(path.with_name(path.stem + "_still.png")).convert("RGBA")
        sheet.alpha_composite(still, (index * N, 0))
    sheet.save(OUT / "generated_memes_preview.png")


def main() -> None:
    paths = [keyboard(), popcorn(), bonk(), stonks(), panic_button()]
    contact_sheet(paths)
    for path in paths:
        print(f"{path.name}\t{path.stat().st_size}")


if __name__ == "__main__":
    main()
