#!/usr/bin/env node
'use strict';
/**
 * Generate a set of PICO-8 pixel-art buttons for the MTG Commander deck builder,
 * straight into the pixel art engine's library/ folder.
 *
 *   node mtg-buttons.js
 *
 * Everything is procedural: the button chrome (border + bevel + face) is drawn
 * by rule, labels come from a 3x5 bitmap font, and icons/pips are ASCII art.
 * Every sprite has two frames -- frame 0 is the resting state, frame 1 is the
 * pressed (or, for the mana pips, the selected) state.
 */

const fs = require('fs');
const path = require('path');

const APP = path.resolve(__dirname, '..');
const ENGINE = process.env.PIXELART_ENGINE
             || path.resolve(APP, '..', '_Pixelart');
const S = require(path.join(ENGINE, 'lib/sprite.js'));
const { encodePNG } = require(path.join(ENGINE, 'lib/png.js'));
const LIBRARY = path.join(ENGINE, 'library');
const EXPORTS = path.join(ENGINE, 'exports');

const PICO8 = S.PALETTES.pico8.colors;
// index names, for readability below
const BLACK = 0, DARKBLUE = 1, DARKPURPLE = 2, DARKGREEN = 3, BROWN = 4,
      DARKGREY = 5, LIGHTGREY = 6, WHITE = 7, RED = 8, ORANGE = 9,
      YELLOW = 10, GREEN = 11, BLUE = 12, LAVENDER = 13, PINK = 14, PEACH = 15;

// ------------------------------------------------------------------ the font

// The glyphs come from pixelfont.js, the same table the app's TTF is built
// from -- a label in the UI and a label on a button are then the same face.
const PF = require('./pixelfont.js');
const FONT = PF.GLYPHS;
const GLYPH_H = PF.BASELINE_ROW + 1;   // rows on or above the baseline

// `oy` is the cap line: a glyph's own `t` offset drops it from there, which is
// what keeps '+' centred and ',' hanging below the baseline
const textWidth = s => s.length * PF.ADVANCE - 1;

// ------------------------------------------------------------------ canvas

function canvas(w, h) {
  const px = new Int16Array(w * h).fill(-1);
  return {
    w, h, px,
    set(x, y, v) { if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = v; },
    get(x, y) { return (x >= 0 && y >= 0 && x < w && y < h) ? px[y * w + x] : -1; },
  };
}

function stamp(c, rows, ox, oy, color) {
  for (let y = 0; y < rows.length; y++) {
    for (let x = 0; x < rows[y].length; x++) {
      if (rows[y][x] === '#') c.set(ox + x, oy + y, color);
    }
  }
}

function drawText(c, text, ox, oy, color) {
  let x = ox;
  for (const ch of text.toUpperCase()) {
    const glyph = FONT[ch];
    if (!glyph) throw new Error('no glyph for "' + ch + '"');
    stamp(c, glyph.r, x, oy + glyph.t, color);
    x += PF.ADVANCE;
  }
}

// ------------------------------------------------------------------ chrome

/**
 * A rectangular button: 1px black outline with clipped corners, a 1px bevel
 * inside it (light on the top/left, dark on the bottom/right), and a flat face.
 * `pressed` flips the bevel, which is the whole trick to making it look pushed.
 */
function buttonPlate(w, h, theme, pressed) {
  const c = canvas(w, h);
  const light = pressed ? theme.dark : theme.light;
  const dark = pressed ? theme.light : theme.dark;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const corner = (x === 0 || x === w - 1) && (y === 0 || y === h - 1);
      if (corner) continue;                                   // clipped: transparent
      if (x === 0 || y === 0 || x === w - 1 || y === h - 1) c.set(x, y, theme.out);
      else if (y === 1 || x === 1) c.set(x, y, light);
      else if (y === h - 2 || x === w - 2) c.set(x, y, dark);
      else c.set(x, y, theme.face);
    }
  }
  return c;
}

