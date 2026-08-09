"""Reading and writing deck lists in the formats the deck sites use.

Import is the awkward half. There is no standard: Moxfield, Archidekt, MTGO,
TappedOut and Deckstats all emit "a card per line" and all disagree about the
details, so the parser strips decorations from the outside in rather than
trying to match one grammar:

    SB: 4x Lightning Bolt (2X2) 117 *F* [Burn]
    ^^^ ^^ ^                ^^^^^ ^^^ ^^^ ^^^^^
    |   |  |                |     |   |   Archidekt category
    |   |  |                |     |   foil marker
    |   |  |                |     collector number
    |   |  set code
    |   quantity
    MTGO sideboard prefix

Everything but the name is optional, and any of it may be absent. What is left
after the decorations come off is the card name.

Name matching is deliberately forgiving, because a name typed by hand rarely
matches the database byte for byte:

  - case is ignored
  - accents fold, so "Adewale" finds "Adéwalé, Breaker of Chains"
  - curly apostrophes fold to straight ones
  - a double-faced card answers to its front face alone, so "Aberrant
    Researcher" finds "Aberrant Researcher // Perfected Form"

No card name in the pool contains a parenthesis, so stripping a trailing
"(SET)" can never eat part of a real name. 826 of them do contain " // ",
which is why comment detection only fires on a leading marker.
"""
import re
import unicodedata

# whole-line section headings, however they are punctuated
SECTIONS = {
    "commander": "commander",
    "commanders": "commander",
    "deck": "main",
    "mainboard": "main",
    "main": "main",
    "maindeck": "main",
    "sideboard": "sideboard",
    "sb": "sideboard",
    "maybeboard": "maybeboard",
    "maybe": "maybeboard",
    "considering": "maybeboard",
    "companion": "companion",
    "tokens": "tokens",
    "token": "tokens",
}

# sections whose cards go into the list; the rest are counted and reported
KEPT_SECTIONS = {"commander", "main", "companion"}

_QTY = re.compile(r"^(\d+)\s*[xX]?\s+(?=\S)")
_SET_SUFFIX = re.compile(r"\s*\(([^)]{1,10})\)(?:\s+([A-Za-z0-9\-★]+))?\s*$")
_TRAILING_TAG = re.compile(r"\s*(?:\*[^*]*\*|\[[^\]]*\]|\^[^^]*\^)\s*$")


def _fold(text):
    """Normalise a name for matching: case, accents, apostrophes, spacing."""
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = (text.replace("’", "'").replace("‘", "'")
                .replace("“", '"').replace("”", '"')
                .replace("—", "-").replace("–", "-"))
    return re.sub(r"\s+", " ", text).strip().lower()


def _front_face(name):
    """The front half of a double-faced name, or None if it isn't one."""
    if " // " not in name:
        return None
    return name.split(" // ", 1)[0].strip()


