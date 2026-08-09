.pragma library

// The overlay palette. Same PICO-8 sixteen the button sprites are drawn from,
// so a dialog and the buttons inside it belong to one picture.
//
// Overlays are dark plates over the light application chrome: that is what
// separates "a panel floating above the page" from "more page", and it is how
// console UI of the era did it without needing a blur.

var black      = "#000000"
var darkblue   = "#1d2b53"
var darkpurple = "#7e2553"
var darkgreen  = "#008751"
var brown      = "#ab5236"
var darkgrey   = "#5f574f"
var lightgrey  = "#c2c3c7"
var white      = "#fff1e8"
var red        = "#ff004d"
var orange     = "#ffa300"
var yellow     = "#ffec27"
var green      = "#00e436"
var blue       = "#29adff"
var lavender   = "#83769c"
var pink       = "#ff77a8"
var peach      = "#ffccaa"

// roles
var plate      = darkblue      // the body of an overlay
var plateDeep  = black         // wells sunk into a plate: lists, text fields
var bevel      = blue          // the lit top/left edge
var bevelDark  = black         // the shaded bottom/right edge
var edge       = black         // the outer border

var ink        = white         // primary text on a plate
var inkDim     = lavender      // secondary text, hints, placeholders
var inkHot     = yellow        // the value you set, the thing that is on
var inkBad     = pink          // errors

// type sizes. Only multiples of 8 stay on the pixel grid -- see src/main.cpp.
var small      = 8
var body       = 8
var title      = 16

// The mana identity colours, for the stats bar. Kept close to the pip sprites.
var identity = { W: peach, U: blue, B: darkgrey, R: red, G: green, C: lightgrey }

function pipColor(letter) {
    return identity[letter] || lightgrey
}
