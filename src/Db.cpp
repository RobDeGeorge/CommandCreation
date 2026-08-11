#include "Db.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QEventLoop>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSet>
#include <QSqlError>
#include <QSqlRecord>
#include <QTimer>

#if defined(Q_OS_WASM)
#include <emscripten.h>
#endif

namespace {

// The card columns every query hands back.
const QStringList kColumns = {
    "id", "name", "mana_cost", "cmc", "type_line", "oracle_text", "flavor_text",
    "power", "toughness",
    "color_identity", "keywords", "rarity", "artist", "set_name",
    "can_be_commander", "frame",
    "edhrec_rank", "image_normal", "image_art_crop", "image_small",
    "image_back_normal",
};

// The layouts that are two cards printed back to back. Split, flip, adventure
// and saga cards are one image with two halves — there is nothing to turn over.
const QStringList kTwoFacedLayouts = {
    "transform", "modal_dfc", "reversible_card", "double_faced_token",
};

// Where the databases live. Three cases, tried in this order:
//
//   WebAssembly  a fixed path in Emscripten's virtual filesystem, which
//                CMakeLists.txt preloads data/ into. There is no host
//                filesystem underneath to fall back to.
//   installed    data/ beside the binary — the layout `cmake --install` lays
//                down. This is what lets a copy of the build run on a machine
//                that never had the sources.
//   built here   the source tree, so ./build/mtgdeck opens the same two files
//                whichever directory it is launched from.
//
// The installed case looks for cards.db rather than the directory: a data/
// beside the binary that is empty means a build copied without its database,
// and falling through to the source tree there is more useful than failing.
QString dataDir()
{
#if defined(Q_OS_WASM)
    return QStringLiteral("/data");
#else
    const QString beside =
        QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("data"));
    if (QFileInfo::exists(QDir(beside).filePath(QStringLiteral("cards.db"))))
        return beside;
    return QDir(QStringLiteral(MTG_SOURCE_DIR)).filePath(QStringLiteral("data"));
#endif
}

// Where decks.db lives, which under WebAssembly is deliberately not where
// cards.db lives.
//
// The two files have opposite needs in the browser: cards.db is preloaded into
// an in-memory filesystem and never written, while decks.db is the only thing
// the user authors and has to survive the tab closing. Keeping them apart lets
// wasm/pre.js mount IndexedDB over this directory alone — a mount on the shared
// one would shadow the preloaded 29 MB and leave the app with no cards at all.
//
// On desktop there is one directory, as there has always been.
QString decksDir()
{
#if defined(Q_OS_WASM)
    return QStringLiteral("/decks");
#else
    return dataDir();
#endif
}

// A filter key carries a value only when it means something. Note that 0 is a
// real bound (mana value 0, power 0) while `false` is not a filter at all —
// which is why this tests the type rather than the truthiness, the same
// distinction Python's `value is False` drew.
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

bool has(const QVariantMap &f, const char *key)
{
    return f.contains(QLatin1String(key)) && !isBlank(f.value(QLatin1String(key)));
}

// sort key -> (nulls-last guard or empty, primary sort expression)
struct SortSpec {
    const char *guard;
    const char *expr;
};

SortSpec sortSpec(const QString &key)
{
    static const QHash<QString, SortSpec> keys = {
        {"name",   {nullptr, "cards.name COLLATE NOCASE"}},
        {"cmc",    {nullptr, "cards.cmc"}},
        {"edhrec", {"cards.edhrec_rank IS NULL", "cards.edhrec_rank"}},
        {"set",    {"set_icons.released_at IS NULL", "set_icons.released_at"}},
        {"rarity", {nullptr, "CASE cards.rarity WHEN 'common' THEN 0"
                             " WHEN 'uncommon' THEN 1 WHEN 'rare' THEN 2"
                             " WHEN 'mythic' THEN 4 ELSE 3 END"}},
    };
    return keys.value(key, keys.value(QStringLiteral("name")));
}

} // namespace

QString Db::now()
{
    // "2026-08-08T20:41:58+00:00" — Python's isoformat(timespec="seconds"),
    // not Qt's trailing "Z". See the note in Db.h.
    return QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"))
           + QStringLiteral("+00:00");
}

QSqlQuery Db::exec(const QString &sql, const QVariantList &params)
{
    QSqlQuery query(m_db);
    query.prepare(sql);
    for (const QVariant &p : params)
        query.addBindValue(p);
    if (!query.exec()) {
        // Callers that expect a failure (a duplicate list name) test the query
        // themselves; anything else reaching here is a bug in the SQL above.
        qWarning().noquote() << "sql failed:" << query.lastError().text() << "\n " << sql;
    }
    return query;
}

