#!/usr/bin/env python3
"""Build OasisPixel.ttf from the same bitmap glyph table the button sprites use.

Every lit pixel becomes a square outline. Runs of lit pixels in a row are merged
into a single rectangle first -- fewer contours, identical rendering, and it
keeps the font small enough to sit in the repo without comment.

The em is 10 rows tall (8 above the baseline, 2 below) and one row is 100 units,
so a `font.pixelSize` that is a multiple of 10 puts one font pixel on an exact
whole number of screen pixels. That is the only way bitmap type stays sharp.
"""
import json
import subprocess
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "qml" / "assets" / "OasisPixel.ttf"

UPM = 1000
PX = 100                       # one bitmap pixel, in font units
ROWS_ABOVE_BASELINE = 7        # rows 0..6 sit on or above the baseline

# read the glyph table out of the JS module, so there is one source of truth
raw = subprocess.run(
    ["node", "-e",
     "const p=require('./pixelfont.js');"
     "process.stdout.write(JSON.stringify("
     "{glyphs:p.GLYPHS, advance:p.ADVANCE, baseline:p.BASELINE_ROW,"
     " ascent:p.ASCENT_ROWS, descent:p.DESCENT_ROWS}))"],
    cwd=HERE, capture_output=True, text=True, check=True).stdout
spec = json.loads(raw)
GLYPHS, ADVANCE = spec["glyphs"], spec["advance"]
ASCENT, DESCENT = spec["ascent"] * PX, spec["descent"] * PX


def runs(row):
    """(start, length) for each run of lit pixels in one row of a glyph."""
    out, x = [], 0
    while x < len(row):
        if row[x] == "#":
            start = x
            while x < len(row) and row[x] == "#":
                x += 1
            out.append((start, x - start))
        else:
            x += 1
    return out


def draw(pen, glyph):
    top = glyph["t"]
    for i, row in enumerate(glyph["r"]):
        r = top + i
        # row r spans from the baseline: row 6 is the row resting on it
        y0 = (ROWS_ABOVE_BASELINE - 1 - r) * PX
        y1 = y0 + PX
        for x0px, length in runs(row):
            x0, x1 = x0px * PX, (x0px + length) * PX
            pen.moveTo((x0, y0))
            pen.lineTo((x1, y0))
            pen.lineTo((x1, y1))
            pen.lineTo((x0, y1))
            pen.closePath()


# ---------------------------------------------------------------- assemble

def glyph_name(ch):
    return "uni%04X" % ord(ch)


order = [".notdef"] + [glyph_name(c) for c in GLYPHS]
cmap = {ord(c): glyph_name(c) for c in GLYPHS}

pens = {}
notdef = TTGlyphPen(None)
# .notdef is a hollow box, so a missing character is obvious rather than blank
for y0, y1, x0, x1 in ((0, 700, 0, 100), (0, 700, 400, 500),
                       (0, 100, 0, 500), (600, 700, 0, 500)):
    notdef.moveTo((x0, y0)); notdef.lineTo((x1, y0))
    notdef.lineTo((x1, y1)); notdef.lineTo((x0, y1)); notdef.closePath()
pens[".notdef"] = notdef.glyph()

for ch, glyph in GLYPHS.items():
    pen = TTGlyphPen(None)
    draw(pen, glyph)
    pens[glyph_name(ch)] = pen.glyph()

advance = ADVANCE * PX
metrics = {name: (advance, 0) for name in order}

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)
fb.setupGlyf(pens)
fb.setupHorizontalMetrics(metrics)
fb.setupHorizontalHeader(ascent=ASCENT, descent=-DESCENT)
fb.setupNameTable({
    "familyName": "Oasis Pixel",
    "styleName": "Regular",
    "psName": "OasisPixel-Regular",
    "version": "1.0",
    "copyright": "Generated from pixelfont.js",
})
fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=-DESCENT, sTypoLineGap=0,
            usWinAscent=ASCENT, usWinDescent=DESCENT,
            sxHeight=5 * PX, sCapHeight=ROWS_ABOVE_BASELINE * PX,
            # bProportion=9 is "monospaced"; the rest is the sans-serif default
            panose=dict(bFamilyType=2, bSerifStyle=11, bWeight=5, bProportion=9,
                        bContrast=2, bStrokeVariation=2, bArmStyle=2,
                        bLetterForm=2, bMidline=2, bXHeight=4))
fb.setupPost(isFixedPitch=1)
fb.save(OUT)

print("%s  (%d glyphs, %.1f KB)" % (OUT, len(order), OUT.stat().st_size / 1024))
