// Chamber editor: paint terrain, place treasures, keys, doors, drops and the ball, tune the
// player physics, and play-test the chamber with the real game code. Works on a level pack
// (the rooms.json format plus a "physics" object), kept in localStorage and exported as JSON.
//
// Coordinates: the canvas is 320x200 with the HUD row on top; chamber cell (col, row) is at
// (16*col, 8 + 8*row). Game positions are 7800 units: px = x*2 - 8, py = y.

import { createPlatform } from '../platform/web.js';
import { Game } from '../game/game.js';
import { Room, decodeTiles, OBJ, ROOM_W, ROOM_H, MAP_W, MAP_H, FACE_LEFT, FACE_RIGHT } from '../game/room.js';
import { newGameState } from '../game/state.js';
import { PHYSICS_PARAMS, ROM_PHYSICS, physicsFrom, jumpProfile } from '../game/physics.js';

const STORE = 'downland.editor.pack';
const HUD = 8;
const toPx = (x) => x * 2 - 8;
const $ = (id) => document.getElementById(id);

// Terrain tiles (index into tiles.png) with what they do in the game's collision.
const TERRAIN = [
  { t: 2, name: 'Floor', does: 'stand on it' },
  { t: 1, name: 'Rope', does: 'climb' },
  { t: 22, name: 'Rope top', does: 'climb' },
  { t: 21, name: 'Bar', does: 'grab from below' },
  { t: 4, name: 'Wall', does: 'blocks' },
  { t: 5, name: 'Wall', does: 'blocks' },
  { t: 12, name: 'Wall pair', does: 'blocks' },
  { t: 6, name: 'Ceiling dip', does: 'blocks' },
  { t: 7, name: 'Slope down', does: 'blocks' },
  { t: 8, name: 'Slope up', does: 'blocks' },
  { t: 19, name: 'Ledge lip', does: 'blocks walking' },
  { t: 20, name: 'Ledge lip', does: 'blocks walking' },
  { t: 3, name: 'Stalactites', does: 'decoration' },
];
const WALL_TILES = new Set([3, 4, 5, 6, 7, 8, 12]);   // palette 0 in the ROM; the rest use 7
const PALETTE_NAMES = ['Walls', '1', 'Doors / rings', '3', 'Keys', 'Diamonds', '6', 'Ropes / floors / text'];

const OBJECT_TOOLS = [
  { tool: 'diamond', name: 'Diamond', tile: OBJ.DIAMOND >> 1, pal: 5 },
  { tool: 'ring', name: 'Ring', tile: OBJ.RING >> 1, pal: 2 },
  { tool: 'key', name: 'Key', tile: OBJ.KEY >> 1, pal: 4 },
  { tool: 'ball', name: 'Ball start', sprite: 'ball' },
  { tool: 'start', name: 'Start here', sprite: 'player' },
];

const ed = {
  pack: null, cur: 0, tab: 'paint', tool: 'paint', tile: 2, palette: 'auto', keyDoor: null,
  grid: true, hover: null, playing: false, game: null, playStart: null, painting: null,
};
let tiles, sprites, spriteSheet, platform;
const canvas = $('screen'), ctx = canvas.getContext('2d');
ctx.imageSmoothingEnabled = false;

// ---------- pack ----------

function savePack() {
  platform.storage.set(STORE, JSON.stringify(ed.pack));
}

async function loadRomPack() {
  const rooms = await platform.loadJSON('data/rooms.json');
  rooms.physics = { ...ROM_PHYSICS };
  return rooms;
}

const def = () => ed.pack.rooms[ed.cur];
const allDoors = () => ed.pack.rooms.flatMap((r) => r.doors.map((d) => ({ room: r, door: d })));

function doorPos(side, row) {
  return { raw: (side === 'right' ? 0x80 : 0) | row, side, x: side === 'right' ? 0x8D : 0x0B, y: row * 8 - 1 };
}

