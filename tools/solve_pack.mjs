// Can a level pack be played through? Explores every input sequence with the real player code
// (src/game/player.js) and the pack's physics, one decision per movement step, from where a
// game starts and from every door arrival it can reach. Keys it reaches open their doors,
// doors it reaches lead on, until nothing new opens up. Drops, the ball and the bird are
// ignored: this checks the cave, not your reflexes.
//
// Usage: node tools/solve_pack.mjs [levels.json]   (default data/rooms.json)
// Exit code 1 if any treasure, key or chamber can't be reached, or the round can't be finished.
import { readFileSync } from 'node:fs';
import { Room, FACE_RIGHT } from '../src/game/room.js';
import { Player } from '../src/game/player.js';
import { physicsFrom } from '../src/game/physics.js';
import { newGameState } from '../src/game/state.js';
import { ROM_RULES } from '../src/game/game.js';

const STATE = ['x', 'y', 'facing', 'vyHi', 'vyLo', 'air', 'vertical', 'jumpLatch', 'climbing', 'hanging', 'holdCount', 'hangSide'];
const INPUTS = ['', 'L', 'R', 'U', 'D', 'J', 'JL', 'JR'].map((s) => ({
  name: s,
  isDown: (k) => (k === 'left' && s.includes('L')) || (k === 'right' && s.includes('R')) ||
    (k === 'up' && s.includes('U')) || (k === 'down' && s.includes('D')) || (k === 'jump' && s.includes('J')),
}));
const isItem = (c) => c >= 0x20 && c <= 0x24;

// The chamber's collision map with every door in the given state and the items lifted out
// (they're targets, and in play they vanish when touched).
function chamberMap(pack, def, doorOpen) {
  const room = Object.create(Room.prototype);
  room.def = def;
  room.codes = new Uint8Array(480);
  def.tiles.forEach((row, r) => row.forEach((t, c) => { room.codes[r * 20 + c] = t * 2; }));
  const state = newGameState(pack.rooms, pack.doorOpenInitial);
  state.doorOpen = doorOpen;
  room.placeObjects(state);
  const items = new Map();
  room.codes.forEach((code, i) => { if (isItem(code)) { items.set(i, code); room.codes[i] = 0; } });
  return { room, items };
}

// Breadth-first search over player states from the given spawns. Returns the item cells
// touched and the doors walked through.
export function explore(pack, def, doorOpen, spawns, physics) {
  const { room, items } = chamberMap(pack, def, doorOpen);
  const player = new Player(physics);
  const touched = new Set(), exits = new Set(), seen = new Set();
  // the whole state as one number: x, y, vy (16 bits), facing, 6 flags, hold, hang side
  const key = () => {
    const p = player;
    return ((((p.x * 256 + p.y) * 65536 + p.vyHi * 256 + p.vyLo) * 4 + p.facing) * 64 +
      (p.air | p.vertical << 1 | p.jumpLatch << 2 | p.climbing << 3 | p.hanging << 4)) * 64 +
      p.holdCount * 4 + p.hangSide;
  };
  const save = () => Object.fromEntries(STATE.map((k) => [k, player[k]]));
  const touch = (x, y) => {
    const { col, row } = room.cellAt(x, y), i = row * 20 + col;
    if (col < 20 && row < 24 && items.has(i)) touched.add(i);
  };
  let queue = [];
  for (const s of spawns) {
    player.reset(s);
    const k = key();
    if (!seen.has(k)) { seen.add(k); queue.push(save()); }
  }
  while (queue.length) {
    const next = [];
    for (const s of queue) {
      for (const input of INPUTS) {
        Object.assign(player, s);
        player.dead = false; player.regen = false; player.splat = 0; player.midairDeath = 0;
        player.events.length = 0;
        let gone = false;
        for (let f = 0; f < physics.stepFrames && !gone; f++) {
          player.update(room, input, f);
          // what the game would pick up: walking into a cell, or touching it in the air / on a rope
          const { x, y } = player;
          if (!player.air && !player.climbing) { touch(x + 7, y + 8); touch(x, y + 8); }
          else { touch(x + 3, y + 1); touch(x + 3, y + 15); touch(x, y + 7); touch(x + 7, y + 7); }
          for (const ev of player.events) {
            if (ev.type !== 'door') continue;
            const row = ((y + 7) & 0xFF) >> 3;
            const door = def.doors.find((d) => d.at.side === ev.side && (d.at.raw & 0x7F) === row);
            if (door) exits.add(door.id);
            gone = true;
          }
          if (player.dead || player.splat || player.y > 0xC0) gone = true;
        }
        if (gone) continue;
        const k = key();
        if (seen.has(k)) continue;
        seen.add(k);
        next.push(save());
      }
    }
    queue = next;
  }
  return { touched, exits, items, states: seen.size };
}

