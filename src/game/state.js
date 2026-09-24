// Per-game object state and pickup rules, ported from the 7800 ROM.

import { OBJ } from './room.js';

const SCORE = { [OBJ.KEY]: 0x250, [OBJ.DIAMOND]: 0x350, [OBJ.RING]: 0x350 };

// [$853C] Copied from ROM tables at game start and kept across chambers: treasure codes
// (0 = taken), key -> door + 1 (0 = taken), door open flags.
export function newGameState(defs, doorOpenInitial) {
  const treasure = new Array(defs.length * 4).fill(0xFF);   // unused slots are $FF, as in ROM
  const keyDoor = new Array(defs.length * 4).fill(0xFF);
  for (const def of defs) {
    for (const t of def.treasures) treasure[t.slot] = t.code;
    for (const k of def.keys) keyDoor[k.slot] = k.door + 1;
  }
  return { treasure, keyDoor, doorOpen: doorOpenInitial.slice() };
}

// [$B2F1 / $B393] A pickup event from the player (the tile is already cleared). Updates the
// state, opens the key's door (redrawn at once if it's in this chamber) and returns the points:
// key 250, treasure 350, each plus a random 00-99 ($C74F).
export function collect(state, room, ev, rng) {
  const def = room.def;
  if (ev.code === OBJ.KEY) {
    const k = def.keys.find((key) => key.col === ev.col && key.row === ev.row);
    if (k && state.keyDoor[k.slot]) {
      const door = state.keyDoor[k.slot] - 1;
      state.keyDoor[k.slot] = 0;
      if (!state.doorOpen[door]) {
        state.doorOpen[door] = 1;
        room.setDoor(door, 1);
      }
    }
  } else {
    const t = def.treasures.find((tr) => tr.col === ev.col && tr.row === ev.row);
    if (t) state.treasure[t.slot] = 0;
  }
  return bcd(SCORE[ev.code] || 0) + randomBonus(rng);
}

function randomBonus(rng) {
  let lo, hi;
  do lo = rng.next() & 0x0F; while (lo > 9);
  do hi = rng.next() & 0x0F; while (hi > 9);
  return hi * 10 + lo;
}

const bcd = (v) => ((v >> 8) & 0xF) * 100 + ((v >> 4) & 0xF) * 10 + (v & 0xF);