// Auto arrival: the door in the destination that leads back here, else the opposite wall.
function updateArrivals() {
  for (const r of ed.pack.rooms) {
    for (const d of r.doors) {
      if (!d.arriveAuto) continue;
      const back = ed.pack.rooms[d.to]?.doors.find((o) => o.to === r.id);
      d.arrive = back ? { ...back.at } : doorPos(d.at.side === 'right' ? 'left' : 'right', d.at.raw & 0x7F);
    }
  }
}

function changed() {
  updateArrivals();
  savePack();
  renderPanels();
}

// ---------- drawing ----------

const tintCache = new Map();
function tintedTile(t, color) {
  const key = t + color;
  let c = tintCache.get(key);
  if (!c) {
    c = document.createElement('canvas');
    c.width = 16; c.height = 8;
    const cx = c.getContext('2d'), img = cx.createImageData(16, 8);
    const v = parseInt(color.slice(1), 16), bits = tiles[t];
    for (let i = 0; i < 128; i++) {
      if (!bits[i]) continue;
      img.data.set([v >> 16, (v >> 8) & 255, v & 255, 255], i * 4);
    }
    cx.putImageData(img, 0, 0);
    tintCache.set(key, c);
  }
  return c;
}

function sprite(cx, index, x, y) {
  const s = sprites.sprites[index];
  cx.drawImage(spriteSheet, s.x, s.y, s.w, s.h, x, y, s.w, s.h);
}

const surface = document.createElement('canvas');
surface.width = ROOM_W; surface.height = ROOM_H;

function renderEditor() {
  const d = def(), pal = d.palettesRGB;
  const room = new Room(d, tiles);
  room.placeObjects(newGameState(ed.pack.rooms, ed.pack.doorOpenInitial));
  surface.getContext('2d').putImageData(new ImageData(room.rgba, ROOM_W, ROOM_H), 0, 0);
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, 320, 200);
  ctx.drawImage(surface, 0, HUD);
  for (const o of room.objects()) {
    if (!o.code) continue;
    const color = o.code === OBJ.KEY ? pal[4][2] : o.code === OBJ.DIAMOND ? pal[5][2] : pal[2][2];
    ctx.drawImage(tintedTile(o.code >> 1, color), o.col * 16, HUD + o.row * 8);
  }
  const drop = sprites.sprites.findIndex((s) => s.addr === '$E02E');
  for (const [x, y] of uniqueDrops(d)) sprite(ctx, drop, toPx(x), y);
  if (d.ball) sprite(ctx, sprites.ballFrames[0], toPx(d.ball.x), d.ball.y);
  if (ed.playStart?.room === ed.cur) {
    const [head, legs] = sprites.playerFrames[ed.playStart.facing === FACE_LEFT ? 6 : 2];
    sprite(ctx, head, toPx(ed.playStart.x), ed.playStart.y);
    sprite(ctx, legs, toPx(ed.playStart.x), ed.playStart.y + 8);
  }
  if (ed.grid) {
    ctx.fillStyle = 'rgba(207,198,255,0.07)';
    for (let c = 1; c < MAP_W; c++) ctx.fillRect(c * 16, HUD, 1, ROOM_H);
    for (let r = 1; r < MAP_H; r++) ctx.fillRect(0, HUD + r * 8, 320, 1);
  }
  // door labels: id and destination
  ctx.font = '6px ui-monospace, monospace';
  ctx.textBaseline = 'top';
  for (const door of d.doors) {
    const row = door.at.raw & 0x7F, right = door.at.side === 'right';
    const label = `#${door.id}→${chamberName(door.to)}${ed.pack.doorOpenInitial[door.id] ? '' : ' locked'}`;
    ctx.fillStyle = 'rgba(0,0,0,.6)';
    const w = ctx.measureText(label).width + 2;
    const x = right ? 286 - w : 18;
    ctx.fillRect(x, HUD + (row - 2) * 8, w, 7);
    ctx.fillStyle = '#fff';
    ctx.fillText(label, x + 1, HUD + (row - 2) * 8);
  }
  if (ed.hover && ed.hover.row >= 0 && ed.hover.row < MAP_H) {
    ctx.strokeStyle = 'rgba(173,211,0,.9)';
    ctx.lineWidth = 1;
    ctx.strokeRect(ed.hover.col * 16 + 0.5, HUD + ed.hover.row * 8 + 0.5, 15, 7);
  }
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, 320, HUD);
  ctx.fillStyle = pal[7][2];
  ctx.font = '7px ui-monospace, monospace';
  ctx.fillText(`${d.name}  ${ed.hover ? `col ${ed.hover.col} row ${ed.hover.row}` : ''}`, 2, 0);
}