/**
 * `opts.icon` names an entry in ICONS and puts that 8x8 glyph in front of the
 * label, sharing the label's ink and drop shadow so the two read as one piece
 * of type rather than a picture next to some words.
 */
function labelButton(label, theme, opts) {
  const o = opts || {};
  const h = o.h || 20;   // 7 rows of glyph + its shadow + bevel + border
  const icon = o.icon ? ICONS[o.icon] : null;
  const GAP = 4;
  const iconWidth = icon ? 8 + GAP : 0;
  const contentWidth = iconWidth + textWidth(label);
  const w = o.w || contentWidth + 10;
  const frames = [false, true].map(pressed => {
    const c = buttonPlate(w, h, theme, pressed);
    const x = Math.floor((w - contentWidth) / 2);
    // the shadow occupies the row below, so bias the glyph up by one
    const ty = Math.floor((h - GLYPH_H - 1) / 2) + (pressed ? 1 : 0);
    // the icon is 8 rows against the cap band's 7, so it hangs one higher
    const iy = ty - 1;
    // the hard 1px drop shadow is what makes a label read as console UI
    // rather than as plain text sitting on a coloured box
    if (theme.textShadow != null) {
      if (icon) stamp(c, icon, x, iy + 1, theme.textShadow);
      drawText(c, label, x + iconWidth, ty + 1, theme.textShadow);
    }
    if (icon) stamp(c, icon, x, iy, theme.text);
    drawText(c, label, x + iconWidth, ty, theme.text);
    return c;
  });
  return frames;
}

function iconButton(icon, theme, opts) {
  const o = opts || {};
  const size = o.size || 16;
  return [false, true].map(pressed => {
    const c = buttonPlate(size, size, theme, pressed);
    const ox = Math.floor((size - 8) / 2);
    const oy = Math.floor((size - 8) / 2) + (pressed ? 1 : 0);
    stamp(c, icon, ox, oy, theme.text);
    return c;
  });
}

/** A round mana pip: filled disc, darker rim, black outline, symbol on top. */
function pip(symbol, shade, theme, pressed) {
  const size = 16, c = canvas(size, size), mid = (size - 1) / 2;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = Math.hypot(x - mid, y - mid);
      if (d <= 5.9) c.set(x, y, pressed ? theme.face : theme.offFace);
      else if (d <= 7.0) c.set(x, y, pressed ? theme.rim : theme.offRim);
      else if (d <= 7.7) c.set(x, y, BLACK);
    }
  }
  // a highlight arc on the upper left, so the disc reads as a sphere
  if (pressed && theme.gloss != null) {
    for (const [x, y] of [[5, 3], [6, 3], [4, 4], [4, 5], [7, 3]]) c.set(x, y, theme.gloss);
  }
  stamp(c, symbol, 4, 4, pressed ? theme.sym : theme.offSym);
  // The second ink, where there is one. Off, it is drawn in the same washed-out
  // grey as the first pass, so an unselected pip stays a flat silhouette.
  if (shade) stamp(c, shade, 4, 4, pressed ? theme.symShade : theme.offSym);
  return c;
}

// ------------------------------------------------------------------ save

function saveSprite(name, frames, tags, w, h) {
  const sprite = S.validate({
    format: 'pixelart/1',
    name, w, h, fps: 2,
    palette: PICO8.slice(),
    frames: frames.map((c, i) => ({
      layers: [{
        name: i === 0 ? 'up' : 'down',
        visible: true, opacity: 1,
        data: S.encodeRLE(Array.from(c.px)),
      }],
    })),
    tags,
  });
  fs.writeFileSync(path.join(LIBRARY, name + '.json'), JSON.stringify(sprite, null, 2));
  return sprite;
}

