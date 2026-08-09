"""Qt list model exposing card search results to QML.

Filter state lives in a single dict driven through setFilter()/setFilters(),
so any frontend — the QML panel today, an MCP server tomorrow — controls the
search through one uniform API. See db.search() for the recognized keys.
"""
from PySide6.QtCore import (
    QAbstractListModel, QModelIndex, Qt, Property, Signal, Slot, QTimer,
)
from PySide6.QtQml import QJSValue

from . import db

ROLE_NAMES = [
    "cardId",
    "name", "manaCost", "cmc", "typeLine", "oracleText", "flavorText",
    "colorIdentity",
    "power", "toughness",
    "rarity", "artist", "setName", "setIcon", "canBeCommander", "edhrecRank",
    "imageNormal", "imageArtCrop", "imageSmall", "imageBack",
]
ROLE_TO_COLUMN = {
    "cardId": "id",
    "name": "name", "manaCost": "mana_cost", "cmc": "cmc",
    "typeLine": "type_line", "oracleText": "oracle_text",
    "flavorText": "flavor_text",
    "colorIdentity": "color_identity", "rarity": "rarity", "artist": "artist",
    "power": "power", "toughness": "toughness",
    "setName": "set_name", "setIcon": "set_icon",
    "canBeCommander": "can_be_commander",
    "edhrecRank": "edhrec_rank",
    "imageNormal": "image_normal", "imageArtCrop": "image_art_crop",
    "imageSmall": "image_small", "imageBack": "image_back_normal",
}


def _is_blank(value):
    """True for values that mean "no filter". Note 0 is a real bound (power 0,
    mana value 0), so it must not be lumped in with False/""/[].
    """
    return (value is None or value is False
            or (isinstance(value, (str, list, dict, tuple)) and len(value) == 0))


def _set_glyph(icon_url):
    """The name of the sprite for a set's symbol, or "" if there isn't one.

    Keyed off the icon's filename rather than the set code, because several
    codes share a symbol — the SVG is what actually identifies it. Scryfall
    hangs a cache-busting query on the URL, so that comes off first.

    The name, not a path: the same symbol ships in two inks (see
    tools/set-glyphs.js) and which one to draw is the caller's business.
    """
    if not icon_url:
        return ""
    name = icon_url.split("?")[0].rsplit("/", 1)[-1]
    if name.endswith(".svg"):
        name = name[:-len(".svg")]
    return name


