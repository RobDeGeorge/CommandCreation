import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// The inside of a "type it or pick it" popover, the way the artist region does
// it: a box you type in, over a list that narrows as you type.
//
// Typing narrows the list at once and reports itself as `edited`; filtering the
// grid on every character resets the model on every character, and a reset
// rebuilds every tile and restarts its card-image load — far more expensive
// than the query. So the owner debounces `edited` into the search. Enter or a
// picked row is `committed`: done deciding, run it now.
//
// The list only ever offers. The filters behind it are substring matches, so a
// word the pool has never heard of is still perfectly typeable.
Column {
    id: root

    property string label: ""
    property string placeholder: ""
    property var options: []
    property alias value: input.text
    property int listHeight: 160

    // Enter in the box, or a row picked off the list. Either way the value is
    // already in `value` by the time this arrives.
    signal committed()

    // A character typed. `value` is current; the owner decides when that
    // becomes a query.
    signal edited()

    // select what's there on open, so typing replaces the old value rather
    // than appending to it
    function focusInput() {
        input.forceActiveFocus()
        input.selectAll()
    }

    width: parent.width
    spacing: 8

    // Lowercased once rather than on every character typed: `options` is a
    // QVariantList and every element read marshals a string across, which for
    // 400-odd subtypes is worth paying exactly one time.
    readonly property var index: {
        var all = root.options
        var names = [], lower = []
        for (var i = 0; i < all.length; i++) {
            var word = String(all[i])
            names.push(word)
            lower.push(word.toLowerCase())
        }
        return { names: names, lower: lower }
    }

    // Text that exactly matches an entry means you picked it off the list
    // rather than typed it. Narrowing to that one row would leave you looking
    // at the choice you already made with no way to change it, so an exact
    // match re-opens the whole list.
    readonly property var matches: {
        var names = index.names, lower = index.lower
        var query = input.text.toLowerCase()
        if (lower.indexOf(query) !== -1) query = ""
        var out = []
        for (var i = 0; i < names.length; i++)
            if (query === "" || lower[i].indexOf(query) !== -1)
                out.push(names[i])
        return out
    }

    Label {
        text: root.label
        font.pixelSize: Retro.body
        color: Retro.inkHot
    }

    RetroField {
        id: input
        width: parent.width
        placeholderText: root.placeholder
        onTextChanged: root.edited()
        onAccepted: root.committed()
    }

    RetroPanel {
        width: parent.width
        height: Math.min(root.listHeight, Math.max(0, list.count * 20))
        visible: height > 0
        sunken: true
        shadowOffset: 0
        plate: Retro.plateDeep

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            model: root.matches

            // when the list re-opens after a pick, scroll to the word you are
            // on rather than dumping you back at the top
            onModelChanged: {
                var i = root.matches.indexOf(input.text)
                if (i < 0) return
                Qt.callLater(function () {
                    list.positionViewAtIndex(i, ListView.Center)
                })
            }

            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: 20
                color: wordHover.hovered ? Retro.blue
                     : (modelData === input.text ? Retro.darkblue : "transparent")
                HoverHandler { id: wordHover }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 5
                    width: parent.width - 10
                    elide: Text.ElideRight
                    text: parent.modelData
                    font.pixelSize: Retro.body
                    color: wordHover.hovered ? Retro.black : Retro.ink
                }
                TapHandler {
                    // picking a word is accepting it
                    onTapped: {
                        input.text = parent.modelData
                        root.committed()
                    }
                }
            }
        }
    }
}
