#!/usr/bin/env python3
"""Draw the application icon, the way tools/ draws every other pixel asset.

The mark is the one the landing page already uses as its favicon — a yellow
card on a navy field, both PICO-8 — with two bands added so it reads as a
Magic card rather than a blank rectangle: the title bar across the top, the
art window under it.

It is authored on a 16x16 grid and scaled by whole multiples with
nearest-neighbour, which is the same rule every sprite in qml/assets follows.
A 256px icon is therefore exactly the 16px one with each pixel 16 across, and
no size in between is ever produced — a pixel mark resampled smoothly stops
being one.

    python3 tools/appicon.py

Writes packaging/mtgdeck.png (256) and packaging/mtgdeck.ico (the four sizes
Windows actually asks for). Both are committed: CI has no Python image stack
and the AppImage needs the PNG at hand.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "packaging"

# PICO-8, the palette the whole app is drawn from — see qml/Retro.js
NAVY = (29, 43, 83)
YELLOW = (255, 236, 39)
INK = (0, 0, 0)

# 16x16. '.' is the field, 'C' the card stock, '#' the ink the card prints:
# the title bar, then the art window, then the text box.
ART = [
    "................",
    "................",
    "...CCCCCCCCCC...",
    "...C########C...",
    "...CCCCCCCCCC...",
    "...C########C...",
    "...C########C...",
    "...C########C...",
    "...C########C...",
    "...CCCCCCCCCC...",
    "...C########C...",
    "...C##CCCCCCC...",
    "...C########C...",
    "...CCCCCCCCCC...",
    "................",
    "................",
]
COLORS = {".": NAVY, "C": YELLOW, "#": INK}


def grid():
    img = Image.new("RGB", (16, 16))
    for y, row in enumerate(ART):
        for x, cell in enumerate(row):
            img.putpixel((x, y), COLORS[cell])
    return img


def main():
    OUT.mkdir(exist_ok=True)
    base = grid()

    png = OUT / "mtgdeck.png"
    base.resize((256, 256), Image.NEAREST).save(png)

    # 16 is the grid itself; the rest are whole multiples of it, so every size
    # in the .ico is the same drawing rather than four different resamplings.
    #
    # Each one is rendered here and handed over finished, largest first.
    # Pillow's ICO writer drops every requested size larger than the image it
    # was called on and resamples the rest smoothly, so saving from the 16px
    # grid yields an .ico containing nothing but a 16px icon — quietly, and it
    # reports success. Starting from 256 and passing the smaller frames in
    # append_images is what gets all four in, each as drawn.
    ico = OUT / "mtgdeck.ico"
    sizes = [256, 48, 32, 16]
    frames = [base.resize((n, n), Image.NEAREST) for n in sizes]
    frames[0].save(ico, append_images=frames[1:],
                   sizes=[(n, n) for n in sizes])

    for f in (png, ico):
        print(f"{f.relative_to(ROOT)} — {f.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