QVariantMap Db::rowOf(const QSqlQuery &query)
{
    const QSqlRecord record = query.record();
    QVariantMap row;
    for (int i = 0; i < record.count(); ++i)
        row.insert(record.fieldName(i), query.value(i));
    return row;
}

QVariantList Db::rowsOf(QSqlQuery &query)
{
    QVariantList rows;
    while (query.next())
        rows.append(rowOf(query));
    return rows;
}

QString Db::cardColumns()
{
    QStringList qualified;
    qualified.reserve(kColumns.size());
    for (const QString &c : kColumns)
        qualified << QStringLiteral("cards.") + c;
    return qualified.join(QLatin1Char(','));
}

// ---------------------------------------------------------------------------
// Opening and schema
// ---------------------------------------------------------------------------

bool Db::open(QString *error)
{
    const QString cards = QDir(dataDir()).filePath(QStringLiteral("cards.db"));
    const QString decks = QDir(decksDir()).filePath(QStringLiteral("decks.db"));

    if (!QFileInfo::exists(cards)) {
        if (error)
            *error = QStringLiteral("data/cards.db not found — run: python3 scripts/ingest.py");
        return false;
    }

    m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"));
    m_db.setDatabaseName(cards);
    if (!m_db.open()) {
        if (error)
            *error = m_db.lastError().text();
        return false;
    }

    // Your lists and decks live in their own file, ATTACHed as `decks`.
    // cards.db is deleted and rebuilt by scripts/ingest.py every refresh;
    // nothing you authored may live inside it.
    exec(QStringLiteral("ATTACH DATABASE ? AS decks"), {decks});

    ensureCardColumns();
    ensureBackFaces();
    ensureSetIcons();
    ensureDeckTables();
    return true;
}

