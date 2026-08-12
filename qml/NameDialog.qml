import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// One-field prompt used for naming, renaming and copying lists.
RetroDialog {
    id: dialog
    // never wider than the screen it is centred on — on a phone that is the
    // binding that does the work, on a desktop the 380 is
    width: Math.min(380, window.width - 24)

    property string label: ""
    property string placeholder: ""
    // Naming a new one also decides what it is. Renaming and copying don't ask,
    // because those already have a kind — the dock's Make/Unmake button is
    // where an existing list changes its mind.
    property bool askKind: false
    property string kind: "list"
    // what to do with the typed name; set by whoever opens the dialog
    property var handler: function (name, kind) {}

    function ask(dialogTitle, fieldLabel, initial, handler, askKind) {
        title = dialogTitle
        label = fieldLabel
        input.text = initial || ""
        dialog.handler = handler
        dialog.askKind = askKind === true
        dialog.kind = "list"
        open()
    }

    onOpened: {
        input.forceActiveFocus()
        input.selectAll()
    }
    onAccepted: handler(input.text, dialog.kind)

    Column {
        width: parent.width
        spacing: 8
        Label {
            text: dialog.label
            font.pixelSize: Retro.body
            color: Retro.inkHot
        }
        RetroField {
            id: input
            width: parent.width
            placeholderText: dialog.placeholder
            onAccepted: dialog.accept()
        }

        Item { width: 1; height: 4; visible: dialog.askKind }

        Label {
            visible: dialog.askKind
            text: "Kind"
            font.pixelSize: Retro.body
            color: Retro.inkHot
        }
        Row {
            visible: dialog.askKind
            spacing: 10
            // exclusive by hand rather than by ButtonGroup: these are sprites,
            // and `checked` is all the state there is
            PixelButton {
                sprite: "mtg-btn-kind-list"
                pixelScale: 2
                checked: dialog.kind === "list"
                // the pressed bevel alone is a 1px difference — too quiet for
                // a choice this size, so the one you didn't pick steps back
                opacity: checked ? 1 : 0.5
                tooltip: "A pile of cards, with no rules attached"
                onClicked: dialog.kind = "list"
            }
            PixelButton {
                sprite: "mtg-btn-kind-deck"
                pixelScale: 2
                checked: dialog.kind === "deck"
                opacity: checked ? 1 : 0.5
                tooltip: "Checked against the Commander rules — 100 cards, "
                       + "singleton, colour identity"
                onClicked: dialog.kind = "deck"
            }
        }
        Label {
            visible: dialog.askKind
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Retro.small
            color: Retro.inkDim
            text: dialog.kind === "deck"
                ? "Checked against the Commander rules as you build."
                : "No rule check. You can make it a deck at any time."
        }
    }

    footer: Item {
        implicitHeight: 56
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 17
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            PixelButton {
                sprite: "mtg-btn-cancel"
                pixelScale: 2
                onClicked: dialog.reject()
            }
            PixelButton {
                sprite: "mtg-btn-ok"
                pixelScale: 2
                onClicked: dialog.accept()
            }
        }
    }
}
