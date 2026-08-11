# CommandCreation

A pixel-art desktop app for building Magic: The Gathering Commander decks —
C++/Qt Quick front to end, backed by Scryfall's card data held locally in SQLite.

Search the whole Commander-legal pool, build lists and decks side by side, and
have every deck check itself against the format as you go: 100 cards, singleton,
and colour identity against your commander. Import from Moxfield, Archidekt,
MTGO, TappedOut or Deckstats; export back out in three formats.

## Setup / run

Needs CMake 3.21+, a C++17 compiler, and Qt 6.5 or newer with the `Core`, `Gui`,
`Qml`, `Quick`, `Sql` and `Network` modules. On Arch that is `qt6-base` and
`qt6-declarative`.

```bash
python3 scripts/ingest.py   # download card data from Scryfall (re-run to refresh)

cmake -S . -B build -DCMAKE_PREFIX_PATH=/usr   # once
cmake --build build                            # after each C++ change (~2s)
./build/mtgdeck
```

Only the first line is Python, and it needs nothing but the standard library —
there is no virtualenv to set up. `cmake --build` is incremental and re-runs the
configure step itself when `CMakeLists.txt` or the file list changes, so the
first line is genuinely one-time.

**`-DCMAKE_PREFIX_PATH=/usr` is not optional if you also have a Qt from the Qt
Online Installer.** It picks the system Qt. Without it CMake may resolve to
whichever Qt is first on `PATH` — an Android or other cross-compile kit will
*configure without complaint* and then fail at link with `file in wrong format`,
which is your linker being handed libraries for the wrong architecture. Worse,
the choice is cached: adding the flag afterwards does not fix that build
directory, you have to delete it. `-DQt6_DIR=/usr/lib/cmake/Qt6` says the same
thing more narrowly.

The QML is compiled into the binary. To edit `qml/` and see the change without
rebuilding, point the app at the directory instead — restart is enough, and only
C++ changes then need `cmake --build`:

```bash
MTG_QML_DIR=qml ./build/mtgdeck
```

## A copy someone else can run

`./build/mtgdeck` reads its databases out of this source tree, so it only works
on the machine it was built on. To get a copy that doesn't:

```bash
cmake --install build --prefix dist
```

That lays down `dist/bin/mtgdeck` beside `dist/bin/data/cards.db`, and the app
prefers a `data/` next to the binary over the source tree — so `dist/` can be
moved or archived and still runs. Your own `data/decks.db` is deliberately *not*
installed: it holds your lists, and the app creates an empty one on first launch.

Qt's own libraries are not bundled by this, so the target machine still needs
Qt 6.5+ installed. A self-contained bundle would want `qt_generate_deploy_app_script`
(or `linuxdeployqt` / `windeployqt`) on top.

## The browser build

Same sources, a second build directory. Nothing forks: `qml/` is shared whole,
and the three places the browser differs are `#ifdef Q_OS_WASM` inside `Db`.

```bash
# once — the Emscripten version is not a preference, see below
git clone --depth 1 https://github.com/emscripten-core/emsdk.git ~/emsdk
~/emsdk/emsdk install 3.1.50 && ~/emsdk/emsdk activate 3.1.50
aqt install-qt all_os wasm 6.7.3 wasm_singlethread --outputdir ~/Qt
chmod +x ~/Qt/6.7.3/wasm_singlethread/bin/{qt-cmake,qmake,qmake6,qtpaths,qtpaths6}

# each build
source ~/emsdk/emsdk_env.sh
~/Qt/6.7.3/wasm_singlethread/bin/qt-cmake -S . -B build-wasm \
    -DQT_HOST_PATH=$HOME/Qt/6.7.3/gcc_64
cmake --build build-wasm
(cd build-wasm && python3 -m http.server 8765)   # then open mtgdeck.html
```

Four things that will cost you an afternoon if you guess at them:

- **The Emscripten version is pinned by Qt**, not chosen. `3.1.50` is what this
  kit names in `QT_EMCC_RECOMMENDED_VERSION`
  (`lib/cmake/Qt6/QtPublicWasmToolchainHelpers.cmake`, also `mkspecs/qconfig.pri`).
  Read it out of the kit rather than trusting a blog post; it changes per Qt
  release.
- **`QT_HOST_PATH` must be a Qt of exactly the same version** as the wasm kit.
  The system Qt here is 6.11.1, so it cannot serve — `~/Qt/6.7.3/gcc_64` can.
- **`aqt` ships the wasm kit from Qt's Windows-hosted archives**, and the Unix
  shell wrappers arrive without their exec bit. That is the `chmod` above; skip
  it and `qt-cmake` fails with "Permission denied".
- **`wasm_singlethread` is deliberate.** The multithreaded kit needs COOP/COEP
  cross-origin-isolation headers from whatever hosts the page, and this app has
  no use for threads.