void Db::ensureDeckTables()
{
    // Lists and decks are the same thing with a different `kind`: a deck is a
    // list that has a commander and gets checked against the Commander rules.
    // Promoting a list to a deck is therefore just setting two fields.
    exec(QStringLiteral(R"(
        CREATE TABLE IF NOT EXISTS decks.lists (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'list',
            commander_id TEXT,
            partner_id TEXT,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        ))"));
    exec(QStringLiteral("CREATE UNIQUE INDEX IF NOT EXISTS decks.idx_list_name"
                        " ON lists(name COLLATE NOCASE)"));
    exec(QStringLiteral(R"(
        CREATE TABLE IF NOT EXISTS decks.list_cards (
            list_id INTEGER NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
            card_id TEXT NOT NULL,
            qty INTEGER NOT NULL DEFAULT 1,
            added_at TEXT NOT NULL,
            label TEXT,
            PRIMARY KEY (list_id, card_id)
        ))"));

    // A card's label belongs to the entry, not the card: the same card can be
    // "ramp" in one deck and "cut?" in another. Added after the table existed,
    // so decks made before labels still open.
    QStringList cols;
    QSqlQuery info = exec(QStringLiteral("PRAGMA decks.table_info(list_cards)"));
    while (info.next())
        cols << info.value(1).toString();
    if (!cols.contains(QStringLiteral("label")))
        exec(QStringLiteral("ALTER TABLE decks.list_cards ADD COLUMN label TEXT"));

    exec(QStringLiteral("PRAGMA foreign_keys = ON"));
}

void Db::ensureCardColumns()
{
    // Databases built before power/toughness/artist existed are still usable —
    // add the columns so queries work. They stay NULL (and so match none of
    // those filters) until scripts/ingest.py is re-run.
    QStringList cols;
    QSqlQuery info = exec(QStringLiteral("PRAGMA table_info(cards)"));
    while (info.next())
        cols << info.value(1).toString();

    const QStringList wanted = {"power", "toughness", "artist", "flavor_text",
                                "frame", "layout", "full_art"};
    for (const QString &col : wanted) {
        if (!cols.contains(col))
            exec(QStringLiteral("ALTER TABLE cards ADD COLUMN %1 TEXT").arg(col));
    }
}

void Db::ensureBackFaces()
{
    // Give databases built before back faces existed one anyway.
    //
    // Scryfall serves the two sides of a card from the same path with one
    // segment different — .../normal/front/0/d/<id>.jpg and
    // .../normal/back/0/d/<id>.jpg — so the back of a card we already have the
    // front of can be named without fetching anything. Only for the layouts
    // that have a back at all: on a split or adventure card that URL is a 404.
    //
    // A re-run of scripts/ingest.py supersedes this with the URLs Scryfall
    // actually published, which is why this runs once — the moment the column
    // is added.
    QStringList cols;
    QSqlQuery info = exec(QStringLiteral("PRAGMA table_info(cards)"));
    while (info.next())
        cols << info.value(1).toString();
    if (cols.contains(QStringLiteral("image_back_normal")))
        return;

    exec(QStringLiteral("ALTER TABLE cards ADD COLUMN image_back_normal TEXT"));
    const QString marks = QStringList(QList<QString>(kTwoFacedLayouts.size(),
                                                     QStringLiteral("?")))
                              .join(QLatin1Char(','));
    QVariantList params;
    for (const QString &layout : kTwoFacedLayouts)
        params << layout;
    exec(QStringLiteral("UPDATE cards SET image_back_normal ="
                        " replace(image_normal, '/front/', '/back/')"
                        " WHERE layout IN (%1) AND image_normal LIKE '%/front/%'")
             .arg(marks),
         params);
}

void Db::ensureSetIcons()
{
    // Cache Scryfall's set metadata (icon SVG URL, release date); one-time
    // fetch. In a database that ingest.py has already built this returns at
    // the count check below without touching the network — which is also what
    // keeps the blocking fetch out of the WebAssembly build's way.
    QStringList cols;
    QSqlQuery info = exec(QStringLiteral("PRAGMA table_info(set_icons)"));
    while (info.next())
        cols << info.value(1).toString();
    if (!cols.isEmpty() && !cols.contains(QStringLiteral("released_at")))
        exec(QStringLiteral("DROP TABLE set_icons")); // old cache schema — rebuild

    exec(QStringLiteral("CREATE TABLE IF NOT EXISTS set_icons"
                        " (code TEXT PRIMARY KEY, icon_svg TEXT, released_at TEXT)"));

    QSqlQuery count = exec(QStringLiteral("SELECT COUNT(*) FROM set_icons"));
    if (count.next() && count.value(0).toInt() > 0)
        return;

    // The browser cannot run the fetch below. It drives a nested QEventLoop,
    // which Emscripten's single-threaded event loop does not support, and it
    // sets a User-Agent header, which browsers forbid. The WebAssembly build
    // ships a cards.db that ingest.py has already filled this table in, so
    // reaching here means that database was built wrong — and cards drawn
    // without their set icons is the better way to find that out than a tab
    // that never finishes loading.
#if defined(Q_OS_WASM)
    return;
#endif

    QNetworkAccessManager network;
    QString url = QStringLiteral("https://api.scryfall.com/sets");
    m_db.transaction();
    while (!url.isEmpty()) {
        QNetworkRequest request{QUrl(url)};
        request.setRawHeader("User-Agent", "OasisMTGDeckbuilder/0.1");
        request.setRawHeader("Accept", "application/json");

        QNetworkReply *reply = network.get(request);
        QEventLoop loop;
        QTimer timeout;
        timeout.setSingleShot(true);
        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
        timeout.start(15000);
        loop.exec();

        if (reply->error() != QNetworkReply::NoError || !timeout.isActive()) {
            reply->abort();
            reply->deleteLater();
            m_db.rollback(); // offline — cards just render without set icons
            return;
        }
        const QJsonObject page = QJsonDocument::fromJson(reply->readAll()).object();
        reply->deleteLater();

        for (const QJsonValue &value : page.value(QStringLiteral("data")).toArray()) {
            const QJsonObject set = value.toObject();
            exec(QStringLiteral("INSERT OR REPLACE INTO set_icons VALUES (?,?,?)"),
                 {set.value(QStringLiteral("code")).toVariant(),
                  set.value(QStringLiteral("icon_svg_uri")).toVariant(),
                  set.value(QStringLiteral("released_at")).toVariant()});
        }
        url = page.value(QStringLiteral("next_page")).toString();
    }
    m_db.commit();
}

// ---------------------------------------------------------------------------
// Searching
// ---------------------------------------------------------------------------

QString Db::orderBy(const QString &sort, bool descending)
{
    const SortSpec spec = sortSpec(sort);
    QStringList terms;
    if (spec.guard)
        terms << QLatin1String(spec.guard);
    terms << QLatin1String(spec.expr) + (descending ? QStringLiteral(" DESC") : QString());
    if (sort != QLatin1String("name"))
        terms << QStringLiteral("cards.name COLLATE NOCASE"); // stable tiebreak
    return terms.join(QStringLiteral(", "));
}

Db::Where Db::buildWhere(const QVariantMap &f)
{
    Where where;
    where.sql = QStringLiteral(" WHERE 1=1");
    QVariantList &params = where.params;
    QString &sql = where.sql;

    const auto like = [](const QString &s) { return QStringLiteral("%") + s + QStringLiteral("%"); };

    if (has(f, "text")) {
        const QString pattern = like(f.value(QStringLiteral("text")).toString());
        sql += QStringLiteral(" AND (name LIKE ? OR type_line LIKE ? OR oracle_text LIKE ?)");
        params << pattern << pattern << pattern;
    }
    if (has(f, "name")) {
        sql += QStringLiteral(" AND name LIKE ?");
        params << like(f.value(QStringLiteral("name")).toString());
    }
    if (has(f, "mana")) {
        QString symbols;
        for (const QChar &c : f.value(QStringLiteral("mana")).toString().toUpper()) {
            if (c != QLatin1Char('{') && c != QLatin1Char('}') && c != QLatin1Char(' '))
                symbols += c;
        }
        sql += QStringLiteral(" AND REPLACE(REPLACE(mana_cost,'{',''),'}','') LIKE ?");
        params << like(symbols);
    }
    if (has(f, "type")) {
        sql += QStringLiteral(" AND type_line LIKE ?");
        params << like(f.value(QStringLiteral("type")).toString());
    }
    if (has(f, "subtype")) {
        // subtypes live after the em dash in the type line
        sql += QStringLiteral(" AND instr(type_line, '—') > 0"
                              " AND substr(type_line, instr(type_line, '—')) LIKE ?");
        params << like(f.value(QStringLiteral("subtype")).toString());
    }
    if (has(f, "oracle")) {
        sql += QStringLiteral(" AND oracle_text LIKE ?");
        params << like(f.value(QStringLiteral("oracle")).toString());
    }
    if (has(f, "flavor")) {
        sql += QStringLiteral(" AND flavor_text LIKE ?");
        params << like(f.value(QStringLiteral("flavor")).toString());
    }
    if (has(f, "artist")) {
        sql += QStringLiteral(" AND artist LIKE ?");
        params << like(f.value(QStringLiteral("artist")).toString());
    }
    if (has(f, "set_codes")) {
        const QVariantList codes = f.value(QStringLiteral("set_codes")).toList();
        QStringList marks;
        for (const QVariant &code : codes) {
            marks << QStringLiteral("?");
            params << code.toString();
        }
        sql += QStringLiteral(" AND set_code IN (%1)").arg(marks.join(QLatin1Char(',')));
    }
    if (has(f, "commanders_only"))
        sql += QStringLiteral(" AND can_be_commander=1");

    // Asks the list what it holds rather than being handed the ids, so a card
    // added or removed while the gallery is showing a list is reflected on the
    // next query instead of leaving the grid a snapshot of an older list.
    if (has(f, "in_list")) {
        sql += QStringLiteral(" AND cards.id IN (SELECT card_id FROM decks.list_cards"
                              " WHERE list_id=?)");
        params << f.value(QStringLiteral("in_list")).toInt();
    }

    if (has(f, "legal_identity")) {
        // The Commander rule: a card may only use colours its commander does.
        // Deliberately separate from the `colors` filter so the two compose —
        // this one asks "could this go in the deck at all", the other is a
        // search you run inside that.
        //
        // A colourless commander arrives as "C" rather than "": it admits only
        // colourless cards, which is a filter, and an empty string would read
        // as no filter at all. "C" holds none of WUBRG, so it falls out here
        // with no special case.
        const QString identity = f.value(QStringLiteral("legal_identity")).toString();
        for (const QChar &colour : QStringLiteral("WUBRG")) {
            if (!identity.contains(colour))
                sql += QStringLiteral(" AND color_identity NOT LIKE '%%1%'").arg(colour);
        }
    }
    if (has(f, "rarities")) {
        const QVariantList rarities = f.value(QStringLiteral("rarities")).toList();
        QStringList marks;
        for (const QVariant &rarity : rarities) {
            marks << QStringLiteral("?");
            params << rarity.toString();
        }
        sql += QStringLiteral(" AND rarity IN (%1)").arg(marks.join(QLatin1Char(',')));
    }

    // The release year is a property of the set, not of the card, and it is
    // the one filter whose answer isn't already in `cards`. A subquery rather
    // than a join, so the promise above holds and countMatching() still never
    // joins.
    const bool hasYearMin = has(f, "year_min");
    const bool hasYearMax = has(f, "year_max");
    if (hasYearMin || hasYearMax) {
        QString bounds;
        if (hasYearMin)
            bounds += QStringLiteral(" AND released_at >= ?");
        if (hasYearMax)
            bounds += QStringLiteral(" AND released_at <= ?");
        sql += QStringLiteral(" AND set_code IN (SELECT code FROM set_icons"
                              " WHERE released_at IS NOT NULL")
               + bounds + QStringLiteral(")");
        if (hasYearMin)
            params << QStringLiteral("%1-01-01").arg(f.value(QStringLiteral("year_min")).toInt());
        if (hasYearMax)
            params << QStringLiteral("%1-12-31").arg(f.value(QStringLiteral("year_max")).toInt());
    }

    if (has(f, "cmc_min")) {
        sql += QStringLiteral(" AND cmc >= ?");
        params << f.value(QStringLiteral("cmc_min"));
    }
    if (has(f, "cmc_max")) {
        sql += QStringLiteral(" AND cmc <= ?");
        params << f.value(QStringLiteral("cmc_max"));
    }

    // Power/toughness are printed text: NULL on non-creatures and non-numeric
    // on the likes of "*" or "*+1". The GLOB guard keeps those out of the
    // comparison rather than letting CAST silently turn them into 0. A leading
    // minus is allowed — Spinal Parasite and Char-Rumbler really are -1 power.
    struct Bound { const char *key; const char *column; const char *op; };
    static const Bound bounds[] = {
        {"power_min", "power", ">="},
        {"power_max", "power", "<="},
        {"toughness_min", "toughness", ">="},
        {"toughness_max", "toughness", "<="},
    };
    for (const Bound &bound : bounds) {
        if (!has(f, bound.key))
            continue;
        sql += QStringLiteral(" AND (%1 GLOB '[0-9]*' OR %1 GLOB '-[0-9]*')"
                              " AND CAST(%1 AS INTEGER) %2 ?")
                   .arg(QLatin1String(bound.column), QLatin1String(bound.op));
        params << f.value(QLatin1String(bound.key));
    }

    if (has(f, "colorless")) {
        sql += QStringLiteral(" AND color_identity = ''");
    } else if (has(f, "colors")) {
        const QString chosen = f.value(QStringLiteral("colors")).toString();
        const QString mode = f.value(QStringLiteral("color_mode"),
                                     QStringLiteral("within")).toString();
        if (mode == QLatin1String("within")) {
            for (const QChar &c : QStringLiteral("WUBRG")) {
                if (!chosen.contains(c))
                    sql += QStringLiteral(" AND color_identity NOT LIKE '%%1%'").arg(c);
            }
        } else { // exact / includes
            for (const QChar &c : chosen) {
                sql += QStringLiteral(" AND color_identity LIKE ?");
                params << QStringLiteral("%%1%").arg(c);
            }
            if (mode == QLatin1String("exact")) {
                sql += QStringLiteral(" AND length(color_identity) = ?");
                params << chosen.size();
            }
        }
    }

    return where;
}

QVariantList Db::search(const QVariantMap &filters, const QString &sort, bool descending,
                        int limit, int offset)
{
    Where where = buildWhere(filters);
    QString sql = QStringLiteral("SELECT %1, set_icons.icon_svg AS set_icon FROM cards"
                                 " LEFT JOIN set_icons ON cards.set_code = set_icons.code")
                      .arg(cardColumns())
                  + where.sql + QStringLiteral(" ORDER BY ") + orderBy(sort, descending);
    if (limit >= 0) {
        sql += QStringLiteral(" LIMIT ? OFFSET ?");
        where.params << limit << offset;
    }
    QSqlQuery query = exec(sql, where.params);
    return rowsOf(query);
}

int Db::countMatching(const QVariantMap &filters)
{
    const Where where = buildWhere(filters);
    QSqlQuery query = exec(QStringLiteral("SELECT COUNT(*) FROM cards") + where.sql,
                           where.params);
    return query.next() ? query.value(0).toInt() : 0;
}

QVariantMap Db::previewCard(const QVariantMap &filters)
{
    // One card the filters actually match — the face the filter form wears.
    // Picked to be recognizable, and where the filters leave room for it, to
    // have power and toughness: the form's regions are measured off a creature
    // frame. Ordinary layouts first and no full-art printings, because the
    // form knows where the regions sit in each of Magic's four frames but a
    // full-art land or a split card has no text box in any of them.
    const Where where = buildWhere(filters);
    QSqlQuery query = exec(
        QStringLiteral("SELECT %1, set_icons.icon_svg AS set_icon FROM cards"
                       " LEFT JOIN set_icons ON cards.set_code = set_icons.code")
                .arg(cardColumns())
            + where.sql
            + QStringLiteral(" ORDER BY COALESCE(cards.layout,'normal') != 'normal',"
                             " COALESCE(cards.full_art,0),"
                             " cards.edhrec_rank IS NULL,"
                             " cards.edhrec_rank + CASE WHEN cards.power IS NULL"
                             " THEN 300 ELSE 0 END,"
                             " cards.name COLLATE NOCASE LIMIT 1"),
        where.params);
    return query.next() ? rowOf(query) : QVariantMap();
}

QStringList Db::listArtists()
{
    QSqlQuery query = exec(QStringLiteral(
        "SELECT DISTINCT artist FROM cards WHERE artist IS NOT NULL AND artist != ''"
        " ORDER BY artist COLLATE NOCASE"));
    QStringList artists;
    while (query.next())
        artists << query.value(0).toString();
    return artists;
}

QStringList Db::typeWords(bool beforeDash)
{
    // The vocabulary of the type line, split into single words. Done here
    // rather than in SQL because a type line holds several words at once —
    // "Legendary Artifact Creature — Golem" is five — while both filters match
    // one word at a time. Split cards carry two faces on one line, so each
    // side of the // is read separately.
    QSet<QString> words;
    QSqlQuery query = exec(QStringLiteral(
        "SELECT DISTINCT type_line FROM cards"
        " WHERE type_line IS NOT NULL AND type_line != ''"));
    while (query.next()) {
        const QString line = query.value(0).toString();
        for (const QString &face : line.split(QStringLiteral("//"))) {
            const int dash = face.indexOf(QStringLiteral("—"));
            QString part;
            if (beforeDash)
                part = dash < 0 ? face : face.left(dash);
            else if (dash >= 0)
                part = face.mid(dash + 1);
            for (const QString &word : part.split(QRegularExpression(QStringLiteral("\\s+")),
                                                  Qt::SkipEmptyParts))
                words.insert(word);
        }
    }
    QStringList sorted(words.begin(), words.end());
    std::sort(sorted.begin(), sorted.end(), [](const QString &a, const QString &b) {
        const int cmp = QString::compare(a, b, Qt::CaseInsensitive);
        return cmp != 0 ? cmp < 0 : a < b;
    });
    return sorted;
}

QStringList Db::listTypes()
{
    return typeWords(true);
}

QStringList Db::listSubtypes()
{
    return typeWords(false);
}

QVariantList Db::yearBounds()
{
    // First and last release year in the card pool. Falls back to a span wide
    // enough to hold Magic's whole history if the set dates were never fetched
    // (offline on first run), so the control still works rather than
    // collapsing to a single year.
    QSqlQuery query = exec(QStringLiteral(
        "SELECT MIN(released_at), MAX(released_at) FROM set_icons"
        " WHERE released_at IS NOT NULL"
        " AND code IN (SELECT set_code FROM cards)"));
    if (query.next() && !query.value(0).isNull()) {
        return {query.value(0).toString().left(4).toInt(),
                query.value(1).toString().left(4).toInt()};
    }
    return {1993, QDateTime::currentDateTimeUtc().date().year() + 1};
}

QVariantList Db::listSets()
{
    QSqlQuery query = exec(QStringLiteral(
        "SELECT DISTINCT cards.set_code AS code, cards.set_name AS name,"
        " set_icons.released_at AS released, set_icons.icon_svg AS icon"
        " FROM cards LEFT JOIN set_icons ON cards.set_code = set_icons.code"
        " ORDER BY set_icons.released_at IS NULL, set_icons.released_at DESC,"
        " cards.set_name COLLATE NOCASE"));
    return rowsOf(query);
}

// ---------------------------------------------------------------------------
// Lists and decks
// ---------------------------------------------------------------------------

void Db::flush()
{
#if defined(Q_OS_WASM)
    // SQLite has written to /decks, which is an IndexedDB mount held in memory
    // until something copies it out. wasm/pre.js owns the copying, including
    // coalescing calls that arrive while one is still in flight; this is only
    // the nudge. It returns immediately — the write lands a moment later, which
    // is why the browser is asked to save after every change rather than at
    // exit, an event a closing tab does not reliably give us.
    EM_ASM({
        if (Module["mtgSyncDecks"])
            Module["mtgSyncDecks"]();
    });
#endif
    // Nothing on desktop: the mutator's write already went to a real file.
}

void Db::touch(int listId)
{
    exec(QStringLiteral("UPDATE decks.lists SET updated_at=? WHERE id=?"), {now(), listId});
}

QVariantList Db::listLists()
{
    QSqlQuery query = exec(QStringLiteral(
        "SELECT l.id, l.name, l.kind, l.commander_id, l.notes, l.updated_at,"
        " c.name AS commander_name, c.color_identity AS commander_identity,"
        " c.image_art_crop AS commander_art,"
        " (SELECT COALESCE(SUM(qty),0) FROM decks.list_cards WHERE list_id=l.id)"
        "   AS card_count"
        " FROM decks.lists l LEFT JOIN cards c ON c.id = l.commander_id"
        " ORDER BY l.name COLLATE NOCASE"));
    return rowsOf(query);
}

int Db::createList(const QString &name, const QString &kind)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return 0;

    const QString stamp = now();
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("INSERT INTO decks.lists (name, kind, created_at, updated_at)"
                                 " VALUES (?,?,?,?)"));
    query.addBindValue(trimmed);
    query.addBindValue(kind);
    query.addBindValue(stamp);
    query.addBindValue(stamp);
    if (!query.exec())
        return 0; // duplicate name — the caller reports it
    flush();
    return query.lastInsertId().toInt();
}

