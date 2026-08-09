#include "DeckModel.h"
#include "CardModel.h"
#include "DeckIo.h"
#include "DeckRules.h"

#include <algorithm>

const QStringList ListRoles = {
    "listId", "name", "kind", "cardCount", "commanderName",
    "commanderIdentity", "commanderArt", "isActive",
};

const QStringList DeckExtraRoles = {"qty", "isCommander", "primaryType", "label"};

namespace {

// Role name -> column, for the deck view: the card columns plus what the list
// entry itself carries. primaryType is derived rather than stored, so it has
// no column and is answered in data().
const QHash<QString, QString> &deckColumns()
{
    static const QHash<QString, QString> columns = [] {
        QHash<QString, QString> map = CardRoles::ToColumn;
        map.insert(QStringLiteral("qty"), QStringLiteral("qty"));
        map.insert(QStringLiteral("isCommander"), QStringLiteral("is_commander"));
        map.insert(QStringLiteral("label"), QStringLiteral("label"));
        return map;
    }();
    return columns;
}

const QStringList &deckRoles()
{
    static const QStringList roles = CardRoles::Names + DeckExtraRoles;
    return roles;
}

QString str(const QVariantMap &row, const char *key)
{
    return row.value(QLatin1String(key)).toString();
}

// Where a card's type sits in the deck view's running order. primaryType()
// answers "Other" for anything TypeOrder doesn't name, which indexOf puts at
// -1; that sorts last, which is where "Other" belongs.
int typeRank(const QVariantMap &row)
{
    const int rank = DeckRules::TypeOrder.indexOf(DeckRules::primaryType(row));
    return rank < 0 ? DeckRules::TypeOrder.size() : rank;
}

} // namespace

// ---------------------------------------------------------------------------
// ListsModel
// ---------------------------------------------------------------------------

ListsModel::ListsModel(DeckStore *store)
    : QAbstractListModel(store)
    , m_store(store)
{
}

int ListsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QHash<int, QByteArray> ListsModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    for (int i = 0; i < ListRoles.size(); ++i)
        roles.insert(Qt::UserRole + i, ListRoles.at(i).toUtf8());
    return roles;
}

QVariant ListsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return QVariant();
    const int slot = role - Qt::UserRole;
    if (slot < 0 || slot >= ListRoles.size())
        return QVariant();

    const QVariantMap row = m_rows.at(index.row()).toMap();
    const QString name = ListRoles.at(slot);

    if (name == QLatin1String("listId"))
        return row.value(QStringLiteral("id"));
    if (name == QLatin1String("isActive"))
        return row.value(QStringLiteral("id")).toInt() == m_store->activeId();
    if (name == QLatin1String("commanderName"))
        return str(row, "commander_name");
    if (name == QLatin1String("commanderIdentity"))
        return str(row, "commander_identity");
    if (name == QLatin1String("commanderArt"))
        return str(row, "commander_art");
    if (name == QLatin1String("cardCount"))
        return row.value(QStringLiteral("card_count"));

    const QVariant value = row.value(name);
    return value.isNull() ? QVariant(QString()) : value;
}

void ListsModel::reload(const QVariantList &rows)
{
    beginResetModel();
    m_rows = rows;
    endResetModel();
}

void ListsModel::refreshActiveFlags()
{
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(m_rows.size() - 1));
}

// ---------------------------------------------------------------------------
// DeckModel
// ---------------------------------------------------------------------------

DeckModel::DeckModel(DeckStore *store)
    : QAbstractListModel(store)
{
}

int DeckModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_visible.size();
}

QHash<int, QByteArray> DeckModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    const QStringList &names = deckRoles();
    for (int i = 0; i < names.size(); ++i)
        roles.insert(Qt::UserRole + i, names.at(i).toUtf8());
    return roles;
}

QVariant DeckModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_visible.size())
        return QVariant();
    const int slot = role - Qt::UserRole;
    if (slot < 0 || slot >= deckRoles().size())
        return QVariant();

    const QVariantMap row = m_visible.at(index.row()).toMap();
    const QString name = deckRoles().at(slot);
    if (name == QLatin1String("primaryType"))
        return DeckRules::primaryType(row);

    const QVariant value = row.value(deckColumns().value(name));
    return value.isNull() ? QVariant(QString()) : value;
}

