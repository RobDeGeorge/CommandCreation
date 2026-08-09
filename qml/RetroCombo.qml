import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// A dropdown wearing the same plate as the overlays, down to its list popup.
ComboBox {
    id: combo

    font.pixelSize: Retro.body
    implicitHeight: 28

    background: RetroPanel {
        sunken: true
        shadowOffset: 0
        plate: combo.down ? Retro.darkblue : Retro.plateDeep
    }

    contentItem: Text {
        leftPadding: 7
        rightPadding: 24
        text: combo.displayText
        font: combo.font
        color: Retro.ink
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: PixelIcon {
        sprite: "mtg-icon-sort-desc"
        on: combo.down
        x: combo.width - width - 5
        y: (combo.height - height) / 2
    }

    // Optional: the model role holding an image source to show left of each
    // label — set symbols in the set picker. Rows whose icon is missing still
    // get the gutter, so the names stay in one column either way. Left unset,
    // the rows are plain text and the model can stay a list of strings.
    property string iconRole: ""
    readonly property int iconGutter: 21

    delegate: ItemDelegate {
        id: row
        required property var modelData
        required property int index
        width: ListView.view.width
        height: 20
        highlighted: combo.highlightedIndex === index
        contentItem: Item {
            Image {
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                visible: combo.iconRole !== ""
                source: combo.iconRole === "" ? ""
                      : (row.modelData[combo.iconRole] || "")
                fillMode: Image.PreserveAspectFit
                // the sprites are drawn at 16px; keep them on the pixel grid
                smooth: false
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: combo.iconRole === "" ? 5 : combo.iconGutter + 5
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: combo.textRole === "" ? row.modelData
                    : (row.modelData[combo.textRole] || "")
                font.pixelSize: Retro.body
                color: row.highlighted ? Retro.black : Retro.ink
                elide: Text.ElideRight
            }
        }
        background: Rectangle {
            color: highlighted ? Retro.blue : "transparent"
        }
    }

    popup: Popup {
        y: combo.height
        width: combo.width
        implicitHeight: Math.min(260, listView.contentHeight + 8)
        padding: 4
        background: RetroPanel { shadowOffset: 3 }
        contentItem: ListView {
            id: listView
            clip: true
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
