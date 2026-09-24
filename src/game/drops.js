// Acid drops, ported from the 7800 ROM. Coordinates are 7800 units (see player.js).
//
// Each slot waits at a random spawn point (a stalactite tip from the chamber's table), then
// falls 2 lines per frame until it passes a floor tile's line. Only falling drops kill.

const T_FLOOR = 0x04;
const EMPTY = 0xFF;

export class Drops {
  // def: chamber from rooms.json; room: chamber index, or -1 for the title screen;
  // difficulty: $015F (0..2).
  constructor(def, room, difficulty, rng) {
    this.rng = rng;
    this.difficulty = difficulty;
    this.title = room === -1;
    this.spawns = def.dropSpawns.map(([x, y]) => ({ x, y }));
    this.mask = room === 8 ? 0x3F : 0x1F;
    // [$B087] Difficulty 2 moves one spawn point and duplicates it into its neighbour.
    if (difficulty === 2 && !this.title) {
      const i = def.dropTweak, s = this.spawns[i];
      s.x = (s.x - 2) & 0xFF;
      s.y = (s.y + 2) & 0xFF;
      this.spawns[i - 1] = { ...s };
    }
    // [$B0C4] Highest slot index ($0148): 8 drops after chamber 5 or on difficulty 2, else 6;
    // difficulty 0 is always 6.
    let last = this.title || room > 5 || difficulty === 2 ? 7 : 5;
    if (difficulty === 0 && !this.title) last = 5;
    this.slots = [];
    for (let i = 0; i <= last; i++) {
      this.slots.push({ x: 0, y: 0, timer: 0, spawn: EMPTY });
      this.spawn(this.slots[i]);   // [$B0F5] every slot starts waiting
    }
  }

  spawn(d) {
    const r = this.rng.next() & this.mask;
    d.x = this.spawns[r].x;
    d.y = this.spawns[r].y;
    d.spawn = r;
    d.timer = 0x38 + (this.rng.next() & 7) + (this.difficulty === 0 ? 0x10 : 0);
  }

  // [$C300] Every frame.
  update(room) {
    for (const d of this.slots) {
      if (d.spawn === EMPTY) {
        if ((this.rng.next() & 7) === 0) this.spawn(d);
        continue;
      }
      if (d.timer) { d.timer--; continue; }
      const x = d.x + 1, y = d.y + 2;
      if (this.title) {
        // [$C41D] Title: burst below the logo or on a letter's circle tile.
        const t = room.tileAt(x, y), sub = x & 7;
        if (y > 0xA2 || (t === 0x16 && sub < 4) || (t === 0x14 && sub >= 4)) { d.spawn = EMPTY; continue; }
      } else if (room.tileAt(x, y) === T_FLOOR && room.tileAt(x, y + 3) !== T_FLOOR) {
        d.spawn = EMPTY;
      }
      d.y = (d.y + 2) & 0xFF;
    }
  }

  // [$B7A2] Does a falling drop overlap the player?
  hits(px, py) {
    return this.slots.some((d) => d.spawn !== EMPTY && d.timer === 0 &&
      ((px + 6 - d.x) & 0xFF) < 8 && ((py + 14 - d.y) & 0xFF) < 18);
  }

  // [$C47D] Drops to draw, with the ROM's small vertical jitter. A waiting drop is hidden if
  // an earlier slot is already waiting on the same spawn point.
  *visible() {
    const jitter = this.rng.next();
    for (let i = 0; i < this.slots.length; i++) {
      const d = this.slots[i];
      if (d.spawn === EMPTY) continue;
      if (i > 0 && d.timer &&
          this.slots.slice(0, i).some((o) => o.spawn === d.spawn && o.timer)) continue;
      yield { x: d.x, y: d.y + (this.rng.next() & 1) + ((jitter >> i) & 1) };
    }
  }
}

// BEGINNER mode (not in the ROM): no drops at all.
export const NO_DROPS = { update() {}, hits: () => false, *visible() {} };