void DeckModel::reload(const QVariantList &rows)
{
    beginResetModel();
    m_rows = rows;
    m_visible.clear();
    for (const QVariant &entry : rows) {
        if (!entry.toMap().value(QStringLiteral("is_commander")).toBool())
            m_visible << entry;
    }

    // The view draws a header above each run of one type, and ListView starts
    // a new run every time section.property changes — so unless the rows
    // arrive grouped, a deck sorted by name gives "Artifact, Sol Ring,
    // Creature, Bear, Artifact, Mox…", a header per card. Group them here.
    //
    // Stable, so the order the query returned survives inside each type: that
    // is the sort the user picked in the combo, and it stays the sort within
    // a group. The groups themselves follow DeckRules::TypeOrder, the order
    // the annotated export already uses.
    std::stable_sort(m_visible.begin(), m_visible.end(),
                     [](const QVariant &a, const QVariant &b) {
                         return typeRank(a.toMap()) < typeRank(b.toMap());
                     });

    // Copies, not rows: a heading over "2x Forest" reads 2. Same rows the
    // grouping just ordered, so the number always matches what is under it.
    m_typeCounts.clear();
    for (const QVariant &entry : std::as_const(m_visible)) {
        const QVariantMap card = entry.toMap();
        const QString type = DeckRules::primaryType(card);
        const int qty = std::max(1, card.value(QStringLiteral("qty")).toInt());
        m_typeCounts[type] = m_typeCounts.value(type).toInt() + qty;
    }

    endResetModel();
    emit typeCountsChanged();
}

// ---------------------------------------------------------------------------
// DeckStore
// ---------------------------------------------------------------------------

DeckStore::DeckStore(Db *db, QObject *parent)
    : QObject(parent)
    , m_db(db)
    , m_lists(new ListsModel(this))
    , m_deck(new DeckModel(this))
{
    reloadLists();
    // Open the list you touched most recently — the sidebar is sorted by name,
    // which is the wrong thing to resume into.
    const QVariantList rows = m_lists->rows();
    if (!rows.isEmpty()) {
        QVariantMap newest = rows.first().toMap();
        for (const QVariant &entry : rows) {
            const QVariantMap row = entry.toMap();
            if (str(row, "updated_at") > str(newest, "updated_at"))
                newest = row;
        }
        setActive(newest.value(QStringLiteral("id")).toInt());
    }
}

QString DeckStore::activeName() const
{
    return str(m_list, "name");
}

QString DeckStore::activeKind() const
{
    return str(m_list, "kind");
}

bool DeckStore::isDeck() const
{
    return str(m_list, "kind") == QLatin1String("deck");
}

QString DeckStore::commanderId() const
{
    return str(m_list, "commander_id");
}

QString DeckStore::commanderName() const
{
    return str(m_list, "commander_name");
}

QString DeckStore::commanderArt() const
{
    return str(m_list, "commander_art");
}

QString DeckStore::commanderMana() const
{
    return str(m_list, "commander_mana");
}

QString DeckStore::commanderRarity() const
{
    return str(m_list, "commander_rarity");
}

QString DeckStore::commanderImage() const
{
    return str(m_list, "commander_image");
}

QString DeckStore::commanderBack() const
{
    return str(m_list, "commander_back");
}

QString DeckStore::commanderIdentity() const
{
    return str(m_list, "commander_identity");
}

QVariantMap DeckStore::stats() const
{
    return DeckRules::stats(m_deck->rows());
}

QVariantList DeckStore::problems() const
{
    if (m_list.isEmpty())
        return {};
    return DeckRules::legality(m_deck->rows(), str(m_list, "commander_identity"),
                               !str(m_list, "commander_id").isEmpty());
}

QVariantList DeckStore::illegalCardIds() const
{
    // Only for decks: a plain list has no rules to break. Only errors count —
    // a warning means unfinished, not wrong, and "34 more cards to go" is not
    // any particular card's fault.
    if (str(m_list, "kind") != QLatin1String("deck"))
        return {};

    QVariantList ids;
    QSet<QString> seen;
    for (const QVariant &entry : problems()) {
        const QVariantMap problem = entry.toMap();
        if (str(problem, "level") != QLatin1String("error"))
            continue;
        for (const QString &id : problem.value(QStringLiteral("card_ids")).toStringList()) {
            if (!seen.contains(id)) {
                seen.insert(id);
                ids << id;
            }
        }
    }
    return ids;
}

QVariantList DeckStore::activeCardIds() const
{
    // Ids in the open list — the grid ticks its tiles against this.
    QVariantList ids;
    for (const QVariant &entry : m_deck->rows())
        ids << entry.toMap().value(QStringLiteral("id"));
    return ids;
}

// -- list management ---------------------------------------------------------

