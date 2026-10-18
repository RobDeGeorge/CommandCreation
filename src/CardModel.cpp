#include "CardModel.h"

#include <QSet>

namespace CardRoles {

const QStringList Names = {
    "cardId",
    "name", "manaCost", "cmc", "typeLine", "oracleText", "flavorText",
    "colorIdentity",
    "power", "toughness",
    "rarity", "artist", "setName", "setIcon", "canBeCommander", "edhrecRank",
    "imageNormal", "imageArtCrop", "imageSmall", "imageBack",
};

const QHash<QString, QString> ToColumn = {
    {"cardId", "id"},
    {"name", "name"}, {"manaCost", "mana_cost"}, {"cmc", "cmc"},
    {"typeLine", "type_line"}, {"oracleText", "oracle_text"},
    {"flavorText", "flavor_text"},
    {"colorIdentity", "color_identity"}, {"rarity", "rarity"}, {"artist", "artist"},
    {"power", "power"}, {"toughness", "toughness"},
    {"setName", "set_name"}, {"setIcon", "set_icon"},
    {"canBeCommander", "can_be_commander"},
    {"edhrecRank", "edhrec_rank"},
    {"imageNormal", "image_normal"}, {"imageArtCrop", "image_art_crop"},
    {"imageSmall", "image_small"}, {"imageBack", "image_back_normal"},
};

} // namespace CardRoles

namespace {

// The name of the sprite for a set's symbol, or "" if there isn't one.
//
// Keyed off the icon's filename rather than the set code, because several
// codes share a symbol — the SVG is what actually identifies it. Scryfall
// hangs a cache-busting query on the URL, so that comes off first.
//
// The name, not a path: the same symbol ships in two inks (see
// tools/set-glyphs.py) and which one to draw is the caller's business.
QString setGlyph(const QString &iconUrl)
{
    if (iconUrl.isEmpty())
        return QString();
    QString name = iconUrl.section(QLatin1Char('?'), 0, 0).section(QLatin1Char('/'), -1);
    if (name.endsWith(QStringLiteral(".svg")))
        name.chop(4);
    return name;
}

// A value that means "no filter". 0 is a real bound (power 0, mana value 0),
// so it must not be lumped in with false/""/[] — hence the type test rather
// than a truthiness test.
bool isBlank(const QVariant &v)
{
    if (!v.isValid() || v.isNull())
        return true;
    if (v.typeId() == QMetaType::Bool)
        return !v.toBool();
    switch (v.typeId()) {
    case QMetaType::QString:
        return v.toString().isEmpty();
    case QMetaType::QVariantList:
        return v.toList().isEmpty();
    case QMetaType::QStringList:
        return v.toStringList().isEmpty();
    case QMetaType::QVariantMap:
        return v.toMap().isEmpty();
    default:
        return false;
    }
}

} // namespace

CardModel::CardModel(Db *db, QObject *parent)
    : QAbstractListModel(parent)
    , m_db(db)
{
    // Debounce keystrokes so we don't query on every character.
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_debounce, &QTimer::timeout, this, [this] { refresh(); });
    refresh();
}

// -- QAbstractListModel ------------------------------------------------------

int CardModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QHash<int, QByteArray> CardModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    for (int i = 0; i < CardRoles::Names.size(); ++i)
        roles.insert(Qt::UserRole + i, CardRoles::Names.at(i).toUtf8());
    return roles;
}

QVariant CardModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return QVariant();
    const int slot = role - Qt::UserRole;
    if (slot < 0 || slot >= CardRoles::Names.size())
        return QVariant();

    const QVariantMap row = m_rows.at(index.row()).toMap();
    const QVariant value = row.value(CardRoles::ToColumn.value(CardRoles::Names.at(slot)));
    return value.isNull() ? QVariant(QString()) : value;
}

bool CardModel::canFetchMore(const QModelIndex &parent) const
{
    return parent.isValid() ? false : m_rows.size() < m_total;
}

void CardModel::fetchMore(const QModelIndex &parent)
{
    // Load the next page. The view calls this as it nears the end.
    if (parent.isValid())
        return;
    const QVariantList more = query(m_rows.size());
    if (more.isEmpty())
        return;
    const int first = m_rows.size();
    beginInsertRows(QModelIndex(), first, first + more.size() - 1);
    m_rows.append(more);
    endInsertRows();
}

// -- filters -----------------------------------------------------------------

void CardModel::setFilter(const QString &key, const QVariant &value)
{
    const QVariantMap before = m_filters;
    if (isBlank(value))
        m_filters.remove(key);
    else
        m_filters.insert(key, value);
    // Re-asserting a filter the map already holds is not a search. It happens
    // whenever the open list changes under a gallery already held to it, and
    // running the query again would only throw the grid back to the top.
    if (m_filters == before)
        return;
    m_debounce.start();
    emit filtersChanged();
}

void CardModel::clearFilters()
{
    m_filters.clear();
    m_debounce.start();
    emit filtersChanged();
}

// -- sorting -----------------------------------------------------------------

void CardModel::setSortOrder(const QString &sort)
{
    m_sort = sort;
    refresh();
}

void CardModel::setSortDescending(bool descending)
{
    m_sortDescending = descending;
    refresh();
}

// -- data for the filter UI --------------------------------------------------

QVariantList CardModel::sets()
{
    if (m_sets.isEmpty()) {
        QVariantList rows = m_db->listSets();
        for (QVariant &entry : rows) {
            QVariantMap row = entry.toMap();
            row.insert(QStringLiteral("glyph"),
                       setGlyph(row.value(QStringLiteral("icon")).toString()));
            entry = row;
        }
        m_sets = rows;
    }
    return m_sets;
}