/** Both frames side by side in one PNG, so a glance shows up + down states. */
function exportSheet(sprite, scale) {
  const cols = sprite.frames.length;
  const W = sprite.w * scale * cols, H = sprite.h * scale;
  const rgba = new Uint8Array(W * H * 4);
  sprite.frames.forEach((_, f) => {
    const cell = S.frameToRGBA(sprite, f, scale);
    for (let y = 0; y < cell.height; y++) {
      for (let x = 0; x < cell.width; x++) {
        const src = (y * cell.width + x) * 4;
        const dst = (y * W + (f * cell.width + x)) * 4;
        for (let k = 0; k < 4; k++) rgba[dst + k] = cell.rgba[src + k];
      }
    }
  });
  fs.writeFileSync(path.join(EXPORTS, sprite.name + '.sheet.png'), encodePNG(W, H, rgba));
}

// ------------------------------------------------------------------ themes

// Light text over a dark shadow on the saturated plates; on the pale neutral
// plate the pair inverts to dark-over-white, which engraves rather than embosses.
const PRIMARY = { out: BLACK, face: ORANGE, light: YELLOW, dark: BROWN, text: WHITE, textShadow: BROWN };
const NEUTRAL = { out: BLACK, face: LIGHTGREY, light: WHITE, dark: DARKGREY, text: DARKBLUE, textShadow: WHITE };
const DANGER  = { out: BLACK, face: RED, light: PINK, dark: DARKPURPLE, text: WHITE, textShadow: DARKPURPLE };
const ACCENT  = { out: BLACK, face: BLUE, light: PEACH, dark: DARKBLUE, text: WHITE, textShadow: DARKBLUE };
const ARCANE  = { out: BLACK, face: LAVENDER, light: PINK, dark: DARKPURPLE, text: WHITE, textShadow: DARKPURPLE };

// ------------------------------------------------------------------ icons

const ICONS = {
  plus:    ['...##...', '...##...', '...##...', '########', '########', '...##...', '...##...', '...##...'],
  minus:   ['........', '........', '........', '########', '########', '........', '........', '........'],
  close:   ['##....##', '###..###', '.######.', '..####..', '..####..', '.######.', '###..###', '##....##'],
  check:   ['......##', '.....###', '....###.', '##..###.', '###.##..', '.#####..', '..###...', '...#....'],
  more:    ['........', '........', '........', '##.##.##',
            '##.##.##', '........', '........', '........'],
  list:    ['#.#####.', '........', '#.#####.', '........',
            '#.#####.', '........', '#.#####.', '........'],
  crown:   ['#..##..#', '#..##..#', '##.##.##', '########', '########', '#.#..#.#', '########', '........'],
  // The handle grows out of the lens's corner, not out from under its bottom
  // edge. A ring this small is drawn with straight sides, so the only place a
  // 45-degree handle can leave it without looking stuck on is the corner the
  // ring cuts diagonally -- and the handle has to run along the *same* diagonal
  // the corner sits on. The lens centre is (2,2), so that is the ray through
  // (3,3), (4,4), (5,5)...: (4,4) is the joint where the rim thickens, and
  // every handle pixel after it straddles that same line.
  search:  ['.###....', '#...#...', '#...#...', '#...#...', '.####...', '.....##.', '......##', '.......#'],
  sortDesc:['........', '##....##', '###..###', '.######.', '..####..', '...##...', '........', '........'],
  sortAsc: ['........', '...##...', '..####..', '.######.', '###..###', '##....##', '........', '........'],
  panel:   ['########', '#.#....#', '#.#....#', '#.#....#', '#.#....#', '#.#....#', '########', '........'],
};

// ------------------------------------------------------------------ mana pips

