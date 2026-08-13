import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import "Retro.js" as Retro
import "CardFrames.js" as CardFrames

ApplicationWindow {
    id: window
    visible: true
    width: 1440
    height: 900
    title: "MTG Commander Deck Builder — Phase 2"
    color: "#d9d9dc"

    // ---- the edges the system keeps -------------------------------------
    // A phone does not hand the app the screen any more. From Android 15 an app
    // that targets SDK 35 or higher is laid out edge to edge whether it asks to
    // be or not — QT_ANDROID_TARGET_SDK_VERSION in CMakeLists.txt is 36 — and
    // from Android 16 the flag that used to opt out of that is ignored. So the
    // window genuinely does start at the top of the screen, underneath the
    // status bar, and it is the app's job to keep anything you need to touch
    // out from under it. Qt applies none of this for you; it only measures it.
    //
    // Everything below is zero on desktop and in the browser, so the four
    // margins can be spent without asking which platform this is.
    Loader {
        id: systemInsets
        active: safeAreaSupported
        source: "SafeInsets.qml"
        // The whole window, and it has to be said in exactly this way.
        //
        // A child declared here is parented to the ApplicationWindow's
        // contentItem, which starts below the header — measuring the status bar
        // against that is measuring it against the one part of the window it
        // cannot reach, and the answer is always zero. Window.contentItem is
        // the root of the scene and does span the header.
        //
        // The size is bound to the window rather than anchored to the parent
        // because `anchors.fill: parent` is resolved against the parent this
        // had at creation, and reassigning `parent` afterwards drops the
        // anchor without a word — leaving a 0x0 probe that dutifully reports no
        // margins at all, on every platform, forever.
        parent: Window.contentItem
        width: window.width
        height: window.height
        // measured, never seen: an Item with no content paints nothing and
        // accepts no input, and this keeps it behind everything regardless
        z: -1
    }
    // `|| 0` rather than a bare read: an unresolved margin would come back
    // undefined and land in the layout as NaN, which does not fail loudly — it
    // collapses whatever it is anchoring to nothing at all.
    readonly property real safeTop: systemInsets.item ? (systemInsets.item.insetTop || 0) : 0
    readonly property real safeBottom: systemInsets.item ? (systemInsets.item.insetBottom || 0) : 0
    readonly property real safeLeft: systemInsets.item ? (systemInsets.item.insetLeft || 0) : 0
    readonly property real safeRight: systemInsets.item ? (systemInsets.item.insetRight || 0) : 0
    // ---- the card face doubles as the filter form ------------------------
    // Every control lives where that thing lives on a real Magic card: the
    // name bar takes the name, the text box takes rules text, the set symbol
    // carries set and rarity, the frame carries colour identity. Regions too
    // cramped to type into open a popover pinned to themselves instead.
    // Geometry is in fractions of the card frame — see the block above the
    // regions themselves for where the numbers come from.

    // corner tab naming the region you are working in
    component FieldTag: Rectangle {
        property string label: ""
        width: tagText.implicitWidth + 12
        height: tagText.implicitHeight + 8
        color: Retro.plate
        border.color: Retro.blue
        border.width: 2
        z: 6
        // flush against the region's top-left corner, nudged back onto the
        // card for regions that sit at the very top or right of the frame
        x: Math.max(-parent.x, Math.min(0, card.width - parent.x - width))
        y: Math.max(-parent.y, -height + 1)
        Text {
            id: tagText
            anchors.centerIn: parent
            text: parent.label
            font.pixelSize: Retro.small
            color: Retro.inkHot
        }
    }

    // A region's cut, taken from fractions of the frame to pixels of the card
    // as drawn. Radii scale off the width alone: a radius is a single length,
    // and giving it one axis is what keeps a corner circular on a card that is
    // half again as tall as it is wide. A bulge scales off whichever axis it
    // pushes along. Both hand back an empty array where the frame prints no
    // box, which is CardPlate's cue to fall back to a plain rounded plate.
    function plateRadii(shape) {
        var r = shape.r
        return r ? [card.width * r[0], card.width * r[1],
                    card.width * r[2], card.width * r[3]] : []
    }
    function plateBows(shape) {
        var b = shape.bow
        return b ? [card.height * b[0], card.width * b[1],
                    card.height * b[2], card.width * b[3]] : []
    }

    // a region you type straight into — it masks the printed text so the
    // card reads as a blank form waiting to be filled in
    //
    // The plate is the application's own panel grey, not a card colour: these
    // are the form, and the form is chrome laid over the card. A plate tinted
    // to the frame reads as part of the printed card, which is exactly the
    // wrong thing for the one part of it you are meant to fill in — and it puts
    // a second colour on a face whose own colours already mean something. Grey
    // is the one tone the card never wears, so a plate can never be mistaken
    // for a region of the art beneath it. Rarity is the single exception (see
    // raritySwatch): the set symbol's colour is a value you set, not decoration.
    component CardField: Item {
        id: field
        property string label: ""
        property string hint: ""
        property color plate: "#d4d4d8"
        property int textAlign: TextInput.AlignVCenter
        property alias text: fieldInput.text
        property bool lit: fieldInput.activeFocus || fieldHover.hovered

        // Where this field sits, as [fx, fy, fw, fh] fractions of the frame —
        // see CardFrames.js. Magic has redrawn its card four times and put the
        // regions in different places each time, so when the face changes to a
        // card from another frame the whole form walks to its new positions
        // rather than jumping. The move is timed to the image swapping
        // underneath it, so the two read as one change.
        property var region: [0, 0, 0, 0]
        // a bite out of the bottom-right corner, as fractions of the frame, for
        // regions another region has to share a corner with — see CardPlate
        property var notch: [0, 0]
        // How the plate is cut to the box printed under it: corner radii and
        // edge bulges, again as fractions of the frame, and again from the
        // table — { r: [...], bow: [...] }, or {} where this frame prints no
        // box here. See window.regionShape.
        property var shape: ({})
        // an arch out of the bottom edge, as [centre, half-width, rise]
        // fractions of the frame, for a region the card prints something
        // through — see window.stampArch
        property var stamp: [0, 0, 0]
        x: card.width * region[0]
        y: card.height * region[1]
        width: card.width * region[2]
        height: card.height * region[3]
        Behavior on x      { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
        Behavior on y      { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }

        // the region you are working in comes to the front, so its corner tag
        // isn't painted over by whichever neighbour happens to be declared after
        // it — the tag sits outside its own region, in a neighbour's space
        z: lit ? 10 : 0

        CardPlate {
            anchors.fill: parent
            fill: field.plate
            strokeWidth: field.lit ? 2 : 1
            stroke: field.lit ? "#4d7bd6" : Qt.darker(field.plate, 1.3)
            // the cut, the bulges and the bite all ease on the same curve the
            // region moves on — CardPlate holds those Behaviors, so a frame
            // change is one gesture and not four
            radii: window.plateRadii(field.shape)
            bows: window.plateBows(field.shape)
            notchWidth: card.width * field.notch[0]
            notchHeight: card.height * field.notch[1]
            // the arch is given in the card's own coordinates and the plate
            // wants its own, so the centre comes back to the plate's left edge
            scallop: [card.width * field.stamp[0] - field.x,
                      card.width * field.stamp[1],
                      card.height * field.stamp[2]]
        }
        HoverHandler { id: fieldHover }
        TextField {
            id: fieldInput
            anchors.fill: parent
            leftPadding: 5
            rightPadding: 4
            topPadding: field.textAlign === TextInput.AlignTop ? 3 : 0
            bottomPadding: 0
            verticalAlignment: field.textAlign
            background: null
            color: "#33333a"                    // the panel's own ink
            // the hint is drawn below rather than handed to placeholderText —
            // see there for why
            font.pixelSize: Retro.body
            selectByMouse: true
            // typing schedules the search; Enter, or the focus moving on to
            // another region, runs it at once — see window.noteTextEdited
            onTextChanged: window.noteTextEdited()
            onAccepted: window.commitText()
            onActiveFocusChanged: if (!activeFocus) window.commitText()
        }

        // The hint, drawn here rather than given to the TextField's own
        // placeholderText.
        //
        // A region starts as the zero-sized rectangle this component declares
        // and takes its real geometry from the frame table a moment later, and
        // a TextField lays its placeholder out against whatever it measured at
        // creation. A centred one is re-placed whenever the height changes, so
        // it catches up on its own; a top-aligned one is not, and stays at the
        // size it was born with — which is nothing. That is why the two text
        // box regions, the only two that align to the top, came up permanently
        // blank while every other region showed its hint. Anything that forced
        // a second layout brought them back, which is what made it look like a
        // problem with the words rather than with when they were measured.
        //
        // A Text bound to the region has no such moment: it follows the frame
        // wherever it goes. Below the tag and above the plate, matching the
        // input's own padding and alignment so the hint sits exactly where the
        // text you type will replace it.
        Text {
            anchors.fill: parent
            leftPadding: 5
            rightPadding: 4
            topPadding: field.textAlign === TextInput.AlignTop ? 3 : 0
            verticalAlignment: field.textAlign
            visible: fieldInput.text === ""
            text: field.hint
            elide: Text.ElideRight
            color: "#8b8b94"
            font.pixelSize: Retro.body
        }
        FieldTag { label: field.label; visible: field.lit }
    }

    // a region too small to type into: shows the value you set, and opens
    // its popover when tapped
    component CardTrigger: Item {
        id: trig
        property string label: ""
        property string summary: ""      // current value; "" when unfiltered
        property string hint: ""
        property color plate: "#d4d4d8"
        property bool open: false
        property bool lit: open || trigHover.hovered
        // colour letters to draw as mana pips ahead of the summary text
        property var pips: []
        // What the label will actually show — the hint stands in for an empty
        // region, but pips already fill one. Resolved here, at the top, so the
        // metrics that reserve room for it and the label that draws it both
        // read one string and neither reaches forward to the other: an id
        // declared further down the component does not exist yet when a
        // binding above it is first evaluated.
        readonly property string display: summary !== "" ? summary
                                        : (pips.length > 0 ? "" : hint)
        signal tapped()

        property var region: [0, 0, 0, 0]   // as CardField — see CardFrames.js
        property var shape: ({})            // as CardField — its cut
        x: card.width * region[0]
        y: card.height * region[1]
        width: card.width * region[2]
        height: card.height * region[3]
        Behavior on x      { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
        Behavior on y      { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }

        z: lit ? 10 : 0          // as CardField: the lit region owns the front

        CardPlate {
            anchors.fill: parent
            fill: trig.plate
            strokeWidth: trig.lit ? 2 : 1
            stroke: trig.lit ? "#4d7bd6" : Qt.darker(trig.plate, 1.3)
            radii: window.plateRadii(trig.shape)
            bows: window.plateBows(trig.shape)
        }
        HoverHandler { id: trigHover; cursorShape: Qt.PointingHandCursor }

        // How wide the label wants to be, measured off the string rather than
        // off the label: the label is sized by what the pips leave, so asking
        // it its own width is a loop. The face is the application font, set on
        // the QGuiApplication, so pixel size is the only thing to match.
        TextMetrics {
            id: summaryMetrics
            font.pixelSize: Retro.body
            text: trig.display
        }

        // The value shown as pips rather than spelled out, where the value is
        // something the card itself draws as a symbol. A region that reads
        // "WUG" is telling you what you picked in the popover's words; the same
        // region wearing three mana pips is telling you in the card's, and you
        // can read it without opening anything.
        Item {
            id: pipStrip
            // hard right, with the summary to its left: a printed mana cost
            // reads generic-then-coloured, "{3}{W}{U}", and this region is
            // standing in for one
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            height: 16
            visible: trig.pips.length > 0

            // The sprites are 16px and are never scaled — pixel art on half
            // pixels is the one thing this whole look can't survive. So when
            // there are more than the region can lay side by side, they close
            // up and overlap like stacked coins instead of shrinking. Even a
            // sliver of one is legible: these six are told apart by colour
            // long before shape.
            //
            // Whatever the summary needs comes off the budget first. Losing the
            // mana value to a row of pips would trade one thing you have to
            // open the popover to read for another. Never more than half the
            // region, either way.
            property int budget: trig.width - 6
                - (trig.display !== ""
                   ? Math.min(summaryMetrics.width, trig.width * 0.5) + 4 : 0)
            property int step: trig.pips.length > 1
                ? Math.max(6, Math.min(17,
                    (budget - 16) / (trig.pips.length - 1)))
                : 0
            width: trig.pips.length > 0 ? 16 + step * (trig.pips.length - 1) : 0

            Repeater {
                model: trig.pips
                delegate: PixelIcon {
                    sprite: "mtg-pip-" + String(modelData).toLowerCase()
                    pixelScale: 1
                    x: index * pipStrip.step
                }
            }
        }

        Text {
            id: trigText
            anchors.verticalCenter: parent.verticalCenter
            // takes whatever the pips leave: on its own that is the whole
            // region and it centres, beside pips it closes up against them so
            // the two read as one cost
            anchors.left: parent.left
            anchors.leftMargin: 3
            anchors.right: pipStrip.left
            anchors.rightMargin: pipStrip.visible ? 4 : 0
            horizontalAlignment: pipStrip.visible ? Text.AlignRight
                                                  : Text.AlignHCenter
            elide: Text.ElideRight
            text: trig.display
            color: trig.summary !== "" ? "#33333a" : "#8b8b94"
            font.pixelSize: Retro.body
        }
        TapHandler { onTapped: trig.tapped() }
        FieldTag { label: trig.label; visible: trig.lit }
    }

    // Shared chrome for the popovers the small regions open.
    //
    // They sit *beside* the card, never over it. A popover covering another
    // region makes that region unclickable — the click lands on the popover
    // and nothing happens — so you can't move straight from one region to the
    // next. Vertically each one centres on the region it belongs to, which is
    // what keeps it reading as that region's popover rather than a loose panel.
    component FilterPopup: Popup {
        // the card region this popover edits; drives its vertical position
        property Item region: null

        // Beside the card it is 250 wide, which is what its two spinners and a
        // dash need. Over the card it takes the card's width less a margin, so
        // it can never hang off the screen edge with half a control on it.
        width: window.narrow ? Math.min(card.width - 16, 320) : 250
        padding: 12
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: RetroPanel {}

        // Leaving a popover is committing what you typed in it. Clicking away,
        // Escape, or opening another region's popover all end up here, so text
        // never waits on the debounce once you have moved on from it. Costs
        // nothing when nothing was typed — commitText is a no-op then.
        onClosed: window.commitText()

        // Wide, beside the card, centred on the region it belongs to.
        //
        // Narrow, there is no beside — the card is the width of the screen. So
        // it drops *under* its region instead, centred horizontally on the
        // card: directly below is the one place that can't cover the region you
        // are editing, which is the whole reason these never sat over the card
        // in the first place. A region near the bottom of the card would put it
        // off the end, so it flips above that region instead, and the clamp
        // catches whatever is left.
        x: window.narrow ? (card.width - width) / 2 : card.width + 10
        y: {
            if (!region) return 0
            if (!window.narrow)
                return Math.max(0, region.y + region.height / 2 - height / 2)
            var below = region.y + region.height + 8
            var placed = below + height <= card.height ? below
                                                       : region.y - height - 8
            return Math.max(0, Math.min(card.height - height, placed))
        }
    }

    // a heading inside an overlay
    component PanelLabel: Label {
        font.pixelSize: Retro.body
        color: Retro.inkHot
    }

    // a rule between groups in a popover that holds more than one
    component PanelDivider: Rectangle {
        width: parent.width
        height: 1
        color: Retro.bevel
        opacity: 0.4
    }

    // ---- top bar ----------------------------------------------------------
    // Nothing up here is part of the query. The card face down in the panel is
    // the whole of the form; the bar carries only what came back from it — how
    // many matched and in what order they arrive — plus the one switch that
    // cannot live inside the workspace it closes. Keeping the split at the
    // window's own edge is what the panel used to spend a rule and a paragraph
    // saying. The bar is cut to exactly one control's height, and nothing that
    // would make it grow is allowed up here.
    header: Rectangle {
        // the sprites' 16 rows doubled, plus a pixel of air either side —
        // and then whatever the status bar is standing on, because this is the
        // band at the top of the window and so it is this that ends up beneath
        // it. The bar grows rather than moves: the extra height is painted in
        // the bar's own grey, so the status bar sits on a strip that matches
        // instead of on whatever happened to be behind it, and the controls
        // below are pushed down clear of it by the same amount.
        implicitHeight: 36 + window.safeTop
        color: "#cfcfd3"

        // Every control in here centres on the bar, so each one is nudged down
        // by half the strip to centre on the 36 that are left rather than on
        // the taller rectangle. Naming it once keeps the three of them in step.
        readonly property real barOffset: window.safeTop / 2

        // the search form's switch, at the end of the bar the form is under —
        // the mirror of the workspace switch at the other end
        PixelButton {
            id: panelToggle
            sprite: "mtg-icon-search"
            pixelScale: 2
            // not `checkable`: a checkable button assigns its own `checked` on
            // click, which throws away the binding below. The window owns
            // whether the form is open — in the narrow layout opening one side
            // shuts the other, so this button has to be able to come back up
            // without having been clicked. See PixelButton.
            checked: window.panelOpen
            tooltip: "Show or hide the search form"
            anchors.left: parent.left
            anchors.leftMargin: 6 + window.safeLeft
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: parent.barOffset
            onClicked: window.openSide("panel", !window.panelOpen)
        }

        Row {
            // flush with the gallery's first column rather than the window's
            // edge: the count and the order both describe the grid, so they
            // start where it starts and follow it when the panel shuts — up to
            // the switch above, which the gallery is allowed to slide under but
            // this is not.
            //
            // In the narrow layout the panel is a sheet laid over the gallery
            // rather than a column beside it, so there is no first column to be
            // flush with and this sits straight after the switch.
            anchors.left: parent.left
            // The gallery it lines up with is inside the inset content area,
            // so the wide branch counts from there rather than from the window
            // edge. The narrow branch measures off the switch, which has
            // already been moved, and so needs nothing added.
            anchors.leftMargin: window.narrow
                ? panelToggle.x + panelToggle.width + 8
                : Math.max(window.safeLeft + filterPanel.width
                               + grid.anchors.leftMargin,
                           panelToggle.x + panelToggle.width + 10)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: parent.barOffset
            spacing: window.narrow ? 5 : 8

            // the one number you watch while you are narrowing things down, so
            // it keeps the larger size it had in the panel
            Label {
                // The number is the thing; the word is what tells you what it
                // counts. On a narrow bar the word goes and the number stays —
                // by then it is the only number up here, and the sort dropdown
                // beside it has already said these are cards.
                text: window.narrow ? cardModel.count
                                    : cardModel.count + " cards"
                font.pixelSize: Retro.title
                color: "#33333a"
                anchors.verticalCenter: parent.verticalCenter
            }

            // The word "Sort" and the rule before it are what the dropdown
            // can't say for itself on a wide bar. On a narrow one they are the
            // first things to go: a dropdown reading "Name" beside a card count
            // is already unambiguous, and the room they cost is room the
            // dropdown itself needs.
            ToolSeparator {
                height: 24
                visible: !window.narrow
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                text: "Sort"
                visible: !window.narrow
                font.pixelSize: Retro.body
                color: "#33333a"
                anchors.verticalCenter: parent.verticalCenter
            }
            RetroCombo {
                id: sortOrder
                // wide enough for "EDHREC rank", the longest of them; it can't
                // fill the bar the way it filled the panel's width
                width: window.narrow ? 112 : 150
                height: 32
                anchors.verticalCenter: parent.verticalCenter
                model: ["Name", "Mana value", "EDHREC rank",
                        "Set release", "Rarity"]
                onActivated: cardModel.setSortOrder(
                    ["name", "cmc", "edhrec", "set", "rarity"][currentIndex])
            }
            PixelButton {
                id: sortDirection
                property bool descending: false
                // two sprites rather than a rotated one: rotating the art would
                // take the button's bevel round with it
                sprite: descending ? "mtg-icon-sort-desc"
                                   : "mtg-icon-sort-asc"
                pixelScale: 2
                tooltip: descending ? "Descending" : "Ascending"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                    descending = !descending
                    cardModel.setSortDescending(descending)
                }
            }
        }

        PixelButton {
            sprite: "mtg-icon-panel"
            pixelScale: 2
            // as the search switch: bound, not self-toggling
            checked: window.dockOpen
            tooltip: "Show or hide the deck workspace"
            // right-hand end of the bar, over the side it opens and shuts
            anchors.right: parent.right
            anchors.rightMargin: 6 + window.safeRight
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: parent.barOffset
            onClicked: window.openSide("dock", !window.dockOpen)
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: "#b6b6bc"
        }
    }

    // ---- filter panel + card grid ---------------------------------------
    Item {
        anchors.fill: parent
        // The three columns stop at the edges the system kept: the gesture bar
        // or navigation buttons along the bottom, and a cutout or a curved
        // corner at the sides in landscape. The top is not among them — the
        // header above has already taken the status bar's height out of what
        // this fills. Zero everywhere but a phone.
        anchors.leftMargin: window.safeLeft
        anchors.rightMargin: window.safeRight
        anchors.bottomMargin: window.safeBottom

        Rectangle {
            id: filterPanel
            // shut the same way the deck workspace shuts, and at the same
            // speed, so the two sides of the gallery behave as one pair.
            // Narrow, it takes the whole width and lies over the gallery
            // instead of beside it — see window.narrow.
            width: window.panelOpen ? (window.narrow ? parent.width : 340) : 0
            visible: width > 0
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            color: "#cfcfd3"
            clip: true
            // above the gallery only when it is covering it; side by side the
            // stacking order never comes up
            z: window.narrow ? 20 : 0
            Behavior on width { NumberAnimation { duration: 140 } }

            Flickable {
                anchors.fill: parent
                anchors.margins: 12
                contentHeight: panelColumn.height
                clip: true
                ScrollBar.vertical: ScrollBar {}

                Column {
                    id: panelColumn
                    width: parent.width
                    spacing: 12

                    // -- the card face IS the filter form
                    Item {
                        id: card
                        objectName: "card"
                        width: parent.width
                        // exactly the card image's own 488x680, so the art fits
                        // the item edge to edge — any other ratio letterboxes it
                        // inside the item and every region fraction drifts off
                        // the frame it was measured against
                        height: width * (680 / 488)

                        // The face you fill in is a card the filters would
                        // really turn up — see window.previewFace. Two layers,
                        // because swapping one Image's source blanks it while
                        // the next comes down off the CDN: the outgoing face
                        // holds underneath until the incoming one is ready, so
                        // changing a filter never flashes the panel empty.
                        Image {
                            id: previousCard
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            visible: exampleCard.opacity < 1
                        }
                        Image {
                            id: exampleCard
                            anchors.fill: parent
                            source: window.previewFace
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            // Once this one is up it becomes the face to hold
                            // through the next swap — and this is the moment
                            // the form is allowed to move, because it is the
                            // moment the new card becomes the one you can see.
                            // Error counts too: the plates should not sit on a
                            // frame whose art never arrived.
                            onStatusChanged: {
                                if (status === Image.Ready)
                                    previousCard.source = source
                                if (status === Image.Ready || status === Image.Error) {
                                    window.previewFrame = window.pendingFrame
                                    window.previewRarity = window.pendingRarity
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: exampleCard.status !== Image.Ready
                                     && previousCard.status !== Image.Ready
                            radius: 12
                            color: "#ded9cf"
                            border.color: "#b3ac9a"
                            Text {
                                anchors.centerIn: parent
                                text: "Card face…"
                                color: "#a49a83"
                            }
                        }

                        // The wash half of the no-match beat (emptyBeat below
                        // carries the border). It sits here, above the art but
                        // below everything declared after it, so it reddens the
                        // card without reddening the form: the plates are the
                        // controls you are about to go and fix, and they stay
                        // the neutral grey they are everywhere else.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 13
                            color: "#38c81f24"
                            opacity: emptyBeat.opacity
                            visible: opacity > 0
                        }

                        // naming the card you are looking at, since the Name
                        // region's plate is sitting on top of its printed name.
                        // The art is deliberately not a click target (see the
                        // frame hotspots below), so this only ever hovers.
                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: card.width * 0.10
                            anchors.rightMargin: card.width * 0.10
                            anchors.topMargin: card.height * 0.12
                            anchors.bottomMargin: card.height * 0.48
                            HoverHandler { id: faceHover }
                            ToolTip.visible: faceHover.hovered
                                             && cardModel.previewName !== ""
                            ToolTip.delay: 600
                            ToolTip.text: cardModel.previewName
                        }

                        // -- colour identity lives in the frame, as in print,
                        // but the popover it opens is the mana one: picking
                        // colours and picking what they cost is one decision,
                        // so the frame is a second door into the same room.
                        // The border strips are the hotspot; clicking the art
                        // is not, so you can't open it by accident.
                        Item {
                            id: frameZone
                            anchors.fill: parent
                            property int hoverCount: 0

                            Repeater {
                                model: [
                                    { fx: 0.000, fy: 0.000, fw: 0.076, fh: 1.000 },
                                    { fx: 0.926, fy: 0.000, fw: 0.074, fh: 1.000 },
                                    { fx: 0.000, fy: 0.000, fw: 1.000, fh: 0.050 },
                                    { fx: 0.000, fy: 0.960, fw: 1.000, fh: 0.040 }
                                ]
                                delegate: MouseArea {
                                    x: card.width * modelData.fx
                                    y: card.height * modelData.fy
                                    width: card.width * modelData.fw
                                    height: card.height * modelData.fh
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: manaPopup.open()
                                    onEntered: frameZone.hoverCount++
                                    onExited: frameZone.hoverCount--
                                }
                            }
                        }
                        // the frame takes on the colours you filter to
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 13
                            color: "transparent"
                            border.width: frameZone.hoverCount > 0 || manaPopup.opened ? 5 : 4
                            border.color: frameZone.hoverCount > 0 || manaPopup.opened
                                ? "#4d7bd6" : window.identityTint
                            visible: window.identityTint !== "transparent"
                                     || frameZone.hoverCount > 0 || manaPopup.opened
                            z: 4
                        }

                        // -- nothing matches: the card beats red
                        // A card held steady in red would just read as another
                        // colour the frame can take — the identity tint already
                        // paints it red for mono-red filters. Beating is the one
                        // thing the frame never does on its own, so it can't be
                        // mistaken for a filter you set. The face underneath is
                        // left on the last card that did match, rather than
                        // blanked: a card beating red says "there is nothing
                        // past this", where an empty panel only says "loading".
                        Rectangle {
                            id: emptyBeat
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 13
                            color: "transparent"        // the wash is above the art
                            border.width: 5
                            border.color: "#d81c21"
                            opacity: 0
                            visible: opacity > 0
                            z: 5

                            SequentialAnimation on opacity {
                                running: cardModel.count === 0
                                loops: Animation.Infinite
                                // lub-dub: two beats close together, then the
                                // rest that makes them read as a pulse
                                NumberAnimation {
                                    to: 1; duration: 110; easing.type: Easing.OutQuad
                                }
                                NumberAnimation {
                                    to: 0.32; duration: 150; easing.type: Easing.InQuad
                                }
                                NumberAnimation {
                                    to: 0.8; duration: 100; easing.type: Easing.OutQuad
                                }
                                NumberAnimation {
                                    to: 0; duration: 420; easing.type: Easing.InQuad
                                }
                                PauseAnimation { duration: 400 }
                                // an animation on a property keeps the value it
                                // stopped on; put the card back when it stops
                                onRunningChanged: if (!running) emptyBeat.opacity = 0
                            }
                        }
                        Rectangle {   // label chip on the bottom border
                            visible: frameZone.hoverCount > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: card.height * 0.955 - height / 2
                            width: identityChip.implicitWidth + 12
                            height: identityChip.implicitHeight + 6
                            radius: 4
                            color: Qt.rgba(0.176, 0.310, 0.561, 0.94)
                            border.color: "#8fb0e6"
                            z: 6
                            Text {
                                id: identityChip
                                anchors.centerIn: parent
                                text: "Colour identity"
                                font.pixelSize: Retro.body
                                color: "white"
                            }
                        }

                        // -- the printed regions, now editable
                        //
                        // Each one takes its place from the frame table for
                        // whichever card is currently the face — see
                        // CardFrames.js for the geometry and how it was
                        // measured. Nothing here holds a coordinate.
                        CardField {
                            id: nameField
                            label: "Name"
                            hint: "any name"
                            region: window.frameGeometry.name
                            shape: window.regionShape("name")
                        }
                        CardTrigger {
                            id: costTrigger
                            label: "Mana, colour & value"
                            hint: "cost"
                            summary: window.costSummary
                            // the colours you picked, in the card's own symbols
                            pips: window.costColors
                            open: manaPopup.opened
                            region: window.frameGeometry.cost
                            shape: window.regionShape("cost")
                            onTapped: manaPopup.open()
                        }
                        // The type bar is split where the em dash falls on a
                        // card whose types read "Creature —" — far and away the
                        // commonest, and the split the eye is trained on. A
                        // longer line ("Legendary Artifact Creature —") pushes
                        // its dash right, but no fixed boundary can track that.
                        CardTrigger {
                            id: typeTrigger
                            label: "Type"
                            hint: "type"
                            summary: window.typeSummary
                            open: typePopup.opened
                            region: window.frameGeometry.type
                            shape: window.regionShape("type")
                            onTapped: typePopup.open()
                        }
                        CardTrigger {
                            id: subtypeTrigger
                            label: "Subtype"
                            hint: "subtype"
                            summary: window.subtypeSummary
                            open: subtypePopup.opened
                            region: window.frameGeometry.subtype
                            shape: window.regionShape("subtype")
                            onTapped: subtypePopup.open()
                        }
                        CardTrigger {
                            id: setTrigger
                            label: "Set & rarity"
                            hint: "set"
                            summary: window.setSummary
                            // the set symbol takes the rarity's colour, as in print
                            plate: window.raritySwatch
                            open: setPopup.opened
                            region: window.frameGeometry.set
                            shape: window.regionShape("set")
                            onTapped: setPopup.open()
                        }
                        // The text box holds two different things and so takes
                        // two regions. Where one ends and the other begins is
                        // not printed — it moves with how much rules text the
                        // card has — so the split goes where the flavour line
                        // starts on a card with a typical amount of both. The
                        // two plates are flush: a gap between them is a strip of
                        // the card's own printed text showing through, which
                        // reads as a hole rather than as breathing room.
                        CardField {
                            id: oracleField
                            label: "Rules text"
                            hint: "rules text — e.g. haste"
                            textAlign: TextInput.AlignTop
                            region: window.frameGeometry.oracle
                            shape: window.regionShape("oracle")
                        }
                        CardField {
                            id: flavorField
                            label: "Flavour text"
                            hint: "flavour text — the italic line"
                            textAlign: TextInput.AlignTop
                            // Runs to the bottom of the text box, and so takes
                            // both of the things that stand on that edge: the
                            // P/T box biting into the corner, and the holofoil
                            // stamp astride the middle of it on a rare or a
                            // mythic. The printed border arches over the stamp
                            // rather than running behind it, so covering it
                            // would be covering the one mark the card itself
                            // makes room for.
                            region: window.frameGeometry.flavor
                            shape: window.regionShape("flavor")
                            stamp: window.stampArch
                            notch: window.frameGeometry.notches.flavor || [0, 0]
                        }
                        CardTrigger {
                            id: artistTrigger
                            label: "Artist"
                            hint: "illustrator"
                            summary: window.artistSummary
                            open: artistPopup.opened
                            region: window.frameGeometry.artist
                            shape: window.regionShape("artist")
                            onTapped: artistPopup.open()
                        }
                        // The copyright notice is the only place a card prints
                        // its year, so that is where you set one. Which corner
                        // that is depends on the frame — beside the credit on a
                        // 2015 card, under it on every older one.
                        CardTrigger {
                            id: yearTrigger
                            label: "Year printed"
                            hint: "year"
                            summary: window.yearSummary
                            open: yearPopup.opened
                            region: window.frameGeometry.year
                            shape: window.regionShape("year")
                            onTapped: yearPopup.open()
                        }
                        CardTrigger {
                            id: ptTrigger
                            label: "Power / toughness"
                            hint: "P/T"
                            summary: window.ptSummary
                            open: ptPopup.opened
                            region: window.frameGeometry.pt
                            shape: window.regionShape("pt")
                            onTapped: ptPopup.open()
                        }

                        // -- popovers for the regions too small to type into

                        // Colour and mana value are one popover because they are
                        // one decision: you pick the colours, then immediately
                        // decide what they should cost. They sit next to each
                        // other here, with the free-text cost field underneath.
                        // Both the cost region and the card frame open it.
                        FilterPopup {
                            id: manaPopup
                            region: costTrigger
                            Column {
                                width: parent.width
                                spacing: 8

                                PanelLabel { text: "Colour identity" }
                                RetroCombo {
                                    id: colorMode
                                    width: parent.width
                                    model: ["Identity fits (deck rule)", "Exactly these",
                                            "Includes these"]
                                    onActivated: window.applyColors()
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 5
                                    Repeater {
                                        id: colorToggles
                                        model: [
                                            { c: "W", name: "White" },
                                            { c: "U", name: "Blue" },
                                            { c: "B", name: "Black" },
                                            { c: "R", name: "Red" },
                                            { c: "G", name: "Green" },
                                            { c: "C", name: "Colourless" }
                                        ]
                                        delegate: PixelButton {
                                            property string letter: modelData.c
                                            sprite: "mtg-pip-" + modelData.c.toLowerCase()
                                            pixelScale: 2
                                            checkable: true
                                            tooltip: modelData.name
                                            onClicked: window.applyColors()
                                        }
                                    }
                                }

                                PanelDivider {}

                                PanelLabel { text: "Mana value" }
                                Row {
                                    spacing: 6
                                    RetroSpin {
                                        id: cmcMin
                                        from: 0; to: 16; value: 0; width: 102
                                        onValueModified: window.applyCmcRange()
                                    }
                                    Label {
                                        text: "–"
                                        color: Retro.inkDim
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    RetroSpin {
                                        id: cmcMax
                                        from: 0; to: 16; value: 16; width: 102
                                        onValueModified: window.applyCmcRange()
                                    }
                                }

                                PanelDivider {}

                                PanelLabel { text: "Mana cost" }
                                RetroField {
                                    id: manaInput
                                    width: parent.width
                                    placeholderText: "e.g. 2GG or {G}{G}"
                                    onAccepted: window.commitText()
                                    onTextChanged: {
                                        // the cost region wears this string, so
                                        // it keeps up with the keystroke; the
                                        // query itself waits for the debounce
                                        window.refreshSummaries()
                                        window.noteTextEdited()
                                    }
                                }
                            }
                        }

                        FilterPopup {
                            id: setPopup
                            region: setTrigger
                            Column {
                                width: parent.width
                                spacing: 8
                                PanelLabel { text: "Set" }
                                RetroCombo {
                                    id: setPicker
                                    width: parent.width
                                    // rows carry their symbol as well as their
                                    // name — 274 sets read far faster by glyph
                                    textRole: "name"
                                    iconRole: "glyph"
                                    model: {
                                        var rows = [{ name: "All sets", glyph: "" }]
                                        for (var i = 0; i < cardModel.sets.length; i++) {
                                            var g = cardModel.sets[i].glyph
                                            rows.push({
                                                name: cardModel.sets[i].name,
                                                // the hot ink: these sit on the
                                                // overlay's dark plate, where the
                                                // tiles' black symbol would vanish
                                                glyph: g === "" ? ""
                                                     : "assets/sets-hot/set-" + g + ".png"
                                            })
                                        }
                                        return rows
                                    }
                                    onActivated: {
                                        window.commitText()
                                        cardModel.setFilter("set_codes", currentIndex === 0
                                            ? [] : [cardModel.sets[currentIndex - 1].code])
                                        window.refreshSummaries()
                                    }
                                }
                                PanelLabel { text: "Rarity" }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        id: rarityToggles
                                        model: [
                                            { r: "common", label: "C", color: Retro.lightgrey },
                                            { r: "uncommon", label: "U", color: Retro.blue },
                                            { r: "rare", label: "R", color: Retro.yellow },
                                            { r: "mythic", label: "M", color: Retro.orange }
                                        ]
                                        // a plate that lights up rather than a
                                        // sprite, because the letter is the label
                                        delegate: Rectangle {
                                            width: 46; height: 28
                                            property bool checked: false
                                            property string rarityKey: modelData.r
                                            color: checked ? modelData.color : Retro.plateDeep
                                            border.width: 2
                                            border.color: Retro.edge
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                color: "transparent"
                                                border.width: 1
                                                border.color: parent.checked
                                                    ? Qt.lighter(modelData.color, 1.4)
                                                    : Retro.darkblue
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: Retro.body
                                                color: parent.checked ? Retro.black : Retro.inkDim
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    parent.checked = !parent.checked
                                                    window.applyRarities()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        FilterPopup {
                            id: ptPopup
                            region: ptTrigger
                            Column {
                                width: parent.width
                                spacing: 8
                                PanelLabel { text: "Power" }
                                Row {
                                    spacing: 6
                                    RetroSpin {
                                        id: powerMin
                                        from: 0; to: 20; value: 0; width: 102
                                        onValueModified: window.applyPtRange()
                                    }
                                    Label {
                                        text: "–"
                                        color: Retro.inkDim
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    RetroSpin {
                                        id: powerMax
                                        from: 0; to: 20; value: 20; width: 102
                                        onValueModified: window.applyPtRange()
                                    }
                                }
                                PanelLabel { text: "Toughness" }
                                Row {
                                    spacing: 6
                                    RetroSpin {
                                        id: toughnessMin
                                        from: 0; to: 20; value: 0; width: 102
                                        onValueModified: window.applyPtRange()
                                    }
                                    Label {
                                        text: "–"
                                        color: Retro.inkDim
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    RetroSpin {
                                        id: toughnessMax
                                        from: 0; to: 20; value: 20; width: 102
                                        onValueModified: window.applyPtRange()
                                    }
                                }
                            }
                        }

                        FilterPopup {
                            id: yearPopup
                            region: yearTrigger
                            // Two spinners and a note make the shortest plate on
                            // the card, squat enough next to its neighbours to
                            // read as a different kind of thing. A floor under
                            // the height settles it without pinning it: more
                            // content still grows it.
                            // implicitContentHeight, not contentHeight: the
                            // latter is what the content was *given*, which is
                            // this height less the padding, so feeding it back
                            // in latches the plate at whatever it first reached
                            // and it could never shrink again.
                            implicitHeight: Math.max(
                                140, implicitContentHeight + topPadding + bottomPadding)
                            Column {
                                width: parent.width
                                spacing: 8
                                PanelLabel { text: "Year printed" }
                                Row {
                                    spacing: 6
                                    // the ends come from the pool itself, so a
                                    // refresh that adds next year's sets widens
                                    // the control without anyone editing it
                                    RetroSpin {
                                        id: yearMin
                                        from: cardModel.years[0]
                                        to: cardModel.years[1]
                                        value: cardModel.years[0]
                                        width: 102
                                        onValueModified: window.applyYearRange()
                                    }
                                    Label {
                                        text: "–"
                                        color: Retro.inkDim
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    RetroSpin {
                                        id: yearMax
                                        from: cardModel.years[0]
                                        to: cardModel.years[1]
                                        value: cardModel.years[1]
                                        width: 102
                                        onValueModified: window.applyYearRange()
                                    }
                                }
                                Label {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Retro.small
                                    color: Retro.inkDim
                                    text: "When the card's set was released, "
                                          + "not when the card was first printed."
                                }
                            }
                        }

                        // The type line's two halves work the artist region's
                        // way: too many words to type blind — 14 card types and
                        // 431 subtypes — but the filter behind them is still a
                        // substring match, so the list offers rather than binds.
                        FilterPopup {
                            id: typePopup
                            region: typeTrigger
                            onOpened: typeList.focusInput()
                            VocabList {
                                id: typeList
                                label: "Type"
                                placeholder: "type a card type…"
                                options: cardModel.types
                                onEdited: window.noteTextEdited()
                                onCommitted: window.applyTextFilters()
                            }
                        }

                        FilterPopup {
                            id: subtypePopup
                            region: subtypeTrigger
                            onOpened: subtypeList.focusInput()
                            VocabList {
                                id: subtypeList
                                label: "Subtype"
                                placeholder: "type a subtype…"
                                options: cardModel.subtypes
                                onEdited: window.noteTextEdited()
                                onCommitted: window.applyTextFilters()
                            }
                        }

                        FilterPopup {
                            id: artistPopup
                            region: artistTrigger
                            // select the name on open, so typing replaces the
                            // one already there instead of appending to it
                            onOpened: {
                                artistSearch.forceActiveFocus()
                                artistSearch.selectAll()
                            }
                            Column {
                                width: parent.width
                                spacing: 8
                                PanelLabel { text: "Artist" }
                                RetroField {
                                    id: artistSearch
                                    width: parent.width
                                    placeholderText: "type a name…"
                                    // Typing narrows the list below at once and
                                    // schedules the search. Filtering the grid
                                    // on every character resets the model on
                                    // every character — and a reset rebuilds
                                    // every tile and restarts its card-image
                                    // load, which costs far more than the query
                                    // does. So the query waits for a pause in
                                    // the typing; Enter, picking a name, or
                                    // leaving the popover runs it immediately.
                                    onTextChanged: window.noteTextEdited()
                                    onAccepted: window.commitText()
                                }
                                RetroPanel {
                                    width: parent.width
                                    // ten names rather than eight: the list is
                                    // the whole point of this popover, and it
                                    // was the shorter half of it
                                    height: Math.min(200, Math.max(0,
                                        artistList.count * 20))
                                    visible: height > 0
                                    sunken: true
                                    shadowOffset: 0
                                    plate: Retro.plateDeep
                                    ListView {
                                        id: artistList
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        ScrollBar.vertical: ScrollBar {}
                                        model: window.artistMatches
                                        // when the list re-opens after a pick,
                                        // scroll to the name you are on rather
                                        // than dumping you back at the letter A
                                        onModelChanged: {
                                            var i = window.artistMatches.indexOf(
                                                artistSearch.text)
                                            if (i < 0) return
                                            Qt.callLater(function () {
                                                artistList.positionViewAtIndex(
                                                    i, ListView.Center)
                                            })
                                        }
                                        delegate: Rectangle {
                                            width: artistList.width
                                            height: 20
                                            color: nameHover.hovered ? Retro.blue
                                                 : (modelData === artistSearch.text
                                                    ? Retro.darkblue : "transparent")
                                            HoverHandler { id: nameHover }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: 5
                                                width: parent.width - 10
                                                elide: Text.ElideRight
                                                text: modelData
                                                font.pixelSize: Retro.body
                                                color: nameHover.hovered ? Retro.black : Retro.ink
                                            }
                                            TapHandler {
                                                // picking a name is accepting it
                                                onTapped: {
                                                    artistSearch.text = modelData
                                                    window.applyTextFilters()
                                                }
                                            }
                                        }
                                    }
                                }
                                Label {
                                    width: parent.width
                                    visible: cardModel.artists.length === 0
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Retro.small
                                    color: Retro.inkDim
                                    text: "No artists in the database yet — "
                                          + "re-run scripts/ingest.py."
                                }
                            }
                        }

                    }

                    // -- the only controls left off the card
                    RetroCheck {
                        id: commandersOnly
                        text: "Commanders only"
                        textColor: "#33333a"        // on the light panel, not a plate
                        pixelScale: 2
                        font.pixelSize: Retro.title
                        spacing: 10
                        onToggled: {
                            window.commitText()
                            cardModel.setFilter("commanders_only", checked)
                        }
                    }

                    // Only what the open deck's commander legally allows. Kept
                    // separate from the colour-identity pips on the card so the
                    // two compose: this bounds the pool, those search inside it.
                    RetroCheck {
                        id: legalOnly
                        // The commander's name goes in the line below, not
                        // here: at this size the panel truncates it to
                        // "Legal for Atraxa, Pr…", and half a card name tells
                        // you less than none — you can't tell which deck it
                        // means, which is the one thing this has to say.
                        text: "Legal for commander"
                        width: parent.width
                        textColor: "#33333a"
                        pixelScale: 2
                        font.pixelSize: Retro.title
                        spacing: 10
                        enabled: deckStore.commanderId !== ""
                        opacity: enabled ? 1 : 0.45
                        onToggled: window.applyLegalIdentity()
                        // a new commander re-bounds the pool; losing one drops
                        // the filter rather than leaving a stale one applied
                        Connections {
                            target: deckStore
                            function onActiveChanged() {
                                if (!legalOnly.enabled)
                                    legalOnly.checked = false
                                window.applyLegalIdentity()
                            }
                        }
                    }

                    // Which commander, which colours, which deck — everything
                    // the toggle is actually scoped to, at a size that fits it.
                    Row {
                        width: parent.width
                        spacing: 6
                        Item {
                            id: legalIndent
                            width: legalOnly.indicator.width + legalOnly.spacing
                            height: 1
                        }
                        Row {
                            id: legalPips
                            spacing: 1
                            Repeater {
                                model: deckStore.commanderId !== ""
                                    ? (deckStore.commanderIdentity || "C").split("")
                                    : []
                                delegate: PixelIcon {
                                    sprite: "mtg-pip-" + modelData.toLowerCase()
                                }
                            }
                        }
                        Label {
                            width: parent.width - legalIndent.width
                                   - legalPips.width - 2 * parent.spacing
                            wrapMode: Text.Wrap
                            font.pixelSize: Retro.small
                            color: "#6b6b74"
                            text: deckStore.commanderId !== ""
                                ? deckStore.commanderName
                                  + "\nin " + deckStore.activeName
                                : "Open a deck with a commander to use this."
                        }
                    }

                    // Reset on its own: there is no Go any more. Every region
                    // searches the moment you are done with it — see
                    // window.noteTextEdited — so a button that says "now do it"
                    // would only ever be pressed after the search had run.
                    // Pixel art can't stretch to fill, so it sits at its natural
                    // size rather than spanning the panel.
                    PixelButton {
                        sprite: "mtg-btn-reset"
                        pixelScale: 3
                        onClicked: window.resetFilters()
                    }

                }
            }
        }

        // ---- card grid --------------------------------------------------
        GridView {
            id: grid
            // Narrow, the two flanking panels are sheets over the gallery
            // rather than columns beside it, so the gallery keeps the whole
            // width and simply sits underneath whichever one is open.
            anchors {
                left: window.narrow ? parent.left : filterPanel.right
                right: window.narrow ? parent.right : deckDock.left
                top: parent.top; bottom: parent.bottom
                leftMargin: window.narrow ? 4 : 12
                rightMargin: window.narrow ? 4 : 12
                topMargin: window.narrow ? 4 : 12
            }
            model: cardModel
            cacheBuffer: 800
            clip: true

            // A tile has to be wide enough to read the set line under the art.
            // 250 is comfortable; 175 is the floor, and it is what puts two
            // cards across a phone rather than one enormous one — a one-column
            // gallery is a list you scroll forever, not a gallery you scan.
            property int columns: Math.max(
                1, Math.floor(width / (window.narrow ? 175 : 250)))
            cellWidth: width / columns
            cellHeight: (cellWidth - 16) * 1.395 + 44   // card art + info row

            ScrollBar.vertical: ScrollBar {}

            function rarityColor(r) {
                return { common: "#5a5a5f", uncommon: "#7d95a6",
                         rare: "#b58e2f", mythic: "#d4512c" }[r] || "#5a5a5f"
            }
            function rarityBg(r) {
                return { common: "#cfcfd6", uncommon: "#a8c6dd",
                         rare: "#e8cf85", mythic: "#eb9d78" }[r] || "#cfcfd6"
            }
            function rarityBgHover(r) {
                var c = Qt.color(rarityBg(r))
                return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 1.8),
                               c.hslLightness * 0.93, 1)
            }

            delegate: Item {
                width: grid.cellWidth
                height: grid.cellHeight

                // violet glow behind legendary / commander-eligible tiles
                MultiEffect {
                    source: tile
                    anchors.fill: tile
                    visible: canBeCommander
                    shadowEnabled: true
                    shadowColor: "#8b48d8"
                    shadowBlur: 0.7
                    shadowOpacity: 0.55
                    shadowScale: 1.015
                    shadowVerticalOffset: 0
                }

                Rectangle {
                    id: tile
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: 10
                    color: tileMouse.containsMouse
                        ? grid.rarityBgHover(rarity) : grid.rarityBg(rarity)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    border.color: "#bbbbc0"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 5

                        Image {
                            id: cardImage
                            width: parent.width
                            height: width * 1.395
                            source: imageNormal
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit

                            Rectangle {
                                anchors.fill: parent
                                visible: cardImage.status !== Image.Ready
                                color: "#c4c4c9"
                                radius: 12
                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 20
                                    text: name
                                    color: "#555"
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        // set name
                        Row {
                            width: parent.width
                            spacing: 5
                            Item {
                                id: setSymbol
                                width: 20; height: 20
                                anchors.verticalCenter: parent.verticalCenter

                                // Keyed off the SVG's filename rather than the
                                // set code: several codes share one symbol, so
                                // the icon file is what actually identifies it.
                                readonly property string glyphName: {
                                    var url = String(setIcon)
                                    if (url === "") return ""
                                    var query = url.indexOf("?")
                                    if (query >= 0) url = url.substring(0, query)
                                    return url.substring(url.lastIndexOf("/") + 1)
                                              .replace(".svg", "")
                                }

                                Image {
                                    id: setGlyph
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: setSymbol.glyphName === "" ? ""
                                          : "assets/sets/set-" + setSymbol.glyphName + ".png"
                                    smooth: false
                                    fillMode: Image.Stretch
                                }

                                // A set printed since the glyphs were last
                                // generated has no sprite; fall back to
                                // Scryfall's SVG, and only fetch it then.
                                Image {
                                    id: setIconImage
                                    anchors.fill: parent
                                    source: setGlyph.status === Image.Error ? setIcon : ""
                                    // rasterize the SVG at exactly the displayed pixel
                                    // size — any other size gets rescaled and blurs
                                    sourceSize: Qt.size(
                                        width * Screen.devicePixelRatio,
                                        height * Screen.devicePixelRatio)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    visible: setIconImage.status === Image.Ready
                                    source: setIconImage
                                    brightness: -1.0   // force every pixel solid black, keep alpha
                                }
                                // fallback dot while the icon loads / if missing
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 9; height: 9; radius: 4.5
                                    visible: setGlyph.status !== Image.Ready
                                             && setIconImage.status !== Image.Ready
                                    color: grid.rarityColor(rarity)
                                }
                            }
                            Text {
                                width: parent.width - 25
                                text: setName
                                color: "#55555a"
                                font.pixelSize: Retro.body
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                cardMenu.openFor(cardId, name,
                                                 canBeCommander === 1, false,
                                                 imageNormal, rarity, imageBack)
                                return
                            }
                            window.showCard(imageNormal, name, rarity, imageBack,
                                            cardId, canBeCommander === 1, false)
                        }
                        // A touch screen has no right button. Holding a tile is
                        // the gesture that stands in for one everywhere else,
                        // so it opens the same menu — and it costs the mouse
                        // nothing, since holding the left button over a tile
                        // did nothing before.
                        onPressAndHold: (mouse) => {
                            if (mouse.button !== Qt.LeftButton) return
                            cardMenu.openFor(cardId, name,
                                             canBeCommander === 1, false,
                                             imageNormal, rarity, imageBack)
                        }
                        // double-click drops the card straight into the open
                        // list — the fast path once you've picked a list
                        onDoubleClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                detailPopup.close()
                                deckStore.addToActive(cardId)
                            }
                        }
                    }

                    // corner badge: this card is already in the open list
                    PixelIcon {
                        sprite: "mtg-icon-check"
                        pixelScale: 1
                        visible: window.activeMembers.indexOf(cardId) !== -1
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                    }
                }
            }
        }

        // ---- deck workspace ---------------------------------------------
        DeckDock {
            id: deckDock
            // as filterPanel: a column when there is room for one, a full-width
            // sheet over the gallery when there is not
            width: window.dockOpen ? (window.narrow ? parent.width : 380) : 0
            visible: width > 0
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            z: window.narrow ? 20 : 0
            touch: window.narrow
            Behavior on width { NumberAnimation { duration: 140 } }

            // the last argument asks the dialog to offer list-or-deck
            onNewListRequested: nameDialog.ask(
                "New list", "Name", "",
                function (n, kind) { deckStore.createList(n, kind) }, true)
            onRenameRequested: (listId, current) => nameDialog.ask(
                "Rename list", "Name", current,
                function (n) { deckStore.renameList(listId, n) })
            onDuplicateRequested: (listId, current) => nameDialog.ask(
                "Duplicate list", "Name for the copy", current + " copy",
                function (n) { deckStore.duplicateList(listId, n) })
            onDeleteRequested: (listId, current) => {
                confirmDelete.listId = listId
                confirmDelete.listName = current
                confirmDelete.open()
            }
            onExportRequested: {
                exportText.text = deckStore.exportText(
                    exportStyle.styles[exportStyle.currentIndex])
                exportDialog.open()
            }
            onImportRequested: importDialog.open_()
            // fromList: true — a card opened from the workspace is one that is
            // already in the open list, so its menu offers to take it out
            onCardActivated: (cardId, image, cardName, rarity, backImage,
                              commanderEligible) =>
                window.showCard(image, cardName, rarity, backImage,
                                cardId, commanderEligible, true)
            onDeckCardMenuRequested: (cardId, cardName, label) =>
                deckCardMenu.openFor(cardId, cardName, label)
        }
    }

    // ---- deck-building chrome --------------------------------------------
    // which of the two sides flanking the gallery are open; both switches live
    // in the top bar, since a shut side has nowhere to keep its own
    property bool panelOpen: true
    property bool dockOpen: true

    // ---- narrow layout ----------------------------------------------------
    // The three columns — the form, the gallery, the deck — only stand side by
    // side on a wide screen. A phone held upright is about 390pt across, which
    // is narrower than the form alone. So under this width the two flanking
    // columns stop being columns: each becomes a full-width sheet over the
    // gallery, and only one is open at a time. Nothing is removed and nothing
    // is given a second implementation — the same panel and the same dock, laid
    // over instead of beside.
    //
    // 820 is the width below which the gallery would be left under 100px
    // between a 340 form and a 380 deck, i.e. narrower than one card tile. That
    // is the real threshold: not a device, but the point where the middle
    // column stops being able to show anything.
    readonly property bool narrow: width < 820
    // Coming into the narrow layout, both sheets shut — you land on the
    // gallery. Going back out, both columns return, which is the wide layout's
    // own resting state.
    onNarrowChanged: {
        panelOpen = !narrow
        dockOpen = !narrow
    }
    // Android's back button arrives as a request to close the window, and
    // quitting the app is almost never what it means. It means "out of
    // whatever I am in": the enlarged card, then the sheet over the gallery.
    // Only from the bare gallery, with nothing left to back out of, does it
    // close the app — which is the convention every Android app follows.
    //
    // Android only, and deliberately so. The same signal on the desktop is the
    // window's close button, and a close button that shuts a popup instead of
    // the window is a close button that appears not to work.
    onClosing: (close) => {
        if (Qt.platform.os !== "android") return
        if (detailPopup.opened) {
            detailPopup.close()
            close.accepted = false
        } else if (window.narrow && (panelOpen || dockOpen)) {
            panelOpen = false
            dockOpen = false
            close.accepted = false
        }
    }

    // opening one sheet shuts the other; side by side there is nothing to shut
    function openSide(which, on) {
        if (which === "panel") {
            panelOpen = on
            if (on && narrow) dockOpen = false
        } else {
            dockOpen = on
            if (on && narrow) panelOpen = false
        }
    }
    // ids in the open list, so grid tiles can tick themselves
    property var activeMembers: deckStore.activeCardIds

    // `backImage` is the far side of a double-faced card, "" for everything
    // else — see detailPopup
    //
    // The last three are what the card *is* rather than what it looks like,
    // and they are here so the enlarged view can carry the same menu the card
    // has everywhere else — see detailPopup's ⋯ button. They can be left off,
    // in which case the button is simply not offered.
    function showCard(image, cardName, rarity, backImage,
                      cardId, commanderEligible, fromList) {
        detailPopup.frontImage = image
        detailPopup.backImage = backImage || ""
        detailPopup.showingBack = false
        detailPopup.fullName = cardName
        detailPopup.cardRarity = rarity
        detailPopup.cardId = cardId || ""
        detailPopup.canBeCommander = commanderEligible === true
        detailPopup.fromList = fromList === true
        detailPopup.open()
    }

    CardMenu {
        id: cardMenu
        onViewRequested: window.showCard(cardMenu.cardImage, cardMenu.cardName,
                                         cardMenu.cardRarity,
                                         cardMenu.cardBackImage,
                                         cardMenu.cardId,
                                         cardMenu.canBeCommander,
                                         cardMenu.showRemove)
        onNewListRequested: nameDialog.ask(
            "New list", "Name", "",
            function (n, kind) {
                if (deckStore.createList(n, kind))
                    deckStore.addCard(deckStore.activeId, cardMenu.cardId)
            }, true)
    }

    // right-click inside the open list, as opposed to out in the grid
    DeckCardMenu {
        id: deckCardMenu
        onLabelRequested: nameDialog.ask(
            "Label " + deckCardMenu.cardName, "Label",
            // read it back rather than trusting what the row was showing when
            // the menu opened — the list can have been rebuilt since
            deckStore.cardLabel(deckCardMenu.listId, deckCardMenu.cardId),
            function (text) {
                deckStore.setCardLabel(deckCardMenu.listId,
                                       deckCardMenu.cardId, text)
            })
    }

    NameDialog { id: nameDialog }

    ImportDialog { id: importDialog }

    RetroDialog {
        id: confirmDelete
        // Left to size itself this one measures its label and nothing else —
        // a Dialog ignores what its footer needs — so a short list name gave a
        // plate narrower than the two buttons, which are anchored to the right
        // edge and so hung off the left of it. Every other dialog here states a
        // width; this was the only one that didn't.
        width: Math.min(380, window.width - 24)
        title: "Delete list"
        property int listId: 0
        property string listName: ""
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Delete “" + confirmDelete.listName + "”?\nThis can't be undone."
            font.pixelSize: Retro.body
            lineHeight: 1.6
            color: Retro.ink
        }
        footer: Item {
            implicitHeight: 56
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 17
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                PixelButton {
                    sprite: "mtg-btn-cancel"
                    pixelScale: 2
                    onClicked: confirmDelete.reject()
                }
                PixelButton {
                    sprite: "mtg-btn-delete"
                    pixelScale: 2
                    onClicked: confirmDelete.accept()
                }
            }
        }
        onAccepted: deckStore.deleteList(listId)
    }

    RetroDialog {
        id: exportDialog
        width: Math.min(560, Math.max(window.width * 0.7, 320), window.width - 24)
        height: Math.min(600, window.height * 0.8)
        title: "Export — " + deckStore.activeName

        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PanelLabel { text: "Format" }
                RetroCombo {
                    id: exportStyle
                    Layout.fillWidth: true
                    readonly property var styles: ["moxfield", "plain", "annotated"]
                    model: ["Moxfield / Archidekt — Commander + Deck sections",
                            "Plain — one card per line, no headings",
                            "Annotated — grouped by type, for reading"]
                    onActivated: exportText.text =
                        deckStore.exportText(styles[currentIndex])
                }
            }
            Label {
                text: [
                    "Sections name the commander, which is what Moxfield and "
                        + "Archidekt read back.",
                    "The lowest common denominator: anything that reads deck "
                        + "lists reads this, but nothing learns the commander.",
                    "For reading, not importing — the group headings aren't a "
                        + "format any site parses."
                ][exportStyle.currentIndex]
                font.pixelSize: Retro.small
                color: Retro.inkDim
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            RetroPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sunken: true
                shadowOffset: 0
                plate: Retro.plateDeep
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 4
                    TextArea {
                        id: exportText
                        readOnly: true
                        selectByMouse: true
                        // already monospaced, and the deck list is the one
                        // place the column alignment does real work
                        font.pixelSize: Retro.body
                        color: Retro.ink
                        selectionColor: Retro.blue
                        selectedTextColor: Retro.black
                        background: null
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 10
                PixelButton {
                    sprite: "mtg-btn-copy"
                    pixelScale: 2
                    onClicked: {
                        exportText.selectAll()
                        exportText.copy()
                        exportText.deselect()
                        window.toast("Deck list copied.")
                    }
                }
                PixelButton {
                    sprite: "mtg-btn-close"
                    pixelScale: 2
                    onClicked: exportDialog.close()
                }
            }
        }
    }

    // ---- brief confirmations ---------------------------------------------
    function toast(message) {
        toastLabel.text = message
        toastRect.opacity = 1
        toastTimer.restart()
    }

    Connections {
        target: deckStore
        function onNotified(message) { window.toast(message) }
    }

    RetroPanel {
        id: toastRect
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: toastLabel.implicitWidth + 32
        height: 34
        opacity: 0
        visible: opacity > 0
        z: 100
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Label {
            id: toastLabel
            anchors.centerIn: parent
            color: Retro.inkHot
            font.pixelSize: Retro.body
        }
        Timer {
            id: toastTimer
            interval: 2200
            onTriggered: toastRect.opacity = 0
        }
    }

    // ---- what the card face shows back to you ----------------------------
    // The regions that open popovers display their own current value, so the
    // card reads as your query. Kept as plain properties refreshed by the
    // apply* functions rather than bindings, so there is one obvious place
    // where filter state and what you see are reconciled.
    property string costSummary: ""
    property string ptSummary: ""
    property string setSummary: ""
    property string typeSummary: ""
    property string subtypeSummary: ""
    property string artistSummary: ""
    property string yearSummary: ""
    // the colour toggles, as letters, for the cost region to wear as pips
    property var costColors: []
    // The dropdown narrows as you type; capped so a blank box doesn't try to
    // list every illustrator in the pool at once.
    //
    // Text that exactly matches a name means you picked it off the list rather
    // than typed it. Narrowing to that one row would leave you looking at the
    // choice you already made with no way to change it, so an exact match
    // re-opens the whole list — uncapped, because the name you are on has to be
    // in it and the view is virtualised anyway.
    // Lowercased once rather than on every character typed. cardModel.artists
    // is a QVariantList; each element read marshals a string across, so 1300+
    // of those per keystroke is worth paying exactly one time.
    readonly property var artistIndex: {
        var all = cardModel.artists
        var names = [], lower = []
        for (var i = 0; i < all.length; i++) {
            var name = String(all[i])
            names.push(name)
            lower.push(name.toLowerCase())
        }
        return { names: names, lower: lower }
    }

    property var artistMatches: {
        var names = artistIndex.names, lower = artistIndex.lower
        var q = artistSearch.text.toLowerCase()
        var picked = lower.indexOf(q) !== -1
        if (picked) q = ""
        var limit = picked ? names.length : 200
        var out = []
        for (var i = 0; i < names.length && out.length < limit; i++)
            if (q === "" || lower[i].indexOf(q) !== -1)
                out.push(names[i])
        return out
    }
    // the set-symbol plate: the plain plate grey until a rarity is picked
    property string raritySwatch: "#d4d4d8"
    property string identityTint: "transparent"

    // ---- the face the form is printed on ---------------------------------
    // Whichever card the filters would actually turn up, so the form is always
    // showing you a live example of what it is asking for. Krenko, Mob Boss
    // (M13) — a frame with every region — stands in only before the first
    // search lands, or if the pool is empty.
    //
    // Held, rather than bound: when the filters match nothing there is no card
    // to show, and the last one that did match is a better thing to leave under
    // an empty result than a blank panel. emptyBeat is what says it is empty.
    readonly property string defaultFace:
        "https://cards.scryfall.io/normal/front/a/a/aa078518-0ce2-4c6f-9061-aa7e22ed7493.jpg"
    property string previewFace: defaultFace

    // Which frame the form is currently laid out for, and which one the face
    // being fetched is in. They are two properties rather than one because the
    // face arrives late: the image comes off the CDN some hundreds of
    // milliseconds after the query answers, and moving the form the moment the
    // query lands would walk the plates across a card still showing the *old*
    // frame. So the pending frame waits, and exampleCard promotes it at the
    // moment the new face becomes visible — see onStatusChanged there. The
    // plates then glide (300ms) over the crossfade (140ms), which is what makes
    // the two read as one movement rather than two.
    property string pendingFrame: CardFrames.DEFAULT
    property string previewFrame: CardFrames.DEFAULT
    // Rarity rides along with the frame for the same reason and on the same
    // beat: from 2015 on, a rare or a mythic carries a holofoil stamp that the
    // text box arches over, so the flavour plate is cut differently for one.
    // Promoting it early would arch the plate over a stamp the face on screen
    // has not got yet.
    property string pendingRarity: ""
    property string previewRarity: ""
    readonly property var frameGeometry: CardFrames.regions(previewFrame)

    // How the plate over one region is cut on the frame currently showing.
    // Separate from frameGeometry because a region can want a shape a frame
    // has no opinion about: the 1993 and 1997 cards print no box under the
    // name, the cost or the P/T, and this hands back {} for those rather than
    // an entry invented to fill the table out. See CardFrames.shape.
    function regionShape(region) {
        return CardFrames.shape(previewFrame, region)
    }

    // The arch the text box takes over the holofoil stamp on the face
    // currently showing — [centre, half-width, rise] in fractions of the card,
    // all three zero on a frame or a rarity that prints no stamp.
    readonly property var stampArch:
        CardFrames.stamp(previewFrame, previewRarity)

    function syncPreviewFace() {
        if (cardModel.previewImage === "") return
        window.previewFace = cardModel.previewImage
        window.pendingFrame = cardModel.previewFrame
        window.pendingRarity = cardModel.previewRarity
    }

    Component.onCompleted: {
        window.syncPreviewFace()
        // onNarrowChanged never fires for a window that *starts* narrow, so
        // the opening state is settled here rather than only on a resize
        if (window.narrow) {
            window.panelOpen = false
            window.dockOpen = false
        }
        // nothing has been drawn yet, so the first layout is placed, not moved
        window.previewFrame = window.pendingFrame
        window.previewRarity = window.pendingRarity
        // from here on, a character in a field is a character someone typed
        window.formReady = true
    }
    Connections {
        target: cardModel
        function onPreviewChanged() { window.syncPreviewFace() }
    }

    // `floor` defaults to 0 — the bottom of every range on the card except the
    // year, whose spinners start at whenever the pool's oldest set came out
    function rangeSummary(min, max, ceiling, floor) {
        if (floor === undefined) floor = 0
        if (min <= floor && max >= ceiling) return ""   // unfiltered
        if (min === max) return String(min)
        if (max >= ceiling) return min + "+"
        if (min <= floor) return "≤" + max
        return min + "–" + max
    }

    function refreshSummaries() {
        // the colours first: whether the cost region is wearing pips decides
        // how much of itself the summary beside them has to spell out
        var letters = []
        var colorless = false
        // every toggle that is on, colourless included, in the order they are
        // laid out in the popover — that is WUBRG, the order Magic prints them
        var pips = []
        for (var j = 0; j < colorToggles.count; j++) {
            var c = colorToggles.itemAt(j)
            if (!c.checked) continue
            pips.push(c.letter)
            if (c.letter === "C") colorless = true
            else letters.push(c.letter)
        }
        costColors = pips

        var mv = rangeSummary(cmcMin.value, cmcMax.value, 16)
        if (manaInput.text !== "")
            costSummary = mv === "" ? manaInput.text : manaInput.text + " · " + mv
        else if (mv === "")
            costSummary = ""
        else
            // "MV 3" alone, but just "3" in front of a row of pips: there it is
            // already sitting where a card prints its generic mana, and the
            // label would cost the pips the room they need
            costSummary = pips.length > 0 ? mv : "MV " + mv

        // "3+/1–4" when both are bounded; otherwise name the half in play,
        // so a lone "5+" can't be misread as the other stat
        var p = rangeSummary(powerMin.value, powerMax.value, 20)
        var t = rangeSummary(toughnessMin.value, toughnessMax.value, 20)
        if (p !== "" && t !== "") ptSummary = p + "/" + t
        else if (p !== "")        ptSummary = "P " + p
        else if (t !== "")        ptSummary = "T " + t
        else                      ptSummary = ""

        typeSummary = typeList.value
        subtypeSummary = subtypeList.value
        artistSummary = artistSearch.text

        // a bare "2019–2024" would read as a card number down on that line;
        // the range is short enough that spelling it out still fits
        var yr = rangeSummary(yearMin.value, yearMax.value,
                              cardModel.years[1], cardModel.years[0])
        yearSummary = yr === "" ? "" : "© " + yr

        setSummary = setPicker.currentIndex <= 0
            ? "" : String(cardModel.sets[setPicker.currentIndex - 1].code).toUpperCase()

        // one rarity picked colours the set symbol the way print does;
        // several picked is not a printable state, so leave the plate neutral
        var rarities = []
        for (var i = 0; i < rarityToggles.count; i++)
            if (rarityToggles.itemAt(i).checked) rarities.push(i)
        raritySwatch = rarities.length === 1
            ? ["#8f8f95", "#b6c6d2", "#d9be6d", "#e28a60"][rarities[0]] : "#d4d4d8"

        if (letters.length > 1)
            identityTint = "#d4b464"                    // gold, as a multicolour frame
        else if (letters.length === 1)
            identityTint = ({ W: "#f4efd2", U: "#a8cbe4", B: "#6e6663",
                              R: "#df7d5a", G: "#7fae74" })[letters[0]]
        else if (colorless)
            identityTint = "#b8b2a8"
        else
            identityTint = "transparent"
    }

    // ---- when typing becomes a search ------------------------------------
    // Everything on the card that isn't typed into — the colour pips, the
    // ranges, the set, the rarities — searches on the click that sets it. The
    // typed regions can't: a query per character resets the model per
    // character, and a reset rebuilds every tile in the gallery and restarts
    // its card-image load, which costs far more than the query does. That is
    // what the Go button used to paper over, at the price of a search that
    // didn't happen until you remembered to ask for it.
    //
    // So typing schedules instead. A pause commits it; anything that says you
    // are done with the region — Enter, the focus moving on, the popover
    // closing — commits it there and then rather than waiting the pause out.
    // The two paths cannot double up: whichever gets there first clears the
    // flag and stops the timer, and with the flag clear commitText does
    // nothing at all. That last part matters, because commitText is wired to
    // every popover's onClosed, and most popovers hold no text.
    //
    // 260ms is under the gap between words and over the gap between letters,
    // so a search lands as you finish a word rather than inside one. The model
    // debounces another 150ms on top (see CardModel), which coalesces the six
    // setFilter calls below into a single query.
    property bool textDirty: false
    // Guards the pass of textChanged signals that fire while the form is being
    // built: nothing has been typed yet, and a search scheduled from those
    // would re-run the opening query for no reason.
    property bool formReady: false

    Timer {
        id: textCommit
        interval: 260
        onTriggered: window.commitText()
    }

    function noteTextEdited() {
        if (!window.formReady) return
        window.textDirty = true
        textCommit.restart()
    }

    // Run what's pending, if anything is. Safe to call from anywhere, as often
    // as you like.
    function commitText() {
        if (window.textDirty) window.applyTextFilters()
    }

    function applyTextFilters() {
        // whatever brought us here is the commit, so nothing is owed after it
        textCommit.stop()
        window.textDirty = false
        // no "text" key: the card face asks which field you mean, so nothing
        // here searches across all of them at once. db.search() still accepts
        // it — that API is for other frontends too, not just this panel.
        cardModel.setFilter("name", nameField.text)
        cardModel.setFilter("mana", manaInput.text)
        cardModel.setFilter("type", typeList.value)
        cardModel.setFilter("subtype", subtypeList.value)
        cardModel.setFilter("oracle", oracleField.text)
        cardModel.setFilter("flavor", flavorField.text)
        // The artist rides with the rest rather than having its own apply: the
        // regions commit each other now — leaving the name field commits the
        // artist you typed earlier and never committed — so every typed region
        // has to travel on every commit, or one of them goes stale.
        cardModel.setFilter("artist", artistSearch.text)
        refreshSummaries()
    }

    // A colourless commander legally admits only colourless cards — a real
    // filter, not the absence of one. setFilter() reads "" as "no filter", so
    // colourless travels as "C", the same letter the identity pips use for it.
    function applyLegalIdentity() {
        commitText()
        if (!legalOnly.checked || deckStore.commanderId === "") {
            cardModel.setFilter("legal_identity", null)
            return
        }
        cardModel.setFilter("legal_identity",
                            deckStore.commanderIdentity || "C")
    }

    // The controls you click rather than type into. Each one takes whatever
    // text is still pending along with it: reaching for another control is
    // leaving the region you were typing in, and letting the debounce fire on
    // its own a moment later would search twice for one decision — and rebuild
    // every tile in the gallery both times.
    function applyColors() {
        commitText()
        var letters = ""
        var colorless = false
        for (var i = 0; i < colorToggles.count; i++) {
            var t = colorToggles.itemAt(i)
            if (!t.checked) continue
            if (t.letter === "C") colorless = true
            else letters += t.letter
        }
        cardModel.setFilter("colorless", colorless)
        cardModel.setFilter("colors", colorless ? "" : letters)
        cardModel.setFilter("color_mode",
            ["within", "exact", "includes"][colorMode.currentIndex])
        refreshSummaries()
    }

    function applyRarities() {
        commitText()
        var rars = []
        for (var i = 0; i < rarityToggles.count; i++) {
            var t = rarityToggles.itemAt(i)
            if (t.checked) rars.push(t.rarityKey)
        }
        cardModel.setFilter("rarities", rars)
        refreshSummaries()
    }

    function applyCmcRange() {
        commitText()
        // treat max at its ceiling (16) as unbounded so 16+ cost cards still show
        cardModel.setFilter("cmc_min", cmcMin.value > 0 ? cmcMin.value : null)
        cardModel.setFilter("cmc_max", cmcMax.value >= 16 ? null : cmcMax.value)
        refreshSummaries()
    }

    function applyPtRange() {
        commitText()
        // as with mana value, a spinner at its ceiling means "no upper bound",
        // so a 20/20 still turns up
        cardModel.setFilter("power_min", powerMin.value > 0 ? powerMin.value : null)
        cardModel.setFilter("power_max", powerMax.value >= 20 ? null : powerMax.value)
        cardModel.setFilter("toughness_min",
            toughnessMin.value > 0 ? toughnessMin.value : null)
        cardModel.setFilter("toughness_max",
            toughnessMax.value >= 20 ? null : toughnessMax.value)
        refreshSummaries()
    }

    function applyYearRange() {
        commitText()
        // a spinner parked on the end of the pool's own range means "no bound
        // that side", the same convention the mana value and P/T ranges use
        cardModel.setFilter("year_min",
            yearMin.value > cardModel.years[0] ? yearMin.value : null)
        cardModel.setFilter("year_max",
            yearMax.value < cardModel.years[1] ? yearMax.value : null)
        refreshSummaries()
    }

    function resetFilters() {
        cardModel.clearFilters()
        nameField.text = ""
        typeList.value = ""
        subtypeList.value = ""
        oracleField.text = ""
        flavorField.text = ""
        artistSearch.text = ""
        manaInput.text = ""
        setPicker.currentIndex = 0
        colorMode.currentIndex = 0
        cmcMin.value = 0
        cmcMax.value = 16
        powerMin.value = 0
        powerMax.value = 20
        toughnessMin.value = 0
        toughnessMax.value = 20
        yearMin.value = cardModel.years[0]
        yearMax.value = cardModel.years[1]
        commandersOnly.checked = false
        legalOnly.checked = false
        for (var i = 0; i < colorToggles.count; i++)
            colorToggles.itemAt(i).checked = false
        for (var j = 0; j < rarityToggles.count; j++)
            rarityToggles.itemAt(j).checked = false
        // Emptying the fields above tripped every onTextChanged on the way
        // past, so there is a commit pending for text that no longer exists.
        // clearFilters has already dropped those keys; letting it fire would
        // set them all over again as empties and re-run the query for nothing.
        textCommit.stop()
        window.textDirty = false
        refreshSummaries()
    }
    // ---- enlarged card view ---------------------------------------------
    Popup {
        id: detailPopup
        anchors.centerIn: parent
        // The card sets the height, so the height has to be able to set the
        // card: on a short window the last 44px are the name and the flip
        // button, and a control you can't reach is worse than one that isn't
        // there.
        width: Math.min(520, window.width * 0.8, (window.height - 60) / 1.42)
        height: width * 1.42 + 44
        modal: true
        property string cardRarity: ""

        // Who the card is, as opposed to what it looks like — everything the
        // menu below needs. Empty when whatever opened this did not say, which
        // is what hides the button rather than offering one that would open a
        // menu with nothing to act on.
        property string cardId: ""
        property bool canBeCommander: false
        property bool fromList: false

        // A transform or modal DFC is two cards printed back to back, and only
        // the front was ever on screen. `backImage` is empty for the
        // single-faced majority, which is what decides whether there is
        // anything to turn over.
        property string frontImage: ""
        property string backImage: ""
        property bool showingBack: false
        // as printed: "Delver of Secrets // Insectile Aberration"
        property string fullName: ""

        readonly property var faces: fullName.split(" // ")
        // name the side you are looking at, not both sides at once
        readonly property string faceName:
            (backImage !== "" && faces.length > 1)
                ? faces[showingBack ? 1 : 0] : fullName

        onClosed: showingBack = false      // always open on the front

        background: RetroPanel { shadowOffset: 6 }

        // Below the content, not above it: the image and the label ignore the
        // mouse, so a click anywhere but the flip button still falls through
        // to here and shuts the card. Declared first is what puts it under.
        MouseArea { anchors.fill: parent; onClicked: detailPopup.close() }

        Column {
            anchors.fill: parent
            spacing: 8
            Image {
                id: detailImage
                width: parent.width
                height: parent.height - 44
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                source: detailPopup.showingBack ? detailPopup.backImage
                                                : detailPopup.frontImage
            }
            Item {
                width: parent.width
                height: 40

                // Everything you could do to this card by right-clicking it.
                //
                // On a desktop the enlarged view is a detour — you right-click
                // the tile, and the card is one row of that menu. With a
                // finger there is no right button: the gallery's press-and-hold
                // stands in for one, but a tap is what a picture invites, and a
                // tap lands you here with the card filling the screen and no
                // way to do anything with it but go back and hold it instead.
                //
                // So the same menu opens from here, on the same card, minus its
                // "View …" row. One menu, one set of behaviours, rather than a
                // second sort-of menu that drifts from the first.
                PixelButton {
                    id: detailMenuButton
                    sprite: "mtg-icon-more"
                    pixelScale: 2
                    visible: detailPopup.cardId !== ""
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    tooltip: "Add to a list, and everything else"
                    onClicked: cardMenu.openFor(
                        detailPopup.cardId, detailPopup.fullName,
                        detailPopup.canBeCommander, detailPopup.fromList,
                        detailPopup.frontImage, detailPopup.cardRarity,
                        detailPopup.backImage,
                        false,               // the card is already on screen
                        detailMenuButton)
                }

                Text {
                    id: detailName
                    anchors.verticalCenter: parent.verticalCenter
                    // the button is on the right, so leave it room on both
                    // sides — a centred name that ducks left when a card
                    // happens to have a back reads as a different layout
                    x: 72
                    width: parent.width - 144
                    text: detailPopup.faceName
                    color: Retro.ink
                    font.pixelSize: Retro.title
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                PixelButton {
                    sprite: "mtg-btn-flip"
                    pixelScale: 2
                    visible: detailPopup.backImage !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    tooltip: detailPopup.showingBack ? "Back to the front face"
                                                     : "Turn the card over"
                    onClicked: detailPopup.showingBack = !detailPopup.showingBack
                }
            }
        }
    }
}
