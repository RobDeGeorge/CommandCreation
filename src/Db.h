#pragma once

#include <QHash>
#include <QList>
#include <QPair>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// SQLite access for the card database.
//
// A row is a QVariantMap keyed by its own column name ("image_art_crop", not
// "imageArtCrop"): the models translate to QML's role names on the way out, and
// keeping the database's vocabulary this far up is what lets the queries below
// be read against the schema itself.
//
// SQL NULL arrives as an invalid QVariant, which the models turn into "".
class Db
{
public:
    // Opens data/cards.db with data/decks.db ATTACHed as `decks`, and brings
    // both up to the current schema. False with *error set if cards.db is
    // missing, which is the one condition that stops the app starting.
    bool open(QString *error);

    QSqlDatabase handle() const { return m_db; }

    // -- cards --------------------------------------------------------------
    // A key that is absent is a filter that isn't applied. The recognized ones,
    // all optional and all composing with each other:
    //
    //   text        substring across name + type line + rules text
    //   name        substring of the card name
    //   mana        mana cost symbols, braces optional ("2GG" finds "{2}{G}{G}")
    //   type        substring of the type line (supertypes/types)
    //   subtype     substring of the part after the em dash in the type line
    //   oracle      substring of the rules text
    //   flavor      substring of the flavor text (the italic line below it)
    //   artist      substring of the illustrator credit
    //   set_codes   list of set codes to include (empty/absent = all sets)
    //   colors      colour letters, e.g. "WUG"; read with color_mode
    //   color_mode  "within" (identity fits in colors — the Commander rule),
    //               "exact" (identity is exactly these), "includes" (contains
    //               all of these)
    //   colorless   only colourless-identity cards (overrides colors)
    //   legal_identity  what a commander admits; "C" for a colourless one. Kept
    //               apart from `colors` so the two compose — this asks "could
    //               this go in the deck at all", the other is a search inside it
    //   commanders_only  only cards that can be your commander
    //   rarities    list of rarities to include
    //   cmc_min / cmc_max                mana value bounds
    //   year_min / year_max              release year of the card's set
    //   power_min / power_max            power bounds (creatures only)
    //   toughness_min / toughness_max    toughness bounds (creatures only)
    // `sort` is one of the keys orderBy() knows; anything else sorts by name.
    QVariantList search(const QVariantMap &filters, const QString &sort, bool descending,
                        int limit = -1, int offset = 0);
    int countMatching(const QVariantMap &filters);
    QVariantMap previewCard(const QVariantMap &filters);

    QStringList listArtists();
    QStringList listTypes();
    QStringList listSubtypes();
    QVariantList yearBounds();
    QVariantList listSets();

    // -- lists and decks ----------------------------------------------------
    QVariantList listLists();
    int createList(const QString &name, const QString &kind = QStringLiteral("list"));
    bool renameList(int listId, const QString &name);
    void deleteList(int listId);
    int duplicateList(int listId, const QString &name);
    QVariantMap getList(int listId);
    void setListKind(int listId, const QString &kind);

    // An empty cardId clears the commander, the way passing None did.
    void setCommander(int listId, const QString &cardId);

    int addCard(int listId, const QString &cardId, int qty = 1);
    int addCards(int listId, const QList<QPair<QString, int>> &pairs);
    int setCardQty(int listId, const QString &cardId, int qty);
    QString setCardLabel(int listId, const QString &cardId, const QString &label);
    QString cardLabel(int listId, const QString &cardId);
    int removeCard(int listId, const QString &cardId);
    QVariantList listContents(int listId, const QString &sort, bool descending = false);
    QList<int> cardMembership(const QString &cardId);
    QHash<QString, int> cardsInList(int listId);

    // Every (id, name) in the pool — what DeckIo builds its match index from.
    // A flat pair list rather than rows: this is 31,830 of them, and the index
    // wants nothing but the two strings.
    QList<QPair<QString, QString>> allCardNames();

    // The timestamp written into created_at/updated_at. Ends "+00:00" rather
    // than Qt's "Z" on purpose: the rows already in decks.db were written that
    // way, and updated_at is compared as text to decide which list to reopen —
    // mixing the two formats would sort a stale list to the top.
    static QString now();

private:
    struct Where {
        QString sql;
        QVariantList params;
    };

    // The WHERE shared by search(), countMatching() and previewCard(), so a
    // count can never disagree with the rows it counts. Every column it
    // touches is on `cards`, which is why a count needs no join.
    static Where buildWhere(const QVariantMap &filters);
    static QString orderBy(const QString &sort, bool descending);
    static QString cardColumns();

    QSqlQuery exec(const QString &sql, const QVariantList &params = {});
    QVariantList rowsOf(QSqlQuery &query);
    static QVariantMap rowOf(const QSqlQuery &query);

    void ensureCardColumns();
    void ensureBackFaces();
    void ensureSetIcons();
    void ensureDeckTables();
    void touch(int listId);
    QStringList typeWords(bool beforeDash);

    QSqlDatabase m_db;
};
