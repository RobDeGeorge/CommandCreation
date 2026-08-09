"""Commander deck rules and statistics.

Everything here is a pure function of a list's card rows (as returned by
db.list_contents), so the same code answers "is this deck legal?" for the UI,
for an export, and for anything that comes later.
"""
import re

DECK_SIZE = 100
BASIC_LANDS = {
    "Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes",
    "Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp",
    "Snow-Covered Mountain", "Snow-Covered Forest", "Snow-Covered Wastes",
}
# Shadowborn Apostle, Relentless Rats, Persistent Petitioners, Dragon's Approach…
ANY_NUMBER = "a deck can have any number of cards named"

CURVE_CAP = 7          # the top bucket is "7+"
PIP_COLORS = "WUBRG"
TYPE_ORDER = [
    "Creature", "Planeswalker", "Instant", "Sorcery",
    "Artifact", "Enchantment", "Battle", "Land",
]


def is_basic_land(card):
    return card["name"] in BASIC_LANDS or "Basic" in (card["type_line"] or "")


def unlimited_copies(card):
    return is_basic_land(card) or ANY_NUMBER in (card["oracle_text"] or "").lower()


def color_identity(card):
    return set(card["color_identity"] or "")


def primary_type(card):
    """The one bucket a card counts toward. A card is filed under the first
    type it has in TYPE_ORDER, so an Artifact Creature counts as a creature —
    that is how deck lists are conventionally read.
    """
    line = card["type_line"] or ""
    face = line.split("//")[0]
    for t in TYPE_ORDER:
        if t in face:
            return t
    return "Other"


def mana_pips(mana_cost):
    """Coloured pips in a mana cost, hybrids counting for both halves."""
    counts = dict.fromkeys(PIP_COLORS, 0)
    for symbol in re.findall(r"\{([^}]+)\}", mana_cost or ""):
        for part in symbol.split("/"):
            if part in counts:
                counts[part] += 1
    return counts


def legality(cards, commander_identity, has_commander):
    """Rule violations, as a list of {level, message, card_ids} problems.

    `level` is "error" for anything that makes the deck illegal and "warning"
    for things that are merely not finished (deck under 100 cards, no commander
    chosen yet) — you are mid-build, so those shouldn't read as failures.
    """
    problems = []
    total = sum(c["qty"] for c in cards)

    if not has_commander:
        problems.append({"level": "warning", "message": "No commander chosen",
                         "card_ids": []})
    if total < DECK_SIZE:
        problems.append({
            "level": "warning",
            "message": f"{DECK_SIZE - total} more card"
                       f"{'s' if DECK_SIZE - total != 1 else ''} to go"
                       f" ({total}/{DECK_SIZE})",
            "card_ids": []})
    elif total > DECK_SIZE:
        problems.append({
            "level": "error",
            "message": f"{total - DECK_SIZE} card"
                       f"{'s' if total - DECK_SIZE != 1 else ''} over"
                       f" ({total}/{DECK_SIZE})",
            "card_ids": []})

    dupes = [c for c in cards if c["qty"] > 1 and not unlimited_copies(c)]
    if dupes:
        problems.append({
            "level": "error",
            "message": "Singleton: " + ", ".join(
                f"{c['name']} ×{c['qty']}" for c in dupes[:4])
                + (f" and {len(dupes) - 4} more" if len(dupes) > 4 else ""),
            "card_ids": [c["id"] for c in dupes]})

    if has_commander:
        outside = [c for c in cards
                   if not color_identity(c) <= set(commander_identity or "")]
        if outside:
            pips = "".join(commander_identity or "") or "colourless"
            problems.append({
                "level": "error",
                "message": f"Outside {pips} identity: " + ", ".join(
                    c["name"] for c in outside[:4])
                    + (f" and {len(outside) - 4} more" if len(outside) > 4 else ""),
                "card_ids": [c["id"] for c in outside]})
    return problems


def stats(cards):
    """Curve, type breakdown, pip counts and averages for the whole list."""
    curve = [0] * (CURVE_CAP + 1)
    types = dict.fromkeys(TYPE_ORDER, 0)
    types["Other"] = 0
    pips = dict.fromkeys(PIP_COLORS, 0)
    spell_cmc = spell_count = lands = total = 0

    for card in cards:
        qty = card["qty"]
        total += qty
        kind = primary_type(card)
        types[kind] = types.get(kind, 0) + qty
        for color, n in mana_pips(card["mana_cost"]).items():
            pips[color] += n * qty
        if kind == "Land":
            lands += qty
            continue                      # lands don't belong on a mana curve
        cmc = int(card["cmc"] or 0)
        curve[min(cmc, CURVE_CAP)] += qty
        spell_cmc += cmc * qty
        spell_count += qty

    return {
        "total": total,
        "lands": lands,
        "avgCmc": round(spell_cmc / spell_count, 2) if spell_count else 0.0,
        "curve": [{"cmc": i, "label": f"{i}+" if i == CURVE_CAP else str(i),
                   "count": n} for i, n in enumerate(curve)],
        "curveMax": max(curve) if curve else 0,
        "types": [{"type": t, "count": types[t]} for t in TYPE_ORDER + ["Other"]
                  if types.get(t)],
        "pips": [{"color": c, "count": pips[c]} for c in PIP_COLORS],
        "pipsTotal": sum(pips.values()),
    }


def export_text(cards, commander_id=None):
    """A deck list in the plain "1 Card Name" format every site imports.
    The commander goes in its own section, as Moxfield and Archidekt expect.
    """
    lines = []
    commander = [c for c in cards if c["id"] == commander_id]
    if commander:
        lines += ["Commander", f"1 {commander[0]['name']}", ""]
    rest = [c for c in cards if c["id"] != commander_id]
    for kind in TYPE_ORDER + ["Other"]:
        group = sorted((c for c in rest if primary_type(c) == kind),
                       key=lambda c: c["name"].lower())
        if not group:
            continue
        lines.append(f"{kind}s ({sum(c['qty'] for c in group)})")
        lines += [f"{c['qty']} {c['name']}" for c in group]
        lines.append("")
    return "\n".join(lines).strip() + "\n"
