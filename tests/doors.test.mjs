// Checks object placement and key/door logic against the ROM (tests/traces/objects.json,
// from tools/trace_objects.py). Run: node tests/doors.test.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Room } from '../src/game/room.js';
import { Player } from '../src/game/player.js';
import { Rng } from '../src/game/rng.js';
import { newGameState, collect } from '../src/game/state.js';

const here = dirname(fileURLToPath(import.meta.url));
const data = JSON.parse(readFileSync(join(here, '..', 'data', 'rooms.json')));
const trace = JSON.parse(readFileSync(join(here, 'traces', 'objects.json')));
const noTiles = new Proxy([], { get: (t, k) => (k === 'length' ? 128 : new Uint8Array(128)) });
let failed = 0;

function check(name, got, want) {
  const bad = [];
  for (let i = 0; i < want.length; i++)
    if (got[i] !== want[i]) bad.push(`(${i % 20},${Math.floor(i / 20)}) js ${got[i].toString(16)} rom ${want[i].toString(16)}`);
  if (bad.length) { failed++; console.log(`FAIL ${name}: ${bad.slice(0, 6).join(', ')}`); }
  else console.log(`ok   ${name}`);
}

const state = newGameState(data.rooms, data.doorOpenInitial);
data.rooms.forEach((def, r) => {
  const room = new Room(def, noTiles);
  room.placeObjects(state);
  check(`chamber ${r} objects and doors`, room.codes, trace.rooms[r]);
});

// Key pickup in chamber 0: fall through the key at column 5, row 6 like the ROM trace.
const s = newGameState(data.rooms, data.doorOpenInitial);
const room = new Room(data.rooms[0], noTiles);
room.placeObjects(s);
check('chamber 0 before key', room.codes, trace.keyPickup.before);
const p = new Player();
p.reset({ x: 0x2A, y: 0x2D, facing: 2 });
p.air = true; p.vertical = true; p.vyHi = 0xFF;
const idle = { isDown: () => false };
for (let f = 0; f < 8 && !p.events.some((e) => e.type === 'pickup'); f++) p.update(room, idle, f);
const ev = p.events.find((e) => e.type === 'pickup');
if (!ev) { failed++; console.log('FAIL key pickup: player never touched the key'); }
else collect(s, room, ev, new Rng());
check('chamber 0 after key (door 0 opens)', room.codes, trace.keyPickup.after);
check('key slots after pickup', s.keyDoor, trace.keyPickup.keysLeft);
check('door states after pickup', s.doorOpen, trace.keyPickup.doorOpen);
// Every key in the game, dropped through as in the ROM trace: the same door must open.
const keyBad = [];
for (const k of trace.allKeys) {
  const st = newGameState(data.rooms, data.doorOpenInitial);
  const rm = new Room(data.rooms[k.chamber], noTiles);
  rm.placeObjects(st);
  const doors = st.doorOpen.slice();
  const pl = new Player();
  pl.reset({ x: 4 + 8 * k.col - 2, y: 8 + 8 * k.row - 11, facing: 2 });
  pl.air = true; pl.vertical = true; pl.vyHi = 0xFF;
  for (let f = 1; f <= 12; f++) {
    pl.update(rm, idle, f);
    for (const e of pl.events) if (e.type === 'pickup') collect(st, rm, e, new Rng());
    pl.events.length = 0;
  }
  const opened = st.doorOpen.flatMap((v, i) => (v !== doors[i] ? [i] : []));
  if (!k.taken || JSON.stringify(opened) !== JSON.stringify(k.opened))
    keyBad.push(`chamber ${k.chamber} slot ${k.slot}: js ${JSON.stringify(opened)} rom ${JSON.stringify(k.opened)}`);
}
if (keyBad.length) { failed++; console.log('FAIL keys: ' + keyBad.join('; ')); }
else console.log(`ok   all ${trace.allKeys.length} keys open the ROM's door`);
process.exit(failed ? 1 : 0);