const chamberName = (i) => (i === 10 ? 'X' : String(i));

// ---------- tools ----------

function cellFromEvent(e) {
  const r = canvas.getBoundingClientRect();
  const px = (e.clientX - r.left) * 320 / r.width, py = (e.clientY - r.top) * 200 / r.height;
  return { px, py, col: Math.floor(px / 16), row: Math.floor((py - HUD) / 8) };
}

const inMap = (c) => c.col >= 0 && c.col < MAP_W && c.row >= 0 && c.row < MAP_H;

function paintCell(c, erase) {
  if (!inMap(c)) return;
  const d = def();
  const t = erase ? 0 : ed.tile;
  const p = erase ? 7 : ed.palette === 'auto' ? (WALL_TILES.has(t) ? 0 : 7) : +ed.palette;
  if (d.tiles[c.row][c.col] === t && d.tilePalette[c.row][c.col] === p) return;
  d.tiles[c.row][c.col] = t;
  d.tilePalette[c.row][c.col] = p;
  if (erase) removeItemAt(c);
}

function removeItemAt(c) {
  const d = def();
  const n = d.treasures.length + d.keys.length;
  d.treasures = d.treasures.filter((t) => t.col !== c.col || t.row !== c.row);
  d.keys = d.keys.filter((k) => k.col !== c.col || k.row !== c.row);
  return n !== d.treasures.length + d.keys.length;
}

function freeSlot(list) {
  const used = new Set(list.map((o) => o.slot));
  for (let s = ed.cur * 4; s < ed.cur * 4 + 4; s++) if (!used.has(s)) return s;
  return -1;
}

function placeItem(c, kind) {
  if (!inMap(c)) return;
  const d = def();
  removeItemAt(c);
  if (kind === 'key') {
    if (ed.keyDoor === null) return status('Add a door first: a key needs a door to open.', true);
    const slot = freeSlot(d.keys);
    if (slot < 0) return status('This chamber already has 4 keys.', true);
    d.keys.push({ slot, col: c.col, row: c.row, door: ed.keyDoor });
  } else {
    const slot = freeSlot(d.treasures);
    if (slot < 0) return status('This chamber already has 4 treasures.', true);
    d.treasures.push({ slot, col: c.col, row: c.row, code: kind === 'ring' ? OBJ.RING : OBJ.DIAMOND });
  }
  d.tiles[c.row][c.col] = 0;    // items sit in empty cells
}

// Standing position for a click: the first floor at or below it.
function standAt(c) {
  const d = def();
  for (let r = Math.max(c.row, 1); r < MAP_H; r++) {
    if (d.tiles[r][c.col] === 2) {
      return { room: ed.cur, x: Math.max(0x0C, Math.min(0x8C, Math.round((c.px + 8) / 2) - 3)), y: r * 8 - 1, facing: FACE_RIGHT };
    }
  }
  return null;
}

