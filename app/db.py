"""SQLite access for the card database."""
import json
import sqlite3
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "cards.db"
# Your lists and decks live in their own file, ATTACHed as `decks`. cards.db is
# deleted and rebuilt by scripts/ingest.py every refresh; nothing you authored
# may live inside it.
DECKS_PATH = Path(__file__).resolve().parent.parent / "data" / "decks.db"

COLUMNS = [
    "id", "name", "mana_cost", "cmc", "type_line", "oracle_text", "flavor_text",
    "power", "toughness",
    "color_identity", "keywords", "rarity", "artist", "set_name",
    "can_be_commander", "frame",
    "edhrec_rank", "image_normal", "image_art_crop", "image_small",
    "image_back_normal",
]

# the layouts that are two cards printed back to back. Split, flip, adventure
# and saga cards are one image with two halves — there is nothing to turn over.
TWO_FACED_LAYOUTS = ("transform", "modal_dfc", "reversible_card",
                     "double_faced_token")


def connect():
    if not DB_PATH.exists():
        raise SystemExit("data/cards.db not found — run: python3 scripts/ingest.py")
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    db.execute("ATTACH DATABASE ? AS decks", (str(DECKS_PATH),))
    _ensure_card_columns(db)
    _ensure_back_faces(db)
    _ensure_set_icons(db)
    _ensure_deck_tables(db)
    return db


def _ensure_deck_tables(db):
    """Lists and decks are the same thing with a different `kind`: a deck is a
    list that has a commander and gets checked against the Commander rules.
    Promoting a list to a deck is therefore just setting two fields.
    """
    db.executescript("""
        CREATE TABLE IF NOT EXISTS decks.lists (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'list',   -- 'list' | 'deck'
            commander_id TEXT,
            partner_id TEXT,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS decks.idx_list_name
            ON lists(name COLLATE NOCASE);
        CREATE TABLE IF NOT EXISTS decks.list_cards (
            list_id INTEGER NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
            card_id TEXT NOT NULL,
            qty INTEGER NOT NULL DEFAULT 1,
            added_at TEXT NOT NULL,
            label TEXT,
            PRIMARY KEY (list_id, card_id)
        );
    """)
    # a card's label belongs to the entry, not the card: the same card can be
    # "ramp" in one deck and "cut?" in another. Added after the table existed,
    # so decks made before labels still open.
    cols = [r[1] for r in db.execute("PRAGMA decks.table_info(list_cards)")]
    if "label" not in cols:
        db.execute("ALTER TABLE decks.list_cards ADD COLUMN label TEXT")
    db.execute("PRAGMA foreign_keys = ON")
    db.commit()


def _ensure_card_columns(db):
    """Databases built before power/toughness/artist existed are still usable —
    add the columns so queries work. They stay NULL (and so match none of those
    filters) until scripts/ingest.py is re-run.
    """
    cols = [r[1] for r in db.execute("PRAGMA table_info(cards)")]
    for col in ("power", "toughness", "artist", "flavor_text",
                "frame", "layout", "full_art"):
        if col not in cols:
            db.execute(f"ALTER TABLE cards ADD COLUMN {col} TEXT")
    db.commit()


def _ensure_back_faces(db):
    """Give databases built before back faces existed one anyway.

    Scryfall serves the two sides of a card from the same path with one segment
    different — .../normal/front/0/d/<id>.jpg and .../normal/back/0/d/<id>.jpg —
    so the back of a card we already have the front of can be named without
    fetching anything. Only for the layouts that have a back at all: on a split
    or adventure card that URL is a 404.

    A re-run of scripts/ingest.py supersedes this with the URLs Scryfall
    actually published, which is why the column is only filled where it is
    empty, and why this runs once — the moment the column is added.
    """
    cols = [r[1] for r in db.execute("PRAGMA table_info(cards)")]
    if "image_back_normal" in cols:
        return
    db.execute("ALTER TABLE cards ADD COLUMN image_back_normal TEXT")
    marks = ",".join("?" * len(TWO_FACED_LAYOUTS))
    db.execute(
        "UPDATE cards SET image_back_normal ="
        " replace(image_normal, '/front/', '/back/')"
        f" WHERE layout IN ({marks}) AND image_normal LIKE '%/front/%'",
        TWO_FACED_LAYOUTS)
    db.commit()


