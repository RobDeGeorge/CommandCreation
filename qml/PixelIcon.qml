import QtQuick

// The same sprites as PixelButton, but inert — for badges, pips and markers
// that show a state rather than accept a click. `on` picks the frame.
Image {
    id: icon

    property string sprite: ""
    property int pixelScale: 1
    property bool on: true

    source: sprite === "" ? "" : "assets/" + sprite + (on ? "-down" : "-up") + ".png"
    smooth: false
    fillMode: Image.Stretch
    width: (sourceSize.width > 0 ? sourceSize.width : 16) * pixelScale
    height: (sourceSize.height > 0 ? sourceSize.height : 16) * pixelScale
}
