#!/usr/bin/env python3
"""Render AIDA64 RemoteSensor layouts to native 320x240 PNG previews.

With no arguments the script renders the comprehensive test fixture. Pass
--aida to fetch the current layout and one SSE update from a running AIDA64
RemoteSensor instance.
"""

from __future__ import annotations

import argparse
import csv
import html as html_module
import io
import json
import math
import re
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LAYOUT = ROOT / "tests" / "fixtures" / "remotesensor-layout.html"
W, H = 320, 240


def number(value: object, fallback: float = 0) -> float:
    match = re.search(r"[-+]?\d+(?:\.\d+)?", str(value or ""))
    return float(match.group(0)) if match else fallback


def integer(value: object, fallback: int = 0) -> int:
    return round(number(value, fallback))


def font_pixels(value: object, fallback: int = 10) -> int:
    pixels = number(value, fallback)
    if "pt" in str(value or "").lower():
        pixels *= 4 / 3
    return max(6, min(96, round(pixels)))


def color(value: object, fallback: str = "#000000") -> str:
    match = re.search(r"#([0-9a-fA-F]{6})", str(value or ""))
    return f"#{match.group(1).upper()}" if match else fallback


def parse_style(raw: str | None) -> dict[str, str]:
    result: dict[str, str] = {}
    for part in (raw or "").split(";"):
        if ":" in part:
            key, value = part.split(":", 1)
            result[key.strip().lower()] = value.strip()
    return result


def geometry(style: dict[str, str]) -> dict[str, int]:
    return {key: integer(style.get(css, 0)) for key, css in {
        "x": "left", "y": "top", "w": "width", "h": "height"
    }.items()}


def gradients(raw: object, fallback: str) -> tuple[str, str]:
    values = re.findall(r"#[0-9a-fA-F]{6}", str(raw or ""))[:2]
    if not values:
        values = [fallback]
    if len(values) == 1:
        values.append(values[0])
    return color(values[0], fallback), color(values[1], fallback)


def text_style(style: dict[str, str], value: str) -> dict[str, Any]:
    size = font_pixels(style.get("font-size"), 10)
    align = style.get("text-align", "right" if style.get("float") == "right" else "left")
    return {
        "text": html_module.unescape(value),
        "color": color(style.get("color"), "#FFFFFF"),
        "size": size,
        "family": style.get("font-family", "Arial"),
        "bold": "bold" in style.get("font-weight", "").lower()
        or integer(style.get("font-weight"), 0) >= 600,
        "italic": "italic" in style.get("font-style", "").lower(),
        "underline": "underline" in style.get("text-decoration", "").lower(),
        "strike": "line-through" in style.get("text-decoration", "").lower(),
        "shadow": {
            "x": integer(re.findall(r"[-+]?\d+(?:\.\d+)?px", style.get("text-shadow", ""))[0], 0),
            "y": integer(re.findall(r"[-+]?\d+(?:\.\d+)?px", style.get("text-shadow", ""))[1], 0),
            "color": color(style.get("text-shadow"), "#000000"),
        } if len(re.findall(r"[-+]?\d+(?:\.\d+)?px", style.get("text-shadow", ""))) >= 2 else None,
        "align": align,
    }


def js_arguments(raw: str) -> list[Any]:
    values = next(csv.reader(io.StringIO(raw), skipinitialspace=True))
    parsed: list[Any] = []
    for value in values:
        value = value.strip()
        try:
            parsed.append(float(value) if "." in value else int(value))
        except ValueError:
            parsed.append(value)
    return parsed


@dataclass
class Item:
    id: str
    kind: str
    page: int
    geometry: dict[str, int]
    style: dict[str, str] = field(default_factory=dict)
    data: dict[str, Any] = field(default_factory=dict)


@dataclass
class Layout:
    background: str
    pages: list[list[Item]]
    items: dict[str, Item]
    source_base: str | None = None
    source_dir: Path | None = None


