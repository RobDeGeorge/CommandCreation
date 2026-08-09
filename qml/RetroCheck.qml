import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// A checkbox that borrows the tick sprite, so it matches the badge the card
// tiles use for the same idea.
CheckBox {
    id: box

    property color textColor: Retro.ink
    property int pixelScale: 1
    font.pixelSize: Retro.body
    spacing: 7

    indicator: PixelIcon {
        sprite: "mtg-check-box"
        pixelScale: box.pixelScale
        on: box.checked
        x: box.leftPadding
        y: (box.height - height) / 2
    }

    // Give the box an explicit width and a long label elides rather than
    // pushing the panel wider than it is — a card name in a label is not
    // something you get to choose the length of.
    contentItem: Text {
        leftPadding: box.indicator.width + box.spacing
        text: box.text
        font: box.font
        color: box.textColor
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
