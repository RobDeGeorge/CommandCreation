#include "DeckIo.h"
#include "DeckRules.h"

#include <QRegularExpression>
#include <QSet>
#include <QVariantMap>

#include <algorithm>

namespace DeckIo {

namespace {

// Whole-line section headings, however they are punctuated.
const QHash<QString, QString> kSections = {
    {"commander", "commander"},   {"commanders", "commander"},
    {"deck", "main"},             {"mainboard", "main"},
    {"main", "main"},             {"maindeck", "main"},
    {"sideboard", "sideboard"},   {"sb", "sideboard"},
    {"maybeboard", "maybeboard"}, {"maybe", "maybeboard"},
    {"considering", "maybeboard"},
    {"companion", "companion"},
    {"tokens", "tokens"},         {"token", "tokens"},
};

const QSet<QString> kKeptSections = {"commander", "main", "companion"};

const QRegularExpression &qtyPattern()
{
    static const QRegularExpression re(QStringLiteral("^(\\d+)\\s*[xX]?\\s+(?=\\S)"));
    return re;
}

const QRegularExpression &setSuffixPattern()
{
    static const QRegularExpression re(
        QStringLiteral("\\s*\\(([^)]{1,10})\\)(?:\\s+([A-Za-z0-9\\-★]+))?\\s*$"));
    return re;
}

const QRegularExpression &trailingTagPattern()
{
    static const QRegularExpression re(
        QStringLiteral("\\s*(?:\\*[^*]*\\*|\\[[^\\]]*\\]|\\^[^^]*\\^)\\s*$"));
    return re;
}

const QRegularExpression &whitespacePattern()
{
    static const QRegularExpression re(QStringLiteral("\\s+"));
    return re;
}

// Normalise a name for matching: case, accents, apostrophes, spacing.
QString fold(const QString &text)
{
    const QString decomposed = text.normalized(QString::NormalizationForm_KD);
    QString stripped;
    stripped.reserve(decomposed.size());
    for (const QChar &c : decomposed) {
        switch (c.category()) {
        case QChar::Mark_NonSpacing:
        case QChar::Mark_SpacingCombining:
        case QChar::Mark_Enclosing:
            continue; // an accent that folded off its letter
        default:
            stripped += c;
        }
    }
    stripped.replace(QChar(0x2019), QLatin1Char('\''));  // ’
    stripped.replace(QChar(0x2018), QLatin1Char('\''));  // ‘
    stripped.replace(QChar(0x201C), QLatin1Char('"'));   // “
    stripped.replace(QChar(0x201D), QLatin1Char('"'));   // ”
    stripped.replace(QChar(0x2014), QLatin1Char('-'));   // —
    stripped.replace(QChar(0x2013), QLatin1Char('-'));   // –
    return stripped.replace(whitespacePattern(), QStringLiteral(" ")).trimmed().toLower();
}

// The front half of a double-faced name, or empty if it isn't one.
QString frontFace(const QString &name)
{
    const int at = name.indexOf(QStringLiteral(" // "));
    if (at < 0)
        return QString();
    return name.left(at).trimmed();
}

QString str(const QVariantMap &card, const char *key)
{
    return card.value(QLatin1String(key)).toString();
}

// Strip every trailing character in `chars`, the way Python's str.rstrip does.
QString rstrip(QString text, QChar c)
{
    while (text.endsWith(c))
        text.chop(1);
    return text;
}

QString stripCommas(QString text)
{
    while (text.startsWith(QLatin1Char(',')))
        text.remove(0, 1);
    while (text.endsWith(QLatin1Char(',')))
        text.chop(1);
    return text;
}

} // namespace

bool isKeptSection(const QString &section)
{
    return kKeptSections.contains(section);
}

Parsed parse(const QString &text)
{
    Parsed result;
    QString section = QStringLiteral("main");

    const QStringList rawLines = text.split(QLatin1Char('\n'));
    for (int number = 1; number <= rawLines.size(); ++number) {
        const QString raw = rawLines.at(number - 1);
        QString line = raw.trimmed();
        if (line.isEmpty())
            continue;

        // A leading marker is a comment; " // " inside a line is a card name.
        bool marked = false;
        if (line.startsWith(QStringLiteral("//"))) {
            marked = true;
            line = line.mid(2).trimmed();
        } else if (line.startsWith(QLatin1Char('#')) && !line.startsWith(QStringLiteral("#!"))) {
            marked = true;
            line = line.mid(1).trimmed();
        }
        if (marked && line.isEmpty())
            continue;

        const QString heading = kSections.value(rstrip(fold(line), QLatin1Char(':')));
        if (!heading.isEmpty()) {
            section = heading;
            continue;
        }
        if (marked)
            continue; // an ordinary comment

        QString entrySection = section;
        static const QRegularExpression sbPrefix(
            QStringLiteral("^sb:\\s*"), QRegularExpression::CaseInsensitiveOption);
        if (line.contains(sbPrefix)) {
            line.remove(sbPrefix);
            entrySection = QStringLiteral("sideboard");
        }

        int qty = 1;
        const QRegularExpressionMatch qtyMatch = qtyPattern().match(line);
        if (qtyMatch.hasMatch()) {
            qty = std::max(1, qtyMatch.captured(1).toInt());
            line = line.mid(qtyMatch.capturedEnd());
        }

        // Decorations come off the tail: tags first, then the set/number.
        bool commander = false;
        while (true) {
            const QRegularExpressionMatch tag = trailingTagPattern().match(line);
            if (!tag.hasMatch())
                break;
            const QString body = tag.captured(0).toLower();
            if (body.contains(QStringLiteral("cmdr")) || body.contains(QStringLiteral("commander")))
                commander = true;
            line = line.left(tag.capturedStart());
            while (line.endsWith(QLatin1Char(' ')) || line.endsWith(QLatin1Char('\t')))
                line.chop(1);
        }

        QString setCode, collector;
        const QRegularExpressionMatch suffix = setSuffixPattern().match(line);
        if (suffix.hasMatch()) {
            setCode = suffix.captured(1);
            collector = suffix.captured(2);
            line = line.left(suffix.capturedStart());
            while (line.endsWith(QLatin1Char(' ')) || line.endsWith(QLatin1Char('\t')))
                line.chop(1);
        }

        const QString name = stripCommas(line.trimmed()).trimmed();
        if (name.isEmpty()) {
            result.notes << QStringLiteral("line %1: couldn't read '%2'")
                                .arg(number)
                                .arg(raw.trimmed());
            continue;
        }

        Entry entry;
        entry.qty = qty;
        entry.name = name;
        entry.set = setCode;
        entry.number = collector;
        entry.section = entrySection;
        entry.commander = commander || entrySection == QLatin1String("commander");
        entry.line = number;
        result.entries << entry;
    }

    return result;
}

QHash<QString, QString> buildIndex(const QList<QPair<QString, QString>> &cards)
{
    QHash<QString, QString> index;
    QHash<QString, QString> aliases;
    index.reserve(cards.size());

    for (const auto &card : cards) {
        const QString &cardId = card.first;
        const QString &name = card.second;
        index.insert(fold(name), cardId);
        const QString front = frontFace(name);
        if (!front.isEmpty()) {
            const QString key = fold(front);
            if (!aliases.contains(key))
                aliases.insert(key, cardId);
        }
    }
    // A front-face alias never displaces a real card of that name: if some
    // card is actually called "Aberrant Researcher", it wins.
    for (auto it = aliases.constBegin(); it != aliases.constEnd(); ++it) {
        if (!index.contains(it.key()))
            index.insert(it.key(), it.value());
    }
    return index;
}

Resolved resolve(const QHash<QString, QString> &index, const QList<Entry> &entries)
{
    Resolved result;
    QHash<QString, int> seen; // card id -> position in result.matched

    for (const Entry &entry : entries) {
        const QString cardId = index.value(fold(entry.name));
        if (cardId.isEmpty()) {
            result.unmatched << entry;
            continue;
        }
        if (seen.contains(cardId)) {
            Match &slot = result.matched[seen.value(cardId)];
            slot.qty = std::max(slot.qty, entry.qty);
            slot.commander = slot.commander || entry.commander;
            // A card listed in two sections keeps the one that would be kept —
            // a maybeboard mention shouldn't demote a card that is also in the
            // deck.
            if (!isKeptSection(slot.section))
                slot.section = entry.section;
            continue;
        }
        Match slot;
        slot.cardId = cardId;
        slot.qty = entry.qty;
        slot.commander = entry.commander;
        slot.name = entry.name;
        slot.section = entry.section;
        seen.insert(cardId, result.matched.size());
        result.matched << slot;
    }
    return result;
}

QString exportText(const QVariantList &cards, const QString &commanderId, const QString &style)
{
    if (style == QLatin1String("annotated"))
        return DeckRules::exportText(cards, commanderId);

    QVariantList commander, rest;
    for (const QVariant &entry : cards) {
        if (!commanderId.isEmpty() && str(entry.toMap(), "id") == commanderId)
            commander << entry;
        else
            rest << entry;
    }
    std::sort(rest.begin(), rest.end(), [](const QVariant &a, const QVariant &b) {
        return QString::compare(str(a.toMap(), "name"), str(b.toMap(), "name"),
                                Qt::CaseInsensitive)
               < 0;
    });

    const auto line = [](const QVariant &entry) {
        const QVariantMap card = entry.toMap();
        return QStringLiteral("%1 %2")
            .arg(card.value(QStringLiteral("qty")).toInt())
            .arg(str(card, "name"));
    };

    QStringList lines;
    if (style == QLatin1String("moxfield")) {
        if (!commander.isEmpty()) {
            lines << QStringLiteral("Commander");
            for (const QVariant &entry : commander)
                lines << line(entry);
            lines << QString() << QStringLiteral("Deck");
        }
        for (const QVariant &entry : rest)
            lines << line(entry);
    } else { // plain
        for (const QVariant &entry : commander)
            lines << line(entry);
        for (const QVariant &entry : rest)
            lines << line(entry);
    }

    return lines.join(QLatin1Char('\n')).trimmed() + QLatin1Char('\n');
}

QString deckNameFrom(const QString &text, const QString &fallback)
{
    // Deckstats and a few exporters lead with "//NAME: Something"; otherwise
    // the caller's fallback stands.
    static const QRegularExpression namePattern(
        QStringLiteral("^(?://|#)\\s*(?:name|deck)\\s*:\\s*(.+)$"),
        QRegularExpression::CaseInsensitiveOption);

    const QStringList lines = text.split(QLatin1Char('\n'));
    const int limit = std::min(5, static_cast<int>(lines.size()));
    for (int i = 0; i < limit; ++i) {
        const QRegularExpressionMatch match = namePattern.match(lines.at(i).trimmed());
        if (match.hasMatch()) {
            const QString name = match.captured(1).trimmed();
            return name.isEmpty() ? fallback : name;
        }
    }
    return fallback;
}

} // namespace DeckIo
