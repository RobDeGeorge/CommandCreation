import QtQuick
import QtQuick.Controls
import "Retro.js" as Retro

// A number well with the plus/minus sprites as its steppers.
SpinBox {
    id: spin

    font.pixelSize: Retro.body
    implicitHeight: 28
    leftPadding: 24
    rightPadding: 24

    // Plain digits. SpinBox formats through the locale by default, which groups
    // thousands — every number in this application is a count, a cost or a year,
    // and "2,015" is not a year.
    textFromValue: function (value, locale) { return String(value) }
    valueFromText: function (text, locale) { return parseInt(text, 10) || 0 }

    background: RetroPanel {
        sunken: true
        shadowOffset: 0
        plate: spin.activeFocus ? Retro.darkblue : Retro.plateDeep
    }

    contentItem: Text {
        text: spin.textFromValue(spin.value, spin.locale)
        font: spin.font
        color: Retro.ink
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    down.indicator: PixelIcon {
        sprite: "mtg-icon-minus"
        on: spin.down.pressed
        x: 4
        y: (spin.height - height) / 2
        opacity: spin.value > spin.from ? 1 : 0.4
    }

    up.indicator: PixelIcon {
        sprite: "mtg-icon-plus"
        on: spin.up.pressed
        x: spin.width - width - 4
        y: (spin.height - height) / 2
        opacity: spin.value < spin.to ? 1 : 0.4
    }
}