bool Db::renameList(int listId, const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return false;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE decks.lists SET name=?, updated_at=? WHERE id=?"));
    query.addBindValue(trimmed);
    query.addBindValue(now());
    query.addBindValue(listId);
    if (!query.exec())
        return false;
    flush();
    return true;
}

void Db::deleteList(int listId)
{
    // Explicit, rather than leaning on ON DELETE CASCADE — foreign keys are a
    // per-connection pragma and this must hold whoever opened the database.
    exec(QStringLiteral("DELETE FROM decks.list_cards WHERE list_id=?"), {listId});
    exec(QStringLiteral("DELETE FROM decks.lists WHERE id=?"), {listId});
    flush();
}

int Db::duplicateList(int listId, const QString &name)
{
    const QVariantMap source = getList(listId);
    const int newId = createList(name, source.value(QStringLiteral("kind")).toString());
    if (newId == 0)
        return 0;
    exec(QStringLiteral("INSERT INTO decks.list_cards (list_id, card_id, qty, added_at, label)"
                        " SELECT ?, card_id, qty, ?, label FROM decks.list_cards"
                        " WHERE list_id=?"),
         {newId, now(), listId});
    exec(QStringLiteral("UPDATE decks.lists SET commander_id="
                        "(SELECT commander_id FROM decks.lists WHERE id=?) WHERE id=?"),
         {listId, newId});
    flush();
    return newId;
}

