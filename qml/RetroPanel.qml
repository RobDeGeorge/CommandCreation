import QtQuick
import "Retro.js" as Retro

// The chrome every overlay sits on: a flat plate, a 2px hard border, a 1px
// bevel lit from the top left, and a hard offset shadow rather than a blur.
// No corner radius anywhere — a rounded corner on a 1px grid can only be a
// smudge, which is exactly what this style is not.
Item {
    id: root

    property color plate: Retro.plate
    property int shadowOffset: 4
    property bool sunken: false     // flip the bevel, for wells rather than plates

    Rectangle {                     // the hard drop shadow
        x: root.shadowOffset
        y: root.shadowOffset
        width: root.width
        height: root.height
        color: "#000000"
        opacity: 0.45
    }

    Rectangle {
        anchors.fill: parent
        color: Retro.edge           // the 2px outer border...
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: root.sunken ? Retro.bevelDark : Retro.bevel
            Rectangle {             // ...a 1px bevel, offset to leave a lit edge
                anchors.fill: parent
                anchors.leftMargin: 1
                anchors.topMargin: 1
                color: root.sunken ? Retro.bevel : Retro.bevelDark
                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 1
                    anchors.bottomMargin: 1
                    color: root.plate
                }
            }
        }
    }
}
