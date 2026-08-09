#!/usr/bin/env python3
"""Phase 1 ingest: download Scryfall bulk data and load Commander-legal cards into SQLite.

Usage: python3 ingest.py
Re-run any time to refresh the database (it rebuilds from scratch).
"""
import gzip
import json
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


def get_image_uris(card):
    """Return (normal, art_crop, small) image URLs, handling double-faced cards."""
    uris = card.get("image_uris")
    if not uris and card.get("card_faces"):
        uris = card["card_faces"][0].get("image_uris")
    if not uris:
        return None, None, None
    return uris.get("normal"), uris.get("art_crop"), uris.get("small")


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
            commander_legal INTEGER,
            can_be_commander INTEGER,
            edhrec_rank INTEGER,
            price_usd TEXT,
            image_normal TEXT,
            image_art_crop TEXT,
            image_small TEXT,
            -- the other side of a transform or modal DFC; NULL for the
            -- single-faced majority, which is how the UI knows whether there
            -- is anything to turn over
            image_back_normal TEXT,
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
    for card in cards:
        legality = card.get("legalities", {}).get("commander")
        if legality != "legal":
            continue
        if card.get("layout") in ("token", "emblem", "art_series"):
            continue
        img_normal, img_art, img_small = get_image_uris(card)
        power, toughness = get_pt(card)
        db.execute(
            "INSERT OR IGNORE INTO cards"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
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
                1,
                1 if can_be_commander(card) else 0,
                card.get("edhrec_rank"),
                (card.get("prices") or {}).get("usd"),
                img_normal,
                img_art,
                img_small,
                get_back_image(card),
                card.get("frame"),
                card.get("layout"),
                1 if card.get("full_art") else 0,
            ),
        )
        inserted += 1
    db.commit()

    total = db.execute("SELECT COUNT(*) FROM cards").fetchone()[0]
    commanders = db.execute("SELECT COUNT(*) FROM cards WHERE can_be_commander=1").fetchone()[0]
    with_art = db.execute("SELECT COUNT(*) FROM cards WHERE image_normal IS NOT NULL").fetchone()[0]
    print(f"Done. {total} Commander-legal cards loaded ({commanders} possible commanders, {with_art} with art).")
    db.close()


if __name__ == "__main__":
    main()
