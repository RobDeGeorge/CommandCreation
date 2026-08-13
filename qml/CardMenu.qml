import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// The right-click menu on a card. Its middle section is rebuilt from
// deckStore.listsForCard() each time it opens, so the ticks always show which
// of your lists the card is already in.
Menu {
    id: menu

    property string cardId: ""
    property string cardName: ""
    property string cardImage: ""
    property string cardBackImage: ""     // "" unless the card is double-faced
    property string cardRarity: ""
    property bool canBeCommander: false
    property bool showRemove: false      // true when opened from inside a list
    // False when the card is already on screen at full size — the menu is
    // being opened from the enlarged view itself, where a row offering to show
    // you what you are looking at is one row of noise on a phone's worth of
    // space. Every other row applies exactly as it does out in the gallery.
    property bool showView: true
    property var listRows: []

    signal viewRequested()
    signal newListRequested()

    padding: 4
    background: RetroPanel { shadowOffset: 4 }

    // A Menu takes its width from its background's implicit width — the stock
    // one hard-codes 200 — because the ListView it uses for content never
    // measures its delegates. RetroPanel is a plain Item with no implicit size,
    // so left alone this menu collapses to the 8px of its own padding. Measure
    // the rows ourselves instead, which also means the plate ends up as wide as
    // the longest list name rather than a fixed guess.
    readonly property int minWidth: 150
    function fitWidth() {
        var widest = 0
        for (var i = 0; i < count; i++) {
            var item = itemAt(i)
            // `shown`, not `visible`: this runs before popup(), so nothing is
            // on screen yet and every item's visible is still false
            if (item && item.shown !== false)
                widest = Math.max(widest, item.implicitWidth)
        }
        contentWidth = Math.max(minWidth, Math.ceil(widest))
    }

    // pull fresh membership, then show — cheap enough to do per open
    //
    // The last two are for the enlarged view and can be left off everywhere
    // else: `viewable` false drops the "View …" row, and `anchor` is an item
    // to hang the menu under instead of putting it at the pointer. Without an
    // anchor a Menu opens where the cursor is, which is the right answer for a
    // right-click and no answer at all for a button pressed with a finger —
    // there is no cursor on a phone, so the position is wherever the mouse
    // last was, i.e. the top-left corner.
    function openFor(id, name, commanderEligible, fromList, image, rarity,
                     backImage, viewable, anchor) {
        cardId = id
        cardName = name
        cardImage = image || ""
        cardBackImage = backImage || ""
        cardRarity = rarity || ""
        canBeCommander = commanderEligible === true
        showRemove = fromList === true
        showView = viewable !== false
        listRows = deckStore.listsForCard(id)
        // every label and every row is settled by now, so this is the one
        // moment the widths are worth measuring
        fitWidth()
        if (anchor)
            // just under the button, and shifted left by the difference in
            // widths so a menu wider than its button still lands on screen
            popup(anchor, Math.min(0, anchor.width - width), anchor.height)
        else
            popup()
    }

    // A row on the overlay plate, with one of the 16px sprites in the gutter.
    // The gutter is reserved whether or not a row has an icon, so the labels
    // still line up down the menu.
    component PixelMenuItem: MenuItem {
        id: item
        property string sprite: ""
        // whether this row applies to the card at all, as opposed to whether
        // it happens to be on screen — fitWidth() measures while the menu is
        // still closed, when `visible` is false for every row alike
        property bool shown: true
        implicitHeight: 22

        visible: shown
        height: shown ? implicitHeight : 0

        // Say how wide we want to be rather than letting the control infer it
        // from contentItem: that inference lands a frame late, and fitWidth()
        // has to read these the moment the menu is built. Straight off the
        // label it is exact and immediate.
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

    PixelMenuItem {
        sprite: "mtg-icon-search"
        text: "View " + (menu.cardName.length > 28
              ? menu.cardName.substring(0, 27) + "…" : menu.cardName)
        shown: menu.showView
        onTriggered: menu.viewRequested()
    }

    PixelSeparator { visible: menu.showView }

    PixelMenuItem {
        text: "Add to list…"
        enabled: false                    // section heading
    }

    // one row per list; clicking toggles the card in or out of it
    Instantiator {
        model: menu.listRows
        delegate: PixelMenuItem {
            sprite: modelData.contains ? "mtg-icon-check" : ""
            text: modelData.name + "   (" + modelData.count + ")"
            onTriggered: deckStore.toggleCard(modelData.id, menu.cardId)
        }
        onObjectAdded: (index, object) => menu.insertItem(index + 3, object)
        onObjectRemoved: (index, object) => menu.removeItem(object)
    }

    PixelMenuItem {
        sprite: "mtg-icon-plus"
        text: "New list…"
        onTriggered: menu.newListRequested()
    }

    PixelSeparator { visible: menu.canBeCommander || menu.showRemove }

    PixelMenuItem {
        sprite: "mtg-icon-commander"
        text: "Set as commander of " + (deckStore.activeName || "the open list")
        shown: menu.canBeCommander && deckStore.activeId > 0
        onTriggered: deckStore.setCommander(deckStore.activeId, menu.cardId)
    }

    PixelMenuItem {
        sprite: "mtg-icon-minus"
        text: "Remove from " + deckStore.activeName
        shown: menu.showRemove && deckStore.activeId > 0
        onTriggered: deckStore.removeCard(deckStore.activeId, menu.cardId)
    }
}