QVariantMap Db::getList(int listId)
{
    QSqlQuery query = exec(QStringLiteral(
                               "SELECT l.*, c.name AS commander_name,"
                               " c.color_identity AS commander_identity,"
                               " c.image_art_crop AS commander_art,"
                               " c.mana_cost AS commander_mana,"
                               " c.rarity AS commander_rarity,"
                               " c.image_normal AS commander_image,"
                               " c.image_back_normal AS commander_back"
                               " FROM decks.lists l LEFT JOIN cards c ON c.id = l.commander_id"
                               " WHERE l.id=?"),
                           {listId});
    return query.next() ? rowOf(query) : QVariantMap();
}

void Db::setListKind(int listId, const QString &kind)
{
    exec(QStringLiteral("UPDATE decks.lists SET kind=?, updated_at=? WHERE id=?"),
         {kind, now(), listId});
    flush();
}

void Db::setCommander(int listId, const QString &cardId)
{
    // The commander is kept in the card list too, so counts and exports
    // include it without special-casing.
    QSqlQuery previous = exec(QStringLiteral("SELECT commander_id FROM decks.lists WHERE id=?"),
                              {listId});
    const QString old = previous.next() ? previous.value(0).toString() : QString();

    exec(QStringLiteral("UPDATE decks.lists SET commander_id=?, kind='deck', updated_at=?"
                        " WHERE id=?"),
         {cardId.isEmpty() ? QVariant() : QVariant(cardId), now(), listId});

    if (!old.isEmpty() && old != cardId) {
        exec(QStringLiteral("DELETE FROM decks.list_cards WHERE list_id=? AND card_id=?"),
             {listId, old});
    }
    if (!cardId.isEmpty()) {
        exec(QStringLiteral("INSERT INTO decks.list_cards (list_id, card_id, qty, added_at)"
                            " VALUES (?,?,1,?) ON CONFLICT(list_id, card_id) DO NOTHING"),
             {listId, cardId, now()});
    }
    flush();
}

