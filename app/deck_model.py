"""Qt models for named lists and the deck being built.

`DeckStore` is the single object QML talks to. It owns the two models — the
sidebar of lists and the contents of whichever list is open — and every
mutation goes through one of its slots, so the database, both models and the
derived stats can never drift apart.
"""
from PySide6.QtCore import (
    QAbstractListModel, QModelIndex, QObject, Qt, Property, Signal, Slot,
)

from . import db, deck_io, deck_rules
from .card_model import ROLE_NAMES as CARD_ROLES, ROLE_TO_COLUMN as CARD_COLUMNS

LIST_ROLES = ["listId", "name", "kind", "cardCount", "commanderName",
              "commanderIdentity", "commanderArt", "isActive"]

DECK_ROLES = CARD_ROLES + ["qty", "isCommander", "primaryType", "label"]
DECK_COLUMNS = dict(CARD_COLUMNS, qty="qty", isCommander="is_commander",
                    label="label")


class ListsModel(QAbstractListModel):
    """Every list you've made, for the sidebar."""

    def __init__(self, store):
        super().__init__(store)
        self._store = store
        self._rows = []

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._rows)

    def roleNames(self):
        return {Qt.UserRole + i: r.encode() for i, r in enumerate(LIST_ROLES)}

    def data(self, index, role):
        if not index.isValid():
            return None
        row = self._rows[index.row()]
        name = LIST_ROLES[role - Qt.UserRole]
        if name == "listId":
            return row["id"]
        if name == "isActive":
            return row["id"] == self._store.activeId
        if name == "commanderName":
            return row["commander_name"] or ""
        if name == "commanderIdentity":
            return row["commander_identity"] or ""
        if name == "commanderArt":
            return row["commander_art"] or ""
        if name == "cardCount":
            return row["card_count"]
        return row.get(name) or ""

    def reload(self, rows):
        self.beginResetModel()
        self._rows = rows
        self.endResetModel()

    def refresh_active_flags(self):
        if self._rows:
            self.dataChanged.emit(self.index(0), self.index(len(self._rows) - 1))


class DeckModel(QAbstractListModel):
    """The cards inside the open list.

    Two views of the same rows, deliberately:

    `rows`      every card, commander included. The commander is a card in the
                deck — it counts toward the hundred and it belongs in the
                export — so the stats and the rule check read this.
    the model    everything except the commander. It already has a slot of its
                interface  own above the list, and listing it twice makes a
                one-card deck look like two.
    """

    def __init__(self, store):
        super().__init__(store)
        self._rows = []          # all of them
        self._visible = []       # ...minus the commander

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._visible)

    def roleNames(self):
        return {Qt.UserRole + i: r.encode() for i, r in enumerate(DECK_ROLES)}

    def data(self, index, role):
        if not index.isValid():
            return None
        row = self._visible[index.row()]
        name = DECK_ROLES[role - Qt.UserRole]
        if name == "primaryType":
            return deck_rules.primary_type(row)
        value = row[DECK_COLUMNS[name]]
        return "" if value is None else value

    def reload(self, rows):
        self.beginResetModel()
        self._rows = rows
        self._visible = [r for r in rows if not r["is_commander"]]
        self.endResetModel()

    @property
    def rows(self):
        return self._rows


