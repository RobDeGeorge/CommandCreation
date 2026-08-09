#pragma once

#include "Db.h"

#include <QAbstractListModel>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// The role names QML reads a card by, and the database column each one comes
// from. DeckModel extends both lists rather than restating them, so a column
// added here reaches the deck dock too.
namespace CardRoles {
extern const QStringList Names;
extern const QHash<QString, QString> ToColumn;
} // namespace CardRoles

// Qt list model exposing card search results to QML.
//
// Filter state lives in a single map driven through setFilter(), so any
// frontend controls the search through one uniform API. See Db::search for the
// recognized keys.
class CardModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QVariantList sets READ sets CONSTANT)
    Q_PROPERTY(QVariantList artists READ artists CONSTANT)
    Q_PROPERTY(QVariantList types READ types CONSTANT)
    Q_PROPERTY(QVariantList subtypes READ subtypes CONSTANT)
    Q_PROPERTY(QVariantList years READ years CONSTANT)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString previewImage READ previewImage NOTIFY previewChanged)
    Q_PROPERTY(QString previewName READ previewName NOTIFY previewChanged)
    Q_PROPERTY(QString previewFrame READ previewFrame NOTIFY previewChanged)
    Q_PROPERTY(QString previewRarity READ previewRarity NOTIFY previewChanged)

public:
    // Rows are fetched a page at a time as the view scrolls. Materialising the
    // whole pool costs about half a second — most of it in building the rows —
    // and every filter change paid it, which is what made typing an artist's
    // name feel like wading.
    static constexpr int Page = 400;

    explicit CardModel(Db *db, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role) const override;
    bool canFetchMore(const QModelIndex &parent) const override;
    void fetchMore(const QModelIndex &parent) override;

    QVariantList sets();
    QVariantList artists();
    QVariantList types();
    QVariantList subtypes();
    QVariantList years();
    int count() const { return m_total; }
    QString previewImage() const;
    QString previewName() const;
    QString previewFrame() const;
    QString previewRarity() const;

    // Set one filter key; blank values clear it. Debounced.
    Q_INVOKABLE void setFilter(const QString &key, const QVariant &value);
    Q_INVOKABLE void clearFilters();

    // One of "name", "cmc", "edhrec", "set", "rarity".
    Q_INVOKABLE void setSortOrder(const QString &sort);
    Q_INVOKABLE void setSortDescending(bool descending);

signals:
    void countChanged();
    void previewChanged();

private:
    QVariantList query(int offset);
    void refresh();

    Db *m_db;
    QVariantList m_rows;
    int m_total = 0;         // rows matching the filters, not rows loaded
    QVariantMap m_preview;   // one card the filters match; see Db::previewCard
    QVariantMap m_filters;
    QString m_sort = QStringLiteral("name");
    bool m_sortDescending = false;
    QTimer m_debounce;

    // The vocabulary lists are each one scan of the pool, so they are built on
    // first ask and kept.
    QVariantList m_sets, m_artists, m_types, m_subtypes, m_years;
};
