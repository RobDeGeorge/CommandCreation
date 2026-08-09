import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Retro.js" as Retro

// Paste a deck list in from anywhere that exports one.
//
// It reads what you pasted and tells you what it found *before* writing
// anything — how many cards, which commander, which names it didn't
// recognise. Importing a hundred-card deck and discovering afterwards that
// eight cards quietly went missing is the failure worth designing against,
// so the unrecognised names are shown, not counted.
RetroDialog {
    id: dialog

    width: Math.min(620, window.width * 0.75)
    height: Math.min(680, window.height * 0.85)
    title: "Import deck list"

    // deckStore.previewImport() for whatever is in the paste box
    property var report: ({ cards: 0, copies: 0, commander: "",
                            unmatched: [], skipped: 0, notes: [],
                            suggestedName: "" })
    readonly property bool hasCards: report.cards > 0

    function open_() {
        pasted.text = ""
        nameField.text = ""
        dialog.report = deckStore.previewImport("")
        open()
    }

    function reread() {
        dialog.report = deckStore.previewImport(pasted.text)
        if (nameField.text === "")
            nameField.placeholderText = dialog.report.suggestedName
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Retro.small
            color: Retro.inkDim
            text: "Paste from Moxfield, Archidekt, MTGO, TappedOut or "
                  + "Deckstats. Quantities, set codes, categories and foil "
                  + "markers are all understood and ignored as appropriate."
        }

        RetroPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 140
            sunken: true
            shadowOffset: 0
            plate: Retro.plateDeep
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                TextArea {
                    id: pasted
                    selectByMouse: true
                    font.pixelSize: Retro.body
                    color: Retro.ink
                    selectionColor: Retro.blue
                    selectedTextColor: Retro.black
                    background: null
                    placeholderText: "1 Sol Ring\n1 Command Tower\n…"
                    placeholderTextColor: Retro.inkDim
                    // re-reading is pure parsing over the pasted text, so it
                    // is cheap enough to do as you type — unlike a card search
                    onTextChanged: dialog.reread()
                }
            }
        }

        // -- what we found ------------------------------------------------
        RetroPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: found.implicitHeight + 16
            sunken: true
            shadowOffset: 0
            plate: Retro.plateDeep

            Column {
                id: found
                x: 8
                y: 8
                width: parent.width - 16
                spacing: 3

                Label {
                    font.pixelSize: Retro.body
                    color: dialog.hasCards ? Retro.inkHot : Retro.inkDim
                    text: dialog.hasCards
                        ? dialog.report.cards + " cards · "
                          + dialog.report.copies + " copies"
                        : (pasted.text === "" ? "Nothing pasted yet."
                                              : "Nothing here matched a card.")
                }
                Label {
                    visible: dialog.report.commander !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Retro.small
                    color: Retro.ink
                    text: "Commander: " + dialog.report.commander
                }
                Label {
                    visible: dialog.report.skipped > 0
                    font.pixelSize: Retro.small
                    color: Retro.inkDim
                    text: dialog.report.skipped
                          + " in a sideboard or maybeboard — not imported"
                }
                Label {
                    visible: dialog.report.unmatched.length > 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Retro.small
                    color: Retro.inkBad
                    // named, not counted: you cannot fix what you cannot see
                    text: "Not recognised (" + dialog.report.unmatched.length
                          + "): " + dialog.report.unmatched.join(", ")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            // Main.qml's PanelLabel is file-scoped to Main.qml
            Label {
                text: "Name"
                font.pixelSize: Retro.body
                color: Retro.inkHot
            }
            RetroField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: dialog.report.suggestedName || "Imported deck"
            }
        }
    }

    footer: Item {
        implicitHeight: 56
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 17
            anchors.rightMargin: 17
            spacing: 10

            PixelButton {
                sprite: "mtg-btn-cancel"
                pixelScale: 2
                onClicked: dialog.reject()
            }
            Item { Layout.fillWidth: true }
            PixelButton {
                sprite: "mtg-btn-new-list"
                pixelScale: 2
                enabled: dialog.hasCards
                tooltip: "Import as a new list"
                onClicked: {
                    var name = nameField.text !== "" ? nameField.text
                                                     : dialog.report.suggestedName
                    if (deckStore.importText(pasted.text, name, false) > 0)
                        dialog.accept()
                }
            }
            PixelButton {
                sprite: "mtg-btn-import"
                pixelScale: 2
                enabled: dialog.hasCards && deckStore.activeId > 0
                tooltip: deckStore.activeId > 0
                    ? "Merge into “" + deckStore.activeName + "”"
                    : "Open a list first to merge into it"
                onClicked: {
                    if (deckStore.importText(pasted.text, "", true) > 0)
                        dialog.accept()
                }
            }
        }
    }
}