QVariantList CardModel::artists()
{
    if (m_artists.isEmpty()) {
        for (const QString &artist : m_db->listArtists())
            m_artists << artist;
    }
    return m_artists;
}

QVariantList CardModel::types()
{
    if (m_types.isEmpty()) {
        for (const QString &type : m_db->listTypes())
            m_types << type;
    }
    return m_types;
}

QVariantList CardModel::subtypes()
{
    if (m_subtypes.isEmpty()) {
        for (const QString &subtype : m_db->listSubtypes())
            m_subtypes << subtype;
    }
    return m_subtypes;
}

QVariantList CardModel::years()
{
    // [first, last] release year in the pool — the year filter's ends.
    if (m_years.isEmpty())
        m_years = m_db->yearBounds();
    return m_years;
}

// -- a card the filters actually match ---------------------------------------
// The filter panel wears one as its face, so the form always shows a live
// example of what it is currently asking for. All of these are "" when nothing
// matches, which is the state the panel signals rather than illustrates.

QString CardModel::previewImage() const
{
    return m_preview.value(QStringLiteral("image_normal")).toString();
}

QString CardModel::previewName() const
{
    return m_preview.value(QStringLiteral("name")).toString();
}

QString CardModel::previewFrame() const
{
    // Which of Magic's frames this printing was laid out in — "1993", "1997",
    // "2003", "2015" or "future". See qml/CardFrames.js.
    return m_preview.value(QStringLiteral("frame")).toString();
}

QString CardModel::previewRarity() const
{
    // From the 2015 frame on, a rare or a mythic carries a holofoil stamp on
    // the bottom edge of its text box and the printed box arches over it, so
    // the form needs this for the same reason it needs the frame.
    return m_preview.value(QStringLiteral("rarity")).toString();
}

// -- internals ---------------------------------------------------------------

QVariantList CardModel::query(int offset, int limit)
{
    return m_db->search(m_filters, m_sort, m_sortDescending,
                        limit > 0 ? limit : Page, offset);
}

void CardModel::reload()
{
    // The list the gallery is held to has gained or lost a card, so the query
    // has to run again. What it must not do is *reset*: a reset throws every
    // delegate away, and the view comes back at the top, which costs you your
    // place in the gallery for the sake of one tile appearing.
    //
    // So run the same query and hand the view the difference — the rows that
    // actually went and came — as row-level inserts and removes. A view that
    // is told what changed keeps its position through it without being asked
    // to remember and restore anything, and nothing races the relayout.
    if (m_debounce.isActive())
        return;   // a filter change is already queued, and it owns the query

    const int limit = qMax(1, (m_rows.size() + Page - 1) / Page) * Page;
    const QVariantList fresh = query(0, limit);

    const int total = m_db->countMatching(m_filters);
    if (total != m_total) {
        m_total = total;
        emit countChanged();
    }

    auto idAt = [](const QVariantList &rows, int i) {
        return rows.at(i).toMap().value(QStringLiteral("id")).toString();
    };

    QSet<QString> freshIds;
    freshIds.reserve(fresh.size());
    for (int i = 0; i < fresh.size(); ++i)
        freshIds.insert(idAt(fresh, i));

    // Drop what is gone, walking backwards so the indices ahead of the cursor
    // are still the ones being talked about.
    for (int i = m_rows.size() - 1; i >= 0; --i) {
        if (freshIds.contains(idAt(m_rows, i)))
            continue;
        beginRemoveRows(QModelIndex(), i, i);
        m_rows.removeAt(i);
        endRemoveRows();
    }

    // Then add what arrived. Both lists carry the same sort, so a row missing
    // from the old one belongs exactly where it sits in the new one.
    QSet<QString> haveIds;
    haveIds.reserve(m_rows.size());
    for (int i = 0; i < m_rows.size(); ++i)
        haveIds.insert(idAt(m_rows, i));

    for (int i = 0; i < fresh.size(); ++i) {
        const QString id = idAt(fresh, i);
        if (haveIds.contains(id))
            continue;
        const int at = qMin(i, m_rows.size());
        beginInsertRows(QModelIndex(), at, at);
        m_rows.insert(at, fresh.at(i));
        endInsertRows();
    }

    // The preview is the one card the panel shows for the current filters, and
    // it can move when the list behind them does.
    const QVariantMap preview = m_db->previewCard(m_filters);
    if (preview != m_preview) {
        m_preview = preview;
        emit previewChanged();
    }
}

void CardModel::refresh(bool keepLoaded)
{
    // A reset costs the view its place, which is right when the question
    // changed and wrong when only the answer did. Say which this is, and the
    // grid holds or drops its position accordingly — see qml/Main.qml.
    if (!keepLoaded)
        emit searching();

    // Round up to whole pages, so what fetchMore() loads next still lands on a
    // page boundary.
    const int pages = keepLoaded ? (m_rows.size() + Page - 1) / Page : 1;
    beginResetModel();
    m_total = m_db->countMatching(m_filters);
    m_rows = query(0, qMax(1, pages) * Page);
    endResetModel();
    emit countChanged();

    // Only when it actually moves: the panel fetches the face off the CDN, and
    // most filter changes leave the best match where it was.
    const QVariantMap preview = m_db->previewCard(m_filters);
    if (preview != m_preview) {
        m_preview = preview;
        emit previewChanged();
    }
}
