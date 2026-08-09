import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// A modal box on the overlay plate, with a title bar rather than a title
// label — the bar is the era's signature, and it gives the drop shadow
// something to hang off.
Dialog {
    id: dlg

    anchors.centerIn: Overlay.overlay
    modal: true
    padding: 14
    topPadding: 12

    background: RetroPanel { shadowOffset: 6 }

    header: Item {
        implicitHeight: 28
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            anchors.topMargin: 3
            color: Retro.blue
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: dlg.title
                font.pixelSize: Retro.body
                color: Retro.black
            }
        }
    }

    Overlay.modal: Rectangle { color: "#aa000000" }
}
