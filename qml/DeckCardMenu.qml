import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// The right-click menu on a card that is already in the open list.
//
// Separate from CardMenu on purpose: out in the gallery the question is "where
// does this card go", which is what CardMenu answers with its list ticks. Once
// a card is in your deck that question is settled, and what's left is what you
// want to say about it there — so this menu is about the entry, not the card.
Menu {
    id: menu

    property int listId: 0
    property string cardId: ""
    property string cardName: ""
    property string cardLabel: ""

    signal labelRequested()

    padding: 4
    background: RetroPanel { shadowOffset: 4 }

    // Same reason as CardMenu.fitWidth(): a Menu takes its width from its
    // background's implicit width, and RetroPanel is a plain Item with none —
    // left alone this collapses to its own padding. Measure the rows instead.
    readonly property int minWidth: 150
    function fitWidth() {
        var widest = 0
        for (var i = 0; i < count; i++) {
            var item = itemAt(i)
            if (item && item.shown !== false)
                widest = Math.max(widest, item.implicitWidth)
        }
        contentWidth = Math.max(minWidth, Math.ceil(widest))
    }

    function openFor(id, name, label) {
        listId = deckStore.activeId
        cardId = id
        cardName = name
        cardLabel = label || ""
        fitWidth()
        popup()
    }

    component PixelMenuItem: MenuItem {
        id: item
        property string sprite: ""
        // applies-at-all, as opposed to on-screen: fitWidth() measures while
        // the menu is still closed, when `visible` is false for every row
        property bool shown: true
        implicitHeight: 22

        visible: shown
        height: shown ? implicitHeight : 0

        implicitWidth: leftPadding + 16 + row.spacing
                       + label.implicitWidth + rightPadding

        background: Rectangle {
            color: item.highlighted ? Retro.blue : "transparent"
        }
        contentItem: Row {
            id: row
            spacing: 7
            Item {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                PixelIcon {
                    sprite: item.sprite
                    visible: item.sprite !== ""
                    opacity: item.enabled ? 1 : 0.45
                }
            }
            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: item.text
                font.pixelSize: Retro.body
                color: !item.enabled ? Retro.inkDim
                     : (item.highlighted ? Retro.black : Retro.ink)
            }
        }
    }

    component PixelSeparator: MenuSeparator {
        padding: 4
        contentItem: Rectangle { implicitHeight: 1; color: Retro.blue; opacity: 0.4 }
    }

    // which row you hit — a menu with one action on it still shouldn't leave
    // that in doubt
    PixelMenuItem {
        text: menu.cardName.length > 28
            ? menu.cardName.substring(0, 27) + "…" : menu.cardName
        enabled: false
    }

    PixelSeparator {}

    PixelMenuItem {
        sprite: "mtg-icon-check"
        text: menu.cardLabel === "" ? "Give label…" : "Edit label…"
        onTriggered: menu.labelRequested()
    }
}
