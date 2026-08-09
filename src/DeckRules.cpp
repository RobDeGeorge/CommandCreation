#include "DeckRules.h"

#include <QRegularExpression>
#include <QSet>

#include <algorithm>
#include <cmath>

namespace DeckRules {

const QStringList TypeOrder = {
    "Creature", "Planeswalker", "Instant", "Sorcery",
    "Artifact", "Enchantment", "Battle", "Land",
};

namespace {

const QString kPipColors = QStringLiteral("WUBRG");

const QSet<QString> kBasicLands = {
    "Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes",
    "Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp",
    "Snow-Covered Mountain", "Snow-Covered Forest", "Snow-Covered Wastes",
};

// Shadowborn Apostle, Relentless Rats, Persistent Petitioners, Dragon's Approach…
const QString kAnyNumber = QStringLiteral("a deck can have any number of cards named");

QString str(const QVariantMap &card, const char *key)
{
    return card.value(QLatin1String(key)).toString();
}

int qtyOf(const QVariantMap &card)
{
    return card.value(QStringLiteral("qty")).toInt();
}

// The names of the first few offenders, then a count of the rest — a rule
// message names what it can and then says how much more there is.
QString firstFew(const QStringList &names, int shown = 4)
{
    QString text = QStringList(names.mid(0, shown)).join(QStringLiteral(", "));
    if (names.size() > shown)
        text += QStringLiteral(" and %1 more").arg(names.size() - shown);
    return text;
}

QVariantMap problem(const QString &level, const QString &message,
                    const QStringList &cardIds = {})
{
    return {{QStringLiteral("level"), level},
            {QStringLiteral("message"), message},
            {QStringLiteral("card_ids"), QVariant(cardIds)}};
}

} // namespace

bool isBasicLand(const QVariantMap &card)
{
    return kBasicLands.contains(str(card, "name"))
           || str(card, "type_line").contains(QStringLiteral("Basic"));
}

bool unlimitedCopies(const QVariantMap &card)
{
    return isBasicLand(card) || str(card, "oracle_text").toLower().contains(kAnyNumber);
}

QString primaryType(const QVariantMap &card)
{
    const QString line = str(card, "type_line");
    const QString face = line.split(QStringLiteral("//")).first();
    for (const QString &type : TypeOrder) {
        if (face.contains(type))
            return type;
    }
    return QStringLiteral("Other");
}

QHash<QChar, int> manaPips(const QString &manaCost)
{
    QHash<QChar, int> counts;
    for (const QChar &c : kPipColors)
        counts.insert(c, 0);

    static const QRegularExpression symbol(QStringLiteral("\\{([^}]+)\\}"));
    QRegularExpressionMatchIterator it = symbol.globalMatch(manaCost);
    while (it.hasNext()) {
        const QString body = it.next().captured(1);
        for (const QString &part : body.split(QLatin1Char('/'))) {
            if (part.size() == 1 && counts.contains(part.at(0)))
                counts[part.at(0)] += 1;
        }
    }
    return counts;
}

QVariantList legality(const QVariantList &cards, const QString &commanderIdentity,
                      bool hasCommander)
{
    QVariantList problems;
    int total = 0;
    for (const QVariant &entry : cards)
        total += qtyOf(entry.toMap());

    if (!hasCommander)
        problems << problem(QStringLiteral("warning"), QStringLiteral("No commander chosen"));

    if (total < DeckSize) {
        const int missing = DeckSize - total;
        problems << problem(QStringLiteral("warning"),
                            QStringLiteral("%1 more card%2 to go (%3/%4)")
                                .arg(missing)
                                .arg(missing != 1 ? QStringLiteral("s") : QString())
                                .arg(total)
                                .arg(DeckSize));
    } else if (total > DeckSize) {
        const int over = total - DeckSize;
        problems << problem(QStringLiteral("error"),
                            QStringLiteral("%1 card%2 over (%3/%4)")
                                .arg(over)
                                .arg(over != 1 ? QStringLiteral("s") : QString())
                                .arg(total)
                                .arg(DeckSize));
    }

    QStringList dupeNames, dupeIds;
    for (const QVariant &entry : cards) {
        const QVariantMap card = entry.toMap();
        if (qtyOf(card) > 1 && !unlimitedCopies(card)) {
            dupeNames << QStringLiteral("%1 ×%2").arg(str(card, "name")).arg(qtyOf(card));
            dupeIds << str(card, "id");
        }
    }
    if (!dupeNames.isEmpty()) {
        problems << problem(QStringLiteral("error"),
                            QStringLiteral("Singleton: ") + firstFew(dupeNames), dupeIds);
    }

    if (hasCommander) {
        QSet<QChar> allowed;
        for (const QChar &c : commanderIdentity)
            allowed.insert(c);

        QStringList outsideNames, outsideIds;
        for (const QVariant &entry : cards) {
            const QVariantMap card = entry.toMap();
            bool within = true;
            for (const QChar &c : str(card, "color_identity")) {
                if (!allowed.contains(c)) {
                    within = false;
                    break;
                }
            }
            if (!within) {
                outsideNames << str(card, "name");
                outsideIds << str(card, "id");
            }
        }
        if (!outsideNames.isEmpty()) {
            const QString pips = commanderIdentity.isEmpty() ? QStringLiteral("colourless")
                                                             : commanderIdentity;
            problems << problem(QStringLiteral("error"),
                                QStringLiteral("Outside %1 identity: ").arg(pips)
                                    + firstFew(outsideNames),
                                outsideIds);
        }
    }
    return problems;
}

QVariantMap stats(const QVariantList &cards)
{
    QList<int> curve(CurveCap + 1, 0);
    QHash<QString, int> types;
    for (const QString &type : TypeOrder)
        types.insert(type, 0);
    types.insert(QStringLiteral("Other"), 0);

    QHash<QChar, int> pips;
    for (const QChar &c : kPipColors)
        pips.insert(c, 0);

    int spellCmc = 0, spellCount = 0, lands = 0, total = 0;

    for (const QVariant &entry : cards) {
        const QVariantMap card = entry.toMap();
        const int qty = qtyOf(card);
        total += qty;

        const QString kind = primaryType(card);
        types[kind] = types.value(kind, 0) + qty;

        const QHash<QChar, int> cardPips = manaPips(str(card, "mana_cost"));
        for (auto it = cardPips.constBegin(); it != cardPips.constEnd(); ++it)
            pips[it.key()] += it.value() * qty;

        if (kind == QLatin1String("Land")) {
            lands += qty;
            continue; // lands don't belong on a mana curve
        }
        const int cmc = static_cast<int>(card.value(QStringLiteral("cmc")).toDouble());
        curve[std::min(cmc, CurveCap)] += qty;
        spellCmc += cmc * qty;
        spellCount += qty;
    }

    QVariantList curveOut;
    int curveMax = 0;
    for (int i = 0; i < curve.size(); ++i) {
        curveOut << QVariantMap{
            {QStringLiteral("cmc"), i},
            {QStringLiteral("label"), i == CurveCap ? QStringLiteral("%1+").arg(i)
                                                    : QString::number(i)},
            {QStringLiteral("count"), curve[i]}};
        curveMax = std::max(curveMax, curve[i]);
    }

    QVariantList typesOut;
    QStringList order = TypeOrder;
    order << QStringLiteral("Other");
    for (const QString &type : order) {
        if (types.value(type) != 0) {
            typesOut << QVariantMap{{QStringLiteral("type"), type},
                                    {QStringLiteral("count"), types.value(type)}};
        }
    }

    QVariantList pipsOut;
    int pipsTotal = 0;
    for (const QChar &c : kPipColors) {
        pipsOut << QVariantMap{{QStringLiteral("color"), QString(c)},
                               {QStringLiteral("count"), pips.value(c)}};
        pipsTotal += pips.value(c);
    }

    const double avgCmc = spellCount
        ? std::round(static_cast<double>(spellCmc) / spellCount * 100.0) / 100.0
        : 0.0;

    return {
        {QStringLiteral("total"), total},
        {QStringLiteral("lands"), lands},
        {QStringLiteral("avgCmc"), avgCmc},
        {QStringLiteral("curve"), curveOut},
        {QStringLiteral("curveMax"), curveMax},
        {QStringLiteral("types"), typesOut},
        {QStringLiteral("pips"), pipsOut},
        {QStringLiteral("pipsTotal"), pipsTotal},
    };
}

QString exportText(const QVariantList &cards, const QString &commanderId)
{
    QStringList lines;

    QVariantList commander, rest;
    for (const QVariant &entry : cards) {
        if (str(entry.toMap(), "id") == commanderId && !commanderId.isEmpty())
            commander << entry;
        else
            rest << entry;
    }

    if (!commander.isEmpty()) {
        lines << QStringLiteral("Commander")
              << QStringLiteral("1 ") + str(commander.first().toMap(), "name")
              << QString();
    }

    QStringList order = TypeOrder;
    order << QStringLiteral("Other");
    for (const QString &kind : order) {
        QVariantList group;
        for (const QVariant &entry : rest) {
            if (primaryType(entry.toMap()) == kind)
                group << entry;
        }
        if (group.isEmpty())
            continue;

        std::sort(group.begin(), group.end(), [](const QVariant &a, const QVariant &b) {
            return QString::compare(str(a.toMap(), "name"), str(b.toMap(), "name"),
                                    Qt::CaseInsensitive)
                   < 0;
        });

        int copies = 0;
        for (const QVariant &entry : group)
            copies += qtyOf(entry.toMap());

        lines << QStringLiteral("%1s (%2)").arg(kind).arg(copies);
        for (const QVariant &entry : group) {
            const QVariantMap card = entry.toMap();
            lines << QStringLiteral("%1 %2").arg(qtyOf(card)).arg(str(card, "name"));
        }
        lines << QString();
    }

    return lines.join(QLatin1Char('\n')).trimmed() + QLatin1Char('\n');
}

} // namespace DeckRules