const SYMBOLS = {
  W: ['...##...', '.#.##.#.', '.######.', '########', '########', '.######.', '.#.##.#.', '...##...'],
  U: ['...##...', '...##...', '..####..', '..####..', '.######.', '.######.', '..####..', '...##...'],
  B: ['..####..', '.######.', '##.##.##', '##.##.##', '.######.', '..####..', '..#..#..', '........'],
  // A fireball, and it has a handedness -- mirror it and it reads as the wrong
  // symbol to anyone who knows the card face. Reducing Scryfall's R.svg to this
  // grid puts the solid ball low, a tall crescent up the right side that leans
  // back to the left as it rises, and a small flick off the left. The lean is
  // the whole tell, so the crescent's top row sits a column left of its base.
  //
  // The cleft between the flick and the crescent is not decoration either: a
  // round mass with one smooth bump on it is a thumbs-up, which is what every
  // uncleft version of this drew, including the one this replaced.
  R: ['....##..', '.....##.', '..#..##.', '.######.', '.######.', '.######.', '.#####..', '..###...'],
  // A tree. The root flare on the last row is what earns the reading: with a
  // canopy and a bare trunk this is a spade or a lollipop, and pinching the
  // canopy in to meet the trunk instead just makes it a mushroom. Roots are
  // the one cue that survives at 8x8.
  G: ['..####..', '.######.', '########', '########', '.######.', '...##...', '...##...', '.######.'],
  C: ['...##...', '..####..', '.######.', '########', '########', '.######.', '..####..', '...##...'],
};

// A second ink over the same 8x8 cell. Every pixel here must also be set in
// SYMBOLS -- this paints over the first pass, it does not extend it.
//
// Only the flame gets one, for the hot core of its ball: red then runs cool
// orange at the edges and up the tongue, yellow in the middle, the way fire
// actually falls. The tongue and the spark stay orange -- lighting the thin
// parts as well leaves the whole symbol one flat yellow shape again.
//
// The tree does not, and shouldn't. Pico-8 has exactly two greens and the
// lighter one is already the disc, so the only ink left to shade a dark green
// tree with is black -- which is also the colour of the disc's outline. Even
// one column of it down the canopy's edge stops reading as a shadowed side and
// starts reading as a hole chewed through the pip. The tree reads from its
// silhouette instead.
const SHADES = {
  R: ['........', '........', '........', '........', '..###...', '..####..', '..###...', '...##...'],
};

// The unselected pip is dark grey, so a selected pip has to be lighter or more
// saturated than that -- which is why black mana is a *black* face with a grey
// rim rather than the dark grey it would otherwise want to be.
const PIP_THEMES = {
  W: { face: WHITE,   rim: PEACH,      sym: BROWN,     gloss: null },
  U: { face: BLUE,    rim: DARKBLUE,   sym: WHITE,     gloss: WHITE },
  B: { face: BLACK,   rim: LAVENDER,   sym: LIGHTGREY, gloss: LAVENDER },
  R: { face: RED,     rim: DARKPURPLE, sym: ORANGE,    gloss: PINK,  symShade: YELLOW },
  G: { face: GREEN,   rim: DARKGREEN,  sym: DARKGREEN, gloss: WHITE },
  C: { face: WHITE,   rim: DARKGREY,   sym: DARKGREY,  gloss: null },
};
// the unselected state of every pip is the same washed-out grey
const PIP_OFF = { offFace: DARKGREY, offRim: BLACK, offSym: LIGHTGREY };

// ------------------------------------------------------------------ build

fs.mkdirSync(EXPORTS, { recursive: true });
const made = [];

const LABELS = [
  // No GO: the search form runs itself. Every region commits when you leave
  // it -- see window.noteTextEdited in qml/Main.qml -- so RESET ALL is the
  // only button the panel needs.
  ['mtg-btn-export',    'EXPORT',    PRIMARY],
  ['mtg-btn-import',    'IMPORT',    ACCENT],
  ['mtg-btn-new-list',  '+ NEW',     ACCENT],
  ['mtg-btn-reset',     'RESET ALL', NEUTRAL],
  ['mtg-btn-copy',      'COPY',      NEUTRAL],
  ['mtg-btn-rename',    'RENAME',    NEUTRAL],
  ['mtg-btn-duplicate', 'DUPLICATE', NEUTRAL],
  ['mtg-btn-delete',    'DELETE',    DANGER],
  ['mtg-btn-cancel',    'CANCEL',    NEUTRAL],
  // turns an enlarged double-faced card over to its other side
  ['mtg-btn-flip',      'FLIP',      ACCENT],
  ['mtg-btn-close',     'CLOSE',     NEUTRAL],
  ['mtg-btn-ok',        'OK',        PRIMARY],
  // the two kinds a new list can be, as a pair of toggles
  ['mtg-btn-kind-list',   'LIST',        NEUTRAL, { icon: 'list',  w: 58 }],
  ['mtg-btn-kind-deck',   'DECK',        ARCANE,  { icon: 'crown', w: 58 }],
];

