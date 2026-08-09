#!/usr/bin/env node
'use strict';
/**
 * Stage two: take the reduced grids from set-glyphs.py and build them into real
 * sprites through the pixel art engine, so they land in the library alongside
 * everything else and can be opened in the editor and fixed by hand.
 *
 *   node tools/set-glyphs.js
 *
 * Sprites are tagged `set-symbol`, which is how you filter them back out of the
 * gallery once there are a couple of hundred of them.
 */

const fs = require('fs');
const path = require('path');

const APP = path.resolve(__dirname, '..');
const ENGINE = process.env.PIXELART_ENGINE
             || path.resolve(APP, '..', '_Pixelart');
const S = require(path.join(ENGINE, 'lib/sprite.js'));
const { encodePNG } = require(path.join(ENGINE, 'lib/png.js'));

const LIBRARY = path.join(ENGINE, 'library');
const APP_ASSETS = path.join(APP, 'qml', 'assets', 'sets');
const APP_ASSETS_HOT = path.join(APP, 'qml', 'assets', 'sets-hot');

const PICO8 = S.PALETTES.pico8.colors;
const BLACK = 0, DARKGREY = 5;
const YELLOW = 10, ORANGE = 9;

// The same artwork twice, in the two places a set symbol has to sit: dark ink
// for the card tiles, which are light, and the overlays' hot yellow for the
// dark plates, where black ink would vanish. It is one sprite with the palette
// swapped under it rather than two drawings, so a symbol fixed by hand in the
// editor stays fixed in both. The lighter of the two ink levels goes to orange,
// keeping the hairlines a step down from the solid ink the way dark grey does.
const HOT_PALETTE = PICO8.slice();
HOT_PALETTE[BLACK] = PICO8[YELLOW];
HOT_PALETTE[DARKGREY] = PICO8[ORANGE];

const input = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'set-glyphs.json'), 'utf8'));
const SIZE = input.size;

fs.mkdirSync(APP_ASSETS, { recursive: true });
fs.mkdirSync(APP_ASSETS_HOT, { recursive: true });

// clear out glyphs from a previous run, so a set that has since been dropped
// from the database does not leave a stale sprite behind
for (const file of fs.readdirSync(LIBRARY)) {
  if (file.startsWith('mtg-set-')) fs.unlinkSync(path.join(LIBRARY, file));
}
for (const dir of [APP_ASSETS, APP_ASSETS_HOT]) {
  for (const file of fs.readdirSync(dir)) {
    if (file.endsWith('.png')) fs.unlinkSync(path.join(dir, file));
  }
}

const names = Object.keys(input.glyphs).sort();
for (const name of names) {
  const rows = input.glyphs[name];
  const sprite = S.validate({
    format: 'pixelart/1',
    name: 'mtg-set-' + name,
    w: SIZE, h: SIZE, fps: 8,
    palette: PICO8.slice(),
    frames: [{
      layers: [{
        name: 'Layer 1', visible: true, opacity: 1,
        // '#' is the solid level, '+' the lighter one that keeps hairlines alive
        data: S.encodeRLE(Array.from(
          S.asciiToPixels(rows, { '#': BLACK, '+': DARKGREY }, SIZE, SIZE))),
      }],
    }],
    tags: ['mtg', 'set-symbol', 'icon'],
  });
  fs.writeFileSync(path.join(LIBRARY, sprite.name + '.json'),
                   JSON.stringify(sprite, null, 2));

  // the app draws these at 1:1, so export at 1:1
  const cell = S.frameToRGBA(sprite, 0, 1);
  fs.writeFileSync(path.join(APP_ASSETS, name + '.png'),
                   encodePNG(cell.width, cell.height, cell.rgba));

  const hot = S.frameToRGBA(
    Object.assign({}, sprite, { palette: HOT_PALETTE }), 0, 1);
  fs.writeFileSync(path.join(APP_ASSETS_HOT, name + '.png'),
                   encodePNG(hot.width, hot.height, hot.rgba));
}

console.log(names.length + ' set glyphs');
console.log('  library -> ' + LIBRARY + '/mtg-set-*.json');
console.log('  app     -> ' + APP_ASSETS);
console.log('  app hot -> ' + APP_ASSETS_HOT);
