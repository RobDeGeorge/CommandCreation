import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// A text field that reads as a well cut into the plate rather than a box drawn
// on top of it: sunken bevel, black ground, and a lit border while focused.
TextField {
    id: field

    color: Retro.ink
    placeholderTextColor: Retro.inkDim
    font.pixelSize: Retro.body
    selectByMouse: true
    selectionColor: Retro.blue
    selectedTextColor: Retro.black
    leftPadding: 6
    rightPadding: 6
    topPadding: 5
    bottomPadding: 5

    background: RetroPanel {
        sunken: true
        shadowOffset: 0
        plate: field.activeFocus ? Retro.darkblue : Retro.plateDeep
    }
}