for (const [name, label, theme, opts] of LABELS) {
  const frames = labelButton(label, theme, opts);
  made.push(saveSprite(name, frames, ['ui', 'button', 'mtg'], frames[0].w, frames[0].h));
}

const ICON_BUTTONS = [
  ['mtg-icon-plus',      'plus',   ACCENT],
  ['mtg-icon-minus',     'minus',  NEUTRAL],
  ['mtg-icon-close',     'close',  DANGER],
  ['mtg-icon-check',     'check',  PRIMARY],
  ['mtg-icon-commander', 'crown',  ARCANE],
  ['mtg-icon-list',      'list',   NEUTRAL],
  ['mtg-icon-more',      'more',   NEUTRAL],
  ['mtg-icon-search',    'search', NEUTRAL],
  ['mtg-icon-sort-desc', 'sortDesc', NEUTRAL],
  ['mtg-icon-sort-asc',  'sortAsc',  NEUTRAL],
  ['mtg-icon-panel',     'panel',  NEUTRAL],
];

for (const [name, icon, theme] of ICON_BUTTONS) {
  const frames = iconButton(ICONS[icon], theme);
  made.push(saveSprite(name, frames, ['ui', 'icon', 'button', 'mtg'], 16, 16));
}

// A checkbox needs its two frames to differ in *content*, not just in bevel:
// the tick sprite reads as ticked whichever frame you show, so the off state
// has to be an empty well instead.
{
  const off = buttonPlate(16, 16, { out: BLACK, face: WHITE, light: LIGHTGREY, dark: WHITE }, true);
  const on = buttonPlate(16, 16, PRIMARY, false);
  stamp(on, ICONS.check, 4, 4, BLACK);
  made.push(saveSprite('mtg-check-box', [off, on], ['ui', 'icon', 'button', 'mtg'], 16, 16));
}

for (const letter of Object.keys(SYMBOLS)) {
  const theme = Object.assign({}, PIP_THEMES[letter], PIP_OFF);
  const sym = SYMBOLS[letter], shade = SHADES[letter];
  const frames = [pip(sym, shade, theme, false), pip(sym, shade, theme, true)];
  made.push(saveSprite('mtg-pip-' + letter.toLowerCase(), frames, ['ui', 'mana', 'pip', 'mtg'], 16, 16));
}

for (const sprite of made) exportSheet(sprite, 4);

// The app wants each state as its own file, at 1:1 -- QML scales it up with
// smooth:false, so the scale is chosen per use site rather than baked in here.
const APP_ASSETS = path.join(APP, 'qml', 'assets');
fs.mkdirSync(APP_ASSETS, { recursive: true });
for (const sprite of made) {
  ['up', 'down'].forEach((state, f) => {
    const c = S.frameToRGBA(sprite, f, 1);
    fs.writeFileSync(path.join(APP_ASSETS, sprite.name + '-' + state + '.png'),
                     encodePNG(c.width, c.height, c.rgba));
  });
}
console.log('app assets -> ' + APP_ASSETS);

console.log(made.length + ' sprites -> ' + LIBRARY);
for (const s of made) console.log('  ' + s.name.padEnd(20) + s.w + 'x' + s.h + '  ' + s.frames.length + ' frames');
