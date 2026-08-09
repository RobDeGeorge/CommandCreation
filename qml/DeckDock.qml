import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "Retro.js" as Retro

// The right-hand workspace: your lists on top, the open one below it, and the
// deck's vital signs — curve, types, colours, rule breaks — under that.
Rectangle {
    id: dock
    color: "#c8c8cc"

    // asked for by a row's context menu; Main.qml owns the dialogs
    signal renameRequested(int listId, string currentName)
    signal duplicateRequested(int listId, string currentName)
    signal deleteRequested(int listId, string currentName)
    signal newListRequested()
    signal exportRequested()
    signal importRequested()
    signal cardActivated(string cardId, string imageUrl, string cardName,
                         string rarity, string backImageUrl)
    // A card in the open list gets its own menu — see DeckCardMenu.qml for why
    // it isn't the gallery's CardMenu.
    signal deckCardMenuRequested(string cardId, string cardName, string label)

    readonly property var identityColors: ({
        W: "#f4efd2", U: "#a8cbe4", B: "#6e6663", R: "#df7d5a", G: "#7fae74"
    })

    function pipColor(letter) {
        return identityColors[letter] || "#b8b2a8"
    }

    // Rows are tinted by colour identity, not by the mana cost: identity is
    // what the deck is actually built around — it's what the commander gates
    // and what the pip bar below counts — and it's the only reading under
    // which a Swamp and a black spell belong to the same colour.
    // deeper than it looks like it needs to be: at the wash opacity a row
    // uses, anything lighter comes out as the panel and an artifact stops
    // reading as a row at all
    readonly property string colorlessTint: "#b5b2ac"
    readonly property string wubrg: "WUBRG"

    // The colours a row blends through, left to right — one entry per colour
    // in the card's identity. Gold is the printed convention for multicolour,
    // but a gold row only says "more than one": blending the actual colours
    // says which, so a Golgari row and an Izzet row don't look alike.
    //
    // Always at least two entries, so the caller can treat every row the same
    // way; a mono card just blends a colour into itself. The database stores
    // identities alphabetically (BGRUW), so put them back in WUBRG order — a
    // Dimir card reading blue-then-black is how a player would say it.
    function rowColors(identity) {
        var out = []
        for (var i = 0; i < wubrg.length; i++)
            if ((identity || "").indexOf(wubrg[i]) !== -1)
                out.push(pipColor(wubrg[i]))
        if (out.length === 0)
            return [colorlessTint, colorlessTint]
        if (out.length === 1)
            return [out[0], out[0]]
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // ---- your lists --------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            // No heading: the picker below is the panel's subject and says so
            // by naming the open list. The two buttons keep the right edge they
            // had, so nothing moves out from under the pointer.
            Item { Layout.fillWidth: true }
            PixelButton {
                sprite: "mtg-btn-import"
                pixelScale: 2
                tooltip: "Paste a deck list in"
                onClicked: dock.importRequested()
            }
            PixelButton {
                sprite: "mtg-btn-new-list"
                pixelScale: 2
                onClicked: dock.newListRequested()
            }
        }

        // Which list is open, as a dropdown rather than a standing list.
        // The sidebar only ever answered one question — which one is active —
        // and a scroll box spends the panel's height answering it permanently.
        // A dropdown answers it in one line and gives the height back to the
        // deck you are actually working on.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RetroCombo {
                id: listPicker
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                model: deckStore.lists
                textRole: "name"
                valueRole: "listId"
                enabled: count > 0
                onActivated: deckStore.setActive(currentValue)

                // The open list can change from anywhere — importing, the card
                // menu, deleting one — so the picker follows the store rather
                // than owning the choice. Set imperatively, not bound:
                // ComboBox reassigns currentIndex itself whenever the model
                // resets, which silently breaks a declarative binding and
                // leaves the field blank.
                function syncToStore() {
                    currentIndex = indexOfValue(deckStore.activeId)
                }
                Component.onCompleted: syncToStore()
                onCountChanged: syncToStore()
                Connections {
                    target: deckStore
                    function onActiveChanged() { listPicker.syncToStore() }
                    function onListsChanged() { listPicker.syncToStore() }
                }

                // the closed field says the same things a row does, so opening
                // it doesn't change the vocabulary
                contentItem: RowLayout {
                    spacing: 5
                    anchors.leftMargin: 6
                    PixelIcon {
                        Layout.leftMargin: 6
                        visible: deckStore.activeId > 0
                        sprite: deckStore.isDeck ? "mtg-icon-commander"
                                                 : "mtg-icon-list"
                        on: deckStore.isDeck
                            && deckStore.commanderIdentity.length > 0
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.rightMargin: 24
                        text: deckStore.activeId > 0 ? deckStore.activeName
                                                     : "No list open"
                        elide: Text.ElideRight
                        font.pixelSize: Retro.body
                        color: deckStore.activeId > 0 ? Retro.ink : Retro.inkDim
                    }
                }

                // deckStore.lists is a QAbstractListModel, so its rows arrive
                // as roles rather than as modelData — RetroCombo's own delegate
                // can't read them
                delegate: ItemDelegate {
                    id: pickerRow
                    required property int index
                    required property string name
                    required property string kind
                    required property int cardCount
                    required property string commanderName
                    required property string commanderIdentity
                    width: ListView.view.width
                    height: 30
                    highlighted: listPicker.highlightedIndex === index

                    background: Rectangle {
                        color: pickerRow.highlighted ? Retro.blue : "transparent"
                    }
                    contentItem: RowLayout {
                        spacing: 5
                        PixelIcon {
                            sprite: pickerRow.kind === "deck" ? "mtg-icon-commander"
                                                              : "mtg-icon-list"
                            on: pickerRow.kind === "deck"
                                && pickerRow.commanderIdentity.length > 0
                        }
                        Row {
                            spacing: 1
                            Repeater {
                                model: pickerRow.commanderIdentity.length > 0
                                     ? pickerRow.commanderIdentity.split("") : []
                                delegate: PixelIcon {
                                    sprite: "mtg-pip-" + modelData.toLowerCase()
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: pickerRow.name
                                elide: Text.ElideRight
                                font.pixelSize: Retro.body
                                color: pickerRow.highlighted ? Retro.black : Retro.ink
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: pickerRow.commanderName !== ""
                                text: pickerRow.commanderName
                                elide: Text.ElideRight
                                font.pixelSize: Retro.small
                                color: pickerRow.highlighted ? Retro.darkblue
                                                             : Retro.inkDim
                            }
                        }
                        Label {
                            text: pickerRow.cardCount
                            font.pixelSize: Retro.body
                            color: pickerRow.highlighted ? Retro.black : Retro.inkDim
                        }
                    }
                }
            }

            Label {
                visible: deckStore.activeId > 0
                text: deckStore.isDeck
                    ? deckStore.stats.total + "/100"
                    : deckStore.stats.total
                      + (deckStore.stats.total === 1 ? " card" : " cards")
                font.pixelSize: Retro.body
                color: "#5c5c66"
            }

            // how the open list is ordered, next to which list is open
            RetroCombo {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 30
                visible: deckStore.activeId > 0
                model: ["Cost", "Name", "Rarity"]
                onActivated: deckStore.setSortOrder(
                    ["cmc", "name", "rarity"][currentIndex])
            }

            // rename / duplicate / delete used to hang off a right-click on the
            // row; with the rows gone it needs a door of its own
            PixelButton {
                id: listMenuButton
                sprite: "mtg-icon-more"
                pixelScale: 2
                enabled: deckStore.activeId > 0
                tooltip: "Rename, duplicate or delete this list"
                onClicked: {
                    listActions.listId = deckStore.activeId
                    listActions.listName = deckStore.activeName
                    var p = listMenuButton.mapToItem(dock, 0, listMenuButton.height + 4)
                    listActions.x = Math.max(
                        6, Math.min(p.x, dock.width - listActions.width - 6))
                    listActions.y = p.y
                    listActions.open()
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: listPicker.count === 0
            horizontalAlignment: Text.AlignHCenter
            text: "No lists yet — right-click any card, or hit + New."
            wrapMode: Text.Wrap
            color: "#7c7c85"
            font.pixelSize: Retro.body
        }

        // ---- the open list ----------------------------------------------
        // No heading: the dropdown above already names it, and the name printed
        // twice reads as two different things.

        // Commander seat. Decks only: a plain list has no commander to seat,
        // and an empty slot on one reads as something you forgot to fill in
        // rather than something that doesn't apply. Naming a commander is what
        // turns a list into a deck (db.set_commander), so the seat appears the
        // moment there is anywhere for it to appear.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            visible: deckStore.activeId > 0 && deckStore.isDeck
            radius: 6
            color: "#b9b9c1"
            border.color: deckStore.commanderId !== "" ? "#8b48d8" : "#a0a0a8"
            border.width: deckStore.commanderId !== "" ? 2 : 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 8
                PixelIcon {
                    sprite: "mtg-icon-commander"
                    on: deckStore.commanderId !== ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: "Commander"
                        font.pixelSize: Retro.body
                        color: "#5c5c66"
                    }
                    Label {
                        Layout.fillWidth: true
                        text: deckStore.commanderName !== ""
                            ? deckStore.commanderName
                            : "No commander selected"
                        elide: Text.ElideRight
                        font.pixelSize: Retro.body
                        color: deckStore.commanderName !== "" ? "#2e2e34" : "#7c7c85"
                    }
                }
                Row {
                    spacing: 2
                    Repeater {
                        model: deckStore.commanderIdentity.split("")
                        delegate: PixelIcon {
                            sprite: "mtg-pip-" + modelData.toLowerCase()
                        }
                    }
                }
                PixelButton {
                    sprite: "mtg-icon-close"
                    pixelScale: 1
                    visible: deckStore.commanderId !== ""
                    tooltip: "Clear commander"
                    onClicked: deckStore.clearCommander(deckStore.activeId)
                }
            }
        }

        // ---- the cards in it ---------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            color: "#dededf"
            radius: 6
            border.color: "#b0b0b6"

            Label {
                anchors.centerIn: parent
                width: parent.width - 30
                visible: deckView.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: deckStore.activeId > 0
                    ? "Empty. Right-click cards in the grid to add them here."
                    : "Pick a list above to open it."
                color: "#7c7c85"
                font.pixelSize: Retro.body
            }

            ListView {
                id: deckView
                anchors.fill: parent
                anchors.margins: 2
                clip: true
                model: deckStore.deck
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                // group header whenever the card type changes
                section.property: "primaryType"
                section.criteria: ViewSection.FullString
                section.delegate: Rectangle {
                    width: deckView.width
                    height: 20
                    color: "#cccccf"
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        text: section
                        font.pixelSize: Retro.body
                        color: "#5c5c66"
                    }
                }

                delegate: Rectangle {
                    id: cardRow
                    width: deckView.width
                    height: 32          // the art thumbnail plus a little air
                    color: cardHover.hovered ? "#eceded" : "transparent"
                    HoverHandler { id: cardHover }

                    // A card that breaks a rule — outside the commander's
                    // colour identity, or a second copy of a singleton —
                    // beats red until you deal with it. The rule text below
                    // says what is wrong; this says which row it means, which
                    // a list of names in a sentence can't.
                    readonly property bool illegal:
                        deckStore.illegalCardIds.indexOf(cardId) !== -1

                    readonly property var tint: dock.rowColors(colorIdentity)

                    // The row's own colour. Held to a wash rather than the full
                    // pip colour: a hundred saturated bars is a colour chart,
                    // and what you want to see down the list is the shape of
                    // the deck, with the names still the loudest thing on it.
                    //
                    // One band per gap between colours, each blending its pair,
                    // so a card wears its whole identity across the row. A
                    // Gradient can't take a variable number of stops, so the
                    // bands are laid out by hand; rounding both edges off the
                    // same expression keeps them flush with no seam.
                    Item {
                        anchors.fill: parent
                        opacity: cardHover.hovered ? 0.72 : 0.5
                        Behavior on opacity { NumberAnimation { duration: 90 } }

                        Repeater {
                            model: cardRow.tint.length - 1
                            delegate: Rectangle {
                                id: band
                                required property int index
                                readonly property int bands:
                                    cardRow.tint.length - 1
                                x: Math.round(band.index * cardRow.width / bands)
                                width: Math.round(
                                    (band.index + 1) * cardRow.width / bands) - x
                                height: cardRow.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    // a GradientStop's parent is the Gradient,
                                    // so reach the band by id, not by parent
                                    GradientStop {
                                        position: 0.0
                                        color: cardRow.tint[band.index]
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: cardRow.tint[band.index + 1]
                                    }
                                }
                            }
                        }
                    }

                    // Runs of one colour are the normal case in a deck — six
                    // Forests in a row — and without a rule between them they
                    // fuse into one block with names floating on it.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Qt.rgba(0, 0, 0, 0.09)
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#c4342a"
                        opacity: 0
                        visible: cardRow.illegal

                        // lub-dub, then rest: two beats close together read as
                        // a pulse, where one even fade just reads as flicker
                        SequentialAnimation on opacity {
                            running: cardRow.illegal
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.34; duration: 110 }
                            NumberAnimation { to: 0.10; duration: 150 }
                            NumberAnimation { to: 0.28; duration: 110 }
                            NumberAnimation { to: 0.00; duration: 320 }
                            PauseAnimation { duration: 620 }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        // A slice of the card's own art, so a row is
                        // recognisable before you've read it. Scryfall's
                        // art_crop, not the whole card — at this size a whole
                        // card is a grey rectangle with a smudge on it.
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 24
                            color: "#b9b9c1"          // shows through while loading
                            border.width: 1
                            border.color: "#8f8f98"

                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: imageArtCrop
                                asynchronous: true
                                // decode at the size it is drawn: a deck is a
                                // hundred of these, and the full crop is
                                // 626x457 apiece
                                sourceSize: Qt.size(
                                    width * Screen.devicePixelRatio,
                                    height * Screen.devicePixelRatio)
                                fillMode: Image.PreserveAspectCrop
                                clip: true
                            }
                        }
                        Label {
                            text: qty + "×"
                            font.pixelSize: Retro.body
                            color: "#6b6b74"
                            Layout.preferredWidth: 20
                        }
                        Label {
                            Layout.fillWidth: true
                            text: name
                            elide: Text.ElideRight
                            font.pixelSize: Retro.body
                            color: "#2e2e34"
                        }
                        // whatever you've called this card in this list. It
                        // sits with the name rather than in a column of its
                        // own: most rows have no label, and an empty column
                        // would cost every row width to say nothing.
                        Rectangle {
                            visible: label !== ""
                            Layout.preferredWidth: Math.min(
                                labelText.implicitWidth + 8, 90)
                            Layout.preferredHeight: 15
                            radius: 2
                            // neutral rather than tinted: it now sits on a
                            // coloured row, and a blue-grey tag on a green row
                            // reads as a second colour the card doesn't have
                            color: "#f4f4f6"
                            border.width: 1
                            border.color: "#8d8d96"
                            Label {
                                id: labelText
                                anchors.centerIn: parent
                                width: parent.width - 6
                                text: label
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Retro.small
                                color: "#3b4351"
                            }
                        }
                        Label {
                            text: manaCost.replace(/[{}]/g, "")
                            font.pixelSize: Retro.body
                            color: "#5c5c66"
                        }
                        // steppers appear on hover so the row stays readable
                        PixelButton {
                            sprite: "mtg-icon-minus"
                            pixelScale: 1
                            visible: cardHover.hovered
                            onClicked: deckStore.setQty(
                                deckStore.activeId, cardId, qty - 1)
                        }
                        PixelButton {
                            sprite: "mtg-icon-plus"
                            pixelScale: 1
                            visible: cardHover.hovered
                            onClicked: deckStore.addCard(deckStore.activeId, cardId)
                        }
                        // takes the whole entry out in one go. The minus above
                        // steps down a copy at a time, which is the wrong tool
                        // for dropping a four-of; held off from the steppers by
                        // a gap so it isn't caught by a misjudged click.
                        PixelButton {
                            sprite: "mtg-icon-close"
                            pixelScale: 1
                            visible: cardHover.hovered
                            Layout.leftMargin: 5
                            tooltip: qty > 1 ? "Remove all " + qty + " copies"
                                             : "Remove from list"
                            onClicked: deckStore.removeCard(
                                deckStore.activeId, cardId)
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: dock.cardActivated(cardId, imageNormal, name,
                                                     rarity, imageBack)
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: dock.deckCardMenuRequested(cardId, name, label)
                    }
                }
            }
        }

        // ---- vital signs --------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: statsColumn.implicitHeight + 16
            visible: deckStore.activeId > 0 && deckStore.stats.total > 0
            radius: 6
            color: "#d3d3d8"
            border.color: "#b0b0b6"

            Column {
                id: statsColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                // mana curve
                Row {
                    width: parent.width
                    height: 54
                    spacing: 3
                    Repeater {
                        model: deckStore.stats.curve
                        delegate: Item {
                            width: (statsColumn.width - 21) / 8
                            height: 54
                            Rectangle {
                                anchors.bottom: bucketLabel.top
                                anchors.bottomMargin: 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 2
                                // the tallest bucket fills the plot; the rest scale to it
                                height: Math.max(2, 36 * modelData.count
                                        / Math.max(1, deckStore.stats.curveMax))
                                radius: 2
                                color: "#4d7bd6"
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.top
                                    visible: modelData.count > 0
                                    text: modelData.count
                                    font.pixelSize: Retro.body
                                    color: "#5c5c66"
                                }
                            }
                            Label {
                                id: bucketLabel
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: Retro.body
                                color: "#5c5c66"
                            }
                        }
                    }
                }

                // colour pips, as a proportional bar
                Row {
                    width: parent.width
                    height: 10
                    visible: deckStore.stats.pipsTotal > 0
                    Repeater {
                        model: deckStore.stats.pips
                        delegate: Rectangle {
                            width: statsColumn.width * modelData.count
                                   / Math.max(1, deckStore.stats.pipsTotal)
                            height: 10
                            color: dock.pipColor(modelData.color)
                        }
                    }
                }

                // type counts
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: deckStore.stats.types
                        delegate: Label {
                            text: modelData.type + " " + modelData.count
                            font.pixelSize: Retro.body
                            color: "#4a4a53"
                        }
                    }
                }

                Label {
                    text: "Lands " + deckStore.stats.lands
                          + "   ·   avg MV " + deckStore.stats.avgCmc
                    font.pixelSize: Retro.body
                    color: "#4a4a53"
                }
            }
        }

        // ---- rule check ---------------------------------------------------
        Column {
            Layout.fillWidth: true
            visible: deckStore.isDeck && deckStore.problems.length > 0
            spacing: 3
            Repeater {
                model: deckStore.problems
                delegate: Rectangle {
                    width: parent.width
                    height: problemText.implicitHeight + 8
                    radius: 4
                    color: modelData.level === "error" ? "#f2d3cd" : "#e6e2d2"
                    border.color: modelData.level === "error" ? "#c4705c" : "#b5ad8f"
                    Label {
                        id: problemText
                        anchors.verticalCenter: parent.verticalCenter
                        x: 7
                        width: parent.width - 14
                        wrapMode: Text.Wrap
                        // "!" rather than a warning sign: the face is drawn
                        // from ASCII and Latin-1 only, and a glyph it doesn't
                        // have comes out as an empty box
                        text: (modelData.level === "error" ? "!  " : "·  ")
                              + modelData.message
                        font.pixelSize: Retro.body
                        color: modelData.level === "error" ? "#7d3121" : "#5f5844"
                    }
                }
            }
        }

        // the tick is the sprite the grid tiles already use, not a character:
        // the face has no ✓, and this way the two ticks in the app are one mark
        RowLayout {
            Layout.fillWidth: true
            visible: deckStore.isDeck && deckStore.problems.length === 0
            spacing: 6
            PixelIcon { sprite: "mtg-icon-check" }
            Label {
                Layout.fillWidth: true
                text: "Legal Commander deck"
                font.pixelSize: Retro.body
                color: "#2e6b3c"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            visible: deckStore.activeId > 0
            spacing: 10
            PixelButton {
                sprite: "mtg-btn-export"
                pixelScale: 2
                onClicked: dock.exportRequested()
            }
            // No Make/Unmake button: the kind is chosen when the list is named.
            // DeckStore still has promoteToDeck/demoteToList if a way back is
            // ever wanted here again.
            Item { Layout.fillWidth: true }
        }
    }

    // right-click on a list in the sidebar. A popup of pixel buttons rather
    // than a Menu, because the buttons carry their own labels and a menu row
    // would only repeat them in the system font.
    Popup {
        id: listActions
        property int listId: 0
        property string listName: ""
        padding: 8
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: RetroPanel { shadowOffset: 4 }

        Column {
            spacing: 6
            Label {
                text: listActions.listName
                width: Math.max(90, implicitWidth)
                elide: Text.ElideRight
                font.pixelSize: Retro.small
                color: Retro.inkHot
            }
            PixelButton {
                sprite: "mtg-btn-rename"
                pixelScale: 2
                onClicked: {
                    listActions.close()
                    dock.renameRequested(listActions.listId, listActions.listName)
                }
            }
            PixelButton {
                sprite: "mtg-btn-duplicate"
                pixelScale: 2
                onClicked: {
                    listActions.close()
                    dock.duplicateRequested(listActions.listId, listActions.listName)
                }
            }
            PixelButton {
                sprite: "mtg-btn-delete"
                pixelScale: 2
                onClicked: {
                    listActions.close()
                    dock.deleteRequested(listActions.listId, listActions.listName)
                }
            }
        }
    }
}