function addDoor(side, row) {
  const d = def();
  row = Math.max(2, Math.min(MAP_H - 1, row));
  if (d.doors.some((o) => o.at.side === side && Math.abs((o.at.raw & 0x7F) - row) < 3)) {
    return status('Doors on the same wall need 3 rows between them.', true);
  }
  const id = ed.pack.doorOpenInitial.length;
  ed.pack.doorOpenInitial.push(1);
  const to = ed.cur === 0 ? 1 : 0;
  d.doors.push({ id, at: doorPos(side, row), to, arrive: doorPos(side, row), arriveAuto: true });
  const col = side === 'right' ? 18 : 0;
  for (let r = row - 2; r <= row; r++) d.tiles[r][col] = 0;
  if (ed.keyDoor === null) ed.keyDoor = id;
  status(`Door #${id} added. Set where it leads in the Doors tab.`);
  ed.tab = 'doors';
}

function deleteDoor(door) {
  const d = def();
  d.doors = d.doors.filter((o) => o !== door);
  let keys = 0;
  for (const r of ed.pack.rooms) {
    const before = r.keys.length;
    r.keys = r.keys.filter((k) => k.door !== door.id);
    keys += before - r.keys.length;
  }
  ed.pack.doorOpenInitial[door.id] = 1;   // id stays reserved so other doors keep theirs
  if (ed.keyDoor === door.id) ed.keyDoor = allDoors()[0]?.door.id ?? null;
  status(`Door #${door.id} deleted${keys ? `, and ${keys} key${keys > 1 ? 's' : ''} that opened it` : ''}.`);
}

// Drops: the game picks one of 32 entries at random, so the unique points are repeated to fill 32.
function uniqueDrops(d) {
  const seen = new Set(), out = [];
  for (const [x, y] of d.dropSpawns) {
    const k = x + ',' + y;
    if (!seen.has(k)) { seen.add(k); out.push([x, y]); }
  }
  return out;
}

function setDrops(d, points) {
  d.dropSpawns = points.length ? Array.from({ length: 32 }, (_, i) => [...points[i % points.length]]) : [];
}

function toggleDrop(c, remove) {
  const d = def(), pts = uniqueDrops(d);
  const x = Math.round((c.px + 4) / 2), y = Math.round(c.py) - 4;   // sprite centred on the click
  const near = pts.findIndex(([px, py]) => Math.abs(toPx(px) + 4 - c.px) < 6 && Math.abs(py + 4 - c.py) < 6);
  if (near >= 0) pts.splice(near, 1);
  else if (!remove) pts.push([x, y]);
  else return;
  setDrops(d, pts);
}

function useTool(c, e, first) {
  const erase = e.button === 2 || (e.buttons & 2) !== 0;
  const d = def();
  switch (ed.tool) {
    case 'paint': paintCell(c, erase); break;
    case 'diamond': case 'ring': case 'key':
      if (!first) return;
      if (erase) removeItemAt(c); else placeItem(c, ed.tool);
      break;
    case 'ball':
      if (!first) return;
      d.ball = erase ? null : { x: Math.round((c.px + 4) / 2), y: Math.round(c.py) - 4 };
      break;
    case 'start':
      if (!first) return;
      ed.playStart = erase ? null : standAt(c);
      if (!erase && !ed.playStart) status('No floor below that spot.', true);
      return;
    case 'door':
      if (!first) return;
      if (erase) {
        const door = d.doors.find((o) => (o.at.side === 'right') === (c.col >= 10) && Math.abs((o.at.raw & 0x7F) - 1 - c.row) <= 1);
        if (door) deleteDoor(door);
      } else {
        addDoor(c.col >= 10 ? 'right' : 'left', c.row);
      }
      break;
    case 'drop':
      if (!first) return;
      toggleDrop(c, erase);
      break;
  }
  ed.dirty = true;
}

canvas.addEventListener('contextmenu', (e) => e.preventDefault());
canvas.addEventListener('pointerdown', (e) => {
  if (ed.playing) return;
  canvas.setPointerCapture(e.pointerId);
  ed.painting = true;
  useTool(cellFromEvent(e), e, true);
});
canvas.addEventListener('pointermove', (e) => {
  if (ed.playing) return;
  const c = cellFromEvent(e);
  ed.hover = inMap(c) ? c : null;
  if (ed.painting) useTool(c, e, false);
});
const endPaint = () => {
  if (!ed.painting) return;
  ed.painting = false;
  if (ed.dirty) { ed.dirty = false; changed(); }
};
canvas.addEventListener('pointerup', endPaint);
canvas.addEventListener('pointercancel', endPaint);
canvas.addEventListener('pointerleave', () => { ed.hover = null; });

