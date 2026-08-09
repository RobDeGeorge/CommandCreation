import QtQuick
import QtQuick.Shapes

// The plate a region of the filter form wears.
//
// Not a rectangle, because the boxes printed on a Magic card are not
// rectangles. The 2015 and 2003 title bars are capped at each end by an arc
// that bulges out past the bar's own corners — that curve is the first thing
// you see of a modern card — and the P/T box carries the same bulge on its
// short sides. The text box is square-cornered in the old frames and eased
// off in the new one. A plate cut to those curves sits *on* its box; a plain
// rectangle only sits near it, and the corners are exactly where the eye
// checks whether the form lines up with the card underneath.
//
// Three things describe every one of them: a radius per corner, a bulge per
// edge, and — where another region has to share a corner — a bite out of the
// bottom right. On a printed card the P/T box bites into the bottom-right
// corner of the text box; the flavour plate is cut to match, so the two are
// neighbours rather than a stack. Two plates overlapping reads as one of them
// being broken; a plate carved to fit reads as the shape it was always meant
// to be. Bottom-right is the only corner that has ever needed it: it is the
// only corner Magic has put a second box in, in any of its frames.
//
// See CardFrames.js for the numbers and how they were measured off print.
Item {
    id: plate

    property color fill: "#d4d4d8"
    property color stroke: Qt.darker(fill, 1.3)
    property int strokeWidth: 1

    // radius for any corner the caller does not name — regions with nothing
    // printed under them (the 1993 and 1997 frames draw no title box, no type
    // box and no P/T box at all) get this and stay plain
    property real corner: 3
    // [top-left, top-right, bottom-right, bottom-left] radii, in pixels
    property var radii: []
    // [top, right, bottom, left] — how far each edge bows out, in pixels.
    // The bulge straddles the plate's rectangle rather than growing off it:
    // the edge's middle stands `bow / 2` proud and its ends draw back by the
    // same, because the region rectangles were measured across the middle of
    // the printed cap, not across its corners.
    property var bows: []

    // the bite, in pixels. Zero on either axis leaves the corner alone.
    property real notchWidth: 0
    property real notchHeight: 0

    // An arch cut up out of the middle of the bottom edge, as
    // [centre, half-width, rise] in pixels measured from this plate's own left
    // edge. This is the holofoil stamp on a rare or a mythic: the printed text
    // box does not run behind the stamp, it lifts over it, and a plate that
    // ran straight across would cover the one thing on the card the border
    // itself gets out of the way of. Zero rise leaves the edge flat, which is
    // every card below rare and every frame before 2015.
    property var scallop: []

    // The ten numbers the outline is actually walked from. They are held as
    // scalars rather than read out of the arrays at draw time so that each
    // can ease to its new value: changing the face to a card from another
    // frame re-cuts every plate as well as moving it, and a shape that snaps
    // while the region it belongs to glides reads as two changes instead of
    // one. Same duration and curve as the regions' own move — see CardField.
    property real cornerTL: pick(radii, 0)
    property real cornerTR: pick(radii, 1)
    property real cornerBR: pick(radii, 2)
    property real cornerBL: pick(radii, 3)
    property real bowTop:    pick(bows, 0, 0)
    property real bowRight:  pick(bows, 1, 0)
    property real bowBottom: pick(bows, 2, 0)
    property real bowLeft:   pick(bows, 3, 0)
    property real archCentre: pick(scallop, 0, 0)
    property real archHalf:   pick(scallop, 1, 0)
    property real archRise:   pick(scallop, 2, 0)

    Behavior on cornerTL  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on cornerTR  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on cornerBR  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on cornerBL  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on bowTop    { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on bowRight  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on bowBottom { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on bowLeft   { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on notchWidth  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    Behavior on notchHeight { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    // Only the rise eases. The span is the same on every card that carries a
    // stamp, so animating it too would open the arch sideways as well as
    // upwards, and a common giving way to a rare would read as the plate
    // tearing rather than as the border lifting.
    Behavior on archRise    { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }

    // one entry of a shape array, or the fallback when the caller left it out
    function pick(a, i, fallback) {
        if (fallback === undefined)
            fallback = corner
        return (a !== undefined && a.length > i && a[i] !== undefined)
               ? a[i] : fallback
    }

    // The outline, clockwise from the top left: the points, the radius each
    // one is eased off by, and the bulge of the edge that leaves it. Six
    // points when carved, four when not — the path builder doesn't care which.
    function outline() {
        var w = width, h = height
        // the corners drawn back by half of whichever bulges meet there
        var x0 = bowLeft / 2, x1 = w - bowRight / 2
        var y0 = bowTop / 2,  y1 = h - bowBottom / 2
        var nw = Math.min(notchWidth, w), nh = Math.min(notchHeight, h)
        var o
        if (nw <= 0 || nh <= 0)
            o = { pts: [[x0, y0], [x1, y0], [x1, y1], [x0, y1]],
                  rad: [cornerTL, cornerTR, cornerBR, cornerBL],
                  bow: [bowTop, bowRight, bowBottom, bowLeft] }
        else
            // Carved: the bite breaks the right and bottom edges in two, and a
            // broken edge is drawn straight. A bulge belongs to a whole edge —
            // half a cap is a dent. Nothing in the frame table asks for both on
            // the same edge anyway: the frame that carves is the 2015 text box,
            // whose sides are dead straight in print.
            o = { pts: [[x0, y0], [x1, y0], [x1, h - nh], [w - nw, h - nh],
                        [w - nw, y1], [x0, y1]],
                  rad: [cornerTL, cornerTR, cornerBR, cornerBR,
                        cornerBR, cornerBL],
                  bow: [bowTop, 0, 0, 0, 0, bowLeft] }
        return arch(o, y1)
    }

    // The stamp's arch, cut into the last run of the bottom edge — the run
    // that ends at the bottom-left corner, which is the whole bottom edge on a
    // plain plate and everything left of the bite on a carved one.
    //
    // It goes in as two more points and one more bulge rather than as a case
    // of its own: the outline is walked clockwise, so the bottom edge runs
    // right to left and a cut *up* into the plate is simply a bulge with the
    // sign turned round. The feet sit flat on the bottom line — no drawing
    // back by half, as a whole edge's bulge does — because the border they
    // stand on is the one the arch leaves and returns to.
    function arch(o, y) {
        var n = o.pts.length
        if (!(archHalf > 0 && archRise > 0.05))
            return o
        var lo = Math.min(o.pts[n - 2][0], o.pts[n - 1][0])
        var hi = Math.max(o.pts[n - 2][0], o.pts[n - 1][0])
        // an arch wider than the run it is cut from would reach round a corner
        // and turn the outline inside out, so it is left off instead
        if (archCentre - archHalf < lo || archCentre + archHalf > hi)
            return o
        o.pts.splice(n - 1, 0, [archCentre + archHalf, y],
                               [archCentre - archHalf, y])
        o.rad.splice(n - 1, 0, 0, 0)
        o.bow.splice(n - 1, 0, -archRise, 0)
        o.bow[n - 2] = 0            // the run into the arch is straight
        return o
    }

    // the point `r` along the way from `from` towards `toward`, never past the
    // halfway mark — that is what keeps two corners from eating each other on
    // a short edge
    function towards(from, toward, r) {
        var dx = toward[0] - from[0], dy = toward[1] - from[1]
        var len = Math.sqrt(dx * dx + dy * dy) || 1
        var t = Math.min(Math.max(r, 0), len / 2) / len
        return [from[0] + dx * t, from[1] + dy * t]
    }

    function at(p) {
        return p[0].toFixed(2) + " " + p[1].toFixed(2)
    }

    // An SVG path round the outline: an arc at every corner, and every edge
    // between them either a straight run or a quadratic bulged out to its
    // measured sagitta. Handing Shape a path string beats building elements
    // one by one — the outline changes shape, not just size, when the face
    // changes to a card from a frame that draws its boxes differently.
    function pathData() {
        var o = outline(), pts = o.pts, n = pts.length
        var d = ""
        for (var i = 0; i < n; i++) {
            var prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            var r = Math.max(0, o.rad[i])
            var into = towards(cur, prev, r)
            var outof = towards(cur, next, r)
            if (i === 0)
                d += "M " + at(into)
            if (r > 0.05) {
                // cross product of the two edge vectors: positive turns the
                // way the outline runs (convex), negative is the notch's
                // reflex corner, which takes the opposite sweep
                var cross = (cur[0] - prev[0]) * (next[1] - cur[1])
                          - (cur[1] - prev[1]) * (next[0] - cur[0])
                d += " A " + r.toFixed(2) + " " + r.toFixed(2) + " 0 0 "
                   + (cross > 0 ? 1 : 0) + " " + at(outof)
            } else {
                d += " L " + at(cur)
                outof = cur
            }
            // the run from here to where the next corner starts turning
            var entry = towards(next, cur, Math.max(0, o.rad[(i + 1) % n]))
            var b = o.bow[i]
            if (Math.abs(b) > 0.05) {
                // A quadratic sits half as far off the chord as its control
                // point does, so the control goes out by twice the bulge. The
                // normal points out of a clockwise outline in screen
                // coordinates, which is the way every one of these curves goes.
                var dx = entry[0] - outof[0], dy = entry[1] - outof[1]
                var len = Math.sqrt(dx * dx + dy * dy) || 1
                var mx = (outof[0] + entry[0]) / 2, my = (outof[1] + entry[1]) / 2
                d += " Q " + at([mx + 2 * b * dy / len, my - 2 * b * dx / len])
                   + " " + at(entry)
            } else {
                d += " L " + at(entry)
            }
        }
        return d + " Z"
    }

    // The bulges stand proud of the plate's own rectangle by half their
    // sagitta, so nothing here may clip: a clipped cap is a flat cap, which
    // is the one thing the whole shape exists to avoid.
    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: plate.fill
            strokeColor: plate.stroke
            strokeWidth: plate.strokeWidth
            // re-walked whenever the plate is resized, re-cut or re-carved
            PathSvg {
                path: plate.width > 0 && plate.height > 0
                      ? plate.pathData() : ""
            }
        }
    }
}