def parse_layout(document: str, source_base: str | None = None,
                 source_dir: Path | None = None) -> Layout:
    background = color(re.search(r"background-color:\s*(#[0-9a-fA-F]+)", document).group(1)
                       if re.search(r"background-color:\s*(#[0-9a-fA-F]+)", document) else None)
    pages: list[list[Item]] = [[]]
    items: dict[str, Item] = {}
    page = 0
    image_index = 0

    def add(item: Item) -> None:
        while len(pages) <= item.page:
            pages.append([])
        pages[item.page].append(item)
        items[item.id] = item

    for raw_line in document.splitlines():
        line = raw_line.strip().replace("\r", "")
        page_match = re.search(r'<div id="page(\d+)"', line)
        if page_match:
            page = int(page_match.group(1))
            while len(pages) <= page:
                pages.append([])
            continue

        match = re.search(r'<div id="(SI\d+)" style="([^"]*)">(.*)</div>', line)
        if match:
            item_id, raw_style, inner = match.groups()
            outer = parse_style(raw_style)
            data: dict[str, Any] = {}
            value_match = re.search(r'<div id="(SIV\d+)" style="([^"]*)">(.*?)</div>', inner)
            if value_match:
                value_id, value_raw, value = value_match.groups()
                data["value_id"] = value_id
                data["value_style"] = parse_style(value_raw)
                data["value"] = text_style(data["value_style"], value)
            # Bar-enabled SensorItems wrap the text row in nested divs. Match
            # leaf text nodes so the wrappers cannot swallow label/unit markup.
            generic = re.findall(r'<div style="([^"]*)">([^<]*?)</div>', inner)
            for child_raw, child_text in generic:
                child_style = parse_style(child_raw)
                entry = {"style": child_style, "text": text_style(child_style, child_text)}
                if child_style.get("float", "").lower() == "left" and "label" not in data:
                    data["label"] = entry
                elif "right" in child_style or child_style.get("float", "").lower() == "right":
                    data["unit"] = entry
            bar_match = re.search(
                r'<div id="(Bar\d+bg)" style="([^"]*)"><span id="(Bar\d+fg)" style="([^"]*)"></span></div>',
                inner,
            )
            if bar_match:
                bg_id, bg_raw, fg_id, fg_raw = bar_match.groups()
                bg_style, fg_style = parse_style(bg_raw), parse_style(fg_raw)
                data["bar"] = {
                    "id": f"Bar{re.search(r'\d+', bg_id).group(0)}p",
                    "bg_style": bg_style,
                    "fg_style": fg_style,
                    "geometry": geometry(bg_style),
                    "percent": number(fg_style.get("width")),
                    "background": gradients(bg_style.get("background"), "#202020"),
                    "foreground": gradients(fg_style.get("background"), "#00FF00"),
                }
            item = Item(item_id, "sensor", page, geometry(outer), outer, data)
            add(item)
            if data.get("value_id"):
                items[data["value_id"]] = item
            if data.get("bar"):
                items[data["bar"]["id"]] = item
            continue

        match = re.search(r'<span id="(Label\d+)" style="([^"]*)">(.*?)</span>', line)
        if match:
            item_id, raw_style, value = match.groups()
            style = parse_style(raw_style)
            add(Item(item_id, "label", page, geometry(style), style,
                     {"text": text_style(style, value)}))
            continue

        match = re.search(
            r'<span style="([^"]*)"><span id="(Simple\d+)" style="([^"]*)">(.*?)</span></span>', line
        )
        if match:
            outer_raw, item_id, inner_raw, value = match.groups()
            outer, inner = parse_style(outer_raw), parse_style(inner_raw)
            merged = {**outer, **inner}
            add(Item(item_id, "simple", page, geometry(outer), merged,
                     {"text": text_style(merged, value)}))
            continue

        match = re.search(r'<span id="(Simple\d+)" style="([^"]*)">(.*?)</span>', line)
        if match:
            item_id, raw_style, value = match.groups()
            style = parse_style(raw_style)
            add(Item(item_id, "simple", page, geometry(style), style,
                     {"text": text_style(style, value)}))
            continue

        match = re.search(
            r'<canvas id="((?:Gph|Arc)\d+)" width="(\d+)px" height="(\d+)px" style="([^"]*)"></canvas>', line
        )
        if match:
            item_id, width, height, raw_style = match.groups()
            style = parse_style(raw_style)
            geom = geometry(style)
            geom.update(w=int(width), h=int(height))
            kind = "graph" if item_id.startswith("Gph") else "arc"
            add(Item(item_id, kind, page, geom, style, {"history": []}))
            items[item_id + "p"] = items[item_id]
            continue

        match = re.search(r'<div style="([^"]*)">(<img[^>]*src="([^"]+)"[^>]*>)</div>', line)
        if match:
            raw_style, tag, src = match.groups()
            image_index += 1
            style = parse_style(raw_style)
            geom = geometry(style)
            width = re.search(r'\bwidth\s*=\s*["\']?(\d+)', tag, re.IGNORECASE)
            height = re.search(r'\bheight\s*=\s*["\']?(\d+)', tag, re.IGNORECASE)
            if width:
                geom["w"] = int(width.group(1))
            if height:
                geom["h"] = int(height.group(1))
            add(Item(f"Image{image_index}", "image", page, geom, style,
                     {"src": html_module.unescape(src)}))

    for call in re.finditer(r'DrawGraph\((.*?)\);', document):
        values = js_arguments(call.group(1))
        item = items.get(str(values[0]))
        if not item:
            continue
        item.data["params"] = {
            "type": str(values[3]), "step": int(values[4]), "thick": int(values[5]),
            "grid_density": int(values[6]), "min": float(values[7]), "max": float(values[8]),
            "autoscale": int(values[9]) == 1, "base100": int(values[10]) == 1,
            "show_background": int(values[11]) == 1, "background": color(values[12]),
            "show_frame": int(values[13]) == 1, "frame": color(values[14], "#808080"),
            "show_grid": int(values[15]) == 1, "grid": color(values[16], "#404040"),
            "graph": color(values[17], "#FFFFFF"), "show_scale": int(values[18]) == 1,
            "font_color": color(values[20], "#FFFFFF"), "font_size": font_pixels(values[21], 8),
            "font_style": str(values[22]), "font_weight": str(values[24]),
            "right_align": int(values[25]) == 1,
        }
        suffix = re.search(r"\d+", item.id).group(0)
        offset = re.search(rf"var gphgridofs{suffix}\s*=\s*(-?\d+)", document)
        maximum = re.search(rf"gpharray{suffix}\.length\s*>\s*(\d+)", document)
        item.data["grid_offset"] = int(offset.group(1)) if offset else 0
        item.data["max_points"] = int(maximum.group(1)) if maximum else 49

    for call in re.finditer(r'DrawArcGauge\((.*?)\);', document):
        values = js_arguments(call.group(1))
        item = items.get(str(values[0]))
        if not item:
            continue
        item.data["params"] = {
            "thickness": int(values[1]), "start": float(values[2]),
            "fill": int(values[6]) == 1, "fill_color": color(values[7]),
            "show_text": int(values[8]) == 1, "font_color": color(values[11], "#FFFFFF"),
            "font_size": font_pixels(values[12], 10),
            "font_style": str(values[13]), "font_weight": str(values[15]),
        }
        item.data.update(percent=0, display_text="0", background_color="#202020", active_color="#00FF00")

    while len(pages) > 1 and not pages[-1]:
        pages.pop()
    return Layout(background, pages, items, source_base, source_dir)


