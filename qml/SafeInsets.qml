import QtQuick
import QtQuick.Window

// How much of the window the system has already spoken for — the status bar at
// the top, the gesture bar or navigation buttons at the bottom, a notch or a
// rounded corner at the sides.
//
// This is a file of its own, and one nothing imports directly, purely so that
// the type it names never has to be resolved by a Qt that has not got it:
// SafeArea arrived in Qt 6.9 and this project still builds against 6.5
// elsewhere. Main.qml reaches it through a Loader that stays inactive below
// that version and reads zero for every margin when it does — see
// safeAreaSupported in src/main.cpp, the compile-time check that decides.
//
// On Android the margins are only correct from 6.9.3: QTBUG-135808 and
// QTBUG-139690 had them reporting zero until something forced a
// recalculation, which on a phone meant the app looked right only after being
// rotated and rotated back. .github/workflows/release.yml pins a Qt new enough.
//
// Desktop and WebAssembly report zeros, which is correct rather than a
// fallback — a desktop window is handed its client area with the chrome
// already subtracted, and the browser build lives inside a canvas.
//
// This has no geometry of its own on purpose. The margins are whatever covers
// *this item*, so what it measures is decided entirely by where it is put and
// how big it is, and both of those are the Loader's to set — a Loader resizes
// what it loads to itself and would win any argument about it anyway. Main.qml
// gives that Loader the whole window, which is the only span that gives a true
// answer: the ApplicationWindow contentItem, where a child would otherwise
// land, begins below the header, so the status bar could never overlap it and
// the top margin would read zero in exactly the case this exists to catch.
Item {
    // insetTop and not top: Item already has top, left, right and bottom as
    // FINAL anchor lines, and shadowing one of those is not a warning — the
    // whole file fails to load, the Loader hands back null, and every margin
    // falls back to the zero it would have had anyway. Which is to say it
    // fails exactly like not having written any of this, on the one platform
    // where it is the difference between usable and not.
    readonly property real insetTop: SafeArea.margins.top
    readonly property real insetBottom: SafeArea.margins.bottom
    readonly property real insetLeft: SafeArea.margins.left
    readonly property real insetRight: SafeArea.margins.right
}