int DeckStore::createList(const QString &name, const QString &kind)
{
    const QString wanted = (kind == QLatin1String("list") || kind == QLatin1String("deck"))
        ? kind
        : QStringLiteral("list");
    const int newId = m_db->createList(name, wanted);
    if (newId == 0) {
        emit notified(QStringLiteral("Couldn't create \"%1\" — "
                                     "a list with that name already exists.")
                          .arg(name.trimmed()));
        return 0;
    }
    reloadLists();
    setActive(newId);
    emit notified(QStringLiteral("Created \"%1\"%2.")
                      .arg(name.trimmed(),
                           wanted == QLatin1String("deck") ? QStringLiteral(" as a deck")
                                                           : QString()));
    return newId;
}

void DeckStore::renameList(int listId, const QString &name)
{
    if (!m_db->renameList(listId, name)) {
        emit notified(QStringLiteral("Couldn't rename to \"%1\".").arg(name.trimmed()));
        return;
    }
    reloadLists();
    if (listId == m_activeId)
        reloadActive();
}

void DeckStore::deleteList(int listId)
{
    const QString name = str(m_db->getList(listId), "name");
    m_db->deleteList(listId);
    reloadLists();
    if (listId == m_activeId) {
        const QVariantList rows = m_lists->rows();
        setActive(rows.isEmpty() ? 0 : rows.first().toMap().value(QStringLiteral("id")).toInt());
    }
    emit notified(QStringLiteral("Deleted \"%1\".").arg(name));
}

void DeckStore::duplicateList(int listId, const QString &name)
{
    const int newId = m_db->duplicateList(listId, name);
    if (newId == 0) {
        emit notified(QStringLiteral("Couldn't copy to \"%1\".").arg(name.trimmed()));
        return;
    }
    reloadLists();
    setActive(newId);
}

void DeckStore::setActive(int listId)
{
    m_activeId = listId;
    reloadActive();
    m_lists->refreshActiveFlags();
}

// -- cards in lists ----------------------------------------------------------

void DeckStore::addCard(int listId, const QString &cardId, int qty)
{
    if (listId == 0 || cardId.isEmpty())
        return;
    const int newQty = m_db->addCard(listId, cardId, qty);
    afterChange(listId);
    const QString name = str(m_db->getList(listId), "name");
    emit notified(QStringLiteral("Added to \"%1\"%2")
                      .arg(name.isEmpty() ? QStringLiteral("list") : name,
                           newQty > 1 ? QStringLiteral(" (×%1)").arg(newQty) : QString()));
}

void DeckStore::addToActive(const QString &cardId)
{
    if (m_activeId == 0) {
        emit notified(QStringLiteral("Make a list first."));
        return;
    }
    addCard(m_activeId, cardId);
}

void DeckStore::removeCard(int listId, const QString &cardId)
{
    m_db->removeCard(listId, cardId);
    afterChange(listId);
}

void DeckStore::setQty(int listId, const QString &cardId, int qty)
{
    m_db->setCardQty(listId, cardId, qty);
    afterChange(listId);
}

void DeckStore::toggleCard(int listId, const QString &cardId)
{
    if (m_db->cardsInList(listId).contains(cardId))
        removeCard(listId, cardId);
    else
        addCard(listId, cardId);
}

void DeckStore::setCardLabel(int listId, const QString &cardId, const QString &label)
{
    const QString kept = m_db->setCardLabel(listId, cardId, label);
    afterChange(listId);
    emit notified(kept.isEmpty() ? QStringLiteral("Label cleared.")
                                 : QStringLiteral("Labelled \"%1\".").arg(kept));
}

QString DeckStore::cardLabel(int listId, const QString &cardId)
{
    return m_db->cardLabel(listId, cardId);
}

QVariantList DeckStore::listsForCard(const QString &cardId)
{
    const QList<int> member = m_db->cardMembership(cardId);
    QVariantList out;
    for (const QVariant &entry : m_lists->rows()) {
        const QVariantMap row = entry.toMap();
        const int id = row.value(QStringLiteral("id")).toInt();
        out << QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("name"), str(row, "name")},
            {QStringLiteral("kind"), str(row, "kind")},
            {QStringLiteral("count"), row.value(QStringLiteral("card_count"))},
            {QStringLiteral("contains"), member.contains(id)},
        };
    }
    return out;
}

// -- commander ---------------------------------------------------------------

void DeckStore::setCommander(int listId, const QString &cardId)
{
    m_db->setCommander(listId, cardId);
    reloadLists();
    afterChange(listId);
    if (cardId.isEmpty()) {
        emit notified(QStringLiteral("Commander cleared."));
        return;
    }
    emit notified(QStringLiteral("Commander set to %1.")
                      .arg(str(m_db->getList(listId), "commander_name")));
}

