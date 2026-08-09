#!/usr/bin/env python3
"""Turn Scryfall's set symbols into pixel art.

Stage one of two. This fetches each set's SVG and reduces it to a 16x16 grid of
ink levels; `set-glyphs.js` then builds the actual sprites through the pixel art
engine, so the engine stays the only thing that knows the sprite format.

    python3 tools/set-glyphs.py        # -> tools/set-glyphs.json
    node    tools/set-glyphs.js        # -> library/ + qml/assets/sets/

Reduction is a supersampled render followed by a box downsample, then two
thresholds rather than one. A pure silhouette loses the thin strokes that make
half these symbols recognisable — a second, lighter ink level costs one palette
entry and buys back most of the legibility.

Symbols the reduction mangles are meant to be fixed by hand: they land in the
engine's library as ordinary sprites, so open the editor and redraw one.
"""
import json
import re
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

from PySide6.QtCore import QByteArray, QRectF, Qt
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

HERE = Path(__file__).resolve().parent
APP = HERE.parent
CACHE = HERE / ".set-svg-cache"
OUT = HERE / "set-glyphs.json"

SIZE = 16                 # the sprite grid
SS = 8                    # supersample factor per cell
SOLID = 0.55              # coverage at or above this is full ink
LIGHT = 0.26              # ...and above this is the lighter ink level

# Scryfall asks for a real User-Agent and ~100ms between requests.
HEADERS = {"User-Agent": "MTG-Commander-Deck-Builder/1.0 (pixel art tooling)",
           "Accept": "image/svg+xml,*/*"}
DELAY = 0.1


def icon_name(url):
    """dom.svg?1234 -> dom. Several set codes share one icon file."""
    return re.sub(r"\.svg.*$", "", url.rsplit("/", 1)[-1])


def wanted_icons():
    db = sqlite3.connect(APP / "data" / "cards.db")
    rows = db.execute(
        "SELECT DISTINCT si.icon_svg FROM cards"
        " JOIN set_icons si ON cards.set_code = si.code"
        " WHERE si.icon_svg IS NOT NULL AND si.icon_svg != ''").fetchall()
    db.close()
    # one entry per icon file, not per set code
    return {icon_name(url): url for (url,) in rows}


def fetch(name, url):
    CACHE.mkdir(exist_ok=True)
    cached = CACHE / (name + ".svg")
    if cached.exists():
        return cached.read_bytes()
    request = urllib.request.Request(url, headers=HEADERS)
    data = urllib.request.urlopen(request, timeout=20).read()
    cached.write_bytes(data)
    time.sleep(DELAY)
    return data


def rasterize(svg):
    """Render the SVG, aspect preserved, into a SIZE*SS square."""
    renderer = QSvgRenderer(QByteArray(svg))
    if not renderer.isValid():
        return None
    box = renderer.viewBoxF()
    if box.width() <= 0 or box.height() <= 0:
        return None

    edge = SIZE * SS
    image = QImage(edge, edge, QImage.Format_ARGB32_Premultiplied)
    image.fill(Qt.transparent)
    scale = min(edge / box.width(), edge / box.height())
    w, h = box.width() * scale, box.height() * scale
    painter = QPainter(image)
    painter.setRenderHint(QPainter.Antialiasing)
    renderer.render(painter, QRectF((edge - w) / 2, (edge - h) / 2, w, h))
    painter.end()
    return image


def coverage(image):
    """Mean alpha per cell, 0..1."""
    grid = []
    for gy in range(SIZE):
        row = []
        for gx in range(SIZE):
            total = 0
            for y in range(gy * SS, (gy + 1) * SS):
                for x in range(gx * SS, (gx + 1) * SS):
                    total += image.pixelColor(x, y).alpha()
            row.append(total / (SS * SS * 255))
        grid.append(row)
    return grid


def to_rows(grid):
    """Two ink levels: '#' solid, '+' light, '.' clear.

    A symbol that comes out empty gets progressively lower thresholds — a few
    are drawn as hairlines that no sane threshold would keep.
    """
    for solid, light in ((SOLID, LIGHT), (0.4, 0.16), (0.25, 0.08), (0.12, 0.04)):
        rows = ["".join("#" if c >= solid else "+" if c >= light else "."
                        for c in row) for row in grid]
        if any("#" in r or "+" in r for r in rows):
            return rows
    return None


def main():
    QGuiApplication(sys.argv + ["-platform", "offscreen"])
    icons = wanted_icons()
    print("%d icon files to convert" % len(icons))

    glyphs, failed = {}, []
    for i, (name, url) in enumerate(sorted(icons.items()), 1):
        try:
            image = rasterize(fetch(name, url))
            rows = to_rows(coverage(image)) if image else None
        except Exception as exc:                       # noqa: BLE001
            rows, exc_note = None, exc
            print("  %s: %s" % (name, exc_note), file=sys.stderr)
        if rows is None:
            failed.append(name)
            continue
        glyphs[name] = rows
        if i % 50 == 0:
            print("  %d/%d" % (i, len(icons)))

    OUT.write_text(json.dumps({"size": SIZE, "glyphs": glyphs}, indent=0))
    print("%d glyphs -> %s" % (len(glyphs), OUT))
    if failed:
        print("could not reduce: %s" % ", ".join(failed), file=sys.stderr)


if __name__ == "__main__":
    main()
