#!/usr/bin/env node
'use strict';
/**
 * The README's pixel art, drawn through the same engine as the app's own —
 * a wordmark banner and a mana-pip rule, into the engine's library/ and out
 * as PNGs under docs/.
 *
 *   node tools/readme-art.js
 *
 * The banner is composited rather than drawn fresh: the crown and the six pips
 * are the app's own sprites, read back out of the library and stamped in. Redraw
 * one in the editor and this picks the new one up.
 */

const fs = require('fs');
const path = require('path');

const APP = path.resolve(__dirname, '..');
const ENGINE = process.env.PIXELART_ENGINE
             || path.resolve(APP, '..', '_Pixelart');
const S = require(path.join(ENGINE, 'lib/sprite.js'));
const { encodePNG } = require(path.join(ENGINE, 'lib/png.js'));
const LIBRARY = path.join(ENGINE, 'library');
const DOCS = path.join(APP, 'docs');

const PICO8 = S.PALETTES.pico8.colors;
const BLACK = 0, DARKBLUE = 1, DARKPURPLE = 2, DARKGREY = 5, LIGHTGREY = 6,
      WHITE = 7, YELLOW = 10;

const PF = require('./pixelfont.js');
const ADVANCE = PF.ADVANCE;
const textWidth = s => s.length * ADVANCE - 1;

// ------------------------------------------------------------------ canvas

function canvas(w, h) {
  const px = new Int16Array(w * h).fill(-1);
  return {
    w, h, px,
    set(x, y, v) { if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = v; },
    get(x, y) { return (x >= 0 && y >= 0 && x < w && y < h) ? px[y * w + x] : -1; },
  };
}

function drawText(c, text, ox, oy, color) {
  let x = ox;
  for (const ch of text.toUpperCase()) {
    const glyph = PF.GLYPHS[ch];
    if (!glyph) throw new Error('no glyph for "' + ch + '"');
    for (let y = 0; y < glyph.r.length; y++)
      for (let gx = 0; gx < glyph.r[y].length; gx++)
        if (glyph.r[y][gx] === '#') c.set(x + gx, oy + glyph.t + y, color);
    x += ADVANCE;
  }
}

/** Text with a one-pixel drop shadow, which is what keeps it off the field. */
function drawLabel(c, text, ox, oy, color, shadow) {
  drawText(c, text, ox + 1, oy + 1, shadow);
  drawText(c, text, ox, oy, color);
}

// ------------------------------------------------------------------ library

/** Read a sprite back out of the library, flattened to one frame of indices. */
function load(name, frame = 0) {
  const sprite = S.validate(JSON.parse(
    fs.readFileSync(path.join(LIBRARY, name + '.json'), 'utf8')));
  return { w: sprite.w, h: sprite.h, px: S.flattenFrame(sprite, frame) };
}

function blit(c, src, ox, oy) {
  for (let y = 0; y < src.h; y++)
    for (let x = 0; x < src.w; x++) {
      const v = src.px[y * src.w + x];
      if (v >= 0) c.set(ox + x, oy + y, v);
    }
}

// ------------------------------------------------------------------ chrome

/** 1px black outline with clipped corners, a bevel inside it, and a flat field. */
function plate(c, field, light, dark) {
  const { w, h } = c;
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const corner = (x < 1 || x > w - 2) && (y < 1 || y > h - 2);
      if (corner) continue;
      const edge = x === 0 || y === 0 || x === w - 1 || y === h - 1;
      const bevel = x === 1 || y === 1 || x === w - 2 || y === h - 2;
      c.set(x, y, edge ? BLACK
                : bevel ? ((x === 1 || y === 1) ? light : dark)
                : field);
    }
}

// ------------------------------------------------------------------ save

function save(name, c, tags) {
  const sprite = S.validate({
    format: 'pixelart/1',
    name, w: c.w, h: c.h, fps: 2,
    palette: PICO8.slice(),
    frames: [{ layers: [{ name: 'art', visible: true, opacity: 1,
                          data: S.encodeRLE(Array.from(c.px)) }] }],
    tags,
  });
  fs.writeFileSync(path.join(LIBRARY, name + '.json'),
                   JSON.stringify(sprite, null, 2));
  return sprite;
}

function exportPNG(sprite, scale, file) {
  const img = S.frameToRGBA(sprite, 0, scale);
  fs.writeFileSync(path.join(DOCS, file), encodePNG(img.width, img.height, img.rgba));
}

// ------------------------------------------------------------------ banner

// Frame 1 of a pip is its selected state, which is the coloured one; frame 0 is
// the grey it wears when the filter is off, and a rule of six greys says nothing.
const PIPS = ['w', 'u', 'b', 'r', 'g', 'c'].map(k => load('mtg-pip-' + k, 1));
const CROWN = load('mtg-icon-commander');

function banner() {
  const pipRow = PIPS.reduce((n, p) => n + p.w, 0);
  const lines = ['COMMAND', 'CREATION'];
  const block = CROWN.w + 4 + Math.max(...lines.map(textWidth));
  const w = Math.max(pipRow, block) + 20;
  const c = canvas(w, 52);
  plate(c, DARKBLUE, DARKPURPLE, BLACK);

  const left = Math.round((w - block) / 2);
  blit(c, CROWN, left, 5);
  lines.forEach((line, i) =>
    drawLabel(c, line, left + CROWN.w + 4, 6 + i * 9, YELLOW, BLACK));

  // A rule of the six identities, which is the one thing every deck here has.
  let x = Math.round((w - pipRow) / 2);
  for (const pip of PIPS) { blit(c, pip, x, 30); x += pip.w; }
  return c;
}

// ------------------------------------------------------------------ strip

/** A thin divider: the six pips on a dark bar, for breaking up the README. */
function rule() {
  const w = PIPS.reduce((n, p) => n + p.w, 0) + 8;
  const c = canvas(w, 20);
  for (let y = 0; y < c.h; y++) for (let x = 0; x < c.w; x++) c.set(x, y, BLACK);
  let x = 4;
  for (const pip of PIPS) { blit(c, pip, x, 2); x += pip.w; }
  return c;
}

// ------------------------------------------------------------------ run

fs.mkdirSync(DOCS, { recursive: true });

const jobs = [
  { name: 'mtg-readme-banner', draw: banner, scale: 3, file: 'banner.png' },
  { name: 'mtg-readme-rule',   draw: rule,   scale: 2, file: 'rule.png' },
];

for (const job of jobs) {
  const sprite = save(job.name, job.draw(), ['mtg', 'readme', 'banner']);
  exportPNG(sprite, job.scale, job.file);
  console.log(job.name + '  ' + sprite.w + 'x' + sprite.h + '  -> docs/' + job.file);
}
console.log('library -> ' + LIBRARY);