int Db::addCard(int listId, const QString &cardId, int qty)
{
    exec(QStringLiteral("INSERT INTO decks.list_cards (list_id, card_id, qty, added_at)"
                        " VALUES (?,?,?,?)"
                        " ON CONFLICT(list_id, card_id) DO UPDATE SET qty = qty + excluded.qty"),
         {listId, cardId, qty, now()});
    touch(listId);
    flush();
    QSqlQuery query = exec(QStringLiteral("SELECT qty FROM decks.list_cards"
                                          " WHERE list_id=? AND card_id=?"),
                           {listId, cardId});
    return query.next() ? query.value(0).toInt() : 0;
}

int Db::addCards(int listId, const QList<QPair<QString, int>> &pairs)
{
    // addCard() commits per call, which is fine for a click and wrong for an
    // import: a hundred-card deck would be a hundred commits.
    if (pairs.isEmpty())
        return 0;
    const QString stamp = now();
    m_db.transaction();
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO decks.list_cards (list_id, card_id, qty, added_at)"
        " VALUES (?,?,?,?)"
        " ON CONFLICT(list_id, card_id) DO UPDATE SET qty = qty + excluded.qty"));
    for (const auto &pair : pairs) {
        query.addBindValue(listId);
        query.addBindValue(pair.first);
        query.addBindValue(pair.second);
        query.addBindValue(stamp);
        query.exec();
    }
    touch(listId);
    m_db.commit();
    flush(); // after the commit, so one import is one sync
    return pairs.size();
}

