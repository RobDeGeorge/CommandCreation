#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// Commander deck rules and statistics.
//
// Everything here is a pure function of a list's card rows (as returned by
// Db::listContents), so the same code answers "is this deck legal?" for the
// UI, for an export, and for anything that comes later.
namespace DeckRules {

constexpr int DeckSize = 100;
constexpr int CurveCap = 7; // the top bucket is "7+"

extern const QStringList TypeOrder;

// The one bucket a card counts toward. A card is filed under the first type it
// has in TypeOrder, so an Artifact Creature counts as a creature — that is how
// deck lists are conventionally read.
QString primaryType(const QVariantMap &card);

bool isBasicLand(const QVariantMap &card);
bool unlimitedCopies(const QVariantMap &card);

// Coloured pips in a mana cost, hybrids counting for both halves.
QHash<QChar, int> manaPips(const QString &manaCost);

// Rule violations, as {level, message, card_ids} maps. `level` is "error" for
// anything that makes the deck illegal and "warning" for things that are
// merely not finished — you are mid-build, so those shouldn't read as
// failures.
QVariantList legality(const QVariantList &cards, const QString &commanderIdentity,
                      bool hasCommander);

// Curve, type breakdown, pip counts and averages for the whole list.
QVariantMap stats(const QVariantList &cards);

// The "annotated" export: grouped under "Creatures (12)" style headings.
QString exportText(const QVariantList &cards, const QString &commanderId);

} // namespace DeckRules
