# tools

Where the pixel art in `qml/assets/` comes from. Nothing here runs at
application start — these regenerate the assets, which are committed.

```
pixelfont.js      the 5x7 bitmap face: one glyph table, two consumers
mtg-buttons.js    button / icon / mana-pip sprites  -> qml/assets/*.png
build-font.py     the same glyphs as a TTF          -> qml/assets/OasisPixel.ttf
set-glyphs.py     Scryfall set symbols, reduced     -> tools/set-glyphs.json
set-glyphs.js     ...built into sprites             -> qml/assets/sets{,-hot}/*.png
```

`pixelfont.js` is the single source of truth for the typeface. The button
sprites stamp its glyphs into PNGs; the TTF traces the same glyphs as outlines.
That is why a label on a button and a label next to it are the same letters
rather than two fonts that merely look alike — change a glyph there and both
follow.

## Regenerating

```bash
node tools/mtg-buttons.js         # needs the pixel art engine (see below)
python3 tools/build-font.py       # needs fonttools
python3 tools/set-glyphs.py && node tools/set-glyphs.js
```

`mtg-buttons.js` draws through the pixel art engine in `../_Pixelart`, and
writes its sprites into that engine's `library/` as well as exporting the PNGs
here — so any of them can be opened in the engine's editor and nudged by hand.
Point `PIXELART_ENGINE` elsewhere if the engine moves.

`build-font.py` needs `fonttools`, which is deliberately not in the
application's `requirements.txt`; it is only needed to rebuild the font.

```bash
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools
/tmp/fontenv/bin/python3 tools/build-font.py
```

## Set symbols

`set-glyphs.py` reads the icon URLs already cached in `data/cards.db`, fetches
each SVG once into `tools/.set-svg-cache/`, and reduces it to a 16x16 grid;
`set-glyphs.js` builds those grids into sprites through the engine. Re-run both
after `ingest.py` pulls in a new set.

They are keyed by the SVG's filename, not the set code — several set codes share
one symbol, so the icon file is what actually identifies it. 266 of them at the
time of writing, tagged `set-symbol` so the engine's gallery can filter them
back out.

Reduction uses two ink levels rather than a flat silhouette: a pure threshold
loses the thin strokes that make half these symbols recognisable. Some still
come out as mush — those are meant to be opened in the engine's editor and
redrawn by hand, which is the whole reason they go into the library rather than
straight to PNG. Anything without a sprite falls back to Scryfall's SVG at
runtime, so a missing or deleted glyph degrades rather than breaks.

## Sizing

The face sits on a 10-row em, so one bitmap pixel is `pixelSize / 10` screen
pixels. **Only multiples of 10 stay sharp** — 10 and 20 are what the UI uses,
and they are named `small` / `body` / `title` in `qml/Retro.js`. A size of 13
or 15 puts glyph rows on half pixels and the type goes muddy.

Sprites follow the same rule from the other direction: `PixelButton` draws its
art at an integer `pixelScale` with nearest-neighbour filtering, and must never
be stretched to fill a layout.
