#!/usr/bin/env python3
"""Phase 1 ingest: download Scryfall bulk data and load Commander-legal cards into SQLite.

Usage: python3 ingest.py
Re-run any time to refresh the database (it rebuilds from scratch).
"""
import gzip
import json
import re
import sqlite3
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "cards.db"
BULK_INDEX_URL = "https://api.scryfall.com/bulk-data"
HEADERS = {"User-Agent": "OasisMTGDeckbuilder/0.1", "Accept": "application/json"}


def fetch_json(url):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


IMAGE_URL_RE = re.compile(
    r"^https://cards\.scryfall\.io/\w+/(?:front|back)/[0-9a-f]/[0-9a-f]/"
    r"([0-9a-f-]{36})\.jpg(?:\?(\d+))?$"
)


def get_image_key(card):
    """The one (image_id, timestamp) every image URL for this card is built from.

    Scryfall serves every size and both faces from one shape:

        https://cards.scryfall.io/<size>/<face>/<a>/<b>/<image-id>.jpg?<ts>

    where <a> and <b> are just the first two characters of the image id. So the
    four URLs a card needs are two values arranged four ways, and storing them
    whole meant keeping 31,830 copies of the same prefix — 9 MB of a 29 MB
    database, which the browser build downloads before it can start. Db.cpp
    rebuilds the URLs in SQL, so nothing above the database notices.

    Beware: this id is NOT the `id` column. That one is the oracle_id, which
    names a card; this names one printing's artwork, and they differ.

    Parsed back out of the URL rather than read from card["id"], because the URL
    is what has to be reproduced exactly. If Scryfall ever keys them on
    something else this returns None, and main() reports it instead of the app
    quietly pointing every card at a 404.
    """
    uris = card.get("image_uris")
    if not uris and card.get("card_faces"):
        uris = card["card_faces"][0].get("image_uris")
    if not uris:
        return None, None

    keys = set()
    for size in ("normal", "art_crop", "small"):
        m = IMAGE_URL_RE.match(uris.get(size) or "")
        if not m:
            return None, None
        keys.add(m.groups())
    # All three sizes must agree, or one id cannot stand for all of them.
    if len(keys) != 1:
        return None, None

    image_id, ts = keys.pop()
    return image_id, (int(ts) if ts else None)


def back_shares_image_id(card, image_id):
    """Does the back face hang off the same image id as the front?

    None when there is no back face. The derivation in Db.cpp assumes True for
    every card that has one; this is what would catch it becoming false.
    """
    back = get_back_image(card)
    if not back:
        return None
    m = IMAGE_URL_RE.match(back)
    return bool(m and m.group(1) == image_id)


def get_back_image(card):
    """The far side of a card that has one, or None.

    Only the layouts that are literally two cards printed back to back —
    transform, modal DFCs, reversible printings. Split, flip, adventure and
    saga cards all read as one image and have nothing to turn over.
    """
    if card.get("image_uris"):        # single image: nothing on the back
        return None
    faces = card.get("card_faces") or []
    if len(faces) < 2:
        return None
    return (faces[1].get("image_uris") or {}).get("normal")


def load_set_icons(db):
    """The set symbol and release date for every set, which the card grid draws
    under each card and the year filter reads its bounds from.

    Loaded here rather than left to the app, because this script rebuilds
    cards.db from scratch and this table goes down with it. The desktop app can
    notice that and refetch on the next launch — the browser build cannot, since
    Db::ensureSetIcons() returns early there rather than run a blocking fetch
    Emscripten has no way to service. Filling it in now is what makes a
    WebAssembly build reproducible from this script alone, instead of quietly
    depending on someone having run the desktop app in between.
    """
    db.execute(
        "CREATE TABLE set_icons (code TEXT PRIMARY KEY, icon_svg TEXT, released_at TEXT)"
    )
    url = "https://api.scryfall.com/sets"
    count = 0
    while url:
        page = fetch_json(url)
        for s in page.get("data", []):
            db.execute(
                "INSERT OR REPLACE INTO set_icons VALUES (?,?,?)",
                (s.get("code"), s.get("icon_svg_uri"), s.get("released_at")),
            )
            count += 1
        url = page.get("next_page")
    db.commit()
    return count


def get_pt(card):
    """Return (power, toughness) as printed, handling double-faced cards."""
    if "power" not in card and card.get("card_faces"):
        card = card["card_faces"][0]
    return card.get("power"), card.get("toughness")


def get_flavor(card):
    """The italic line under the rules text. Not every printing has one, and
    double-faced cards carry it per face — take the front's, to match the art
    and the rules text we store."""
    if card.get("flavor_text"):
        return card["flavor_text"]
    faces = card.get("card_faces") or []
    return faces[0].get("flavor_text") if faces else None


def get_artist(card):
    """Illustrator credit; double-faced cards carry it per face."""
    if card.get("artist"):
        return card["artist"]
    faces = card.get("card_faces") or []
    names = [f["artist"] for f in faces if f.get("artist")]
    # both faces by the same hand print as one credit
    return " & ".join(dict.fromkeys(names)) or None


