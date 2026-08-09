#pragma once

#include "Db.h"

#include <QAbstractListModel>
#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class DeckStore;

// The role names the sidebar reads a list by.
extern const QStringList ListRoles;
// A deck row is a card row plus what the entry adds to it.
extern const QStringList DeckExtraRoles;

// Every list you've made, for the sidebar.
class ListsModel : public QAbstractListModel
{
    Q_OBJECT
public:
    explicit ListsModel(DeckStore *store);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role) const override;

    void reload(const QVariantList &rows);
    void refreshActiveFlags();
    const QVariantList &rows() const { return m_rows; }

private:
    DeckStore *m_store;
    QVariantList m_rows;
};

// The cards inside the open list.
//
// Two views of the same rows, deliberately:
//
//   rows()      every card, commander included. The commander is a card in the
//               deck — it counts toward the hundred and it belongs in the
//               export — so the stats and the rule check read this.
//   the model   everything except the commander. It already has a slot of its
//               own above the list, and listing it twice makes a one-card deck
//               look like two.
class DeckModel : public QAbstractListModel
{
    Q_OBJECT
    // Copies per type, for the heading above each group: {"Creature": 25, ...}.
    // Counted off the rows the view actually draws, not off stats(), which
    // includes the commander — a deck led by a creature would otherwise claim
    // one more creature than it lists.
    Q_PROPERTY(QVariantMap typeCounts READ typeCounts NOTIFY typeCountsChanged)

public:
    explicit DeckModel(DeckStore *store);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role) const override;

    void reload(const QVariantList &rows);
    const QVariantList &rows() const { return m_rows; }
    QVariantMap typeCounts() const { return m_typeCounts; }

signals:
    void typeCountsChanged();

private:
    QVariantList m_rows;    // all of them
    QVariantList m_visible; // ...minus the commander
    QVariantMap m_typeCounts;
};

// The single object QML talks to. It owns the two models — the sidebar of
// lists and the contents of whichever list is open — and every mutation goes
// through one of its slots, so the database, both models and the derived stats
// can never drift apart.
class DeckStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *lists READ listsModel CONSTANT)
    Q_PROPERTY(QObject *deck READ deckModel CONSTANT)
    Q_PROPERTY(int activeId READ activeId NOTIFY activeChanged)
    Q_PROPERTY(QString activeName READ activeName NOTIFY activeChanged)
    Q_PROPERTY(QString activeKind READ activeKind NOTIFY activeChanged)
    Q_PROPERTY(bool isDeck READ isDeck NOTIFY activeChanged)
    Q_PROPERTY(QString commanderId READ commanderId NOTIFY activeChanged)
    Q_PROPERTY(QString commanderName READ commanderName NOTIFY activeChanged)
    Q_PROPERTY(QString commanderIdentity READ commanderIdentity NOTIFY activeChanged)
    Q_PROPERTY(QString commanderArt READ commanderArt NOTIFY activeChanged)
    // The rest of the commander's card, for the seat: its printed cost, and
    // what the enlarged view needs to show it the way a row in the list does.
    Q_PROPERTY(QString commanderMana READ commanderMana NOTIFY activeChanged)
    Q_PROPERTY(QString commanderRarity READ commanderRarity NOTIFY activeChanged)
    Q_PROPERTY(QString commanderImage READ commanderImage NOTIFY activeChanged)
    Q_PROPERTY(QString commanderBack READ commanderBack NOTIFY activeChanged)
    Q_PROPERTY(QVariantMap stats READ stats NOTIFY contentsChanged)
    Q_PROPERTY(QVariantList problems READ problems NOTIFY contentsChanged)
    Q_PROPERTY(QVariantList illegalCardIds READ illegalCardIds NOTIFY contentsChanged)
    Q_PROPERTY(QVariantList activeCardIds READ activeCardIds NOTIFY contentsChanged)

public:
    explicit DeckStore(Db *db, QObject *parent = nullptr);

    QObject *listsModel() const { return m_lists; }
    QObject *deckModel() const { return m_deck; }

    int activeId() const { return m_activeId; }
    QString activeName() const;
    QString activeKind() const;
    bool isDeck() const;
    QString commanderId() const;
    QString commanderName() const;
    QString commanderIdentity() const;
    QString commanderArt() const;
    QString commanderMana() const;
    QString commanderRarity() const;
    QString commanderImage() const;
    QString commanderBack() const;

    QVariantMap stats() const;
    QVariantList problems() const;
    QVariantList illegalCardIds() const;
    QVariantList activeCardIds() const;

    // -- list management ----------------------------------------------------
    // `kind` is "list" or "deck" — chosen when the list is named.
    Q_INVOKABLE int createList(const QString &name,
                               const QString &kind = QStringLiteral("list"));
    Q_INVOKABLE void renameList(int listId, const QString &name);
    Q_INVOKABLE void deleteList(int listId);
    Q_INVOKABLE void duplicateList(int listId, const QString &name);
    Q_INVOKABLE void setActive(int listId);

    // -- cards in lists -----------------------------------------------------
    Q_INVOKABLE void addCard(int listId, const QString &cardId, int qty = 1);
    Q_INVOKABLE void addToActive(const QString &cardId);
    Q_INVOKABLE void removeCard(int listId, const QString &cardId);
    Q_INVOKABLE void setQty(int listId, const QString &cardId, int qty);
    // One click adds; clicking the same list again takes it back out.
    Q_INVOKABLE void toggleCard(int listId, const QString &cardId);
    // The label a card wears inside one list. Empty clears it.
    Q_INVOKABLE void setCardLabel(int listId, const QString &cardId, const QString &label);
    Q_INVOKABLE QString cardLabel(int listId, const QString &cardId);
    // [{id, name, kind, count, contains}] — what the right-click menu renders.
    Q_INVOKABLE QVariantList listsForCard(const QString &cardId);

    // -- commander ----------------------------------------------------------
    Q_INVOKABLE void setCommander(int listId, const QString &cardId);
    Q_INVOKABLE void clearCommander(int listId);
    Q_INVOKABLE void promoteToDeck(int listId);
    // Turn a deck back into a plain list. The commander is kept, not cleared:
    // this only stops the Commander rules being checked, and going back and
    // forth shouldn't cost you the commander you chose.
    Q_INVOKABLE void demoteToList(int listId);

    // -- export and import --------------------------------------------------
    Q_INVOKABLE QString exportText(const QString &style = QStringLiteral("moxfield"));
    // Read a pasted list without changing anything, so the dialog can show
    // what will happen before the user commits to it.
    Q_INVOKABLE QVariantMap previewImport(const QString &text);
    // Bring a pasted deck list in. Returns the list id, 0 on failure.
    Q_INVOKABLE int importText(const QString &text, const QString &name,
                               bool intoActive = false);

    Q_INVOKABLE void setSortOrder(const QString &sort);

signals:
    void listsChanged();
    void activeChanged();
    void contentsChanged();
    // Something the user should see said back to them: a duplicate name, a
    // card added, a deck exported.
    void notified(const QString &message);

private:
    void reloadLists();
    void reloadActive();
    // Counts in the sidebar, and the open list if it was the one touched.
    void afterChange(int listId);

    Db *m_db;
    int m_activeId = 0;
    QVariantMap m_list; // the open list's row, or empty
    ListsModel *m_lists;
    DeckModel *m_deck;
    QString m_sort = QStringLiteral("cmc");

    friend class ListsModel;
};
