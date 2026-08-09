import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "Retro.js" as Retro

// A button drawn from the pixel-art sprites in assets/.
//
// Each sprite ships two states -- `-up.png` and `-down.png` -- at their native
// pixel size; `pixelScale` multiplies that up with nearest-neighbour filtering,
// so a button is only ever an exact integer multiple of its art. Never give one
// a Layout.fillWidth: stretching pixel art to a container's width is the one
// thing that ruins it.
Item {
    id: root

    property string sprite: ""
    property int pixelScale: 2
    property bool checkable: false
    property bool checked: false
    property string tooltip: ""
    // The pressed art doubles as the "on" art. `checked` drives it whether or
    // not the button is `checkable` — checkable only decides whether a click
    // toggles it here, so a set of buttons that are exclusive can bind
    // `checked` to whichever one is selected and own the state themselves.
    readonly property bool down: mouse.pressed || checked
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    implicitWidth: (art.sourceSize.width > 0 ? art.sourceSize.width : 16) * pixelScale
    implicitHeight: (art.sourceSize.height > 0 ? art.sourceSize.height : 16) * pixelScale

    Image {
        id: art
        anchors.fill: parent
        source: root.sprite === "" ? ""
              : "assets/" + root.sprite + (root.down ? "-down" : "-up") + ".png"
        smooth: false
        fillMode: Image.Stretch
        // drawn straight, and therefore perfectly crisp, in the resting state;
        // the effect below takes over only while hovered or disabled
        visible: root.enabled && !mouse.containsMouse
    }

    MultiEffect {
        anchors.fill: parent
        source: art
        visible: !art.visible
        brightness: root.enabled ? 0.22 : 0
        saturation: root.enabled ? 0 : -0.9
        opacity: root.enabled ? 1 : 0.5
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.checkable) root.checked = !root.checked
            root.clicked()
        }
    }

    // an explicit ToolTip rather than the attached one, so it can wear the
    // same plate as every other overlay
    ToolTip {
        id: tip
        visible: root.tooltip !== "" && mouse.containsMouse
        text: root.tooltip
        delay: 400
        padding: 6
        contentItem: Text {
            text: tip.text
            font.pixelSize: Retro.small
            color: Retro.ink
        }
        background: RetroPanel { shadowOffset: 3 }
    }
}