def can_be_commander(card):
    type_line = card.get("type_line", "")
    if "Legendary" in type_line and "Creature" in type_line:
        return True
    return "can be your commander" in card.get("oracle_text", "")


def main():
    print("Fetching bulk data index...")
    index = fetch_json(BULK_INDEX_URL)
    oracle = next(d for d in index["data"] if d["type"] == "oracle_cards")
    size_mb = oracle["compressed_size"] / 1_000_000
    print(f"Downloading Oracle Cards bulk file ({size_mb:.0f} MB compressed)...")
    req = urllib.request.Request(oracle["jsonl_download_uri"], headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        with gzip.open(resp, "rt", encoding="utf-8") as f:
            cards = [json.loads(line) for line in f if line.strip()]
    print(f"Downloaded {len(cards)} card objects.")

    if DB_PATH.exists():
        DB_PATH.unlink()
    db = sqlite3.connect(DB_PATH)
    db.execute("""
        CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            mana_cost TEXT,
            cmc REAL,
            type_line TEXT,
            oracle_text TEXT,
            flavor_text TEXT,
            power TEXT,
            toughness TEXT,
            colors TEXT,
            color_identity TEXT,
            keywords TEXT,
            rarity TEXT,
            artist TEXT,
            set_code TEXT,
            set_name TEXT,
            can_be_commander INTEGER,
            edhrec_rank INTEGER,
            -- The art, as the two values every URL for it is built from rather
            -- than as four near-identical strings; see get_image_key(). Db.cpp
            -- reassembles image_normal, image_art_crop, image_small and
            -- image_back_normal from these, under those same names, so the
            -- models and QML are unaffected.
            image_id TEXT,
            image_ts INTEGER,
            -- whether there is a far side to turn over: transform and modal
            -- DFCs have one, split and adventure cards only look like they do
            has_back INTEGER NOT NULL DEFAULT 0,
            -- which frame this printing was laid out in: "1993", "1997",
            -- "2003", "2015" or "future". The filter panel draws its form
            -- over the card face, and every one of these puts the title bar,
            -- type bar and text box somewhere different.
            frame TEXT,
            layout TEXT,
            full_art INTEGER
        )
    """)
    db.execute("CREATE INDEX idx_name ON cards(name)")
    db.execute("CREATE INDEX idx_identity ON cards(color_identity)")
    db.execute("CREATE INDEX idx_commander ON cards(can_be_commander)")

    inserted = 0
    no_image_key = 0
    back_mismatch = 0
    for card in cards:
        legality = card.get("legalities", {}).get("commander")
        if legality != "legal":
            continue
        if card.get("layout") in ("token", "emblem", "art_series"):
            continue
        image_id, image_ts = get_image_key(card)
        if image_id is None and (card.get("image_uris") or card.get("card_faces")):
            no_image_key += 1
        shares = back_shares_image_id(card, image_id)
        if shares is False:
            back_mismatch += 1
        power, toughness = get_pt(card)
        db.execute(
            "INSERT OR IGNORE INTO cards"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                card["oracle_id"],
                card["name"],
                card.get("mana_cost"),
                card.get("cmc"),
                card.get("type_line"),
                card.get("oracle_text"),
                get_flavor(card),
                power,
                toughness,
                "".join(card.get("colors", [])),
                "".join(card.get("color_identity", [])),
                ",".join(card.get("keywords", [])),
                card.get("rarity"),
                get_artist(card),
                card.get("set"),
                card.get("set_name"),
                1 if can_be_commander(card) else 0,
                card.get("edhrec_rank"),
                image_id,
                image_ts,
                1 if shares else 0,
                card.get("frame"),
                card.get("layout"),
                1 if card.get("full_art") else 0,
            ),
        )
        inserted += 1
    db.commit()

    print("Fetching set symbols...")
    sets = load_set_icons(db)

    # Reclaim the pages the dropped columns used to occupy. Without this the
    # file keeps its old size and the browser build downloads the difference for
    # nothing.
    db.execute("VACUUM")

    total = db.execute("SELECT COUNT(*) FROM cards").fetchone()[0]
    commanders = db.execute("SELECT COUNT(*) FROM cards WHERE can_be_commander=1").fetchone()[0]
    with_art = db.execute("SELECT COUNT(*) FROM cards WHERE image_id IS NOT NULL").fetchone()[0]
    backs = db.execute("SELECT COUNT(*) FROM cards WHERE has_back=1").fetchone()[0]
    print(f"Done. {total} Commander-legal cards loaded "
          f"({commanders} possible commanders, {with_art} with art, {backs} double-faced), "
          f"{sets} set symbols.")
    print(f"      {DB_PATH.stat().st_size / 1e6:.1f} MB")

    # Both of these mean the app would draw missing or wrong art, and neither is
    # visible from inside the app — say so here, where the data comes in.
    if no_image_key:
        print(f"WARNING: {no_image_key} cards had image URLs this script could not read."
              " Their art will be blank; check whether Scryfall changed the URL format.")
    if back_mismatch:
        print(f"WARNING: {back_mismatch} double-faced cards keep their back under a"
              " different image id. Db.cpp assumes the two match, so those backs will"
              " be wrong.")
    db.close()


if __name__ == "__main__":
    main()