The payload is ~52 MB raw, ~17 MB gzipped: a 35 MB `.wasm`, and `cards.db`
packaged whole into a 17 MB `.data` the page fetches before it starts. Serve it
compressed, and with `application/wasm` on the `.wasm` — without that MIME type
the browser cannot stream-compile and buffers the whole thing first.

Note what the two columns say. Slimming `cards.db` from 29 MB took 12 MB off the
raw size but only ~1.3 MB off the wire, because the bytes removed were repeated
URL prefixes and gzip was already collapsing them. The win that matters is at
the other end: the `.data` is unpacked into memory at startup, so it is 12 MB
less browser RAM and less time spent writing it there.

Decks persist in IndexedDB. `cards.db` is preloaded read-only into the in-memory
filesystem at `/data`, while `decks.db` sits alone at `/decks` under an IDBFS
mount — separate directories on purpose, since a mount over the shared one would
shadow the preloaded 29 MB. `wasm/pre.js` reads the decks back before `main()`
runs (as an Emscripten run dependency, the one way to get an async step before
startup without Asyncify), and `Db::flush()` pushes them out again after every
change, coalescing calls that overlap.

Two consequences worth knowing: decks are **per-browser, not per-user** until
accounts exist, and clearing site data deletes them.

## The site

`web/` is the landing page, and `scripts/build-site.sh` assembles it with the
browser build into `site/` — page at the root, app under `app/`:

```bash
./scripts/build-site.sh            # or --build to rebuild the wasm first
python3 -m http.server 8765 --directory site
```

The landing page is deliberately **not** the app. It is plain HTML and one
stylesheet, about 155 KB gzipped against the builder's 17 MB, because a first
impression that costs a 17 MB download is not one, and because a link preview
and a search engine need something they can actually read. It carries the app's
own PICO-8 palette and bitmap face so the two read as one product.

Static files with no server-side anything, so any static host works. Two things
that host must do:

- send `.wasm` as **`application/wasm`**, or the browser cannot stream-compile
  and buffers all 35 MB before it starts
- **compress**: ~52 MB raw against ~17 MB gzipped

## Setup notes

The ingest step is required before the first launch and takes a few minutes: it
pulls Scryfall's Oracle bulk data, filters it to Commander-legal cards, and
writes `data/cards.db` (~29 MB, ~31k cards). That file and your own
`data/decks.db` stay out of the repo — the first is regenerated, the second is
yours.

Card art is not stored. It loads on demand from Scryfall's CDN, so the app wants
a network connection to show card images.

## Building decks

Right-click any card in the grid:

- **Add to list** — tick any of your lists to drop the card in, untick to pull it back out
- **New list…** — name a list and put the card straight into it
- **Set as commander** — on any legendary creature; this also turns the list into a deck

Double-clicking a card adds it to whichever list is open. The deck panel on the
right picks the open list from a dropdown, then gives the rest of its height to
that list: the contents (grouped by card type, with ±  quantity steppers), the
mana curve, colour pips, type counts, and a running rule check — 100 cards,
singleton, and colour identity against your commander.

The dropdown replaced a standing scroll box. That box only ever answered one
question — which list is open — and spent a permanent slice of the panel doing
it. The card count and the sort order sit on that same row, so one line carries
everything about *which* list you are looking at and the rest of the panel is
the list itself. Rename, duplicate and delete used to hang off a right-click on
its rows; they now live behind the `⋯` button beside the dropdown.

The commander is not repeated in the card list. It has its own slot above, and
listing it twice makes a one-card deck look like two. It is still a card in the
deck underneath: it counts toward the hundred, it is in the export, and the
grid still ticks it as present.

Each row carries a thumbnail of the card's own art — Scryfall's `art_crop`, not
the whole card, because at 34×24 a whole card is a grey rectangle with a smudge
on it. They decode at the size they're drawn rather than at the crop's native
626×457; a hundred rows at full size is a hundred megabytes for something the
width of a thumbnail.

## Lists and decks

They are the same thing with a different `kind`. A **deck** gets checked against
the Commander rules; a **list** is just a pile of cards. You pick which when you
name it — `+ New` asks, and that is the only place the choice is made.

Setting a commander on a plain list also turns it into a deck, since a list with
a commander is what a deck is. `DeckStore.promoteToDeck()` and `demoteToList()`
still exist for changing kind after the fact; nothing in the UI calls them.

Every row in the sidebar carries a symbol, so the gutter lines up and the
absence of a crown is never just an absence of anything:

| | |
|---|---|
| ruled lines | a list |
| crown | a deck |
| crown + colour pips | a deck with a commander, and its colour identity |

The crown is the same one on the `Make deck` button and the commander seat —
one symbol, one meaning. A deck with no commander yet shows the crown alone: it
used to show a colourless mana pip, which read as "colourless deck" rather than
"deck".

## Staying legal