void DeckStore::clearCommander(int listId)
{
    m_db->setCommander(listId, QString());
    reloadLists();
    afterChange(listId);
}

void DeckStore::promoteToDeck(int listId)
{
    m_db->setListKind(listId, QStringLiteral("deck"));
    reloadLists();
    if (listId == m_activeId)
        reloadActive();
}

void DeckStore::demoteToList(int listId)
{
    m_db->setListKind(listId, QStringLiteral("list"));
    reloadLists();
    if (listId == m_activeId)
        reloadActive();
}

// -- export and import -------------------------------------------------------

QString DeckStore::exportText(const QString &style)
{
    return DeckIo::exportText(m_deck->rows(), str(m_list, "commander_id"), style);
}

QVariantMap DeckStore::previewImport(const QString &text)
{
    // Importing a deck and finding out afterwards that eight cards silently
    // vanished is the thing to avoid here.
    const DeckIo::Parsed parsed = DeckIo::parse(text);
    const DeckIo::Resolved resolved = DeckIo::resolve(DeckIo::buildIndex(m_db->allCardNames()),
                                                      parsed.entries);

    int copies = 0, kept = 0;
    QString commander;
    for (const DeckIo::Match &match : resolved.matched) {
        if (!DeckIo::isKeptSection(match.section))
            continue;
        ++kept;
        copies += match.qty;
        if (match.commander && commander.isEmpty())
            commander = match.name;
    }
    QStringList unmatched;
    for (const DeckIo::Entry &entry : resolved.unmatched)
        unmatched << entry.name;

    return {
        {QStringLiteral("cards"), kept},
        {QStringLiteral("copies"), copies},
        {QStringLiteral("commander"), commander},
        {QStringLiteral("unmatched"), unmatched},
        {QStringLiteral("skipped"), static_cast<int>(resolved.matched.size()) - kept},
        {QStringLiteral("notes"), parsed.notes},
        {QStringLiteral("suggestedName"), DeckIo::deckNameFrom(text)},
    };
}

int DeckStore::importText(const QString &text, const QString &name, bool intoActive)
{
    // Unmatched names are reported through notified() rather than swallowed;
    // previewImport() is the way to see them before committing.
    const DeckIo::Parsed parsed = DeckIo::parse(text);
    const DeckIo::Resolved resolved = DeckIo::resolve(DeckIo::buildIndex(m_db->allCardNames()),
                                                      parsed.entries);

    QList<DeckIo::Match> keep;
    for (const DeckIo::Match &match : resolved.matched) {
        if (DeckIo::isKeptSection(match.section))
            keep << match;
    }
    if (keep.isEmpty()) {
        emit notified(QStringLiteral("Nothing in that list matched a card."));
        return 0;
    }

    int listId = 0;
    if (intoActive && m_activeId != 0) {
        listId = m_activeId;
    } else {
        listId = m_db->createList(name.isEmpty() ? QStringLiteral("Imported deck") : name);
        if (listId == 0) {
            emit notified(QStringLiteral("A list called “%1” already exists.").arg(name));
            return 0;
        }
    }

    QList<QPair<QString, int>> pairs;
    int copies = 0;
    for (const DeckIo::Match &match : keep) {
        pairs.append({match.cardId, match.qty});
        copies += match.qty;
    }
    m_db->addCards(listId, pairs);

    for (const DeckIo::Match &match : keep) {
        if (match.commander) {
            m_db->setCommander(listId, match.cardId);
            m_db->setListKind(listId, QStringLiteral("deck"));
            break;
        }
    }

    setActive(listId);
    afterChange(listId);

    QString message = QStringLiteral("Imported %1 cards").arg(copies);
    if (!resolved.unmatched.isEmpty())
        message += QStringLiteral(" — %1 not recognised").arg(resolved.unmatched.size());
    emit notified(message + QStringLiteral("."));
    return listId;
}

void DeckStore::setSortOrder(const QString &sort)
{
    m_sort = sort;
    reloadActive();
}

// -- internals ---------------------------------------------------------------

void DeckStore::reloadLists()
{
    m_lists->reload(m_db->listLists());
    emit listsChanged();
}

void DeckStore::reloadActive()
{
    m_list = m_activeId != 0 ? m_db->getList(m_activeId) : QVariantMap();
    const QVariantList rows = m_list.isEmpty()
        ? QVariantList()
        : m_db->listContents(m_activeId, m_sort);
    m_deck->reload(rows);
    emit activeChanged();
    emit contentsChanged();
}

void DeckStore::afterChange(int listId)
{
    reloadLists();
    if (listId == m_activeId)
        reloadActive();
    else
        m_lists->refreshActiveFlags();
}