def parse_sse(payload: str) -> tuple[int | None, list[dict[str, Any]]]:
    page: int | None = None
    updates: list[dict[str, Any]] = []
    for entry in payload.split("{|}"):
        entry = entry.strip()
        if not entry:
            continue
        page_match = re.fullmatch(r"Page(\d+)", entry)
        if page_match:
            page = int(page_match.group(1))
            continue
        fields = entry.split("|")
        item_id = fields[0]
        if re.fullmatch(r"(?:SIV|Simple)\d+", item_id):
            updates.append({"id": item_id, "kind": "text", "text": html_module.unescape(fields[1] if len(fields) > 1 else "")})
        elif re.fullmatch(r"Bar\d+p", item_id):
            updates.append({"id": item_id, "kind": "bar", "percent": number(fields[1] if len(fields) > 1 else 0),
                            "background": gradients(fields[2] if len(fields) > 2 else "", "#202020"),
                            "foreground": gradients(fields[3] if len(fields) > 3 else "", "#00FF00")})
        elif re.fullmatch(r"Gph\d+p", item_id):
            updates.append({"id": item_id, "kind": "graph", "value": number(fields[1] if len(fields) > 1 else 0)})
        elif re.fullmatch(r"Arc\d+p", item_id):
            updates.append({"id": item_id, "kind": "arc", "percent": number(fields[1] if len(fields) > 1 else 0),
                            "text": html_module.unescape(fields[2] if len(fields) > 2 else ""),
                            "background_color": color(fields[3] if len(fields) > 3 else "", "#202020"),
                            "active_color": color(fields[4] if len(fields) > 4 else "", "#00FF00")})
    return page, updates