def _ensure_set_icons(db):
    """Cache Scryfall's set metadata (icon SVG URL, release date); one-time fetch."""
    cols = [r[1] for r in db.execute("PRAGMA table_info(set_icons)")]
    if cols and "released_at" not in cols:
        db.execute("DROP TABLE set_icons")  # old cache schema — rebuild
    db.execute(
        "CREATE TABLE IF NOT EXISTS set_icons"
        " (code TEXT PRIMARY KEY, icon_svg TEXT, released_at TEXT)"
    )
    if db.execute("SELECT COUNT(*) FROM set_icons").fetchone()[0]:
        return
    url = "https://api.scryfall.com/sets"
    try:
        while url:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "OasisMTGDeckbuilder/0.1",
                         "Accept": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                page = json.load(resp)
            db.executemany(
                "INSERT OR REPLACE INTO set_icons VALUES (?,?,?)",
                [(s["code"], s.get("icon_svg_uri"), s.get("released_at"))
                 for s in page["data"]],
            )
            url = page.get("next_page")
        db.commit()
    except OSError:
        db.rollback()  # offline — cards just render without set icons


# sort key -> (nulls-last guard or None, primary sort expression)
SORT_KEYS = {
    "name": (None, "cards.name COLLATE NOCASE"),
    "cmc": (None, "cards.cmc"),
    "edhrec": ("cards.edhrec_rank IS NULL", "cards.edhrec_rank"),
    "set": ("set_icons.released_at IS NULL", "set_icons.released_at"),
    "rarity": (None, "CASE cards.rarity WHEN 'common' THEN 0"
               " WHEN 'uncommon' THEN 1 WHEN 'rare' THEN 2"
               " WHEN 'mythic' THEN 4 ELSE 3 END"),
}


def _order_by(levels):
    """levels: list of (key, descending) pairs, highest priority first."""
    terms = []
    for key, descending in levels:
        guard, expr = SORT_KEYS.get(key, SORT_KEYS["name"])
        if guard:
            terms.append(guard)
        terms.append(expr + (" DESC" if descending else ""))
    if not any(key == "name" for key, _ in levels):
        terms.append("cards.name COLLATE NOCASE")  # stable tiebreak
    return ", ".join(terms)


