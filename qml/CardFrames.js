.pragma library

// Where each region of the filter form sits, per card frame.
//
// The form is printed onto whichever card the filters would actually turn up,
// and Magic has redrawn its card four times. A title bar that is a box in the
// 2015 frame is bare frame in 1997; the illustrator credit moved from inside
// the card down to the bottom info line; the copyright moved from bottom-left
// to bottom-right; the P/T box changed size and place. One table cannot serve
// them, so there is one per frame, and the form moves between them as the face
// changes. Scryfall tags every printing with the frame it was laid out in —
// that tag is the key into this table.
//
// Every number is a fraction of the card frame, measured rather than guessed:
// for each family, the row-by-row edge strength of sixteen cards is averaged,
// which cancels the art out (it differs on every card) and leaves that frame's
// own rules standing as peaks. See the scratchpad's measure2.py/overlay2.py.
// The pixel figures in each comment are of the reference image's 488x680.
//
// `shapes` is the same measurement carried one step further. A region's box is
// not a rectangle on any frame that draws one, so tracing it takes more than
// four numbers: a radius at each corner and how far each edge bows out. Those
// were read off the same averaged edge maps, following each border a row at a
// time instead of only asking where it starts and stops — see the scratchpad's
// grad.py, which builds the maps, and fit.py, which fits a curve to one edge.
//   r:   [top-left, top-right, bottom-right, bottom-left] corner radii, as
//        fractions of the card's width
//   bow: [top, right, bottom, left] sagittas — how far the middle of that edge
//        stands off the straight line between its corners. Sides are fractions
//        of the card's width, top and bottom of its height.
// A region with no entry is one with nothing printed underneath it to trace,
// and wears a plain lightly-rounded plate. Whole frames go without: 1993 and
// 1997 draw no title box, no type box and no P/T box at all — the name, the
// cost and the P/T are set straight onto the frame — so on those two only the
// text box has a shape of its own.