class CardModel(QAbstractListModel):
    countChanged = Signal()
    previewChanged = Signal()

    # Rows are fetched a page at a time as the view scrolls. Materialising the
    # whole pool costs ~200ms — about half in SQLite and half in building the
    # row dicts — and every filter change paid it, which is what made typing an
    # artist's name feel like wading. A page is ~17ms.
    PAGE = 400

    def __init__(self, connection=None, parent=None):
        super().__init__(parent)
        self._db = connection or db.connect()
        self._rows = []
        self._total = 0        # rows matching the filters, not rows loaded
        self._preview = None   # one card the filters match; see db.preview_card
        self._filters = {}
        self._sort = "name"
        self._sort_desc = False
        self._sort_levels = None  # advanced multi-level sort; overrides the above
        self._sets = None
        self._artists = None
        self._years = None
        self._types = None
        self._subtypes = None
        # debounce keystrokes so we don't query on every character
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.setInterval(150)
        self._timer.timeout.connect(self._refresh)
        self._refresh()

    # -- QAbstractListModel ----------------------------------------------
    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._rows)

    def roleNames(self):
        return {Qt.UserRole + i: r.encode() for i, r in enumerate(ROLE_NAMES)}

    def data(self, index, role):
        if not index.isValid():
            return None
        row = self._rows[index.row()]
        role_name = ROLE_NAMES[role - Qt.UserRole]
        value = row[ROLE_TO_COLUMN[role_name]]
        return "" if value is None else value

    def canFetchMore(self, parent=QModelIndex()):
        if parent.isValid():
            return False
        return len(self._rows) < self._total

    def fetchMore(self, parent=QModelIndex()):
        """Load the next page. The view calls this as it nears the end."""
        if parent.isValid():
            return
        more = self._query(offset=len(self._rows))
        if not more:
            return
        first = len(self._rows)
        self.beginInsertRows(QModelIndex(), first, first + len(more) - 1)
        self._rows.extend(more)
        self.endInsertRows()

    # -- filters (QML + future MCP entry point) ---------------------------
    @Slot(str, "QVariant")
    def setFilter(self, key, value):
        """Set one filter key; falsy values clear it. Debounced."""
        if isinstance(value, QJSValue):
            value = value.toVariant()
        if _is_blank(value):
            self._filters.pop(key, None)
        else:
            self._filters[key] = value
        self._timer.start()

    @Slot("QVariantMap")
    def setFilters(self, filters):
        """Replace the entire filter state at once."""
        cleaned = {}
        for k, v in dict(filters).items():
            if isinstance(v, QJSValue):
                v = v.toVariant()
            if not _is_blank(v):
                cleaned[k] = v
        self._filters = cleaned
        self._timer.start()

    @Slot()
    def clearFilters(self):
        self._filters = {}
        self._timer.start()

    # -- sorting ----------------------------------------------------------
    @Slot(str)
    def setSortOrder(self, sort):
        """One of "name", "cmc", "edhrec", "set", "rarity"."""
        self._sort = sort
        self._sort_levels = None
        self._refresh()

    @Slot(bool)
    def setSortDescending(self, descending):
        self._sort_desc = descending
        self._sort_levels = None
        self._refresh()

    @Slot("QVariantList")
    def setSortLevels(self, levels):
        """Advanced sort: [{key, desc}, ...] by priority; [] reverts to simple."""
        parsed = [(lv["key"], bool(lv["desc"])) for lv in levels]
        self._sort_levels = parsed or None
        self._refresh()

    # -- data for filter UI ------------------------------------------------
    def _get_sets(self):
        if self._sets is None:
            rows = db.list_sets(self._db)
            for row in rows:
                row["glyph"] = _set_glyph(row.get("icon"))
            self._sets = rows
        return self._sets

    sets = Property("QVariantList", _get_sets, constant=True)

    def _get_artists(self):
        if self._artists is None:
            self._artists = db.list_artists(self._db)
        return self._artists

    artists = Property("QVariantList", _get_artists, constant=True)

    def _get_types(self):
        if self._types is None:
            self._types = db.list_types(self._db)
        return self._types

    types = Property("QVariantList", _get_types, constant=True)

    def _get_subtypes(self):
        if self._subtypes is None:
            self._subtypes = db.list_subtypes(self._db)
        return self._subtypes

    subtypes = Property("QVariantList", _get_subtypes, constant=True)

    def _get_years(self):
        """[first, last] release year in the pool — the year filter's ends."""
        if self._years is None:
            self._years = db.year_bounds(self._db)
        return self._years

    years = Property("QVariantList", _get_years, constant=True)

    def _get_count(self):
        """Everything the filters match — not just what's been loaded, which
        is what the UI means when it says "31830 cards"."""
        return self._total

    count = Property(int, _get_count, notify=countChanged)

    # -- a card the filters actually match ---------------------------------
    # The filter panel wears one as its face, so the form always shows a live
    # example of what it is currently asking for. Both are "" when nothing
    # matches, which is the state the panel signals rather than illustrates.
    def _get_preview_image(self):
        return (self._preview or {}).get("image_normal") or ""

    previewImage = Property(str, _get_preview_image, notify=previewChanged)

    def _get_preview_name(self):
        return (self._preview or {}).get("name") or ""

    previewName = Property(str, _get_preview_name, notify=previewChanged)

    def _get_preview_frame(self):
        """Which of Magic's frames this printing was laid out in — "1993",
        "1997", "2003", "2015" or "future". The filter form has a region table
        per frame; see qml/CardFrames.js."""
        return (self._preview or {}).get("frame") or ""

    previewFrame = Property(str, _get_preview_frame, notify=previewChanged)

    def _get_preview_rarity(self):
        """What this printing was printed at — "common", "uncommon", "rare",
        "mythic" or one of the odd ones ("special", "bonus"). The form needs it
        for the same reason it needs the frame: from the 2015 frame on, a rare
        or a mythic carries a holofoil stamp on the bottom edge of its text
        box, and the printed box arches over it. See qml/CardFrames.js."""
        return (self._preview or {}).get("rarity") or ""

    previewRarity = Property(str, _get_preview_rarity, notify=previewChanged)

    def _query(self, offset):
        return db.search(
            self._db, filters=self._filters, sort=self._sort,
            descending=self._sort_desc, sort_levels=self._sort_levels,
            limit=self.PAGE, offset=offset,
        )

    def _refresh(self):
        self.beginResetModel()
        self._total = db.count_matching(self._db, self._filters)
        self._rows = self._query(offset=0)
        self.endResetModel()
        self.countChanged.emit()
        # only when it actually moves: the panel fetches the face off the CDN,
        # and most filter changes leave the best match where it was
        preview = db.preview_card(self._db, self._filters)
        if preview != self._preview:
            self._preview = preview
            self.previewChanged.emit()