// ---------- panels ----------

let statusTimer;
function status(msg, warn = false) {
  const el = $('status');
  el.textContent = msg;
  el.classList.toggle('warn', warn);
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => { el.textContent = ''; }, 6000);
}

function tileButton(label, sub, drawTile, onClick, active) {
  const b = document.createElement('button');
  b.className = 'swatch' + (active ? ' on' : '');
  const c = document.createElement('canvas');
  c.width = 16; c.height = 8;
  drawTile(c.getContext('2d'));
  b.append(c, Object.assign(document.createElement('span'), { textContent: label }));
  if (sub) b.append(Object.assign(document.createElement('span'), { textContent: sub, className: 'hint' }));
  b.addEventListener('click', onClick);
  return b;
}

function renderPanels() {
  const d = def(), pal = d.palettesRGB;
  if (ed.tab === 'drops') ed.tool = 'drop';
  if (ed.tab === 'doors') ed.tool = 'door';
  if (ed.tab === 'paint') ed.tool = 'paint';
  if (ed.tab === 'objects' && !OBJECT_TOOLS.some((o) => o.tool === ed.tool)) ed.tool = 'diamond';
  for (const b of document.querySelectorAll('.tabs button')) b.classList.toggle('on', b.dataset.tab === ed.tab);
  for (const p of document.querySelectorAll('.panel')) p.classList.toggle('on', p.id === 'tab-' + ed.tab);

  // paint
  $('tiles').replaceChildren(...TERRAIN.map(({ t, name, does }) => tileButton(name, does,
    (cx) => cx.drawImage(tintedTile(t, pal[WALL_TILES.has(t) ? 0 : 7][2]), 0, 0),
    () => { ed.tool = 'paint'; ed.tile = t; renderPanels(); },
    ed.tool === 'paint' && ed.tile === t)));
  $('palette').replaceChildren(new Option('Auto (by tile)', 'auto'),
    ...PALETTE_NAMES.map((n, i) => new Option(`${i}: ${n}`, i)));
  $('palette').value = ed.palette;
  $('colors').replaceChildren(...pal.map((p, i) => {
    const l = document.createElement('label');
    const input = Object.assign(document.createElement('input'), { type: 'color', value: p[2] });
    input.addEventListener('change', () => { p[2] = input.value; tintCache.clear(); changed(); });
    l.append(input, `${i} ${PALETTE_NAMES[i]}`);
    return l;
  }));

  // objects
  $('objtools').replaceChildren(...OBJECT_TOOLS.map((o) => tileButton(o.name, null, (cx) => {
    if (o.tile !== undefined) cx.drawImage(tintedTile(o.tile, pal[o.pal][2]), 0, 0);
    else if (o.sprite === 'ball') sprite(cx, sprites.ballFrames[0], 4, 0);
    else { const [head] = sprites.playerFrames[2]; sprite(cx, head, 0, 0); }
  }, () => { ed.tool = o.tool; renderPanels(); }, ed.tool === o.tool)));
  const doors = allDoors();
  if (ed.keyDoor === null || !doors.some((x) => x.door.id === ed.keyDoor)) ed.keyDoor = doors[0]?.door.id ?? null;
  $('keydoor').replaceChildren(...doors.map(({ room, door }) => new Option(
    `#${door.id} in ${chamberName(room.id)}, ${door.at.side} row ${door.at.raw & 0x7F} → ${chamberName(door.to)}`, door.id)));
  if (ed.keyDoor !== null) $('keydoor').value = ed.keyDoor;

  // doors
  $('doors').replaceChildren(...d.doors.map(doorEditor));

  // drops
  $('dropcount').textContent = `${uniqueDrops(d).length} spawn point(s)`;

  renderSliders();
}