int Db::setCardQty(int listId, const QString &cardId, int qty)
{
    if (qty <= 0)
        return removeCard(listId, cardId);
    exec(QStringLiteral("UPDATE decks.list_cards SET qty=? WHERE list_id=? AND card_id=?"),
         {qty, listId, cardId});
    touch(listId);
    flush();
    return qty;
}

QString Db::setCardLabel(int listId, const QString &cardId, const QString &label)
{
    // An empty label clears it rather than storing a blank, so the row goes
    // back to showing nothing at all.
    const QString kept = label.trimmed();
    exec(QStringLiteral("UPDATE decks.list_cards SET label=? WHERE list_id=? AND card_id=?"),
         {kept.isEmpty() ? QVariant() : QVariant(kept), listId, cardId});
    touch(listId);
    flush();
    return kept;
}

QString Db::cardLabel(int listId, const QString &cardId)
{
    QSqlQuery query = exec(QStringLiteral("SELECT label FROM decks.list_cards"
                                          " WHERE list_id=? AND card_id=?"),
                           {listId, cardId});
    return query.next() ? query.value(0).toString() : QString();
}

int Db::removeCard(int listId, const QString &cardId)
{
    exec(QStringLiteral("DELETE FROM decks.list_cards WHERE list_id=? AND card_id=?"),
         {listId, cardId});
    // a removed commander is no longer the commander
    exec(QStringLiteral("UPDATE decks.lists SET commander_id=NULL"
                        " WHERE id=? AND commander_id=?"),
         {listId, cardId});
    touch(listId);
    flush();
    return 0;
}