def apply_updates(layout: Layout, updates: list[dict[str, Any]]) -> None:
    for update in updates:
        item = layout.items.get(update["id"])
        if not item:
            continue
        if update["kind"] == "text":
            if item.kind == "sensor":
                item.data["value"]["text"] = update["text"]
            else:
                item.data["text"]["text"] = update["text"]
        elif update["kind"] == "bar" and item.data.get("bar"):
            item.data["bar"].update(percent=update["percent"], background=update["background"],
                                    foreground=update["foreground"])
        elif update["kind"] == "graph":
            item.data["history"].append(update["value"])
        elif update["kind"] == "arc":
            item.data.update(percent=update["percent"], display_text=update["text"],
                             background_color=update["background_color"], active_color=update["active_color"])


_FONTS: dict[tuple[str, int, bool, bool], ImageFont.FreeTypeFont | ImageFont.ImageFont] = {}


def font(family: str, size: int, bold: bool = False, italic: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    key = (family, size, bold, italic)
    if key in _FONTS:
        return _FONTS[key]
    path = ROOT / "package" / "font" / "aida_noto_sans_sc.ttf"
    try:
        value = ImageFont.truetype(str(path), max(1, size))
    except OSError:
        value = ImageFont.load_default()
    _FONTS[key] = value
    return value


def draw_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], width: int, style: dict[str, Any],
              override: str | None = None) -> None:
    value = str(style.get("text", "") if override is None else override)
    fnt = font(style.get("family", "Arial"), int(style.get("size", 10)), style.get("bold", False), style.get("italic", False))
    x, y = xy
    if width > 0 and style.get("align") in {"right", "center"}:
        box = draw.textbbox((0, 0), value, font=fnt)
        text_width = box[2] - box[0]
        x += width - text_width if style["align"] == "right" else (width - text_width) // 2
    stroke = max(1, int(style.get("size", 10)) // 16) if style.get("bold") else 0
    shadow = style.get("shadow")
    if shadow:
        draw.text((x + shadow["x"], y - 1 + shadow["y"]), value, font=fnt,
                  fill=shadow["color"], stroke_width=stroke, stroke_fill=shadow["color"])
    draw.text((x, y - 1), value, font=fnt, fill=style.get("color", "#FFFFFF"),
              stroke_width=stroke, stroke_fill=style.get("color", "#FFFFFF"))
    box = draw.textbbox((x, y - 1), value, font=fnt, stroke_width=stroke)
    thickness = max(1, int(style.get("size", 10)) // 14)
    if style.get("underline"):
        draw.rectangle((box[0], box[3] - thickness, box[2], box[3]), fill=style.get("color", "#FFFFFF"))
    if style.get("strike"):
        mid = (box[1] + box[3]) // 2
        draw.rectangle((box[0], mid, box[2], mid + thickness - 1), fill=style.get("color", "#FFFFFF"))


def vertical_gradient(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], colors: tuple[str, str]) -> None:
    x1, y1, x2, y2 = box
    if x2 < x1 or y2 < y1:
        return
    rgb1 = tuple(int(colors[0][i:i + 2], 16) for i in (1, 3, 5))
    rgb2 = tuple(int(colors[1][i:i + 2], 16) for i in (1, 3, 5))
    height = max(1, y2 - y1)
    for y in range(y1, y2 + 1):
        ratio = (y - y1) / height
        mixed = tuple(round(a + (b - a) * ratio) for a, b in zip(rgb1, rgb2))
        draw.line((x1, y, x2, y), fill=mixed)


def graph_spacing(params: dict) -> int:
    if params["type"] == "HG":
        return max(1, params["thick"]) + max(0, params["step"])
    return max(0, params["step"]) + 1


def graph_range(item: Item, drawable_width: int) -> tuple[float, float]:
    params, history = item.data["params"], item.data["history"]
    low, high = params["min"], params["max"]
    if params["autoscale"] and history:
        visible_count = min(len(history), (max(1, drawable_width) - 1) // graph_spacing(params) + 1)
        visible = history[-visible_count:]
        low, high = min(visible), max(visible)
        if params["base100"]:
            low, high = round(low * .009) * 100, round(high * .011) * 100
        else:
            low, high = round(low * .9), round(high * 1.1)
    if high <= low:
        high = low + max(1, abs(low * .1))
    return low, high


def render_graph(draw: ImageDraw.ImageDraw, item: Item, page_background: str) -> None:
    g, p = item.geometry, item.data.get("params", {})
    if not p:
        return
    x, y, w, h = g["x"], g["y"], g["w"], g["h"]
    draw.rectangle((x, y, x + w - 1, y + h - 1), fill=p["background"] if p["show_background"] else page_background)
    left, top, right, bottom = x, y, x + w - 1, y + h - 1
    drawable_width, drawable_height = w, h
    if p["show_frame"]:
        left, top, right, bottom = left + 1, top + 1, right - 1, bottom - 1
        drawable_width, drawable_height = max(1, w - 2), max(1, h - 2)
    low, high = graph_range(item, drawable_width)
    if p["show_grid"]:
        density = max(2, p["grid_density"])
        offset = item.data.get("grid_offset", 0) % density
        for index in range(drawable_width):
            if index % density == offset:
                draw.line((left + index, top, left + index, bottom), fill=p["grid"])
        for index in range(drawable_height - 1, -1, -1):
            if index % density == 0 and (not p["show_frame"] or index > 0):
                gy = bottom - index
                draw.line((left, gy, right, gy), fill=p["grid"])
    history = item.data["history"][-item.data.get("max_points", 49):]
    spacing = graph_spacing(p)
    points = [(right - offset * spacing,
               bottom - int(max(0, min(1, (history[-1 - offset] - low) / (high - low))) * drawable_height))
              for offset in range(len(history))]
    points = [(px, py) for px, py in points if px >= left]
    if p["type"] == "HG":
        for px, py in points:
            thick = max(1, p["thick"])
            draw.rectangle((max(left, px - (thick - 1)), max(top, py), px, bottom), fill=p["graph"])
    elif points:
        if p["type"] == "AG" and len(points) > 1:
            overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            area = ImageDraw.Draw(overlay)
            area.polygon(points + [(points[-1][0], bottom), (points[0][0], bottom)], fill=(*tuple(int(p["graph"][i:i + 2], 16) for i in (1, 3, 5)), 84))
            draw._image.alpha_composite(overlay)
        if len(points) > 1:
            draw.line(points, fill=p["graph"], width=max(1, p["thick"]), joint="curve")
    if p["show_scale"]:
        style = {"family": "AIDA Noto Sans SC", "size": p["font_size"],
                 "color": p["font_color"], "align": "left" if p["right_align"] else "right",
                 "bold": "bold" in p.get("font_weight", "").lower(),
                 "italic": "italic" in p.get("font_style", "").lower()}
        high_text, low_text = str(round(high)), str(round(low))
        fnt = font(style["family"], style["size"], style["bold"], style["italic"])
        high_width = max(1, round(draw.textlength(high_text, font=fnt)))
        low_width = max(1, round(draw.textlength(low_text, font=fnt)))
        high_x = right - high_width if p["right_align"] else left + 1
        low_x = right - low_width if p["right_align"] else left + 1
        draw_text(draw, (high_x, top + 1), high_width, style, high_text)
        draw_text(draw, (low_x, max(top, bottom - round(p["font_size"] * 1.52) + 1)), low_width, style, low_text)
    if p["show_frame"]:
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline=p["frame"])


def render_arc(draw: ImageDraw.ImageDraw, item: Item, page_background: str) -> None:
    g, p = item.geometry, item.data.get("params", {})
    if not p:
        return
    x, y, w, h = g["x"], g["y"], g["w"], g["h"]
    draw.rectangle((x, y, x + w - 1, y + h - 1), fill=page_background)
    value = str(item.data.get("display_text", ""))
    if not value:
        return
    thickness = max(1, min(p["thickness"], w // 2))
    cx, cy = x + w / 2, y + h / 2
    radius = max(.5, (w - thickness) / 2)
    box = (round(cx - radius), round(cy - radius), round(cx + radius), round(cy + radius))
    if p["fill"]:
        fill_radius = max(0, w / 2 - thickness / 2)
        draw.ellipse((round(cx - fill_radius), round(cy - fill_radius),
                      round(cx + fill_radius), round(cy + fill_radius)), fill=p["fill_color"])
    start = p["start"]
    span = max(0, min(100, item.data.get("percent", 0))) * 3.6
    if span <= 0:
        draw.arc(box, 0, 360, fill=item.data.get("background_color", "#202020"), width=thickness)
    elif span < 360:
        draw.arc(box, start + span - 90, start + 360 - 90,
                 fill=item.data.get("background_color", "#202020"), width=thickness)
    if span > 0:
        draw.arc(box, start - 90, start + span - 90,
                 fill=item.data.get("active_color", "#00FF00"), width=thickness)
    if p["show_text"]:
        style = {"family": "AIDA Noto Sans SC", "size": p["font_size"],
                 "color": p["font_color"], "align": "center",
                 "bold": "bold" in p.get("font_weight", "").lower(),
                 "italic": "italic" in p.get("font_style", "").lower()}
        draw_text(draw, (x, y + max(0, (h - p["font_size"]) // 2)), w, style, value)


def load_resource(layout: Layout, src: str) -> Image.Image | None:
    try:
        if layout.source_base:
            with urllib.request.urlopen(urllib.parse.urljoin(layout.source_base.rstrip("/") + "/", src), timeout=3) as response:
                return Image.open(io.BytesIO(response.read())).convert("RGBA")
        if layout.source_dir:
            path = layout.source_dir / urllib.parse.unquote(src)
            if path.exists():
                with Image.open(path) as image:
                    image.seek(0)
                    return image.convert("RGBA")
    except Exception:
        return None
    return None


def render_page(layout: Layout, page_index: int) -> Image.Image:
    image = Image.new("RGBA", (W, H), layout.background)
    draw = ImageDraw.Draw(image)
    for item in layout.pages[page_index]:
        g = item.geometry
        if item.kind in {"label", "simple"}:
            draw_text(draw, (g["x"], g["y"]), g["w"] or W - g["x"], item.data["text"])
        elif item.kind == "sensor":
            width = g["w"] or W - g["x"]
            bar = item.data.get("bar")
            if bar:
                bg = bar["geometry"]
                bx, by = g["x"] + bg["x"], g["y"] + bg["y"]
                bw, bh = bg["w"] or width, bg["h"] or 4
                vertical_gradient(draw, (bx, by, bx + bw - 1, by + bh - 1), bar["background"])
                fill_width = round(bw * max(0, min(100, bar["percent"])) / 100)
                if fill_width:
                    vertical_gradient(draw, (bx, by, bx + fill_width - 1, by + bh - 1), bar["foreground"])
            if item.data.get("label"):
                draw_text(draw, (g["x"] + integer(item.data["label"]["style"].get("left")), g["y"]),
                          width, item.data["label"]["text"])
            unit_x = g["x"] + width
            if item.data.get("unit"):
                unit_style = item.data["unit"]["style"]
                unit = dict(item.data["unit"]["text"])
                unit_font = font(unit.get("family", "Arial"), int(unit.get("size", 10)),
                                 unit.get("bold", False), unit.get("italic", False))
                unit_box = draw.textbbox((0, 0), unit.get("text", ""), font=unit_font)
                unit_width = integer(unit_style.get("width")) or max(1, unit_box[2] - unit_box[0] + 3)
                unit_x = g["x"] + width - integer(unit_style.get("right")) - unit_width
                draw_text(draw, (unit_x, g["y"]), unit_width, unit)
            if item.data.get("value"):
                value_style = item.data["value_style"]
                value = item.data["value"]
                value_font = font(value.get("family", "Arial"), int(value.get("size", 10)),
                                  value.get("bold", False), value.get("italic", False))
                value_box = draw.textbbox((0, 0), value.get("text", ""), font=value_font)
                value_width = max(1, value_box[2] - value_box[0] + 3)
                if "left" in value_style:
                    value_x = g["x"] + integer(value_style.get("left"))
                elif "right" in value_style:
                    value_x = g["x"] + width - integer(value_style.get("right")) - value_width
                elif value_style.get("float", "").lower() == "right":
                    value_x = unit_x - value_width
                else:
                    value_x = g["x"]
                draw_text(draw, (value_x, g["y"]), value_width, value)
        elif item.kind == "graph":
            render_graph(draw, item, layout.background)
        elif item.kind == "arc":
            render_arc(draw, item, layout.background)
        elif item.kind == "image":
            resource = load_resource(layout, item.data["src"])
            if resource:
                target_width, target_height = g["w"], g["h"]
                if target_width > 0 or target_height > 0:
                    if target_width <= 0:
                        target_width = max(1, round(resource.width * target_height / resource.height))
                    if target_height <= 0:
                        target_height = max(1, round(resource.height * target_width / resource.width))
                    resource = resource.resize((target_width, target_height), Image.Resampling.LANCZOS)
                image.alpha_composite(resource, (g["x"], g["y"]))
            else:
                draw.rectangle((g["x"], g["y"], g["x"] + 15, g["y"] + 15), outline="#FF00FF")
                draw.line((g["x"], g["y"], g["x"] + 15, g["y"] + 15), fill="#FF00FF")
                draw.line((g["x"] + 15, g["y"], g["x"], g["y"] + 15), fill="#FF00FF")
    return image


def demo_updates(layout: Layout) -> None:
    payload = "Page0{|}SIV3|42{|}Bar3p|42|#202020,#151515|#00FF00,#00AA00{|}Arc7p|42|42|#202020|#00FF00{|}Simple11|CPU Temp 48°C{|}"
    _, updates = parse_sse(payload)
    apply_updates(layout, updates)
    for item in {id(value): value for key, value in layout.items.items() if key.startswith("Gph")}.values():
        phase = integer(re.search(r"\d+", item.id).group(0)) * .7
        item.data["history"] = [max(0, min(100, 48 + 31 * math.sin(index / 5 + phase) + 9 * math.sin(index / 2.3)))
                                for index in range(item.data.get("max_points", 49))]


def fetch_live(base: str, layout_url: str | None = None, stream_url: str | None = None) -> tuple[str, str | None]:
    base = base.rstrip("/")
    request = urllib.request.Request(layout_url or base + "/", headers={"Accept-Encoding": "identity", "Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=5) as response:
        document = response.read().decode("utf-8", errors="replace")
    payload = None
    stream = urllib.request.Request(stream_url or base + "/sse", headers={"Accept": "text/event-stream", "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(stream, timeout=5) as response:
            for _ in range(200):
                line = response.readline().decode("utf-8", errors="replace").strip()
                if line.startswith("data:"):
                    payload = line[5:].strip()
                    if payload:
                        break
    except Exception as error:
        print(f"warning: SSE sample unavailable ({error}); using layout defaults")
    return document, payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--aida", help="RemoteSensor base URL, e.g. http://192.168.0.232:9999")
    source.add_argument("--device", help="HoloCubic base URL; reads its AIDA Monitor WebUI state")
    source.add_argument("--layout", type=Path, help="local RemoteSensor HTML file")
    parser.add_argument("--output", type=Path, default=ROOT / "art" / "local-previews")
    args = parser.parse_args()

    if args.device:
        state_url = args.device.rstrip("/") + "/aida_monitor/api/state"
        with urllib.request.urlopen(state_url, timeout=5) as response:
            state = json.load(response)
        layout_url = str(state["layout_url"])
        stream_url = str(state["stream_url"])
        parsed = urllib.parse.urlsplit(layout_url)
        aida_base = f"{parsed.scheme}://{parsed.netloc}"
        document, payload = fetch_live(aida_base, layout_url, stream_url)
        layout = parse_layout(document, source_base=aida_base)
        if payload:
            _, updates = parse_sse(payload)
            apply_updates(layout, updates)
        source_name = f"{args.device.rstrip('/')} -> {aida_base}"
    elif args.aida:
        document, payload = fetch_live(args.aida)
        layout = parse_layout(document, source_base=args.aida)
        if payload:
            _, updates = parse_sse(payload)
            apply_updates(layout, updates)
        source_name = args.aida
    else:
        source_path = (args.layout or DEFAULT_LAYOUT).resolve()
        document = source_path.read_text(encoding="utf-8")
        layout = parse_layout(document, source_dir=source_path.parent)
        demo_updates(layout)
        source_name = str(source_path)

    args.output.mkdir(parents=True, exist_ok=True)
    pages: list[Image.Image] = []
    for index in range(len(layout.pages)):
        image = render_page(layout, index)
        image.convert("RGB").save(args.output / f"page-{index + 1}.png", optimize=True)
        pages.append(image)

    gap, title_height = 8, 28
    overview = Image.new("RGB", (W * len(pages) + gap * max(0, len(pages) - 1), H + title_height), "#080B10")
    overview_draw = ImageDraw.Draw(overview)
    for index, image in enumerate(pages):
        x = index * (W + gap)
        overview.paste(image.convert("RGB"), (x, title_height))
        overview_draw.text((x + 6, 6), f"PAGE {index + 1}", font=font("Consolas", 12, bold=True), fill="#49B6FF")
    overview.save(args.output / "overview.png", optimize=True)
    print(json.dumps({"output": str(args.output.resolve()), "pages": len(pages), "source": source_name}, ensure_ascii=False))


if __name__ == "__main__":
    main()