function doorEditor(door) {
  const box = document.createElement('div');
  box.className = 'door';
  const chambers = ed.pack.rooms.map((r) => new Option(r.name, r.id));
  const row = door.at.raw & 0x7F;
  box.innerHTML = `
    <strong>Door #${door.id}</strong>
    <div class="row">
      <label>Wall <select data-k="side"><option value="left">left</option><option value="right">right</option></select></label>
      <label>Row <input type="number" data-k="row" min="2" max="23" value="${row}"></label>
      <label><input type="checkbox" data-k="open" ${ed.pack.doorOpenInitial[door.id] ? 'checked' : ''}> open at start</label>
    </div>
    <div class="row"><label>Leads to <select data-k="to"></select></label></div>
    <div class="row">
      <label><input type="checkbox" data-k="auto" ${door.arriveAuto ? 'checked' : ''}> auto arrival</label>
      <label>at <select data-k="aside"><option value="left">left</option><option value="right">right</option></select></label>
      <label>row <input type="number" data-k="arow" min="2" max="23" value="${door.arrive.raw & 0x7F}"></label>
    </div>
    <div class="row"><button data-k="del">Delete door</button></div>`;
  const q = (k) => box.querySelector(`[data-k="${k}"]`);
  q('side').value = door.at.side;
  q('to').replaceChildren(...chambers);
  q('to').value = door.to;
  q('aside').value = door.arrive.side;
  q('aside').disabled = q('arow').disabled = !!door.arriveAuto;
  const apply = () => {
    const side = q('side').value, r = Math.max(2, Math.min(23, +q('row').value || 2));
    door.at = doorPos(side, r);
    door.to = +q('to').value;
    door.arriveAuto = q('auto').checked;
    if (!door.arriveAuto) door.arrive = doorPos(q('aside').value, Math.max(2, Math.min(23, +q('arow').value || 2)));
    ed.pack.doorOpenInitial[door.id] = q('open').checked ? 1 : 0;
    const col = side === 'right' ? 18 : 0;
    for (let y = r - 2; y <= r; y++) def().tiles[y][col] = 0;
    changed();
  };
  for (const k of ['side', 'row', 'to', 'auto', 'aside', 'arow', 'open']) q(k).addEventListener('change', apply);
  q('del').addEventListener('click', () => { deleteDoor(door); changed(); });
  return box;
}

// Height and reach of a running jump on flat ground, in tiles (8 lines tall, 8 hpos wide).
function updateJumpInfo() {
  const j = jumpProfile(ed.pack.physics), tiles = (n) => +(n / 8).toFixed(1);
  const el = $('jumpinfo');
  el.textContent = `Running jump: ${tiles(j.height)} tiles high, ${tiles(j.distance)} tiles across, ` +
    `lands at speed ${j.landSpeed}` + (j.kills ? ' — that landing KILLS on flat ground. Lower jump power or gravity, or raise the deadly landing speed.' : ' (safe).');
  el.classList.toggle('warn', j.kills);
}

function renderSliders() {
  const ph = ed.pack.physics;
  const info = Object.assign(document.createElement('div'), { id: 'jumpinfo' });
  $('sliders').replaceChildren(info, ...PHYSICS_PARAMS.map((p) => {
    const box = document.createElement('div');
    box.className = 'slider';
    const changedFromRom = ph[p.key] !== ROM_PHYSICS[p.key];
    if (p.toggle) {
      box.innerHTML = `<label class="row ${changedFromRom ? 'changed' : ''}"><input type="checkbox" ${ph[p.key] ? 'checked' : ''}> ${p.label}</label>`;
      box.querySelector('input').addEventListener('change', (e) => {
        ph[p.key] = e.target.checked ? 1 : 0;
        e.target.blur();
        savePack(); renderSliders();
      });
    } else {
      const fmt = (v) => `${+v.toFixed(4)}${p.unit ? ' ' + p.unit : ''}`;
      box.innerHTML = `
        <div class="top"><label class="${changedFromRom ? 'changed' : ''}">${p.label}</label><output>${fmt(ph[p.key])}</output></div>
        <input type="range" min="${p.min}" max="${p.max}" step="${p.step}" value="${ph[p.key]}" aria-label="${p.label}">
        <small>ROM: ${fmt(ROM_PHYSICS[p.key])}${p.help ? ' · ' + p.help : ''}</small>`;
      const input = box.querySelector('input'), out = box.querySelector('output');
      input.addEventListener('input', () => { ph[p.key] = +input.value; out.textContent = fmt(+input.value); updateJumpInfo(); });
      input.addEventListener('change', () => { input.blur(); savePack(); renderSliders(); });
    }
    return box;
  }));
  updateJumpInfo();
}