export function solvePack(pack) {
  const physics = physicsFrom(pack.physics);
  const rules = { ...ROM_RULES, ...(pack.rules || {}) };
  const doorOpen = pack.doorOpenInitial.slice();
  const entries = new Map([[0, [{ ...rules.start }]]]);   // chamber -> spawns
  const taken = new Map();                                // chamber -> touched item cells
  const exited = new Set();
  const doorById = new Map(pack.rooms.flatMap((r) => r.doors.map((d) => [d.id, { room: r, door: d }])));
  const done = new Map();   // chamber -> what it was last explored with
  let changed = true, passes = 0;
  while (changed) {
    changed = false;
    passes++;
    for (const [id, spawns] of entries) {
      const def = pack.rooms[id];
      // explore again only if it has new ways in or one of its doors opened
      const sig = JSON.stringify([spawns, def.doors.map((d) => doorOpen[d.id])]);
      if (done.get(id) === sig) continue;
      done.set(id, sig);
      const r = explore(pack, def, doorOpen, spawns, physics);
      const got = taken.get(id) || new Set();
      for (const cell of r.touched) {
        if (got.has(cell)) continue;
        got.add(cell);
        changed = true;
        const key = def.keys.find((k) => k.row * 20 + k.col === cell);
        if (key && !doorOpen[key.door]) doorOpen[key.door] = 1;
      }
      taken.set(id, got);
      for (const doorId of r.exits) {
        if (exited.has(doorId)) continue;
        exited.add(doorId);
        changed = true;
        const { door } = doorById.get(doorId);
        let to = door.to;
        const spawn = Room.doorSpawn(door.arrive);
        const add = (room, s) => {
          if (!pack.rooms[room]) return;
          const list = entries.get(room) || [];
          if (!list.some((o) => o.x === s.x && o.y === s.y)) list.push(s);
          entries.set(room, list);
        };
        add(to, spawn);
        // ESCAPE mode: the loop chamber's way back to 0 leads to the escape chamber instead
        if (to === 0 && id === rules.loopFrom && pack.rooms[rules.escape]) add(rules.escape, { x: 0x0B, y: spawn.y, facing: FACE_RIGHT });
      }
    }
  }
  // report
  const problems = [];
  const report = [];
  for (const def of pack.rooms) {
    const got = taken.get(def.id) || new Set();
    const name = def.name;
    if (!entries.has(def.id)) { problems.push(`${name}: never reached`); continue; }
    const missed = [...def.treasures.map((t) => ({ ...t, what: t.code === 0x22 ? 'ring' : 'diamond' })),
                    ...def.keys.map((k) => ({ ...k, what: `key (opens door #${k.door})` }))]
      .filter((o) => !got.has(o.row * 20 + o.col));
    for (const o of missed) problems.push(`${name}: can't reach the ${o.what} at col ${o.col} row ${o.row}`);
    const doors = def.doors.map((d) => `#${d.id}→${d.to}${exited.has(d.id) ? '' : ' (never used)'}`).join(' ');
    report.push(`${name.padEnd(14)} items ${def.treasures.length + def.keys.length - missed.length}/${def.treasures.length + def.keys.length}  doors ${doors}`);
  }
  const loopDoor = pack.rooms[rules.loopFrom]?.doors.find((d) => d.to === 0);
  const finishes = loopDoor ? exited.has(loopDoor.id) : false;
  if (!finishes) problems.push(`the round can't be finished: no usable door from chamber ${rules.loopFrom} back to chamber 0`);
  return { problems, report, passes };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const file = process.argv[2] || new URL('../data/rooms.json', import.meta.url).pathname;
  const { problems, report, passes } = solvePack(JSON.parse(readFileSync(file, 'utf8')));
  console.log(report.join('\n'));
  console.log(`(${passes} passes)`);
  if (problems.length) { console.log('\nPROBLEMS:\n  ' + problems.join('\n  ')); process.exit(1); }
  console.log('\nAll treasures, keys and chambers reachable; the round can be finished.');
}