class DeckStore(QObject):
    listsChanged = Signal()
    activeChanged = Signal()
    contentsChanged = Signal()
    # something the user should see said back to them: a duplicate name, a
    # card added, a deck exported
    notified = Signal(str)

    def __init__(self, connection=None, parent=None):
        super().__init__(parent)
        self._db = connection or db.connect()
        self._active_id = 0
        self._list = None          # the open list's row, or None
        self._lists_model = ListsModel(self)
        self._deck_model = DeckModel(self)
        self._sort = "cmc"
        self._reload_lists()
        # open the list you touched most recently — the sidebar is sorted by
        # name, which is the wrong thing to resume into
        rows = self._lists_model._rows
        if rows:
            self.setActive(max(rows, key=lambda r: r["updated_at"])["id"])

    # -- models QML binds to ----------------------------------------------
    lists = Property(QObject, lambda self: self._lists_model, constant=True)
    deck = Property(QObject, lambda self: self._deck_model, constant=True)

    # -- the open list ------------------------------------------------------
    def _get_active_id(self):
        return self._active_id

    activeId = Property(int, _get_active_id, notify=activeChanged)
    activeName = Property(str, lambda self: (self._list or {}).get("name", ""),
                          notify=activeChanged)
    activeKind = Property(str, lambda self: (self._list or {}).get("kind", ""),
                          notify=activeChanged)
    isDeck = Property(bool, lambda self: (self._list or {}).get("kind") == "deck",
                      notify=activeChanged)
    commanderId = Property(
        str, lambda self: (self._list or {}).get("commander_id") or "",
        notify=activeChanged)
    commanderName = Property(
        str, lambda self: (self._list or {}).get("commander_name") or "",
        notify=activeChanged)
    commanderIdentity = Property(
        str, lambda self: (self._list or {}).get("commander_identity") or "",
        notify=activeChanged)

    def _get_stats(self):
        return deck_rules.stats(self._deck_model.rows)

    stats = Property("QVariantMap", _get_stats, notify=contentsChanged)

    def _get_problems(self):
        if not self._list:
            return []
        return deck_rules.legality(
            self._deck_model.rows,
            self._list.get("commander_identity") or "",
            bool(self._list.get("commander_id")))

    problems = Property("QVariantList", _get_problems, notify=contentsChanged)

    def _get_illegal_card_ids(self):
        """Ids of cards that break a rule, so the UI can point at them.

        Only for decks: a plain list has no rules to break. Only errors count —
        a warning means unfinished, not wrong, and "34 more cards to go" is not
        any particular card's fault.
        """
        if not (self._list or {}).get("kind") == "deck":
            return []
        ids = []
        for problem in self._get_problems():
            if problem["level"] == "error":
                ids.extend(problem["card_ids"])
        return list(dict.fromkeys(ids))

    illegalCardIds = Property("QVariantList", _get_illegal_card_ids,
                              notify=contentsChanged)

    def _get_active_card_ids(self):
        """Ids in the open list — the grid ticks its tiles against this."""
        return [row["id"] for row in self._deck_model.rows]

    activeCardIds = Property("QVariantList", _get_active_card_ids,
                             notify=contentsChanged)

    # -- list management ----------------------------------------------------
    @Slot(str, result=int)
    @Slot(str, str, result=int)
    def createList(self, name, kind="list"):
        """`kind` is "list" or "deck" — chosen when the list is named."""
        kind = kind if kind in ("list", "deck") else "list"
        new_id = db.create_list(self._db, name, kind)
        if new_id is None:
            self.notified.emit(f'Couldn\'t create "{name.strip()}" — '
                               "a list with that name already exists.")
            return 0
        self._reload_lists()
        self.setActive(new_id)
        self.notified.emit(
            f'Created "{name.strip()}"{" as a deck" if kind == "deck" else ""}.')
        return new_id

    @Slot(str, str, result=int)
    def createListWithCard(self, name, card_id):
        """The "New list…" path from the card context menu: make it, then put
        the card you right-clicked straight into it."""
        new_id = self.createList(name)
        if new_id:
            self.addCard(new_id, card_id)
        return new_id

    @Slot(int, str)
    def renameList(self, list_id, name):
        if not db.rename_list(self._db, list_id, name):
            self.notified.emit(f'Couldn\'t rename to "{name.strip()}".')
            return
        self._reload_lists()
        if list_id == self._active_id:
            self._reload_active()

    @Slot(int)
    def deleteList(self, list_id):
        name = (db.get_list(self._db, list_id) or {}).get("name", "")
        db.delete_list(self._db, list_id)
        self._reload_lists()
        if list_id == self._active_id:
            rows = self._lists_model._rows
            self.setActive(rows[0]["id"] if rows else 0)
        self.notified.emit(f'Deleted "{name}".')

    @Slot(int, str)
    def duplicateList(self, list_id, name):
        new_id = db.duplicate_list(self._db, list_id, name)
        if new_id is None:
            self.notified.emit(f'Couldn\'t copy to "{name.strip()}".')
            return
        self._reload_lists()
        self.setActive(new_id)

    @Slot(int)
    def setActive(self, list_id):
        self._active_id = int(list_id)
        self._reload_active()
        self._lists_model.refresh_active_flags()

    # -- cards in lists -----------------------------------------------------
    @Slot(int, str)
    @Slot(int, str, int)
    def addCard(self, list_id, card_id, qty=1):
        if not list_id or not card_id:
            return
        new_qty = db.add_card(self._db, list_id, card_id, qty)
        self._after_change(list_id)
        name = (db.get_list(self._db, list_id) or {}).get("name", "list")
        self.notified.emit(f'Added to "{name}"'
                           + (f" (×{new_qty})" if new_qty > 1 else ""))

    @Slot(str)
    def addToActive(self, card_id):
        if not self._active_id:
            self.notified.emit("Make a list first.")
            return
        self.addCard(self._active_id, card_id)

    @Slot(int, str)
    def removeCard(self, list_id, card_id):
        db.remove_card(self._db, list_id, card_id)
        self._after_change(list_id)

    @Slot(int, str, int)
    def setQty(self, list_id, card_id, qty):
        db.set_card_qty(self._db, list_id, card_id, qty)
        self._after_change(list_id)

    @Slot(int, str)
    def toggleCard(self, list_id, card_id):
        """One click adds; clicking the same list again takes it back out."""
        if card_id in db.cards_in_list(self._db, list_id):
            self.removeCard(list_id, card_id)
        else:
            self.addCard(list_id, card_id)

    @Slot(int, str, str)
    def setCardLabel(self, list_id, card_id, label):
        """The label a card wears inside one list. Empty clears it."""
        kept = db.set_card_label(self._db, list_id, card_id, label)
        self._after_change(list_id)
        self.notified.emit(f'Labelled "{kept}".' if kept else "Label cleared.")

    @Slot(int, str, result=str)
    def cardLabel(self, list_id, card_id):
        """What the label dialog opens with, so editing one starts from it."""
        return db.card_label(self._db, list_id, card_id)

    @Slot(str, result="QVariantList")
    def listsForCard(self, card_id):
        """[{id, name, kind, contains}] — what the right-click menu renders."""
        member = set(db.card_membership(self._db, card_id))
        return [{"id": row["id"], "name": row["name"], "kind": row["kind"],
                 "count": row["card_count"], "contains": row["id"] in member}
                for row in self._lists_model._rows]

    # -- commander ----------------------------------------------------------
    @Slot(int, str)
    def setCommander(self, list_id, card_id):
        db.set_commander(self._db, list_id, card_id)
        self._reload_lists()
        self._after_change(list_id)
        name = card_id and (db.get_list(self._db, list_id) or {}).get(
            "commander_name")
        self.notified.emit(f"Commander set to {name}." if card_id
                           else "Commander cleared.")

    @Slot(int)
    def clearCommander(self, list_id):
        db.set_commander(self._db, list_id, None)
        self._reload_lists()
        self._after_change(list_id)

    @Slot(int)
    def promoteToDeck(self, list_id):
        db.set_list_kind(self._db, list_id, "deck")
        self._reload_lists()
        if list_id == self._active_id:
            self._reload_active()

    @Slot(int)
    def demoteToList(self, list_id):
        """Turn a deck back into a plain list.

        The commander is kept, not cleared: this only stops the Commander rules
        being checked against the list, and going back and forth shouldn't cost
        you the commander you chose. Naming a commander promotes it again — see
        db.set_commander.
        """
        db.set_list_kind(self._db, list_id, "list")
        self._reload_lists()
        if list_id == self._active_id:
            self._reload_active()

    # -- export -------------------------------------------------------------
    @Slot(result=str)
    @Slot(str, result=str)
    def exportText(self, style="moxfield"):
        """See deck_io.export_text for what the styles mean."""
        return deck_io.export_text(
            self._deck_model.rows, (self._list or {}).get("commander_id"), style)

    @Slot(str, result=bool)
    @Slot(str, str, result=bool)
    def exportToFile(self, path, style="moxfield"):
        target = path.replace("file://", "")
        try:
            with open(target, "w", encoding="utf-8") as fh:
                fh.write(self.exportText(style))
        except OSError as exc:
            self.notified.emit(f"Couldn't write {target}: {exc.strerror}")
            return False
        self.notified.emit(f"Exported to {target}")
        return True

    # -- import -------------------------------------------------------------
    @Slot(str, result="QVariantMap")
    def previewImport(self, text):
        """Read a pasted list without changing anything.

        Lets the dialog show what will happen — how many cards, which names
        weren't recognised — before the user commits to it. Importing a deck
        and finding out afterwards that eight cards silently vanished is the
        thing to avoid here.
        """
        entries, notes = deck_io.parse(text)
        matched, unmatched = deck_io.resolve(self._db, entries)

        keep = [m for m in matched if m["section"] in deck_io.KEPT_SECTIONS]
        skipped = len(matched) - len(keep)
        commander = next((m["name"] for m in keep if m["commander"]), "")
        return {
            "cards": len(keep),
            "copies": sum(m["qty"] for m in keep),
            "commander": commander,
            "unmatched": [u["name"] for u in unmatched],
            "skipped": skipped,
            "notes": notes,
            "suggestedName": deck_io.deck_name_from(text),
        }

    @Slot(str, str, result=int)
    @Slot(str, str, bool, result=int)
    def importText(self, text, name, into_active=False):
        """Bring a pasted deck list in. Returns the list id, 0 on failure.

        Unmatched names are reported through notified() rather than swallowed;
        previewImport() is the way to see them before committing.
        """
        entries, _notes = deck_io.parse(text)
        matched, unmatched = deck_io.resolve(self._db, entries)
        keep = [m for m in matched if m["section"] in deck_io.KEPT_SECTIONS]
        if not keep:
            self.notified.emit("Nothing in that list matched a card.")
            return 0

        if into_active and self._active_id:
            list_id = self._active_id
        else:
            list_id = db.create_list(self._db, name or "Imported deck")
            if list_id is None:
                self.notified.emit(f"A list called “{name}” already exists.")
                return 0

        db.add_cards(self._db, list_id, [(m["card_id"], m["qty"]) for m in keep])

        commander = next((m for m in keep if m["commander"]), None)
        if commander:
            db.set_commander(self._db, list_id, commander["card_id"])
            db.set_list_kind(self._db, list_id, "deck")

        self.setActive(list_id)
        self._after_change(list_id)

        message = f"Imported {sum(m['qty'] for m in keep)} cards"
        if unmatched:
            message += f" — {len(unmatched)} not recognised"
        self.notified.emit(message + ".")
        return list_id

    @Slot(str, result=str)
    def readFile(self, path):
        """Read a deck list off disk so the dialog can show it before import."""
        source = path.replace("file://", "")
        try:
            with open(source, "r", encoding="utf-8") as fh:
                return fh.read()
        except OSError as exc:
            self.notified.emit(f"Couldn't read {source}: {exc.strerror}")
            return ""

    # -- sorting inside the open list ---------------------------------------
    @Slot(str)
    def setSortOrder(self, sort):
        self._sort = sort
        self._reload_active()

    # -- internals ----------------------------------------------------------
    def _reload_lists(self):
        self._lists_model.reload(db.list_lists(self._db))
        self.listsChanged.emit()

    def _reload_active(self):
        self._list = db.get_list(self._db, self._active_id) if self._active_id else None
        rows = (db.list_contents(self._db, self._active_id, sort=self._sort)
                if self._list else [])
        self._deck_model.reload(rows)
        self.activeChanged.emit()
        self.contentsChanged.emit()

    def _after_change(self, list_id):
        """Counts in the sidebar, and the open list if it was the one touched."""
        self._reload_lists()
        if list_id == self._active_id:
            self._reload_active()
        else:
            self._lists_model.refresh_active_flags()