A deck checks itself as you build. Cards that break a rule — outside the
commander's colour identity, or a second copy of something that isn't a basic
land — **pulse red** in the deck list, in a two-beat heartbeat. The rule text
under the deck already said what was wrong; the pulse says *which row*, which a
list of names in a sentence can't.

Only decks pulse, and only errors do. "34 more cards to go" is a warning, not a
card's fault.

`Legal for commander` in the filter panel narrows the whole card pool to what
the open deck's commander legally allows. It names which one directly under the
toggle — colour pips, the commander, and the deck it belongs to — because with
several decks on the go, *which* commander is the whole question the toggle
answers. Switching decks re-scopes it; opening one with no commander clears it
rather than leaving a stale filter applied.

It composes with the colour-identity pips on the card face rather than
replacing them: the toggle bounds what could go in the deck at all, the pips
are a search you run inside that. A colourless commander allows only colourless
cards, which is a real filter and not the absence of one.

`Import` takes a deck list pasted from Moxfield, Archidekt, MTGO, TappedOut or
Deckstats. Quantities, `1x` prefixes, `(SET) 123` suffixes, `[Category]` tags,
`*F*` foil markers, `SB:` prefixes and `//` comments are all understood.
Matching ignores case and accents, folds curly apostrophes, and lets a
double-faced card answer to its front face alone — so `Aberrant Researcher`
finds `Aberrant Researcher // Perfected Form`.

It shows you what it found before writing anything: how many cards, which
commander, and **which names it didn't recognise, by name**. Cards in a
sideboard or maybeboard are reported and left out. Import as a new list, or
merge into the one that's open.

`Export…` offers three formats, because the sites disagree and nothing
satisfies all of them:

| | |
|---|---|
| **Moxfield / Archidekt** | `Commander` and `Deck` headings. The only one that carries which card is the commander. |
| **Plain** | Bare `1 Card Name` lines. Anything that reads deck lists reads this, but the commander is lost. |
| **Annotated** | Grouped under `Creatures (12)` headings — for reading, not importing. Those headings are not a format any site parses. |

## Layout

- `CMakeLists.txt` — the build; also globs `qml/` and its assets into the binary
- `src/` — C++ backend (`Db` SQLite queries, `CardModel` search results,
  `DeckModel` lists/decks exposed to QML, `DeckRules` legality and stats,
  `DeckIo` reading and writing deck lists, `main.cpp` entry point)
- `qml/` — QML UI (`Main.qml` shell + filter card, `DeckDock.qml` deck workspace,
  `CardMenu.qml` right-click menu, `NameDialog.qml`)
- `qml/Retro*.qml`, `qml/Pixel*.qml`, `qml/Retro.js` — the pixel-art look: buttons,
  icons, overlay chrome, and the palette and type scale they share
- `qml/assets/` — sprite PNGs, set-symbol glyphs, the UI face `PressStart2P-Regular.ttf`
  (SIL OFL, licence beside it) and `OasisPixel.ttf` (generated; see `tools/`)
- `tools/` — regenerates everything in `qml/assets/`
- `scripts/ingest.py` — downloads Scryfall Oracle bulk data, filters to Commander-legal cards, builds `data/cards.db`
- `data/cards.db` — SQLite database (generated, ~31k cards)
- `data/decks.db` — your lists and decks (created on first run)

Your lists live in their own file on purpose: `ingest.py` deletes and rebuilds
`cards.db` on every refresh, so nothing you author may live inside it.

Card art is loaded on demand from Scryfall's CDN via URLs stored in the database.

## The look

Buttons, icons, mana pips and the set symbols are pixel art built through a
separate pixel art engine, kept alongside this project as `../_Pixelart`.
Everything lands in that engine's library, so any of it can be opened in its
editor and redrawn by hand. The finished sprites are committed in
`qml/assets/`, so the engine is only needed to regenerate them — the app runs
without it. `tools/README.md` covers regenerating it.

The type is Press Start 2P. The in-house face it replaced, `OasisPixel.ttf`,
drew the digit `1` and the letter `l` from the same pixels one row apart, so a
count like `31830 cards` read as `3i830`; this one gives the `1` a flag and a
foot no letter has. It is still in `qml/assets/` and one `MTG_FONT=` away.

The typeface is chosen in one place — `src/main.cpp` — and can be changed
without editing anything:

```bash
MTG_FONT=system ./build/mtgdeck              # the platform's own font
MTG_FONT=/path/to/Other.ttf ./build/mtgdeck
MTG_FONT_SIZE=16 ./build/mtgdeck             # bigger
```

Sizes want to be multiples of 8: the face is drawn on an 8-row em, so anything
else lands glyph rows on half pixels. It is monospaced at one em per glyph,
which makes every label a third wider than the old face at the same size —
hence a scale of 8 / 8 / 16 rather than 10 / 10 / 20. It also carries ASCII and
Latin-1 only, so marks like a tick come from the icon sprites, never from a
character. The relative scale (`small` / `body` / `title`) and the overlay
palette live in `qml/Retro.js`.