def _where(filters):
    """Build the WHERE fragment shared by search() and count_matching().

    Kept as one function on purpose: a count that doesn't match the rows it is
    counting is worse than no count at all.

    Returns (sql, params) where sql begins with " WHERE 1=1". Every column it
    touches lives on `cards`, so a caller that only needs a count can skip the
    join to set_icons entirely.
    """
    f = filters or {}
    sql = " WHERE 1=1"
    params = []

    if f.get("text"):
        like = f"%{f['text']}%"
        sql += " AND (name LIKE ? OR type_line LIKE ? OR oracle_text LIKE ?)"
        params += [like, like, like]
    if f.get("name"):
        sql += " AND name LIKE ?"
        params.append(f"%{f['name']}%")
    if f.get("mana"):
        symbols = "".join(c for c in f["mana"].upper() if c not in "{} ")
        sql += " AND REPLACE(REPLACE(mana_cost,'{',''),'}','') LIKE ?"
        params.append(f"%{symbols}%")
    if f.get("type"):
        sql += " AND type_line LIKE ?"
        params.append(f"%{f['type']}%")
    if f.get("subtype"):
        # subtypes live after the em dash in the type line
        sql += (" AND instr(type_line, '—') > 0"
                " AND substr(type_line, instr(type_line, '—')) LIKE ?")
        params.append(f"%{f['subtype']}%")
    if f.get("oracle"):
        sql += " AND oracle_text LIKE ?"
        params.append(f"%{f['oracle']}%")
    if f.get("flavor"):
        sql += " AND flavor_text LIKE ?"
        params.append(f"%{f['flavor']}%")
    if f.get("artist"):
        sql += " AND artist LIKE ?"
        params.append(f"%{f['artist']}%")
    if f.get("set_codes"):
        codes = list(f["set_codes"])
        sql += f" AND set_code IN ({','.join('?' * len(codes))})"
        params += codes
    if f.get("commanders_only"):
        sql += " AND can_be_commander=1"
    if f.get("legal_identity"):
        # The Commander rule: a card may only use colours its commander does.
        # Deliberately separate from the `colors` filter so the two compose —
        # this one asks "could this go in the deck at all", the other is a
        # search you run inside that.
        #
        # A colourless commander arrives as "C" rather than "": it admits only
        # colourless cards, which is a filter, and an empty string would read
        # as no filter at all. "C" holds none of WUBRG, so it falls out here
        # with no special case.
        for colour in "WUBRG":
            if colour not in f["legal_identity"]:
                sql += f" AND color_identity NOT LIKE '%{colour}%'"
    if f.get("rarities"):
        rars = list(f["rarities"])
        sql += f" AND rarity IN ({','.join('?' * len(rars))})"
        params += rars
    # The release year is a property of the set, not of the card, and it is the
    # one filter whose answer isn't already in `cards`. A subquery rather than a
    # join, so the promise above holds and count_matching() still never joins.
    if f.get("year_min") is not None or f.get("year_max") is not None:
        bounds = ""
        if f.get("year_min") is not None:
            bounds += " AND released_at >= ?"
        if f.get("year_max") is not None:
            bounds += " AND released_at <= ?"
        sql += (" AND set_code IN (SELECT code FROM set_icons"
                " WHERE released_at IS NOT NULL" + bounds + ")")
        if f.get("year_min") is not None:
            params.append(f"{int(f['year_min'])}-01-01")
        if f.get("year_max") is not None:
            params.append(f"{int(f['year_max'])}-12-31")

    if f.get("cmc_min") is not None:
        sql += " AND cmc >= ?"
        params.append(f["cmc_min"])
    if f.get("cmc_max") is not None:
        sql += " AND cmc <= ?"
        params.append(f["cmc_max"])

    # Power/toughness are printed text: NULL on non-creatures and non-numeric
    # on the likes of "*" or "*+1". The GLOB guard keeps those out of the
    # comparison rather than letting CAST silently turn them into 0. A leading
    # minus is allowed — Spinal Parasite and Char-Rumbler really are -1 power.
    for key, col, op in (("power_min", "power", ">="),
                         ("power_max", "power", "<="),
                         ("toughness_min", "toughness", ">="),
                         ("toughness_max", "toughness", "<=")):
        if f.get(key) is not None:
            sql += (f" AND ({col} GLOB '[0-9]*' OR {col} GLOB '-[0-9]*')"
                    f" AND CAST({col} AS INTEGER) {op} ?")
            params.append(f[key])

    if f.get("colorless"):
        sql += " AND color_identity = ''"
    elif f.get("colors"):
        chosen = f["colors"]
        mode = f.get("color_mode", "within")
        if mode == "within":
            for c in "WUBRG":
                if c not in chosen:
                    sql += f" AND color_identity NOT LIKE '%{c}%'"
        else:  # exact / includes
            for c in chosen:
                sql += " AND color_identity LIKE ?"
                params.append(f"%{c}%")
            if mode == "exact":
                sql += " AND length(color_identity) = ?"
                params.append(len(chosen))

    return sql, params


def search(db, filters=None, sort="name", descending=False, sort_levels=None,
           limit=None, offset=0):
    """Search cards. `filters` is a dict; recognized keys:

    text        substring across name + type line + rules text
    name        substring of the card name
    mana        mana cost symbols, braces optional ("2GG" matches "{2}{G}{G}")
    type        substring of the type line (supertypes/types)
    subtype     substring of the part after the em dash in the type line
    oracle      substring of the rules text
    flavor      substring of the flavor text (the italic line below the rules)
    artist      substring of the illustrator credit
    set_codes   list of set codes to include (empty/absent = all sets)
    colors      color letters, e.g. "WUG"; combined with color_mode
    color_mode  "within" (identity fits in colors — the Commander rule),
                "exact" (identity is exactly these colors),
                "includes" (identity contains all these colors)
    colorless   True = only colorless-identity cards (overrides colors)
    commanders_only  True = only cards that can be your commander
    rarities    list of rarities to include
    cmc_min / cmc_max  mana value bounds
    year_min / year_max  release year of the card's set
    power_min / power_max          power bounds (creatures only)
    toughness_min / toughness_max  toughness bounds (creatures only)

    `limit`/`offset` page the result. Building the row dicts costs about as
    much as the query itself, so a caller that only shows a screenful should
    ask for a screenful — see CardModel, which pages as you scroll.
    """
    where, params = _where(filters)
    cols = ",".join(f"cards.{c}" for c in COLUMNS)
    sql = (f"SELECT {cols}, set_icons.icon_svg AS set_icon FROM cards"
           " LEFT JOIN set_icons ON cards.set_code = set_icons.code"
           + where
           + " ORDER BY " + _order_by(sort_levels or [(sort, descending)]))
    if limit is not None:
        sql += " LIMIT ? OFFSET ?"
        params = params + [limit, offset]
    return [dict(r) for r in db.execute(sql, params)]