QVariantList Db::listContents(int listId, const QString &sort, bool descending)
{
    QSqlQuery query = exec(
        QStringLiteral("SELECT %1, set_icons.icon_svg AS set_icon, lc.qty AS qty,"
                       " lc.label AS label,"
                       " (cards.id = (SELECT commander_id FROM decks.lists WHERE id=?))"
                       "   AS is_commander"
                       " FROM decks.list_cards lc JOIN cards ON cards.id = lc.card_id"
                       " LEFT JOIN set_icons ON cards.set_code = set_icons.code"
                       " WHERE lc.list_id=?"
                       " ORDER BY is_commander DESC, %2")
            .arg(cardColumns(), orderBy(sort, descending)),
        {listId, listId});
    return rowsOf(query);
}

QList<int> Db::cardMembership(const QString &cardId)
{
    QSqlQuery query = exec(QStringLiteral("SELECT list_id FROM decks.list_cards WHERE card_id=?"),
                           {cardId});
    QList<int> ids;
    while (query.next())
        ids << query.value(0).toInt();
    return ids;
}

QHash<QString, int> Db::cardsInList(int listId)
{
    QSqlQuery query = exec(QStringLiteral("SELECT card_id, qty FROM decks.list_cards"
                                          " WHERE list_id=?"),
                           {listId});
    QHash<QString, int> contents;
    while (query.next())
        contents.insert(query.value(0).toString(), query.value(1).toInt());
    return contents;
}

QList<QPair<QString, QString>> Db::allCardNames()
{
    QSqlQuery query = exec(QStringLiteral("SELECT id, name FROM cards"));
    QList<QPair<QString, QString>> cards;
    while (query.next())
        cards.append({query.value(0).toString(), query.value(1).toString()});
    return cards;
}