var FRAMES = {
    // title bar y 34..71, type bar y 384..418, text box y 428..633,
    // P/T box y 607..642 x 381..460, bottom info line y 647..658
    "2015": {
        name:    [0.0656, 0.0529, 0.6544, 0.0485],
        cost:    [0.7300, 0.0529, 0.2024, 0.0485],
        type:    [0.0656, 0.5676, 0.2400, 0.0441],
        subtype: [0.3150, 0.5676, 0.4450, 0.0441],
        set:     [0.7700, 0.5676, 0.1624, 0.0441],
        oracle:  [0.0656, 0.6324, 0.8668, 0.1610],
        flavor:  [0.0656, 0.7934, 0.8668, 0.1345],
        // the only frame that prints the credit outside the card proper, on
        // the info line, with the copyright beside it rather than beneath
        artist:  [0.0656, 0.9485, 0.4944, 0.0265],
        year:    [0.5900, 0.9485, 0.3424, 0.0265],
        // x 381..460 at its widest, y 607..642. The rectangle is the *middle*
        // of the bulge on each side rather than its crown — see `shapes`, and
        // CardPlate on why a bow straddles the rectangle it is given.
        pt:      [0.7849, 0.8926, 0.1545, 0.0515],
        // the P/T box bites furthest into the text box in this frame, so the
        // flavour plate is carved around it — width and height of the bite,
        // taken out of its bottom-right corner. Cut to where the P/T box is
        // widest, not to its corners: a bite sized to the corners would be
        // overlapped by the bulge halfway down.
        notches: { flavor: [0.1536, 0.0368] },

        // The frame that curves most, and the reason any of this exists. Its
        // title bar and type bar are capped at each end by an arc that stands
        // about 5.8px proud of the bar's corners over a 38px height — traced
        // right edge of the title bar, top to bottom: 451.1, 454.0, 456.2,
        // 457.0 at the middle, then back down to 451.5. The cap arcs are all
        // but the same on both bars, so the name and the type take the left
        // one and the cost and the set symbol take the right, each squared off
        // where it meets its neighbour so the pair reads as one printed bar.
        // The text box is straight-sided with its corners eased about 4.5px.
        shapes: {
            name:    { r: [0.0051, 0, 0, 0.0051], bow: [0, 0, 0, 0.0119] },
            cost:    { r: [0, 0.0051, 0.0051, 0], bow: [0, 0.0119, 0, 0] },
            type:    { r: [0.0051, 0, 0, 0.0051], bow: [0, 0, 0, 0.0116] },
            subtype: { r: [0, 0, 0, 0] },
            set:     { r: [0, 0.0051, 0.0051, 0], bow: [0, 0.0116, 0, 0] },
            oracle:  { r: [0.0092, 0.0092, 0, 0] },
            flavor:  { r: [0, 0, 0.0092, 0.0092] },
            // hangs off the bottom right as a rounded box whose short sides
            // bow out about 4px over its 35px height, x 380.8..460.7
            pt:      { r: [0.013, 0.013, 0.013, 0.013],
                       bow: [0, 0.0084, 0, 0.0084] }
        },

        // The holofoil stamp, which this frame was the first to carry: an oval
        // sitting astride the bottom edge of the text box, dead centre, on
        // rares and mythics only. The printed box does not run behind it — the
        // border lifts and arches over it and comes back down, and the flavour
        // plate is cut to the same arch so that the stamp stays uncovered.
        //
        // [centre, half-width, rise], the first two fractions of the card's
        // width and the last of its height. The arch is a true parabola, which
        // is exactly what a quadratic draws — fit a peak of 617.8 to a flat
        // line at 630.7 and the border comes out predicted 623.3 / 621.7 /
        // 620.3 / 619.3 against a traced 623.1 / 621.3 / 620.0 / 619.0, with
        // its feet at x 213 and 275. See CardPlate's `scallop`.
        stamp: [0.5000, 0.0635, 0.0194]
    },

    // title bar y 37..71, type bar y 385..416, text box y 426..603,
    // credit y 625..642 (inside the card, left), copyright y 640..655
    "2003": {
        name:    [0.0640, 0.0574, 0.6400, 0.0456],
        cost:    [0.7200, 0.0574, 0.2160, 0.0456],
        type:    [0.0640, 0.5721, 0.2400, 0.0397],
        subtype: [0.3150, 0.5721, 0.4300, 0.0397],
        set:     [0.7600, 0.5721, 0.1760, 0.0397],
        oracle:  [0.0640, 0.6294, 0.8720, 0.1400],
        // stops at the top of the P/T box rather than taking a bite out of
        // itself: this frame's box sits below the text box, barely into it
        flavor:  [0.0640, 0.7694, 0.8720, 0.1159],
        // the credit and the copyright are stacked barely a line apart in this
        // frame, so both plates are cut thin enough to keep a channel between
        artist:  [0.0640, 0.9160, 0.4500, 0.0220],
        year:    [0.0640, 0.9420, 0.6000, 0.0210],
        // x 365..445 at its widest, y 607..643 — as 2015, the rectangle runs
        // through the middle of the bulge rather than round its crown
        pt:      [0.7495, 0.8926, 0.1650, 0.0529],
        notches: {},

        // The same capped bars as 2015, drawn shallower: the title bar's right
        // edge runs 448.1, 451.1, 452.9 at the middle, then back to 449.2 over
        // a 34px height, so about 4.4px of bulge against the newer frame's
        // 5.8. Where the two really part company is everywhere else — this
        // frame's text box is square-cornered, and its P/T box is a properly
        // rounded box — a 7.5px radius on a 36px height, against a bulge of
        // barely 1.5px — rather than a bulged one, which is why the P/T is
        // the region that changes most visibly between these two frames.
        shapes: {
            name:    { r: [0.0061, 0, 0, 0.0061], bow: [0, 0, 0, 0.0090] },
            cost:    { r: [0, 0.0061, 0.0061, 0], bow: [0, 0.0090, 0, 0] },
            type:    { r: [0.0061, 0, 0, 0.0061], bow: [0, 0, 0, 0.0076] },
            subtype: { r: [0, 0, 0, 0] },
            set:     { r: [0, 0.0061, 0.0061, 0], bow: [0, 0.0076, 0, 0] },
            oracle:  { r: [0.0031, 0.0031, 0, 0] },
            flavor:  { r: [0, 0, 0.0031, 0.0031] },
            pt:      { r: [0.0154, 0.0154, 0.0154, 0.0154],
                       bow: [0, 0.0031, 0, 0.0031] }
        }
    },

    // no title box at all — the name is set straight on the frame. Credit and
    // copyright are centred, stacked, inside the card.
    "1997": {
        name:    [0.1000, 0.0441, 0.5600, 0.0368],
        cost:    [0.6800, 0.0441, 0.2500, 0.0368],
        type:    [0.1000, 0.5559, 0.2400, 0.0397],
        subtype: [0.3500, 0.5559, 0.3900, 0.0397],
        set:     [0.7500, 0.5559, 0.1600, 0.0397],
        oracle:  [0.1025, 0.6059, 0.7991, 0.1400],
        flavor:  [0.1025, 0.7459, 0.7991, 0.1365],
        artist:  [0.2000, 0.9000, 0.6000, 0.0235],
        year:    [0.2000, 0.9265, 0.6000, 0.0176],
        pt:      [0.8400, 0.8950, 0.1100, 0.0430],
        // this frame hangs the P/T clear of the text box — nothing to carve
        notches: {},

        // The only box this frame prints is the text box, and it is a plain
        // rectangle: its top edge holds 406.1 to within a twentieth of a pixel
        // from corner to corner, and turns the corner in about one. Everything
        // else on the card — the name, the cost, the type line, the P/T — is
        // set straight onto the frame with no box under it at all, so those
        // regions have nothing to trace and stay plain.
        shapes: {
            oracle: { r: [0.0020, 0.0020, 0, 0] },
            flavor: { r: [0, 0, 0.0020, 0.0020] }
        }
    },

    // as 1997, but the text box is inset further and the credit runs left
    "1993": {
        name:    [0.1000, 0.0441, 0.5600, 0.0368],
        cost:    [0.6800, 0.0441, 0.2500, 0.0368],
        type:    [0.1000, 0.5500, 0.2400, 0.0400],
        subtype: [0.3500, 0.5500, 0.3900, 0.0400],
        set:     [0.7500, 0.5500, 0.1600, 0.0400],
        oracle:  [0.1170, 0.6103, 0.7740, 0.1400],
        flavor:  [0.1170, 0.7503, 0.7740, 0.1290],
        artist:  [0.1000, 0.8985, 0.4500, 0.0294],
        year:    [0.1000, 0.9320, 0.6000, 0.0206],
        pt:      [0.8600, 0.9000, 0.1000, 0.0430],
        notches: {},

        // as 1997: one box on the whole card, and barely rounded at that
        shapes: {
            oracle: { r: [0.0041, 0.0041, 0, 0] },
            flavor: { r: [0, 0, 0.0041, 0.0041] }
        }
    }
}

