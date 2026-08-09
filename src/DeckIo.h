#pragma once

#include <QHash>
#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QVariantList>

// Reading and writing deck lists in the formats the deck sites use.
//
// Import is the awkward half. There is no standard: Moxfield, Archidekt, MTGO,
// TappedOut and Deckstats all emit "a card per line" and all disagree about
// the details, so the parser strips decorations from the outside in rather
// than trying to match one grammar:
//
//     SB: 4x Lightning Bolt (2X2) 117 *F* [Burn]
//     ^^^ ^^ ^                ^^^^^ ^^^ ^^^ ^^^^^
//     |   |  |                |     |   |   Archidekt category
//     |   |  |                |     |   foil marker
//     |   |  |                |     collector number
//     |   |  set code
//     |   quantity
//     MTGO sideboard prefix
//
// Everything but the name is optional, and any of it may be absent. What is
// left after the decorations come off is the card name.
//
// Name matching is deliberately forgiving, because a name typed by hand rarely
// matches the database byte for byte: case is ignored, accents fold, curly
// apostrophes fold to straight ones, and a double-faced card answers to its
// front face alone.
namespace DeckIo {

struct Entry {
    int qty = 1;
    QString name;
    QString set;
    QString number;
    QString section;
    bool commander = false;
    int line = 0;
};

struct Match {
    QString cardId;
    int qty = 1;
    bool commander = false;
    QString name;
    QString section;
};

struct Parsed {
    QList<Entry> entries;
    // Lines that could not be read at all, so the caller can show them rather
    // than silently dropping them.
    QStringList notes;
};

struct Resolved {
    QList<Match> matched;
    QList<Entry> unmatched;
};

// Sections whose cards go into the list; the rest are counted and reported.
bool isKeptSection(const QString &section);

Parsed parse(const QString &text);

// Folded name -> card id, including front faces of double-faced cards. A
// front-face alias never displaces a real card of that name.
QHash<QString, QString> buildIndex(const QList<QPair<QString, QString>> &cards);

// Match parsed entries to cards. Entries naming the same card are merged,
// keeping the largest quantity rather than summing, since a list that mentions
// a card twice means one card.
Resolved resolve(const QHash<QString, QString> &index, const QList<Entry> &entries);

// Write a deck list out. Three styles, because the sites disagree:
//   moxfield   "Commander" / "Deck" headings, one "1 Card Name" per line.
//   plain      Bare lines, commander first, no headings at all.
//   annotated  Grouped under "Creatures (12)" style headings — for reading,
//              not for importing.
QString exportText(const QVariantList &cards, const QString &commanderId,
                   const QString &style = QStringLiteral("moxfield"));

// A name for the list, if the paste announced one ("//NAME: Something").
QString deckNameFrom(const QString &text,
                     const QString &fallback = QStringLiteral("Imported deck"));

} // namespace DeckIo