def count_matching(db, filters=None):
    """How many cards the filters match, without materialising any of them.

    Free next to search(): no join, no row objects, and SQLite counts straight
    off the scan.
    """
    where, params = _where(filters)
    return db.execute("SELECT COUNT(*) FROM cards" + where, params).fetchone()[0]


def preview_card(db, filters=None):
    """One card the filters actually match — the face the filter form wears.
    None when nothing matches.

    Picked to be recognizable (EDHREC rank is a fair proxy for "you have seen
    this card before") and, where the filters leave room for it, to have power
    and toughness: the form's regions are measured off a creature frame, so a
    card that fills every one of them reads best under them. The bonus is small
    enough that filters with no well-known creature in them still get their most
    familiar card rather than an obscure creature that happens to qualify.

    Ordinary layouts first, and no full-art printings: the form knows where the
    regions sit in each of Magic's four frames (see qml/CardFrames.js), but a
    full-art land or a split card has no text box in any of them. Those still
    turn up when the filters leave nothing else, which is the honest answer.

    One row, so this costs about what count_matching() does — both scan.
    """
    where, params = _where(filters)
    cols = ",".join(f"cards.{c}" for c in COLUMNS)
    row = db.execute(
        f"SELECT {cols}, set_icons.icon_svg AS set_icon FROM cards"
        " LEFT JOIN set_icons ON cards.set_code = set_icons.code"
        + where
        + " ORDER BY COALESCE(cards.layout,'normal') != 'normal',"
          " COALESCE(cards.full_art,0),"
          " cards.edhrec_rank IS NULL,"
          " cards.edhrec_rank + CASE WHEN cards.power IS NULL THEN 300 ELSE 0 END,"
          " cards.name COLLATE NOCASE LIMIT 1",
        params).fetchone()
    return dict(row) if row else None


def list_artists(db):
    """Every illustrator in the card pool, A–Z. Empty until ingest stores artists."""
    return [r[0] for r in db.execute(
        "SELECT DISTINCT artist FROM cards WHERE artist IS NOT NULL AND artist != ''"
        " ORDER BY artist COLLATE NOCASE"
    )]


def _type_words(db, before_dash):
    """The vocabulary of the type line, split into single words.

    Done in Python rather than SQL because a type line holds several words at
    once — "Legendary Artifact Creature — Golem" is five — while both filters
    match one word at a time. Split cards carry two faces on one line, so each
    side of the // is read separately.
    """
    words = set()
    for (line,) in db.execute(
            "SELECT DISTINCT type_line FROM cards"
            " WHERE type_line IS NOT NULL AND type_line != ''"):
        for face in line.split("//"):
            head, dash, tail = face.partition("—")
            words.update((head if before_dash else tail if dash else "").split())
    return sorted(words, key=str.casefold)


def list_types(db):
    """Card types and supertypes in the pool — the words before the em dash."""
    return _type_words(db, True)


def list_subtypes(db):
    """Subtypes in the pool — the words after the em dash."""
    return _type_words(db, False)


def year_bounds(db):
    """First and last release year in the card pool — the ends of the year
    filter's range. Falls back to a span wide enough to hold Magic's whole
    history if the set dates were never fetched (offline on first run), so the
    control still works rather than collapsing to a single year.
    """
    row = db.execute(
        "SELECT MIN(released_at), MAX(released_at) FROM set_icons"
        " WHERE released_at IS NOT NULL"
        " AND code IN (SELECT set_code FROM cards)").fetchone()
    if not row or not row[0]:
        return [1993, datetime.now(timezone.utc).year + 1]
    return [int(row[0][:4]), int(row[1][:4])]