def parse(text):
    """Parse a pasted deck list.

    Returns (entries, notes). Each entry is a dict:

        {"qty": int, "name": str, "set": str|None, "number": str|None,
         "section": str, "commander": bool, "line": int}

    `notes` collects lines that could not be read at all, so the caller can
    show them rather than silently dropping them.
    """
    entries, notes = [], []
    section = "main"

    for number, raw in enumerate((text or "").splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue

        # A leading marker is a comment; " // " inside a line is a card name.
        marker = None
        if line.startswith("//"):
            marker, line = "//", line[2:].strip()
        elif line.startswith("#") and not line.startswith("#!"):
            marker, line = "#", line[1:].strip()
        if marker and not line:
            continue

        heading = SECTIONS.get(_fold(line).rstrip(":"))
        if heading:
            section = heading
            continue
        if marker:
            continue                       # an ordinary comment

        entry_section = section
        if re.match(r"^sb:\s*", line, re.I):
            line = re.sub(r"^sb:\s*", "", line, flags=re.I)
            entry_section = "sideboard"

        qty = 1
        match = _QTY.match(line)
        if match:
            qty = max(1, int(match.group(1)))
            line = line[match.end():]

        # decorations come off the tail: tags first, then the set/number
        commander = False
        while True:
            tag = _TRAILING_TAG.search(line)
            if not tag:
                break
            if "cmdr" in tag.group(0).lower() or "commander" in tag.group(0).lower():
                commander = True
            line = line[:tag.start()].rstrip()

        set_code = collector = None
        suffix = _SET_SUFFIX.search(line)
        if suffix:
            set_code, collector = suffix.group(1), suffix.group(2)
            line = line[:suffix.start()].rstrip()

        name = line.strip().strip(",").strip()
        if not name:
            notes.append(f"line {number}: couldn't read {raw.strip()!r}")
            continue

        entries.append({
            "qty": qty, "name": name, "set": set_code, "number": collector,
            "section": entry_section,
            "commander": commander or entry_section == "commander",
            "line": number,
        })

    return entries, notes


def build_index(db):
    """Folded name -> card id, including front faces of double-faced cards.

    A front-face alias never displaces a real card of that name: if some card
    is actually called "Aberrant Researcher", it wins.
    """
    index, aliases = {}, {}
    for row in db.execute("SELECT id, name FROM cards"):
        card_id, name = row["id"], row["name"]
        index[_fold(name)] = card_id
        front = _front_face(name)
        if front:
            aliases.setdefault(_fold(front), card_id)
    for key, card_id in aliases.items():
        index.setdefault(key, card_id)
    return index


def resolve(db, entries, index=None):
    """Match parsed entries to cards. Returns (matched, unmatched).

    `matched` is a list of {"card_id", "qty", "commander", "name", "section"};
    entries naming the same card are merged, keeping the largest quantity
    rather than summing, since a list that mentions a card twice means one
    card. A card listed in two sections keeps the one that would be kept — a
    maybeboard mention shouldn't demote a card that is also in the deck.
    """
    index = build_index(db) if index is None else index
    matched, unmatched, seen = [], [], {}

    for entry in entries:
        card_id = index.get(_fold(entry["name"]))
        if card_id is None:
            unmatched.append(entry)
            continue
        if card_id in seen:
            slot = seen[card_id]
            slot["qty"] = max(slot["qty"], entry["qty"])
            slot["commander"] = slot["commander"] or entry["commander"]
            if slot["section"] not in KEPT_SECTIONS:
                slot["section"] = entry["section"]
            continue
        slot = {"card_id": card_id, "qty": entry["qty"],
                "commander": entry["commander"], "name": entry["name"],
                "section": entry["section"]}
        seen[card_id] = slot
        matched.append(slot)

    return matched, unmatched


def export_text(cards, commander_id=None, style="moxfield"):
    """Write a deck list out.

    Three styles, because the sites disagree and there is no way to satisfy
    all of them at once:

    moxfield   "Commander" / "Deck" headings, one "1 Card Name" per line.
               What Moxfield and Archidekt emit, and what they read back.
    plain      Bare "1 Card Name" lines, commander first, no headings at all.
               The lowest common denominator — anything that reads deck lists
               reads this, but nothing learns which card is the commander.
    annotated  Grouped under "Creatures (12)" style headings. For reading,
               not for importing: those headings are not a format any site
               claims to parse.
    """
    from . import deck_rules

    if style == "annotated":
        return deck_rules.export_text(cards, commander_id)

    commander = [c for c in cards if c["id"] == commander_id]
    rest = sorted((c for c in cards if c["id"] != commander_id),
                  key=lambda c: c["name"].lower())

    lines = []
    if style == "moxfield":
        if commander:
            lines += ["Commander"]
            lines += [f"{c['qty']} {c['name']}" for c in commander]
            lines += ["", "Deck"]
        lines += [f"{c['qty']} {c['name']}" for c in rest]
    else:                                   # plain
        lines += [f"{c['qty']} {c['name']}" for c in commander + rest]

    return "\n".join(lines).strip() + "\n"


def deck_name_from(text, fallback="Imported deck"):
    """A name for the list, if the paste announced one.

    Deckstats and a few exporters lead with "//NAME: Something"; otherwise the
    caller's fallback stands.
    """
    for raw in (text or "").splitlines()[:5]:
        line = raw.strip()
        match = re.match(r"^(?://|#)\s*(?:name|deck)\s*:\s*(.+)$", line, re.I)
        if match:
            return match.group(1).strip() or fallback
    return fallback