// Frames with too few cards in the pool to be worth measuring, pointed at the
// one they were drawn from. "future" is the Future Sight timeshifted frame —
// fifty cards, laid out on the 2003 skeleton.
var ALIASES = { "future": "2003" }

var DEFAULT = "2015"

function regions(frame) {
    var key = ALIASES[frame] || frame
    return FRAMES[key] || FRAMES[DEFAULT]
}

// How one region's plate is cut on one frame. Empty for a region this frame
// prints no box under — the plate falls back to a plain rounded rectangle,
// which is the honest answer when there is no printed edge to follow.
function shape(frame, region) {
    return (regions(frame).shapes || {})[region] || {}
}

// The arch the text box takes over the holofoil stamp, as [centre, half-width,
// rise] — see the 2015 frame's `stamp`. The span is handed back whatever the
// card is and only the rise goes to zero when there is no stamp to clear, so
// that a rare following a common flattens the arch out of the plate rather
// than having one appear from nowhere at full height.
//
// Frames before 2015 printed no stamp at all, and neither does anything below
// rare on the frames that do. Scryfall's odd rarities — "special" and "bonus",
// which are mostly promos and Mystery Booster printings — are left unstamped:
// they are stamped inconsistently in print, so the safe reading is the one
// that leaves the plate covering ground the card is not using.
function stamp(frame, rarity) {
    var s = regions(frame).stamp
    if (!s) return [0, 0, 0]
    var stamped = rarity === "rare" || rarity === "mythic"
    return [s[0], s[1], stamped ? s[2] : 0]
}