function renderChamberSelect() {
  $('chamber').replaceChildren(...ed.pack.rooms.map((r) => new Option(r.name, r.id)));
  $('chamber').value = ed.cur;
}

// ---------- play-test ----------

async function startPlay() {
  if (ed.playing) return;
  updateArrivals();
  const game = new Game(platform);
  await game.load('.', structuredClone(ed.pack));
  game.physics = ed.pack.physics;            // shared: slider changes apply immediately
  game.beginner = $('nodrops').checked;
  if (game.beginner) game.difficulty = 0;
  platform.input.takePressed();
  game.startGame();
  game.jumpToRoom(ed.cur);
  if (ed.playStart?.room === ed.cur) game.player.reset(ed.playStart);
  game.player.jumpLatch = true;
  ed.game = game;
  ed.playing = true;
  canvas.classList.add('playing');
  $('play').textContent = '■ Stop';
  canvas.focus();
}

function stopPlay() {
  if (!ed.playing) return;
  ed.playing = false;
  ed.game.sound.stopAll();
  platform.audio.setRegisters(ed.game.sound.update());
  ed.game = null;
  canvas.classList.remove('playing');
  $('play').textContent = '▶ Play-test';
}

// ---------- loop ----------

function loop() {
  const STEP = 1000 / 60;
  let last = performance.now(), acc = 0;
  const frame = (now) => {
    acc += Math.min(now - last, 250);
    last = now;
    if (ed.playing) {
      while (acc >= STEP && ed.playing) {
        ed.game.update();
        if (ed.game.mode === 'title') stopPlay();    // game over, or R pressed
        acc -= STEP;
      }
      if (ed.playing) ed.game.render();
    } else {
      acc = 0;
      renderEditor();
    }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

// ---------- wiring ----------

// Destructive buttons ask for a second click within 3 seconds (no browser dialogs).
function confirmClick(button, ask, action) {
  const label = button.textContent;
  let armed = null;
  button.addEventListener('click', () => {
    if (!armed) {
      button.textContent = ask;
      button.classList.add('armed');
      armed = setTimeout(() => { armed = null; button.textContent = label; button.classList.remove('armed'); }, 3000);
      return;
    }
    clearTimeout(armed);
    armed = null;
    button.textContent = label;
    button.classList.remove('armed');
    action();
  });
}

function wire() {
  for (const b of document.querySelectorAll('.tabs button')) {
    b.addEventListener('click', () => { ed.tab = b.dataset.tab; renderPanels(); });
  }
  $('chamber').addEventListener('change', (e) => { stopPlay(); ed.cur = +e.target.value; renderPanels(); });
  $('palette').addEventListener('change', (e) => { ed.palette = e.target.value; });
  $('keydoor').addEventListener('change', (e) => { ed.keyDoor = +e.target.value; });
  $('play').addEventListener('click', () => (ed.playing ? stopPlay() : startPlay()));
  $('add-door').addEventListener('click', () => {
    // first free spot: right wall then left, top down
    const d = def(), free = (side, row) => !d.doors.some((o) => o.at.side === side && Math.abs((o.at.raw & 0x7F) - row) < 3);
    for (const side of ['right', 'left']) {
      for (let row = 4; row < MAP_H; row++) if (free(side, row)) { addDoor(side, row); changed(); return; }
    }
    status('No room for another door in this chamber.', true);
  });
  $('clear-drops').addEventListener('click', () => { setDrops(def(), []); changed(); });
  $('reset-physics').addEventListener('click', () => {
    Object.assign(ed.pack.physics, ROM_PHYSICS);
    savePack(); renderSliders();
    status('Physics reset to the ROM values.');
  });
  confirmClick($('clear'), 'Click again to empty it', () => {
    const d = def();
    d.tiles = d.tiles.map((r) => r.map(() => 0));
    d.tilePalette = d.tilePalette.map((r) => r.map(() => 7));
    d.treasures = []; d.keys = []; d.ball = null;
    setDrops(d, []);
    changed();
    status(`${d.name} emptied. Doors stay.`);
  });
  confirmClick($('revert'), 'Click again to lose all edits', async () => {
    stopPlay();
    ed.pack = await loadRomPack();
    ed.playStart = null;
    changed(); renderChamberSelect();
    status('Reverted to the ROM chambers.');
  });
  $('copy').addEventListener('click', async () => {
    updateArrivals();
    const text = JSON.stringify(ed.pack);
    try {
      await navigator.clipboard.writeText(text);
      status(`Copied the level pack (${Math.round(text.length / 1024)} KB). Paste it into a file named levels.json.`);
    } catch {
      const area = Object.assign(document.createElement('textarea'), { value: text });
      document.body.append(area);
      area.select();
      const ok = document.execCommand('copy');
      area.remove();
      status(ok ? 'Copied the level pack. Paste it into a file named levels.json.' : 'Copying was blocked; use Export instead.', !ok);
    }
  });
  $('export').addEventListener('click', () => {
    updateArrivals();
    const blob = new Blob([JSON.stringify(ed.pack)], { type: 'application/json' });
    const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: 'levels.json' });
    a.click();
    URL.revokeObjectURL(a.href);
  });
  $('import').addEventListener('click', () => $('import-file').click());
  $('import-file').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    try {
      const pack = JSON.parse(await file.text());
      if (!Array.isArray(pack.rooms) || !Array.isArray(pack.doorOpenInitial)) throw new Error('not a level pack');
      pack.physics = physicsFrom(pack.physics);
      stopPlay();
      ed.pack = pack; ed.cur = 0; ed.playStart = null;
      changed(); renderChamberSelect();
      status(`Imported ${file.name}.`);
    } catch (err) {
      status(`Couldn't import ${file.name}: ${err.message}`, true);
    }
    e.target.value = '';
  });
  $('open-game').addEventListener('click', () => { updateArrivals(); savePack(); });   // a link: saving is all it needs
  addEventListener('keydown', (e) => {
    if (e.target instanceof Element && e.target.closest('input, select, textarea')) return;
    if (e.key === 'Escape') stopPlay();
    else if (ed.playing) return;
    else if (e.key === 'g' || e.key === 'G') ed.grid = !ed.grid;
    else if (e.key === 'p' || e.key === 'P') startPlay();
  });
}

// ---------- start ----------

platform = await createPlatform(canvas);
const [tileBmp, spriteData, sheet] = await Promise.all([
  platform.loadBitmap('assets/tiles.png'),
  platform.loadJSON('assets/sprites.json'),
  platform.loadBitmap('assets/sprites.png'),
]);
tiles = decodeTiles(tileBmp);
sprites = spriteData;
spriteSheet = sheet.handle;
try { ed.pack = JSON.parse(platform.storage.get(STORE)); } catch { ed.pack = null; }
if (!ed.pack?.rooms) ed.pack = await loadRomPack();
ed.pack.physics = physicsFrom(ed.pack.physics);
renderChamberSelect();
wire();
renderPanels();
loop();
window.editor = ed;   // console access