def list_sets(db):
    """All sets present in the card pool, newest release first."""
    return [dict(r) for r in db.execute(
        "SELECT DISTINCT cards.set_code AS code, cards.set_name AS name,"
        " set_icons.released_at AS released, set_icons.icon_svg AS icon"
        " FROM cards LEFT JOIN set_icons ON cards.set_code = set_icons.code"
        " ORDER BY set_icons.released_at IS NULL, set_icons.released_at DESC,"
        " cards.set_name COLLATE NOCASE"
    )]


# ---------------------------------------------------------------------------
# Lists and decks
# ---------------------------------------------------------------------------

def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _touch(db, list_id):
    db.execute("UPDATE decks.lists SET updated_at=? WHERE id=?", (_now(), list_id))


def list_lists(db):
    """Every list you've made, with its card count and commander name."""
    return [dict(r) for r in db.execute(
        "SELECT l.id, l.name, l.kind, l.commander_id, l.notes, l.updated_at,"
        " c.name AS commander_name, c.color_identity AS commander_identity,"
        " c.image_art_crop AS commander_art,"
        " (SELECT COALESCE(SUM(qty),0) FROM decks.list_cards WHERE list_id=l.id)"
        "   AS card_count"
        " FROM decks.lists l LEFT JOIN cards c ON c.id = l.commander_id"
        " ORDER BY l.name COLLATE NOCASE"
    )]


def create_list(db, name, kind="list"):
    """Make a new list. Returns its id, or None if the name is taken."""
    name = (name or "").strip()
    if not name:
        return None
    now = _now()
    try:
        cur = db.execute(
            "INSERT INTO decks.lists (name, kind, created_at, updated_at)"
            " VALUES (?,?,?,?)", (name, kind, now, now))
    except sqlite3.IntegrityError:
        return None          # duplicate name — the caller reports it
    db.commit()
    return cur.lastrowid


def rename_list(db, list_id, name):
    name = (name or "").strip()
    if not name:
        return False
    try:
        db.execute("UPDATE decks.lists SET name=?, updated_at=? WHERE id=?",
                   (name, _now(), list_id))
    except sqlite3.IntegrityError:
        return False
    db.commit()
    return True


def delete_list(db, list_id):
    # explicit, rather than leaning on ON DELETE CASCADE — foreign keys are a
    # per-connection pragma and this must hold whoever opened the database
    db.execute("DELETE FROM decks.list_cards WHERE list_id=?", (list_id,))
    db.execute("DELETE FROM decks.lists WHERE id=?", (list_id,))
    db.commit()


def duplicate_list(db, list_id, name):
    new_id = create_list(db, name, kind=get_list(db, list_id)["kind"])
    if new_id is None:
        return None
    db.execute(
        "INSERT INTO decks.list_cards (list_id, card_id, qty, added_at, label)"
        " SELECT ?, card_id, qty, ?, label FROM decks.list_cards WHERE list_id=?",
        (new_id, _now(), list_id))
    db.execute("UPDATE decks.lists SET commander_id="
               "(SELECT commander_id FROM decks.lists WHERE id=?) WHERE id=?",
               (list_id, new_id))
    db.commit()
    return new_id


def get_list(db, list_id):
    row = db.execute(
        "SELECT l.*, c.name AS commander_name,"
        " c.color_identity AS commander_identity"
        " FROM decks.lists l LEFT JOIN cards c ON c.id = l.commander_id"
        " WHERE l.id=?", (list_id,)).fetchone()
    return dict(row) if row else None


def set_list_kind(db, list_id, kind):
    db.execute("UPDATE decks.lists SET kind=?, updated_at=? WHERE id=?",
               (kind, _now(), list_id))
    db.commit()


def set_commander(db, list_id, card_id):
    """Name the deck's commander. Passing None clears it. The commander is kept
    in the card list too, so counts and exports include it without special-casing.
    """
    old = db.execute("SELECT commander_id FROM decks.lists WHERE id=?",
                     (list_id,)).fetchone()
    db.execute("UPDATE decks.lists SET commander_id=?, kind='deck', updated_at=?"
               " WHERE id=?", (card_id, _now(), list_id))
    if old and old["commander_id"] and old["commander_id"] != card_id:
        db.execute("DELETE FROM decks.list_cards WHERE list_id=? AND card_id=?",
                   (list_id, old["commander_id"]))
    if card_id:
        db.execute(
            "INSERT INTO decks.list_cards (list_id, card_id, qty, added_at)"
            " VALUES (?,?,1,?) ON CONFLICT(list_id, card_id) DO NOTHING",
            (list_id, card_id, _now()))
    db.commit()


