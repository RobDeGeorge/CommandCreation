#!/usr/bin/env python3
"""MTG Commander deck builder — launch the UI.

Usage: python3 main.py
(First run: python3 scripts/ingest.py to build the card database.)
"""
import os
import sys
from pathlib import Path

from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from app import db
from app.card_model import CardModel
from app.deck_model import DeckStore

ROOT = Path(__file__).resolve().parent


# ---- the UI font -----------------------------------------------------------
# This is the one place the typeface is chosen. Override without editing:
#
#   MTG_FONT=system python3 main.py             the platform's own font
#   MTG_FONT=/path/to/Other.ttf python3 main.py any other font file
#   MTG_FONT_SIZE=20 python3 main.py            bigger
#
# The relative type scale (small / body / title) lives in qml/Retro.js.
DEFAULT_FONT = ROOT / "qml" / "assets" / "PressStart2P-Regular.ttf"
DEFAULT_FONT_SIZE = 8


def use_pixel_font(app):
    """Make the bitmap face the application default.

    Setting it on the QGuiApplication rather than per-control means menus,
    tooltips, dialog titles and every other bit of chrome Qt draws for us pick
    it up too — there is no second place to keep in sync.

    The face is drawn on an 8-row em, so one bitmap pixel is exactly
    pixelSize/8 screen pixels: sizes that are multiples of 8 land on whole
    pixels and anything else renders unevenly. Hinting is off for the same
    reason — the outlines are already on the pixel grid, and a hinter would
    only push them off it.

    Press Start 2P is monospaced at one em per glyph, which is why the sizes
    in qml/Retro.js are two steps smaller than the face it replaced: the same
    label is a third wider here at equal size. It carries ASCII and Latin-1 and
    nothing else — a ✓ or a ⚠ in a string comes out in whatever face Qt falls
    back to, which next to the bitmap glyphs reads as a mistake, so marks like
    those are drawn from the icon sprites instead.
    """
    choice = os.environ.get("MTG_FONT", str(DEFAULT_FONT))
    size = int(os.environ.get("MTG_FONT_SIZE", DEFAULT_FONT_SIZE))
    if choice == "system":
        return

    font_id = QFontDatabase.addApplicationFont(choice)
    families = QFontDatabase.applicationFontFamilies(font_id)
    if not families:
        print("could not load font %r — using the system font" % choice,
              file=sys.stderr)
        return

    font = QFont(families[0])
    font.setPixelSize(size)
    font.setHintingPreference(QFont.PreferNoHinting)
    app.setFont(font)


def main():
    app = QGuiApplication(sys.argv)
    app.setApplicationName("MTG Commander Deck Builder")
    use_pixel_font(app)

    # one connection for both models, so a card added to a list is visible to
    # every query immediately rather than after a commit lands on disk
    connection = db.connect()
    model = CardModel(connection)
    decks = DeckStore(connection)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("cardModel", model)
    engine.rootContext().setContextProperty("deckStore", decks)
    engine.load(ROOT / "qml" / "Main.qml")
    if not engine.rootObjects():
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