def add_card(db, list_id, card_id, qty=1):
    """Add a copy. Returns the new quantity."""
    db.execute(
        "INSERT INTO decks.list_cards (list_id, card_id, qty, added_at)"
        " VALUES (?,?,?,?)"
        " ON CONFLICT(list_id, card_id) DO UPDATE SET qty = qty + excluded.qty",
        (list_id, card_id, qty, _now()))
    _touch(db, list_id)
    db.commit()
    return db.execute("SELECT qty FROM decks.list_cards WHERE list_id=? AND card_id=?",
                      (list_id, card_id)).fetchone()["qty"]


def add_cards(db, list_id, pairs):
    """Add many cards in one transaction. `pairs` is [(card_id, qty), ...].

    add_card() commits per call, which is fine for a click and wrong for an
    import: a hundred-card deck would be a hundred commits.
    """
    pairs = list(pairs)
    if not pairs:
        return 0
    now = _now()
    db.executemany(
        "INSERT INTO decks.list_cards (list_id, card_id, qty, added_at)"
        " VALUES (?,?,?,?)"
        " ON CONFLICT(list_id, card_id) DO UPDATE SET qty = qty + excluded.qty",
        [(list_id, card_id, qty, now) for card_id, qty in pairs])
    _touch(db, list_id)
    db.commit()
    return len(pairs)


def set_card_qty(db, list_id, card_id, qty):
    if qty <= 0:
        return remove_card(db, list_id, card_id)
    db.execute("UPDATE decks.list_cards SET qty=? WHERE list_id=? AND card_id=?",
               (qty, list_id, card_id))
    _touch(db, list_id)
    db.commit()
    return qty


def set_card_label(db, list_id, card_id, label):
    """Tag one entry with a note of the user's own — "ramp", "cut?", "combo".

    An empty label clears it rather than storing a blank, so the row goes back
    to showing nothing at all.
    """
    label = (label or "").strip()
    db.execute("UPDATE decks.list_cards SET label=? WHERE list_id=? AND card_id=?",
               (label or None, list_id, card_id))
    _touch(db, list_id)
    db.commit()
    return label


def card_label(db, list_id, card_id):
    row = db.execute("SELECT label FROM decks.list_cards"
                     " WHERE list_id=? AND card_id=?",
                     (list_id, card_id)).fetchone()
    return (row["label"] or "") if row else ""


def remove_card(db, list_id, card_id):
    db.execute("DELETE FROM decks.list_cards WHERE list_id=? AND card_id=?",
               (list_id, card_id))
    # a removed commander is no longer the commander
    db.execute("UPDATE decks.lists SET commander_id=NULL"
               " WHERE id=? AND commander_id=?", (list_id, card_id))
    _touch(db, list_id)
    db.commit()
    return 0


def list_contents(db, list_id, sort="name", descending=False, sort_levels=None):
    """The cards in a list, as full card rows plus `qty` and `is_commander`."""
    cols = ",".join(f"cards.{c}" for c in COLUMNS)
    sql = (f"SELECT {cols}, set_icons.icon_svg AS set_icon, lc.qty AS qty,"
           " lc.label AS label,"
           " (cards.id = (SELECT commander_id FROM decks.lists WHERE id=?))"
           "   AS is_commander"
           " FROM decks.list_cards lc JOIN cards ON cards.id = lc.card_id"
           " LEFT JOIN set_icons ON cards.set_code = set_icons.code"
           " WHERE lc.list_id=?"
           " ORDER BY is_commander DESC, "
           + _order_by(sort_levels or [(sort, descending)]))
    return [dict(r) for r in db.execute(sql, (list_id, list_id))]


def card_membership(db, card_id):
    """Which lists a card is already in — drives the checkmarks in the menu."""
    return [r[0] for r in db.execute(
        "SELECT list_id FROM decks.list_cards WHERE card_id=?", (card_id,))]


def cards_in_list(db, list_id):
    return {r[0]: r[1] for r in db.execute(
        "SELECT card_id, qty FROM decks.list_cards WHERE list_id=?", (list_id,))}
